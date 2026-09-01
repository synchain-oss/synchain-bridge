<#
.SYNOPSIS  Synchain Bridge 本地质量门禁 —— 提子 PR 前必须全绿(单 bundle)。
.DESCRIPTION
  结构同 06 §5.1,但只有一个 bundle;额外含 vcpkg ixwebsocket 预检(gate 1)、
  端口 9420 一致性检查(gate 3d:src/BridgeApi.h ↔ web/bridge.js ↔ web-preview/mock-server.mjs)与
  版本一致性检查(gate 3e:CMakeLists.txt project(VERSION) ↔ web-preview 的 mock-server.mjs /
  package.json / package-lock.json)。
  任一 gate FAIL 即以非零码退出,最后打印一张可直接粘进 PR 描述的表格。
.EXAMPLE   pwsh scripts/gates.ps1                         # 全量(含 GUI pluginval)
.EXAMPLE   pwsh scripts/gates.ps1 -PluginOnly             # 跳过 GUI pluginval(与 CI 等价)
.EXAMPLE   pwsh scripts/gates.ps1 -Quick                  # 跳过 pluginval,快速回环
.EXAMPLE   pwsh scripts/gates.ps1 -BuildDir build-B11     # 并行 agent:各用各的构建目录
#>
[CmdletBinding()]
param(
    [switch]$Quick,          # 跳过 pluginval(gate 6/7)
    [switch]$PluginOnly,     # 跳过 GUI pluginval(gate 7)
    [string]$Config   = 'Release',
    [string]$JucePath = $env:JUCE_PATH,
    [string]$BuildDir = 'build'
)

$ErrorActionPreference = 'Stop'

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
    else {
        $ixConfig = Join-Path $vcpkgRoot 'installed\x64-windows-static\share\ixwebsocket\ixwebsocket-config.cmake'
        if (-not (Test-Path $ixConfig)) { $ok = $false; $detail += 'ixwebsocket (x64-windows-static) 未安装(vcpkg install ixwebsocket:x64-windows-static); ' }
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

# ---- gate 3b:gitleaks(与 compliance.yml 同参) ----
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
        } finally { Pop-Location }
    }
    Add-Result 'gitleaks (--no-git --redact)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
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

# ---- gate 3e:版本一致性(CMake 真源 ↔ web-preview 的三处镜像) ----
# CLAUDE.md §9:版本号真源 = CMakeLists.txt 的 project(... VERSION)。web-preview 的 mock server 会把
# PLUGIN_VERSION 当作插件版本上报给网页,漂了就等于向网页谎报一个不存在的插件版本。CI 的版本门禁只在
# 打 tag 时比 tag ↔ CMake,不覆盖这三处镜像,故在本地 gate 里断死。
function Test-Version {
    $ok = $true
    $detail = ''
    $cmakePath = Join-Path $RepoRoot 'CMakeLists.txt'
    $src = $null
    if (-not (Test-Path $cmakePath)) {
        $ok = $false; $detail = 'CMakeLists.txt 不存在'
    } else {
        $cmakeText = Get-Content -LiteralPath $cmakePath -Raw
        if ($cmakeText -match 'project\s*\(\s*\S+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)') {
            $src = $Matches[1]
        } else {
            $ok = $false; $detail = 'CMakeLists.txt 未找到 project(... VERSION x.y.z)'
        }
    }
    if ($ok) {
        # 镜像取值一律走「定点读取」,不做全文件 grep:package-lock.json 里 ws 依赖自己也有 "version",
        # 宽正则会把它一起比进来。JSON 走 ConvertFrom-Json 取指定字段,.mjs 走常量名锚定的正则。
        $bad = @()
        $seen = @()
        function Get-Mirror([string]$rel, [scriptblock]$reader) {
            $path = Join-Path $RepoRoot $rel
            if (-not (Test-Path $path)) { return @{ Err = ($rel + '(不存在)') } }
            $text = Get-Content -LiteralPath $path -Raw
            $vals = & $reader $text
            $vals = @($vals | Where-Object { $_ })
            if ($vals.Count -eq 0) { return @{ Err = ($rel + '(未找到版本号)') } }
            return @{ Vals = $vals }
        }
        $readers = [ordered]@{
            'web-preview/mock-server.mjs'   = { param($t) if ($t -match 'PLUGIN_VERSION\s*=\s*"([^"]+)"') { $Matches[1] } }
            'web-preview/package.json'      = { param($t) ($t | ConvertFrom-Json).version }
            'web-preview/package-lock.json' = { param($t)
                # lockfile v3 的根包挂在 packages 的**空字符串键**下,ConvertFrom-Json 不带
                # -AsHashtable 时会直接报错(PSCustomObject 不支持空属性名),故这里必须用哈希表。
                $j = $t | ConvertFrom-Json -AsHashtable
                @($j['version'], $j['packages']['']['version'])
            }
        }
        foreach ($rel in $readers.Keys) {
            $r = Get-Mirror $rel $readers[$rel]
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
    Add-Result '版本一致性 (CMake ↔ web-preview)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
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
        '-DVCPKG_TARGET_TRIPLET=x64-windows-static'
    )
    & cmake @cmakeArgs 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { $ok = $false; $detail = ('cmake configure 失败 (exit ' + $LASTEXITCODE + ')') }
    Add-Result 'cmake 配置' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
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
        $w = Select-String -Path $logFile -Pattern '\swarning\s+C\d{4}' | Where-Object { $_.Line -notmatch '[\\/](JUCE|vcpkg|_deps)[\\/]' }
        if ($w.Count -gt 0) {
            $ok = $false
            $detail = ('MSVC 告警 ' + $w.Count + ' 条(/W4 要求零告警): ' + $w[0].Line)
        }
    }
    Add-Result 'build (/W4, 0 warning)' ($(if ($ok) { 'PASS' } else { 'FAIL' })) $detail
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
Write-Host ''

# 只读 gate(1,2,3,3b,3c,3d,3e)恒跑,互不依赖
$roOk = $true
$roOk = (Test-Deps) -and $roOk
$roOk = (Test-ClangFormat) -and $roOk
$roOk = (Test-Prettier) -and $roOk
$roOk = (Test-Gitleaks) -and $roOk
$roOk = (Test-Reuse) -and $roOk
$roOk = (Test-Port) -and $roOk
$roOk = (Test-Version) -and $roOk

if (-not $roOk) {
    Add-Result 'cmake 配置' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'build (/W4, 0 warning)' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'pluginval 非 GUI (strict 5)' 'SKIP' '只读 gate 失败,跳过'
    Add-Result 'pluginval 全量含 GUI (本地真机)' 'SKIP' '只读 gate 失败,跳过'
} else {
    $cfgOk = Test-Configure
    if ($cfgOk) { $buildOk = Test-Build } else {
        $buildOk = $false
        Add-Result 'build (/W4, 0 warning)' 'SKIP' 'cmake 配置失败,跳过'
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