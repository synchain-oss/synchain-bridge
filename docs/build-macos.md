# macOS 源码构建指南

> 面向 macOS 11.0+ / Apple Silicon（arm64）。产物是 `Synchain Bridge.vst3` 与 `Synchain Bridge.component`
> （都是 **bundle 目录**，不是单文件）。
> 只想下载预编译版并插进 DAW 的读者，请看 [README](../README.md) 的 Install 一节。

## 前置依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| macOS | 11.0+，Apple Silicon（arm64） | 构建默认只出 arm64；Intel Mac 不在 v1 支持范围 |
| Xcode Command Line Tools | `xcode-select --install` | 只需 CLT（clang + macOS SDK），无需完整 Xcode.app |
| CMake | ≥ 3.22 | 见 `CMakeLists.txt:1`；`brew install cmake` |
| Ninja | 任意版本 | `brew install ninja`；本文命令以 Ninja 为准（Xcode 生成器亦可） |
| JUCE | 版本真源 `.juce-version` | clone 命令见下，不要手写版本号 |
| ixwebsocket | **无需手工安装** | macOS 走 CMake `FetchContent`，tag 由 `IXWEBSOCKET_TAG`（默认 `v11.4.6`）钉死，配置期自动拉取 |
| vcpkg / NuGet CLI / WebView2 Runtime | **不需要** | 三者都是 Windows 侧依赖；macOS 用系统 WKWebView |

配置期会 `git clone` ixwebsocket，因此**首次配置需要网络**（`GIT_SHALLOW TRUE`，只拉一个 tag）。

## 一次性准备

```bash
git clone --depth 1 --branch "$(tr -d '[:space:]' < .juce-version)" https://github.com/juce-framework/JUCE.git ~/dev/JUCE
```

`.juce-version` 是 JUCE 版本的单一真源；上面的 `tr` 直接把它喂给 `--branch`，避免手抄版本号漂移。

## 配置 + 构建（在仓库根目录执行）

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DJUCE_PATH="$HOME/dev/JUCE"
cmake --build build --parallel
```

配置期日志里应出现：

```
-- Building Synchain Bridge for macOS: VST3 + AU, arch=arm64, min=11.0, WKWebView
```

产物：

- `build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3`
- `build/SynchainBridgeVST_artefacts/Release/AU/Synchain Bridge.component`

## 安装

用 `ditto` 而不是 `cp -r`：bundle 里有符号链接与扩展属性，`ditto` 会原样保留。

```bash
ditto "build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3" \
      ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3"
ditto "build/SynchainBridgeVST_artefacts/Release/AU/Synchain Bridge.component" \
      ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"

# AU 组件缓存由 AudioComponentRegistrar 持有：不重启它，DAW 扫到的仍是旧副本
killall -9 AudioComponentRegistrar
```

本地构建出来的 bundle **不带** `com.apple.quarantine`；只有从 Releases 下载的 zip 需要解除隔离，见
[README](../README.md#install) 的 macOS 小节。

## 验证

### auval（AU 官方校验，必过）

```bash
auval -v aufx Snb1 Snch
```

参数顺序是 `<类型> <插件码> <厂商码>`：`aufx` = Effect（对应 `CMakeLists.txt` 的
`AU_MAIN_TYPE kAudioUnitType_Effect`），`Snb1` = `PLUGIN_CODE`，`Snch` = `PLUGIN_MANUFACTURER_CODE`。
期望结尾出现：

```
AU VALIDATION SUCCEEDED.
```

`auval -a | grep Snb1` 可先确认组件被系统登记；查不到就回到上一节 `killall -9 AudioComponentRegistrar`。

### pluginval（全量，含 GUI —— 本地门禁）

```bash
pluginval --strictness-level 5 --validate \
  "build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3"
```

版本真源 `.pluginval-version`。**不要**加 `--skip-gui-tests`：macOS 侧的编辑器（WKWebView）必须进验证范围，
这条全量运行就是本地门禁本身。

### 架构确认（只应有 arm64）

```bash
lipo -archs "build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3/Contents/MacOS/Synchain Bridge"
# 期望输出：arm64

file "build/SynchainBridgeVST_artefacts/Release/AU/Synchain Bridge.component/Contents/MacOS/Synchain Bridge"
# 期望含：Mach-O 64-bit bundle arm64
```

## 可选：命令行覆盖

### 试构建 universal（arm64 + x86_64）

两个架构变量都带 `NOT DEFINED` 守卫，命令行传值即可覆盖默认：

```bash
cmake -S . -B build-universal -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DJUCE_PATH="$HOME/dev/JUCE" \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
```

**这不是受支持的发布配置**：v1 只发 arm64。双架构会让 juceaide 与全部 JUCE 模块的编译量翻倍，
且 Intel 侧未经实测。要试请用**另一个 build 目录**（架构是缓存变量，改了得重配）。

### 额外 Origin 白名单（构建期注入）

与 Windows 完全同一套语义（同一份 CMake 代码），只是命令行写法不同：

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DJUCE_PATH="$HOME/dev/JUCE" \
  -DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="example-git-*-example-team.example.app;preview.example.com"
```

模式语法、通配段不跨 `.`、域名锚点 fail-closed、只在 https 下生效、值不得含引号或反斜杠等**全部规则见**
[build-windows.md 的「可选：额外 Origin 白名单」](build-windows.md#可选额外-origin-白名单构建期注入)，此处不重复。

## 关键坑（必读）

### 1. 架构与部署目标必须在 `project()` **之前**设置

`CMakeLists.txt` 顶部的 `CMAKE_OSX_ARCHITECTURES` / `CMAKE_OSX_DEPLOYMENT_TARGET` 参与编译器探测，
写在 `project()` 之后就晚了。尤其是部署目标：**不显式设则取构建机 SDK 的版本**，在新系统上打的包会在
老系统上直接拒绝加载——这是 mac 移植最常见的静默事故。两者都只对 Apple 平台有意义，Windows 构建完全忽略。

### 2. 本插件不是 sandbox-safe AU

`AU_SANDBOX_SAFE` 保持 JUCE 默认 `FALSE`，**不要改成 TRUE**：插件要 bind `127.0.0.1` 监听 socket 并起
WKWebView，两者在 AU sandbox 里都会被拒。代价是 **GarageBand（只加载 sandbox-safe AU）可能拒载**；
Logic 以非沙箱方式加载，不受影响。用 Logic / Reaper / Live 等宿主。

### 3. 改了 AU 一定要重启 AudioComponentRegistrar

AU 的组件信息有系统级缓存。重装后不 `killall -9 AudioComponentRegistrar`，`auval` 与 DAW 都可能仍在
校验上一次的副本，表现为「明明改了却没变」。VST3 无此问题。

### 4. macOS 上 ixwebsocket 走 FetchContent，不走包管理器

`CMakeLists.txt` 的依赖块按 `if(APPLE)` 分支：Windows 继续用 vcpkg `x64-windows-static`，macOS 用
`FetchContent` + 钉死的 `IXWEBSOCKET_TAG`。mac 侧显式关掉 `USE_TLS`（桥 #2 只在 `127.0.0.1` 上服务
明文 `ws://`，见 `src/VstBridgeServer.cpp` 的 `VstBridgeServer::start`），因此**不链接 mbedtls，也不需要
Security.framework**；压缩用的 zlib 取 macOS SDK 自带的系统库。要换 tag 请改 `IXWEBSOCKET_TAG` 而不是
在本地手工替换源码。

### 5. 浏览器侧：Safari 打不开 Creative Space

网页是 https，桥 #2 是 `ws://127.0.0.1`。**Safari 不给 localhost 开 mixed content 豁免**，握手会被直接拦掉。
mac 上请用 Chrome / Edge / Firefox 打开 Creative Space。这不是插件故障，插件日志里根本看不到这次连接。

### 6. 常见失败排查

- **`JUCE_PATH must be set`**：没传 `-DJUCE_PATH`，或路径指到了 JUCE 子目录而非根。
- **配置期卡在 `Fetching ixwebsocket`**：无网络或 git 被代理拦截。可先手工 `git clone --branch v11.4.6` 验证连通性。
- **`auval` 找不到组件**：没装到 `~/Library/Audio/Plug-Ins/Components/`，或没 `killall -9 AudioComponentRegistrar`。
- **DAW 里插件不显示 / 报架构不匹配**：宿主跑在 Rosetta（x86_64）下。本插件只有 arm64 slice，
  **勾「使用 Rosetta 打开」也加载不了**——请以原生 arm64 方式启动 DAW。
- **插件窗口是英文兜底面板**：WKWebView 加载超时（多见于首次冷启动）。点 Retry，或关掉插件窗口重开。

## CI 对照

CI（`.github/workflows/`）目前覆盖 Windows 构建与 pluginval；**macOS 侧的验收以本地门禁为准** ——
即上面「验证」一节的 `auval` + 全量（含 GUI）`pluginval` 两条都过。
