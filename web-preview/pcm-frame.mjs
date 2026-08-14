// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// Synchain Bridge — PCM 帧构造真源(桥 #2 二进制帧,严格按 BRIDGE_CONTRACT.md §二 1)
// =============================================================================
// 帧布局(小端):
//   12 字节头 = u32 sampleRate | u32 channels | u32 numSamples
//   紧接 numSamples * channels 个 float32 interleaved
//   总字节 = 12 + numSamples * channels * 4
// 本模块只依赖 Node 内建 Buffer,纯 ESM,无第三方依赖。
// =============================================================================

export const HEADER_BYTES = 12;

/** 计算一帧的总字节数。 */
export function frameByteLength(channels, numSamples) {
  return HEADER_BYTES + numSamples * channels * 4;
}

/**
 * 由交错 float32 样本构造一帧二进制 PCM。
 * @param {{sampleRate:number, channels:number, samples:Float32Array|ArrayLike<number>}} opts
 *   samples 长度必须 = numSamples * channels(interleaved)。
 * @returns {Buffer} 小端二进制帧。
 */
export function buildPcmFrame({ sampleRate, channels, samples }) {
  if (!Number.isInteger(sampleRate) || sampleRate <= 0) {
    throw new RangeError("sampleRate must be a positive integer");
  }
  if (!Number.isInteger(channels) || channels <= 0) {
    throw new RangeError("channels must be a positive integer");
  }
  if (!samples || samples.length % channels !== 0) {
    throw new RangeError("samples.length must be a multiple of channels");
  }
  const numSamples = samples.length / channels;
  const buf = Buffer.allocUnsafe(frameByteLength(channels, numSamples));
  buf.writeUInt32LE(sampleRate >>> 0, 0);
  buf.writeUInt32LE(channels >>> 0, 4);
  buf.writeUInt32LE(numSamples >>> 0, 8);
  for (let i = 0; i < samples.length; i++) {
    buf.writeFloatLE(samples[i], HEADER_BYTES + i * 4);
  }
  return buf;
}

/**
 * 生成一段正弦波(interleaved float32),相位跨块连续。
 * @returns {Float32Array}
 */
export function buildSineBlock({
  sampleRate = 48000,
  channels = 2,
  numSamples = 256,
  startSample = 0,
  freqL = 220,
  freqR = 330,
  gainL = 1,
  gainR = 1,
} = {}) {
  const out = new Float32Array(numSamples * channels);
  for (let i = 0; i < numSamples; i++) {
    const t = (startSample + i) / sampleRate;
    out[i * channels] = Math.sin(2 * Math.PI * freqL * t) * gainL;
    if (channels > 1) out[i * channels + 1] = Math.sin(2 * Math.PI * freqR * t) * gainR;
  }
  return out;
}

/** 便捷:一段正弦 PCM 帧(正弦 + 帧头一次到位)。 */
export function buildSineFrame(opts = {}) {
  const samples = buildSineBlock(opts);
  return buildPcmFrame({
    sampleRate: opts.sampleRate ?? 48000,
    channels: opts.channels ?? 2,
    samples,
  });
}

/**
 * 解码帧头(测试/校验用)。
 * @returns {{sampleRate:number, channels:number, numSamples:number, byteLength:number}}
 */
export function decodeHeader(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < HEADER_BYTES) {
    throw new RangeError("frame too short: need at least 12 bytes");
  }
  return {
    sampleRate: buf.readUInt32LE(0),
    channels: buf.readUInt32LE(4),
    numSamples: buf.readUInt32LE(8),
    byteLength: buf.length,
  };
}
