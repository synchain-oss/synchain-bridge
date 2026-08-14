# Changelog

> **v1.3.1 及更早版本的 git 历史与 Release 位于 Synchain 私有单体仓库(`DLsnows/Synchain`)。** 本文件仅回填这些版本的 release body 文字内容;旧 tag 不迁移到本仓(D6 全新首 commit,08 §3.4)。
>
> 首个公开版本 = **v1.4.0**(U6)。协议类改动记录在对应版本的「契约变更」小节。

## [1.4.0] — 首个公开版本

**首个在 `synchain-oss/synchain-bridge` 公开发布的版本。** 插件二进制与 v1.3.1 完全兼容:厂商码/插件码(`Snch` / `Snb1`)、`BUNDLE_ID`(`com.synchain.bridge`)与 wire 协议均未变,现有 DAW 工程无需重建。

### 新增

- 公开的 GitHub Release 分发渠道(tag `v1.4.0`,zip + sha256 草稿 Release,`release.yml`)。
- `web-preview/`:可脱离 DAW 独立预览 UI / 桥 #2 的 mock server(仅依赖 `ws`)。
- 独立仓库结构:源码迁入 `src/`,双语 README、CONTRIBUTING、SECURITY、CODE_OF_CONDUCT、CLAUDE、CHANGELOG 等协作文档齐备。
- 本版本不签名(U13);zip 内随附 LICENSE / THIRD-PARTY-NOTICES 与字体 OFL 全文。

### 契约变更

- 引入独立协议版本号 `BRIDGE_CONTRACT_VERSION = "2.0"`(与插件版本解耦);`status` 帧新增**可选字段** `contract:"2.0"`(只增不改,旧客户端 `??` 兜底忽略)。起点取 2.0:1.x 语义留给抽取前未版本化的历史。

### 兼容性

- 与 v1.3.1 完全兼容(见上);协议 2.0 为纯增量,对旧网页客户端零破坏。

## [1.3.1] — 2026-07-08(源仓库)

### 变更

- **版本号统一到单一真源**:`CMakeLists.txt` `project(VERSION 1.3.1)` → `JucePlugin_VersionString`,删除会漂移的手写常量 `plugin::Version="1.2.10"`。插件自身 WebView UI 与网页端现在都动态显示 v1.3.1。
- **兼容基线从 1.3.1 起**(不再兼容更早插件版本)。
- 基于 v1.3.0 的安全加固(Synchain issue 167 CSWSH 白名单 / issue 168 processBlock 实时安全 SPSC / issue 169 交织越界 / issue 170 心跳)。

## [1.3.0] — 2026-07-07(源仓库)

安全与实时稳定性加固版。

### 安全

- **Synchain issue 167(P1)CSWSH 防护**:本地 WebSocket 桥(`ws://127.0.0.1:9420`)严格校验握手 `Origin` —— 仅放行 prod 域 `synchain.cn` / `synchain.ca`、dev 域 `dev.synchain.cn` / `dev.synchain.ca`、精确匹配的 Vercel preview 前缀,以及 `localhost` / `127.0.0.1`。任意网页对插件桥的跨站 WebSocket 握手(CSWSH)被拒绝。

### 实时音频稳定性

- **Synchain issue 168(P1)processBlock 实时安全**:音频回调改走无锁 SPSC 环形缓冲(`juce::AbstractFifo`),发送线程仅在 start/stop 时创建/销毁 —— 音频线程内不再有锁、堆分配或阻塞调用。
- **Synchain issue 169 交织缓冲越界修复**:多声道交织写入的边界修正,消除潜在越界访问。
- **Synchain issue 170 心跳保活**:桥连接加入心跳机制,及时发现并处理断连。

## [1.2.10] — 2026-07-06(源仓库)

在 v1.2.0 基础上大量修复与增强,聚合 v1.2.1–v1.2.9 的改动。

### 连接性 / 前端(关键修复)

- **修「前端打不开 / 报无法打开此页」根因**:Windows 显式 `withBackend(webview2)`,不再回退到旧 IE 控件;加运行时探测 + 加载看门狗 + 兜底面板(缺运行时时引导安装)。
- **修 Windows 连不上房间**:桥接客户端由 `localhost` 改直连 `127.0.0.1`(避开 `localhost`→IPv6 `::1` 解析抖动)。

### 界面 / 电平表

- 电平表重做:按真实声道数渲染(单声道 1 条 / 立体声 2 条)、实时弹道 + 白色峰值保持线、未传输时归零。
- 铺满窗口 + **界面缩放档位 33%–300%**(固定设计盒 × zoom,高 DPI 稳健,无滚动条 / 黑边);尺寸**全局持久化**(新实例沿用);改档位有防呆确认弹窗(10s 自动恢复)。
- 连接状态灯反映**真实连接**(浏览器断开即回落「等待连接」);声道数**真实上报**(修此前网页恒显「立体声」)。

### 音量

- DAW 音量双向实时同步(网页音量条 ↔ 插件 `masterGain`),且避免回环/双向拖动打架;web→VST 音量改由编辑器 Timer 应用(修 `MessageManager::callAsync` 某些宿主不可靠执行)。

## [1.2.0] — 2026-07-02(源仓库)

首个 GitHub Release(Windows x64)。

### 功能

- WebView 玻璃拟态 UI(近乎复刻设计稿),中 / EN / FR 三语可切换并持久化。
- L/R 立体声电平表(dBFS,反映推流后电平)、采样率 / 声道 / 延迟实时显示。
- 主控音量 0–200%(可自动化,**只影响推流副本**,DAW 轨道穿透音频零改动)。
- 可编辑本地端口(默认 9420,占用自动避让)。
- 状态随工程保存。

### 验证

- 本地:VS2019 + JUCE 8.0.8 构建,`pluginval --strictness-level 5`(含 WebView2 编辑器)**全量通过**。
- CI(windows-2022):构建 + `pluginval --skip-gui-tests` strictness-5 通过(无头 Server 无法托管 WebView2 编辑器,编辑器在本地 Win11 验证)。
