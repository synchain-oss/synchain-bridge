# scripts/package-aax.ps1 —— AAX(Avid Pro Tools)Windows x64 打包唯一真源(本机签名流程与 CI 共用同一脚本)
# 与 scripts/package.ps1(VST3)并列、互不改动:那条发版链路已验过,AAX 的新组合不带进去。
# 十二条硬要求逐条落地:
#   1. Version 必须匹配 ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$(与 release.yml 的 tag 校验去掉 v
#      之后同口径),不匹配即 throw;-Version 与 -PrereleaseTag 互斥,显式传入空串同样 throw(不静默回落)
#   2. zip 名由 Mode + Version 算出,绝不写字面量:
#        Signed   → SynchainBridge-AAX-v$Version-win64.zip
#        Unsigned → SynchainBridge-AAX-v$Version-win64-UNSIGNED.zip
#   3. bundle 定位:-BundlePath 显式给出;否则在 -BuildDir 下带 -Force 枚举 *.aaxplugin 目录(JUCE 给 bundle 目录
#      设了 attrib +s,不带 -Force 可能被滤掉),只计**已构建**的(含 Contents\):VS 多配置生成器在 generate 期就为
#      每个配置各建一个只有 desktop.ini 的空壳目录(JUCEUtils.cmake 的 file(GENERATE)),它们不是产物。
#      已构建的必须恰好 1 个,目录名必须是 'Synchain Bridge.aaxplugin'
#   4. 结构断言:Contents\x64\Synchain Bridge.aaxplugin 是文件且 PE 头 Machine = 0x8664(x64);
#      根目录有 desktop.ini 与 Plugin.ico;bundle 内不得出现 *.pdb / *.ilk / *.exp / *.lib
#   5. Mode 断言(在建 staging 之前):Signed 要求 DLL 带 Authenticode 签名 —— SignerCertificate 非空,且 Status
#      不是 NotSigned / HashMismatch / NotSupportedFileFormat;自签名证书的 Status 是 UnknownError / NotTrusted,
#      属预期,故**不用 Valid 判定**。不满足即 throw 'refusing to package an unsigned bundle under a release name'。
#      Unsigned 不查签名
#   6. 写 INSTALL-AAX.txt(不叫 INSTALL.txt:与 VST3 包解压到同一目录时互不覆盖)
#   7. 合规文件入 zip 根目录,与 package.ps1 同一组:LICENSE.txt / THIRD-PARTY-NOTICES.md / LICENSES/OFL-1.1.txt
#   8. 压缩照 package.ps1 用 .NET ZipFile;打包后断言 zip 内有 DLL、desktop.ini、Plugin.ico 与四个合规文件
#   9. 仅 Signed:zip 解到 GetTempPath() 下的随机目录回读,对解出的 DLL 重做第 5 条断言,并要求其 SHA256 与源 DLL
#      相等 ——「发出去的字节还带着签名」。任何一步失败都删掉本次的 zip / .sha256:失败路径上绝不留下发行名 zip
#  10. .sha256 与 package.ps1 逐字同口径:小写 hex + 两个空格 + zip 基名 + LF,UTF-8 无 BOM
#  11. package-summary.md 与 package.ps1 第 9 步逐字同构(按段追加、同名段去重、先写 .tmp 再 Move)——
#      **改一处必须改全部四处**(package.ps1 / package-macos.sh / 本脚本 / package-aax-macos.sh)
#  12. -DryRun 照 package.ps1:只打印计划并校验合规源文件存在,不产出任何产物。
#      本脚本**不调用 wraptool、不碰任何凭据**:打包与 PACE 工具零耦合,所以 CI 能跑
# 绝不在 workflow 里内联打包命令 —— AAX 打包逻辑只在此处(mac 侧见 scripts/package-aax-macos.sh)。
[CmdletBinding()]
param(
    # 无默认值,强制显式;大小写敏感,免得 'signed' / 'SIGNED' 这类拼写在下面的 -ceq 判断里走偏
    [Parameter(Mandatory)][ValidateSet('Unsigned', 'Signed', IgnoreCase = $false)][string]$Mode,
    [string]$Version = "",        # 不带 v;留空且无 -PrereleaseTag 时从 CMakeLists.txt 读唯一真源
    [string]$PrereleaseTag = "",  # 例:ci.fe933da → Version = <CMake VERSION>-ci.fe933da;与 -Version 互斥
    [string]$SourceRef = "",      # INSTALL-AAX.txt 源码链接的 ref;默认 v$Version;用 -PrereleaseTag 时必须显式给
    [string]$BuildDir = "build",  # 与 -BundlePath 二选一;-BundlePath 非空时忽略
    [string]$BundlePath = "",     # 显式 .aaxplugin 目录(签名流程用:签名产物不在构建目录里)
    [string]$OutDir = "dist/aax", # 相对路径按仓库根解析;dist/ 已被 .gitignore 与 .gitleaks.toml 覆盖
    [switch]$DryRun               # 只打印计划并校验合规源文件存在,不产出任何产物
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

# 1) Version(硬要求 #1)。「没传」与「传了空串」必须区分:后者是调用方没算出版本(例如 CI 的 env 为空),
#    静默回落到 CMakeLists.txt 会产出版本号对不上的资产(与 package-macos.sh 第 1 步同一纪律)。
$versionGiven = $PSBoundParameters.ContainsKey('Version')
$preGiven     = $PSBoundParameters.ContainsKey('PrereleaseTag')
$refGiven     = $PSBoundParameters.ContainsKey('SourceRef')
if ($versionGiven -and $preGiven) { throw "-Version and -PrereleaseTag are mutually exclusive" }
if ($versionGiven -and -not $Version) {
    throw "-Version was passed as an empty string: the caller failed to compute a version (refusing to fall back to CMakeLists.txt)"
}
if ($preGiven -and -not $PrereleaseTag) { throw "-PrereleaseTag was passed as an empty string" }
if ($refGiven -and -not $SourceRef) { throw "-SourceRef was passed as an empty string" }
if (-not $Version) {
    # 行首锚 + 只认未注释的 project():注释里留一行旧 `# project(... VERSION x.y.z)` 不会被先命中
    # (与 package-macos.sh / gates.ps1 版本 gate 剔注释同口径)
    $line = Select-String -Path (Join-Path $RepoRoot 'CMakeLists.txt') -Pattern '^\s*project\s*\(\s*\S+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)' |
        Select-Object -First 1
    if (-not $line) { throw "cannot parse VERSION from CMakeLists.txt" }
    $Version = $line.Matches[0].Groups[1].Value
    if ($PrereleaseTag) {
        if ($PrereleaseTag -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.-]*$') { throw "invalid -PrereleaseTag '$PrereleaseTag'" }
        $Version = "$Version-$PrereleaseTag"
    }
}
# 容忍调用方直接把 tag 传进来(与 package-macos.sh 同口径),免得 zip 名与源码 URL 出现 vv1.2.3
$Version = $Version -replace '^v', ''
if ($Version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$') {
    throw "invalid version '$Version' (expected X.Y.Z or X.Y.Z-prerelease, no 'v' prefix)"
}

# SourceRef:正式版默认指向 tag v$Version;-PrereleaseTag 的构建没有对应 tag,默认值会是一条死链 —— 必须显式给 commit
if ($preGiven -and -not $refGiven) {
    throw "-PrereleaseTag builds have no matching tag: pass -SourceRef <40-hex commit> so INSTALL-AAX.txt points at real source"
}
if (-not $SourceRef) { $SourceRef = "v$Version" }
if ($SourceRef -cnotmatch '^(v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?|[0-9a-f]{40})$') {
    throw "invalid -SourceRef '$SourceRef' (expected a tag vX.Y.Z[-pre] or a 40-hex commit)"
}

# 2) zip 名由 Mode + Version 算出来(硬要求 #2)
$suffix      = if ($Mode -ceq 'Unsigned') { '-UNSIGNED' } else { '' }
$zipFileName = "SynchainBridge-AAX-v$Version-win64$suffix.zip"
$zipPath     = Join-Path $OutDir $zipFileName
$shaFileName = "$zipFileName.sha256"
$shaPath     = Join-Path $OutDir $shaFileName
$summaryPath = Join-Path $OutDir 'package-summary.md'

$bundleWant = 'Synchain Bridge.aaxplugin'
$dllRel     = 'Contents\x64\Synchain Bridge.aaxplugin'   # 主体 DLL:一个文件,后缀也是 .aaxplugin

# 3) 合规源文件清单(硬要求 #7)
$licenseSrc = Join-Path $RepoRoot 'LICENSE'                       # GPLv3 全文 → zip 内 LICENSE.txt
$noticesSrc = Join-Path $RepoRoot 'THIRD-PARTY-NOTICES.md'
$oflSrc     = Join-Path $RepoRoot 'LICENSES\OFL-1.1.txt'          # 字体子集嵌进二进制,OFL 全文须随分发

if ($DryRun) {
    Write-Host "[DryRun] RepoRoot  : $RepoRoot"
    Write-Host "[DryRun] Mode      : $Mode"
    Write-Host "[DryRun] Version   : $Version"
    Write-Host "[DryRun] SourceRef : $SourceRef"
    if ($BundlePath) { Write-Host "[DryRun] Bundle    : $(Resolve-RepoPath $BundlePath)" }
    else { Write-Host "[DryRun] BuildDir  : $BuildDir" }
    Write-Host "[DryRun] OutDir    : $OutDir"
    Write-Host "[DryRun] zip       : $zipPath"
    Write-Host "[DryRun] sha256    : $shaPath"
    foreach ($f in @($licenseSrc, $noticesSrc, $oflSrc)) {
        if (-not (Test-Path -LiteralPath $f)) { throw "compliance source missing: $f" }
        Write-Host "[DryRun] compliance ok : $f"
    }
    Write-Host "[DryRun] OK — 未创建任何产物。"
    exit 0
}

foreach ($f in @($licenseSrc, $noticesSrc, $oflSrc)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "compliance source missing: $f" }
}

# PE 头 Machine 字段:MZ → 偏移 0x3C 处的 e_lfanew → 'PE\0\0' → 紧随其后的 UInt16
function Assert-PeAmd64([string]$path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        if ($fs.Length -lt 0x40) { throw "'$path' is too small to be a PE image" }
        if ($br.ReadUInt16() -ne 0x5A4D) { throw "'$path' is not a PE image (no MZ header)" }
        $fs.Position = 0x3C
        $peOffset = [int64]$br.ReadUInt32()
        if ($peOffset + 6 -gt $fs.Length) { throw "'$path' has a truncated PE header" }
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { throw "'$path' is not a PE image (no 'PE\0\0' signature)" }
        $machine = $br.ReadUInt16()
        if ($machine -ne 0x8664) { throw ("'{0}' PE Machine = 0x{1:X4}, expected 0x8664 (x64)" -f $path, $machine) }
    } finally {
        $fs.Dispose()
    }
}

# 硬要求 #5:有签名者证书 + 签名本身完好即算「已签」;Status 的信任链结论不作判据(自签名证书恒不受信任)
function Assert-AuthenticodeSigned([string]$path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    $bad = @('NotSigned', 'HashMismatch', 'NotSupportedFileFormat')
    if ($null -eq $sig.SignerCertificate -or $bad -contains [string]$sig.Status) {
        throw "refusing to package an unsigned bundle under a release name: '$path' has no intact Authenticode signature (Status=$($sig.Status))"
    }
    return $sig
}

# 4) bundle 定位(硬要求 #3)
if ($BundlePath) {
    $BundlePath = Resolve-RepoPath $BundlePath
    if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) { throw "-BundlePath '$BundlePath' is not a directory" }
    $bundleDir = (Get-Item -LiteralPath $BundlePath -Force).FullName
} else {
    if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) { throw "build dir not found: $BuildDir" }
    $all = @(Get-ChildItem -LiteralPath $BuildDir -Recurse -Directory -Filter '*.aaxplugin' -Force -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)
    $built = @($all | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'Contents') -PathType Container })
    $shells = @($all | Where-Object { $built -notcontains $_ })
    foreach ($s in $shells) { Write-Host "skip (not built, no Contents\): $s" }
    if ($built.Count -ne 1) {
        throw ("expected exactly 1 built .aaxplugin bundle under '$BuildDir', found $($built.Count)" +
            $(if ($built.Count) { ": " + ($built -join '; ') + " (pass -BundlePath to pick one)" } else { '' }))
    }
    $bundleDir = $built[0]
}
$bundleName = (Get-Item -LiteralPath $bundleDir -Force).Name
if ($bundleName -cne $bundleWant) {
    throw "unexpected bundle name '$bundleName' (expected '$bundleWant')"
}

# 5) 结构断言(硬要求 #4)
$dllPath = Join-Path $bundleDir $dllRel
if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "bundle '$bundleDir' missing $dllRel (file)" }
Assert-PeAmd64 $dllPath
foreach ($f in 'desktop.ini', 'Plugin.ico') {
    if (-not (Test-Path -LiteralPath (Join-Path $bundleDir $f) -PathType Leaf)) { throw "bundle '$bundleDir' missing $f" }
}
$junk = @(Get-ChildItem -LiteralPath $bundleDir -Recurse -File -Force |
    Where-Object { @('.pdb', '.ilk', '.exp', '.lib') -contains $_.Extension.ToLowerInvariant() } |
    Select-Object -ExpandProperty FullName)
if ($junk.Count) { throw "bundle contains build intermediates that must not ship: $($junk -join '; ')" }

# 6) Mode 断言(硬要求 #5)—— 必须在建 staging 之前:拒收时不留下任何产物
if ($Mode -ceq 'Signed') {
    $sig = Assert-AuthenticodeSigned $dllPath
    Write-Host "Authenticode: Status=$($sig.Status) Signer=$($sig.SignerCertificate.Subject) Thumbprint=$($sig.SignerCertificate.Thumbprint)"
}

# 7) INSTALL-AAX.txt(硬要求 #6;中文,只有源码那一行是英文,与 package.ps1 的 INSTALL.txt 同口径)
if ($Mode -ceq 'Unsigned') {
    $modeBlock = @"
⚠ 未签名构建(UNSIGNED)—— 不是发行版
------------------------------------
本包里的 AAX 没有经过 PACE 签名,零售版 Pro Tools 不会加载。它只用于:
  ① 维护者用 scripts/sign-aax.ps1 签名后再打发行包;
  ② AAX 开发者在 Avid 的 Pro Tools Developer 版本里测试。
正式版请到 GitHub Releases 下载不带 -UNSIGNED 后缀的 zip。
"@
} else {
    $modeBlock = @"
签名说明(AAX 是本项目唯一签名的格式)
------------------------------------
零售版 Pro Tools 只加载经 PACE 签名的 AAX 插件;本包由维护者在本机用 PACE wraptool 签名,
构建流水线不持有任何签名凭据。Windows 侧的代码签名证书是自签名的:文件「属性 → 数字签名」里
显示签名者不受信任属预期,不影响 Pro Tools 加载。
签名后改动 bundle 内任何文件都会让签名失效 —— 请整体复制,不要增删或编辑其中的文件。
VST3 / AU 版本仍不签名(U13)。
"@
}

$installTxt = @"
Synchain Bridge AAX(Avid Pro Tools)—— 安装说明(Windows x64)
=============================================================

版本:$Version

$modeBlock

系统要求
--------
Windows 10/11 x64、Pro Tools(64 位、AAX Native);Microsoft Edge WebView2 Runtime。

安装路径(需要管理员权限)
------------------------
Pro Tools 只扫描下面这一个目录(64 位的 Common Files 下),没有用户级目录:

  %CommonProgramW6432%\Avid\Audio\Plug-Ins\

(通常为 C:\Program Files\Common Files\Avid\Audio\Plug-Ins\)

先退出 Pro Tools,再以管理员身份打开 PowerShell 执行(<解压路径> 换成本压缩包解压出来的目录;
`$env:CommonProgramW6432 恒指向 64 位的 Common Files,系统盘不是 C: 也适用):

  Remove-Item "`$env:CommonProgramW6432\Avid\Audio\Plug-Ins\$bundleWant" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "<解压路径>\$bundleWant" "`$env:CommonProgramW6432\Avid\Audio\Plug-Ins\" -Recurse -Force

必须先删旧版:按上面的写法(目标是父目录 Plug-Ins\),已存在同名 bundle 时 Copy-Item 是合并,旧版残留的文件
会混进来;若把目标写成 bundle 自身的路径,还会嵌套成 ...\$bundleWant\$bundleWant。
重启 Pro Tools,在插入点的插件菜单里按名称 Synchain Bridge 查找。

商标
----
Avid、Pro Tools 与 AAX 是 Avid Technology, Inc. 的商标或注册商标;PACE 与 iLok 是 PACE Anti-Piracy, Inc.
的商标。Synchain Bridge 是独立项目,与 Avid 无隶属、赞助或背书关系。

许可证
------
AAX 构建额外包含 Avid AAX SDK 2.8.0(随 JUCE 8.0.8),按其 GPLv3 选项使用,故 AAX 二进制整体按
GPL 第 3 版分发(LICENSE.txt),详见 THIRD-PARTY-NOTICES.md。

源码获取
--------
Complete corresponding source for this exact build: https://github.com/synchain-oss/synchain-bridge/tree/$SourceRef
"@

# 8) staging + 压缩 + 断言 + .sha256 + summary。从这里起任何失败都删掉本次的 zip / .sha256(硬要求 #9):
#    Signed 模式下失败路径上绝不能留下发行名 zip;Unsigned 同样不留半成品。与 mac 侧的 PACKAGED_OK + EXIT trap
#    同口径:$packagedOk 只在 summary 落盘之后才置位,写 .sha256 / summary 时失败同样清理。
$staging = Join-Path $OutDir '_staging'
$summaryTmp = $summaryPath + '.tmp'
$packagedOk = $false
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
foreach ($p in @($zipPath, $shaPath)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
try {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    # -Force:desktop.ini 带 System 属性,不带 -Force 的递归拷贝会把它当隐藏/系统文件跳过
    Copy-Item -LiteralPath $bundleDir -Destination (Join-Path $staging $bundleWant) -Recurse -Force
    Copy-Item -LiteralPath $licenseSrc -Destination (Join-Path $staging 'LICENSE.txt') -Force
    Copy-Item -LiteralPath $noticesSrc -Destination (Join-Path $staging 'THIRD-PARTY-NOTICES.md') -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $staging 'LICENSES') | Out-Null
    Copy-Item -LiteralPath $oflSrc -Destination (Join-Path $staging 'LICENSES\OFL-1.1.txt') -Force
    # 统一 CRLF + UTF-8 无 BOM:脚本本身按 .gitattributes 是 LF 检出,here-string 里的换行随之是 LF;
    # Set-Content 只在末尾补一个 CRLF,会写出 LF / CRLF 混排的文件。给 Windows 用户看的文本一律 CRLF。
    [System.IO.File]::WriteAllText((Join-Path $staging 'INSTALL-AAX.txt'),
        (($installTxt -replace "`r?`n", "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))

    # 压缩:.NET ZipFile(非 7z、非内联通配),staging 内容平铺到 zip 根目录,保住目录层级(硬要求 #8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName })
        $required = @(
            "$bundleWant/Contents/x64/$bundleWant",
            "$bundleWant/desktop.ini",
            "$bundleWant/Plugin.ico",
            'LICENSE.txt', 'THIRD-PARTY-NOTICES.md', 'LICENSES/OFL-1.1.txt', 'INSTALL-AAX.txt'
        )
        foreach ($r in $required) {
            if ($names -cnotcontains $r) { throw "zip assertion failed: missing '$r'" }
        }
    } finally {
        $archive.Dispose()
    }

    # 9) 仅 Signed:回读验证(硬要求 #9)
    if ($Mode -ceq 'Signed') {
        $readback = Join-Path ([System.IO.Path]::GetTempPath()) ('synchain-aax-readback-' + [guid]::NewGuid().ToString('N'))
        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $readback)
            $rbDll = Join-Path (Join-Path $readback $bundleWant) $dllRel
            if (-not (Test-Path -LiteralPath $rbDll -PathType Leaf)) { throw "readback: '$rbDll' not found in the extracted zip" }
            Assert-AuthenticodeSigned $rbDll | Out-Null
            $srcHash = (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash
            $rbHash  = (Get-FileHash -LiteralPath $rbDll -Algorithm SHA256).Hash
            if ($srcHash -ne $rbHash) { throw "readback: DLL in zip hashes to $rbHash, source bundle DLL is $srcHash" }
            Write-Host "Readback OK: zipped DLL is byte-identical to the signed source ($srcHash)"
        } finally {
            if (Test-Path -LiteralPath $readback) { Remove-Item -LiteralPath $readback -Recurse -Force }
        }
    }

    # 10) .sha256 独立资产(硬要求 #10)—— 与 package.ps1 第 9 步逐字同口径
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    # LF + 无 BOM:.sha256 是跨 job 被 sha256sum -c 消费、也是发给用户在 mac/Linux 上直接校验的资产,CRLF 会让
    # 结尾的 \r 被当成文件名的一部分而校验必失败;与下面 summary 的落盘同口径。
    [System.IO.File]::WriteAllText($shaPath, "$hash  $zipFileName`n", [System.Text.UTF8Encoding]::new($false))

    $sizeBytes   = (Get-Item -LiteralPath $zipPath).Length
    $releaseDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    # 11) package-summary.md(硬要求 #11)—— 与 package.ps1 第 9 步逐字同构,改一处必须改全部四处。
    # summary 以空行分段追加 + 同名段去重,与 package-macos.sh 第 10 步的 awk 语义与布局一致(issue #23):
    # 同一个 OutDir 下可能已有别的平台或本脚本上一次运行写的段落,整文件覆盖会把它们静默抹掉。
    #   - 切段一律按记录首行 `version:` 切,不按空行切:旧文件的段间可能没有空行,按空行切会把整个文件当一段;
    #   - 只删 `zipFileName:` 整行逐字相等(-ceq,大小写敏感)的旧段,不用子串包含 —— 0.0.0-ci 不能误删 0.0.0-ci2;
    #   - 首条记录之前的内容(将来若加表头)原样透传;空行只是分隔符,重排时统一重新生成;
    #   - 布局:每个保留的旧段后补一个空行,末尾追加本次的新段 —— 段间恰一个空行、文件末尾恰一个换行,
    #     两边字节布局相同。
    #   - 行尾一律 LF、UTF-8 无 BOM:Set-Content 在 Windows 写的是 CRLF,mac 侧 awk 的 `$0 == z` 是逐字相等,
    #     读到带 CR 尾的行会失配、同名段删不掉;两边共用一个 OutDir 时双向都得成立,故这里写 LF、读旧文件时
    #     把 CRLF 归一成 LF(mac 侧 awk 同样先 sub(/\r$/, "") 再比)。
    $zipLine = "zipFileName: $zipFileName"
    $kept    = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $summaryPath) {
        $rec = New-Object System.Collections.Generic.List[string]
        $started = $false
        $drop    = $false
        $oldText = [string](Get-Content -LiteralPath $summaryPath -Raw)
        foreach ($ln in @(($oldText -replace "`r`n", "`n") -split "`n")) {
            if ($ln.Trim().Length -eq 0) { continue }
            if ($ln -cmatch '^version:\s') {
                if ($started -and -not $drop) { $kept.AddRange($rec); $kept.Add('') }
                $rec.Clear(); $drop = $false; $started = $true
            }
            if (-not $started) { $kept.Add($ln); continue }
            $rec.Add($ln)
            if ($ln -ceq $zipLine) { $drop = $true }
        }
        if ($started -and -not $drop) { $kept.AddRange($rec); $kept.Add('') }
    }
    $kept.AddRange([string[]]@(
        "version: $Version",
        $zipLine,
        "sizeBytes: $sizeBytes",
        "sha256: $hash",
        "releaseDate: $releaseDate"
    ))
    # 先写同目录 .tmp 再 Move-Item -Force 覆盖,与 mac 侧 tmp + mv 同口径:上面已把旧 summary 读进内存,
    # 直接写原路径是「先截断再写」,中途被打断会把别的平台 / 历史版本的段落一起丢掉。
    # 不用 Set-Content:它在 Windows 写 CRLF,且 Windows PowerShell 5.1 的 -Encoding UTF8 还会带 BOM。
    [System.IO.File]::WriteAllText($summaryTmp, (($kept -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $summaryTmp -Destination $summaryPath -Force

    $packagedOk = $true
} finally {
    if (-not $packagedOk) {
        foreach ($p in @($zipPath, $shaPath, $summaryTmp)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
    }
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}

Write-Host "Packaged: $zipPath ($sizeBytes bytes, Mode=$Mode)"
Write-Host "SHA256:   $hash"
