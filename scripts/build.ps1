<#
.SYNOPSIS  一键构建 Synchain Bridge 并可选安装进系统 VST3 目录,供 DAW 实测。
.DESCRIPTION
  单 bundle(Synchain Bridge.vst3)。依赖 B03 的 CMake 结构;cmake 配置/构建命令与
  docs/build-windows.md 一致。路径引用一律走环境变量(JUCE_PATH / VCPKG_ROOT)与相对
  BuildDir,不写死绝对路径。默认不安装;加 -Install 时复制 .vst3 到系统 VST3 目录
  (无管理员权限自动回退到用户级目录,并先检测目标是否被 DAW 占用)。
.EXAMPLE   pwsh scripts/build.ps1 -Install
.EXAMPLE   pwsh scripts/build.ps1 -Config Debug
.EXAMPLE   pwsh scripts/build.ps1 -BuildDir build-B11        # 并行 agent:各用各的构建目录
.EXAMPLE   pwsh scripts/build.ps1 -Clean -Install           # 清构建目录(保留 NuGet 缓存)后构建并安装
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug', 'RelWithDebInfo')][string]$Config = 'Release',
    [string]$JucePath = $env:JUCE_PATH,
    [string]$BuildDir = 'build',
    [switch]$Install,        # 构建后复制 .vst3 到系统 VST3 目录
    [switch]$Clean,          # 清 $BuildDir(保留 $BuildDir/packages 的 NuGet 缓存)
    [switch]$OpenFolder      # 构建后打开产物目录
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string]$p) {
    if ($p -match '^([a-zA-Z]:[\\/]|\\\\|/)') { return $p }
    return (Join-Path $RepoRoot $p)
}
$BuildDir = Resolve-RepoPath $BuildDir

# 版本唯一真源 = CMakeLists.txt 的 project(... VERSION ...)
$vLine = Select-String -Path (Join-Path $RepoRoot 'CMakeLists.txt') -Pattern 'project\s*\(\s*\S+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)'
if (-not $vLine) { throw 'cannot parse VERSION from CMakeLists.txt' }
$Version = $vLine.Matches[0].Groups[1].Value

$start = Get-Date
Write-Host ''
Write-Host '== Synchain Bridge build ==' -ForegroundColor Cyan
Write-Host ("  Repo    : " + $RepoRoot)
Write-Host ("  Version : " + $Version)
Write-Host ("  Config  : " + $Config)
Write-Host ("  BuildDir: " + $BuildDir)
Write-Host ''

# ---------------------------------------------------------------------------
# 依赖预检(一次性全查完,给出可执行修复指引)
# ---------------------------------------------------------------------------
$errors = @()

# cmake >= 3.22
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
    $errors += 'cmake 不在 PATH。安装: winget install Kitware.CMake'
} else {
    $cv = (& cmake --version | Select-Object -First 1)
    if ($cv -match 'version\s+(\d+)\.(\d+)') {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 22)) {
            $errors += ('cmake ' + $maj + '.' + $min + ' < 3.22。升级: winget install Kitware.CMake')
        } else {
            Write-Host ('[OK] cmake ' + $maj + '.' + $min) -ForegroundColor Green
        }
    }
}

# MSVC(VS2022 优先;VS2019 BuildTools 亦可,见 docs/build-windows.md)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsVersion = $null
$generator = $null
if (Test-Path $vswhere) {
    $vsVersion = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion
}
if ($vsVersion -match '^17\.') { $generator = 'Visual Studio 17 2022' }
elseif ($vsVersion -match '^16\.') { $generator = 'Visual Studio 16 2019' }
if (-not $generator) {
    $errors += '未找到带 "Desktop development with C++" 的 VS2022 / VS2019。安装 VS2022(或 VS2019 BuildTools)的 VC 工具集。'
} else {
    Write-Host ('[OK] MSVC toolset (generator: ' + $generator + ')') -ForegroundColor Green
}

# JUCE(版本单一真源 .juce-version)
$juceVer = (Get-Content (Join-Path $RepoRoot '.juce-version') -Raw).Trim()
if (-not $JucePath) {
    $errors += ('JUCE_PATH 未设置。clone: git clone --depth 1 --branch ' + $juceVer + ' https://github.com/juce-framework/JUCE.git,并设 JUCE_PATH 环境变量(或用 -JucePath 传入)。')
} elseif (-not (Test-Path (Join-Path $JucePath 'CMakeLists.txt'))) {
    $errors += ('JUCE_PATH 指向的不是 JUCE 根目录(缺 CMakeLists.txt): ' + $JucePath)
} else {
    $jv = (git -C $JucePath describe --tags 2>$null).Trim()
    if ($jv -ne $juceVer) {
        $errors += ('JUCE 版本 "' + $jv + '" != .juce-version "' + $juceVer + '"。checkout 正确 tag 后重试。')
    } else {
        Write-Host ('[OK] JUCE ' + $juceVer) -ForegroundColor Green
    }
}

# vcpkg + ixwebsocket(x64-windows-static)
$vcpkgRoot = $env:VCPKG_ROOT
if (-not $vcpkgRoot) {
    $errors += 'VCPKG_ROOT 未设置。安装 vcpkg 并设 VCPKG_ROOT 环境变量。'
} else {
    $toolchain = Join-Path $vcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
    $ixConfig  = Join-Path $vcpkgRoot 'installed\x64-windows-static\share\ixwebsocket\ixwebsocket-config.cmake'
    if (-not (Test-Path $toolchain)) { $errors += ('vcpkg toolchain 不存在: ' + $toolchain) }
    if (-not (Test-Path $ixConfig))  { $errors += 'ixwebsocket (x64-windows-static) 未安装。安装: vcpkg install ixwebsocket:x64-windows-static' }
    if ((Test-Path $toolchain) -and (Test-Path $ixConfig)) {
        Write-Host '[OK] vcpkg + ixwebsocket (x64-windows-static)' -ForegroundColor Green
    }
}

# nuget(WebView2 配置期拉取;build/packages 已缓存则可跳过)
$nuget = Get-Command nuget -ErrorAction SilentlyContinue
$wv2Cached = Test-Path (Join-Path $BuildDir 'packages\Microsoft.Web.WebView2')
if (-not $nuget -and -not $wv2Cached) {
    $errors += 'nuget.exe 不在 PATH(WebView2 配置期需要)。安装 NuGet CLI 并加入 PATH,或预先缓存 build\packages。'
} elseif ($wv2Cached) {
    Write-Host '[OK] WebView2 NuGet 包已缓存(跳过 nuget 检查)' -ForegroundColor Green
} else {
    Write-Host '[OK] nuget' -ForegroundColor Green
}

# WebView2 Runtime(运行期依赖;缺失只警告,不阻断构建/DAW 扫描)
$wv2Key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue
if (-not $wv2Key -or -not $wv2Key.pv) {
    Write-Host '[WARN] WebView2 Runtime 未检测到;打开插件编辑器时需要。下载: https://go.microsoft.com/fwlink/p/?LinkId=2124703' -ForegroundColor Yellow
} else {
    Write-Host ('[OK] WebView2 Runtime ' + $wv2Key.pv) -ForegroundColor Green
}

# 磁盘空间 >= 5 GB
try {
    $free = (New-Object System.IO.DriveInfo($RepoRoot)).AvailableFreeSpace
    if ($free -lt 5GB) {
        $errors += ('磁盘空间不足 5GB(当前 ' + [math]::Round($free/1GB, 1) + ' GB)。')
    } else {
        Write-Host ('[OK] 磁盘空间充足 (' + [math]::Round($free/1GB, 1) + ' GB)') -ForegroundColor Green
    }
} catch {
    Write-Host '[WARN] 无法读取磁盘剩余空间' -ForegroundColor Yellow
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host '依赖预检失败:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host ('  - ' + $_) -ForegroundColor Red }
    exit 1
}
Write-Host ''

# ---------------------------------------------------------------------------
# -Clean:清 $BuildDir(保留 packages NuGet 缓存)
# ---------------------------------------------------------------------------
if ($Clean) {
    if (Test-Path $BuildDir) {
        Get-ChildItem $BuildDir -Exclude packages | Remove-Item -Recurse -Force
        Write-Host ('[Clean] 已清空 ' + $BuildDir + '(保留 packages/)') -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 配置 + 构建
# ---------------------------------------------------------------------------
Write-Host '== Configure ==' -ForegroundColor Cyan
$toolchain = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
$juceForCmake  = $JucePath -replace '\\', '/'
$toolchainForCmake = $toolchain -replace '\\', '/'
$cmakeArgs = @(
    '-S', $RepoRoot,
    '-B', $BuildDir,
    '-G', $generator,
    '-A', 'x64',
    ('-DJUCE_PATH=' + $juceForCmake),
    ('-DCMAKE_TOOLCHAIN_FILE=' + $toolchainForCmake),
    '-DVCPKG_TARGET_TRIPLET=x64-windows-static'
)
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw ('cmake configure failed (exit ' + $LASTEXITCODE + ')') }

Write-Host '== Build ==' -ForegroundColor Cyan
& cmake --build $BuildDir --config $Config --parallel
if ($LASTEXITCODE -ne 0) { throw ('cmake build failed (exit ' + $LASTEXITCODE + ')') }

# ---------------------------------------------------------------------------
# 定位产物
# ---------------------------------------------------------------------------
$bundle = Join-Path $BuildDir ('SynchainBridgeVST_artefacts\' + $Config + '\VST3\Synchain Bridge.vst3')
if (-not (Test-Path $bundle)) {
    throw ('未找到 VST3 产物: ' + $bundle)
}

$elapsed = ((Get-Date) - $start).TotalSeconds
Write-Host ''
Write-Host '== 构建完成 ==' -ForegroundColor Green
Write-Host ('  产物 : ' + $bundle)
Write-Host ('  版本 : ' + $Version)
Write-Host ('  耗时 : ' + [math]::Round($elapsed, 1) + 's')

# ---------------------------------------------------------------------------
# -Install:复制到系统 VST3 目录(无管理员权限回退用户级目录)
# ---------------------------------------------------------------------------
if ($Install) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        $vst3Dir = Join-Path $env:CommonProgramFiles 'VST3'
    } else {
        $vst3Dir = Join-Path $env:LOCALAPPDATA 'Programs\Common\VST3'
        Write-Host '[INFO] 无管理员权限,安装到用户级 VST3 目录。' -ForegroundColor Yellow
    }

    $targetBundle = Join-Path $vst3Dir 'Synchain Bridge.vst3'

    # 目标已被安装过则检测是否被 DAW 占用(文件锁),不静默失败
    if (Test-Path $targetBundle) {
        $inner = Get-ChildItem -Path $targetBundle -Recurse -File -Filter '*.vst3' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($inner) {
            $locked = $false
            try {
                $fs = [System.IO.File]::Open($inner.FullName, 'Open', 'ReadWrite', 'None')
                $fs.Close()
            } catch { $locked = $true }
            if ($locked) {
                Write-Host ('目标 .vst3 正被占用(可能 DAW 已加载该插件)。请先关闭 DAW 后重试。') -ForegroundColor Red
                exit 1
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $vst3Dir | Out-Null
    if (Test-Path $targetBundle) { Remove-Item -LiteralPath $targetBundle -Recurse -Force }
    Copy-Item -LiteralPath $bundle -Destination $targetBundle -Recurse -Force
    Write-Host ('  安装到: ' + $targetBundle) -ForegroundColor Green
}

if ($OpenFolder) {
    Start-Process explorer.exe (Split-Path $bundle -Parent)
}
