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

namespace synchain {
namespace bridge {

// --- C++ -> JS 事件名（编辑器用 emitEventIfBrowserIsVisible 推送）----------
namespace Event {
  // {running:bool, clients:int, port:int} —— running 或 clients 变化时推送；web 状态灯据
  //   running+clients 派生 online/waiting/offline（clients==0 时为 waiting，让用户察觉链路已断）
  inline constexpr const char* State = "bridge.state";
  // {l:0..1, r:0..1, ldb:dBFS, rdb:dBFS, peak:dBFS}
  inline constexpr const char* Meter = "bridge.meter";
  // {sampleRate:int, channels:int, latencyMs:number}
  inline constexpr const char* Audio = "bridge.audio";
  // {code:string, message:string}
  inline constexpr const char* Error = "bridge.error";
}

// --- JS -> C++ 原生函数名（withNativeFunction 注册）------------------------
namespace Fn {
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
}

// --- withInitialisationData 预置键（首帧同步可读，无需往返）----------------
namespace Init {
  inline constexpr const char* Version = "version";
  inline constexpr const char* Port    = "port";
  inline constexpr const char* Volume  = "volume";   // 0..200
  inline constexpr const char* Lang    = "lang";     // "zh"|"en"|"fr"
}

} // namespace bridge

// --- 插件命名常量（与 CMake / getName / status 消息保持一致）---------------
// 版本号**不在此定义**：单一真源是 CMakeLists.txt `project(... VERSION ...)`
// → `JucePlugin_VersionString`。status 上报（PluginProcessor sendStatus）与插件
// WebView UI（WebViewEditor withInitialisationData / requestInitialState）一律取该宏，
// 避免手写常量随构建版本漂移。1.3.1 起以构建版本为唯一基线，不再兼容更早插件版本。
namespace plugin {
  inline constexpr const char* ProductName = "Synchain Bridge";
  inline constexpr const char* Company     = "Synchain";
  inline constexpr const char* BundleId    = "com.synchain.bridge";
  // VST3 唯一 ID 组成（改这两个会生成全新 ClassID，DAW 视为新插件）
  inline constexpr const char* ManufacturerCode = "Snch"; // PLUGIN_MANUFACTURER_CODE
  inline constexpr const char* PluginCode       = "Snb1"; // PLUGIN_CODE
  // 默认本地端口（与 web 契约 lib/store/vst.ts preferredPort / mock server 对齐）
  inline constexpr int         DefaultPort = 9420;
  inline constexpr int         MinPort     = 1024;
  inline constexpr int         MaxPort     = 65535;
  // 界面缩放档位范围（setUiScale 与 APVTS uiScale 共用；档位下拉见 web/index.html）
  inline constexpr float       DefaultUiScale = 1.0f;
  inline constexpr float       MinUiScale     = 0.33f;
  inline constexpr float       MaxUiScale     = 3.0f;
}

} // namespace synchain
