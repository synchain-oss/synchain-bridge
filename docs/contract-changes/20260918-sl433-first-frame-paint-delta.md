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
| PR | #37（SL-433，`feat/SL-433-second-white` → `dev`；⚠ 分支前缀必须是 `feat/*` 或 `feature/*`，`fix/*` 会被 `branch-gate` 拦掉，见 `CLAUDE.md` §1） |
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

### ⚠ 上面两条不是推理，是实测 —— 两个方向各一条证据

本仓有判例:**SL-132 就是「反向兼容论断与实现不符」**（新版无条件追加尾字段、旧版按定长比较整块拒载），
而本次正好是同一形态（**给既有事件的载荷加字段**）。所以 `contract-impact: none` 这个自申报
**先实测再写**，不靠读代码得出。

方法：pluginval strict 5 `--repeat 5` 真开窗（真 WebView2 宿主），诊断行经 `OutputDebugString`
由自建 DBWIN 捕获收取；捕获脚本**先跑自测探针**确认能捕到才开测（否则「没捕到」与「没打日志」
分不开）。每种组合单独重编，测完复原并复测。

| 方向 | 组合 | 实测到的诊断行 | 结果 |
|---|---|---|---|
| **旧 C++ + 新页面**（载荷多一个它不认识的字段） | `origin/dev` 的 `WebViewEditor.{h,cpp}` + `BridgeApi.h`，本 PR 的 `web/index.html` | `first-frame signal after N ms (still parked)`（**旧格式、无后缀**）×5 | 多出来的字段被**静默忽略**；`webview revealed (firstFrame)` 5/5；无崩、无 timeout、无 fallback |
| **新 C++ + 旧页面**（载荷里没有这个字段） | 本 PR 的 C++，`origin/dev` 的 `web/index.html`（`payload: {}`） | `first-frame signal after N ms (still parked) (no paint record)` ×5 | 走 `(no paint record)` 分支；`webview revealed (firstFrame)` 5/5；无崩、无 timeout、无 fallback |
| （对照）新 C++ + 新页面 | 本 PR HEAD | `... (signal-firstPaint +15..+18 ms)` ×5，复原后复测 `+14..+17 ms` ×3 | 新路确实生效（信号落在 first-paint 之后）；`firstFrame` 8/8 |

⇒ 两个方向都**不改变放行行为、不崩、不退化成超时兜底**，`none` 属实。

## 落地清单

- [x] `BRIDGE_CONTRACT.md` §一 那条「时序/诊断面信号不进本表」的指路已补上本文档
      （§二/§五协议内容零改动，无 §五 变更记录可写）；§三 VERSION 行随插件版本同步。
- [x] `CHANGELOG.md` 「[未发布]」已记录（SL-433 词条，含「不涉及契约变更」声明）。
- [x] PR 描述已含 `contract-impact: none` 申报；PR 已加 `status/frozen-contract` 标签
      （本仓口径：冻结契约面变更 = 变更文档 **+** 该标签）。
      **@ 主仓维护者：不适用** —— `none` 级、wire 零变化、不涉桥 #2，闭源网页端零感知，无需主仓动作
      （对照 `20260914-sl386-reveal-gate.md` 那份是「告知性同步」，本次连告知面都没有）。
- [ ] 维护者已在 PR 里批准（本文档是 `branch-gate` 认的唯一机器凭据，标签不参与判定）。
