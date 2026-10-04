<#
.SYNOPSIS  生成 AAX Windows 签名用的自签名代码签名证书,并把 pfx 导出到仓库外。维护者本机一次性操作。
.DESCRIPTION
  Pro Tools 加载 AAX 靠的是 PACE 签名;wraptool 在 Windows 上还要一张 Authenticode 代码签名证书(.pfx)。
  本项目用自签名证书:文件「属性 → 数字签名」里显示签名者不受信任属预期。生成的 pfx 交给
  scripts/sign-aax.ps1 -KeyFile 使用。

  先用 -WhatIf 预演:只做参数与路径断言并打印将要执行的操作 —— 不读口令、不写证书库、不生成任何文件。
  真跑(ConfirmImpact = High,会先要求确认)时:
    1. 两次读入 pfx 口令(Read-Host -AsSecureString,一致且至少 12 位);
    2. New-SelfSignedCertificate 在 Cert:\CurrentUser\My 生成证书(RSA 3072 / SHA256 / 私钥可导出);
    3. Export-PfxCertificate 导出(默认 AES256_SHA256;wraptool 读不了时用 -PfxEncryption TripleDES_SHA1 重新生成,V8);
    4. 用同一口令 Get-PfxData 回读,指纹必须一致;
    5. -RemoveFromStore 时把证书连同私钥从证书库删掉(此后只剩 pfx 这一份)。
  断言:Windows;-OutPfx 的完整路径不在仓库目录下;-OutPfx 不存在(除非 -Force);-Subject 不含邮箱。

  语法保持 Windows PowerShell 5.1 兼容(不用 ?? / 三元运算符 / -AsHashtable):pwsh 7 里若 PKI cmdlet 不可用或
  导出失败,改用 `powershell.exe -File scripts/new-selfsigned-codesign-cert.ps1` 运行(V7,TO-VALIDATE)。
  本文件以 UTF-8 BOM 保存:5.1 读无 BOM 的脚本按系统 ANSI 代码页解码,中文会乱码、甚至吞掉相邻的引号。
.PARAMETER OutPfx
  pfx 输出路径,默认 $env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx;必须在仓库外,扩展名 .pfx / .p12。
.PARAMETER Subject
  证书主题,默认 'CN=Synchain Bridge AAX Code Signing (self-signed)';必须以 CN= 开头,不得含邮箱。
.PARAMETER Years
  有效期(年),默认 10。
.PARAMETER PfxEncryption
  pfx 加密算法:AES256_SHA256(默认)或 TripleDES_SHA1(V8:wraptool 读不了 AES 加密的 pfx 时用)。
.PARAMETER RemoveFromStore
  导出并回读成功后,把证书连同私钥从 Cert:\CurrentUser\My 删除。
.PARAMETER Force
  允许覆盖已存在的 -OutPfx。
.EXAMPLE
  pwsh scripts/new-selfsigned-codesign-cert.ps1 -WhatIf
.EXAMPLE
  powershell.exe -File scripts/new-selfsigned-codesign-cert.ps1 -RemoveFromStore
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$OutPfx = '',
    [string]$Subject = 'CN=Synchain Bridge AAX Code Signing (self-signed)',
    [ValidateRange(1, 30)][int]$Years = 10,
    [ValidateSet('AES256_SHA256', 'TripleDES_SHA1')][string]$PfxEncryption = 'AES256_SHA256',
    [switch]$RemoveFromStore,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 1) 平台:Windows PowerShell 5.1 只跑在 Windows 上、也没有 $IsWindows;pwsh 7 读 $IsWindows
$onWindows = $true
if ($PSVersionTable.PSEdition -eq 'Core') {
    $onWindows = [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}
if (-not $onWindows) { throw '只支持 Windows(New-SelfSignedCertificate 与 Cert:\ 证书库是 Windows 专有);macOS 用钥匙串身份签名' }

# Cert: 驱动器由 Microsoft.PowerShell.Security 提供。从 pwsh 7 里启动的 powershell.exe 会继承 pwsh 的 PSModulePath,
# 自动加载挑到 pwsh 版本的同名模块而失败,Cert: 就不存在 —— 按 $PSHOME 显式加载当前版本自带的那一份(只读操作)
if (-not (Test-Path -Path 'Cert:\')) {
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security') -ErrorAction SilentlyContinue
}
if (-not (Test-Path -Path 'Cert:\CurrentUser\My')) {
    throw 'Cert: 驱动器不可用(Microsoft.PowerShell.Security 未加载):在新开的 PowerShell 窗口里重试'
}

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-GitTop([string]$Dir) {
    # 5.1 下 EAP=Stop 遇到外部命令的 stderr 会抛 NativeCommandError,局部降为 Continue,只看退出码
    $ErrorActionPreference = 'Continue'
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return $null }
    $out = & git -C $Dir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return [System.IO.Path]::GetFullPath([string]@($out)[0]).TrimEnd('\')
}

# pfx 不得落在仓库目录下(CLAUDE.md §0 铁律 1)。两道判定:完整路径前缀(不区分大小写);
# git 兜底 —— 目录经 junction / subst 指进仓库时前缀比较看不出来,git 会解析到真实工作树。
function Test-InsideRepo([string]$FullPath) {
    $root = $RepoRoot.TrimEnd('\', '/')
    if ($FullPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $FullPath.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $repoTop = Invoke-GitTop $RepoRoot
    if (-not $repoTop) { return $false }
    $dir = Split-Path -Parent $FullPath
    while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path -Parent $dir }
    if (-not $dir) { return $false }
    $top = Invoke-GitTop $dir
    return ($top -and $top.Equals($repoTop, [System.StringComparison]::OrdinalIgnoreCase))
}

# 两个 SecureString 逐字符比较,不经托管明文字符串;BSTR 用完即 ZeroFreeBSTR
function Test-SecureStringEqual([System.Security.SecureString]$A, [System.Security.SecureString]$B) {
    if ($A.Length -ne $B.Length) { return $false }
    $pa = [IntPtr]::Zero
    $pb = [IntPtr]::Zero
    try {
        $pa = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($A)
        $pb = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($B)
        $diff = 0
        for ($i = 0; $i -lt $A.Length; $i++) {
            $diff = $diff -bor ([System.Runtime.InteropServices.Marshal]::ReadInt16($pa, $i * 2) -bxor
                [System.Runtime.InteropServices.Marshal]::ReadInt16($pb, $i * 2))
        }
        return ($diff -eq 0)
    } finally {
        if ($pa -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pa) }
        if ($pb -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pb) }
    }
}

# 2) OutPfx:默认走环境变量,不写字面的本机用户路径
if ($PSBoundParameters.ContainsKey('OutPfx') -and -not $OutPfx) { throw '-OutPfx 传入空串' }
if (-not $OutPfx) {
    if (-not $env:USERPROFILE) { throw '环境变量 USERPROFILE 为空,请显式传 -OutPfx' }
    $OutPfx = Join-Path $env:USERPROFILE '.synchain-signing\synchain-aax-codesign.pfx'
}
$OutPfx = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutPfx))
if (@('.pfx', '.p12') -notcontains [System.IO.Path]::GetExtension($OutPfx).ToLowerInvariant()) {
    throw "-OutPfx 的扩展名必须是 .pfx 或 .p12:$OutPfx"
}
if (Test-InsideRepo $OutPfx) {
    throw "-OutPfx 位于仓库目录内($OutPfx):pfx 必须放在仓库外(CLAUDE.md §0 铁律 1)"
}
if ((Test-Path -LiteralPath $OutPfx) -and -not $Force) {
    throw "$OutPfx 已存在:确认要覆盖就加 -Force(旧 pfx 先备份;覆盖后用旧证书签过的件指纹会对不上)"
}

# 3) Subject:不得含邮箱(会命中 gitleaks 的 non-org-email 规则,也没必要把邮箱写进证书)
if ($Subject -notmatch '^CN=') { throw "-Subject 必须以 CN= 开头:$Subject" }
if ($Subject -match '@') { throw "-Subject 不得含邮箱:$Subject" }

# 4) PKI cmdlet(V7,TO-VALIDATE:pwsh 7 下经 Windows PowerShell 兼容层加载时证书对象能否直接传给 Export-PfxCertificate)
foreach ($c in @('New-SelfSignedCertificate', 'Export-PfxCertificate', 'Get-PfxData')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
        throw "找不到 $c(PKI 模块):改用 powershell.exe -File scripts/new-selfsigned-codesign-cert.ps1 运行"
    }
}

$notAfter = (Get-Date).AddYears($Years)
$plan = "在 Cert:\CurrentUser\My 生成自签名代码签名证书($Subject;RSA 3072 / SHA256;私钥可导出;有效期至 " +
    $notAfter.ToString('yyyy-MM-dd') + "),以 $PfxEncryption 导出 pfx"
if ($RemoveFromStore) { $plan += ',导出并回读后从证书库删除证书与私钥' }

# 唯一的写操作闸门:-WhatIf(或确认时答 No)到此为止 —— 不读口令、不写证书库、不生成文件
if (-not $PSCmdlet.ShouldProcess($OutPfx, $plan)) {
    Write-Host '未执行任何写操作:没有读取口令、没有写入证书库、没有生成 pfx。'
    return
}

# 5) 口令:两次输入一致、至少 12 位;全程 SecureString
$pw = Read-Host -AsSecureString 'pfx 口令(至少 12 位)'
$pw2 = Read-Host -AsSecureString '再输入一次'
try {
    if ($pw.Length -lt 12) { throw 'pfx 口令至少 12 位' }
    if (-not (Test-SecureStringEqual $pw $pw2)) { throw '两次输入的口令不一致' }
} finally {
    $pw2.Dispose()
}

$dir = Split-Path -Parent $OutPfx
if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Path $dir -Force -Confirm:$false | Out-Null
}

$cert = $null
$tmpPfx = $OutPfx + '.tmp-' + [guid]::NewGuid().ToString('N')
try {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject -KeyAlgorithm RSA -KeyLength 3072 `
        -HashAlgorithm SHA256 -KeyExportPolicy Exportable -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter $notAfter -Confirm:$false
    # 先导出到同目录临时文件、回读核对指纹后再替换目标:-Force 覆盖时导出失败不会把旧 pfx 弄丢
    Export-PfxCertificate -Cert $cert -FilePath $tmpPfx -Password $pw -CryptoAlgorithmOption $PfxEncryption -Confirm:$false | Out-Null
    $pfxData = Get-PfxData -FilePath $tmpPfx -Password $pw
    $thumbs = @($pfxData.EndEntityCertificates | ForEach-Object { $_.Thumbprint })
    if ($thumbs -notcontains $cert.Thumbprint) {
        throw "导出的 pfx 回读指纹($($thumbs -join ', '))与证书库里的($($cert.Thumbprint))不一致"
    }
    Move-Item -LiteralPath $tmpPfx -Destination $OutPfx -Force -Confirm:$false
} catch {
    if (Test-Path -LiteralPath $tmpPfx) { Remove-Item -LiteralPath $tmpPfx -Force -Confirm:$false }
    if ($cert) {
        Write-Warning ("证书已写入 Cert:\CurrentUser\My(指纹 $($cert.Thumbprint)),但导出 / 回读失败。清理:" +
            "Remove-Item Cert:\CurrentUser\My\$($cert.Thumbprint) -DeleteKey")
    }
    throw
} finally {
    $pw.Dispose()
}

if ($RemoveFromStore) {
    # -DeleteKey 是证书提供程序的动态参数,随 -Path 解析出提供程序后才可用(指纹是纯 hex,不含通配符)
    Remove-Item -Path ('Cert:\CurrentUser\My\' + $cert.Thumbprint) -DeleteKey -Confirm:$false
    Write-Host '已从 Cert:\CurrentUser\My 删除证书与私钥:此后 pfx 是唯一副本。'
} else {
    Write-Host "证书仍在 Cert:\CurrentUser\My(指纹 $($cert.Thumbprint));不需要时用 Remove-Item ... -DeleteKey 删除。"
}

Write-Host ''
Write-Host "Thumbprint : $($cert.Thumbprint)"
Write-Host "NotAfter   : $($cert.NotAfter.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Pfx        : $OutPfx($PfxEncryption)"
Write-Host ''
Write-Host '提醒:把 pfx 和口令备份到密码管理器;绝不入库、不进 CI、不进 artifact。'
Write-Host '签名用法:pwsh scripts/sign-aax.ps1 -UnsignedZip <...-win64-UNSIGNED.zip> -Account <PACE 账号> -WcGuid <GUID> -KeyFile <上面的 Pfx 路径>'
