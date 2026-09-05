# 契约变更说明 —— `<YYYYMMDD>-<slug>`

> 触碰冻结契约面（`BRIDGE_CONTRACT.md`、`src/WebSocketProtocol.{h,cpp}`）且 PR body 的 `contract-impact` 为
> `minor` / `major` 时，必须在**同一个 PR** 里以本模板新增一份 `docs/contract-changes/<YYYYMMDD>-<slug>.md`
> （`branch-gate` 的 Frozen-contract change guard 机器校验；`none` 级的纯文档澄清 / 登记快照不需要）。
> 分级定义与流程见 `CLAUDE.md` §5；协议真源永远是 `BRIDGE_CONTRACT.md`，本文件只是变更的说明与兼容性承诺。

| 项 | 值 |
|---|---|
| 日期 | `<YYYY-MM-DD>` |
| PR | `#<n>` |
| 级别（`contract-impact`） | `minor` / `major` |
| 契约版本 | `BRIDGE_CONTRACT_VERSION`：`<旧>` → `<新>`（patch 级不改版本） |
| 主仓跟进 | `<闭源主仓 issue/PR 链接>`（minor 可异步；major 必须先 RFC 并双读） |

## 改了什么

- `<消息类型 / 字段 / 字节布局的具体变化，逐条>`

## 兼容性说明（必填）

- **旧客户端遇到新插件**：`<行为>`
- **新客户端遇到旧插件**：`<行为>`
- **兼容窗口**：`<major 级必填：新旧双读保留到哪个插件 minor 版本>`

## 落地清单

- [ ] `BRIDGE_CONTRACT.md` 已更新（含 §五 变更记录）
- [ ] `CHANGELOG.md` 「契约变更」小节已记录
- [ ] PR 描述已 @ 主仓维护者同步
- [ ] 维护者已在 PR 里批准（本文档是 branch-gate 认的唯一机器凭据，标签不参与判定）
