<#
.SYNOPSIS  AAX(Windows x64)本机签名:CI 产出的 -UNSIGNED.zip → PACE wraptool 签名 → package-aax.ps1 -Mode Signed 出发行包。
.DESCRIPTION
  只由维护者在本机手工执行;CI 不调用、流水线不持有任何签名凭据(CLAUDE.md §0 铁律 1)。
  AAX 是本项目唯一签名的格式(零售版 Pro Tools 只加载 PACE 签名件),VST3 / AU 仍按 U13 不签名。

  两组参数各二选一(互斥,预检 0 判定):
    签名身份  -CertThumbprint <SHA1>(推荐)→ --signid:证书留在「个人」证书库(CurrentUser\My 或 LocalMachine\My),
              不读证书口令,wraptool 的命令行上也没有 --keypassword
              -KeyFile <pfx>(备选)→ --keyfile + --keypassword:pfx 口令交互读入
    发布者    -WcGuid <GUID>(推荐)→ --wcguid:PACE Central 里为本产品建的 wrap 配置(要连 PACE 服务器,需账号口令,见下)
              -CustomerNumber + -CustomerName [+ -ProductName,默认 'Synchain Bridge'](备选)
              → --customernumber / --customername / --productname
  -Account 可选:不给就不传 --account,wraptool 用 iLok License Manager 的默认账号。PACE 账号口令两种给法:
    ① 推荐:事先手动执行一次带 --password 的 `wraptool sync --account <PACE 账号>`,口令存进 wraptool 自己的钥匙串,之后签名
       不用再给(`wraptool remove-pswd --account <PACE 账号>` 清除);
    ② -PromptAccountPassword(须同时给 -Account):交互读入,经 --pswd-no-save 传给 wraptool,不写进钥匙串。
  signtool:wraptool 在 Windows 上调 signtool.exe 加 Authenticode 签名,本脚本一律经 --signtool 显式指定(-SignToolPath,不给就按
    预检 5d 的顺序找)。不给 --signtool 时 wraptool 6.0.1 在它的「默认位置」找不到 Windows SDK 的 signtool,报的却是
    "Can't sign with the certificate identified by the thumbprint ..."(证书本身没问题),实测 2026-10-08。
  摘要算法:默认经 --explicitsigningoptions 让 signtool 用 SHA256 文件摘要 + RFC 3161 时间戳(/fd sha256 /tr <Sectigo> /td sha256);
    -LegacySha1Digest 回退到 wraptool 自己的默认命令(SHA1 文件摘要 + 旧式 /t 时间戳)。-KeyFile 方式只能走回退(见预检 0)。

  流程(任一步失败即 exit 1):
    预检 0 参数:Windows;两组参数各恰好一种;-WcGuid 是 GUID;-CertThumbprint 是 40 位 hex(容忍空格 / 冒号 / 从证书管理器
           复制带出的不可见方向符);-KeyFile 须同时给 -LegacySha1Digest;-ExtraWraptoolArgs 不含口令、不覆盖本脚本管理的 flag
           (长短写法都算,含 --signtool 与两个 signing options)
    预检 1 完整性:输入 zip 同目录的 .sha256 逐字节符合「64 位小写 hex + 两个空格 + zip 名 + LF」,且与实际哈希相等。
           只防损坏 / 下载不完整 —— .sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256,防不了替换
    预检 2 从文件名解析版本:SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip
    预检 3 检出对应该版本:-ci.<sha> 版本要求 HEAD 以该 sha 开头(SourceRef = 完整 HEAD);其余版本要求 HEAD 上有
           tag v<版本>(SourceRef = v<版本>);LICENSE / THIRD-PARTY-NOTICES.md / LICENSES / scripts 无未提交改动
    预检 3b 来源(-SourceRunId):该 run 属于本仓库(非 fork)、是 ci.yml / release.yml、结论 success、事件为 push / workflow_dispatch
           (pull_request 构建的是合并提交,不认)、head_sha = HEAD;
           再用 gh run download 取回它的 aax-unsigned-* artifact,其中同名 zip 必须与输入 zip 字节相同。
           这是「哪些字节会被盖上签名」的信任根;不给 -SourceRunId 只记 WARN(本地自建件没有 run 可核对)
    预检 4 签名身份:-CertThumbprint 的证书在 Cert:\CurrentUser\My 或 Cert:\LocalMachine\My 里(只读打开证书库)、带私钥、
           在有效期内、EKU 含代码签名;-KeyFile 存在,且解析后的完整路径不在仓库目录下(路径前缀 + git 公共目录两道判定,
           覆盖本仓库的其他 worktree)
    预检 5 5a PACE_FUSION_HOME:进程环境里没有就从 Machine 级环境变量补上(装签名工具之前开的终端里没有它);两处都没有 FAIL
           5b 定位 wraptool:-WraptoolPath → $env:PACE_FUSION_HOME\bin\wraptool.exe → PATH →
              %ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\<版本号最高的>\bin\wraptool.exe → %ProgramFiles(x86)% 同一相对路径
           5c `wraptool help` 的输出里有本次要用的全部 flag(按签名身份 / 发布者 / 账号方式 / 摘要算法决定),本脚本给它传值的
              flag 在 help 里也标着带值(`--x ] arg` / `--x arg`):哪天某个 flag 变成开关,值会变成多余的位置参数
           5d 定位 signtool:-SignToolPath → %ProgramFiles(x86)%\Windows Kits\10\bin\<版本号最高的>\x64\signtool.exe → PATH;
              都没有 FAIL(装 Windows SDK 的「Signing Tools」组件,或用 -SignToolPath 指定)。打印路径与版本
    预检 6 iLok 只提醒不硬检(wraptool 自己会报错;iLok 上没有签名证书时报 CouldNotFindSignerCredentials,见 docs/release.md §7.4)
    预检 7 解压到全新临时目录:bundle 存在、内层 DLL 为 NotSigned、`wraptool verify --in <内层 DLL>` 必须失败且输出 NOT signed
           (已签过的件重签会报错)
    签名   整个 bundle 复制到 <work>\out 并核对与 <work>\in 逐文件相同,再对 out 里的内层 DLL 原地签名(不给 --out)。
           Windows 上 wraptool 的 --in 必须是文件,签的就是 Contents\x64\Synchain Bridge.aaxplugin 这个 DLL;in 保持未签名原样,
           后检拿它比对。选原地签名而不是 --in <in DLL> --out <out DLL>:help 写明「不给输出路径就原地签名」,而 --out 指向一个
           已存在的文件时是否覆盖没有实测过;原地签名只依赖写明了的行为,失败时 in 与输入 zip 都没动过,从同一个 zip 重跑即可。
           始终传 --signtool <预检 5d 找到的 signtool>;默认另传 --explicitsigningoptions "sign /sha1 <指纹> /fd sha256 /tr <Sectigo>
           /td sha256"。实测 6.0.1(2026-10-08):这个值按空格切开后**整体替换** wraptool 默认的 signtool 参数(连 sign 子命令
           与 /sha1 都要自己给,--signid 此时不参与签名),文件路径仍由 wraptool 追加在最后。
           口令(-KeyFile 的 pfx 口令、-PromptAccountPassword 的账号口令)只经 Read-Host -AsSecureString 读入;BSTR → 明文只在
           调用瞬间存在,finally 里 ZeroFreeBSTR;回显的命令里口令 / PACE 账号 / wcguid / customer number 一律打码为 ****
    后检   wraptool verify --in <out DLL> 退出码 0;out 与 in 的文件清单相同、除 DLL 外逐字节相同(wraptool 只改了 DLL、没在
           bundle 里留下多余文件);Authenticode 签名者指纹 = -CertThumbprint / pfx 指纹;默认要求带时间戳(-AllowNoTimestamp
           显式放行);从 PE 证书表解出 PKCS#7,文件摘要与签名者摘要算法都必须是 SHA256(-LegacySha1Digest 时为 SHA1),默认方式
           下时间戳还必须是 RFC 3161、摘要 SHA256、且与签名对得上;调 package-aax.ps1 -Mode Signed 打包;再把产出的 zip 解压回读,
           复验 bundle 与 out 逐文件相同、wraptool verify、指纹与摘要算法;最后只**打印** gh release upload 命令,不自动执行
  成功即删除临时工作目录;失败则保留并打印路径(里面只有 bundle,没有秘密)。
  打包之后的任何一步(回读复验等)失败,都删掉本次产出的发行名 zip 与 .sha256:失败路径上 OutDir 里不留可上传的发行名 zip
  (package-summary.md 里本次追加的段落会留下,只是记录,不是可上传的文件)。

  -DryRun:跑全部预检(第 7 步的解压也在临时目录里做,结束即删)并汇总 PASS / WARN / FAIL / SKIP,打印签名计划
  (口令占位打码)与 package-aax.ps1 -DryRun 的输出;不读口令、不载入 pfx、不复制 bundle、不调用 wraptool sign、不产出任何文件。
  KeyFile 不存在在 DryRun 下只记 WARN;KeyFile 位于仓库内、-CertThumbprint 在证书库里找不到,任何模式都 FAIL。

  已在 wraptool 6.0.1 实测(2026-10-08):默认安装位置 %ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\6\bin\wraptool.exe,
  安装器设 Machine 级 PACE_FUSION_HOME(没有它 wraptool 报 "The PACE_FUSION_HOME environment variable is not defined");
  `wraptool help` 打印全部选项(`help sign` 在 v6 里不合法,exit 9);不给 --account 时用 iLok License Manager 的默认账号;
  Windows 上 verify / sign 的 --in 必须是文件(给 bundle 目录报 "A file must be specified for the 'verify' operation on
  Windows"),--out 可省(原地签名);未签名 DLL 的 verify 退出码 2、输出 "The architecture is NOT signed";--signid 收「个人」
  证书库里证书的 SHA1 指纹;时间戳默认就加(--timestampretry 默认 600 秒、--timestampretrysleep 默认 10 秒);--password 存进
  wraptool 钥匙串、--pswd-no-save 不存,两者都带口令值(help 里是 `-p [ --password ] arg` / `--pswd-no-save arg`);help 里没有经
  stdin / 环境变量传口令的通道。
  首次真签名实测(2026-10-08,wraptool 6.0.1 + Windows SDK 10.0.19041 的 signtool + 自签名证书):--signid 指纹 + --wcguid +
  --signtool 对内层 DLL 原地签名成功;已签名件 verify 退出码 0(输出 "The digital signature was verified" 与 "The binary was
  signed, but not wrapped.");签名件带 Sectigo 时间戳(V3);wraptool 默认的 signtool 命令是 `sign /sha1 "<指纹>" /t
  http://timestamp.sectigo.com <文件>`(SHA1 文件摘要 + 旧式时间戳),经 --explicitsigningoptions 换成 SHA256 + RFC 3161 后
  verify 照样是 0;--verbose 不回显口令(含 -PromptAccountPassword 的 --pswd-no-save 方式),但会回显 wcguid、默认账号名与它
  调 signtool 的整条命令行 —— 前两者本脚本打码,指纹是公开属性;不给账号口令时用 ILM 默认账号连得上服务器。自签名证书的链
  在 signtool verify /pa 下"terminated in a root ... not trusted"、Get-AuthenticodeSignature 为 UnknownError,均属预期。
  TO-VALIDATE:自签名证书签的件零售版 Pro Tools / Pro Tools Intro 是否接受;-KeyFile 身份与 --customernumber 发布者两条
  备选路径未真签过(-KeyFile 下 wraptool 回显的 signtool 命令行可能含 pfx 口令,按字面打码;能否读 AES256 加密的 pfx,V8);
  --explicitsigningoptions 方式下 --timestampretry 是否仍生效;证书在 Cert:\LocalMachine\My 时能否签(默认方式加 /sm,
  -LegacySha1Digest 方式看 wraptool 自己怎么找;实测只覆盖 CurrentUser\My);V11:gh release upload 能否直传 draft Release。

  禁止 Start-Transcript:本脚本不开 transcript,也不要在开着 transcript 的会话里运行(wraptool 的输出与本脚本的
  日志都不该进任何落盘记录)。口令交互读取,不进本脚本的参数、日志与 shell 历史。-CertThumbprint 方式下 wraptool 的命令行上
  没有证书口令;-KeyFile 方式的 pfx 口令与 -PromptAccountPassword 的账号口令只能经命令行参数交给 wraptool(--keypassword /
  --pswd-no-save):签名那几秒本机进程列表可见,开着进程命令行审计(Security 4688 含命令行 / Sysmon / EDR)时会被记录。
  只在可信的单用户机器上执行,签名期间不要让他人登录本机。wraptool 的输出逐行把口令(含它在命令行里的转义形态)/ PACE 账号 /
  wcguid / customer number 字面替换成 **** 后再显示,不给 -Account 时它打印的默认账号名同样打码。

  原生命令传参:$PSNativeCommandArgumentPassing 从 7.3 起才是正式特性(故 #Requires 7.3);Invoke-Wraptool 在函数作用域内
  显式设为 Standard,含双引号 / 空格的口令按 Windows 规则转义后原样交给 wraptool(7.2 的 Legacy 模式会把含 " 的口令
  拆错、把后面的参数吞掉)。git / gh 的输出按 UTF-8 解码(中文 Windows 默认 CP936,按它解码会把 JSON 拼坏)。
  本脚本给进程补上的 PACE_FUSION_HOME 在退出时撤掉,不改调用方会话的环境(新开的终端本来就有)。
.EXAMPLE
  在 pwsh 7.3+ 会话里、仓库根目录下用 & 调用(signtool 自动找;要指定就加 -SignToolPath <signtool.exe>):
  gh run download <run ID> -R synchain-oss/synchain-bridge -n aax-unsigned-win64 -D <下载目录>
  & ./scripts/sign-aax.ps1 -UnsignedZip <下载目录>\SynchainBridge-AAX-v1.6.0-win64-UNSIGNED.zip -SourceRunId <run ID> `
       -CertThumbprint <证书 SHA1 指纹> -WcGuid <wrap 配置 GUID> -DryRun
  不要经 `pwsh scripts/sign-aax.ps1 ...`(等同 pwsh -File)传数组参数:-ExtraWraptoolArgs '--timestampretry','120' 这种写法在
  -File 下不会被解析成数组,参数随之错位,报出「-CertThumbprint 与 -KeyFile 互斥」一类的假错(实测 2026-10-08)。
.EXAMPLE
  备选组合:pfx + customer number,账号口令交互读入、不存钥匙串;-KeyFile 须加 -LegacySha1Digest
  & ./scripts/sign-aax.ps1 -UnsignedZip <下载目录>\SynchainBridge-AAX-v1.6.0-win64-UNSIGNED.zip -SourceRunId <run ID> `
       -KeyFile $env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx -LegacySha1Digest `
       -CustomerNumber <PACE customer number> -CustomerName <公司名> -Account <PACE 账号> -PromptAccountPassword -DryRun
#>
#Requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UnsignedZip,   # SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip,同目录须有 .sha256
    [string]$CertThumbprint = '',                 # 签名身份(推荐):「个人」证书库里代码签名证书的 SHA1 指纹 → --signid
    [string]$KeyFile = '',                        # 签名身份(备选):代码签名证书 .pfx,必须在仓库外 → --keyfile + --keypassword
    [string]$WcGuid = '',                         # 发布者(推荐):PACE wrap 配置 GUID → --wcguid(日志里打码)
    [string]$CustomerNumber = '',                 # 发布者(备选):PACE customer number → --customernumber(日志里打码)
    [string]$CustomerName = '',                   # 与 -CustomerNumber 同用:公司名 → --customername
    [string]$ProductName = 'Synchain Bridge',     # 与 -CustomerNumber 同用 → --productname
    [string]$Account = '',                        # 可选:PACE 账号 → --account(日志里打码);不给则用 iLok License Manager 的默认账号
    [string]$OutDir = 'dist/aax-signed',          # 相对路径按仓库根解析;dist/ 已被 .gitignore 覆盖
    [string]$WraptoolPath = '',                   # 不给就按预检 5b 的顺序找
    [string]$SignToolPath = '',                   # signtool.exe;不给就按预检 5d 的顺序找。签名时一律经 --signtool 传给 wraptool
    [string[]]$ExtraWraptoolArgs = @(),           # 原样透传给 wraptool sign,例如 '--timestampretry','120'
    [string]$SourceRunId = '',                    # 产出该 zip 的 CI / release run 的 ID:给了就核对来源(预检 3b),不给只记 WARN
    [switch]$PromptAccountPassword,               # 交互读入 PACE 账号口令,经 --pswd-no-save 传(不写进钥匙串);须同时给 -Account
    [switch]$LegacySha1Digest,                    # 回退到 wraptool 默认的 signtool 命令(SHA1 文件摘要 + 旧式时间戳);-KeyFile 方式必须给
    [switch]$AllowNoTimestamp,                    # 放行不带时间戳的 Authenticode 签名(V3)
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$BundleName = 'Synchain Bridge.aaxplugin'
$DllRel     = 'Contents\x64\Synchain Bridge.aaxplugin'   # 主体 DLL:一个文件,后缀也是 .aaxplugin;Windows 上 wraptool 签的就是它
$UploadRepo = 'synchain-oss/synchain-bridge'

# wraptool 的安装布局(实测 6.0.1,2026-10-08):%ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\6\bin\wraptool.exe,
# Machine 级 PACE_FUSION_HOME = ...\Versions\6\。版本目录名按版本号比较,取最高的
$FusionVersionsRel = 'PACEAntiPiracy\Eden\Fusion\Versions'
$WraptoolRel       = 'bin\wraptool.exe'

# Windows SDK 的 signtool:%ProgramFiles(x86)%\Windows Kits\10\bin\<版本>\x64\signtool.exe(实测 10.0.19041.0)
$KitsBinRel  = 'Windows Kits\10\bin'
$SignToolRel = 'x64\signtool.exe'

# 默认的 signtool 参数(经 --explicitsigningoptions,整体替换 wraptool 的默认参数,文件路径由 wraptool 追加)。
# 时间戳服务器与 wraptool 默认用的是同一家(Sectigo),只是从旧式 /t 换成 RFC 3161 的 /tr + /td
$TimestampUrl = 'http://timestamp.sectigo.com'

# 后检核对的算法 / 属性 OID
$OidSpcIndirectData = '1.3.6.1.4.1.311.2.1.4'   # Authenticode 的 SignedData 内容类型
$OidRfc3161Stamp    = '1.3.6.1.4.1.311.3.3.1'   # 未签名属性:RFC 3161 时间戳(/tr)
$OidLegacyStamp     = '1.2.840.113549.1.9.6'    # 未签名属性:PKCS#9 countersignature,旧式时间戳(/t)
$DigestNames = @{ '1.3.14.3.2.26' = 'sha1'; '2.16.840.1.101.3.4.2.1' = 'sha256'; '2.16.840.1.101.3.4.2.2' = 'sha384'; '2.16.840.1.101.3.4.2.3' = 'sha512' }

# 本脚本自己管理的 flag:-ExtraWraptoolArgs 不得重复给出(否则同一 flag 出现两次,以哪个为准取决于 wraptool 实现)。
# 长写法不区分大小写;短写法照 wraptool 6.0.1 `help` 的别名表,区分大小写(-p 是 --password、-P 是 --keypassword、
# -i 是 --in、-I 是 --signid、-J 是 --extrasigningoptions),且 boost 风格允许值紧贴短 flag(-pXXX),所以按前缀拦。
# signtool 的命令行整个由本脚本决定(--signtool + --explicitsigningoptions,6.0.1 help 里这两个都没有短写法),
# --extrasigningoptions 一并拦下
$ManagedFlagRe      = '^--(account|password|pswd-no-save|wcguid|wcfile|customernumber|customername|productname|signid|keyfile|keypassword|in|out|signtool|explicitsigningoptions|extrasigningoptions)(=|$)'
$ManagedShortFlagRe = '^-[apPGWCNUIkioJ]'
$CodeSigningEku     = '1.3.6.1.5.5.7.3.3'

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

# 一行 wraptool 输出的打码:String.Replace 是字面子串替换,不经正则 —— 账号很短或是常见词时会连带替换无关文字,只影响可读性。
# 不给 --account 时 wraptool 会打印它用的默认账号(实测 6.0.1:"Using the default iLok License Manager account for this
# operation: <账号>"),脚本不知道账号名,按这句文案把冒号后面的值打码
function Hide-Secrets([string]$Line, [string[]]$Tokens) {
    foreach ($s in $Tokens) { $Line = $Line.Replace($s, '****') }
    # 冒号后整行都遮掉:账号名带空格 / 引号,或者文案改成 "...: <账号> (xxx)" 时也不漏
    return [regex]::Replace($Line, '(?i)(account for this operation:\s*).+$', '${1}****')
}

# -Redact:wraptool 的输出逐行把这些值(及其转义形态 / 片段,见 Get-RedactTokens)字面替换成 **** 后再显示 / 返回。
# 实测 6.0.1(2026-10-08):sign --verbose 不回显口令,但回显 wcguid("with this wrap config guid: ...")与它调 signtool 的
# 整条命令行。-Capture 只收集不显示
function Invoke-Wraptool([string[]]$Arguments, [string[]]$Display = $null, [switch]$Capture, [string[]]$Redact = @()) {
    if ($null -eq $Display) { $Display = $Arguments }
    Write-Host ("> wraptool " + (Format-CommandLine $Display))
    $ErrorActionPreference = 'Continue'
    # 只在本函数作用域内生效:不论调用方 / profile 怎么设,传给 wraptool.exe 的参数都按 Standard 规则转义
    # (含 " 与空格的口令原样到达 wraptool,后面的参数不会错位)。需要 7.3+(见 #Requires)
    $PSNativeCommandArgumentPassing = 'Standard'
    $tokens = Get-RedactTokens $Redact
    $lines = [System.Collections.Generic.List[string]]::new()
    & $script:Wraptool @Arguments 2>&1 | ForEach-Object {
        $line = Hide-Secrets "$_" $tokens
        if ($Capture) { $lines.Add($line) } else { Write-Host "  $line" }
    }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($lines -join "`n") }
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

function Get-EkuOids([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert) {
    return @($Cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } |
        ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object { $_.Value })
}

# %ProgramFiles(x86)%\Windows Kits\10\bin\<版本>\x64\signtool.exe 里版本号最高的一个;arm64 / x86 这类不是版本号的目录跳过
function Find-SignToolInKits {
    if (-not ${env:ProgramFiles(x86)}) { return $null }
    $bin = Join-Path ${env:ProgramFiles(x86)} $KitsBinRel
    if (-not (Test-Path -LiteralPath $bin -PathType Container)) { return $null }
    $best = Get-ChildItem -LiteralPath $bin -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $v = $null
        $exe = Join-Path $_.FullName $SignToolRel
        if ([version]::TryParse($_.Name, [ref]$v) -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
            [pscustomobject]@{ Version = $v; Path = $exe }
        }
    } | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($best) { return $best.Path }
    return $null
}

function Get-DigestName([string]$Oid) {
    if ($DigestNames.ContainsKey($Oid)) { return $DigestNames[$Oid] }
    return $Oid
}

# 从 PE 的证书表(数据目录第 4 项,它的地址是文件偏移而不是 RVA)取出 Authenticode 的 PKCS#7,解出文件摘要算法
# (SpcIndirectDataContent 里的 DigestInfo,即 signtool verify 的 "Hash of file (xxx)")、签名者摘要算法与时间戳形态。
# Get-AuthenticodeSignature 只给签名者 / 时间戳证书,看不出摘要算法,也分不出 RFC 3161 与旧式时间戳。
# 只看证书表的第一项和主签名:嵌套签名(signtool /as,未签名属性 1.3.6.1.4.1.311.2.4.1)不解析 —— 本流程只签一次,不会产生
function Get-AuthenticodeDigest([string]$Path) {
    Add-Type -AssemblyName System.Security.Cryptography.Pkcs
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 0x40) { throw '文件太短,不是 PE' }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -lt 0 -or [long]$pe + 26 -gt $b.Length -or [BitConverter]::ToUInt32($b, $pe) -ne 0x00004550) { throw '不是 PE 文件' }
    $opt = $pe + 24
    $dd = switch ([BitConverter]::ToUInt16($b, $opt)) { 0x20B { $opt + 112 } 0x10B { $opt + 96 } default { throw '可选头的 magic 不认识' } }
    if ([long]$dd + 40 -gt $b.Length -or [BitConverter]::ToUInt32($b, $dd - 4) -lt 5) { throw 'PE 没有证书表这一项数据目录' }
    $secOff = [long][BitConverter]::ToUInt32($b, $dd + 32)
    $secLen = [long][BitConverter]::ToUInt32($b, $dd + 36)
    if ($secOff -eq 0 -or $secLen -lt 8 -or $secOff + $secLen -gt $b.Length) { throw 'PE 证书表为空或越界:没有 Authenticode 签名' }
    # WIN_CERTIFICATE:dwLength / wRevision / wCertificateType(2 = PKCS_SIGNED_DATA)/ 内容
    $wcLen = [long][BitConverter]::ToUInt32($b, [int]$secOff)
    if ([BitConverter]::ToUInt16($b, [int]$secOff + 6) -ne 2 -or $wcLen -le 8 -or $wcLen -gt $secLen) { throw '证书表里的第一项不是 PKCS#7 签名' }
    $pkcs = [byte[]]::new($wcLen - 8)
    [Array]::Copy($b, $secOff + 8, $pkcs, 0, $wcLen - 8)
    $cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
    $cms.Decode($pkcs)
    if ($cms.ContentInfo.ContentType.Value -cne $OidSpcIndirectData) { throw "PKCS#7 的内容类型是 $($cms.ContentInfo.ContentType.Value),不是 Authenticode" }
    if ($cms.SignerInfos.Count -ne 1) { throw "PKCS#7 里有 $($cms.SignerInfos.Count) 个签名者(应恰好 1 个)" }
    # SpcIndirectDataContent ::= SEQUENCE { data SpcAttributeTypeAndOptionalValue, messageDigest DigestInfo }
    $seq = [System.Formats.Asn1.AsnReader]::new($cms.ContentInfo.Content, [System.Formats.Asn1.AsnEncodingRules]::DER).ReadSequence()
    $null = $seq.ReadEncodedValue()
    $fileOid = $seq.ReadSequence().ReadSequence().ReadObjectIdentifier()
    $si = $cms.SignerInfos[0]
    $stamp = 'None'; $stampDigest = $null; $stampOk = $false
    foreach ($a in $si.UnsignedAttributes) {
        if ($a.Oid.Value -ceq $OidRfc3161Stamp) {
            $stamp = 'RFC3161'
            $tok = $null; $read = 0
            if ([System.Security.Cryptography.Pkcs.Rfc3161TimestampToken]::TryDecode($a.Values[0].RawData, [ref]$tok, [ref]$read)) {
                $stampDigest = Get-DigestName $tok.TokenInfo.HashAlgorithmId.Value
                $tsaCert = $null
                # 时间戳令牌的签名有效,且它盖的正是这个签名者的签名值
                $stampOk = $tok.VerifySignatureForSignerInfo($si, [ref]$tsaCert)
            }
        } elseif ($a.Oid.Value -ceq $OidLegacyStamp -and $stamp -eq 'None') {
            $stamp = 'Legacy'
        }
    }
    return [pscustomobject]@{
        FileDigest = Get-DigestName $fileOid; SignerDigest = Get-DigestName $si.DigestAlgorithm.Value
        Timestamp = $stamp; TimestampDigest = $stampDigest; TimestampVerified = $stampOk
    }
}

# <Root>\PACEAntiPiracy\Eden\Fusion\Versions\<版本>\bin\wraptool.exe 里版本号最高的一个;目录名不是版本号的跳过
function Find-WraptoolUnder([string]$Root) {
    if (-not $Root) { return $null }
    $vdir = Join-Path $Root $FusionVersionsRel
    if (-not (Test-Path -LiteralPath $vdir -PathType Container)) { return $null }
    $best = Get-ChildItem -LiteralPath $vdir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $v = $null
        $n = if ($_.Name -match '^[0-9]+$') { "$($_.Name).0" } else { $_.Name }   # [version] 至少要 major.minor
        $exe = Join-Path $_.FullName $WraptoolRel
        if ([version]::TryParse($n, [ref]$v) -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
            [pscustomobject]@{ Version = $v; Path = $exe }
        }
    } | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($best) { return $best.Path }
    return $null
}

# bundle 内的相对文件清单(含隐藏 / 系统文件:desktop.ini 可能带 System 属性)
function Get-BundleFiles([string]$Bundle) {
    return @(Get-ChildItem -LiteralPath $Bundle -Recurse -File -Force |
        ForEach-Object { [System.IO.Path]::GetRelativePath($Bundle, $_.FullName) } | Sort-Object)
}

# 两个 bundle 的文件清单必须相同,且逐文件字节相同;-AllowDllChange 时只有内层 DLL 可以不同(签名改的就是它)
function Assert-SameBundle([string]$Ref, [string]$Bundle, [string]$Label, [switch]$AllowDllChange) {
    $a = Get-BundleFiles $Ref
    $b = Get-BundleFiles $Bundle
    $extra = @($b | Where-Object { $a -notcontains $_ })
    $gone  = @($a | Where-Object { $b -notcontains $_ })
    if ($extra.Count -or $gone.Count) {
        throw "${Label}:bundle 的文件清单变了(多出:$(if ($extra.Count) { $extra -join ', ' } else { '无' });缺少:$(if ($gone.Count) { $gone -join ', ' } else { '无' }))"
    }
    foreach ($rel in $a) {
        if ($AllowDllChange -and $rel -eq $DllRel) { continue }
        $h1 = (Get-FileHash -LiteralPath (Join-Path $Ref $rel) -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath (Join-Path $Bundle $rel) -Algorithm SHA256).Hash
        if ($h1 -ne $h2) { throw "${Label}:$rel 与对照件字节不同" }
    }
}

# 本次要用的 wraptool flag(预检 5c 在 `wraptool help` 的输出里逐个找)
function Get-RequiredFlags {
    $f = @('--verbose', '--in', '--signtool')
    if ($CertThumbprint) { $f += '--signid' } else { $f += @('--keyfile', '--keypassword') }
    if ($WcGuid) { $f += '--wcguid' } else { $f += @('--customernumber', '--customername', '--productname') }
    if ($Account) { $f += '--account' }
    if ($PromptAccountPassword) { $f += '--pswd-no-save' }
    if (-not $LegacySha1Digest) { $f += '--explicitsigningoptions' }
    return $f
}

# 默认方式交给 signtool 的完整参数(文件路径由 wraptool 追加)。只在 -CertThumbprint 方式下用(-KeyFile 须 -LegacySha1Digest)。
# signtool /sha1 默认只查当前用户的 My 库;预检 4 也接受 Cert:\LocalMachine\My,证书在那里时按 signtool 文档加 /sm 改查本机库
# (TO-VALIDATE:实测只覆盖了 CurrentUser\My;-LegacySha1Digest 走 wraptool 自己的命令,LocalMachine 下能否签同样未实测)
function Get-ExplicitSigningOptions {
    $sm = if ($certLoc -ceq 'LocalMachine') { ' /sm' } else { '' }
    return "sign /sha1 $certThumb$sm /fd sha256 /tr $TimestampUrl /td sha256"
}

# wraptool sign 的参数表。-Masked 给回显用(口令 / 账号 / wcguid / customer number 换成 ****);真实参数只在签名那一步临时拼出。
# 不给 --out:对 --in 指向的 DLL 原地签名(理由见文件头「签名」一段)
function Get-SignArgs([string]$Dll, [string]$KeyPw = '', [string]$AccountPw = '', [switch]$Masked) {
    # --verbose:实测 6.0.1 不回显口令,回显的 wcguid / 默认账号名经 Invoke-Wraptool 打码
    $a = @('sign', '--verbose', '--signtool', $(if ($script:SignTool) { $script:SignTool } else { '<signtool.exe>' }))
    if ($Account) { $a += @('--account', $(if ($Masked) { '****' } else { $Account })) }
    if ($CertThumbprint) {
        $a += @('--signid', $certThumb)   # 指纹是证书的公开属性,不打码
        # 默认方式下 signtool 的参数整体换成下面这串,--signid 不参与签名(实测 6.0.1 不给也能签);仍照传,两种方式的身份参数一致
        if (-not $LegacySha1Digest) { $a += @('--explicitsigningoptions', (Get-ExplicitSigningOptions)) }
    } else {
        $a += @('--keyfile', $(if ($keyFull) { $keyFull } else { '<KeyFile>' }), '--keypassword', $(if ($Masked) { '****' } else { $KeyPw }))
    }
    if ($WcGuid) {
        $a += @('--wcguid', $(if ($Masked) { '****' } else { $WcGuid }))
    } else {
        $a += @('--customernumber', $(if ($Masked) { '****' } else { $CustomerNumber }), '--customername', $CustomerName, '--productname', $ProductName)
    }
    if ($PromptAccountPassword) { $a += @('--pswd-no-save', $(if ($Masked) { '****' } else { $AccountPw })) }
    $a += @('--in', $Dll)
    return @($a + $ExtraWraptoolArgs)
}

$script:Wraptool = $null
$script:SignTool = $null
$certThumb   = ($CertThumbprint -replace '[\s:\u200E\u200F]', '').ToUpperInvariant()   # 证书管理器里复制的指纹常带空格与不可见方向符
$certWhere   = $null   # -CertThumbprint 找到的证书库位置(回显用)
$certLoc     = $null   # 同上,CurrentUser / LocalMachine(LocalMachine 时默认方式给 signtool 加 /sm)
$expectThumb = $null   # 后检要求的 Authenticode 签名者指纹:-CertThumbprint 方式在预检 4 定,-KeyFile 方式在签名前载入 pfx 时定
$keyFull     = $null
$fusionAdded = $false  # 本脚本给进程补上了 PACE_FUSION_HOME:退出时撤掉
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
        foreach ($n in 'CertThumbprint', 'KeyFile', 'WcGuid', 'CustomerNumber', 'CustomerName', 'ProductName', 'Account', 'WraptoolPath', 'SignToolPath') {
            if ($PSBoundParameters.ContainsKey($n) -and -not ([string]$PSBoundParameters[$n]).Trim()) { throw "-$n 传入了空串" }
        }
        if ($CertThumbprint -and $KeyFile) { throw '-CertThumbprint 与 -KeyFile 互斥:签名身份只能选一种' }
        if (-not $CertThumbprint -and -not $KeyFile) {
            throw '缺签名身份:给 -CertThumbprint <SHA1 指纹>(推荐,证书在「个人」证书库)或 -KeyFile <pfx>(备选)'
        }
        if ($WcGuid -and $CustomerNumber) { throw '-WcGuid 与 -CustomerNumber 互斥:发布者信息只能选一种' }
        if (-not $WcGuid -and -not $CustomerNumber) {
            throw '缺发布者信息:给 -WcGuid <wrap 配置 GUID>(推荐),或 -CustomerNumber 加 -CustomerName(备选)'
        }
        if ($CustomerNumber -and -not $CustomerName) { throw '-CustomerNumber 须同时给 -CustomerName(公司名)' }
        if (-not $CustomerNumber -and ($PSBoundParameters.ContainsKey('CustomerName') -or $PSBoundParameters.ContainsKey('ProductName'))) {
            throw '-CustomerName / -ProductName 只与 -CustomerNumber 同用(-WcGuid 方式下发布者与产品信息来自 wrap 配置)'
        }
        if ($WcGuid -and $WcGuid -cnotmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') {
            throw '-WcGuid 不是 GUID(期望 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,不带花括号)'
        }
        if ($CertThumbprint -and $certThumb -cnotmatch '^[0-9A-F]{40}$') {
            throw '-CertThumbprint 不是 40 位十六进制的 SHA1 指纹(证书「详细信息 → 指纹」,或 Get-ChildItem Cert:\CurrentUser\My 的 Thumbprint 列)'
        }
        if ($CustomerNumber -and ($CustomerNumber -match '\s' -or $CustomerNumber.StartsWith('-'))) {
            throw '-CustomerNumber 不得含空白、不得以 - 开头'
        }
        # 以 - 开头的值会被 wraptool(boost 风格)当成短 flag
        if ($CustomerNumber -and $CustomerName.StartsWith('-')) { throw '-CustomerName 不得以 - 开头' }
        if ($CustomerNumber -and $ProductName.StartsWith('-')) { throw '-ProductName 不得以 - 开头' }
        if ($PromptAccountPassword -and -not $Account) {
            throw '-PromptAccountPassword 须同时给 -Account:读入的口令属于哪个 PACE 账号要明确'
        }
        # SHA256 要经 --explicitsigningoptions 把整条 signtool 参数交给 wraptool;-KeyFile 方式下这串里得带 /f <pfx> /p <口令>:
        # wraptool 按空格切分(含空格的路径 / 口令怎么切未实测),--verbose 还会把整条 signtool 命令行打印出来
        if ($KeyFile -and -not $LegacySha1Digest) {
            throw ('-KeyFile 方式须同时给 -LegacySha1Digest(SHA1 文件摘要,wraptool 默认的 signtool 命令):SHA256 要把 pfx 路径与口令写进 ' +
                '--explicitsigningoptions,本脚本不这么做。要 SHA256,把 pfx 导入「个人」证书库后改用 -CertThumbprint')
        }
        foreach ($a in $ExtraWraptoolArgs) {
            if ($a -like '*password*' -or $a -like '*pswd*') { throw "-ExtraWraptoolArgs 不得含口令类参数('$a'):口令只经交互读入,不进参数" }
            if ($a -match $ManagedFlagRe -or $a -cmatch $ManagedShortFlagRe) { throw "-ExtraWraptoolArgs 不得重复本脚本管理的 flag('$a')" }
        }
        if ($SourceRunId -and $SourceRunId -cnotmatch '^[0-9]+$') { throw "-SourceRunId 应为纯数字的 workflow run ID:'$SourceRunId'" }
        Add-Check '0 参数' 'PASS' ("签名身份 {0};发布者 {1};账号 {2};摘要 {3};ExtraWraptoolArgs {4} 项" -f `
            $(if ($CertThumbprint) { "-CertThumbprint $certThumb" } else { '-KeyFile' }),
            $(if ($WcGuid) { '-WcGuid(格式正确)' } else { "-CustomerNumber / -CustomerName '$CustomerName' / -ProductName '$ProductName'" }),
            $(if ($Account) { '-Account(打码)' + $(if ($PromptAccountPassword) { ' + 交互口令(--pswd-no-save)' } else { '' }) } else { 'iLok License Manager 默认账号' }),
            $(if ($LegacySha1Digest) { 'SHA1 + 旧式时间戳(-LegacySha1Digest)' } else { 'SHA256 + RFC 3161 时间戳' }),
            $ExtraWraptoolArgs.Count)
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

    # ---------------------------------------------------------------- 预检 4:签名身份
    if ($CertThumbprint -and $KeyFile) {
        Add-Check '4 签名身份' 'SKIP' '-CertThumbprint 与 -KeyFile 互斥(见预检 0)'
    } elseif ($CertThumbprint) {
        try {
            if ($certThumb -cnotmatch '^[0-9A-F]{40}$') { throw '指纹格式不对(见预检 0)' }
            # wraptool 的 --signid 在当前用户与本机两个「个人」库里找(实测 6.0.1 help);这里同样两处都查,只读打开,不写证书库
            $found = @()
            foreach ($loc in 'CurrentUser', 'LocalMachine') {
                $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', $loc)
                try {
                    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadOnly, OpenExistingOnly')
                    foreach ($c in $store.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $certThumb, $false)) {
                        $found += [pscustomobject]@{ Where = "Cert:\$loc\My"; Loc = $loc; Cert = $c }
                    }
                } catch {
                    # 该位置没有 My 库 / 打不开:按「这里没找到」处理,另一处照查
                } finally { $store.Close() }
            }
            if (-not $found.Count) {
                throw ("证书库里找不到指纹 $certThumb(查了 Cert:\CurrentUser\My 与 Cert:\LocalMachine\My):先用 " +
                    'scripts/new-selfsigned-codesign-cert.ps1 生成(不加 -RemoveFromStore),或把 pfx 导入「个人」证书库;只有 pfx 时改用 -KeyFile')
            }
            $hit = $found | Where-Object { $_.Cert.HasPrivateKey } | Select-Object -First 1
            if (-not $hit) { throw "$($found[0].Where) 里的证书 $certThumb 没有关联私钥:wraptool 用它签不了名" }
            $cert = $hit.Cert
            $now = Get-Date
            if ($cert.NotAfter -lt $now) { throw "证书 $certThumb 已于 $($cert.NotAfter) 过期" }
            if ($cert.NotBefore -gt $now) { throw "证书 $certThumb 要到 $($cert.NotBefore) 才生效" }
            if ((Get-EkuOids $cert) -notcontains $CodeSigningEku) {
                throw "证书 $certThumb 的增强型密钥用法里没有代码签名($CodeSigningEku)"
            }
            $certWhere = $hit.Where
            $certLoc = $hit.Loc
            $expectThumb = $certThumb
            Add-Check '4 签名身份' 'PASS' ("$certWhere\$certThumb;$($cert.Subject);带私钥;有效期至 " +
                $cert.NotAfter.ToString('yyyy-MM-dd') + ";EKU 含代码签名;不读证书口令")
        } catch { Add-Check '4 签名身份' 'FAIL' $_.Exception.Message }
    } elseif ($KeyFile) {
        try {
            $keyFull = Resolve-UserPath $KeyFile
            if (Test-InsideRepo $keyFull) {
                throw "KeyFile 位于仓库目录内($keyFull):pfx 必须放在仓库外(CLAUDE.md §0 铁律 1),例如 `$env:USERPROFILE\.synchain-signing\"
            }
            if (Test-Path -LiteralPath $keyFull -PathType Leaf) {
                Add-Check '4 签名身份' 'PASS' "-KeyFile $keyFull(仓库外;口令签名时交互读入)"
            } elseif ($DryRun) {
                Add-Check '4 签名身份' 'WARN' "-KeyFile 不存在:$keyFull —— DryRun 放行(位置在仓库外);真签名时必须存在"
            } else {
                throw "KeyFile 不存在:$keyFull"
            }
        } catch { Add-Check '4 签名身份' 'FAIL' $_.Exception.Message }
    } else {
        Add-Check '4 签名身份' 'SKIP' '没给签名身份(见预检 0)'
    }

    # ---------------------------------------------------------------- 预检 5a:PACE_FUSION_HOME
    # 实测 6.0.1(2026-10-08):安装器设的是 Machine 级环境变量,装之前就开着的终端里没有,wraptool 会报
    # "The PACE_FUSION_HOME environment variable is not defined"。进程里没有就从 Machine 级补上(退出时撤掉)
    try {
        if (-not $env:PACE_FUSION_HOME) {
            $machine = [Environment]::GetEnvironmentVariable('PACE_FUSION_HOME', 'Machine')
            if (-not $machine) {
                throw ('PACE_FUSION_HOME 未定义(进程环境与 Machine 级环境变量里都没有),wraptool 没有它就报 "The PACE_FUSION_HOME ' +
                    'environment variable is not defined":装完 PACE 签名工具要新开一个终端再跑;新终端里仍没有,就重装签名工具')
            }
            $env:PACE_FUSION_HOME = $machine
            $fusionAdded = $true
        }
        if (-not (Test-Path -LiteralPath $env:PACE_FUSION_HOME -PathType Container)) {
            throw "PACE_FUSION_HOME = $env:PACE_FUSION_HOME 不是存在的目录:签名工具装坏了或被删了,重装签名工具"
        }
        Add-Check '5a PACE_FUSION_HOME' 'PASS' $(if ($fusionAdded) {
            "进程环境里没有(多半是装签名工具之前开的终端),已从 Machine 级补上:$env:PACE_FUSION_HOME"
        } else { "进程环境里已有:$env:PACE_FUSION_HOME" })
    } catch { Add-Check '5a PACE_FUSION_HOME' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 5b:wraptool
    try {
        $src = $null
        if ($WraptoolPath) {
            $p = Resolve-UserPath $WraptoolPath
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "-WraptoolPath 指向的文件不存在:$p" }
            $script:Wraptool = $p
            $src = '-WraptoolPath'
        } else {
            $fromHome = if ($env:PACE_FUSION_HOME) { Join-Path $env:PACE_FUSION_HOME $WraptoolRel } else { $null }
            $cmd = Get-Command wraptool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($fromHome -and (Test-Path -LiteralPath $fromHome -PathType Leaf)) {
                $script:Wraptool = $fromHome; $src = 'PACE_FUSION_HOME'
            } elseif ($cmd) {
                $script:Wraptool = $cmd.Source; $src = 'PATH'
            } elseif ($p = Find-WraptoolUnder $env:ProgramFiles) {
                $script:Wraptool = $p; $src = '%ProgramFiles% 下版本号最高的'
            } elseif ($p = Find-WraptoolUnder ${env:ProgramFiles(x86)}) {
                $script:Wraptool = $p; $src = '%ProgramFiles(x86)% 下版本号最高的'   # TO-VALIDATE:6.0.1 装在 64 位 Program Files,x86 布局未见过
            } else {
                throw ("找不到 wraptool:PACE_FUSION_HOME\$WraptoolRel、PATH、%ProgramFiles% / %ProgramFiles(x86)%\$FusionVersionsRel\<版本>\$WraptoolRel " +
                    '都没有。先装好 PACE 签名工具(装完新开终端),或用 -WraptoolPath <wraptool.exe> 指定')
            }
        }
        # wraptool 按 PACE_FUSION_HOME 找自己的资源:选中的 wraptool 不在它下面(PATH 上的旧版本 / -WraptoolPath 指向别处)就提醒
        $fusionRoot = if ($env:PACE_FUSION_HOME) { [System.IO.Path]::GetFullPath($env:PACE_FUSION_HOME).TrimEnd('\') + '\' } else { $null }
        if ($fusionRoot -and -not $script:Wraptool.StartsWith($fusionRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Check '5b wraptool' 'WARN' "$($script:Wraptool)(来自 $src)不在 PACE_FUSION_HOME = $env:PACE_FUSION_HOME 下:确认两者是同一套安装"
        } else {
            Add-Check '5b wraptool' 'PASS' "$($script:Wraptool)(来自 $src)"
        }
    } catch { $script:Wraptool = $null; Add-Check '5b wraptool' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 5c:wraptool flag
    if ($script:Wraptool -and $env:PACE_FUSION_HOME) {
        try {
            # 实测 6.0.1(2026-10-08):`wraptool help` 打印全部选项;`help sign` 在 v6 里不合法(too many positional options,
            # exit 9)。不看退出码,只看输出里有没有本次要用的 flag;本脚本给它传值的 flag 还要在 help 里标着带值
            # (选项表里是 `-I [ --signid ] arg` / `--pswd-no-save arg` 这种写法)
            $help = Invoke-Wraptool @('help') -Capture
            $need = Get-RequiredFlags
            $missing = @($need | Where-Object { $help.Output -cnotmatch ('(?<![\w-])' + [regex]::Escape($_) + '(?![\w-])') })
            if ($missing.Count) {
                throw "「wraptool help」的输出里没有 $($missing -join ', '):wraptool 版本与本脚本不符(本脚本按 wraptool 6.0.1 实测编写)"
            }
            $noArg = @($need | Where-Object { $_ -cne '--verbose' } |
                Where-Object { $help.Output -cnotmatch ('(?<![\w-])' + [regex]::Escape($_) + '(?:\s*\])?\s+arg(?![\w-])') })
            if ($noArg.Count) {
                throw "「wraptool help」里 $($noArg -join ', ') 没有标成带值的选项(arg),本脚本却要给它传值:wraptool 版本与本脚本不符"
            }
            Add-Check '5c wraptool flag' 'PASS' ($need -join ' ')
        } catch { Add-Check '5c wraptool flag' 'FAIL' $_.Exception.Message }
    } else {
        Add-Check '5c wraptool flag' 'SKIP' $(if (-not $script:Wraptool) { 'wraptool 不可用' } else { 'PACE_FUSION_HOME 未就绪(见预检 5a)' })
    }

    # ---------------------------------------------------------------- 预检 5d:signtool
    # 实测 6.0.1(2026-10-08):不给 --signtool 时 wraptool 在它的「默认位置」找不到 Windows SDK 10.0.19041 的 signtool,报
    # "Can't sign with the certificate identified by the thumbprint ..." —— 看着像证书问题,其实是没找到 signtool。签名时一律显式传
    try {
        $src = $null
        if ($SignToolPath) {
            $p = Resolve-UserPath $SignToolPath
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "-SignToolPath 指向的文件不存在:$p" }
            $script:SignTool = $p; $src = '-SignToolPath'
        } elseif ($p = Find-SignToolInKits) {
            $script:SignTool = $p; $src = "%ProgramFiles(x86)%\$KitsBinRel 下版本号最高的"
        } elseif ($cmd = Get-Command signtool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $script:SignTool = $cmd.Source; $src = 'PATH'
        } else {
            throw ("找不到 signtool.exe:%ProgramFiles(x86)%\$KitsBinRel\<版本>\$SignToolRel 与 PATH 都没有。装 Windows SDK 时勾选" +
                '「Windows SDK Signing Tools for Desktop Apps」组件,或用 -SignToolPath <signtool.exe> 指定')
        }
        $stVer = (Get-Item -LiteralPath $script:SignTool).VersionInfo.ProductVersion
        Add-Check '5d signtool' 'PASS' "$($script:SignTool)(来自 $src;版本 $(if ($stVer) { $stVer } else { '未知' }))"
    } catch { $script:SignTool = $null; Add-Check '5d signtool' 'FAIL' $_.Exception.Message }

    # ---------------------------------------------------------------- 预检 6:iLok(只提醒)
    # 实测 6.0.1(2026-10-08):iLok 上还没有签名证书时报 AuthorizationException::CouldNotFindSignerCredentials,在 iLok License
    # Manager 里对 iLok 做一次 Synchronize 即可(之后 iLok 详情里出现 "Digital Signing Certified Expires ...")
    Add-Check '6 iLok' 'INFO' ('签名需要插着带签名授权的 iLok(或已激活 iLok Cloud 会话)并运行 iLok License Manager;本脚本不硬检。' +
        'wraptool 报 CouldNotFindSignerCredentials 时,在 iLok License Manager 里对这个 iLok 做一次 Synchronize 再重跑')

    # ---------------------------------------------------------------- 预检 7:解压 + 输入件确实未签名
    $inBundle = $null
    $outBundle = $null
    $inDll = $null
    $outDll = $null
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
            $outDll = Join-Path $outBundle $DllRel
            if (-not (Test-Path -LiteralPath $inBundle -PathType Container)) { throw "zip 根目录下没有 '$BundleName'" }
            $inDll = Join-Path $inBundle $DllRel
            if (-not (Test-Path -LiteralPath $inDll -PathType Leaf)) { throw "bundle 缺 $DllRel" }
            $inSig = Get-AuthenticodeSignature -LiteralPath $inDll
            if ([string]$inSig.Status -ne 'NotSigned') {
                throw "输入 DLL 的 Authenticode 状态是 $($inSig.Status)(应为 NotSigned):输入件已签过或被改过,拒绝"
            }
            Add-Check '7a 输入 bundle' 'PASS' "已解压到 $inDir;内层 DLL = NotSigned"
            $bundleOk = $true
        } catch { Add-Check '7a 输入 bundle' 'FAIL' $_.Exception.Message }

        if ($bundleOk -and $script:Wraptool -and $env:PACE_FUSION_HOME) {
            try {
                # 实测 6.0.1(2026-10-08):Windows 上 --in 必须是文件(给 bundle 目录报 "A file must be specified for the
                # 'verify' operation on Windows");未签名 DLL → 退出码 2,输出 "The architecture is NOT signed"。只看退出码非零
                # 会把别的失败(PACE_FUSION_HOME 缺失、参数错误)当成「未签名」,所以同时要求输出里有 NOT signed。
                # 区分大小写:「not signed in」一类的未登录报错不能算
                $v = Invoke-Wraptool @('verify', '--in', $inDll) -Capture
                if ($v.ExitCode -eq 0) { throw "wraptool verify 对输入 DLL 返回成功 —— 它已经签过(重签会报错),中止" }
                if ($v.Output -cnotmatch 'NOT signed') {
                    $tail = @($v.Output -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
                    throw "wraptool verify 失败(exit $($v.ExitCode)),但输出里没有 NOT signed,失败原因不是「未签名」:$tail"
                }
                Add-Check '7b wraptool verify' 'PASS' "按预期失败(exit $($v.ExitCode),输出 NOT signed):输入 DLL 未签名"
            } catch { Add-Check '7b wraptool verify' 'FAIL' $_.Exception.Message }
        } else {
            Add-Check '7b wraptool verify' 'SKIP' $(if (-not $bundleOk) { '输入 bundle 未就绪' } elseif (-not $script:Wraptool) { 'wraptool 不可用' } else { 'PACE_FUSION_HOME 未就绪' })
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

    # 签名命令的打码版(回显用)
    $wtShow = Get-SignArgs $(if ($outDll) { $outDll } else { "<work>\out\$BundleName\$DllRel" }) -Masked

    if ($DryRun) {
        Write-Host ''
        Write-Host '[DryRun] 签名计划(未执行):'
        Write-Host $(if ($SourceRunId) { "  0) 来源已按 run $SourceRunId 核对(见预检 3b)" } else { '  0) 未给 -SourceRunId:来源未核对(只验了完整性)' })
        Write-Host ("  1) 复制整个 bundle:{0} → {1},核对逐文件相同;之后只对 out 里的内层 DLL 原地签名" -f `
            $(if ($inBundle) { $inBundle } else { "<work>\in\$BundleName" }), $(if ($outBundle) { $outBundle } else { "<work>\out\$BundleName" }))
        if ($CertThumbprint) {
            Write-Host ("  2) 签名身份:{0}\{1} —— 不读证书口令,wraptool 命令行上没有 --keypassword" -f `
                $(if ($certWhere) { $certWhere } else { '<个人证书库>' }), $certThumb)
        } else {
            Write-Host '  2) 签名身份:Read-Host -AsSecureString 读 pfx 口令(不进本脚本参数 / 日志 / transcript),载入 pfx 取指纹并确认带私钥、未过期'
            Write-Host '     注意:签名那几秒 pfx 口令会以 --keypassword 出现在 wraptool 进程命令行里(wraptool 的限制),签名期间不要让他人登录本机'
        }
        if ($PromptAccountPassword) {
            Write-Host '     另读 PACE 账号口令,经 --pswd-no-save 传(不写进 wraptool 钥匙串;签名那几秒同样出现在 wraptool 进程命令行里)'
        } else {
            Write-Host ('     不传账号口令:wraptool 用它钥匙串里存过的口令,或 iLok License Manager 默认账号的会话(-WcGuid 方式要连 PACE ' +
                '服务器;连不上就先手动 sync 一次,见 docs/release.md §7.1)')
        }
        Write-Host ("  3) wraptool " + (Format-CommandLine $wtShow))
        Write-Host ('  4) 后检:wraptool verify --verbose --in <out DLL> 退出码 0;out 与 in 只有内层 DLL 不同;Authenticode 签名者指纹 = ' +
            $(if ($CertThumbprint) { '-CertThumbprint' } else { 'pfx 指纹' }) + ';' +
            $(if ($LegacySha1Digest) { '文件 / 签名者摘要 SHA1' } else { '文件 / 签名者摘要 SHA256' }) + ';' +
            $(if ($AllowNoTimestamp) { '时间戳缺失放行(-AllowNoTimestamp)' } else { '必须带时间戳' }) +
            $(if ($LegacySha1Digest) { '' } else { '(带了就必须是 RFC 3161 / SHA256)' }))
        Write-Host ("  5) package-aax.ps1 -Mode Signed -Version {0} -SourceRef {1} -BundlePath <out bundle> -OutDir {2}" -f `
            $(if ($ver) { $ver } else { '<版本>' }), $(if ($sourceRef) { $sourceRef } else { '<SourceRef>' }), $OutDirFull)
        Write-Host '  6) 回读:把产出的 zip 解到新临时目录,复验 bundle 与 out 逐文件相同、wraptool verify、签名者指纹与摘要算法'
        if ($isCiBuild) {
            Write-Host "  7) 版本 $ver 是 CI 预发布件,没有对应 Release:只打印提示,不给上传命令"
        } else {
            Write-Host ("  7) 打印(不执行):gh release upload v{0} <zip> <zip>.sha256 --repo {1}" -f $(if ($ver) { $ver } else { '<版本>' }), $UploadRepo)
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
        # 整个 bundle 复制到 out(-Force:带 System 属性的 desktop.ini 也要拷),核对与 in 逐文件相同;in 从此不再动
        Copy-Item -LiteralPath $inBundle -Destination $outBundle -Recurse -Force
        Assert-SameBundle $inBundle $outBundle '复制'

        if ($KeyFile) {
            # pfx 口令:只经交互读入,SecureString 全程;载入 pfx 同时验证口令、取预期指纹(EphemeralKeySet:私钥不落盘)
            $kp = Read-Host -AsSecureString '代码签名证书 (.pfx) 口令'
            try {
                $pfx = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($keyFull, $kp,
                    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
            } catch {
                throw "载入 pfx 失败(口令错误或文件损坏 / 加密算法不受支持,见 V8):$($_.Exception.Message)"
            }
            try {
                $expectThumb = $pfx.Thumbprint
                if (-not $pfx.HasPrivateKey) { throw "pfx 里没有私钥:$keyFull" }
                if ($pfx.NotAfter -lt (Get-Date)) { throw "证书已于 $($pfx.NotAfter) 过期" }
                if ((Get-EkuOids $pfx) -notcontains $CodeSigningEku) { Write-Warning "证书没有 Code Signing EKU($CodeSigningEku);wraptool 可能拒收" }
                Write-Host "pfx: Subject=$($pfx.Subject) Thumbprint=$expectThumb NotAfter=$($pfx.NotAfter)"
            } finally {
                $pfx.Dispose()
            }
        }
        if ($PromptAccountPassword) { $ap = Read-Host -AsSecureString 'PACE 账号口令(经 --pswd-no-save 传,不存钥匙串)' }

        $bstrK = [IntPtr]::Zero
        $bstrA = [IntPtr]::Zero
        $plainK = $null
        $plainA = $null
        $wtArgs = $null
        try {
            # BSTR → 明文只在这次调用期间存在;finally 里 ZeroFreeBSTR + 置空引用
            if ($kp) {
                $bstrK = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($kp)
                $plainK = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrK)
            }
            if ($ap) {
                $bstrA = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ap)
                $plainA = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrA)
            }
            $wtArgs = Get-SignArgs $outDll -KeyPw $plainK -AccountPw $plainA
            # 实测 6.0.1:--verbose 会回显 wcguid 与 signtool 命令行(-KeyFile 方式下可能含 pfx 口令)—— 口令 / 账号 / wcguid /
            # customer number 一律打码
            $sign = Invoke-Wraptool $wtArgs -Display $wtShow -Redact @($plainK, $plainA, $Account, $WcGuid, $CustomerNumber)
        } finally {
            if ($bstrK -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrK) }
            if ($bstrA -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrA) }
            $plainK = $null
            $plainA = $null
            $wtArgs = $null
        }
        if ($sign.ExitCode -ne 0) { throw "wraptool sign 失败(exit $($sign.ExitCode))" }

        # ================================================================ 后检
        function Assert-SignedBundle([string]$Bundle, [string]$Label) {
            $dll = Join-Path $Bundle $DllRel
            if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "${Label}:缺 $DllRel" }
            # 实测 6.0.1(2026-10-08):已签名 DLL 的 verify 退出码 0,输出 "The digital signature was verified"
            $vr = Invoke-Wraptool @('verify', '--verbose', '--in', $dll) -Redact @($Account, $WcGuid, $CustomerNumber)
            if ($vr.ExitCode -ne 0) { throw "${Label}:wraptool verify 失败(exit $($vr.ExitCode))" }
            $sig = Get-AuthenticodeSignature -LiteralPath $dll
            if ($null -eq $sig.SignerCertificate) { throw "${Label}:DLL 没有 Authenticode 签名(Status=$($sig.Status))" }
            # 自签名证书的链不受信任,Status 是 UnknownError(实测),属预期;只拦这几种「签名本身坏了」的状态
            if (@('NotSigned', 'HashMismatch', 'NotSupportedFileFormat') -contains [string]$sig.Status) {
                throw "${Label}:Authenticode 签名不完好(Status=$($sig.Status))"
            }
            if ($sig.SignerCertificate.Thumbprint -ne $expectThumb) {
                throw "${Label}:签名者指纹 $($sig.SignerCertificate.Thumbprint) ≠ 预期指纹 $expectThumb"
            }
            $dg = Get-AuthenticodeDigest $dll
            $wantDigest = if ($LegacySha1Digest) { 'sha1' } else { 'sha256' }
            if ($dg.FileDigest -cne $wantDigest -or $dg.SignerDigest -cne $wantDigest) {
                $hint = if ($LegacySha1Digest) { '-LegacySha1Digest 走 wraptool 默认的 signtool 命令,6.0.1 实测为 SHA1;它的默认变了就去掉这个开关' }
                        else { '--explicitsigningoptions 没按预期生效,查 wraptool 回显的 signtool 命令行' }
                throw "${Label}:摘要算法是文件 $($dg.FileDigest) / 签名者 $($dg.SignerDigest),预期都是 $wantDigest($hint)"
            }
            if ($null -eq $sig.TimeStamperCertificate) {
                # V3:拿不到时间戳也不要事后用 signtool 补 —— 那会改动已签名的文件,签名必须是最后一次修改
                if ($AllowNoTimestamp) { Write-Warning "${Label}:Authenticode 签名没有时间戳(-AllowNoTimestamp 放行;证书过期后签名随之失效)" }
                else { throw "${Label}:Authenticode 签名没有时间戳(V3:wraptool 默认就加时间戳,查它的输出;确实拿不到时显式传 -AllowNoTimestamp)" }
            } elseif (-not $LegacySha1Digest -and
                ($dg.Timestamp -cne 'RFC3161' -or $dg.TimestampDigest -cne 'sha256' -or -not $dg.TimestampVerified)) {
                throw ("${Label}:时间戳应为 RFC 3161、摘要 SHA256 且与签名对得上,实际:$($dg.Timestamp) / " +
                    "$(if ($dg.TimestampDigest) { $dg.TimestampDigest } else { '-' }) / 核对$(if ($dg.TimestampVerified) { '通过' } else { '未通过' })")
            }
            Write-Host ("$Label OK:Status=$($sig.Status) Signer=$($sig.SignerCertificate.Subject) Thumbprint=$($sig.SignerCertificate.Thumbprint) " +
                "Digest=$($dg.FileDigest) Timestamp=$($dg.Timestamp)$(if ($dg.TimestampDigest) { '/' + $dg.TimestampDigest })")
        }
        # wraptool 只该改内层 DLL:bundle 里多出 / 少了文件(例如原地签名留下的临时文件)或别的文件被改,都不能进发行包
        Assert-SameBundle $inBundle $outBundle '后检' -AllowDllChange
        Assert-SignedBundle $outBundle '后检'

        # 打包:Signed 模式会再做一遍 Authenticode 断言与 zip 回读比对字节;独立 pwsh 进程,状态与本脚本隔离
        & $pwshExe -NoProfile -NonInteractive -File $pkgScript -Mode Signed -Version $ver -SourceRef $sourceRef `
            -BundlePath $outBundle -OutDir $OutDirFull
        if ($LASTEXITCODE -ne 0) { throw "package-aax.ps1 -Mode Signed 失败(exit $LASTEXITCODE)" }
        if (-not (Test-Path -LiteralPath $signedZip -PathType Leaf)) { throw "打包后找不到 $signedZip" }
        $packaged = $true   # 从这里起失败,finally 删掉本次的发行名 zip / .sha256(打包脚本自己的失败路径由它自己清理)

        # 回读:产出的 zip 解到新临时目录,bundle 必须与签好的 out 逐文件相同,再复验 wraptool verify 与指纹(发出去的字节还带着签名)
        $rb = Join-Path $work 'readback'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($signedZip, $rb)
        Assert-SameBundle $outBundle (Join-Path $rb $BundleName) '回读'
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
    if ($fusionAdded) { Remove-Item -Path Env:PACE_FUSION_HOME -ErrorAction SilentlyContinue }
    if ($work -and (Test-Path -LiteralPath $work)) {
        if ($succeeded) {
            Remove-Item -LiteralPath $work -Recurse -Force
        } else {
            Write-Host "工作目录已保留供排查(里面只有 bundle,没有秘密):$work" -ForegroundColor Yellow
        }
    }
}
exit $exitCode
