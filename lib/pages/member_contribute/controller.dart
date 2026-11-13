import 'dart:math';

import 'package:PiliPlus/models_new/space/space/tab2.dart';
import 'package:PiliPlus/pages/member/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MemberContributeCtr extends GetxController
    with GetSingleTickerProviderStateMixin {
  MemberContributeCtr({
    required this.heroTag,
    required this.initialIndex,
  });
  final String? heroTag;
  final int? initialIndex;

  TabController? tabController;
  List<Tab>? tabs;
  late final _ctr = Get.find<MemberController>(tag: heroTag);
  List<SpaceTab2Item>? items;

  @override
  void onInit() {
    super.onInit();
    SpaceTab2 contribute = _ctr.tab2!.firstWhere(
      (item) => item.param == 'contribute',
    );
    final items = contribute.items;
    if (items != null && items.isNotEmpty) {
      // 已有顶级「合集」标签时，投稿内不再出现任何合集相关子标签
      if (_ctr.hasSeasonOrSeries == true) {
        items.removeWhere(
          (e) =>
              e.param == 'ugcSeason' ||
              e.param == 'season_video' ||
              e.param == 'series',
        );
      }
      this.items = items;
      if (items.length > 1) {
        tabs = items.map((item) => Tab(text: item.title)).toList();
        tabController = TabController(
          vsync: this,
          length: items.length,
          initialIndex: (initialIndex ?? 0).clamp(0, items.length - 1),
        );
      }
    }
  }

  @override
  void onClose() {
    tabController?.dispose();
    super.onClose();
  }
}
