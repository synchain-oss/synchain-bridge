<#
.SYNOPSIS  AAX(Windows x64)本机签名:CI 产出的 -UNSIGNED.zip → PACE wraptool 签名 → package-aax.ps1 -Mode Signed 出发行包。
.DESCRIPTION
  只由维护者在本机手工执行;CI 不调用、流水线不持有任何签名凭据(CLAUDE.md §0 铁律 1)。
  AAX 是本项目唯一签名的格式(零售版 Pro Tools 只加载 PACE 签名件),VST3 / AU 仍按 U13 不签名。

  流程(任一步失败即 exit 1):
    预检 0 参数:Windows;-WcGuid 是 GUID;-ExtraWraptoolArgs 不含口令、不覆盖本脚本管理的 flag
    预检 1 完整性:输入 zip 同目录的 .sha256 逐字节符合「64 位小写 hex + 两个空格 + zip 名 + LF」,且与实际哈希相等。
           只防损坏 / 下载不完整 —— .sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256,防不了替换
    预检 2 从文件名解析版本:SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip
    预检 3 检出对应该版本:-ci.<sha> 版本要求 HEAD 以该 sha 开头(SourceRef = 完整 HEAD);其余版本要求 HEAD 上有
           tag v<版本>(SourceRef = v<版本>);LICENSE / THIRD-PARTY-NOTICES.md / LICENSES / scripts 无未提交改动
    预检 3b 来源(-SourceRunId):该 run 属于本仓库(非 fork)、是 ci.yml / release.yml、结论 success、事件为 push / workflow_dispatch
           (pull_request 构建的是合并提交,不认)、head_sha = HEAD;
           再用 gh run download 取回它的 aax-unsigned-* artifact,其中同名 zip 必须与输入 zip 字节相同。
           这是「哪些字节会被盖上签名」的信任根;不给 -SourceRunId 只记 WARN(本地自建件没有 run 可核对)
    预检 4 KeyFile 存在,且解析后的完整路径不在仓库目录下(路径前缀 + git 公共目录两道判定,覆盖本仓库的其他 worktree)
    预检 5 wraptool 可执行,`wraptool help sign` 列出所需 flag(TO-VALIDATE)
    预检 6 iLok 只提醒不硬检(wraptool 自己会报错)
    预检 7 解压到全新临时目录:bundle 存在、DLL 为 NotSigned、`wraptool verify` 必须失败(已签过的件重签会报错)
    签名   pfx 口令只经 Read-Host -AsSecureString 读入;BSTR → 明文只在调用瞬间存在,finally 里 ZeroFreeBSTR;
           回显的命令里口令 / PACE 账号 / wcguid 一律打码为 ****
    后检   wraptool verify 通过;Authenticode 签名者指纹 = pfx 指纹;默认要求带时间戳(-AllowNoTimestamp 显式放行);
           调 package-aax.ps1 -Mode Signed 打包;再把产出的 zip 解压回读,复验 wraptool verify 与指纹;
           最后只**打印** gh release upload 命令,不自动执行
  成功即删除临时工作目录;失败则保留并打印路径(里面只有 bundle,没有秘密)。
  打包之后的任何一步(回读复验等)失败,都删掉本次产出的发行名 zip 与 .sha256:失败路径上 OutDir 里不留可上传的发行名 zip
  (package-summary.md 里本次追加的段落会留下,只是记录,不是可上传的文件)。

  -DryRun:跑全部预检(第 7 步的解压也在临时目录里做,结束即删)并汇总 PASS / WARN / FAIL / SKIP,打印签名计划
  (口令占位打码)与 package-aax.ps1 -DryRun 的输出;不读口令、不载入 pfx、不调用 wraptool sign、不产出任何文件。
  KeyFile 不存在在 DryRun 下只记 WARN;KeyFile 位于仓库内则任何模式都 FAIL。

  TO-VALIDATE:所有 wraptool 子命令 / flag / 默认安装路径都来自公开资料,Eden 版本不同可能有差异;所有者拿到
  PACE 工具后逐条核对(V1 子命令与 flag、V2 账号口令、V3 时间戳、V8 pfx 加密算法、V11 上传到 draft、
  V12 默认安装路径),核对完删掉对应标记。

  禁止 Start-Transcript:本脚本不开 transcript,也不要在开着 transcript 的会话里运行(wraptool 的输出与本脚本的
  日志都不该进任何落盘记录)。口令交互读取,不进本脚本的参数、日志与 shell 历史;但 wraptool 只收命令行参数(TO-VALIDATE
  是否有 stdin / 环境变量通道),签名期间口令会以 --keypassword <明文>(加 -PromptAccountPassword 时还有 --password)出现在
  wraptool 的进程命令行里:本机进程列表短暂可见,开着进程命令行审计(Security 4688 含命令行 / Sysmon / EDR)时会被记录。
  只在可信的单用户机器上执行,签名期间不要让他人登录本机。wraptool --verbose 是否回显收到的参数未知(TO-VALIDATE V1):
  它的输出逐行把口令(含它在命令行里的转义形态)/ PACE 账号 / wcguid 字面替换成 **** 后再显示。

  原生命令传参:$PSNativeCommandArgumentPassing 从 7.3 起才是正式特性(故 #Requires 7.3);Invoke-Wraptool 在函数作用域内
  显式设为 Standard,含双引号 / 空格的口令按 Windows 规则转义后原样交给 wraptool(7.2 的 Legacy 模式会把含 " 的口令
  拆错、把后面的参数吞掉)。git / gh 的输出按 UTF-8 解码(中文 Windows 默认 CP936,按它解码会把 JSON 拼坏)。
.EXAMPLE
  gh run download <run ID> -R synchain-oss/synchain-bridge -n aax-unsigned-win64 -D <下载目录>
  pwsh scripts/sign-aax.ps1 -UnsignedZip <下载目录>\SynchainBridge-AAX-v1.6.0-win64-UNSIGNED.zip -SourceRunId <run ID> `
       -Account <PACE 账号> -WcGuid <wrap 配置 GUID> -KeyFile $env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx -DryRun
#>
#Requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UnsignedZip,   # SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip,同目录须有 .sha256
    [Parameter(Mandatory)][string]$Account,       # PACE 账号(日志里打码)
    [Parameter(Mandatory)][string]$WcGuid,        # PACE wrap 配置 GUID(日志里打码)
    [Parameter(Mandatory)][string]$KeyFile,       # 代码签名证书 .pfx,必须在仓库外
    [string]$OutDir = 'dist/aax-signed',          # 相对路径按仓库根解析;dist/ 已被 .gitignore 覆盖
    [string]$WraptoolPath = '',                   # 默认先找 PATH,再找 Eden 默认安装路径(TO-VALIDATE)
    [string[]]$ExtraWraptoolArgs = @(),           # 原样透传给 wraptool sign,例如 '--dsig1-compat','off'(TO-VALIDATE)
    [string]$SourceRunId = '',                    # 产出该 zip 的 CI / release run 的 ID:给了就核对来源(预检 3b),不给只记 WARN
    [switch]$PromptAccountPassword,               # 交互读入 PACE 账号口令并传 --password(V2:是否需要,TO-VALIDATE)
    [switch]$AllowNoTimestamp,                    # 放行不带时间戳的 Authenticode 签名(V3)
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$BundleName = 'Synchain Bridge.aaxplugin'
$DllRel     = 'Contents\x64\Synchain Bridge.aaxplugin'   # 主体 DLL:一个文件,后缀也是 .aaxplugin
$UploadRepo = 'synchain-oss/synchain-bridge'

# wraptool 默认安装路径(TO-VALIDATE V12:Eden 版本号目录 Versions\5 与 Fusion 子目录以实际安装为准)。
# 走环境变量而不是写字面盘符:系统盘不是 C: 时同样成立。
$WraptoolDefault = if (${env:ProgramFiles(x86)}) {
    Join-Path ${env:ProgramFiles(x86)} 'PACEAntiPiracy\Eden\Fusion\Versions\5\wraptool.exe'   # TO-VALIDATE(V12)
} else { '' }

# wraptool sign 必须支持的 flag(TO-VALIDATE V1:来自公开资料;核对 `wraptool help sign` 的真实输出后再删标记)
$RequiredSignFlags = @('--account', '--wcguid', '--keyfile', '--keypassword', '--in', '--out')   # TO-VALIDATE(V1)
# 本脚本自己管理的 flag:-ExtraWraptoolArgs 不得重复给出(否则同一 flag 出现两次,以哪个为准取决于 wraptool 实现)
$ManagedFlagRe = '^--(account|wcguid|keyfile|keypassword|password|in|out)(=|$)'

function Resolve-RepoPath([string]$p) {
    if ($p -match '^([a-zA-Z]:[\\/]|\\\\|/)') { return $p }
    return (Join-Path $RepoRoot $p)
}

# 用户给的路径(-UnsignedZip / -KeyFile / -WraptoolPath)按当前目录解析成完整路径,解析结果就是之后实际使用的路径
function Resolve-UserPath([string]$p) {
    return [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p))
}

# ---- 预检结果登记 ----
# 非 DryRun:第一项 FAIL 即抛出(外层 catch → exit 1);DryRun:只登记,跑完全部预检后汇总。
# 约定:每项预检在自己的 try 里遇到问题就 throw,只在 catch 里登记 FAIL —— 不在 try 里直接登记 FAIL,免得重复登记。
$Checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Id, [string]$Result, [string]$Detail) {
    $Checks.Add([pscustomobject]@{ Id = $Id; Result = $Result; Detail = $Detail })
    $color = switch ($Result) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'SKIP' { 'DarkGray' } default { 'Cyan' } }
    Write-Host ("[{0}] {1} —— {2}" -f $Result, $Id, $Detail) -ForegroundColor $color
    if ($Result -eq 'FAIL' -and -not $DryRun) { throw "预检 $Id 未通过:$Detail" }
}

# git / gh 的输出是 UTF-8,PowerShell 却按 [Console]::OutputEncoding 解码原生命令的输出 —— 中文 Windows 默认 CP936,
# 非 ASCII 字节会被错拼(字符串末尾落单的前导字节能把 JSON 的结束引号吞掉,ConvertFrom-Json 随之失败)。
# 调用期间临时切到 UTF-8,finally 里恢复;没有控制台的宿主里设置可能抛异常,此时保持原样(gh 侧另有 --jq 只取 ASCII 字段兜底)。
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Enter-Utf8Console {
    try {
        $prev = [Console]::OutputEncoding
        if ($prev.CodePage -ne 65001) { [Console]::OutputEncoding = $script:Utf8NoBom }
        return $prev
    } catch { return $null }
}
function Exit-Utf8Console($Prev) {
    if ($null -ne $Prev) { try { [Console]::OutputEncoding = $Prev } catch { } }
}

# 外部命令:局部把 ErrorActionPreference 降为 Continue,stderr 不当终止错误,只看退出码
function Invoke-Git([string[]]$GitArgs, [string]$Dir = $RepoRoot) {
    $ErrorActionPreference = 'Continue'
    $OutputEncoding = $script:Utf8NoBom   # 函数作用域内生效,返回即恢复
    $prevEnc = Enter-Utf8Console
    try {
        $out = & git -C $Dir @GitArgs 2>$null
        $code = $LASTEXITCODE
    } finally { Exit-Utf8Console $prevEnc }
    return [pscustomobject]@{ ExitCode = $code; Lines = @($out | ForEach-Object { "$_" }) }
}

# 回显时含空白的参数加引号;-Display 是打过码的参数表,真实参数(含口令)绝不经这里输出
function Format-CommandLine([string[]]$Display) {
    return (($Display | ForEach-Object { if ($_ -match '\s' -or $_ -eq '') { '"' + $_ + '"' } else { $_ } }) -join ' ')
}

# 打码用的替换表:每个秘密值本身;它在 Windows 命令行里的转义形态(Standard 传参下 " → \",紧挨引号的反斜杠加倍 ——
# wraptool 若回显原始命令行而不是解析后的 argv,看到的是这种形态);再加按空白切开后长度 ≥ 4 的片段(兜住只回显一部分的情况)。
# 长的先替换,免得短片段先把长串拆散后长串再也匹配不上。
function Get-RedactTokens([string[]]$Values) {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($v in @($Values | Where-Object { $_ })) {
        [void]$set.Add($v)
        $esc = [regex]::Replace($v, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
        [void]$set.Add($esc)
        foreach ($frag in @(($v -split '\s+') + ($esc -split '\s+'))) { if ($frag.Length -ge 4) { [void]$set.Add($frag) } }
    }
    return @($set | Sort-Object -Property Length -Descending)
}

# -Redact:回显 wraptool 输出前逐行把这些值(及其转义形态 / 片段,见 Get-RedactTokens)字面替换成 ****
# (TO-VALIDATE V1:--verbose 是否回显收到的参数未知,先按会回显处理)
function Invoke-Wraptool([string[]]$Arguments, [string[]]$Display = $null, [switch]$Capture, [string[]]$Redact = @()) {
    if ($null -eq $Display) { $Display = $Arguments }
    Write-Host ("> wraptool " + (Format-CommandLine $Display))
    $ErrorActionPreference = 'Continue'
    # 只在本函数作用域内生效:不论调用方 / profile 怎么设,传给 wraptool.exe 的参数都按 Standard 规则转义
    # (含 " 与空格的口令原样到达 wraptool,后面的 --in / --out 不会错位)。需要 7.3+(见 #Requires)
    $PSNativeCommandArgumentPassing = 'Standard'
    if ($Capture) {
        $text = (& $script:Wraptool @Arguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text }
    }
    $secrets = Get-RedactTokens $Redact
    & $script:Wraptool @Arguments 2>&1 | ForEach-Object {
        $line = "$_"
        # String.Replace:字面子串替换,不经正则。账号很短或是常见词时会连带替换无关文字,只影响可读性(TO-VALIDATE V1 时顺带看)
        foreach ($s in $secrets) { $line = $line.Replace($s, '****') }
        Write-Host "  $line"
    }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = '' }
}

function Invoke-Gh([string[]]$GhArgs) {
    $ErrorActionPreference = 'Continue'
    $OutputEncoding = $script:Utf8NoBom   # 函数作用域内生效,返回即恢复
    $prevEnc = Enter-Utf8Console
    try {
        $all = @(& gh @GhArgs 2>&1)
        $code = $LASTEXITCODE
    } finally { Exit-Utf8Console $prevEnc }
    $out = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    return [pscustomobject]@{ ExitCode = $code; Lines = $out; Err = ($err -join ' ') }
}

# 同一仓库的所有 worktree 共用同一个 git 公共目录(--git-common-dir);不在任何 git 工作树里则返回 $null
function Get-GitCommonDir([string]$Dir) {
    $r = Invoke-Git @('rev-parse', '--path-format=absolute', '--git-common-dir') $Dir
    if ($r.ExitCode -ne 0 -or -not $r.Lines) { return $null }
    return [System.IO.Path]::GetFullPath($r.Lines[0]).TrimEnd('\', '/')
}

# pfx 不得落在仓库目录下(CLAUDE.md §0 铁律 1)。两道判定:
#   ① 完整路径前缀(不区分大小写;文件本身若是符号链接,链接目标同样比);
#   ② git 兜底:KeyFile 所在(或最近一个已存在的上级)目录只要与本仓库共用同一个 git 公共目录就判在库内 ——
#      覆盖经 junction / subst 指进仓库(git 会解析到真实路径)以及放在本仓库另一个 worktree 里两种情况。
function Test-InsideRepo([string]$FullPath) {
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    $roots = @($RepoRoot.TrimEnd('\', '/'))
    $cands = @($FullPath)
    if (Test-Path -LiteralPath $FullPath) {
        $t = (Get-Item -LiteralPath $FullPath -Force).ResolveLinkTarget($true)
        if ($t) { $cands += $t.FullName }
    }
    foreach ($c in $cands) {
        foreach ($r in $roots) {
            if ($c.Equals($r, $cmp) -or $c.StartsWith($r + '\', $cmp)) { return $true }
        }
    }
    $repoCommon = Get-GitCommonDir $RepoRoot
    if (-not $repoCommon) { return $false }
    $dir = Split-Path -Parent $FullPath
    while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path -Parent $dir }
    if (-not $dir) { return $false }
    $common = Get-GitCommonDir $dir
    return [bool]($common -and $common.Equals($repoCommon, $cmp))
}

$script:Wraptool = $null
$work      = $null
$succeeded = $false
$packaged  = $false   # 本次运行已产出发行名 zip:之后任何一步失败都要删掉它(见 finally)
$signedZip = $null
$exitCode  = 0
$kp = $null
$ap = $null

try {
    # ---------------------------------------------------------------- 预检 0:参数
    try {
        if (-not $IsWindows) { throw '只支持 Windows(Authenticode 断言依赖 Get-AuthenticodeSignature);macOS 用 scripts/sign-aax-macos.sh' }
        if ($WcGuid -cnotmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') {
            throw '-WcGuid 不是 GUID(期望 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,不带花括号)'
        }
        if (-not $Account.Trim()) { throw '-Account 为空' }
        foreach ($a in $ExtraWraptoolArgs) {
            if ($a -like '*password*') { throw "-ExtraWraptoolArgs 不得含口令类参数('$a'):口令只经交互读入,不进参数" }
            if ($a -match $ManagedFlagRe) { throw "-ExtraWraptoolArgs 不得重复本脚本管理的 flag('$a')" }
        }
        if ($SourceRunId -and $SourceRunId -cnotmatch '^[0-9]+$') { throw "-SourceRunId 应为纯数字的 workflow run ID:'$SourceRunId'" }
        Add-Check '0 参数' 'PASS' ("WcGuid 格式正确;ExtraWraptoolArgs {0} 项" -f $ExtraWraptoolArgs.Count)
    } catch { Add-Check '0 参数' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 1:.sha256(完整性)
    # 只防损坏 / 下载不完整:.sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256 —— 来源由预检 3b 核对
    $zipFull = Resolve-UserPath $UnsignedZip
    $zipName = Split-Path -Leaf $zipFull
    $zipOk = $false
    try {
        if (-not (Test-Path -LiteralPath $zipFull -PathType Leaf)) { throw "找不到输入 zip:$zipFull" }
        $shaFull = "$zipFull.sha256"
        if (-not (Test-Path -LiteralPath $shaFull -PathType Leaf)) {
            throw "缺少同目录的 $zipName.sha256(CI artifact 里与 zip 成对下载;不要手工生成)"
        }
        # 逐字节读、不剥 BOM:格式必须与 package-aax.ps1 写出的完全一致(UTF-8 无 BOM、LF、只有一行)
        $shaText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($shaFull))
        $m = [regex]::Match($shaText, '^(?<h>[0-9a-f]{64})  ' + [regex]::Escape($zipName) + '\n\z')
        if (-not $m.Success) {
            throw "$zipName.sha256 格式不符:应恰为「64 位小写 hex + 两个空格 + $zipName + LF」(无 BOM / CRLF / 多余行)"
        }
        $actual = (Get-FileHash -LiteralPath $zipFull -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $m.Groups['h'].Value) {
            throw "SHA256 不符:.sha256 记录 $($m.Groups['h'].Value),实际 $actual —— zip 损坏或下载不完整(本项只验完整性),拒绝签名"
        }
        Add-Check '1 sha256' 'PASS' "完整性:$zipName = $actual"
        $zipOk = $true
    } catch { Add-Check '1 sha256' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 2:版本
    $ver = $null
    try {
        # 版本段与 package-aax.ps1 的版本校验同口径;大小写敏感
        $vm = [regex]::Match($zipName,
            '^SynchainBridge-AAX-v(?<v>[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?)-win64-UNSIGNED\.zip$')
        if (-not $vm.Success) {
            throw "文件名不是 SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip:'$zipName'(只接受 package-aax.ps1 -Mode Unsigned 的产物,不要改名)"
        }
        $ver = $vm.Groups['v'].Value
        Add-Check '2 版本' 'PASS' "v$ver"
    } catch { Add-Check '2 版本' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 3:检出与版本对应
    $sourceRef = $null
    $headCommit = $null   # 已确认与版本对应的 HEAD commit(预检 3b 用;合规文件脏不影响它)
    if ($ver) {
        try {
            if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { throw 'git 不在 PATH 上' }
            $head = Invoke-Git @('rev-parse', 'HEAD')
            if ($head.ExitCode -ne 0 -or $head.Lines.Count -ne 1) { throw "git rev-parse HEAD 失败(exit $($head.ExitCode)):$RepoRoot 不是 git 检出?" }
            $headSha = $head.Lines[0].Trim()
            $ci = [regex]::Match($ver, '-ci\.(?<sha>[0-9a-f]{7,40})$')
            if ($ci.Success) {
                # CI 预发布件(<CMake VERSION>-ci.<sha7>):没有对应 tag,源码链接钉完整 commit(与 ci.yml 6d 同口径)
                $want = $ci.Groups['sha'].Value
                if (-not $headSha.StartsWith($want, [System.StringComparison]::Ordinal)) {
                    throw "版本 $ver 来自 commit $want,当前 HEAD = ${headSha}:先 git checkout $want(合规文件与 INSTALL-AAX.txt 的源码链接必须对应该 commit)"
                }
                $sourceRef = $headSha
                $headCommit = $headSha
            } else {
                # 正式版与 tag 预发布(含 v0.0.0-test 彩排):HEAD 上必须有 v<版本> tag
                $tags = Invoke-Git @('tag', '--points-at', 'HEAD')
                if ($tags.ExitCode -ne 0) { throw "git tag --points-at HEAD 失败(exit $($tags.ExitCode))" }
                if ($tags.Lines -cnotcontains "v$ver") {
                    $have = if ($tags.Lines.Count) { $tags.Lines -join ', ' } else { '(无)' }
                    throw "HEAD 上没有 tag v$ver(现有:$have):先 git checkout v$ver"
                }
                $sourceRef = "v$ver"
                $headCommit = $headSha
            }
            $dirty = Invoke-Git @('status', '--porcelain', '--', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'LICENSES', 'scripts')
            if ($dirty.ExitCode -ne 0) { throw "git status 失败(exit $($dirty.ExitCode))" }
            if ($dirty.Lines.Count) {
                throw "合规文件 / scripts 有未提交改动(打进发行包的合规文件必须就是该版本的):$($dirty.Lines -join '; ')"
            }
            Add-Check '3 检出' 'PASS' "SourceRef = $sourceRef;合规文件与 scripts/ 无改动"
        } catch { $sourceRef = $null; Add-Check '3 检出' 'FAIL' $_.Exception.Message }
    } else {
        Add-Check '3 检出' 'SKIP' '版本未解析出来'
    }

    # ---------------------------------------------------------------- 预检 3b:来源(哪次构建产出了这些字节)
    if (-not $SourceRunId) {
        Add-Check '3b 来源' 'WARN' ('未给 -SourceRunId:只验了完整性,没核对这个 zip 出自哪次 CI 构建(.sha256 与 zip 同一份下载,' +
            '防不了替换)。签 CI / release 产物时请传产出它的 run ID')
    } elseif ($SourceRunId -cnotmatch '^[0-9]+$') {
        Add-Check '3b 来源' 'SKIP' '-SourceRunId 无效(见预检 0)'
    } elseif (-not $zipOk -or -not $headCommit) {
        Add-Check '3b 来源' 'SKIP' '输入 zip 完整性或检出未通过,无从核对'
    } else {
        $prov = $null
        try {
            if (-not (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)) { throw 'gh 不在 PATH 上(来源核对用 GitHub CLI,需已 gh auth login)' }
            # --jq 在 gh 端只投影出所需的 ASCII 字段(与 mac 版同口径):display_title / head_commit.message 这类可能含中文的
            # 字段根本不进管道,控制台代码页怎么解码都拼不坏 JSON;对象结构保持不变,后面的 $run.xxx 不用改
            $r = Invoke-Gh @('api', "repos/$UploadRepo/actions/runs/$SourceRunId", '--jq',
                '{repository:{full_name:.repository.full_name},head_repository:{full_name:.head_repository.full_name},path,status,conclusion,head_sha,event}')
            if ($r.ExitCode -ne 0) { throw "读取 run $SourceRunId 失败(exit $($r.ExitCode)):$($r.Err)" }
            $run = ($r.Lines -join "`n") | ConvertFrom-Json
            $runRepo  = [string]$run.repository.full_name
            $headRepo = [string]$run.head_repository.full_name
            if ($runRepo -cne $UploadRepo -or $headRepo -cne $UploadRepo) {
                throw "run $SourceRunId 属于 $runRepo(head 来自 $headRepo),不是 $UploadRepo 本仓库的构建"
            }
            if (@('.github/workflows/ci.yml', '.github/workflows/release.yml') -cnotcontains [string]$run.path) {
                throw "run $SourceRunId 的 workflow 是 '$($run.path)',只接受 ci.yml / release.yml 的产物"
            }
            if ([string]$run.conclusion -cne 'success') {
                throw "run $SourceRunId 的结论是 '$($run.status)/$($run.conclusion)',只接受成功完成的构建"
            }
            # pull_request 事件下 ci.yml 的 checkout 构建的是合并提交 refs/pull/N/merge(head + 当时的 base),run 的 head_sha
            # 却是 PR head —— head_sha 对上也不代表字节由当前检出构建。只认 push / workflow_dispatch:这两种事件构建的就是 head_sha
            if (@('push', 'workflow_dispatch') -cnotcontains [string]$run.event) {
                throw ("run $SourceRunId 的事件是 '$($run.event)':pull_request 构建的是合并提交,不是当前检出;只接受 push / " +
                    "workflow_dispatch 的 run(要签某个分支的件,对该分支 gh workflow run ci.yml --ref <分支> 再取它的 artifact)")
            }
            if ([string]$run.head_sha -cne $headCommit) {
                throw "run $SourceRunId 构建的是 $($run.head_sha),当前检出是 ${headCommit}:zip 与检出不是同一个 commit"
            }
            # 取回该 run 的 aax-unsigned-* artifact,其中同名 zip 必须与输入字节相同。ci.yml 6e / 8e(push / workflow_dispatch)与
            # release.yml 的 release / release-macos 都产出它(aax-unsigned-win64 / aax-unsigned-macos-arm64);签 tag 版本时传该 tag 的
            # release run ID(见 docs/release.md §7.3)。哪些 run 算合法来源,以上面几条判据为准
            $prov = Join-Path ([System.IO.Path]::GetTempPath()) ('synchain-aax-provenance-' + [guid]::NewGuid().ToString('N'))
            $d = Invoke-Gh @('run', 'download', $SourceRunId, '-R', $UploadRepo, '-p', 'aax-unsigned-*', '-D', $prov)
            if ($d.ExitCode -ne 0) { throw "gh run download $SourceRunId 失败(exit $($d.ExitCode);artifact 过期了?):$($d.Err)" }
            $hits = @(Get-ChildItem -LiteralPath $prov -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ceq $zipName })
            if ($hits.Count -ne 1) { throw "run $SourceRunId 的 aax-unsigned-* artifact 里找到 $($hits.Count) 个 $zipName(应恰好 1 个)" }
            $runHash = (Get-FileHash -LiteralPath $hits[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($runHash -cne $actual) {
                throw "输入 zip($actual)与 run $SourceRunId 的 artifact($runHash)字节不同:不是这次构建的产物,拒绝签名"
            }
            Add-Check '3b 来源' 'PASS' ("run $SourceRunId($($run.path),$($run.event),head $($run.head_sha.Substring(0, 7)))" +
                "的 artifact 与输入 zip 字节相同")
        } catch {
            Add-Check '3b 来源' 'FAIL' $_.Exception.Message
        } finally {
            if ($prov -and (Test-Path -LiteralPath $prov)) { Remove-Item -LiteralPath $prov -Recurse -Force }
        }
    }

    # ---------------------------------------------------------------- 预检 4:KeyFile
    $keyFull = $null
    $keyOk = $false
    try {
        $keyFull = Resolve-UserPath $KeyFile
        if (Test-InsideRepo $keyFull) {
            throw "KeyFile 位于仓库目录内($keyFull):pfx 必须放在仓库外(CLAUDE.md §0 铁律 1),例如 `$env:USERPROFILE\.synchain-signing\"
        }
        if (Test-Path -LiteralPath $keyFull -PathType Leaf) {
            Add-Check '4 KeyFile' 'PASS' "$keyFull(仓库外)"
            $keyOk = $true
        } elseif ($DryRun) {
            Add-Check '4 KeyFile' 'WARN' "不存在:$keyFull —— DryRun 放行(位置在仓库外);真签名时必须存在"
        } else {
            throw "KeyFile 不存在:$keyFull"
        }
    } catch { Add-Check '4 KeyFile' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 5:wraptool
    try {
        if ($WraptoolPath) {
            $p = Resolve-UserPath $WraptoolPath
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "-WraptoolPath 指向的文件不存在:$p" }
            $script:Wraptool = $p
        } else {
            $cmd = Get-Command wraptool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) {
                $script:Wraptool = $cmd.Source
            } elseif ($WraptoolDefault -and (Test-Path -LiteralPath $WraptoolDefault -PathType Leaf)) {
                $script:Wraptool = $WraptoolDefault
            } else {
                $shown = if ($WraptoolDefault) { $WraptoolDefault } else { '(无 ProgramFiles(x86))' }
                throw ("找不到 wraptool:PATH 里没有,默认路径 $shown 也不存在(TO-VALIDATE:Eden 默认安装路径以实际版本为准)。" +
                    "先装好 PACE Eden 签名工具,再重试或用 -WraptoolPath <wraptool.exe> 指定")
            }
        }
        Add-Check '5a wraptool' 'PASS' $script:Wraptool
    } catch { $script:Wraptool = $null; Add-Check '5a wraptool' 'FAIL' $_.Exception.Message }

    if ($script:Wraptool) {
        try {
            # TO-VALIDATE(V1):子命令写法 `help sign`;不看退出码(有的工具打印帮助后返回非零),只看输出里的 flag
            $help = Invoke-Wraptool @('help', 'sign') -Capture   # TO-VALIDATE(V1)
            $need = @($RequiredSignFlags)
            if ($PromptAccountPassword) { $need += '--password' }   # TO-VALIDATE(V2)
            $missing = @($need | Where-Object { $help.Output -cnotmatch ('(?<![\w-])' + [regex]::Escape($_) + '(?![\w-])') })
            if ($missing.Count) {
                throw "Eden 版本 flag 不符,按 TO-VALIDATE 更新脚本:「wraptool help sign」的输出里没有 $($missing -join ', ')"
            }
            Add-Check '5b wraptool flag' 'PASS' ($need -join ' ')
        } catch { Add-Check '5b wraptool flag' 'FAIL' $_.Exception.Message }
    } else {
        Add-Check '5b wraptool flag' 'SKIP' 'wraptool 不可用'
    }

    # ---------------------------------------------------------------- 预检 6:iLok(只提醒)
    Add-Check '6 iLok' 'INFO' ('签名需要插着 iLok(或已激活 iLok Cloud 会话)并运行 iLok License Manager;' +
        '本脚本不硬检,缺了 wraptool 自己会报错(TO-VALIDATE:进程名 / 报错文案)')

    # ---------------------------------------------------------------- 预检 7:解压 + 输入件确实未签名
    $inBundle = $null
    $outBundle = $null
    if ($zipOk) {
        $bundleOk = $false
        try {
            $work = Join-Path ([System.IO.Path]::GetTempPath()) ('synchain-aax-sign-' + [guid]::NewGuid().ToString('N'))
            $inDir = Join-Path $work 'in'
            New-Item -ItemType Directory -Force -Path $inDir, (Join-Path $work 'out') | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            # .NET 的 ExtractToDirectory 拒绝解到目标目录之外的条目(zip slip)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFull, $inDir)
            $inBundle = Join-Path $inDir $BundleName
            $outBundle = Join-Path (Join-Path $work 'out') $BundleName
            if (-not (Test-Path -LiteralPath $inBundle -PathType Container)) { throw "zip 根目录下没有 '$BundleName'" }
            $inDll = Join-Path $inBundle $DllRel
            if (-not (Test-Path -LiteralPath $inDll -PathType Leaf)) { throw "bundle 缺 $DllRel" }
            $inSig = Get-AuthenticodeSignature -LiteralPath $inDll
            if ([string]$inSig.Status -ne 'NotSigned') {
                throw "输入 DLL 的 Authenticode 状态是 $($inSig.Status)(应为 NotSigned):输入件已签过或被改过,拒绝"
            }
            Add-Check '7a 输入 bundle' 'PASS' "已解压到 $inDir;DLL = NotSigned"
            $bundleOk = $true
        } catch { Add-Check '7a 输入 bundle' 'FAIL' $_.Exception.Message }

        if ($bundleOk -and $script:Wraptool) {
            try {
                # TO-VALIDATE(V1):verify 的语法,以及「未签名 bundle → 非零退出」这一约定。语法若写错这里也会是非零
                # (假 PASS),但签名后的后检要求 verify 返回 0,语法错误会在那里暴露。
                $v = Invoke-Wraptool @('verify', '--in', $inBundle) -Capture   # TO-VALIDATE(V1)
                if ($v.ExitCode -eq 0) { throw "wraptool verify 对输入 bundle 返回成功 —— 它已经签过(重签会报错),中止" }
                Add-Check '7b wraptool verify' 'PASS' "按预期失败(exit $($v.ExitCode)):输入件未签名"
            } catch { Add-Check '7b wraptool verify' 'FAIL' $_.Exception.Message }
        } else {
            Add-Check '7b wraptool verify' 'SKIP' $(if ($bundleOk) { 'wraptool 不可用' } else { '输入 bundle 未就绪' })
        }
    } else {
        Add-Check '7a 输入 bundle' 'SKIP' '输入 zip 未通过完整性校验,不解压'
        Add-Check '7b wraptool verify' 'SKIP' '输入 zip 未通过完整性校验'
    }

    $OutDirFull = [System.IO.Path]::GetFullPath((Resolve-RepoPath $OutDir))
    $pkgScript  = Join-Path $PSScriptRoot 'package-aax.ps1'
    $pwshExe    = (Get-Process -Id $PID).Path   # 用当前同一个 pwsh 跑打包脚本(独立进程,状态隔离)
    $signedZip  = if ($ver) { Join-Path $OutDirFull "SynchainBridge-AAX-v$ver-win64.zip" } else { $null }
    $isCiBuild  = [bool]($ver -and $ver -cmatch '-ci\.[0-9a-f]{7,40}$')

    # 签名命令的打码版(回显用);真实参数只在签名那一步的 try 里临时拼出
    $wtShow = @(
        'sign', '--verbose',                                       # TO-VALIDATE(V1)
        '--account', '****', '--wcguid', '****',                   # TO-VALIDATE(V1)
        '--keyfile', $(if ($keyFull) { $keyFull } else { '<KeyFile>' }),
        '--keypassword', '****',                                   # TO-VALIDATE(V1)
        '--in', $(if ($inBundle) { $inBundle } else { "<work>\in\$BundleName" }),     # TO-VALIDATE(V1):给 bundle 目录还是内层 DLL
        '--out', $(if ($outBundle) { $outBundle } else { "<work>\out\$BundleName" })  # TO-VALIDATE(V1):能否指向新路径
    )
    if ($PromptAccountPassword) { $wtShow += @('--password', '****') }   # TO-VALIDATE(V2)
    $wtShow += $ExtraWraptoolArgs

    if ($DryRun) {
        Write-Host ''
        Write-Host '[DryRun] 签名计划(未执行):'
        Write-Host $(if ($SourceRunId) { "  0) 来源已按 run $SourceRunId 核对(见预检 3b)" } else { '  0) 未给 -SourceRunId:来源未核对(只验了完整性)' })
        Write-Host '  1) Read-Host -AsSecureString 读 pfx 口令(不进本脚本参数 / 日志 / transcript),载入 pfx 取指纹并确认带私钥、未过期'
        Write-Host '     注意:签名那几秒口令会以 --keypassword 出现在 wraptool 进程命令行里(wraptool 的限制),签名期间不要让他人登录本机'
        if ($PromptAccountPassword) { Write-Host '     另读 PACE 账号口令(--password,TO-VALIDATE V2)' }
        Write-Host ("  2) wraptool " + (Format-CommandLine $wtShow))
        Write-Host ('  3) 后检:wraptool verify --verbose --in <out> 退出码 0;Authenticode 签名者指纹 = pfx 指纹;' +
            $(if ($AllowNoTimestamp) { '时间戳缺失放行(-AllowNoTimestamp)' } else { '必须带时间戳' }))
        Write-Host ("  4) package-aax.ps1 -Mode Signed -Version {0} -SourceRef {1} -BundlePath <out> -OutDir {2}" -f `
            $(if ($ver) { $ver } else { '<版本>' }), $(if ($sourceRef) { $sourceRef } else { '<SourceRef>' }), $OutDirFull)
        Write-Host '  5) 回读:把产出的 zip 解到新临时目录,复验 wraptool verify 与签名者指纹'
        if ($isCiBuild) {
            Write-Host "  6) 版本 $ver 是 CI 预发布件,没有对应 Release:只打印提示,不给上传命令"
        } else {
            Write-Host ("  6) 打印(不执行):gh release upload v{0} <zip> <zip>.sha256 --repo {1}" -f $(if ($ver) { $ver } else { '<版本>' }), $UploadRepo)
        }

        # 用打包脚本自己的 -DryRun 校验「版本 + SourceRef」组合会被 Signed 模式接受(它不碰 bundle、不产出文件)
        if ($ver -and $sourceRef) {
            Write-Host ''
            Write-Host '[DryRun] package-aax.ps1 -Mode Signed -DryRun:'
            & $pwshExe -NoProfile -NonInteractive -File $pkgScript -Mode Signed -Version $ver -SourceRef $sourceRef `
                -BundlePath $(if ($outBundle) { $outBundle } else { Join-Path ([System.IO.Path]::GetTempPath()) $BundleName }) `
                -OutDir $OutDirFull -DryRun | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -ne 0) { Add-Check '8 打包计划' 'FAIL' "package-aax.ps1 -DryRun 退出码 $LASTEXITCODE" }
            else { Add-Check '8 打包计划' 'PASS' 'package-aax.ps1 -Mode Signed -DryRun 接受该版本与 SourceRef' }
        } else {
            Add-Check '8 打包计划' 'SKIP' '版本或 SourceRef 未确定'
        }

        $fails = @($Checks | Where-Object Result -eq 'FAIL')
        $warns = @($Checks | Where-Object Result -eq 'WARN')
        Write-Host ''
        Write-Host '[DryRun] 预检汇总:'
        foreach ($c in $Checks) { Write-Host ("  {0,-4}  {1}" -f $c.Result, $c.Id) }
        if ($fails.Count) {
            Write-Host ("[DryRun] 结论:{0} 项 FAIL({1})—— 真签名会在第一项 FAIL 处中止。未读口令、未调用 wraptool sign、未产出文件。" -f `
                $fails.Count, (($fails | ForEach-Object Id) -join ' / ')) -ForegroundColor Red
            $exitCode = 1
        } else {
            Write-Host ("[DryRun] 结论:预检全部通过{0}。未读口令、未调用 wraptool sign、未产出文件。" -f `
                $(if ($warns.Count) { "(另有 $($warns.Count) 项 WARN,真签名前处理)" } else { '' })) -ForegroundColor Green
        }
        $succeeded = $true   # DryRun 的临时目录一律删
    } else {
        # ================================================================ 签名
        # pfx 口令:只经交互读入,SecureString 全程;载入 pfx 同时验证口令、取预期指纹(EphemeralKeySet:私钥不落盘)
        $kp = Read-Host -AsSecureString '代码签名证书 (.pfx) 口令'
        try {
            $pfx = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($keyFull, $kp,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        } catch {
            throw "载入 pfx 失败(口令错误或文件损坏 / 加密算法不受支持,见 V8):$($_.Exception.Message)"
        }
        try {
            $pfxThumb = $pfx.Thumbprint
            if (-not $pfx.HasPrivateKey) { throw "pfx 里没有私钥:$keyFull" }
            if ($pfx.NotAfter -lt (Get-Date)) { throw "证书已于 $($pfx.NotAfter) 过期" }
            $eku = @($pfx.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } |
                ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object { $_.Value })
            if ($eku -notcontains '1.3.6.1.5.5.7.3.3') { Write-Warning '证书没有 Code Signing EKU(1.3.6.1.5.5.7.3.3);wraptool 可能拒收' }
            Write-Host "pfx: Subject=$($pfx.Subject) Thumbprint=$pfxThumb NotAfter=$($pfx.NotAfter)"
        } finally {
            $pfx.Dispose()
        }
        if ($PromptAccountPassword) { $ap = Read-Host -AsSecureString 'PACE 账号口令' }   # TO-VALIDATE(V2)

        $bstrK = [IntPtr]::Zero
        $bstrA = [IntPtr]::Zero
        $plainK = $null
        $plainA = $null
        $wtArgs = $null
        try {
            # BSTR → 明文只在这次调用期间存在;finally 里 ZeroFreeBSTR + 置空引用
            $bstrK = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($kp)
            $plainK = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrK)
            $wtArgs = @(
                'sign', '--verbose',              # TO-VALIDATE(V1)
                '--account', $Account,            # TO-VALIDATE(V1)
                '--wcguid', $WcGuid,              # TO-VALIDATE(V1)
                '--keyfile', $keyFull,            # TO-VALIDATE(V1)
                '--keypassword', $plainK,         # TO-VALIDATE(V1)
                '--in', $inBundle,                # TO-VALIDATE(V1):给 bundle 目录还是内层 DLL
                '--out', $outBundle               # TO-VALIDATE(V1):能否指向新路径
            )
            if ($PromptAccountPassword) {
                $bstrA = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ap)
                $plainA = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrA)
                $wtArgs += @('--password', $plainA)   # TO-VALIDATE(V2)
            }
            $wtArgs += $ExtraWraptoolArgs             # TO-VALIDATE:例如 --dsig1-compat off
            # TO-VALIDATE(V1):--verbose 是否回显收到的参数未知 —— 输出里的口令 / 账号 / wcguid 一律字面替换成 ****
            $sign = Invoke-Wraptool $wtArgs -Display $wtShow -Redact @($plainK, $plainA, $Account, $WcGuid)
        } finally {
            if ($bstrK -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrK) }
            if ($bstrA -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrA) }
            $plainK = $null
            $plainA = $null
            $wtArgs = $null
        }
        if ($sign.ExitCode -ne 0) { throw "wraptool sign 失败(exit $($sign.ExitCode))" }
        if (-not (Test-Path -LiteralPath $outBundle -PathType Container)) { throw "wraptool sign 返回 0,但没有产出 $outBundle(TO-VALIDATE:--out 语义)" }

        # ================================================================ 后检
        function Assert-SignedBundle([string]$Bundle, [string]$Label) {
            $vr = Invoke-Wraptool @('verify', '--verbose', '--in', $Bundle) -Redact @($Account, $WcGuid)   # TO-VALIDATE(V1):语法与退出码
            if ($vr.ExitCode -ne 0) { throw "${Label}:wraptool verify 失败(exit $($vr.ExitCode))" }
            $dll = Join-Path $Bundle $DllRel
            if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "${Label}:缺 $DllRel" }
            $sig = Get-AuthenticodeSignature -LiteralPath $dll
            if ($null -eq $sig.SignerCertificate) { throw "${Label}:DLL 没有 Authenticode 签名(Status=$($sig.Status))" }
            if (@('NotSigned', 'HashMismatch', 'NotSupportedFileFormat') -contains [string]$sig.Status) {
                throw "${Label}:Authenticode 签名不完好(Status=$($sig.Status))"
            }
            if ($sig.SignerCertificate.Thumbprint -ne $pfxThumb) {
                throw "${Label}:签名者指纹 $($sig.SignerCertificate.Thumbprint) ≠ pfx 指纹 $pfxThumb"
            }
            if ($null -eq $sig.TimeStamperCertificate) {
                # V3:拿不到时间戳也不要事后用 signtool 补 —— 那会改动已签名的文件,签名必须是最后一次修改
                if ($AllowNoTimestamp) { Write-Warning "${Label}:Authenticode 签名没有时间戳(-AllowNoTimestamp 放行;证书过期后签名随之失效)" }
                else { throw "${Label}:Authenticode 签名没有时间戳(V3:确认 wraptool 的时间戳选项;确实拿不到时显式传 -AllowNoTimestamp)" }
            }
            Write-Host "$Label OK:Status=$($sig.Status) Signer=$($sig.SignerCertificate.Subject) Thumbprint=$($sig.SignerCertificate.Thumbprint)"
        }
        Assert-SignedBundle $outBundle '后检'

        # 打包:Signed 模式会再做一遍 Authenticode 断言与 zip 回读比对字节;独立 pwsh 进程,状态与本脚本隔离
        & $pwshExe -NoProfile -NonInteractive -File $pkgScript -Mode Signed -Version $ver -SourceRef $sourceRef `
            -BundlePath $outBundle -OutDir $OutDirFull
        if ($LASTEXITCODE -ne 0) { throw "package-aax.ps1 -Mode Signed 失败(exit $LASTEXITCODE)" }
        if (-not (Test-Path -LiteralPath $signedZip -PathType Leaf)) { throw "打包后找不到 $signedZip" }
        $packaged = $true   # 从这里起失败,finally 删掉本次的发行名 zip / .sha256(打包脚本自己的失败路径由它自己清理)

        # 回读:产出的 zip 解到新临时目录,复验 wraptool verify 与指纹(发出去的字节还带着 PACE 签名)
        $rb = Join-Path $work 'readback'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($signedZip, $rb)
        Assert-SignedBundle (Join-Path $rb $BundleName) '回读'

        Write-Host ''
        Write-Host "签名完成:$signedZip"
        Write-Host "          $signedZip.sha256"
        if (-not $SourceRunId) { Write-Warning '本次未给 -SourceRunId:输入 zip 的来源没有核对过(只验了完整性)' }
        if ($isCiBuild) {
            Write-Host "版本 $ver 是 CI 预发布件,没有对应的 Release tag:只用于本机 / Pro Tools 实测,不要上传。"
        } else {
            # TO-VALIDATE(V11):gh release upload 能否直接传到 draft Release
            Write-Host '确认无误后手动上传到 draft Release(本脚本不自动执行):'
            Write-Host ("  gh release upload v{0} `"{1}`" `"{1}.sha256`" --repo {2}" -f $ver, $signedZip, $UploadRepo)
        }
        $succeeded = $true
    }
} catch {
    Write-Host "sign-aax: FAIL —— $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    # 打包之后的步骤(回读复验等)没通过:删掉本次产出的发行名 zip / .sha256 —— 它的文件名与 docs/release.md §7.3 第 5 步的
    # 上传路径逐字相同,留着就可能被照文档传上去。只在本次确实打过包时删,早期失败不碰上一次成功留下的件。
    if ($packaged -and -not $succeeded) {
        $removedAll = $true
        foreach ($p in @($signedZip, "$signedZip.sha256")) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
                catch {
                    $removedAll = $false
                    Write-Host "无法删除 ${p}:$($_.Exception.Message) —— 请手动删除,不要上传" -ForegroundColor Red
                }
            }
        }
        if ($removedAll) {
            Write-Host ("打包之后的步骤未通过:已删除 $signedZip 及 .sha256(失败路径不留发行名 zip;" +
                'package-summary.md 里本次追加的段落只是记录)') -ForegroundColor Yellow
        }
    }
    if ($kp) { $kp.Dispose() }
    if ($ap) { $ap.Dispose() }
    if ($work -and (Test-Path -LiteralPath $work)) {
        if ($succeeded) {
            Remove-Item -LiteralPath $work -Recurse -Force
        } else {
            Write-Host "工作目录已保留供排查(里面只有 bundle,没有秘密):$work" -ForegroundColor Yellow
        }
    }
}
exit $exitCode
