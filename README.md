**English** | [简体中文](README.zh-CN.md)

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platform: Windows x64 VST3](https://img.shields.io/badge/platform-Windows%20x64%20VST3-lightgrey.svg)

# Synchain Bridge

> Stream your DAW audio to remote collaborators in real time — the open-source plugin side of the Synchain real-time collaboration platform.

## What it does

Synchain Bridge is a **VST3 audio plugin** that captures a stereo bus from your DAW and streams it, losslessly as PCM, to remote collaborators over a local WebSocket:

```
DAW → Synchain Bridge (PCM float32) → WebSocket (127.0.0.1) → browser → AudioWorklet → LiveKit Opus → server
```

- **Zero added latency** — audio is sent block-by-block as the DAW delivers it, with no extra accumulation.
- **Transparent passthrough** — the plugin never alters your DAW mix; a 0–200% master volume applies only to the streamed copy.
- **Live meters** — L/R peak level (dBFS) reflects the streamed signal.
- **Glassmorphism WebView UI** — localized in Chinese / English / French, with an editable local port (default `9420`).

> **⚠️ This repository contains only the plugin side; the receiving side is a closed-source SaaS (the Synchain web application).** To actually use it you need a Synchain account and membership in a project — this repo is not a self-hostable server.

### Architecture: the two bridges

| | Bridge #1: editor WebView ↔ C++ | Bridge #2: VstBridgeServer ↔ browser |
|---|---|---|
| Purpose | Drives the plugin window UI (in-process) | Streams DAW audio to the browser client |
| Transport | JUCE native integration (`window.__JUCE__`) | Local WebSocket (ixwebsocket, `127.0.0.1`) |
| Data | Processor atomics (levels/state, not over WebSocket) | PCM binary frames + JSON |
| Contract | `WebViewEditor.cpp` ↔ `web/bridge.js` | `VstBridgeServer.cpp` ↔ Synchain web app (closed source) |

The wire protocol is specified in [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md).

## Screenshots

Synchain Bridge uses a glassmorphism WebView UI (JUCE 8 WebView; WebView2 on Windows). Screenshots will be published with the first public release. The UI provides:

- Language switcher (中文 / EN / FR), persisted
- Status pill (online / offline, pulse dot) + connected client count
- L/R stereo level meters (dBFS)
- Sample rate / channels / latency readout
- Editable local port (default `9420`)
- Master volume slider 0–200% (stream only)
- Start / stop streaming + version footer

## Requirements

- **Windows x64** with **Visual Studio 2022** (Desktop development with C++; MSVC v143 + Windows SDK). VS2019 BuildTools (v142) also works.
- **CMake** ≥ 3.22
- **JUCE 8.0.8** — https://github.com/juce-framework/JUCE
- **vcpkg** + `ixwebsocket:x64-windows-static`
- **NuGet CLI** (`nuget.exe` on PATH; CMake fetches `Microsoft.Web.WebView2` at configure time)
- **Microsoft Edge WebView2 Runtime** (preinstalled on Windows 11; on Windows 10 install the Evergreen runtime)
- macOS: uses the system WKWebView; no NuGet / WebView2 runtime required.

## Install

Grab a prebuilt Windows x64 build from [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases) (`SynchainBridge-VST3-vX.Y.Z-win64.zip`, Release build validated with pluginval strictness 5), or build from source (below).

The build produces (or the zip contains) `Synchain Bridge.vst3` — a **bundle directory**, not a single file. Install either way:

- **System directory (admin)**: copy the whole `Synchain Bridge.vst3` folder to `C:\Program Files\Common Files\VST3\`
  ```powershell
  Copy-Item "<path>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **No admin**: put the `.vst3` anywhere and add that folder as a VST3 scan path in your DAW (Reaper: Options → Preferences → Plug-ins/VST → Add path → rescan).

macOS: place the `.vst3` in `~/Library/Audio/Plug-Ins/VST3/`.

The plugin uses dedicated manufacturer/plugin codes (`Snch` / `Snb1`), so DAWs see it as an independent plugin. Changing these codes would generate a new VST3 unique ID and orphan existing projects — never alter them.

## Quick start

1. Load **Synchain Bridge** on a stereo track in your DAW.
2. Click **Start streaming** — the plugin starts a WebSocket server on `127.0.0.1:9420` (auto-retries `9420–9429` if busy).
3. Open the Synchain web app, enter a project's Creative Space; if auto-connect fails, enter the port shown by the plugin into the DAW audio bridge panel.
4. Audio is published to the LiveKit room for collaborators to hear.

**Preview the UI without a DAW** — see `web-preview/` (a standalone mock server for bridge #2; no compile/DAW needed):

```bash
cd web-preview && npm install
npm run mock          # starts a mock plugin on ws://localhost:9420 (sends binary PCM frames)
npm run serve         # serves ../web over http (not file://; ES modules are blocked by CORS)
```

## Build from source

```powershell
# One-time setup
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
C:\dev\vcpkg\vcpkg install ixwebsocket:x64-windows-static
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE

# Configure + build (repo root)
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
# Artifact: build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3
```

At configure time CMake uses `nuget` to fetch `Microsoft.Web.WebView2` into `build/packages` and links the static loader — no manual SDK install needed.

CI (`.github/workflows/build-vst3.yml`, `windows-2022`) clones JUCE 8.0.8, installs ixwebsocket via vcpkg, installs the WebView2 Evergreen runtime, configures, builds, and runs pluginval `--skip-gui-tests` (strictness 5). The full strictness-5 run including the WebView2 editor is validated locally on real Windows 11 — a headless server runner cannot host the editor.

## Documentation

- [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md) — the wire protocol (bridge #1 + bridge #2), frozen contract.
- [`docs/DAW_TEST_GUIDE.md`](docs/DAW_TEST_GUIDE.md) — end-to-end DAW test guide (Windows).
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) — third-party license notices.
- [`CHANGELOG.md`](CHANGELOG.md) — release history.
- Build / release / web-client guides are being added under `docs/`.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the developer workflow (DCO, branch model, local gates). All contributors are expected to follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues must be reported per [`SECURITY.md`](SECURITY.md) — never in a public issue.

## License

Synchain Bridge is released under the **GNU General Public License v3.0 or later** ([`LICENSE`](LICENSE)).

It builds on the **JUCE Framework**, dual-licensed under AGPLv3 and a commercial licence — this project uses the AGPLv3 option (https://github.com/juce-framework/JUCE/blob/master/LICENSE.md).

VST is a trademark of Steinberg Media Technologies GmbH. The **VST3 SDK** is distributed under the MIT licence since November 2025.

Complete corresponding source for every released binary is available in this repository.

## Related projects

- [SCVB](https://github.com/synchain-oss/scvb) — the Synchain Creative Voice Balance plugins (input/output pair).
- [Synchain CLI](https://github.com/synchain-oss/synchain-cli) — the command-line interface for Synchain.
- [synchain.ca](https://synchain.ca) — the Synchain platform.

## Status

Windows x64 VST3 ships first; macOS follows (aligned with the platform roadmap). See [`CHANGELOG.md`](CHANGELOG.md) for the version history.

<!-- B07 no-op acceptance probe -->

