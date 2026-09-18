# 契约变更说明 —— `20260918-sl433-first-frame-paint-delta`

> `branch-gate` 的 Frozen-contract change guard 分两档（`CLAUDE.md` §5，判据在 `.github/workflows/branch-gate.yml`）：
> **strict**（`src/WebSocketProtocol.{h,cpp}`、`src/BridgeApi.h`、`src/PcmFrame.h`）——碰到即须在**同一个 PR** 里以本模板
> 新增一份 `docs/contract-changes/<YYYYMMDD>-<slug>.md`，自申报 `none` 不免检；**loose**（`BRIDGE_CONTRACT.md`、
> `src/VstBridgeServer.{h,cpp}`）——PR body 申报 `contract-impact: none`（纯文档澄清 / 登记快照 / 不动 wire 的重构）
> 免检，`minor` / `major` 或未申报同样须新增本文档。凭据只认本 PR **新增**（`added`）的文档，改名 / 修改旧文档不算。
> 协议真源永远是 `BRIDGE_CONTRACT.md`；本文件只是变更的说明与兼容性承诺。

| 项 | 值 |
|---|---|
| 日期 | `2026-09-18` |
| PR | SL-433（`fix/SL-433-second-white` → `dev`；PR 号见本文档所在 PR） |
| 级别（`contract-impact`） | `none`（无 wire 变化；strict 级因触碰 `src/BridgeApi.h` 而新增本文档登记，`none` 申报不免检 —— 即本文档） |
| 契约版本 | `BRIDGE_CONTRACT_VERSION`：`2.0` → `2.0`（不变） |
| 主仓跟进 | 不需要：本变更无 wire 变化、不涉桥 #2，闭源网页端零感知（见下「兼容性说明」） |

## 改了什么

- **wire 零变化**：桥 #2（WebSocket）的帧格式、消息类型、字段、必填语义一个字节都没动
  （`WebSocketProtocol.*` / `VstBridgeServer.*` / `PcmFrame.h` 本次未触碰）。
- `src/BridgeApi.h` 的**时序/诊断面**命名空间 `synchain::bridge::timing` 新增一个常量：
  `FirstFramePaintDeltaKey = "paintDeltaMs"`。它是 **既有** `FirstFrameSignal`（`__bridge__firstFrame`，
  登记于 `docs/contract-changes/20260914-sl386-reveal-gate.md`）那条上行信号**载荷里**唯一被读的字段名。
  载荷此前是空对象 `{}`、C++ 侧整个丢掉；[SL-433] 起页面在有 `first-paint` 记录时带上
  `信号时刻 − first-paint 时刻` 的毫秒**差值**，C++ 侧只把它拼进诊断行
  （`first-frame signal after N ms ... (signal-firstPaint +M ms)`，没有 paint 记录时打 `(no paint record)`）。
- **它不进 `Fn::` 契约名表、不写进 `BRIDGE_CONTRACT.md` 的桥 #1 函数/事件表**，理由与
  `FirstFrameSignal` 逐条相同（`20260914-sl386-reveal-gate.md` 已论证，此处不复述）：走 JUCE **内建**通道、
  前端与 C++ 随同一 artifact 分发、不存在「两端各自部署」的现实组合。本次再加一条：
  **这个字段不参与任何放行判定**，放行仍全在 `WebViewRevealGate` 里；它读不到（字段缺失、类型不对、
  非有限 double）时 C++ 只是少打一段文案，控制流一个字节不变。
- 为什么把它立成常量而不是就地写字面量：这个名字跨了 web → C++ 两侧，任一侧打错一个字母的失败形态是
  C++ 打 `(no paint record)` —— 而那与「页面确实走了回落路 / 保险路」在日志里**逐字同形**，
  贴 log 回来的人分不出是哪一种。立成常量后由 `web-preview/reveal-first-frame.test.mjs` 第 ② 格
  **两侧逐字对拍**（页面侧写错、C++ 侧改写字面量，各有一格删除式注入必红）。

## 兼容性说明（必填）

- **旧客户端遇到新插件**：不存在该组合 —— `__bridge__firstFrame` 的两端（内嵌前端与 `WebViewEditor`）
  在同一个 VST3/AU bundle 里编译与分发，不存在独立部署的「旧前端」。桥 #2 的旧网页客户端遇到新插件：
  零影响（本字段不涉桥 #2，wire 零变化）。
- **新客户端遇到旧插件**：同上，不存在该组合。真要把新前端喂给不认这个字段的旧编辑器：
  JUCE 的事件监听拿到的是整个 `payload` 对象，多一个它不读的键**不会报错也不会改行为** ——
  旧编辑器照旧只当「信号到了」。反方向（旧前端不带这个字段喂给新编辑器）同样安全：
  新编辑器读不到就打 `(no paint record)`，放行逻辑不受影响。
- **兼容窗口**：不适用（`none` 级，无 wire 变化）。

## 落地清单

- [x] `BRIDGE_CONTRACT.md` §一 那条「时序/诊断面信号不进本表」的指路已补上本文档
      （§二/§五协议内容零改动，无 §五 变更记录可写）；§三 VERSION 行随插件版本同步。
- [x] `CHANGELOG.md` 「[未发布]」已记录（SL-433 词条，含「不涉及契约变更」声明）。
- [ ] PR 描述已含 `contract-impact: none` 申报并 @ 主仓维护者同步（告知性同步：无 wire 变化，无需主仓动作）。
- [ ] 维护者已在 PR 里批准（本文档是 `branch-gate` 认的唯一机器凭据，标签不参与判定）。
