<#
.SYNOPSIS  Synchain Bridge 本地质量门禁 —— 提子 PR 前必须全绿(单 bundle)。
.DESCRIPTION
  结构同 06 §5.1,但只有一个 bundle;额外含 vcpkg ixwebsocket 预检(gate 1;仓库根有 vcpkg.json 时按
  manifest 模式验 baseline 与依赖声明,依赖本身由 configure 期的 vcpkg toolchain 自动安装)、
  端口 9420 一致性检查(gate 3d:src/BridgeApi.h ↔ web/bridge.js ↔ web-preview/mock-server.mjs)、
  版本一致性检查(gate 3e:CMakeLists.txt project(VERSION) ↔ web-preview 的 mock-server.mjs /
  package.json / package-lock.json ↔ BRIDGE_CONTRACT.md §三 VERSION 行)、
  ixwebsocket 两平台版本一致性(gate 3g:vcpkg.json override ↔ CMakeLists.txt IXWEBSOCKET_TAG 注释,与 compliance.yml 同参)、
  vcpkg 安装版本断言(gate 4b:configure 后 <BuildDir>/vcpkg_installed/vcpkg/status ↔ vcpkg.json override 与
  THIRD-PARTY-NOTICES.md,经 scripts/assert-vcpkg-installed.ps1 与 ci.yml / release.yml 共用同一份逻辑)、
  字体 name 表 RFN 断言(gate 3b2,与 compliance.yml 同参)、PCM 帧头组帧接线断言(gate 3f:
  src/VstBridgeServer.cpp 必须经 src/PcmFrame.h 组帧,与 compliance.yml 同构)与零依赖纯逻辑自测
  (gate 5b:Origin 白名单 + PCM 帧头 golden,与 compliance.yml 同源同用例)。
  签名材料 / Avid 评估工具不入库(gate 3h:pfx/p12/pvk、DigiShell / AAX Validator、测试计划 PDF;只读、秒级,恒跑)。
  -IncludeAax 时另跑 AAX 三道 gate(selftest 之后、pluginval 之前):5c bundle 结构(PE x64 / desktop.ini / Plugin.ico)、
  5d 打包冒烟(scripts/package-aax.ps1 Unsigned + Signed 反向断言)、5e AAX Validator(可选,需 -AaxValidatorPath)。
  任一 gate FAIL 即以非零码退出,最后打印一张可直接粘进 PR 描述的表格。
.EXAMPLE   pwsh scripts/gates.ps1                         # 全量(含 GUI pluginval)
.EXAMPLE   pwsh scripts/gates.ps1 -PluginOnly             # 跳过 GUI pluginval(与 CI 等价)
.EXAMPLE   pwsh scripts/gates.ps1 -Quick                  # 跳过 pluginval,快速回环
.EXAMPLE   pwsh scripts/gates.ps1 -BuildDir build-B11     # 并行 agent:各用各的构建目录
.EXAMPLE   pwsh scripts/gates.ps1 -PluginOnly -IncludeAax -BuildDir build-aax   # 加跑 AAX gate 5c/5d/5e
.EXAMPLE   pwsh scripts/gates.ps1 -PluginOnly -AaxValidatorPath "$env:USERPROFILE\avid-tools\<解压目录>\dsh.exe"
           # 给了 Validator 路径即隐含 -IncludeAax;工具必须放仓库外(Avid 评估许可,不入库)
#>
[CmdletBinding()]
param(
    [switch]$Quick,          # 跳过 pluginval(gate 6/7)
    [switch]$PluginOnly,     # 跳过 GUI pluginval(gate 7)
    [string]$Config   = 'Release',
    [string]$JucePath = $env:JUCE_PATH,
    [string]$BuildDir = 'build',
    # 新参数一律追加在末尾:脚本参数默认按声明顺序可按位置绑定,插在中间会让既有的按位置调用错绑
    [switch]$IncludeAax,             # 跑 AAX gate 5c/5d/5e(默认关;gate 3h 不受此开关控制,恒跑)
    [string]$AaxValidatorPath = ''   # Avid AAX Validator(DigiShell)可执行文件,必须在仓库外;给了即隐含 -IncludeAax
)

$ErrorActionPreference = 'Stop'

# -AaxValidatorPath 给了即隐含 -IncludeAax。「显式传了空串」同样算给了:那是调用方没算出路径(例如引用了未设置的
# 环境变量),静默 SKIP 等于把 5e 从门禁里悄悄删掉 —— 交给 5e 报 FAIL(与 package-aax.ps1 拒收空串同一纪律)。
$AaxValidatorGiven = $PSBoundParameters.ContainsKey('AaxValidatorPath')
$RunAax = $IncludeAax.IsPresent -or $AaxValidatorGiven

# ---- gate 5e 的 AAX Validator 调用常量 ----
# TODO-AAXVAL(owner 实测后填写):三个常量要等 owner 拿到 Avid 评估工具、按 docs/build-windows.md 的 AAX Validator
# 探查步骤实测出非交互调用方式与判据后回填,填完删掉本标记。任一为 $null 时 gate 5e 恒 SKIP
# 「TODO-AAXVAL:调用方式未实测」—— 宁可 SKIP,绝不假绿。
#   AaxValidatorArgs        —— 传给 -AaxValidatorPath 的参数数组;其中的 '{bundle}' 替换为待测 .aaxplugin 目录的绝对路径。
#                              若工具只能交互或只认脚本文件:改成先把命令写进 $BuildDir 下的临时脚本,再在这里传
#                              脚本路径,gate 结构不变。
#   AaxValidatorPassPattern —— 输出里出现即视为通过的标记(.NET 正则,Multiline,大小写敏感)。
#   AaxValidatorFailPattern —— 输出里出现即判失败的标记(同上),优先于 PassPattern。
# 判定与 auval 同口径:以输出标记为准,退出码只记进结果明细作参考。只记录我们自己写的命令和判据,不抄 Avid 文档原文。
$script:AaxValidatorArgs        = $null   # TODO-AAXVAL(owner 实测后填写),形如 @('<子命令>', '{bundle}')
$script:AaxValidatorPassPattern = $null   # TODO-AAXVAL(owner 实测后填写)
$script:AaxValidatorFailPattern = $null   # TODO-AAXVAL(owner 实测后填写)

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string]$p) {
    if ($p -match '^([a-zA-Z]:[\\/]|\\\\|/)') { return $p }
    return (Join-Path $RepoRoot $p)
}
$BuildDir = Resolve-RepoPath $BuildDir

# ---- 结果收集 ----
$script:results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$name, [string]$result, [string]$detail) {
    $script:results.Add([pscustomobject]@{ Name = $name; Result = $result; Detail = $detail })
    $color = if ($result -eq 'PASS') { 'Green' } elseif ($result -eq 'FAIL') { 'Red' } else { 'Yellow' }
    Write-Host ('[' + $result + '] ' + $name) -ForegroundColor $color
    if ($detail -and $result -ne 'PASS') { Write-Host ('      ' + $detail) -ForegroundColor $color }
}

# ---- 公共:CMake 生成器自动探测(VS2022 优先,VS2019 亦可) ----
function Get-CMakeGenerator {
    $pfx86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $vswhere = Join-Path $pfx86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $v = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion
    if ($v -match '^17\.') { return 'Visual Studio 17 2022' }
    if ($v -match '^16\.') { return 'Visual Studio 16 2019' }
    return $null
}

# ---- gate 1:依赖预检 ----
function Test-Deps {
    $ok = $true
    $detail = ''

    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $cmake) { $ok = $false; $detail += 'cmake 不在 PATH; ' }
    else {
        $cv = (& cmake --version | Select-Object -First 1)
        if ($cv -match 'version\s+(\d+)\.(\d+)') {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2]
            if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 22)) { $ok = $false; $detail += ('cmake ' + $maj + '.' + $min + ' < 3.22; ') }
        }
    }

    if (-not (Get-CMakeGenerator)) { $ok = $false; $detail += '未找到 VS2022/VS2019 VC 工具集; ' }

    $juceVer = (Get-Content (Join-Path $RepoRoot '.juce-version') -Raw).Trim()
    if (-not $JucePath) { $ok = $false; $detail += 'JUCE_PATH 未设置; ' }
    elseif (-not (Test-Path (Join-Path $JucePath 'CMakeLists.txt'))) { $ok = $false; $detail += 'JUCE_PATH 不是 JUCE 根目录; ' }
    else {
        $jv = (git -C $JucePath describe --tags 2>$null).Trim()
        if ($jv -ne $juceVer) { $ok = $false; $detail += ('JUCE "' + $jv + '" != ' + $juceVer + '; ') }
    }

    $cf = Get-Command clang-format -ErrorAction SilentlyContinue
    if (-not $cf) { $ok = $false; $detail += 'clang-format 不在 PATH; ' }
    else {
        $cfv = (& clang-format --version)
        if ($cfv -notmatch '18\.1\.8') { $ok = $false; $detail += ('clang-format "' + $cfv + '" != 18.1.8; ') }
    }

    $pv = Get-Command pluginval -ErrorAction SilentlyContinue
    $pvVer = (Get-Content (Join-Path $RepoRoot '.pluginval-version') -Raw).Trim()
    if (-not $pv) { $ok = $false; $detail += 'pluginval 不在 PATH; ' }
    else {
        $pvv = (& pluginval --version 2>&1 | Select-Object -First 1)
        if ($pvv -notmatch ([regex]::Escape($pvVer.TrimStart('v')))) { $ok = $false; $detail += ('pluginval 版本与 .pluginval-version ' + $pvVer + ' 不一致; ') }
    }

    $vcpkgRoot = $env:VCPKG_ROOT
    if (-not $vcpkgRoot) { $ok = $false; $detail += 'VCPKG_ROOT 未设置; ' }
    elseif (-not (Test-Path (Join-Path $vcpkgRoot 'scripts\buildsystems\vcpkg.cmake'))) { $ok = $false; $detail += 'VCPKG_ROOT 下无 scripts/buildsystems/vcpkg.cmake; ' }
    else {
        $manifest = Join-Path $RepoRoot 'vcpkg.json'
        if (Test-Path $manifest) {
            # manifest 模式(仓库根有 vcpkg.json):ixwebsocket 不再由人手 `vcpkg install`,而是 CMake 配置期经
            # vcpkg toolchain 按 vcpkg.json 的 builtin-baseline 自动装进 <BuildDir>/vcpkg_installed(每个 -BuildDir
            # 各自一份,并行 agent 互不干扰;二进制缓存在 %LOCALAPPDATA%\vcpkg\archives,第二次起秒级)。
            # 预检因此改验三件事:vcpkg.exe 已 bootstrap、manifest 声明了 ixwebsocket、baseline 是 40 位 SHA
            # (与 CLAUDE.md §0 铁律 3 对 action 的口径相同:可变 ref 不接受)。
            $vcpkgExe = Join-Path $vcpkgRoot 'vcpkg.exe'
            if (-not (Test-Path $vcpkgExe)) { $ok = $false; $detail += 'VCPKG_ROOT 下无 vcpkg.exe(先跑 bootstrap-vcpkg.bat); ' }
            try {
                $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
                $depNames = @($m.dependencies | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
                if ($depNames -notcontains 'ixwebsocket') { $ok = $false; $detail += 'vcpkg.json 未声明 ixwebsocket 依赖; ' }
                if (-not ($m.'builtin-baseline' -is [string]) -or $m.'builtin-baseline' -notmatch '^[0-9a-f]{40}$') {
                    $ok = $false; $detail += 'vcpkg.json 的 builtin-baseline 不是 40 位 commit SHA; '
                }
            } catch {
                $ok = $false; $detail += ('vcpkg.json 解析失败: ' + $_.Exception.Message + '; ')
            }
        } else {
            # 经典模式(无 vcpkg.json 的旧分支):向后兼容,仍验全局 installed 树里的 ixwebsocket。
            $ixConfig = Join-Path $vcpkgRoot 'installed\x64-windows-static\share\ixwebsocket\ixwebsocket-config.cmake'
            if (-not (Test-Path $ixConfig)) { $ok = $false; $detail += 'ixwebsocket (x64-windows-static) 未安装(vcpkg install ixwebsocket:x64-windows-static); ' }
        }
    }

    Add-Result '依赖预检 (cmake/VS/JUCE/clang-format/pluginval/vcpkg ixwebsocket)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 2:clang-format ----
function Test-ClangFormat {
    $ok = $true
    $detail = ''
    $files = @(git -C $RepoRoot ls-files '*.h' '*.hpp' '*.cpp' '*.cc' | Where-Object { $_ -notmatch '^third_party/' })
    if ($files.Count -eq 0) {
        $ok = $false; $detail = '未找到 C++ 源文件'
    } else {
        & clang-format --dry-run --Werror --style=file $files 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = 'clang-format --dry-run --Werror 失败;跑 clang-format -i 修复' }
    }
    Add-Result 'clang-format (18.1.8)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3:prettier ----
# 与 .github/workflows/format.yml 的检查逐字相同(06 §5.1:抽成常量 $PrettierCmd),范围收敛交给 .prettierignore。
# npm 的 npx.ps1 shim 在被脚本调用时会错误重建命令行(npm 已知 bug),Windows 上改用 npx.cmd 透传参数;
# 两者跑的是同一个 prettier@3 --check .,与 CI 语义完全一致(避免「本地绿 / CI 红」)。
$PrettierCmd = 'npx --yes prettier@3 --check .'
function Test-Prettier {
    $ok = $true
    $detail = ''
    $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
    if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
    if (-not $npx) { $ok = $false; $detail = 'npx 不在 PATH(需 Node.js)' }
    else {
        Push-Location $RepoRoot
        try {
            & $npx.Source --yes prettier@3 --check . 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = 'prettier --check 失败;跑 npx prettier@3 --write . 修复' }
        } finally { Pop-Location }
    }
    Add-Result 'prettier (--check .)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3b:gitleaks 树扫描 + 历史扫描(与 compliance.yml 的两个 Secret scan 步骤同参) ----
# 注意本地与 CI 的口径差:历史扫描走 `git log` 全部 ref,**含本地未推送的分支**,而 CI 只看
# checkout 出来的那份。所以「本地红 / CI 绿」是可能的,方向是 fail-closed(本地先拦住),
# 出现时按 BEFORE_PUBLIC_CHECKLIST.md §5 处置本地分支,不要靠 CI 绿灯放行。
function Test-Gitleaks {
    $ok = $true
    $detail = ''
    $g = Get-Command gitleaks -ErrorAction SilentlyContinue
    if (-not $g) { $ok = $false; $detail = 'gitleaks 不在 PATH(版本见 .gitleaks-version)' }
    else {
        Push-Location $RepoRoot
        try {
            & gitleaks detect --no-git --source . --redact -v --config .gitleaks.toml 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = 'gitleaks 检出密钥;误报请登记进 .gitleaks.toml allowlist,不得绕过' }
            # 历史扫描(与 compliance.yml 的 "Secret scan (git history)" 同参):敏感信息不借任何历史 commit 入库
            if ($ok) {
                & gitleaks detect --source . --redact -v --config .gitleaks.toml 2>&1 | ForEach-Object { Write-Host $_ }
                if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = 'gitleaks 历史扫描检出敏感信息;历史处置见 BEFORE_PUBLIC_CHECKLIST.md §5' }
            }
        } finally { Pop-Location }
    }
    Add-Result 'gitleaks (树扫描 + 历史扫描)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3b2:字体 name 表 RFN(与 compliance.yml 的 "Font name-table RFN check" 同参) ----
# woff2 是 brotli 压缩的,gitleaks/grep 对二进制失明:只有解出 name 表逐条比对才算 OFL-1.1 §3 的证据。
# python 或 fontTools/brotli 不可用一律 FAIL —— 静默跳过等于把这条断言从门禁里删掉。
function Test-FontNames {
    $ok = $true
    $detail = ''
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) {
        $ok = $false; $detail = 'python 不在 PATH(脚本另需 fontTools + brotli:pip install fonttools brotli)'
    } else {
        Push-Location $RepoRoot
        try {
            & $py.Source scripts/check-font-names.py 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                $ok = $false
                $detail = 'check-font-names.py 失败;缺依赖跑 pip install fonttools brotli,重新生成字体见 web/fonts/README.md'
            }
        } finally { Pop-Location }
    }
    Add-Result '字体 name 表 RFN (OFL-1.1 §3)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3c:reuse lint ----
function Test-Reuse {
    $ok = $true
    $detail = ''
    Push-Location $RepoRoot
    try {
        if (Get-Command pipx -ErrorAction SilentlyContinue) {
            & pipx run reuse lint 2>&1 | ForEach-Object { Write-Host $_ }
        } elseif (Get-Command reuse -ErrorAction SilentlyContinue) {
            & reuse lint 2>&1 | ForEach-Object { Write-Host $_ }
        } else {
            $ok = $false; $detail = 'reuse 不可用(pipx run reuse lint 或 reuse lint)'
        }
        if ($ok -and $LASTEXITCODE -ne 0) { $ok = $false; $detail = 'reuse lint 失败(SPDX/许可证缺失)' }
    } finally { Pop-Location }
    Add-Result 'reuse lint' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3d:端口 9420 一致性(本仓三处) ----
function Test-Port {
    $patterns = [ordered]@{
        'src/BridgeApi.h'              = 'DefaultPort\s*=\s*(\d+)'
        'web/bridge.js'                = 'DEFAULT_PORT\s*=\s*(\d+)'
        'web-preview/mock-server.mjs'  = 'PORT_BASE\s*=\s*parseInt\([^)]*"(\d+)"'
    }
    $ports = @()
    $labels = @()
    $ok = $true
    $detail = ''
    foreach ($rel in $patterns.Keys) {
        $path = Join-Path $RepoRoot $rel
        if (-not (Test-Path $path)) { $ok = $false; $detail += ($rel + ' 不存在; '); continue }
        $text = Get-Content -LiteralPath $path -Raw
        if ($text -match $patterns[$rel]) {
            $ports += [int]$Matches[1]
            $labels += ($rel + '=' + $Matches[1])
        } else {
            $ok = $false
            $detail += ($rel + ' 未找到端口常量; ')
        }
    }
    if ($ok -and $ports.Count -gt 0) {
        $uniq = @($ports | Select-Object -Unique)
        if ($uniq.Count -ne 1) {
            $ok = $false
            $detail = '三处端口不一致: ' + ($labels -join ' / ')
        } else {
            $detail = ($labels -join ' / ') + ' 一致'
        }
    }
    Add-Result '端口一致性 (BridgeApi.h/bridge.js/mock-server.mjs)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3e:版本一致性(CMake 真源 ↔ web-preview 三处镜像 ↔ BRIDGE_CONTRACT.md §三) ----
# CLAUDE.md §9:版本号真源 = CMakeLists.txt 的 project(... VERSION)。web-preview 的 mock server 会把
# PLUGIN_VERSION 当作插件版本上报给网页,漂了就等于向网页谎报一个不存在的插件版本。BRIDGE_CONTRACT.md
# §三的 VERSION 行是给两端实现看的登记快照,漂了等于协议文档写错版本(实际漂过一次,见 PR #19 审查)。
# CI 的版本门禁只在打 tag 时比 tag ↔ CMake,不覆盖这四处镜像,故在本地 gate 里断死。
function Test-Version {
    $ok = $true
    $detail = ''
    $cmakePath = Join-Path $RepoRoot 'CMakeLists.txt'
    $src = $null
    if (-not (Test-Path $cmakePath)) {
        $ok = $false; $detail = 'CMakeLists.txt 不存在'
    } else {
        $cmakeText = Get-Content -LiteralPath $cmakePath -Raw
        # 真源取值先剔 CMake 行注释:注释里留着旧版本的 `project(... VERSION x.y.z)`(说明、示例、被注掉的
        # 旧行)会被 -match 先命中,于是拿一个陈旧版本当真源,再拿它去比镜像 —— 本 gate 会全绿地比错。
        # 剔完再断言「恰好一处」:多于一处说明真源本身有歧义,报错比静默取第一处安全。
        $cmakeCode = (($cmakeText -split "`r?`n") -replace '#.*$', '') -join "`n"
        $vm = [regex]::Matches($cmakeCode, 'project\s*\(\s*\S+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)')
        if ($vm.Count -eq 1) {
            $src = $vm[0].Groups[1].Value
        } elseif ($vm.Count -eq 0) {
            $ok = $false; $detail = 'CMakeLists.txt 未找到 project(... VERSION x.y.z)'
        } else {
            $ok = $false; $detail = 'CMakeLists.txt 有 ' + $vm.Count + ' 处 project(... VERSION),真源有歧义'
        }
    }
    if ($ok) {
        # 镜像取值一律走「定点读取」,不做全文件 grep:package-lock.json 里 ws 依赖自己也有 "version",
        # 宽正则会把它一起比进来。JSON 走 ConvertFrom-Json 取指定字段,.mjs 走常量名锚定的正则。
        $bad = @()
        $seen = @()
        function Get-Mirror([string]$rel, [scriptblock]$reader, [int]$want) {
            $path = Join-Path $RepoRoot $rel
            if (-not (Test-Path $path)) { return @{ Err = ($rel + '(不存在)') } }
            # reader 在文件结构变化时会直接抛(package-lock.json 升版把 packages[''] 挪走、JSON 不合法……),
            # 本脚本 $ErrorActionPreference = 'Stop',不兜住的话整个 gates 会在这里中断、后面的 gate 一个不跑、
            # 结果表也打不出。兜成本 gate 的 FAIL 并带上可读原因(issue #23)。
            try {
                $text = Get-Content -LiteralPath $path -Raw
                $vals = @(& $reader $text | Where-Object { $_ })
            } catch {
                return @{ Err = ($rel + '(解析失败: ' + $_.Exception.Message + ')') }
            }
            # try/catch 只兜得住「抛」的一半:结构变化也可能是**不抛而返回 $null**(键还在、version 字段没了,
            # 索引 $null 在 PowerShell 里静默得 $null),被上面的 Where-Object 滤掉后就静默降级成只比剩下的
            # 几处。故 reader 返回后再断言取值个数恰等于期望个数,少了同样记 FAIL(PR #29 review)。
            if ($vals.Count -ne $want) {
                return @{ Err = ($rel + '(结构变化:期望 ' + $want + ' 个版本字段,实际 ' + $vals.Count + ' 个)') }
            }
            return @{ Vals = $vals }
        }
        # 每处镜像:Read = 定点读取的 scriptblock;Want = 该文件里应取到的版本字段个数(lockfile 是根 version +
        # packages[''].version 两处,其余各一处)。
        $readers = [ordered]@{
            'web-preview/mock-server.mjs'   = @{ Want = 1; Read = { param($t) if ($t -match 'PLUGIN_VERSION\s*=\s*"([^"]+)"') { $Matches[1] } } }
            'web-preview/package.json'      = @{ Want = 1; Read = { param($t) ($t | ConvertFrom-Json).version } }
            'web-preview/package-lock.json' = @{ Want = 2; Read = { param($t)
                # lockfile v3 的根包挂在 packages 的**空字符串键**下,ConvertFrom-Json 不带
                # -AsHashtable 时会直接报错(PSCustomObject 不支持空属性名),故这里必须用哈希表。
                $j = $t | ConvertFrom-Json -AsHashtable
                @($j['version'], $j['packages']['']['version'])
            } }
            # §三是一张 markdown 表:锚定行首竖线 + 单元格恰为 VERSION,避开同表的 BRIDGE_CONTRACT_VERSION 行
            # (那是协议版本,独立于插件版本,不参与本 gate)。
            'BRIDGE_CONTRACT.md'            = @{ Want = 1; Read = { param($t) if ($t -match '(?m)^\|\s*VERSION\s*\|\s*`([0-9]+\.[0-9]+\.[0-9]+)`') { $Matches[1] } } }
        }
        foreach ($rel in $readers.Keys) {
            $r = Get-Mirror $rel $readers[$rel].Read $readers[$rel].Want
            if ($r.Err) { $ok = $false; $bad += $r.Err; continue }
            foreach ($v in $r.Vals) {
                $seen += ($rel + '=' + $v)
                if ($v -ne $src) { $ok = $false; $bad += ($rel + '=' + $v) }
            }
        }
        if ($ok) {
            $detail = 'CMake=' + $src + ' == ' + ($seen -join ' / ')
        } else {
            $detail = '与 CMake ' + $src + ' 不一致: ' + ($bad -join ' / ')
        }
    }
    Add-Result '版本一致性 (CMake ↔ web-preview ↔ BRIDGE_CONTRACT)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3g:ixwebsocket 两平台版本一致性(vcpkg.json override ↔ CMakeLists.txt IXWEBSOCKET_TAG 注释) ----
# Windows 侧真源 = vcpkg.json 的 override(version-semver + 显式 port-version),macOS 侧真源 = CMakeLists.txt 的
# IXWEBSOCKET_TAG(40 位 SHA,机器不可能反推出版本号),故断言那一行的注释必须标注 `(= tag v<override 版本>)`:
# 升级时忘了动任何一侧,这里就红。与 compliance.yml 的 "ixwebsocket cross-platform pin consistency" 同参。
function Test-IxwebsocketPin {
    $ok = $true
    $detail = ''
    # 与 gate 1 / 4b 同口径的经典模式向后兼容:无 vcpkg.json 的 worktree 上 SKIP 而不是一条含义不明的 FAIL
    if (-not (Test-Path (Join-Path $RepoRoot 'vcpkg.json'))) {
        Add-Result 'ixwebsocket 版本一致性 (vcpkg.json ↔ CMakeLists IXWEBSOCKET_TAG)' 'SKIP' '无 vcpkg.json(经典模式)'
        return $true
    }
    try {
        $m = Get-Content -LiteralPath (Join-Path $RepoRoot 'vcpkg.json') -Raw | ConvertFrom-Json
        $ov = @($m.overrides | Where-Object name -eq 'ixwebsocket') | Select-Object -First 1
        $ver = $ov.'version-semver'
        if (-not $ver) {
            $ok = $false; $detail = 'vcpkg.json 无 ixwebsocket override 的 version-semver'
        } elseif ($null -eq $ov.'port-version') {
            $ok = $false; $detail = 'vcpkg.json 的 ixwebsocket override 未显式写 port-version(baseline 下为 #0 也要写 0)'
        } else {
            $lines = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'CMakeLists.txt') |
                Where-Object { $_ -match '^\s*set\(IXWEBSOCKET_TAG\s+"[0-9a-f]{40}"' })
            $tagNote = '(= tag v' + $ver + ')'
            if ($lines.Count -ne 1) {
                $ok = $false; $detail = 'CMakeLists.txt 应恰有 1 处 set(IXWEBSOCKET_TAG "<40 位 SHA>" ...),实际 ' + $lines.Count + ' 处'
            } elseif (-not $lines[0].Contains($tagNote)) {
                $ok = $false; $detail = 'CMakeLists.txt 的 IXWEBSOCKET_TAG 行未标注 ' + $tagNote + '(vcpkg.json 钉 ' + $ver + '): ' + $lines[0].Trim()
            } else {
                $detail = 'vcpkg.json override ' + $ver + '#' + $ov.'port-version' + ' ↔ IXWEBSOCKET_TAG 注释 ' + $tagNote
            }
        }
    } catch {
        $ok = $false; $detail = ('解析失败: ' + $_.Exception.Message)
    }
    Add-Result 'ixwebsocket 版本一致性 (vcpkg.json ↔ CMakeLists IXWEBSOCKET_TAG)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3f:PCM 帧头组帧接线(src/VstBridgeServer.cpp 必须走 src/PcmFrame.h)----
# tests/pcm_frame_selftest.cpp 只能钉 PcmFrame.h 自身的字节布局,钉不住「VstBridgeServer.cpp 真的经它组帧」
# (那要链 JUCE 才测得到)。这里用轻量文本断言补上:必须 #include "PcmFrame.h",且不得再出现抽取前两份
# 手写实现的特征 —— `writeU32(` 手写 lambda 与字面量 `headerSize = 12`(87133fe 删掉的就是它们)。
# 与 compliance.yml 的「PCM frame wiring」步骤同构(那边用 grep)。只读、秒级,归入只读 gate 恒跑。
function Test-PcmFrameWiring {
    $ok = $true
    $detail = ''
    $rel = 'src/VstBridgeServer.cpp'
    $path = Join-Path $RepoRoot $rel
    if (-not (Test-Path $path)) {
        $ok = $false; $detail = ($rel + ' 不存在')
    } else {
        $text = Get-Content -LiteralPath $path -Raw
        $bad = @()
        if ($text -notmatch '(?m)^\s*#include\s+"PcmFrame\.h"') { $bad += '缺少 #include "PcmFrame.h"' }
        if ($text -match 'writeU32\(') { $bad += '出现手写 writeU32( lambda' }
        if ($text -match 'headerSize\s*=\s*12\b') { $bad += '出现字面量 headerSize = 12' }
        # 正向断言(黑名单只认「上次是怎么错的」,拦不住第三种手写法):两条组帧路径都必须经 pcm::writeHeader。
        # 覆盖边界:本 gate 只盯 VstBridgeServer.cpp,别的 .cpp 里出现第四条组帧路径不在射程内。
        # 计次(compliance 侧 grep -o | wc -l 同口径)。「>= 2」钉的是当前两条路径(sendPcmPacket 为遗留无调用方路径);
        # 将来删掉遗留路径时改 >= 1。
        $calls = [regex]::Matches($text, 'pcm::writeHeader\(').Count
        if ($calls -lt 2) { $bad += ('pcm::writeHeader( 调用点 ' + $calls + ' 处,应 >= 2(两条组帧路径各一处)') }
        if ($bad.Count -gt 0) {
            $ok = $false
            $detail = ($rel + ': ' + ($bad -join '; ') + ';帧头必须经 src/PcmFrame.h 的 writeHeader/kHeaderSize 组帧')
        } else {
            $detail = ($rel + ' 经 PcmFrame.h 组帧,无手写帧头')
        }
    }
    Add-Result 'PCM 帧头接线 (VstBridgeServer.cpp → PcmFrame.h)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 3h:签名材料 / Avid 评估工具不入库 ----
# 代码签名材料(pfx / p12 / pvk)是签名凭据(CLAUDE.md §0 铁律 1),Avid DigiShell / AAX Validator 及其安装包、测试计划
# 属评估许可、不得再分发 —— 两类都只能放仓库外。只按「扩展名 + 文件名」匹配:文档文件名里出现 validator 不会误报。
# 两轮枚举(-z:NUL 分隔、不做 core.quotePath 转义,否则非 ASCII 文件名会被包成带引号的 "\346..." 而让 $ 锚定失配):
#   ① --cached --others --exclude-standard:已跟踪的 + `git add .` 会带进去的未跟踪文件;
#   ② --others --ignored --exclude-standard:被 .gitignore 藏起来的文件。.gitignore 已忽略 *.pfx / *.p12 / *.pvk,
#      只跑 ① 就看不见仓库里躺着的证书 —— 可签名材料本就必须在仓库外(签名脚本与证书助手同样拒绝仓库内路径),
#      被忽略只是让它在 `git status` 里隐身,一次 `git add -f` 或 .gitignore 改动就会入库。
# git 本身失败(不是仓库、git 不在 PATH)一律 FAIL:枚举不出来不等于没有。只读、秒级,恒跑(不挂 -IncludeAax)。
$script:SigningMaterialPattern = '(?i)\.(pfx|p12|pvk)$|(^|/)dsh\.exe$|(digishell|aax[ _-]?validator).*\.(exe|dll|zip|msi|dmg|pkg|pdf)$|test[ _-]?plan.*\.pdf$'
function Test-SigningMaterial {
    $label = '签名材料 / Avid 评估工具不入库 (pfx/p12/pvk、DigiShell、AAX Validator、测试计划)'
    $ok = $true
    $detail = ''
    $hits = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($pass in @(
                @{ Tag = ''; Args = @('--cached', '--others', '--exclude-standard') },
                @{ Tag = '(被 .gitignore 隐藏)'; Args = @('--others', '--ignored', '--exclude-standard') })) {
            $raw = & git -C $RepoRoot -c core.quotePath=false ls-files -z @($pass.Args)
            if ($LASTEXITCODE -ne 0) { throw ('git ls-files ' + ($pass.Args -join ' ') + ' 失败 (exit ' + $LASTEXITCODE + ')') }
            # 原生命令输出按行切成数组;-z 下只有文件名里自带的换行才会被切开,先按 LF 拼回再按 NUL 切
            foreach ($f in (@($raw) -join "`n") -split "`0") {
                if ($f -and [regex]::IsMatch($f, $script:SigningMaterialPattern) -and -not $hits.Contains($f + $pass.Tag)) {
                    $hits.Add($f + $pass.Tag)
                }
            }
        }
    } catch {
        $ok = $false; $detail = ('枚举仓库文件失败: ' + $_.Exception.Message)
    }
    if ($ok -and $hits.Count -gt 0) {
        $ok = $false
        foreach ($h in $hits) { Write-Host ('      命中: ' + $h) -ForegroundColor Red }
        $detail = ('仓库内有 ' + $hits.Count + ' 个签名材料 / Avid 评估工具文件,必须移到仓库外(已入库的还要按 ' +
            'BEFORE_PUBLIC_CHECKLIST.md §5 处置历史): ' + (@($hits | Select-Object -First 5) -join '; ') +
            $(if ($hits.Count -gt 5) { ' …' } else { '' }))
    } elseif ($ok) {
        $detail = '已跟踪 / 未跟踪 / 被忽略的文件均无命中'
    }
    Add-Result $label ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 4:cmake 配置 ----
function Test-Configure {
    $ok = $true
    $detail = ''
    $generator = Get-CMakeGenerator
    $toolchain = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
    $cmakeArgs = @(
        '-S', $RepoRoot,
        '-B', $BuildDir,
        '-G', $generator,
        '-A', 'x64',
        ('-DJUCE_PATH=' + ($JucePath -replace '\\', '/')),
        ('-DCMAKE_TOOLCHAIN_FILE=' + ($toolchain -replace '\\', '/')),
        '-DVCPKG_TARGET_TRIPLET=x64-windows-static',
        '-DBRIDGE_BUILD_SELFTESTS=ON' # 供 gate 5b 的两个纯逻辑 selftest;默认 OFF,不影响发布构建
    )
    & cmake @cmakeArgs 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = ('cmake configure 失败 (exit ' + $LASTEXITCODE + ')') }
    Add-Result 'cmake 配置' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 4b:vcpkg 安装版本断言(manifest 模式;与 ci.yml / release.yml 共用 scripts/assert-vcpkg-installed.ps1) ----
# configure 期 vcpkg toolchain 按 vcpkg.json 装进 <BuildDir>/vcpkg_installed 后,断言 status 文件里 ixwebsocket 核心段的
# Version / Port-Version == override、Status 为 install ok installed,传递依赖 mbedtls / zlib == THIRD-PARTY-NOTICES.md
# 登记版本 —— 本地与 CI 同一份脚本、同一口径,不会出现「本地绿 / CI 红」。无 vcpkg.json 的旧分支(经典模式)SKIP。
function Test-VcpkgInstalled {
    $label = 'vcpkg 安装版本 (status ↔ vcpkg.json override / THIRD-PARTY-NOTICES)'
    if (-not (Test-Path (Join-Path $RepoRoot 'vcpkg.json'))) {
        Add-Result $label 'SKIP' '无 vcpkg.json(经典模式)'
        return $true
    }
    $ok = $true
    $detail = ''
    try {
        & (Join-Path $PSScriptRoot 'assert-vcpkg-installed.ps1') -BuildDir $BuildDir 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = ('assert-vcpkg-installed.ps1 失败 (exit ' + $LASTEXITCODE + '),见上方 ::error:: 行') }
    } catch {
        $ok = $false; $detail = ('assert-vcpkg-installed.ps1 异常: ' + $_.Exception.Message)
    }
    Add-Result $label ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 5:构建 + 零 warning(/W4) ----
function Test-Build {
    $ok = $true
    $detail = ''
    $logFile = Join-Path $BuildDir 'gates-build.log'
    & cmake --build $BuildDir --config $Config --parallel 2>&1 | Tee-Object -FilePath $logFile | ForEach-Object { Write-Host $_ }
    $buildCode = $LASTEXITCODE
    if ($buildCode -ne 0) {
        $ok = $false
        $detail = ('cmake build 失败 (exit ' + $buildCode + ')')
    } else {
        # 排除项含 vcpkg_installed:manifest 模式下 ixwebsocket 头文件落在 <BuildDir>/vcpkg_installed/...,
        # 路径里不再出现 `\vcpkg\`,只写 vcpkg 会让第三方头的告警混进第一方零告警门(与 ci.yml / release.yml 同参)。
        $w = Select-String -Path $logFile -Pattern '\swarning\s+C\d{4}' | Where-Object { $_.Line -notmatch '[\\/](JUCE|vcpkg|vcpkg_installed|_deps)[\\/]' }
        if ($w.Count -gt 0) {
            $ok = $false
            $detail = ('MSVC 告警 ' + $w.Count + ' 条(/W4 要求零告警): ' + $w[0].Line)
        }
    }
    Add-Result 'build (/W4, 0 warning)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 5b:纯逻辑 selftest(origin allowlist + PCM 帧头 golden + SL-386 遮挡闸)----
# 三个零依赖自测可执行文件,由 Test-Configure 的 -DBRIDGE_BUILD_SELFTESTS=ON 产出;秒级,不依赖 DAW/GUI:
#   origin_allowlist_selftest —— Origin 白名单的纯字符串逻辑(src/OriginAllowlist.h);
#   pcm_frame_selftest        —— PCM 帧头 12 字节布局的 golden 字节(src/PcmFrame.h,契约 §二 第 1 条);
#   reveal_gate_selftest      —— SL-386 开窗遮挡闸(src/WebViewRevealGate.h):只认首帧放行 /
#                                navFinished 只记账 / settle 双条件(回绕安全)/ 3s 兜底 /
#                                挪窗几何 / 占位渐变 golden。
# 与 compliance workflow 同源同用例(那边用 g++ 直接编译同一份 tests/*.cpp)。
$script:Selftests = @(
    [pscustomobject]@{ Exe = 'origin_allowlist_selftest'; Label = 'origin selftest (Origin 白名单纯函数断言)' },
    [pscustomobject]@{ Exe = 'pcm_frame_selftest';        Label = 'pcm frame selftest (PCM 帧头 golden 断言)' },
    [pscustomobject]@{ Exe = 'reveal_gate_selftest';      Label = 'reveal gate selftest (SL-386 遮挡闸纯逻辑断言)' }
)

function Test-Selftest([string]$exeName, [string]$label) {
    $ok = $true
    $detail = ''
    $exe = Get-ChildItem -Path $BuildDir -Recurse -Filter ($exeName + '.exe') -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        $ok = $false
        $detail = ('未找到 ' + $exeName + '.exe(configure 须带 -DBRIDGE_BUILD_SELFTESTS=ON): ' + $BuildDir)
    } else {
        & $exe.FullName 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            $ok = $false
            $detail = ($exeName + ' 失败 (exit ' + $LASTEXITCODE + '),用例见 tests/' + $exeName + '.cpp')
        }
    }
    Add-Result $label ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

function Test-Selftests {
    $all = $true
    foreach ($t in $script:Selftests) { $all = (Test-Selftest $t.Exe $t.Label) -and $all }
    return $all
}

# ---- gate 5c/5d/5e:AAX(仅 -IncludeAax;selftest 之后、pluginval 之前)----
# 路径与 gate 6 的 VST3 同法写死(JUCE 产物布局):主体 DLL 是 bundle 内的 Contents\x64\Synchain Bridge.aaxplugin
# (一个文件,后缀也是 .aaxplugin)。pluginval 托管不了 AAX,本机能自动化的只有结构 / 打包 / (可选)Validator 三道。
$script:AaxBundleLabel    = 'AAX bundle 结构 (PE x64 / desktop.ini / Plugin.ico / 已构建恰好 1 个)'
$script:AaxPackageLabel   = 'AAX 打包冒烟 (package-aax.ps1 Unsigned + Signed 反向断言)'
$script:AaxValidatorLabel = 'AAX Validator (可选,-AaxValidatorPath)'
function Add-AaxSkips([string]$why) {
    foreach ($l in @($script:AaxBundleLabel, $script:AaxPackageLabel, $script:AaxValidatorLabel)) { Add-Result $l 'SKIP' $why }
}
function Get-AaxBundlePath { return (Join-Path $BuildDir ('SynchainBridgeVST_artefacts\' + $Config + '\AAX\Synchain Bridge.aaxplugin')) }

# PE 头 Machine 字段:MZ → 偏移 0x3C 处的 e_lfanew → 'PE\0\0' → 紧随其后的 UInt16(与 package-aax.ps1 同一读法)
function Get-PeMachine([string]$path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        if ($fs.Length -lt 0x40 -or $br.ReadUInt16() -ne 0x5A4D) { throw '不是 PE 映像(无 MZ 头)' }
        $fs.Position = 0x3C
        $peOffset = [int64]$br.ReadUInt32()
        if ($peOffset + 6 -gt $fs.Length) { throw 'PE 头被截断' }
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { throw "不是 PE 映像(无 'PE\0\0' 签名)" }
        return [int]$br.ReadUInt16()
    } finally {
        $fs.Dispose()
    }
}

# gate 5c:结构断言。「已构建恰好 1 个」只计含 Contents\ 的 *.aaxplugin 目录:VS 多配置生成器在 generate 期就为每个配置
# 各建一个只有 desktop.ini 的空壳目录(JUCE 的 file(GENERATE)),它们不是产物(与 package-aax.ps1 的定位同口径)。
# 枚举必须带 -Force:JUCE 给 bundle 目录设了 attrib +s,不带 -Force 可能被滤掉。
function Test-AaxBundle {
    $bad = @()
    $bundle = Get-AaxBundlePath
    $dll = Join-Path $bundle 'Contents\x64\Synchain Bridge.aaxplugin'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        $bad += ('未找到 AAX 主体 DLL ' + $dll + '(CMake 缓存里 SYNCHAIN_BRIDGE_AAX 是否被关掉?)')
    } else {
        try {
            $m = Get-PeMachine $dll
            if ($m -ne 0x8664) { $bad += ('主体 DLL 的 PE Machine = 0x{0:X4},应为 0x8664 (x64)' -f $m) }
        } catch {
            $bad += ('主体 DLL 读 PE 头失败: ' + $_.Exception.Message)
        }
    }
    foreach ($f in 'desktop.ini', 'Plugin.ico') {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $f) -PathType Leaf)) { $bad += ('bundle 根目录缺 ' + $f) }
    }
    $all = @(Get-ChildItem -LiteralPath $BuildDir -Recurse -Directory -Filter '*.aaxplugin' -Force -ErrorAction SilentlyContinue)
    $built = @($all | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Contents') -PathType Container })
    if ($built.Count -ne 1) {
        $bad += ('BuildDir 下已构建(含 Contents\)的 .aaxplugin 应恰好 1 个,实际 ' + $built.Count + ' 个' +
            $(if ($built.Count) { ': ' + (@($built | ForEach-Object { $_.FullName }) -join '; ') } else { '' }) +
            '(CI 的 package-aax.ps1 -BuildDir 定位同样要求恰好 1 个;残留的其他配置产物请清掉)')
    }
    $ok = ($bad.Count -eq 0)
    $detail = if ($ok) { 'Contents\x64 主体 DLL 为 x64 PE,desktop.ini / Plugin.ico 齐全,已构建 bundle 恰好 1 个' } else { $bad -join '; ' }
    Add-Result $script:AaxBundleLabel ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# gate 5d:打包冒烟。走 -BundlePath(不走 BuildDir 搜索,免得本地残留目录干扰计数);输出目录按 BuildDir 区分
# (dist\gates-aax-<BuildDir 名>:并行 agent 互不干扰,且在 dist/ 下 —— 已被 .gitignore 与 .gitleaks.toml 覆盖),
# 每次先清空,断言不受上一次残留影响。版本固定为 0.0.0-gates(一眼看出是冒烟件,与 CI 的 0.0.0-ci 同思路)。
#   Unsigned 跑一次:zip 与 .sha256 都产出,.sha256 与 ci.yml 的 AAX 冒烟逐字同一套字节断言;
#   Signed 反向断言:同一个未签名 bundle 必须被拒,且失败原因必须是签名检查(前置检查先挂掉不算数),输出目录里
#   不得出现发行名 zip。
function Test-AaxPackage {
    $ok = $true
    $detail = ''
    $bundle = Get-AaxBundlePath
    $out = Join-Path $RepoRoot ('dist\gates-aax-' + (Split-Path $BuildDir -Leaf))
    $neg = Join-Path $out 'neg'
    $ver = '0.0.0-gates'
    $zip = 'SynchainBridge-AAX-v' + $ver + '-win64-UNSIGNED.zip'
    $releaseZip = 'SynchainBridge-AAX-v' + $ver + '-win64.zip'
    $pkg = Join-Path $PSScriptRoot 'package-aax.ps1'
    try {
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
        & $pkg -Mode Unsigned -Version $ver -BundlePath $bundle -OutDir $out 2>&1 | ForEach-Object { Write-Host $_ }
        foreach ($f in @($zip, ($zip + '.sha256'), 'package-summary.md')) {
            if (-not (Test-Path -LiteralPath (Join-Path $out $f) -PathType Leaf)) { throw ('Unsigned 打包没产出 ' + $f) }
        }
        # 读原始字节:无 BOM、恰为 `<64 位小写 hex><两个空格><zip 基名>` + 一个 LF(\z 不放过结尾双换行),hash 与现算一致
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $out ($zip + '.sha256')))
        $raw = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw ($zip + '.sha256 以 UTF-8 BOM 开头') }
        if ($raw -cnotmatch ('^[0-9a-f]{64}  ' + [regex]::Escape($zip) + "`n\z")) {
            throw ($zip + '.sha256 不是恰好 "<64 hex>  ' + $zip + '" + 一个 LF(无 CR / 无多余空行): ' + [BitConverter]::ToString($bytes))
        }
        $want = (Get-FileHash -LiteralPath (Join-Path $out $zip) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($raw.TrimEnd("`n") -cne ($want + '  ' + $zip)) { throw ($zip + '.sha256 与 zip 现算的 hash ' + $want + ' 不一致') }

        $rejected = $false
        try {
            & $pkg -Mode Signed -Version $ver -BundlePath $bundle -OutDir $neg 2>&1 | ForEach-Object { Write-Host $_ }
        } catch {
            $msg = $_.Exception.Message
            if ($msg -cnotlike '*refusing to package an unsigned bundle under a release name*') {
                throw ('Signed 反向断言因无关原因失败(签名检查根本没执行到): ' + $msg)
            }
            $rejected = $true
            Write-Host ('      预期的拒收: ' + $msg)
        }
        if (-not $rejected) { throw 'package-aax.ps1 -Mode Signed 接受了未签名 bundle' }
        if (Test-Path -LiteralPath (Join-Path $neg $releaseZip)) { throw ('未签名 bundle 产出了发行名 zip ' + $releaseZip) }
        $detail = ($zip + ' + .sha256 字节形态正确;Signed 模式拒收未签名 bundle、未留发行名 zip(输出 ' + $out + ')')
    } catch {
        $ok = $false
        $detail = $_.Exception.Message
    }
    Add-Result $script:AaxPackageLabel ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# gate 5e:AAX Validator(可选)。判定顺序:没给路径 → SKIP;路径是空串 / 在仓库内 / 不存在 → FAIL(参数错误与 bundle
# 状态无关,先报);TODO-AAXVAL 常量未填 → SKIP;5c 失败 → SKIP;否则真跑,输出 Tee 到 $BuildDir\gates-aaxval.log,
# 以输出标记判定(FailPattern 优先,PassPattern 必须出现),退出码只作参考。
function Test-AaxValidator([bool]$bundleOk) {
    $label = $script:AaxValidatorLabel
    if (-not $AaxValidatorGiven) {
        Add-Result $label 'SKIP' '未提供 -AaxValidatorPath(Avid 评估许可工具,不入库)'
        return $true
    }
    if (-not $AaxValidatorPath) {
        Add-Result $label 'FAIL' '-AaxValidatorPath 传了空串(调用方没算出路径?不跑 Validator 就别传这个参数)'
        return $false
    }
    $full = [System.IO.Path]::GetFullPath((Resolve-RepoPath $AaxValidatorPath))
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + '\'
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Result $label 'FAIL' ('-AaxValidatorPath 在仓库内: ' + $full + '(Avid 评估许可工具必须放仓库外,例如 $env:USERPROFILE\avid-tools\)')
        return $false
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Add-Result $label 'FAIL' ('-AaxValidatorPath 不存在或不是文件: ' + $full)
        return $false
    }
    if ($null -eq $script:AaxValidatorArgs -or $null -eq $script:AaxValidatorPassPattern -or $null -eq $script:AaxValidatorFailPattern) {
        Add-Result $label 'SKIP' 'TODO-AAXVAL:调用方式未实测(gates.ps1 文件头三个常量未填)'
        return $true
    }
    if (-not $bundleOk) {
        Add-Result $label 'SKIP' 'gate 5c 失败,跳过'
        return $true
    }
    $ok = $true
    $detail = ''
    $log = Join-Path $BuildDir 'gates-aaxval.log'
    try {
        $bundle = Get-AaxBundlePath
        $valArgs = @($script:AaxValidatorArgs | ForEach-Object { ([string]$_).Replace('{bundle}', $bundle) })
        & $full @valArgs 2>&1 | Tee-Object -FilePath $log | ForEach-Object { Write-Host $_ }
        $code = $LASTEXITCODE
        $text = [string](Get-Content -LiteralPath $log -Raw)
        $opt = [System.Text.RegularExpressions.RegexOptions]::Multiline
        if ([regex]::IsMatch($text, $script:AaxValidatorFailPattern, $opt)) {
            $ok = $false; $detail = ('输出命中失败标记(exit ' + $code + '),日志见 ' + $log)
        } elseif (-not [regex]::IsMatch($text, $script:AaxValidatorPassPattern, $opt)) {
            $ok = $false; $detail = ('输出里没有通过标记(exit ' + $code + '),日志见 ' + $log)
        } else {
            $detail = ('输出命中通过标记(exit ' + $code + ',退出码仅供参考),日志见 ' + $log)
        }
    } catch {
        $ok = $false; $detail = ('运行 AAX Validator 失败: ' + $_.Exception.Message)
    }
    Add-Result $label ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- gate 6/7:pluginval(single bundle) ----
function Test-Pluginval([bool]$gui) {
    $label = if ($gui) { 'pluginval 全量含 GUI (本地真机)' } else { 'pluginval 非 GUI (strict 5)' }
    $ok = $true
    $detail = ''
    $bundle = Join-Path $BuildDir ('SynchainBridgeVST_artefacts\' + $Config + '\VST3\Synchain Bridge.vst3')
    if (-not (Test-Path $bundle)) { $ok = $false; $detail = ('未找到 VST3 产物: ' + $bundle) }
    else {
        $logDir = Join-Path $BuildDir ('pluginval-logs-' + $(if ($gui) { 'gui' } else { 'nogui' }))
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $args = @('--strictness-level', '5', '--timeout-ms', '60000')
        if (-not $gui) { $args += '--skip-gui-tests' }
        $args += @('--output-dir', $logDir, $bundle)

        $mutex = $null
        try {
            if ($gui) {
                # GUI pluginval 全局串行(桌面会话 + .vst3 文件锁)
                $mutex = New-Object System.Threading.Mutex($false, 'Global\SynchainBridge-pluginval-gui')
                if (-not $mutex.WaitOne(0)) {
                    Write-Host '      GUI pluginval 被其他 agent 占用,等待释放...' -ForegroundColor Yellow
                    $mutex.WaitOne() | Out-Null
                }
            }
            & pluginval @args 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = ('pluginval 失败 (exit ' + $LASTEXITCODE + '),日志见 ' + $logDir) }
        } finally {
            if ($mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
        }
    }
    Add-Result $label ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
    return $ok
}

# ---- 主流程 ----
Write-Host ''
Write-Host '== Synchain Bridge gates ==' -ForegroundColor Cyan
Write-Host ('  Config  : ' + $Config)
Write-Host ('  BuildDir: ' + $BuildDir)
Write-Host ('  Mode    : ' + $(if ($Quick) { 'Quick(跳过 pluginval)' } elseif ($PluginOnly) { 'PluginOnly(跳过 GUI pluginval)' } else { '全量(含 GUI pluginval)' }))
Write-Host ('  AAX     : ' + $(if ($RunAax) {
            '开(gate 5c/5d/5e;Validator ' + $(if ($AaxValidatorGiven) { '= ' + $AaxValidatorPath } else { '未提供' }) + ')'
        } else { '关(-IncludeAax 开启 gate 5c/5d/5e)' }))
Write-Host ''

# 只读 gate(1,2,3,3b,3b2,3c,3d,3e,3f,3g,3h)恒跑,互不依赖
$roOk = $true
$roOk = (Test-Deps) -and $roOk
$roOk = (Test-ClangFormat) -and $roOk
$roOk = (Test-Prettier) -and $roOk
$roOk = (Test-Gitleaks) -and $roOk
$roOk = (Test-FontNames) -and $roOk
$roOk = (Test-Reuse) -and $roOk
$roOk = (Test-Port) -and $roOk
$roOk = (Test-Version) -and $roOk
$roOk = (Test-IxwebsocketPin) -and $roOk
$roOk = (Test-PcmFrameWiring) -and $roOk
$roOk = (Test-SigningMaterial) -and $roOk

if (-not $roOk) {
    Add-Result 'cmake 配置' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'vcpkg 安装版本 (status ↔ vcpkg.json override / THIRD-PARTY-NOTICES)' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'build (/W4, 0 warning)' 'SKIP' '只读 gate 失败,跳过'
    foreach ($t in $script:Selftests) { Add-Result $t.Label 'SKIP' '只读 gate 失败,跳过' }
    if ($RunAax) { Add-AaxSkips '只读 gate 失败,跳过' }
    Add-Result 'pluginval 非 GUI (strict 5)' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'pluginval 全量含 GUI (本地真机)' 'SKIP' '只读 gate 失败,跳过'
} else {
    $cfgOk = Test-Configure
    # gate 4b 只在 configure 成功后有意义(status 文件由 configure 期的 vcpkg toolchain 落盘);断言失败视同配置失败,
    # 后续构建 / pluginval 一律 SKIP —— 绝不用一份漂了的依赖往下跑。
    if ($cfgOk) { $cfgOk = Test-VcpkgInstalled } else {
        Add-Result 'vcpkg 安装版本 (status ↔ vcpkg.json override / THIRD-PARTY-NOTICES)' 'SKIP' 'cmake 配置失败,跳过'
    }
    if ($cfgOk) { $buildOk = Test-Build } else {
        $buildOk = $false
        Add-Result 'build (/W4, 0 warning)' 'SKIP' 'cmake 配置失败,跳过'
    }
    if ($cfgOk -and $buildOk) {
        $null = Test-Selftests
    } else {
        foreach ($t in $script:Selftests) { Add-Result $t.Label 'SKIP' '构建失败,跳过' }
    }
    # AAX gate(5c → 5d → 5e):5c 不过时 5d 无从谈起(SKIP);5e 自己处理参数错误与 TODO-AAXVAL,bundle 不完好时 SKIP。
    # -Quick 不影响这三道(-Quick 只跳过 pluginval)。
    if ($RunAax) {
        if ($cfgOk -and $buildOk) {
            $aaxBundleOk = Test-AaxBundle
            if ($aaxBundleOk) { $null = Test-AaxPackage } else { Add-Result $script:AaxPackageLabel 'SKIP' 'gate 5c 失败,跳过' }
            $null = Test-AaxValidator $aaxBundleOk
        } else {
            Add-AaxSkips '构建失败,跳过'
        }
    }
    if ($cfgOk -and $buildOk) {
        if ($Quick) {
            Add-Result 'pluginval 非 GUI (strict 5)' 'SKIP' '-Quick'
            Add-Result 'pluginval 全量含 GUI (本地真机)' 'SKIP' '-Quick'
        } else {
            $p6 = Test-Pluginval $false
            if ($PluginOnly) {
                Add-Result 'pluginval 全量含 GUI (本地真机)' 'SKIP' '-PluginOnly'
            } else {
                $p7 = Test-Pluginval $true
            }
        }
    } else {
        Add-Result 'pluginval 非 GUI (strict 5)' 'SKIP' '构建失败,跳过'
        Add-Result 'pluginval 全量含 GUI (本地真机)' 'SKIP' '构建失败,跳过'
    }
}

# ---- 打印表格(可直接粘进 PR 描述) ----
Write-Host ''
Write-Host '```' -ForegroundColor DarkGray
Write-Host '| gate | 结果 |'
Write-Host '|---|---|'
$anyFail = $false
foreach ($r in $script:results) {
    Write-Host ('| ' + $r.Name + ' | ' + $r.Result + ' |')
    if ($r.Result -eq 'FAIL') { $anyFail = $true }
}
Write-Host '```' -ForegroundColor DarkGray
Write-Host ''

if ($anyFail) {
    Write-Host 'GATES RESULT: FAIL' -ForegroundColor Red
    exit 1
}
Write-Host 'GATES RESULT: PASS' -ForegroundColor Green
exit 0