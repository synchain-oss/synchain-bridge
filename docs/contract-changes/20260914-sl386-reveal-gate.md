# 契约变更说明 —— `20260914-sl386-reveal-gate`

> `branch-gate` 的 Frozen-contract change guard 分两档（`CLAUDE.md` §5，判据在 `.github/workflows/branch-gate.yml`）：
> **strict**（`src/WebSocketProtocol.{h,cpp}`、`src/BridgeApi.h`、`src/PcmFrame.h`）——碰到即须在**同一个 PR** 里以本模板
> 新增一份 `docs/contract-changes/<YYYYMMDD>-<slug>.md`，自申报 `none` 不免检；**loose**（`BRIDGE_CONTRACT.md`、
> `src/VstBridgeServer.{h,cpp}`）——PR body 申报 `contract-impact: none`（纯文档澄清 / 登记快照 / 不动 wire 的重构）
> 免检，`minor` / `major` 或未申报同样须新增本文档。凭据只认本 PR **新增**（`added`）的文档，改名 / 修改旧文档不算。
> 协议真源永远是 `BRIDGE_CONTRACT.md`；本文件只是变更的说明与兼容性承诺。

| 项 | 值 |
|---|---|
| 日期 | `2026-09-14` |
| PR | #34(fix/SL-386-reveal-gate → dev) |
| 级别（`contract-impact`） | `none`（无 wire 变化；strict 级因触碰 `src/BridgeApi.h` 而新增本文档登记，`none` 申报不免检 —— 即本文档） |
| 契约版本 | `BRIDGE_CONTRACT_VERSION`：`2.0` → `2.0`（不变） |
| 主仓跟进 | 不需要：本变更无 wire 变化、不涉桥 #2，闭源网页端零感知（见下「兼容性说明」） |

## 改了什么

- **wire 零变化**：桥 #2（WebSocket）的帧格式、消息类型、字段、必填语义一个字节都没动
  （`WebSocketProtocol.*` / `VstBridgeServer.*` / `PcmFrame.h` 本次未触碰）。
- 桥 #1 侧新增一个**时序/诊断面**上行信号：`src/BridgeApi.h` 新增
  `synchain::bridge::timing::FirstFrameSignal = "__bridge__firstFrame"`。它**不进** `Fn::` 契约名表、
  **不写进** `BRIDGE_CONTRACT.md` 的桥 #1 函数/事件表，理由：
  1. 走 JUCE **内建**通道（前端 `window.__JUCE__.postMessage ←→ C++ Options::withEventListener`），
     不经 `web/bridge.js`、不占用 `withNativeFunction` 名表 —— 与 JUCE 自己的 `__juce__` 前缀内建通道同族；
  2. 它是插件**内嵌前端**与编辑器之间的一次性「首帧已绘」时序信号（SL-386 开窗遮挡闸的唯一正常放行路），
     前端与 C++ 随同一 artifact 分发，不存在「两端各自部署、版本错开」的现实组合 —— 这正是契约面存在的前提；
  3. 载荷为空、只发一次、无返回值，没有可漂移的语义面。
  与 SCVB 的 `__scvb__firstFrame` 同口径（scvb @ 76ffb04 `src/plugin-common/WebViewHost.h` 的
  `kFirstFrameEventId`，同走内建通道、同判非契约）。

## 兼容性说明（必填）

- **旧客户端遇到新插件**：不存在该组合 —— `__bridge__firstFrame` 的两端（内嵌前端与 WebViewEditor）
  在同一个 VST3/AU bundle 里编译与分发，不存在独立部署的「旧前端」。桥 #2 的旧网页客户端遇到新插件：
  零影响（本信号不涉桥 #2，wire 零变化）。
- **新客户端遇到旧插件**：同上，不存在该组合；内嵌前端在检测不到 `window.__JUCE__`（浏览器预览）或
  对端未注册监听（理论上的旧编辑器）时静默失败，前端以 `try` 包裹、静默返回 —— 还有 C++ 侧 3s 超时兜底，
  任何一侧缺失都只会退化为「多等 3s 占位」，不会崩、不会卡。
- **兼容窗口**：不适用（`none` 级，无 wire 变化）。

## 落地清单

- [x] `BRIDGE_CONTRACT.md` 已更新：仅 §三 VERSION 行随插件版本 1.5.0 → 1.5.1 的登记快照同步；
      协议内容（§一/§二/§五）零改动 —— 时序信号按上文判定**不进**协议面，故无 §五 变更记录可写。
- [x] `CHANGELOG.md` 「[未发布]」已记录（见「修复」词条的「不涉及契约变更」声明）。
- [x] PR 描述已含 `contract-impact: none` 申报并 @ 主仓维护者同步（告知性同步：无 wire 变化，无需主仓动作）。
- [ ] 维护者已在 PR 里批准（本文档是 branch-gate 认的唯一机器凭据，标签不参与判定）
