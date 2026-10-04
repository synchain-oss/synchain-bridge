**English** | [简体中文](README.zh-CN.md)

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platform: Windows x64 VST3 + AAX / macOS arm64 VST3 + AU + AAX](https://img.shields.io/badge/platform-Windows%20x64%20%C2%B7%20macOS%20arm64-lightgrey.svg)

# Synchain Bridge

> Stream your DAW audio to remote collaborators in real time — the open-source plugin side of the Synchain real-time collaboration platform.

## What it does

Synchain Bridge is an **audio plugin** — VST3 on Windows and macOS, Audio Unit (AU) on macOS, and AAX for Avid Pro Tools on both (Beta) — that captures a stereo bus from your DAW and streams it, losslessly as PCM, to remote collaborators over a local WebSocket:

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

Synchain Bridge uses a glassmorphism WebView UI (JUCE 8 WebView; WebView2 on Windows, WKWebView on macOS). Screenshots will be published with the first public release. The UI provides:

- Language switcher (中文 / EN / FR), persisted
- Status pill (online / offline, pulse dot) + connected client count
- L/R stereo level meters (dBFS)
- Sample rate / channels / latency readout
- Editable local port (default `9420`)
- Master volume slider 0–200% (stream only)
- Start / stop streaming + version footer

## Requirements

Common to both platforms:

- **CMake** ≥ 3.22
- **JUCE 8.0.8** — https://github.com/juce-framework/JUCE

Windows:

- **Windows x64** with **Visual Studio 2022** (Desktop development with C++; MSVC v143 + Windows SDK). VS2019 BuildTools (v142) also works.
- **vcpkg** (a bootstrapped clone; ixwebsocket is pinned by the repo's `vcpkg.json` manifest and installed automatically at configure time — no manual `vcpkg install`)
- **NuGet CLI** (`nuget.exe` on PATH; CMake fetches `Microsoft.Web.WebView2` at configure time)
- **Microsoft Edge WebView2 Runtime** (preinstalled on Windows 11; on Windows 10 install the Evergreen runtime)

macOS:

- **macOS 11.0+ (Big Sur) on Apple Silicon — arm64 only**, with **Xcode Command Line Tools** (`xcode-select --install`).
- **Ninja** (optional; `brew install ninja` — the documented commands use it, but the Xcode and Makefile generators work too).
- No vcpkg / NuGet / WebView2: ixwebsocket is fetched by CMake at configure time (pinned to a 40-char commit SHA = upstream tag v12.0.1) and the UI runs on the system WKWebView.

## Install

Prebuilt builds for both platforms are on [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases), each Release build validated in CI (pluginval strictness 5, plus `auval` for the AU). AAX is the exception: pluginval cannot host AAX, so CI only checks the bundle structure and architecture and runs a packaging smoke test; acceptance in Pro Tools is done by hand:

| Platform | Asset | Contents |
|---|---|---|
| Windows x64 | `SynchainBridge-VST3-vX.Y.Z-win64.zip` | `Synchain Bridge.vst3` |
| macOS arm64 | `SynchainBridge-VST3-AU-vX.Y.Z-macos-arm64.zip` | `Synchain Bridge.vst3` + `Synchain Bridge.component` |
| Windows x64 (Pro Tools) | `SynchainBridge-AAX-vX.Y.Z-win64.zip` | `Synchain Bridge.aaxplugin` |
| macOS arm64 (Pro Tools) | `SynchainBridge-AAX-vX.Y.Z-macos-arm64.zip` | `Synchain Bridge.aaxplugin` |

Every asset ships a matching `.sha256`. The macOS build is **Apple Silicon only and is neither signed nor notarized** — see [Known limitations on macOS](#known-limitations-on-macos) and the quarantine step below.

The two AAX zips (Beta) are attached starting with the first release that ships AAX. They are PACE-signed by the maintainer on a local machine and added by hand to the release that CI drafts, so they can appear later than the VST3/AU zips of the same release. A file named `*-UNSIGNED.zip` (CI artifacts `aax-unsigned-win64` / `aax-unsigned-macos-arm64`) is the unsigned input to that signing step, **not a release** — retail Pro Tools will not load it.

The plugin uses dedicated manufacturer/plugin codes (`Snch` / `Snb1`), so DAWs see it as an independent plugin. Changing these codes would generate a new VST3 unique ID (and a new AU component identity) and orphan existing projects — **never alter them, on either platform**. AAX uses the same two codes as its manufacturer / product IDs, plus the AAX identifier `com.synchain.bridge` (the same string as the bundle ID), so the same rule applies to AAX.

### Windows

The build produces (or the zip contains) `Synchain Bridge.vst3` — a **bundle directory**, not a single file. Install either way:

- **System directory (admin)**: copy the whole `Synchain Bridge.vst3` folder to `C:\Program Files\Common Files\VST3\`. When upgrading, delete the previous folder first — `Copy-Item -Force` *merges* into an existing bundle and would leave files from the old version behind:
  ```powershell
  Remove-Item "C:\Program Files\Common Files\VST3\Synchain Bridge.vst3" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "<path>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **No admin**: put the `.vst3` anywhere and add that folder as a VST3 scan path in your DAW (Reaper: Options → Preferences → Plug-ins/VST → Add path → rescan).

### macOS

Two formats are produced: `Synchain Bridge.vst3` and `Synchain Bridge.component` (AU). Both are **bundle directories**. Use `ditto` rather than `cp -r` so symlinks and extended attributes survive — and delete the previous install first, because `ditto` *merges* into an existing bundle and would leave stale files (renamed fonts, old helpers) behind:

```bash
rm -rf ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3" \
       ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
ditto "<path>/Synchain Bridge.vst3"      ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3"
ditto "<path>/Synchain Bridge.component" ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
killall -9 AudioComponentRegistrar   # drop the cached AU component info, otherwise the DAW rescans the old copy
```

The macOS builds are **unsigned and un-notarized** (v1). A bundle you built yourself carries no quarantine flag; a zip downloaded from Releases (or via a browser, AirDrop, …) does, and macOS will refuse to load it until the flag is cleared. The commands below are for the per-user paths above and need no `sudo`; installing into `/Library/Audio/Plug-Ins/...` instead requires an admin prompt to copy and `sudo` on both commands:

```bash
xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/VST3/"Synchain Bridge.vst3"
xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
```

### Pro Tools (AAX)

Pro Tools scans a single system directory (there is no per-user directory), so installing needs administrator rights. Quit Pro Tools first. The `.aaxplugin` is a **bundle directory**; delete the previous copy before copying, because a copy over an existing bundle *merges*. The same commands are in the `INSTALL-AAX.txt` inside each AAX zip.

Windows (administrator PowerShell; `$env:CommonProgramW6432` is the 64-bit Common Files folder, usually `C:\Program Files\Common Files`):

```powershell
Remove-Item "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\Synchain Bridge.aaxplugin" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "<path>\Synchain Bridge.aaxplugin" "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\" -Recurse -Force
```

macOS (Apple Silicon; `ditto`, not `cp -r`, so symlinks and the executable bit survive):

```bash
sudo rm -rf "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
sudo ditto "<path>/Synchain Bridge.aaxplugin" "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
sudo xattr -dr com.apple.quarantine "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
```

Restart Pro Tools and look the plug-in up by name (**Synchain Bridge**) in an insert slot. It is registered with the AAX category "None", so when the menu is organized by category it may be listed under *Other* rather than a themed group. A signed bundle must not be modified — any change to a file inside it invalidates the signature — so always copy the whole folder as is.

## Known limitations on macOS

- **Apple Silicon (arm64) only.** There is no x86_64 slice, so Intel Macs are not supported — and on an Apple Silicon Mac, ticking **"Open using Rosetta"** on your DAW **will not make it load either**: a Rosetta (x86_64) host cannot load an arm64 plugin. Launch the DAW natively. This is the failure most often mistaken for a broken plugin.
- **GarageBand may refuse the AU.** GarageBand only loads AUs that declare themselves sandbox-safe. This plugin listens on a local socket and hosts a WebView, neither of which works inside the AU sandbox, so it does not make that declaration. Use Logic, Reaper, Live or another host that loads non-sandboxed AUs.
- **Safari is expected not to reach the bridge (not yet verified on a real Mac).** The web app is served over https while bridge #2 is a plain `ws://127.0.0.1` socket; unlike Chromium, Safari is not known to grant a mixed-content exemption for loopback, so the handshake should be blocked before it ever reaches the plugin. Prefer Chrome, Edge or Firefox on macOS — and note those may still show a *local network access* permission prompt the first time. Both halves of this are inferred from browser behaviour, not measured here; if you test it, please report what you see in an issue.

## Known limitations in Pro Tools (AAX)

- **Mono and stereo inserts only** (mono→mono and stereo→stereo). There is no AudioSuite version and no multi-mono variant.
- **Offline rendering does not stream.** While Pro Tools renders faster than real time (offline bounce, Track Commit, Freeze) the audio passes through untouched and nothing is metered or pushed to the browser; live streaming resumes once the render ends. This applies to the AAX build only — VST3 / AU behave as before.
- **Dynamic Plug-in Processing may pause the stream.** When no audio reaches the plug-in (for example a muted or silent track), Pro Tools can stop calling it, so streaming can pause until audio flows again.
- **Latency readout.** JUCE's AAX wrapper always prepares the plug-in with the AAX maximum block size of 1024 samples, so the panel's buffer / latency reading reflects 1024 samples (about 21.3 ms at 48 kHz), not your hardware buffer size.
- **Signing.** Release AAX files carry the maintainer's PACE signature, which retail Pro Tools requires. On Windows the code-signing certificate is self-signed, so Properties → Digital Signatures shows an untrusted signer; this is expected. On macOS the bundle is **not notarized**, so the `sudo xattr` step above is required.
- **Apple Silicon only, native Pro Tools.** The macOS AAX has an arm64 slice only; Pro Tools must run natively, not under Rosetta.
- **Unsigned builds** (anything you build yourself, or a `*-UNSIGNED.zip`) can only be loaded by Pro Tools Developer.
- **Diagnostics.** The plugin writes event-driven diagnostic lines prefixed `SynchainBridge:`; the ones most useful in Pro Tools are editor opened, a UI-scale resize the host refused, audio settings changed (these three only while the plug-in window is open) and host non-realtime on/off. On Windows, view them with Sysinternals DebugView (Capture Win32) and filter on that prefix; on macOS they go to Pro Tools' standard error, so start Pro Tools from Terminal to see them.

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

### Windows

```powershell
# One-time setup (no `vcpkg install` needed: vcpkg.json is a manifest, see below)
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE

# Configure + build (repo root)
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
# Artifact: build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3
```

At configure time the vcpkg toolchain reads the repo's `vcpkg.json` (manifest mode) and installs `ixwebsocket` 12.0.1 — pinned by `builtin-baseline` (a 40-char microsoft/vcpkg commit) plus an `overrides` entry — into `build/vcpkg_installed`; the first configure compiles it, later ones hit vcpkg's binary cache. CMake also uses `nuget` to fetch `Microsoft.Web.WebView2` into `build/packages` and links the static loader — no manual SDK install needed.

CI (`.github/workflows/ci.yml`, job `build-and-validate`, `windows-2022`) clones JUCE 8.0.8 (skipped on an `actions/cache` hit), installs the WebView2 Evergreen runtime, configures (vcpkg installs ixwebsocket from the manifest, with its binary cache persisted via `actions/cache`; the installed version is then asserted against `vcpkg.json`), builds, and runs pluginval `--skip-gui-tests` (strictness 5). Caches only speed things up — a miss clones / compiles as before. The full strictness-5 run including the WebView2 editor is validated locally on real Windows 11 — a headless server runner cannot host the editor.

### macOS

```bash
git clone --depth 1 --branch "$(tr -d '[:space:]' < .juce-version)" https://github.com/juce-framework/JUCE.git ~/dev/JUCE
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DJUCE_PATH="$HOME/dev/JUCE"
cmake --build build --parallel
# Artifacts: build/SynchainBridgeVST_artefacts/Release/{VST3,AU}/
```

No vcpkg, NuGet or WebView2 needed — CMake fetches ixwebsocket at configure time from a pinned commit SHA (= upstream tag v12.0.1), and the UI runs on the system WKWebView. The build targets arm64 with a macOS 11.0 deployment target. Full guide, including `auval` / pluginval acceptance: [`docs/build-macos.md`](docs/build-macos.md).

CI (`.github/workflows/ci.yml`, job `build-and-validate-macos`, `macos-15`) restores JUCE and the pinned ixwebsocket source from `actions/cache` (cloning on a miss and asserting the checkout equals the pinned SHA), builds both formats, asserts the binaries are arm64-only, runs pluginval `--skip-gui-tests` (strictness 5) against the VST3 and `auval` against the AU, and uploads a `ditto` zip of both bundles. The GUI pluginval run — and pluginval against the AU — remain local gates.

### AAX (Pro Tools)

The AAX SDK (2.8.0) ships inside JUCE 8.0.8, so no extra download is needed: the normal configure + build above also produces the AAX target on both platforms (CMake option `SYNCHAIN_BRIDGE_AAX`, ON by default; pass `-DSYNCHAIN_BRIDGE_AAX=OFF` to build VST3 / AU only).

```
build/SynchainBridgeVST_artefacts/Release/AAX/Synchain Bridge.aaxplugin
```

A build from source is **unsigned**: it loads only in Pro Tools Developer, and that is as far as an outside contributor can take it. On Windows, `pwsh scripts/build.ps1 -InstallAax` (administrator PowerShell) builds and copies it into the Pro Tools plug-in folder. To package it, use `pwsh scripts/package-aax.ps1 -Mode Unsigned` (Windows) or `bash scripts/package-aax-macos.sh --mode unsigned` (macOS), which produce a `*-UNSIGNED.zip`. Signing needs the maintainer's PACE credentials and is done by hand on a local machine — see [§7 of `docs/release.md`](docs/release.md#7-aaxpro-tools本机签名--手工上传). Per-platform details: [`docs/build-windows.md`](docs/build-windows.md#aaxpro-tools), [`docs/build-macos.md`](docs/build-macos.md#aaxpro-tools).

CI builds the AAX target on both platforms; the packaging scripts check the bundle structure and architecture (x64 PE on Windows, arm64-only on macOS) as part of a packaging smoke test — including a negative check that the signed mode refuses an unsigned bundle — and on push and manual (`workflow_dispatch`) runs the unsigned zip is uploaded as the `aax-unsigned-win64` / `aax-unsigned-macos-arm64` artifact (pull-request runs build a merge commit, so they only run the smoke test). CI does not run pluginval on AAX. Locally, `pwsh scripts/gates.ps1 -IncludeAax` adds the AAX structure and packaging gates on Windows.

## Documentation

- [`BRIDGE_CONTRACT.md`](BRIDGE_CONTRACT.md) — the wire protocol (bridge #1 + bridge #2), frozen contract.
- [`docs/DAW_TEST_GUIDE.md`](docs/DAW_TEST_GUIDE.md) — end-to-end DAW test guide (Windows; Pro Tools section for both platforms).
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) — third-party license notices.
- [`CHANGELOG.md`](CHANGELOG.md) — release history.
- [`docs/build-windows.md`](docs/build-windows.md) — Windows build from source (deps, configure, pitfalls, AAX).
- [`docs/build-macos.md`](docs/build-macos.md) — macOS build from source (arm64, VST3 + AU + AAX, install, `auval` / pluginval).
- [`docs/release.md`](docs/release.md) — release runbook (version bump → tag → `release.yml`; AAX signing and manual upload in §7).
- [`docs/web-client.md`](docs/web-client.md) — where the browser-side client lives and its coupling points.
- [`docs/webview-ui-pattern.md`](docs/webview-ui-pattern.md) — how to replicate this WebView UI (copy checklist + pitfalls).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the developer workflow (DCO, branch model, local gates). All contributors are expected to follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues must be reported per [`SECURITY.md`](SECURITY.md) — never in a public issue.

## License

Synchain Bridge is released under the **GNU General Public License v3.0 or later** ([`LICENSE`](LICENSE)).

It builds on the **JUCE Framework**, dual-licensed under AGPLv3 and a commercial licence — this project uses the AGPLv3 option (https://github.com/juce-framework/JUCE/blob/master/LICENSE.md).

VST is a trademark of Steinberg Media Technologies GmbH. The **VST3 SDK** is distributed under the MIT licence since November 2025.

The AAX build additionally includes the **Avid AAX SDK 2.8.0** (bundled with JUCE 8.0.8). The SDK is offered under Avid's commercial licence or the GPL v3; this project uses the GPL v3 option, so the AAX binaries as a whole are distributed under version 3 of the GPL (see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)).

Avid, Pro Tools and AAX are trademarks or registered trademarks of Avid Technology, Inc. PACE and iLok are trademarks of PACE Anti-Piracy, Inc. Synchain Bridge is an independent project, not affiliated with, sponsored or endorsed by Avid.

Complete corresponding source for every released binary is available in this repository.

## Related projects

- [SCVB](https://github.com/synchain-oss/scvb) — the Synchain Creative Voice Balance plugins (input/output pair).
- [Synchain CLI](https://github.com/synchain-oss/synchain-cli) — the command-line interface for Synchain.
- [synchain.ca](https://synchain.ca) — the Synchain platform.

## Status

Windows x64 (VST3) shipped first. macOS on Apple Silicon (VST3 + AU) has been published since v1.5.0 as a prebuilt Release asset alongside the Windows zip — unsigned and arm64 only; signing/notarization comes in a later release. AAX (Pro Tools) support for both platforms (Beta) is in development on the `feature/aax` branch; the AAX files are signed by the maintainer and uploaded by hand. See [`CHANGELOG.md`](CHANGELOG.md) for the version history.
