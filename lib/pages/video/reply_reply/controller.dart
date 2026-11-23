import 'dart:async';
import 'dart:collection';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo, DetailListReply, Mode;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/models_new/dynamic/dyn_mention/item.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/common/reply/fold/reply_fold_mixin.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:PiliPlus/pages/video/reply_new/view.dart';
import 'package:PiliPlus/pages/video/reply_reply/tree.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class VideoReplyReplyController extends ReplyController
    with
        GetSingleTickerProviderStateMixin,
        ReplyLocateMixin,
        BaseReplyFoldMixin {
  VideoReplyReplyController({
    required this.hasRoot,
    required this.id,
    required this.oid,
    required this.rpid,
    required this.dialog,
    required this.replyType,
  });
  final int? dialog;
  int? id;
  // 视频aid 请求时使用的oid
  @override
  int oid;
  // rpid 请求楼中楼回复
  int rpid;
  @override
  int replyType;

  bool hasRoot = false;
  final firstFloor = Rxn<ReplyInfo>();

  final index = RxnInt();

  final listController = ListController();

  late final horizontalPreview = Pref.horizontalPreview;

  @override
  dynamic get sourceId => replyType == 1 ? IdUtils.av2bv(oid) : oid;

  @override
  ReplySortType get prefSortType => Pref.reply2SortType;

  late final removedReply = HashMap<Int64, ReplyInfo>();

  @override
  void onInit() {
    super.onInit();
    queryData().whenComplete(() {
      if (!isClosed) _maybeAutoThread();
    });
  }

  @override
  List<ReplyInfo>? getDataList(response) {
    return dialog != null ? response.replies : response.root.replies;
  }

  @override
  bool customHandleResponse(bool isRefresh, Success response) {
    final data = response.response;

    if (isRefresh) {
      handleSubjectControl(data.subjectControl);
    }

    // reply2Reply // isDialogue.not
    if (data is DetailListReply) {
      count.value = data.root.count.toInt();
      if (isRefresh && !hasRoot) {
        firstFloor.value ??= data.root;
      }
      if (id != null) {
        setIndexById(Int64(id!), data.root.replies);
        id = null;
      }

      getFoldCard(data.mixedCards);
    }

    handlePagination(
      cursor: data.cursor,
      offset: data.paginationReply.nextOffset,
    );

    return false;
  }

  Iterable<ReplyInfo> getParentChain(int index, ReplyInfo? firstFloor) {
    final data = loadingState.value.data!;
    final item = data[index];
    final replies = [item];
    for (var i = index - 1, parent = item.parent; i >= 0; i--) {
      final item = data[i];
      if (item.id == parent) {
        replies.add(item);
        parent = item.parent;
      }
    }
    if (firstFloor != null && firstFloor.id != replies.last.id) {
      replies.add(firstFloor);
    }
    return replies.reversed;
  }

  bool setIndexById(Int64 id64, [List<ReplyInfo>? replies]) {
    final index = (replies ?? loadingState.value.data!).indexWhere(
      (item) => item.id == id64,
    );
    if (index != -1) {
      this.index.value = index;
      jumpToItem(index);
      return true;
    }
    return false;
  }

  ExtendedNestedScrollController? nestedController;

  @pragma('vm:notify-debugger-on-exception')
  void jumpToItem(int index) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      colorAnimController.forward(from: 0);
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final offset = listController.getOffsetToReveal(index, 0.25);
        if (offset.isFinite) {
          if (nestedController case final nestedController?) {
            nestedController.nestedPositions.last.localJumpTo(offset);
          } else {
            scrollController.jumpTo(offset);
          }
        }
      } catch (_) {}
    });
  }

  @override
  Future<LoadingState> customGetData() => dialog != null
      ? ReplyGrpc.dialogList(
          type: replyType,
          oid: oid,
          root: rpid,
          dialog: dialog!,
          offset: nextOffset,
        )
      : ReplyGrpc.detailList(
          type: replyType,
          oid: oid,
          root: rpid,
          rpid: id ?? 0,
          mode: mode,
          offset: nextOffset,
          removed: removedReply,
        );

  @override
  Future<void> onReload() {
    if (loadingState.value.isSuccess) {
      index.value = null;
    }
    // 重载会换掉整份回复数据，旧树指向的是旧对象，留着会在下次切回线程视图时
    // 显示过期内容。这里一并丢弃；下次进线程视图会按新数据重新建树。
    if (!showReplyTree) {
      replyTree.value = null;
    }
    return super.onReload();
  }

  Future<ReplyInfo?> _sendReply(ReplyInfo replyItem) async {
    final (bool inputDisable, String? hint) = replyHint;
    if (inputDisable) return null;

    final oid = replyItem.oid.toInt();
    final root = replyItem.id.toInt();
    final key = oid + root;

    final replyInfo = await Get.key.currentState!.push(
      PublishRoute<ReplyInfo>(
        pageBuilder: (context, _, _) {
          return ReplyPage(
            hint: hint,
            oid: oid,
            root: root,
            parent: root,
            replyType: replyType,
            replyItem: replyItem,
            items: savedReplies[key],
            onSave: (reply) {
              if (reply.isEmpty) {
                savedReplies.remove(key);
              } else {
                savedReplies[key] = reply.toList();
              }
            },
          );
        },
      ),
    );

    if (replyInfo != null) {
      savedReplies.remove(key);
      count.value += 1;
      if (enableCommAntifraud) {
        onCheckReply(replyInfo, isManual: false);
      }
    }
    return replyInfo;
  }

  @override
  Future<void> onReply(
    covariant ReplyInfo replyItem, {
    int? oid,
    int? replyType,
    covariant int index = -1,
    MentionItem? mentionItem,
  }) async {
    assert(index != -1 || replyItem.root == replyItem.id);

    if (await _sendReply(replyItem) case final replyInfo?) {
      loadingState
        ..value.dataOrNull?.insert(index + 1, replyInfo)
        ..refresh();
    }
  }

  Timer? _replyTimer;
  Future<void>? _inflightReply;
  final progress = RxDouble(0);

  bool get inFetchReply => _replyTimer != null || _inflightReply != null;

  void _cancelReplyTimer() {
    _replyTimer?.cancel();
    _replyTimer = null;
  }

  void nextReplyRound() {
    _replyTimer = null;
    _inflightReply = _fetchNextReply();
  }

  void _createReplyTimer() {
    _replyTimer = Timer(const Duration(milliseconds: 300), nextReplyRound);
  }

  Future<void> _fetchNextReply() async {
    try {
      if (isEnd && foldCard != null) {
        await loadFoldList(toast: false);
      } else {
        await queryData(false);
      }
    } finally {
      _inflightReply = null;
    }
    if (!isClosed) {
      if (isEnd && foldCard == null) {
        buildTree();
      } else {
        _createReplyTimer();
      }
    }
  }

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    await super.queryData(isRefresh);
    if (isEnd) {
      progress.value = 1;
    } else if (count.rawValue > 0) {
      progress.value =
          (loadingState.rawValue.dataOrNull?.length ?? 0) / count.rawValue;
    }
  }

  @override
  Future<void> onLoadMore() {
    if (_replyTimer != null) {
      assert(_inflightReply == null);
      _cancelReplyTimer();
      return _inflightReply = _fetchNextReply();
    } else if (_inflightReply case final future?) {
      return future;
    }
    return super.onLoadMore();
  }

  @override
  Future<void> onRefresh() async {
    // 只有在「正在显示线程视图」时才拦截刷新。
    //
    // 不能判 replyTree != null：线程树一旦建好就一直存在（按钮只是翻转
    // showReplyTree 来切换显示），用户切回普通列表后树并没有销毁。若用
    // replyTree 判空，切回普通列表后下拉刷新和排序依旧被挡住。
    if (showReplyTree) return Future.syncValue(null);
    if (_inflightReply != null) await _inflightReply;
    _cancelReplyTimer();
    return super.onRefresh();
  }

  @override
  void onClose() {
    _cancelReplyTimer();
    super.onClose();
  }

  bool showReplyTree = false;
  final replyTree = Rxn<ReplyTree>();

  /// 「自动线程化展示」开关。默认关闭，保持上游行为不变。
  late final autoReplyThread = Pref.autoReplyThread;

  /// 「自动线程化条数上限」。0 表示不限制。
  late final autoReplyThreadMax = Pref.autoReplyThreadMax;

  /// 自动模式是否已启动，保证只触发一次。
  ///
  /// 只触发一次的原因：用户手动关掉线程视图后，不应因为后续加载数据又被强行
  /// 打开；也不该在每次分页时重复启动拉取循环。
  bool _autoThreadKicked = false;

  /// 「自动线程化展示」：进入楼中楼后自动拉取全部回复，拉完后由
  /// [_fetchNextReply] 末尾的 [buildTree] 自动切换为线程视图。
  ///
  /// 线程视图需要完整回复列表（[isEnd] 为真）才能正确建树，所以这里先自动
  /// 发起拉取循环，而不是直接建树——否则会基于不完整数据建出一棵残缺的树。
  void _maybeAutoThread() {
    if (!autoReplyThread || _autoThreadKicked || isClosed) return;
    if (showReplyTree || replyTree.rawValue != null) return;
    if (inFetchReply) return;

    // 单页就拉完了，直接建树
    if (isEnd && foldCard == null) {
      _autoThreadKicked = true;
      buildTree();
      return;
    }

    // 评论过多时与手动按钮保持同样的克制：只有总量可控才自动拉全量，
    // 避免一进楼中楼就静默消耗大量流量或触发风控。
    // 上限来自设置项「自动线程化条数上限」，0 表示不限制。
    final maxCount = autoReplyThreadMax;
    if (maxCount > 0) {
      final count = this.count.rawValue;
      if (count != -1 && count > maxCount) return;
    }
    _autoThreadKicked = true;
    nextReplyRound();
  }

  void buildTree() {
    // 建树依赖已成功加载的回复列表。非 Success 时 loadingState.data 会 throw，
    // 自动流程可能在任何时刻被触发（含加载失败），故这里必须显式判空。
    final data = loadingState.rawValue.dataOrNull;
    if (data == null || data.isEmpty) return;
    showReplyTree = true;
    _buildTreeFrom(data);
  }

  /// 用给定数据建树，并按 [sortType] 决定一级是否按热度排。
  ///
  /// 先复制一份再按 id 去重：上游原先直接对 loadingState 里的列表
  /// `retainWhere`，会顺手改写数据源，影响切回普通列表后的内容。
  void _buildTreeFrom(List<ReplyInfo> source) {
    final seen = HashSet<Int64>();
    final list = List<ReplyInfo>.of(source)..retainWhere((i) => seen.add(i.id));
    if (list.isEmpty) return;
    replyTree.value = ReplyTree.build(
      data: list,
      seen: seen,
      rootId: firstFloor.rawValue?.id ?? list.first.root,
      removed: removedReply,
      foldDepth: Pref.foldDepth,
      // 线程视图里「按热度」时只重排一级，子级仍按 ctime 保持楼内对话顺序
      hotTopLevel: sortType.value == ReplySortType.hot,
    );
  }

  @override
  void queryBySort() {
    // 线程视图下：只切换排序类型并重建树，不重新拉取数据。
    //
    // 线程视图需要完整回复列表才能建树，重新拉取代价太大；而一级评论的排序
    // 只依赖本地已有的 like / ctime 字段，重建一次树即可，无需联网。
    if (showReplyTree) {
      switch (sortType.value) {
        case ReplySortType.time:
          sortType.value = ReplySortType.hot;
          mode = Mode.MAIN_LIST_HOT;
          break;
        case ReplySortType.hot:
          sortType.value = ReplySortType.time;
          mode = Mode.MAIN_LIST_TIME;
          break;
        case ReplySortType.select:
          return;
      }
      feedBack();
      rebuildTree();
      return;
    }
    super.queryBySort();
  }

  /// 按当前 [sortType] 重建线程树。数据不重拉，仅本地重排。
  ///
  /// 折叠状态会被重置为 [Pref.foldDepth] 的自动折叠，因为重排后节点下标全都变了，
  /// 沿用旧的展开/收起记录只会错位。
  void rebuildTree() {
    if (!showReplyTree) return;
    final data = loadingState.rawValue.dataOrNull;
    if (data == null || data.isEmpty) return;
    _buildTreeFrom(data);
  }

  void toggleCollapseTree(int index) {
    replyTree
      ..rawValue!.toggleCollapse(index)
      ..refresh();
  }

  bool setIndexByTreeNode(int end, ReplyTreeNode? node) {
    if (node != null) {
      final index = replyTree.rawValue!.reverseIdentityIndexOf(node, end);
      if (index != -1) {
        this.index.value = index;
        jumpToItem(index);
        return true;
      }
    }
    return false;
  }

  Future<void> onReplyByTreeNode(int index, ReplyInfo replyItem) async {
    if (await _sendReply(replyItem) case final replyInfo?) {
      replyTree
        ..rawValue!.appendLeaf(replyInfo, index)
        ..refresh();

      final data = loadingState.rawValue.dataOrNull;
      if (data != null) {
        final index = data.reverseIdentityIndexOf(replyItem);
        data.insert(index + 1, replyInfo);
      }
    }
  }

  void onRemoveByTreeNode(int index, ReplyInfo replyItem) {
    replyTree
      ..rawValue!.remove(index)
      ..refresh();

    final data = loadingState.rawValue.dataOrNull;
    if (data != null) {
      final index = data.reverseIdentityIndexOf(replyItem);
      onRemove(index, replyItem, null);
    }
  }
}
