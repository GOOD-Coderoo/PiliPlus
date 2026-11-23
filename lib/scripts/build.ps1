param(
    [string]$Arg = ''
)

try {
    $versionName = $null

    # versionCode 取「git commit 数」与「固定下限」中的较大者。
    #
    # 本仓库历史较短（约 5664 个 commit），而用户已安装的正式版构建号是 6599。
    # 若直接用 commit 数，Android 会判定为降级而拒绝安装。因此设一个下限
    # $MinVersionCode，保证构建出的包能覆盖安装既有版本；将来 commit 数超过
    # 该下限后自动改用 commit 数，无需再改这里。
    $MinVersionCode = 6600
    $autoVersionCode = [int](git rev-list --count HEAD).Trim()
    $versionCode = [Math]::Max($autoVersionCode, $MinVersionCode)

    $commitHash = (git rev-parse HEAD).Trim()

    $updatedContent = foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
        if ($line -match '^\s*version:\s*([\d\.]+)') {
            $versionName = $matches[1]
            if ($Arg -eq 'android') {
                $versionName += '-' + $commitHash.Substring(0, 9)
            }
            "version: $versionName+$versionCode"
        }
        else {
            $line
        }
    }

    if ($null -eq $versionName) {
        throw 'version not found'
    }

    $updatedContent | Set-Content -Path 'pubspec.yaml' -Encoding UTF8

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    $data = @{
        'pili.name' = $versionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = $buildTime
    }

    $data | ConvertTo-Json -Compress | Out-File 'pili_release.json' -Encoding UTF8

    Add-Content -Path $env:GITHUB_ENV -Value "version=$versionName+$versionCode"
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}