// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// Synchain Bridge — web-preview mock server(桥 #2 的本地替身)
// =============================================================================
// 纯 ESM,仅依赖 ws。行为对齐 BRIDGE_CONTRACT.md §二:
//   • 二进制 PCM 帧(buildPcmFrame:12 字节头 + float32 interleaved)
//   • JSON:server→client 发 status / settings / meter / ping
//   •       client→server 收 handshake / get_settings / set_settings / set_volume / pong
//   • 心跳:每 ~5s ping,超 ~12s 无 pong 则 close(4408)
//   • 只绑 127.0.0.1,端口 base..base+9 顺延(默认 9420)
// 启动:npm run mock(或 node mock-server.mjs [PORT])
// =============================================================================

import { WebSocketServer, WebSocket } from "ws";
import { buildPcmFrame, buildSineBlock } from "./pcm-frame.mjs";

const SAMPLE_RATE = 48000;
const CHANNELS = 2;
const BLOCK_SIZE = 256; // 与延迟对齐:1000*256/48000 ≈ 5.33 ms
const BLOCK_MS = (BLOCK_SIZE / SAMPLE_RATE) * 1000;
const LATENCY_MS = BLOCK_MS;
const OPUS_BITRATE = 128000;
const PLUGIN_NAME = "Synchain Bridge (mock)";
const PLUGIN_VERSION = "1.4.0";
const CONTRACT_VERSION = "2.0";

const HEARTBEAT_MS = 5000;
const HEARTBEAT_TIMEOUT_MS = 12000;

// 正弦 + 慢速包络(L/R 不同 LFO 频率 → 两路电平各自跳动,便于肉眼确认)。
const FREQ_L = 220;
const FREQ_R = 330;
const ENV_LFO_L = 0.7;
const ENV_LFO_R = 1.1;
const ENV_MIN = 0.05; // ≈ -26 dBFS
const ENV_MAX = 0.9; // ≈ -0.9 dBFS

const HOST = "127.0.0.1";
const PORT_BASE = parseInt(process.argv[2] ?? process.env.PORT ?? "9420", 10);

// ---------- 音频合成 ----------
function envelope(t, lfoRate) {
  return (
    ENV_MIN +
    (ENV_MAX - ENV_MIN) * (0.5 + 0.5 * Math.sin(2 * Math.PI * lfoRate * t))
  );
}

function peakDb(block, channel, channels) {
  let peak = 0;
  for (let i = channel; i < block.length; i += channels) {
    const a = Math.abs(block[i]);
    if (a > peak) peak = a;
  }
  return peak === 0 ? -Infinity : 20 * Math.log10(peak);
}

// ---------- 监听(只绑 127.0.0.1,base..base+9 顺延) ----------
async function listen(base, host) {
  let lastErr;
  for (let p = base; p < base + 10; p++) {
    try {
      const wss = await new Promise((resolve, reject) => {
        const s = new WebSocketServer({ host, port: p });
        s.once("listening", () => resolve(s));
        s.once("error", reject);
      });
      return { wss, port: p };
    } catch (err) {
      if (!err || err.code !== "EADDRINUSE") throw err;
      lastErr = err;
    }
  }
  throw lastErr ?? new Error(`no free port in ${base}..${base + 9}`);
}

const { wss, port } = await listen(PORT_BASE, HOST);

const clients = new Set();
const meta = new Map(); // ws -> { lastPongAt }

let sampleIndex = 0;

function broadcastBinary(buf) {
  for (const ws of clients) {
    if (ws.readyState === WebSocket.OPEN) ws.send(buf);
  }
}

function broadcastJson(obj) {
  const s = JSON.stringify(obj);
  for (const ws of clients) {
    if (ws.readyState === WebSocket.OPEN) ws.send(s);
  }
}

function sendStatus(ws) {
  ws.send(
    JSON.stringify({
      type: "status",
      connected: true,
      pluginName: PLUGIN_NAME,
      version: PLUGIN_VERSION,
      volume: 100,
      contract: CONTRACT_VERSION,
    }),
  );
}

function sendSettings(ws) {
  ws.send(
    JSON.stringify({
      type: "settings",
      sampleRate: SAMPLE_RATE,
      bufferSize: BLOCK_SIZE,
      channels: CHANNELS,
      opusBitrate: OPUS_BITRATE,
      latencyMs: LATENCY_MS,
    }),
  );
}

wss.on("connection", (ws) => {
  clients.add(ws);
  meta.set(ws, { lastPongAt: Date.now() });

  sendStatus(ws);
  sendSettings(ws);

  ws.on("message", (data, isBinary) => {
    if (isBinary) return; // mock 不消费 client→server 的二进制
    let m;
    try {
      m = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (!m || typeof m.type !== "string") return;
    if (m.type === "pong") {
      meta.get(ws).lastPongAt = Date.now();
    } else if (m.type === "handshake") {
      console.log(`[mock] handshake from ${m.username || m.userId || "?"}`);
    } else if (m.type === "get_settings") {
      sendSettings(ws);
    }
    // set_settings / set_volume:mock 无真实参数,no-op。
  });

  ws.on("close", () => {
    clients.delete(ws);
    meta.delete(ws);
  });
  ws.on("error", () => {});
});

// ---------- 音频循环:每块生成 256 样本正弦并广播 PCM 帧;每 ~50ms 广播一次 meter ----------
let lastMeterAt = 0;
const audioTimer = setInterval(
  () => {
    const t = sampleIndex / SAMPLE_RATE;
    const samples = buildSineBlock({
      sampleRate: SAMPLE_RATE,
      channels: CHANNELS,
      numSamples: BLOCK_SIZE,
      startSample: sampleIndex,
      freqL: FREQ_L,
      freqR: FREQ_R,
      gainL: envelope(t, ENV_LFO_L),
      gainR: envelope(t, ENV_LFO_R),
    });
    sampleIndex += BLOCK_SIZE;
    broadcastBinary(
      buildPcmFrame({ sampleRate: SAMPLE_RATE, channels: CHANNELS, samples }),
    );

    const now = Date.now();
    if (now - lastMeterAt >= 50) {
      lastMeterAt = now;
      const left = peakDb(samples, 0, CHANNELS);
      const right = CHANNELS > 1 ? peakDb(samples, 1, CHANNELS) : left;
      broadcastJson({
        type: "meter",
        left,
        right,
        peak: Math.max(left, right),
      });
    }
  },
  Math.max(1, BLOCK_MS),
);

// ---------- 心跳 ----------
const heartbeatTimer = setInterval(() => {
  const now = Date.now();
  for (const ws of clients) {
    const m = meta.get(ws);
    if (!m) continue;
    if (now - m.lastPongAt > HEARTBEAT_TIMEOUT_MS) {
      ws.close(4408, "heartbeat timeout");
    } else {
      ws.send(JSON.stringify({ type: "ping", timestamp: now }));
    }
  }
}, HEARTBEAT_MS);

console.log(`[mock] listening on ws://${HOST}:${port}`);
console.log(
  `[mock] PCM ${SAMPLE_RATE} Hz / ${CHANNELS} ch / ${BLOCK_SIZE} samples (${LATENCY_MS.toFixed(2)} ms)`,
);

function shutdown() {
  clearInterval(audioTimer);
  clearInterval(heartbeatTimer);
  for (const ws of clients) ws.close(1000, "server shutdown");
  wss.close(() => process.exit(0));
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
