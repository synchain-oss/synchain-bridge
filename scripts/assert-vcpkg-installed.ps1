<#
.SYNOPSIS  供应链留痕:断言 vcpkg manifest 模式 configure 后装进 <BuildDir>/vcpkg_installed 的包正是钉死的版本。
.DESCRIPTION
  ci.yml / release.yml 的 windows job 与 scripts/gates.ps1(gate 4b)共用本脚本 —— 本地 / CI 同口径的唯一真源,
  不在三处各抄一份「逐字相同」的 pwsh。读 vcpkg 落盘的 status 文件(debian control 格式,按空行分段)而不是
  `vcpkg list` 的实验性 --x-* 参数。断言:
    ① ixwebsocket 核心段(显式排掉 feature 段)`Status: install ok installed`,Version == vcpkg.json override 的
       version-semver,Port-Version == override 的 port-version(override 缺省视为 0;status 段里 #0 时 vcpkg 不写
       Port-Version 行,缺行同样视为 0);
    ② 传递依赖 mbedtls / zlib 的核心段 Version == 下方 $ExpectedTransitive 表(与 THIRD-PARTY-NOTICES.md 的表逐项对应);
    ③ 闭包完整性:本 triplet 下 install ok installed 的非 feature 段集合不得超出 ixwebsocket + 期望表(多出即红)。
  任一不符即非零退出并打印实际值;全部相符打印一行「installed ... == pinned ...」留痕。
.EXAMPLE   pwsh scripts/assert-vcpkg-installed.ps1 -BuildDir build
.EXAMPLE   pwsh scripts/assert-vcpkg-installed.ps1 -BuildDir build-B11   # 并行 agent:各用各的构建目录
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDir,
    [string]$Triplet = 'x64-windows-static'
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关);相对 BuildDir 相对仓库根解析
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($BuildDir -notmatch '^([a-zA-Z]:[\\/]|\\\\|/)') { $BuildDir = Join-Path $RepoRoot $BuildDir }

# 传递依赖的期望版本:与 THIRD-PARTY-NOTICES.md 表逐项对应。法务文档不做机器解析源,这里手抄一份,
# 升 vcpkg.json 的 builtin-baseline 时两处同步。只比 Version 不比 Port-Version:表里登记的是上游版本,
# port-version 是 vcpkg 侧的打包修订(不改上游源码与许可证),实际值只打印留痕。
$ExpectedTransitive = [ordered]@{ mbedtls = '3.6.5'; zlib = '1.3.2' }

$manifestPath = Join-Path $RepoRoot 'vcpkg.json'
$override = ((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).overrides |
    Where-Object name -eq 'ixwebsocket' | Select-Object -First 1)
$wantVersion = $override.'version-semver'
if (-not $wantVersion) { Write-Host '::error::vcpkg.json has no ixwebsocket override (version-semver) to assert against'; exit 1 }
$wantPortVersion = if ($null -ne $override.'port-version') { [int]$override.'port-version' } else { 0 }

$statusPath = Join-Path $BuildDir 'vcpkg_installed\vcpkg\status'
if (-not (Test-Path -LiteralPath $statusPath)) {
    Write-Host "::error::vcpkg status file not found: $statusPath (manifest install did not run?)"; exit 1
}
# 分隔正则用非捕获组,否则 -split 会把分隔符本身也混进结果
$stanzas = (Get-Content -LiteralPath $statusPath -Raw) -split '(?:\r?\n){2,}'

function Get-CoreStanza([string]$pkg) {
    # feature 段(`Feature: ssl` / `Feature: mbedtls`)与核心段同 Package + Architecture 但没有 Version 行,
    # 显式排掉而不是赌核心段先落盘;Status 必须是 install ok installed —— 半装 / 待删的段同样带 Version 行。
    $pkgRe  = '(?m)^Package: ' + [regex]::Escape($pkg) + '$'
    $archRe = '(?m)^Architecture: ' + [regex]::Escape($Triplet) + '$'
    return ($script:stanzas | Where-Object {
        $_ -match $pkgRe -and $_ -match $archRe -and
        $_ -notmatch '(?m)^Feature:' -and $_ -match '(?m)^Status: install ok installed$'
    } | Select-Object -First 1)
}

$expect = [ordered]@{}
$expect['ixwebsocket'] = @{ Version = $wantVersion; PortVersion = $wantPortVersion; Source = 'vcpkg.json override' }
foreach ($k in $ExpectedTransitive.Keys) {
    $expect[$k] = @{ Version = $ExpectedTransitive[$k]; PortVersion = $null; Source = 'THIRD-PARTY-NOTICES.md' }
}

$failed = $false
$seen = @()
foreach ($pkg in $expect.Keys) {
    $e  = $expect[$pkg]
    $st = Get-CoreStanza $pkg
    if (-not $st -or $st -notmatch '(?m)^Version: (\S+)$') {
        Write-Host "::error::${pkg}:${Triplet} has no 'install ok installed' core stanza in $statusPath"
        $failed = $true; continue
    }
    $gotVersion = $Matches[1]
    $gotPortVersion = if ($st -match '(?m)^Port-Version: (\d+)$') { [int]$Matches[1] } else { 0 }
    $seen += ($pkg + '=' + $gotVersion + '#' + $gotPortVersion)
    if ($gotVersion -ne $e.Version) {
        Write-Host "::error::${pkg}:${Triplet} installed $gotVersion != $($e.Version) pinned by $($e.Source)"
        $failed = $true
    }
    if ($null -ne $e.PortVersion -and $gotPortVersion -ne $e.PortVersion) {
        Write-Host "::error::${pkg}:${Triplet} installed port-version $gotPortVersion != $($e.PortVersion) pinned by $($e.Source)"
        $failed = $true
    }
}

# 闭包完整性:点名式断言只盖「表里有的包版本要对」,反方向没人看 —— 升 baseline / 上游 port 换默认 feature
# (ssl 从 mbedtls 切 openssl、新引入 zstd)时闭包里冒出第四个包,THIRD-PARTY-NOTICES.md 就漏登记一个静态
# 链进产物的包。枚举 status 里 Architecture == triplet 且 install ok installed 的非 feature 段,集合超出
# 期望表即红,并把实际闭包打进日志供人工核 NOTICES。host 依赖(vcpkg-cmake 等)Architecture 不是本 triplet,天然排除。
$archRe = '(?m)^Architecture: ' + [regex]::Escape($Triplet) + '$'
$installedPkgs = @($stanzas | Where-Object {
    $_ -match $archRe -and $_ -notmatch '(?m)^Feature:' -and $_ -match '(?m)^Status: install ok installed$'
} | ForEach-Object { [regex]::Match($_, '(?m)^Package: (\S+)$').Groups[1].Value } | Where-Object { $_ } | Sort-Object -Unique)
Write-Host ("vcpkg closure ($Triplet): " + ($installedPkgs -join ', '))
$unexpected = @($installedPkgs | Where-Object { $expect.Keys -notcontains $_ })
if ($unexpected.Count -gt 0) {
    Write-Host ("::error::unexpected packages in the $Triplet closure: " + ($unexpected -join ', ') +
        "; update THIRD-PARTY-NOTICES.md and `$ExpectedTransitive together")
    $failed = $true
}

if ($failed) { exit 1 }
Write-Host ("vcpkg installed ($Triplet) " + ($seen -join ' / ') +
    " == pinned (ixwebsocket $wantVersion#$wantPortVersion from vcpkg.json; " +
    (($ExpectedTransitive.Keys | ForEach-Object { $_ + ' ' + $ExpectedTransitive[$_] }) -join ' / ') +
    ' from THIRD-PARTY-NOTICES.md)')
exit 0
