# 网页客户端（浏览器侧）与耦合点

> 本仓库只含**插件端**。桥 #2 的浏览器侧客户端（接收 DAW 音频、把 PCM 发布进 LiveKit 房间的「DAW 音频桥」面板）是 **Synchain 网页应用的一部分（闭源）**，不随本仓库发布。本文说明：客户端在哪、与插件的耦合点、契约如何跨仓治理。
>
> 本文吸收了抽取前 `web-contract/MIGRATION.md` 唯一有价值的内容（「与插件（C++）的耦合点」一节：端口 9420 三处一致、协议真源与双端同步义务），并按 `BRIDGE_CONTRACT.md` §一/§五 的跨仓治理口径重写。原 MIGRATION.md 记录的是私有仓库内部的一次目录搬迁，其内部路径/分支名/历史项目名对公开读者是噪音，**不搬入本仓库**。

## 1. 客户端在哪

| 端 | 位置 | 说明 |
|---|---|---|
| 桥 #1：插件内嵌 WebView UI | 本仓 `web/` | 编译进插件二进制，跑在插件进程里，走 JUCE 原生集成 |
| 桥 #2：浏览器侧客户端 | Synchain 网页应用（闭源） | WebSocket 客户端 + 「DAW 音频桥」面板 + LiveKit 发布，不在本仓 |
| 本地开发 / 演示替代品 | 本仓 [web-preview/](../web-preview/README.md) | `mock-server.mjs`（mock 桥 #2）+ `pcm-frame.mjs`（PCM 帧构造真源）+ http 托管，与真桥同契约 |

## 2. 与插件的耦合点

### 2.1 默认端口 9420 三处一致

本仓三处锁死 **9420**：

- `src/BridgeApi.h:95` —— `synchain::plugin::DefaultPort = 9420`
- `web/bridge.js:22` —— `const DEFAULT_PORT = 9420`
- `web-preview/mock-server.mjs:42` —— `PORT_BASE`（默认 9420）

网页侧（闭源）也必须与 9420 一致（其 `preferredPort` / 连接面板 placeholder）。取舍与历史见 [BRIDGE_CONTRACT.md](../BRIDGE_CONTRACT.md) §四。

### 2.2 协议真源 = BRIDGE_CONTRACT.md

桥 #2 的 wire 格式——二进制 PCM 帧（12 字节头 `u32 sampleRate | u32 channels | u32 numSamples` + `float32` interleaved）与 JSON 文本帧（`status`/`meter`/`settings`/`volume`/`error`/`ping` 等精确 snake_case 字段）——唯一真源是 [BRIDGE_CONTRACT.md](../BRIDGE_CONTRACT.md) §二。两端实现都必须与它一致，改动不得破坏网页侧 WS 客户端。

### 2.3 双端同步义务（跨仓）

抽取后，C++ 端（本仓 `src/WebSocketProtocol.*` / `src/VstBridgeServer.*`）与 web 端（闭源网页应用）**分处两个仓库**，协议演进失去「同一 PR 原子改两端」的能力。靠两件事维系：

1. **协议版本号** `BRIDGE_CONTRACT_VERSION = "2.0"`（独立于插件版本，semver；真源 `src/BridgeApi.h:76-79`，经 `status` 帧可选字段 `contract` 上报，只增不改）。
2. **三级变更流程**（`BRIDGE_CONTRACT.md` §五）：patch（纯文档澄清，单仓 PR）/ minor（只增可选字段，Bridge 仓合并后主仓异步跟进）/ major（改字段名/布局/删消息/改必填语义，必须先 RFC PR → 主仓新旧双读 → 两侧上线后才移除旧路径，兼容窗口 ≥ 1 个插件 minor 版本）。

## 3. 契约治理与护栏

- 协议改动必须：① 写兼容性说明（旧客户端遇新插件 / 新客户端遇旧插件各自行为）；② 记入 [CHANGELOG.md](../CHANGELOG.md)「契约变更」小节；③ 在 PR 描述里 @ 主仓维护者同步。
- 机器护栏：PR 若改动 `BRIDGE_CONTRACT.md` / `src/WebSocketProtocol.*` / `src/VstBridgeServer.*` / `src/BridgeApi.h` 任一，`.github/workflows/contract-guard.yml` 要求 PR body 含一行 `contract-impact: none|minor|major`，缺则 fail。
