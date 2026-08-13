// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// Synchain Bridge — 界面文案字典（中 / EN / FR）
// =============================================================================
// 真源为 claude design 稿的 T = {zh,en,fr}，此处原样搬入并补 `mono` 键。
// UI（index.html）通过 applyI18n(root, lang) 刷新所有静态 [data-t] 标签；
// 动态文案（状态/声道/按钮/提示）由 index.html 调 dict(lang) 自行渲染。
// =============================================================================

export const T = {
  zh: {
    online: "在线", offline: "离线", waiting: "等待连接", clients: "客户端", level: "电平", dbfs: "dBFS",
    sampleRate: "采样率", channels: "声道", stereo: "立体声", mono: "单声道", latency: "缓冲延迟",
    localPort: "本地端口", master: "主控音量", start: "开始传输", stop: "停止传输",
    startedHint: "正在传输到浏览器", stoppedHint: "待机 · 等待开始传输", waitingHint: "已启动 · 等待浏览器连接", scale: "界面缩放",
    scaleKeepTitle: "保持此缩放？", scaleKeepHint: "秒后自动恢复上一个尺寸", keep: "保持", cancel: "取消",
  },
  en: {
    online: "ONLINE", offline: "OFFLINE", waiting: "WAITING", clients: "CLIENTS", level: "LEVEL", dbfs: "dBFS",
    sampleRate: "Sample Rate", channels: "Channels", stereo: "Stereo", mono: "Mono", latency: "Buffer",
    localPort: "Local Port", master: "Master", start: "Start Bridge", stop: "Stop Bridge",
    startedHint: "Streaming to browser", stoppedHint: "Idle · ready to bridge", waitingHint: "Started · waiting for browser", scale: "UI Scale",
    scaleKeepTitle: "Keep this scale?", scaleKeepHint: "s until previous size is restored", keep: "Keep", cancel: "Cancel",
  },
  fr: {
    online: "EN LIGNE", offline: "HORS LIGNE", waiting: "EN ATTENTE", clients: "CLIENTS", level: "NIVEAU", dbfs: "dBFS",
    sampleRate: "Échantillon", channels: "Canaux", stereo: "Stéréo", mono: "Mono", latency: "Tampon",
    localPort: "Port local", master: "Master", start: "Démarrer le pont", stop: "Arrêter le pont",
    startedHint: "Diffusion vers le navigateur", stoppedHint: "Inactif · prêt à diffuser", waitingHint: "Démarré · en attente du navigateur", scale: "Échelle",
    scaleKeepTitle: "Garder cette échelle ?", scaleKeepHint: "s avant de rétablir la taille précédente", keep: "Garder", cancel: "Annuler",
  },
};

/** 取某语言字典，未知语言回落中文。 */
export function dict(lang) {
  return T[lang] || T.zh;
}

/**
 * 把 root 里所有 `data-t="key"` 元素的文本替换为当前语言字典对应值。
 * 返回该语言字典，供调用方渲染动态文案。
 */
export function applyI18n(root, lang) {
  const t = dict(lang);
  root.querySelectorAll("[data-t]").forEach((el) => {
    const key = el.getAttribute("data-t");
    if (t[key] != null) el.textContent = t[key];
  });
  return t;
}
