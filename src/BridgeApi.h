// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// =============================================================================
// Synchain Bridge — 编辑器内 JS <-> C++ 桥的契约常量（唯一真源）
// =============================================================================
// 本文件定义「桥 #1」（编辑器内 WebView <-> processor）的事件名 / 原生函数名，
// 以及插件的命名/版本常量。C++ 端（WebViewEditor）与前端（web/bridge.js）
// 必须严格使用这里定义的字符串。修改需同步更新 BRIDGE_CONTRACT.md 与 web/bridge.js。
//
// 注意：这里的「桥 #1」与「桥 #2」（VstBridgeServer <-> 浏览器 WS 协议，见
// WebSocketProtocol.h / BRIDGE_CONTRACT.md §WS）是两条独立的桥，切勿混淆。
// =============================================================================

namespace synchain
{
namespace bridge
{

// --- C++ -> JS 事件名（编辑器用 emitEventIfBrowserIsVisible 推送）----------
namespace Event
{
// {running:bool, clients:int, port:int} —— running 或 clients 变化时推送；web 状态灯据
//   running+clients 派生 online/waiting/offline（clients==0 时为 waiting，让用户察觉链路已断）
inline constexpr const char* State = "bridge.state";
// {l:0..1, r:0..1, ldb:dBFS, rdb:dBFS, peak:dBFS}
inline constexpr const char* Meter = "bridge.meter";
// {sampleRate:int, channels:int, latencyMs:number}
inline constexpr const char* Audio = "bridge.audio";
// {code:string, message:string}
inline constexpr const char* Error = "bridge.error";
} // namespace Event

// --- JS -> C++ 原生函数名（withNativeFunction 注册）------------------------
namespace Fn
{
// [] -> 全量快照 {running,clients,port,volume,lang,version,sampleRate,channels,latencyMs}
//      DOMContentLoaded 调用一次；同时置 C++ mBridgeReady=true（解决 emit-before-ready 竞态）
inline constexpr const char* RequestInitialState = "requestInitialState";
// [shouldRun:bool] -> {running:bool, port:int, error?:string}
inline constexpr const char* ToggleRun = "toggleRun";
// [port:int(1024..65535)] -> {ok:bool, port:int}
inline constexpr const char* SetPort = "setPort";
// [pct:int(0..200)] -> {ok:bool}
inline constexpr const char* SetMasterGain = "setMasterGain";
// [code:"zh"|"en"|"fr"] -> {ok:bool}
inline constexpr const char* SetLang = "setLang";
// [scale:float(0.33..3.0)] -> {ok:bool, scale:float, w:int, h:int}
//   仅缩放插件编辑器窗口（setSize = DESIGN×scale）做实时预览；web 侧卡片为固定 DESIGN 设计盒 + zoom:scale
//   铺满（不依赖 CSS 视口，v1.2.6 弃 (100/scale)% 避免 WebView2 resize 视口不同步致右下黑边）。
//   **不**写全局默认（防呆：未确认档位不落盘）——确认「保持」时才由 CommitUiScale 落盘。
inline constexpr const char* SetUiScale = "setUiScale";
// [] -> {ok:bool, scale:float}
//   防呆确认「保持」后调用：把当前（已确认）uiScale 写入全局默认设置文件，新实例/新工程沿用。
inline constexpr const char* CommitUiScale = "commitUiScale";
} // namespace Fn

// --- 时序/诊断面（**非契约**）：JUCE 内建 __JUCE__.postMessage ←→ withEventListener 通道 ---
// [SL-386] 前端「首帧已绘」上行信号名。**不进**上面的 Fn:: 契约名表：它是插件内嵌前端与编辑器
// 之间的一次性时序信号 —— 前端随插件同一 artifact 分发，不存在「新旧两端各自部署」的兼容面；
// 走 JUCE 内建通道（window.__JUCE__.postMessage ←→ Options::withEventListener），不经 bridge.js、
// 不占 Fn:: 名表（同 JUCE 自己 __juce__ 前缀的惯例；与 SCVB 的 __scvb__firstFrame 同口径）。
// 判定为非协议面的完整理由与兼容性承诺见 docs/contract-changes/ 下 SL-386 的变更文档；
// 机理与判据只写在 src/WebViewRevealGate.h 一处。web/index.html 的 <head> 内联脚本逐字引用
// 这里的字面量（web-preview/reveal-first-frame.test.mjs 钉两处相等）。
namespace timing
{
inline constexpr const char* FirstFrameSignal = "__bridge__firstFrame";

// [SL-433] 上面那条信号载荷里**唯一**被读的字段名：页面量到的
// `信号时刻 − first-paint 时刻`（毫秒差值，**只进诊断日志，不参与任何放行判定**）。
// 与 FirstFrameSignal 同属时序/诊断面、同样不进 Fn:: 名表（判定与兼容性承诺见
// docs/contract-changes/20260918-sl433-first-frame-paint-delta.md）。
// ⚠ 为什么单独立常量、不就地写字面量：这个名字跨了 web → C++ 两侧，任一侧打错一个字母的
// 失败形态是 **C++ 打 `(no paint record)`** —— 而那与「页面确实走了回落路 / 保险路」在日志里
// **逐字同形**，贴 log 回来的人分不出是哪一种，这个诊断字段就失去存在意义。立成常量之后，
// web-preview/reveal-first-frame.test.mjs 第 ② 格照 FirstFrameSignal 的同一个 shape 逐字对拍。
inline constexpr const char* FirstFramePaintDeltaKey = "paintDeltaMs";
} // namespace timing

// --- withInitialisationData 预置键（首帧同步可读，无需往返）----------------
namespace Init
{
inline constexpr const char* Version = "version";
inline constexpr const char* Port = "port";
inline constexpr const char* Volume = "volume"; // 0..200
inline constexpr const char* Lang = "lang"; // "zh"|"en"|"fr"
} // namespace Init

} // namespace bridge

// --- 桥接契约协议版本（BRIDGE_CONTRACT_VERSION；独立于插件版本，semver）-----
// 起点定 2.0（08 §1.3 / U6）：1.x 语义留给「抽取前的未版本化历史」，避免与插件版本号混淆。
// wire 上报：status 帧新增可选字段 contract（只增不改；旧 web 客户端 `??` 兜底忽略）。
// 真源约束：改这里必须同步改 BRIDGE_CONTRACT.md 头部「协议版本」行，并走 §五 变更流程。
namespace contract
{
inline constexpr const char* ContractVersion = "2.0";
} // namespace contract

// --- 插件命名常量（与 CMake / getName / status 消息保持一致）---------------
// 版本号**不在此定义**：单一真源是 CMakeLists.txt `project(... VERSION ...)`
// → `JucePlugin_VersionString`。status 上报（PluginProcessor sendStatus）与插件
// WebView UI（WebViewEditor withInitialisationData / requestInitialState）一律取该宏，
// 避免手写常量随构建版本漂移。1.3.1 起以构建版本为唯一基线，不再兼容更早插件版本。
namespace plugin
{
inline constexpr const char* ProductName = "Synchain Bridge";
inline constexpr const char* Company = "Synchain";
inline constexpr const char* BundleId = "com.synchain.bridge";
// VST3 唯一 ID 组成（改这两个会生成全新 ClassID，DAW 视为新插件）
inline constexpr const char* ManufacturerCode = "Snch"; // PLUGIN_MANUFACTURER_CODE
inline constexpr const char* PluginCode = "Snb1"; // PLUGIN_CODE
// 默认本地端口（与 web 契约 lib/store/vst.ts preferredPort / mock server 对齐）
inline constexpr int DefaultPort = 9420;
inline constexpr int MinPort = 1024;
inline constexpr int MaxPort = 65535;
// 界面缩放档位范围（setUiScale 与 APVTS uiScale 共用；档位下拉见 web/index.html）
inline constexpr float DefaultUiScale = 1.0f;
inline constexpr float MinUiScale = 0.33f;
inline constexpr float MaxUiScale = 3.0f;
} // namespace plugin

} // namespace synchain
