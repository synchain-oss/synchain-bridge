# Synchain Bridge VST3

把 DAW 音频通过本地 WebSocket 推流给 Synchain 网页端，让远端协作者实时高保真听到。UI 为 **JUCE 8 WebView**（玻璃拟态设计），Windows 走 WebView2。

## 音频管线

```
DAW → Synchain Bridge (PCM float32) → WebSocket(127.0.0.1) → 浏览器 → AudioWorklet → LiveKit Opus 编码 → 服务器
```

- **缓冲块**：用 DAW 给的缓冲块大小，插件不额外累积，每块即发，穿透音频零附加延迟。
- **主音量(0-200%)**：只作用于**推流给浏览器的副本**，不改动经过 DAW 轨道的声音。
- **延迟显示**：`1000 × 缓冲块 / 采样率` ms，仅展示（不向 host 报告延迟）。
- **编码**：Opus 编码在浏览器/LiveKit 侧，插件本身不编码。

## 两条桥（架构）

- **桥 #1**：插件窗口 = WebView，经 JUCE 原生集成与 processor 通信（电平/状态进程内直取，不走 WebSocket）。
- **桥 #2**：`VstBridgeServer`(ixwebsocket) ↔ 浏览器 WS 客户端（位于 Synchain 网页应用，闭源）。协议契约见 `BRIDGE_CONTRACT.md`。

## 前置依赖（本地构建）

- **Visual Studio 2022**（含「使用 C++ 的桌面开发」，MSVC v143 + Windows SDK）——VS2019 BuildTools（v142，生成器改 `Visual Studio 16 2019`）亦可，已实测通过
- **CMake** ≥ 3.22
- **JUCE 8.0.8** — https://github.com/juce-framework/JUCE
- **vcpkg** + `ixwebsocket:x64-windows-static`
- **NuGet CLI**（`nuget.exe` 在 PATH；CMake 配置期自动拉 `Microsoft.Web.WebView2`）
- **WebView2 Runtime**（Windows 11 已内置；Win10 若无则装 Evergreen）
- macOS：用系统 WKWebView，无需 NuGet / Runtime

## 构建（Windows）

```powershell
# 一次性准备
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
C:\dev\vcpkg\vcpkg install ixwebsocket:x64-windows-static
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE

# 配置 + 构建（在仓库根目录）
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
# 产物: build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3
```

CMake 会在配置期用 `nuget` 把 `Microsoft.Web.WebView2` 拉到 `build/packages` 并链接静态 loader，无需手动装 SDK。

## 下载（预编译）

不想自己编译可从 [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases) 下载 Windows x64 预编译版
（`SynchainBridge-VST3-vX.Y.Z-win64.zip`，Release 构建 + pluginval strictness 5 验证）。

## 安装 / 加载到 DAW

构建产物（或 Release 下载解压后的）`Synchain Bridge.vst3` 是一个 **bundle 目录**（不是单文件），二选一安装：

- **系统目录（需管理员）**：把整个 `Synchain Bridge.vst3` 文件夹拷到 `C:\Program Files\Common Files\VST3\`
  ```powershell
  Copy-Item "<产物路径>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **免管理员**：把 `.vst3` 放任意目录，在 DAW 里把该目录加为 VST3 扫描路径后重扫
  （Reaper：选项 → 偏好 → 插件/VST → 添加路径 → 重新扫描）

装好后在立体声轨插入 **Synchain Bridge**。插件用独立厂商码/插件码（`Snch` / `Snb1`），
DAW 将其识别为独立插件。macOS 同理，`.vst3` 放 `~/Library/Audio/Plug-Ins/VST3/`。

## 用法

1. 在 DAW 的立体声轨上加载 **Synchain Bridge**
2. 点「开始传输」——插件在 `127.0.0.1:9420` 起 WebSocket 服务（占用时自动重试 9420-9429）
3. 打开 Synchain 网页端进入项目的 Creative Space；若自动连接失败，把插件显示的端口填进浏览器的 DAW 音频桥面板
4. 音频发布到 LiveKit 房间供协作者收听

## 插件 UI（WebView）

- 语言切换（中 / EN / FR），选择会持久化
- 状态胶囊（在线/离线，脉冲点）+ 客户端数
- L/R 立体声电平表（dBFS，反映推流后电平）
- 采样率 / 声道 / 延迟
- 本地端口（可编辑，默认 9420）
- 主音量滑块 0-200%（只影响推流）
- 开始/停止传输；底部版本号

## 不装 DAW 的 UI/协议预览

见 `web-preview/`（可脱离 Next.js 独立验证桥 #2，含 mock server）：

```bash
cd web-preview && npm install
npm run mock          # 起 ws://localhost:9420 的 mock 插件（发二进制 PCM 帧）
npm run serve         # 用 http 托管 ../web（不能用 file://，ES module 会被 CORS 拦截）
```
然后在浏览器打开 `http://localhost:5173/index.html`（经 `bridge.js` 的 WsPreview 后端直连 mock）即可预览插件 UI + 交互，无需编译/DAW。

## CI

`.github/workflows/ci.yml`（windows-2022）：clone JUCE 8.0.8 → vcpkg 装 ixwebsocket → 装 WebView2 Evergreen Runtime → CMake 配置（拉 WebView2 NuGet）→ 构建 → pluginval `--skip-gui-tests`（strictness 5，验证协议/状态/参数/音频/总线等非 GUI 契约）。含 Editor 的全量 strictness-5 在真实 Windows 11 本地验证——无桌面的 Server runner 无法托管 WebView2 编辑器。

## 目录

| 文件 | 说明 |
|---|---|
| `PluginProcessor.{h,cpp}` | 音频抓取/推流增益/电平原子/端口·语言·状态持久化 |
| `WebViewEditor.{h,cpp}` | WebBrowserComponent 宿主 + JS↔C++ 桥 + 25Hz Timer |
| `VstBridgeServer.{h,cpp}` / `WebSocketProtocol.{h,cpp}` | 桥 #2 WS 服务与协议 |
| `AudioMeter.{h,cpp}` | 峰值电平（dBFS） |
| `BridgeApi.h` / `BRIDGE_CONTRACT.md` | 桥 #1/#2 契约（事件/函数名、WS 不变量、命名常量） |
| `web/` | WebView UI（index.html / styles.css / bridge.js / i18n.js / js/juce/index.js） |
| `web-preview/` | 桥 #2 mock server（独立验证预览，无需编译/DAW） |

## WebSocket 协议

见 `BRIDGE_CONTRACT.md` 第二节与 `WebSocketProtocol.h`。二进制 PCM 帧 = 12 字节头（`u32 sampleRate | u32 channels | u32 numSamples`）+ float32 interleaved；`meter`/`status`/`settings`(含可选 `latencyMs`)/`error`/`ping` 为 JSON 文本帧。
