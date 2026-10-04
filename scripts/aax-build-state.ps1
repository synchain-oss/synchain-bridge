<#
.SYNOPSIS  共用片段:判断构建目录里的 AAX bundle 是不是本次构建的产物(供 dot-source,单独运行只定义函数)。
.DESCRIPTION
  scripts/build.ps1(-InstallAax)与 scripts/gates.ps1(gate 5c)共用这一个判据,不在两处各抄一份。

  CMakeLists.txt 的 SYNCHAIN_BRIDGE_AAX 是普通 CACHE 选项:设成 OFF 后一直留在缓存里,直到有人显式传 ON 或清空构建目录。
  OFF 时不生成 SynchainBridgeVST_AAX 目标,而 CMake / MSBuild 都不删已移除目标的旧产物 —— 构建目录里的 .aaxplugin
  是开关打开时留下的旧二进制。旧的 SynchainBridgeVST_AAX.vcxproj 同样会残留,不能拿它当判据;可信的只有缓存值与每次
  generate 都重写的解决方案文件(.sln,新版 VS 生成器可能是 .slnx;两者都以 SynchainBridgeVST_AAX.vcxproj 引用该目标)。
.OUTPUTS   $null = 开关为 ON 且生成的工程里有 AAX 目标;否则返回一句原因(调用方自行补充后续处理的提示)。
#>
function Get-AaxDisabledReason([string]$Dir) {
    $cache = Join-Path $Dir 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cache -PathType Leaf)) { return ('找不到 ' + $cache + '(还没 configure?)') }
    $m = Select-String -LiteralPath $cache -Pattern '^SYNCHAIN_BRIDGE_AAX:[A-Za-z]+=(.*)$' | Select-Object -First 1
    if (-not $m) { return 'CMakeCache.txt 里没有 SYNCHAIN_BRIDGE_AAX(不是本仓库的构建目录?)' }
    $v = $m.Matches[0].Groups[1].Value.Trim()
    # CMake 的真值:ON / YES / TRUE / Y / 非零数(不区分大小写);其余(OFF / NO / FALSE / N / 0 / 空 / *-NOTFOUND)都算关
    if ($v -notmatch '^(?i)(ON|TRUE|YES|Y|[1-9][0-9]*)$') { return ('CMakeCache.txt 里 SYNCHAIN_BRIDGE_AAX=' + $v) }
    $sln = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue | Where-Object { @('.sln', '.slnx') -contains $_.Extension })
    if ($sln.Count -gt 0 -and
        -not @($sln | Where-Object { Select-String -LiteralPath $_.FullName -SimpleMatch 'SynchainBridgeVST_AAX.vcxproj' -Quiet }).Count) {
        return ((($sln | ForEach-Object Name) -join ' / ') + ' 里没有 SynchainBridgeVST_AAX 目标(SYNCHAIN_BRIDGE_AAX=' + $v + ',但 JUCE 没建 AAX)')
    }
    return $null
}
