// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// Synchain Bridge — 前端桥抽象（桥 #1 契约的 JS 实现）
// =============================================================================
// 统一 API，两种后端自动切换：
//   • JuceBackend    —— 插件内运行（检测到 window.__JUCE__），走 JUCE 原生集成
//   • WsPreviewBackend —— 纯浏览器预览（无 __JUCE__），直连 mock server(ws://localhost:9420)
//
// UI（web/index.html + i18n.js）只依赖本文件导出的 createBridge()，
// 不直接碰 window.__JUCE__ 或 WebSocket。事件名/函数名严格对应 BridgeApi.h / BRIDGE_CONTRACT.md。
// =============================================================================

const EVT = {
  STATE: "bridge.state",
  METER: "bridge.meter",
  AUDIO: "bridge.audio",
  ERROR: "bridge.error",
};
const DEFAULT_PORT = 9420;

/** dBFS -> 线性(0..1)，用于电平条宽度；-Infinity/极小值 -> 0 */
function dbToLinear(db) {
  if (!isFinite(db)) return 0;
  return Math.min(1, Math.max(0, Math.pow(10, db / 20)));
}

/** 简单事件分发器 */
function makeEmitter() {
  const map = new Map();
  return {
    on(evt, cb) {
      (map.get(evt) || map.set(evt, []).get(evt)).push(cb);
    },
    emit(evt, payload) {
      (map.get(evt) || []).forEach((cb) => cb(payload));
    },
  };
}

// ---------------------------------------------------------------------------
// JuceBackend —— 插件内
// ---------------------------------------------------------------------------
function makeJuceBackend(init) {
  const em = makeEmitter();
  const backend = window.__JUCE__.backend;
  // 把 C++ emit 的事件转给 UI
  [EVT.STATE, EVT.METER, EVT.AUDIO, EVT.ERROR].forEach((id) =>
    backend.addEventListener(id, (payload) => em.emit(id, payload)),
  );

  // 延迟加载 JUCE 官方前端 helper（仅插件内存在 window.__JUCE__ 时才 import）
  const nativePromise = import("./js/juce/index.js");
  const nf =
    (name) =>
    async (...args) => {
      const { getNativeFunction } = await nativePromise;
      return getNativeFunction(name)(...args);
    };

  return {
    isPreview: false,
    init,
    on: em.on,
    requestInitialState: nf("requestInitialState"),
    toggleRun: (shouldRun) => nf("toggleRun")(!!shouldRun),
    setPort: (port) => nf("setPort")(port | 0),
    setMasterGain: (pct) => nf("setMasterGain")(pct | 0),
    setLang: (code) => nf("setLang")(String(code)),
    setUiScale: (factor) => nf("setUiScale")(Number(factor) || 1),
    commitUiScale: () => nf("commitUiScale")(),
  };
}

// ---------------------------------------------------------------------------
// WsPreviewBackend —— 纯浏览器预览（把桥 #2 的 WS 消息映射成桥 #1 的事件）
// ---------------------------------------------------------------------------
function makeWsPreviewBackend(init, url) {
  const em = makeEmitter();
  const state = {
    running: false,
    clients: 0,
    port: init.port,
    volume: init.volume,
    lang: init.lang,
    sampleRate: 48000,
    channels: 2,
    latencyMs: null,
  };
  let ws = null;

  function connect() {
    try {
      ws = new WebSocket(url);
    } catch {
      return;
    }
    ws.binaryType = "arraybuffer";
    ws.onopen = () => {
      state.running = true;
      state.clients = 1;
      ws.send(
        JSON.stringify({
          type: "handshake",
          projectId: "preview",
          userId: "preview",
          username: "Preview",
        }),
      );
      em.emit(EVT.STATE, {
        running: state.running,
        clients: state.clients,
        port: state.port,
      });
    };
    ws.onmessage = (e) => {
      if (e.data instanceof ArrayBuffer) return; // 预览不解码 PCM
      let m;
      try {
        m = JSON.parse(e.data);
      } catch {
        return;
      }
      if (m.type === "meter") {
        em.emit(EVT.METER, {
          l: dbToLinear(m.left),
          r: dbToLinear(m.right),
          ldb: m.left,
          rdb: m.right,
          peak: m.peak,
        });
      } else if (m.type === "settings") {
        state.sampleRate = m.sampleRate;
        state.channels = m.channels;
        state.latencyMs = m.latencyMs ?? null;
        em.emit(EVT.AUDIO, {
          sampleRate: m.sampleRate,
          channels: m.channels,
          latencyMs: state.latencyMs,
        });
      } else if (m.type === "status") {
        state.running = true;
        em.emit(EVT.STATE, {
          running: true,
          clients: state.clients,
          port: state.port,
        });
      } else if (m.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", timestamp: m.timestamp }));
      }
    };
    ws.onclose = () => {
      state.running = false;
      state.clients = 0;
      em.emit(EVT.STATE, { running: false, clients: 0, port: state.port });
    };
    ws.onerror = () => {};
  }

  return {
    isPreview: true,
    init,
    on: em.on,
    async requestInitialState() {
      return {
        running: state.running,
        clients: state.clients,
        port: state.port,
        volume: state.volume,
        lang: state.lang,
        version: init.version,
        uiScale: init.uiScale,
        sampleRate: state.sampleRate,
        channels: state.channels,
        latencyMs: state.latencyMs,
      };
    },
    async toggleRun(shouldRun) {
      if (shouldRun) {
        connect();
        return { running: true, port: state.port };
      }
      if (ws) ws.close();
      return { running: false, port: state.port };
    },
    async setPort(port) {
      state.port = port | 0;
      return { ok: true, port: state.port };
    },
    async setMasterGain(pct) {
      state.volume = pct | 0;
      return { ok: true };
    },
    async setLang(code) {
      state.lang = String(code);
      return { ok: true };
    },
    // 预览无原生窗口：仅回执，缩放由 index.html 本地对卡片应用 zoom（applyPreviewFit）演示。
    async setUiScale(factor) {
      return { ok: true, scale: Number(factor) || 1 };
    },
    // 预览无全局设置文件：确认「保持」的回执 no-op。
    async commitUiScale() {
      return { ok: true };
    },
  };
}

// ---------------------------------------------------------------------------
// 工厂 —— UI 只调这一个
// ---------------------------------------------------------------------------
export function createBridge(opts = {}) {
  const previewUrl = opts.previewUrl || `ws://localhost:${DEFAULT_PORT}`;
  if (typeof window !== "undefined" && window.__JUCE__) {
    const init = readInit(window.__JUCE__.initialisationData);
    return makeJuceBackend(init);
  }
  const init = readInit(opts.previewInit);
  return makeWsPreviewBackend(init, previewUrl);
}

function readInit(src) {
  src = src || {};
  return {
    version: src.version ?? "1.3.1",
    port: (src.port ?? DEFAULT_PORT) | 0,
    volume: (src.volume ?? 100) | 0,
    lang: src.lang ?? "zh",
    uiScale: Number(src.uiScale) || 1,
  };
}

export { EVT, DEFAULT_PORT };
