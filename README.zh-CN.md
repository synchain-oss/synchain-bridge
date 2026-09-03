[English](README.md) | **简体中文**

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platform: Windows x64 VST3 / macOS arm64 VST3 + AU](https://img.shields.io/badge/platform-Windows%20x64%20%C2%B7%20macOS%20arm64-lightgrey.svg)

# Synchain Bridge

> 把 DAW 音频通过本地 WebSocket 实时推流给远端协作者 —— Synchain 实时协作平台的开源插件端。

## 它解决什么问题

Synchain Bridge 是一个音频插件(Windows / macOS 出 **VST3**,macOS 另出 **AU**),把 DAW 里的一路立体声总线无损采集成 PCM,经本地 WebSocket 推流给远端协作者:

```
DAW → Synchain Bridge (PCM float32) → WebSocket(127.0.0.1) → 浏览器 → AudioWorklet → LiveKit Opus 编码 → 服务器
```

- **零附加延迟** —— 用 DAW 给的缓冲块大小,插件不额外累积,每块即发,穿透音频零附加延迟。
- **透明穿透** —— 不改动经过 DAW 轨道的声音;主音量 0–200% 只作用于推流副本。
- **实时电平表** —— L/R 峰值电平(dBFS)反映推流后电平。
- **玻璃拟态 WebView UI** —— 中 / EN / FR 三语,本地端口可编辑(默认 `9420`)。

> **⚠️ 免责声明:本仓库只含插件端,接收端是闭源 SaaS(即 Synchain 网页应用)。** 真正用起来需要一个 Synchain 账号与项目成员身份;本仓库不是可自建的服务器。

### 两条桥(架构)

| | 桥 #1:编辑器内 WebView ↔ C++ | 桥 #2:VstBridgeServer ↔ 浏览器 |
|---|---|---|
| 作用 | 驱动插件窗口 UI(本地进程内) | 把 DAW 音频推流给浏览器客户端 |
| 传输 | JUCE 原生集成(`window.__JUCE__`) | 本地 WebSocket(ixwebsocket,`127.0.0.1`) |
| 数据 | processor 原子量(电平/状态,不走 WebSocket) | PCM 二进制帧 + JSON |
| 契约方 | `WebViewEditor.cpp` ↔ `web/bridge.js` | `VstBridgeServer.cpp` ↔ Synchain 网页应用(闭源) |

wire 协议契约见 [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md)。

## 截图

Synchain Bridge 使用玻璃拟态 WebView UI(JUCE 8 WebView;Windows 走 WebView2,macOS 走 WKWebView)。截图将随首个公开版本发布。UI 提供:

- 语言切换(中 / EN / FR),选择会持久化
- 状态胶囊(在线/离线,脉冲点)+ 客户端数
- L/R 立体声电平表(dBFS)
- 采样率 / 声道 / 延迟
- 本地端口(可编辑,默认 `9420`)
- 主音量滑块 0–200%(只影响推流)
- 开始/停止传输;底部版本号

## 系统要求

两个平台共同:

- **CMake** ≥ 3.22
- **JUCE 8.0.8** — https://github.com/juce-framework/JUCE

Windows:

- **Windows x64** + **Visual Studio 2022**(「使用 C++ 的桌面开发」,MSVC v143 + Windows SDK);VS2019 BuildTools(v142)亦可。
- **vcpkg** + `ixwebsocket:x64-windows-static`
- **NuGet CLI**(`nuget.exe` 在 PATH;CMake 配置期自动拉 `Microsoft.Web.WebView2`)
- **Microsoft Edge WebView2 Runtime**(Windows 11 已内置;Win10 若无则装 Evergreen)

macOS:

- **macOS 11.0+(Big Sur)、Apple Silicon —— 仅 arm64**,需 **Xcode Command Line Tools**(`xcode-select --install`)。
- **Ninja**(可选;`brew install ninja` —— 文档里的命令以 Ninja 为例,用 Xcode 或 Makefile 生成器同样能出产物)。
- 无需 vcpkg / NuGet / WebView2:ixwebsocket 由 CMake 在配置期按钉死的 40 位 commit SHA(= 上游 tag v12.0.1)自动拉取,UI 用系统 WKWebView。

## 安装

两个平台的预编译版都在 [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases),均为 Release 构建并经 CI 验证(pluginval strictness 5;AU 另经 `auval`):

| 平台 | 资产 | zip 内容 |
|---|---|---|
| Windows x64 | `SynchainBridge-VST3-vX.Y.Z-win64.zip` | `Synchain Bridge.vst3` |
| macOS arm64 | `SynchainBridge-VST3-AU-vX.Y.Z-macos-arm64.zip` | `Synchain Bridge.vst3` + `Synchain Bridge.component` |

每个资产都附同名 `.sha256`。macOS 版**仅 Apple Silicon,且不签名不公证** —— 见 [macOS 已知限制](#macos-已知限制)与下面的解除隔离步骤。

插件用独立厂商码/插件码(`Snch` / `Snb1`),DAW 将其识别为独立插件。改这两个码会生成新的 VST3 唯一 ID(AU 身份同样变化),DAW 视为全新插件、旧工程会丢插件 —— **两个平台都绝对禁止改动**。

### Windows

构建产物(或解压后得到的)`Synchain Bridge.vst3` 是一个 **bundle 目录**(不是单文件),二选一安装:

- **系统目录(需管理员)**:把整个 `Synchain Bridge.vst3` 文件夹拷到 `C:\Program Files\Common Files\VST3\`
  ```powershell
  Copy-Item "<产物路径>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **免管理员**:把 `.vst3` 放任意目录,在 DAW 里把该目录加为 VST3 扫描路径后重扫(Reaper:选项 → 偏好 → 插件/VST → 添加路径 → 重新扫描)。

### macOS

产物有两份:`Synchain Bridge.vst3` 与 `Synchain Bridge.component`(AU),都是 **bundle 目录**。用 `ditto` 而不是 `cp -r`,以原样保留符号链接与扩展属性;并且**先删掉上一版**再拷 —— `ditto` 对已存在的目标目录是**合并**语义,上一版里被删掉的文件(改过名的字体、旧 helper 等)会留在新 bundle 里:

```bash
rm -rf ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3" \
       ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
ditto "<产物路径>/Synchain Bridge.vst3"      ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3"
ditto "<产物路径>/Synchain Bridge.component" ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
killall -9 AudioComponentRegistrar   # 清掉 AU 组件缓存,否则 DAW 扫到的仍是旧副本
```

macOS 版本**不签名、不公证**(v1)。自己构建出来的 bundle 不带 quarantine 属性;从 Releases(或浏览器、AirDrop)下载来的 zip 会带上 quarantine,系统直接拒绝加载,需解除一次隔离。下面两条对应上面的家目录路径,不需要 sudo;若改装到 `/Library/Audio/Plug-Ins/...`,复制需要管理员授权、两条命令都要加 `sudo`:

```bash
xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3"
xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
```

## macOS 已知限制

- **仅 arm64(Apple Silicon)**。产物没有 x86_64 slice,Intel Mac 不支持;并且在 Apple Silicon 上给 DAW 勾**「使用 Rosetta 打开」也加载不了** —— Rosetta(x86_64)宿主装不下 arm64 插件。请以原生 arm64 方式启动 DAW。这条最容易被误判成「插件坏了」。
- **GarageBand 可能拒载 AU**。GarageBand 只加载申报了 sandbox-safe 的 AU。本插件要监听本地 socket 并托管 WebView,两者在 AU sandbox 里都会被拒,故不作此申报。请用 Logic / Reaper / Live 等能加载非沙箱 AU 的宿主。
- **Safari 预计连不上桥(尚未在真机验证)**。网页走 https,桥 #2 是明文 `ws://127.0.0.1`;与 Chromium 不同,Safari 未知会给回环开 mixed content 豁免,握手预计在到达插件之前就被拦掉。mac 上建议用 Chrome / Edge / Firefox 打开 Creative Space —— 但这些浏览器首次也可能弹**本地网络访问**授权提示。以上两点均由浏览器行为推断、非本仓实测;若你实测过,欢迎开 issue 反馈结果。

## 快速上手

1. 在 DAW 的立体声轨上加载 **Synchain Bridge**
2. 点「开始传输」—— 插件在 `127.0.0.1:9420` 起 WebSocket 服务(占用时自动重试 9420-9429)
3. 打开 Synchain 网页端进入项目的 Creative Space;若自动连接失败,把插件显示的端口填进浏览器的 DAW 音频桥面板
4. 音频发布到 LiveKit 房间供协作者收听

**不装 DAW 的 UI/协议预览** —— 见 `web-preview/`(可脱离 Next.js 独立验证桥 #2,含 mock server):

```bash
cd web-preview && npm install
npm run mock          # 起 ws://localhost:9420 的 mock 插件(发二进制 PCM 帧)
npm run serve         # 用 http 托管 ../web(不能用 file://,ES module 会被 CORS 拦截)
```

## 从源码构建

### Windows

```powershell
# 一次性准备
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
C:\dev\vcpkg\vcpkg install ixwebsocket:x64-windows-static
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE

# 配置 + 构建(在仓库根目录)
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
# 产物: build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3
```

CMake 会在配置期用 `nuget` 把 `Microsoft.Web.WebView2` 拉到 `build/packages` 并链接静态 loader,无需手动装 SDK。

CI(`.github/workflows/ci.yml`,job `build-and-validate`,`windows-2022`):clone JUCE 8.0.8 → vcpkg 装 ixwebsocket → 装 WebView2 Evergreen Runtime → CMake 配置(拉 WebView2 NuGet)→ 构建 → pluginval `--skip-gui-tests`(strictness 5)。含 Editor 的全量 strictness-5 在真实 Windows 11 本地验证 —— 无桌面的 Server runner 无法托管 WebView2 编辑器。

### macOS

```bash
git clone --depth 1 --branch "$(tr -d '[:space:]' < .juce-version)" https://github.com/juce-framework/JUCE.git ~/dev/JUCE
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DJUCE_PATH="$HOME/dev/JUCE"
cmake --build build --parallel
# 产物: build/SynchainBridgeVST_artefacts/Release/{VST3,AU}/
```

无需 vcpkg / NuGet / WebView2 —— ixwebsocket 由 CMake 在配置期按钉死的 commit SHA(= 上游 tag v12.0.1)拉取,UI 用系统 WKWebView;目标架构 arm64,部署目标 macOS 11.0。完整指南(含 `auval` / pluginval 验收)见 [`docs/build-macos.md`](docs/build-macos.md)。

CI(`.github/workflows/ci.yml`,job `build-and-validate-macos`,`macos-15`):构建两种格式 → 断言产物为 arm64 单架构 → 对 VST3 跑 pluginval `--skip-gui-tests`(strictness 5)、对 AU 跑 `auval` → `ditto` 打 zip 传 artifact。含 GUI 的 pluginval、以及对 AU 的 pluginval 仍是本地门禁。

## 文档

- [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md) — wire 协议(桥 #1 + 桥 #2),冻结契约。
- [`docs/DAW_TEST_GUIDE.md`](docs/DAW_TEST_GUIDE.md) — DAW 端到端实测指南(Windows)。
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) — 第三方许可证声明。
- [`CHANGELOG.md`](CHANGELOG.md) — 版本历史。
- [`docs/build-windows.md`](docs/build-windows.md) — Windows 源码构建（依赖、配置、坑）。
- [`docs/build-macos.md`](docs/build-macos.md) — macOS 源码构建（arm64、VST3 + AU、安装、`auval` / pluginval）。
- [`docs/release.md`](docs/release.md) — 发布 runbook（改版本号 → 打 tag → `release.yml`）。
- [`docs/web-client.md`](docs/web-client.md) — 浏览器侧客户端在哪与耦合点。
- [`docs/webview-ui-pattern.md`](docs/webview-ui-pattern.md) — 如何复刻这套 WebView UI（复制清单 + 坑）。

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)(DCO、分支模型、本地 gates)。所有贡献者须遵守 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。安全问题请按 [`SECURITY.md`](SECURITY.md) 私下上报,勿公开开 issue。

## 许可证

Synchain Bridge 以 **GNU General Public License v3.0 or later** 发布([`LICENSE`](LICENSE))。

它构建于 **JUCE Framework**(AGPLv3 与商业双授权 —— 本项目使用 AGPLv3 选项,[JUCE LICENSE.md](https://github.com/juce-framework/JUCE/blob/master/LICENSE.md))。

VST 是 Steinberg Media Technologies GmbH 的商标。**VST3 SDK** 自 2025 年 11 月起按 MIT 许可证分发。

每个发布二进制对应的完整源码均在本仓库公开可得。

## 相关项目

- [SCVB](https://github.com/synchain-oss/scvb) — Synchain 创意人声平衡插件(Input/Output 成对)。
- [Synchain CLI](https://github.com/synchain-oss/synchain-cli) — Synchain 命令行工具。
- [synchain.ca](https://synchain.ca) — Synchain 平台。

## 状态

Windows x64(VST3)先行;macOS Apple Silicon(VST3 + AU)自 v1.5.0 起随 Windows zip 一同作为预编译资产发布 —— 不签名、仅 arm64,签名与公证留待后续版本。版本历史见 [`CHANGELOG.md`](CHANGELOG.md)。
