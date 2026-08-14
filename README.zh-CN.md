[English](README.md) | **简体中文**

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platform: Windows x64 VST3](https://img.shields.io/badge/platform-Windows%20x64%20VST3-lightgrey.svg)

# Synchain Bridge

> 把 DAW 音频通过本地 WebSocket 实时推流给远端协作者 —— Synchain 实时协作平台的开源插件端。

## 它解决什么问题

Synchain Bridge 是一个 **VST3 音频插件**,把 DAW 里的一路立体声总线无损采集成 PCM,经本地 WebSocket 推流给远端协作者:

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

Synchain Bridge 使用玻璃拟态 WebView UI(JUCE 8 WebView;Windows 走 WebView2)。截图将随首个公开版本发布。UI 提供:

- 语言切换(中 / EN / FR),选择会持久化
- 状态胶囊(在线/离线,脉冲点)+ 客户端数
- L/R 立体声电平表(dBFS)
- 采样率 / 声道 / 延迟
- 本地端口(可编辑,默认 `9420`)
- 主音量滑块 0–200%(只影响推流)
- 开始/停止传输;底部版本号

## 系统要求

- **Windows x64** + **Visual Studio 2022**(「使用 C++ 的桌面开发」,MSVC v143 + Windows SDK);VS2019 BuildTools(v142)亦可。
- **CMake** ≥ 3.22
- **JUCE 8.0.8** — https://github.com/juce-framework/JUCE
- **vcpkg** + `ixwebsocket:x64-windows-static`
- **NuGet CLI**(`nuget.exe` 在 PATH;CMake 配置期自动拉 `Microsoft.Web.WebView2`)
- **Microsoft Edge WebView2 Runtime**(Windows 11 已内置;Win10 若无则装 Evergreen)
- macOS:用系统 WKWebView,无需 NuGet / Runtime。

## 安装

从 [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases) 下载 Windows x64 预编译版(`SynchainBridge-VST3-vX.Y.Z-win64.zip`,Release 构建 + pluginval strictness 5 验证),或从源码构建(见下)。

构建产物(或解压后得到的)`Synchain Bridge.vst3` 是一个 **bundle 目录**(不是单文件),二选一安装:

- **系统目录(需管理员)**:把整个 `Synchain Bridge.vst3` 文件夹拷到 `C:\Program Files\Common Files\VST3\`
  ```powershell
  Copy-Item "<产物路径>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **免管理员**:把 `.vst3` 放任意目录,在 DAW 里把该目录加为 VST3 扫描路径后重扫(Reaper:选项 → 偏好 → 插件/VST → 添加路径 → 重新扫描)。

macOS:`.vst3` 放 `~/Library/Audio/Plug-Ins/VST3/`。

插件用独立厂商码/插件码(`Snch` / `Snb1`),DAW 将其识别为独立插件。改这两个码会生成新的 VST3 唯一 ID,DAW 视为全新插件、旧工程会丢插件 —— 绝对禁止改动。

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

CI(`.github/workflows/build-vst3.yml`,`windows-2022`):clone JUCE 8.0.8 → vcpkg 装 ixwebsocket → 装 WebView2 Evergreen Runtime → CMake 配置(拉 WebView2 NuGet)→ 构建 → pluginval `--skip-gui-tests`(strictness 5)。含 Editor 的全量 strictness-5 在真实 Windows 11 本地验证 —— 无桌面的 Server runner 无法托管 WebView2 编辑器。

## 文档

- [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md) — wire 协议(桥 #1 + 桥 #2),冻结契约。
- [`docs/DAW_TEST_GUIDE.md`](docs/DAW_TEST_GUIDE.md) — DAW 端到端实测指南(Windows)。
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) — 第三方许可证声明。
- [`CHANGELOG.md`](CHANGELOG.md) — 版本历史。
- 构建 / 发布 / 网页客户端指南正陆续补进 `docs/`。

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

Windows x64 VST3 先行,macOS 后续(与平台路线图一致)。版本历史见 [`CHANGELOG.md`](CHANGELOG.md)。
