# scripts/package.ps1 —— 唯一打包真源(06 §3.8 / 08 §5.2;本地发版与 CI 共用同一脚本)
# 六条硬要求逐条落地:
#   1. zip 名从 -Version 算出来(SynchainBridge-VST3-v$Version-win64.zip),绝不写字面量
#   2. 枚举 .vst3 bundle 目录并断言恰好 1 个(Synchain Bridge.vst3),打包时保住 .vst3/Contents/ 层级
#   3. 生成 .sha256 独立资产 + dist/package-summary.md(version/zipFileName/sizeBytes/sha256/releaseDate)
#   4. 生成 INSTALL.txt(安装路径 + SmartScreen 说明 + 精确到 tag 的源码声明)
#   5. 许可证与声明文件入 zip 根目录(LICENSE.txt / THIRD-PARTY-NOTICES.md / LICENSES/OFL-1.1.txt;
#      U2 = 不附 LICENSE-EXCEPTION.md,依赖 GPLv3 系统库例外默认解释)
#   6. 打包后断言:zip 内存在 bundle 的 Contents/ 层级 + 每个合规文件;缺一即 throw
# 绝不在 workflow 里内联 7z 通配 —— 打包逻辑只在此处。
[CmdletBinding()]
param(
    [string]$Version = "",       # 版本号(不带 v 前缀);留空则从 CMakeLists.txt 读唯一真源
    [string]$BuildDir = "build", # 构建目录(内含 .vst3 bundle);相对路径按仓库根解析
    [string]$OutDir  = "dist",   # 输出目录(zip / .sha256 / summary);相对路径按仓库根解析
    [switch]$DryRun              # 只打印计划并校验合规源文件存在,不产出任何产物(gate 用)
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string]$p) {
    if ($p -match '^([a-zA-Z]:[\\/]|\\\\|/)') { return $p }
    return (Join-Path $RepoRoot $p)
}
$BuildDir = Resolve-RepoPath $BuildDir
$OutDir   = Resolve-RepoPath $OutDir

# 1) Version:参数优先;留空则从 CMakeLists.txt(版本唯一真源)读
if (-not $Version) {
    $line = Select-String -Path (Join-Path $RepoRoot 'CMakeLists.txt') -Pattern 'project\s*\(\s*\S+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)'
    if (-not $line) { throw "cannot parse VERSION from CMakeLists.txt" }
    $Version = $line.Matches[0].Groups[1].Value
}

# 2) zip 名从 Version 算出来(硬要求 #1)
$zipFileName = "SynchainBridge-VST3-v$Version-win64.zip"
$zipPath     = Join-Path $OutDir $zipFileName
$shaFileName = "$zipFileName.sha256"
$shaPath     = Join-Path $OutDir $shaFileName
$summaryPath = Join-Path $OutDir 'package-summary.md'

# 3) 合规源文件清单(硬要求 #5)
$licenseSrc = Join-Path $RepoRoot 'LICENSE'                       # GPLv3 全文 → zip 内 LICENSE.txt
$noticesSrc = Join-Path $RepoRoot 'THIRD-PARTY-NOTICES.md'
$oflSrc     = Join-Path $RepoRoot 'LICENSES\OFL-1.1.txt'          # 字体子集嵌进二进制,OFL 全文须随分发

if ($DryRun) {
    Write-Host "[DryRun] RepoRoot : $RepoRoot"
    Write-Host "[DryRun] Version  : $Version"
    Write-Host "[DryRun] BuildDir : $BuildDir"
    Write-Host "[DryRun] OutDir   : $OutDir"
    Write-Host "[DryRun] zip      : $zipPath"
    Write-Host "[DryRun] sha256   : $shaPath"
    foreach ($f in @($licenseSrc, $noticesSrc, $oflSrc)) {
        if (-not (Test-Path -LiteralPath $f)) { throw "compliance source missing: $f" }
        Write-Host "[DryRun] compliance ok : $f"
    }
    Write-Host "[DryRun] OK — 未创建任何产物。"
    exit 0
}

# 4) 枚举 .vst3 bundle 目录并断言恰好 1 个(硬要求 #2)
$bundles = @(Get-ChildItem -Path $BuildDir -Directory -Filter '*.vst3' -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
if ($bundles.Count -ne 1) {
    throw "expected exactly 1 .vst3 bundle under '$BuildDir', found $($bundles.Count)"
}
$bundleDir  = $bundles[0]
$bundleName = Split-Path $bundleDir -Leaf
if ($bundleName -ne 'Synchain Bridge.vst3') {
    throw "unexpected bundle name '$bundleName' (expected 'Synchain Bridge.vst3')"
}
if (-not (Test-Path -LiteralPath (Join-Path $bundleDir 'Contents'))) {
    throw "bundle '$bundleDir' missing Contents/ hierarchy"
}

# 5) INSTALL.txt(硬要求 #4;含精确到 tag 的源码获取声明)
$installTxt = @"
Synchain Bridge VST3 — 安装说明
================================

版本:$Version

安装路径
--------
将压缩包内的 Synchain Bridge.vst3 文件夹整体复制到 VST3 目录:

  %COMMONPROGRAMFILES%\VST3\

(通常为 C:\Program Files\Common Files\VST3\)

SmartScreen 说明(U13:v1 不做代码签名)
-------------------------------------
本插件未签名。首次加载时 Windows SmartScreen 可能提示「已保护你的电脑」,
请点击「更多信息」→「仍要运行」。该提示源于未签名二进制,并非恶意软件。

源码获取
--------
Complete corresponding source for this exact build: https://github.com/synchain-oss/synchain-bridge/tree/v$Version
"@

# 6) 组装 staging 目录(保住 bundle 目录层级)
$staging = Join-Path $OutDir '_staging'
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutDir   | Out-Null
New-Item -ItemType Directory -Force -Path $staging  | Out-Null

Copy-Item -LiteralPath $bundleDir -Destination $staging -Recurse -Force
Copy-Item -LiteralPath $licenseSrc -Destination (Join-Path $staging 'LICENSE.txt') -Force
Copy-Item -LiteralPath $noticesSrc -Destination (Join-Path $staging 'THIRD-PARTY-NOTICES.md') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'LICENSES') | Out-Null
Copy-Item -LiteralPath $oflSrc -Destination (Join-Path $staging 'LICENSES\OFL-1.1.txt') -Force
Set-Content -LiteralPath (Join-Path $staging 'INSTALL.txt') -Value $installTxt -Encoding UTF8

# 7) 压缩:用 .NET ZipFile(非 7z、非内联通配),staging 内容平铺到 zip 根目录,保住目录层级
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# 8) 打包后断言(硬要求 #6):bundle 层级 + 每个合规文件;缺一即 throw
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    if (-not ($names | Where-Object { $_ -like "$bundleName/Contents/*" })) {
        throw "zip assertion failed: no entries under '$bundleName/Contents/'"
    }
    foreach ($r in @('LICENSE.txt', 'THIRD-PARTY-NOTICES.md', 'LICENSES/OFL-1.1.txt', 'INSTALL.txt')) {
        if ($names -notcontains $r) { throw "zip assertion failed: missing '$r'" }
    }
} finally {
    $archive.Dispose()
}
Remove-Item -LiteralPath $staging -Recurse -Force

# 9) .sha256 独立资产 + package-summary.md(硬要求 #3)
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $zipFileName" | Set-Content -LiteralPath $shaPath -Encoding ASCII

$sizeBytes   = (Get-Item -LiteralPath $zipPath).Length
$releaseDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
@"
version: $Version
zipFileName: $zipFileName
sizeBytes: $sizeBytes
sha256: $hash
releaseDate: $releaseDate
"@ | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Packaged: $zipPath ($sizeBytes bytes)"
Write-Host "SHA256:   $hash"
