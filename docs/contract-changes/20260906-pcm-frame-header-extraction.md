# 契约变更说明 —— `20260906-pcm-frame-header-extraction`

> 本次为 **wire 逐字节零变化**的实现收敛：12 字节 PCM 帧头的编码从 `src/VstBridgeServer.cpp` 两处手写
> 收敛到新文件 `src/PcmFrame.h`。新文件定义了冻结布局的常量（偏移 / 头长），因此被纳入 branch-gate 的
> **strict** 档（碰到即要求变更说明，自申报 `none` 不免检）。本文档即该凭据：记录这次搬迁的事实与兼容性承诺。

| 项 | 值 |
|---|---|
| 日期 | 2026-09-06 |
| PR | #27（feat/pcm-frame-golden → feature/eng-debt-23；随 feature/eng-debt-23 晋升 dev） |
| 级别（`contract-impact`） | `none`（实现重构 + golden 测试；wire 零变化） |
| 契约版本 | `BRIDGE_CONTRACT_VERSION`：`2.0` → `2.0`（不变） |
| 主仓跟进 | 不需要（网页侧 WS 客户端零改动） |

## 改了什么

- 新增 `src/PcmFrame.h`（`synchain::pcm`，纯 C++17 标准库）：`kHeaderSize = 12`、`kSampleRateOffset = 0` /
  `kChannelsOffset = 4` / `kNumSamplesOffset = 8`、`writeU32LE` / `readU32LE`、`writeHeader` / `readHeader`、
  `payloadSize` / `frameSize`。
- `src/VstBridgeServer.cpp` 的同步遗留路径 `sendPcmPacket()` 与后台发送线程路径 `buildPcmFrame()` 改为调用
  `pcm::writeHeader` + `pcm::kHeaderSize`，不再各自手写偏移。掩码移位、`memcpy` 位置、空帧保护逐字保留。
- 新增 `tests/pcm_frame_selftest.cpp`（golden 字节钉死布局）与 `web-preview/pcm-frame.test.mjs`（JS mock 侧
  同一组 golden）；两平台 CI 与本地 gates 编译并运行；gate 3f / compliance 断言服务端必须经 `PcmFrame.h` 组帧。

## 兼容性说明（必填）

- **旧客户端遇到新插件**：行为完全不变。帧头三个 u32 小端字段的顺序、偏移、总长与改动前逐字节相同
  （golden：`(48000, 2, 512)` → `80 BB 00 00 | 02 00 00 00 | 00 02 00 00`，总长 4108）。
- **新客户端遇到旧插件**：不适用（客户端未改）。
- **兼容窗口**：不适用（无新旧双读）。

## 落地清单

- [x] `BRIDGE_CONTRACT.md` §二 第 1 条加实现指引（wire 描述一字未动，§五 机器护栏句同步列出 `src/PcmFrame.h`）
- [x] `CHANGELOG.md` [未发布]「内部工程（无契约变更）」已记录
- [x] 主仓维护者：无需同步（wire 零变化）
- [x] 维护者已在 PR 里批准（本文档是 branch-gate 认的唯一机器凭据，标签不参与判定）
