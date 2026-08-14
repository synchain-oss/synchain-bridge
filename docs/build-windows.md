# Windows 源码构建指南

> 面向 Windows x64 + Visual Studio 2022。产物是 `Synchain Bridge.vst3`（一个 **bundle 目录**，不是单文件）。
> 只想下载预编译版并插进 DAW 的读者，请看 [README](../README.md) 的 Install 一节。

## 前置依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| Windows | x64 | v1 只发布 Windows x64（macOS 用系统 WKWebView，代码跨平台但首发不构建） |
| Visual Studio 2022 | 「使用 C++ 的桌面开发」（MSVC v143 + Windows SDK） | VS2019 BuildTools（v142）亦可 |
| CMake | ≥ 3.22 | 见 `CMakeLists.txt:1` |
| JUCE | 8.0.8（版本真源 `.juce-version`） | `git clone --branch 8.0.8` |
| vcpkg | `ixwebsocket:x64-windows-static` | 必须用 `x64-windows-static` triplet，与静态 CRT 对齐 |
| NuGet CLI | `nuget.exe` 在 PATH | CMake 配置期自动拉 `Microsoft.Web.WebView2`，无需手工装 SDK |
| WebView2 Runtime | Evergreen | Win11 已内置；Win10 缺时插件会弹原生兜底面板引导安装 |

## 一次性准备

```powershell
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
C:\dev\vcpkg\vcpkg install ixwebsocket:x64-windows-static
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE
```

## 配置 + 构建（在仓库根目录执行）

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
```

产物：`build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3`

## 关键坑（必读）

### 1. 静态 CRT 必须在 `project()` **之前**设置

`CMakeLists.txt:3-9`。`CMAKE_MSVC_RUNTIME_LIBRARY` 的 `/MT` 必须写在 `project()` 之前才生效，与 vcpkg `x64-windows-static` triplet 和 WebView2 静态 loader 三者对齐。顺序颠倒会导致链接期 `/MT` vs `/MD` 冲突（LNK2038）。

### 2. vcpkg triplet 必须 `x64-windows-static`

ixwebsocket 用静态 triplet 编译（内嵌 mbedtls，无需单独 OpenSSL）。动态 triplet 会与静态 CRT 冲突。

### 3. WebView2 是配置期 NuGet 自动拉取，不是「装 SDK」

`CMakeLists.txt:24-57`。JUCE 的 `NEEDS_WEBVIEW2` 只会**查找 + 链接**已经存在的 NuGet 包，不会自己下载。本仓在配置期用 `nuget.exe` 把 `Microsoft.Web.WebView2` 拉到确定性目录 `build/packages`，再经 `JUCE_WEBVIEW2_PACKAGE_LOCATION` 指过去——不依赖 `%USERPROFILE%`，本地与 CI 可复现。缺 `nuget.exe` 会直接 FATAL_ERROR。

### 4. 编译宏组合（必要且易漏）

`CMakeLists.txt:144-153`。三个宏缺一不可：

- `JUCE_WEB_BROWSER=1` —— 启用 `WebBrowserComponent`
- `JUCE_USE_WIN_WEBVIEW2=1` —— 启用 WebView2 代码路径
- `JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING=1` —— 静态 loader，运行时不需要 `WebView2Loader.dll`

注意：这些宏**只让代码路径存在 + 链接 loader，并不切换后端**。真正选后端靠 `WebViewEditor.cpp` 里的 `withBackend(webview2)`（见 [webview-ui-pattern.md](webview-ui-pattern.md) 条目 2）。

### 5. 常见失败排查

- **`JUCE_PATH must be set`**：没传 `-DJUCE_PATH`，或路径指向了 JUCE 子目录而非根。
- **`nuget.exe not found`**：装 NuGet CLI 并确保在 PATH；或预先往 `build/packages` 放好 WebView2 包（离线 / 缓存场景）。
- **LNK2038（`/MT` vs `/MD` 不匹配）**：回到坑 1/2 检查 CRT 设置位置与 triplet。
- **`无法打开此页 https://juce.backend`**（运行期，非构建期）：未显式选 WebView2 后端，回退到了旧 IE 控件。见 [webview-ui-pattern.md](webview-ui-pattern.md) 条目 2。
- **插件窗口是英文兜底面板**：WebView2 Runtime 缺失或加载超时。装 Runtime 后重开插件窗口。

## CI 对照

CI（`.github/workflows/ci.yml`，job `build-and-validate`）与上述步骤同构：clone JUCE（版本读 `.juce-version`）→ vcpkg 装 ixwebsocket → 装 WebView2 Evergreen Runtime → CMake 配置 → 构建 → pluginval `--skip-gui-tests`（strictness 5）。含 WebView2 编辑器的全量 strictness-5 在真实 Win11 本地验证——无桌面的 Server runner 无法托管编辑器。
