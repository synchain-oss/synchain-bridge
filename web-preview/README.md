# web-preview — Synchain Bridge UI preview (no DAW)

Runs the Synchain Bridge WebView UI in a plain browser, driven by a mock of bridge #2 — the
local WebSocket the plugin exposes on `127.0.0.1:9420`. No DAW, no C++ compile, no WebView2.

## Why two processes

- `npm run mock` — a mock plugin (`mock-server.mjs`) listening on `ws://localhost:9420`.
  It sends binary PCM frames plus `status` / `settings` / `meter` / `ping` JSON, matching
  the real `VstBridgeServer` (see `BRIDGE_CONTRACT.md` §二).
- `npm run serve` — an http server for `../web`.

> **Do not open `web/index.html` directly as `file://`.** The UI is an ES module
> (`<script type="module">`), and `file://` origins are blocked by CORS, so the page fails
> to load. Always serve it over http.

## Prerequisites

Node.js ≥ 18 and npm. The only runtime dependency is [`ws`](https://www.npmjs.com/package/ws).

## Quick start

```bash
cd web-preview
npm install
npm run mock     # terminal 1 — mock plugin on ws://localhost:9420
npm run serve    # terminal 2 — http server on http://localhost:5173
```

Then open <http://localhost:5173/index.html>.

If `npx serve` is unavailable, use the Python fallback:

```bash
npm run serve:python
# or: python -m http.server 5173 --directory ../web
```

## What you should see

1. Click **Start Bridge** — the status pill turns green (ONLINE).
2. The L/R meters pulse with the mock sine wave.
3. Readout shows sample rate **48.0 kHz**, **stereo**, latency **≈5.3 ms**.
4. The language switcher (中 / EN / FR) works and is persisted in the preview.
5. The **UI scale** dropdown applies instantly and asks for a 10-second confirmation
   (auto-reverts if not confirmed) — the anti-misclick guard from the real editor.

## Port

Default port is **9420**, kept consistent with `src/BridgeApi.h` (`DefaultPort`) and
`web/bridge.js` (`DEFAULT_PORT`). The mock auto-retries `9420–9429` if busy, mirroring the
plugin. Override with:

```bash
PORT=9430 npm run mock
# or: node mock-server.mjs 9430
```

## Files

- `mock-server.mjs` — mock bridge #2 server (pure ESM, only dependency: `ws`).
- `pcm-frame.mjs` — PCM binary frame builder (12-byte header `u32 sampleRate | u32 channels |
  u32 numSamples` + `float32` interleaved), the single source of truth for the frame layout used here.
- `package.json` — `mock` / `serve` scripts; only runtime dependency is `ws`.
