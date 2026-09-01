# Windows 源码构建指南

> 面向 Windows x64 + Visual Studio 2022。产物是 `Synchain Bridge.vst3`（一个 **bundle 目录**，不是单文件）。
> 只想下载预编译版并插进 DAW 的读者，请看 [README](../README.md) 的 Install 一节。
> macOS（Apple Silicon，VST3 + AU）另见 [build-macos.md](build-macos.md)。

## 前置依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| Windows | x64 | 本文只覆盖 Windows 侧；macOS（arm64，VST3 + AU）的构建见 [build-macos.md](build-macos.md) |
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

## 可选：额外 Origin 白名单（构建期注入）

WebSocket 桥的 Origin 白名单（CSWSH 防护）在源码里只含 `synchain.cn` / `synchain.ca` 系默认域与本地回环；
**预览部署等额外来源不写进仓库**，需要时在配置期注入：

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="example-git-*-example-team.example.app;preview.example.com"
```

- 值为 `;` 或 `,` 分隔的 **host 模式**列表；每个模式**至多一个 `*`**，无 `*` 时按精确 host 匹配；
  匹配前统一小写归一，FQDN 尾点（`https://example.com.`）会被剥掉后再比。
- `*` 只匹配**单个 DNS 标签内**的一段非空字符：**通配段不跨 `.`**。即 `a-*-b.example.app` 匹配
  `a-x-b.example.app`，但**不**匹配 `a-x.evil.com-b.example.app`。
- 模式必须带**真实域名锚点**才会被采纳：去掉 `*` 后剩下的字面量须含 `.`，且最后一个 `.` 之后是一段
  纯字母、长度 ≥2 的 TLD。因此 `*`、`*.`、`-*`、`*-`、`*.example.*` 这类「字面量全是标点 / 通配到 TLD」
  的模式会被 **fail-closed 丢弃**（含多个 `*` 的模式同样丢弃），不会变成变相的全通配。
- 额外来源同样**只在 https 下生效**（非 https 的远程来源一律拒）。
- 值里**不得含双引号或反斜杠**：该值最终会进生成头 `BridgeOriginConfig.h` 的字符串字面量，
  CMake 配置期检测到会直接 `FATAL_ERROR`。
- **不传即不定义该宏**：默认构建不放行任何额外来源。实现见 `src/VstBridgeServer.cpp` 的 `isAllowedOrigin()`。

## 关键坑（必读）

### 1. 静态 CRT 必须在 `project()` **之前**设置

`CMakeLists.txt:3-7`（`project()` 在第 21 行）。`CMAKE_MSVC_RUNTIME_LIBRARY` 的 `/MT` 必须写在 `project()` 之前才生效，与 vcpkg `x64-windows-static` triplet 和 WebView2 静态 loader 三者对齐。顺序颠倒会导致链接期 `/MT` vs `/MD` 冲突（LNK2038）。同一块里 `project()` 之前还设了 macOS 的架构 / 部署目标（同样要参与编译器探测），那两个变量在 Windows 上完全无作用。

### 2. vcpkg triplet 必须 `x64-windows-static`

ixwebsocket 用静态 triplet 编译（内嵌 mbedtls，无需单独 OpenSSL）。动态 triplet 会与静态 CRT 冲突。
依赖块按平台分支：**Windows 走 vcpkg 的 `find_package(ixwebsocket)`（本节），macOS 走 `FetchContent`**，两条路径互不影响。

### 3. WebView2 是配置期 NuGet 自动拉取，不是「装 SDK」

`CMakeLists.txt:36-69`。JUCE 的 `NEEDS_WEBVIEW2` 只会**查找 + 链接**已经存在的 NuGet 包，不会自己下载。本仓在配置期用 `nuget.exe` 把 `Microsoft.Web.WebView2` 拉到确定性目录 `build/packages`，再经 `JUCE_WEBVIEW2_PACKAGE_LOCATION` 指过去——不依赖 `%USERPROFILE%`，本地与 CI 可复现。缺 `nuget.exe` 会直接 FATAL_ERROR。

### 4. 编译宏组合（必要且易漏）

`CMakeLists.txt:189-200`。三个宏缺一不可（后两个只在 `if(WIN32)` 内定义）：

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
