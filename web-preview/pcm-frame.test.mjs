// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// =============================================================================
// pcm-frame.mjs 的 golden 自测(node:test + node:assert,零依赖,不需要 npm install)
// =============================================================================
// 与 tests/pcm_frame_selftest.cpp 用**同一组 golden 字节**钉死 BRIDGE_CONTRACT.md §二 第 1 条
// 的 12 字节帧头布局(u32 LE sampleRate | u32 LE channels | u32 LE numSamples,紧跟 float32
// interleaved)。C++ 侧唯一实现 = src/PcmFrame.h;本文件守的是 JS 侧(web-preview mock)的
// 同布局实现,改布局时两处一起红。
//
// 断言口径与 C++ 侧一致:golden 字节写死为字面量而不是用 decodeHeader 反推 —— 编码与反解
// 一起写错(例如同时调换字段顺序)时 roundtrip 仍会绿,只有字面量能抓到。
//
// 运行:npm test(在 web-preview/ 下)或 node --test web-preview/pcm-frame.test.mjs(仓库根)。
// =============================================================================

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  HEADER_BYTES,
  buildPcmFrame,
  decodeHeader,
  frameByteLength,
} from "./pcm-frame.mjs";

/** 取 buf 的前 n 个字节为普通数组,便于 deepEqual 打印差异。 */
function bytes(buf, offset, n) {
  return Array.from(buf.subarray(offset, offset + n));
}

/** 构造 numSamples * channels 个样本(默认全 0),只为让帧头取到指定 numSamples。 */
function zeros(numSamples, channels) {
  return new Float32Array(numSamples * channels);
}

test("契约常量:帧头 12 字节,总长 = 12 + numSamples*channels*4", () => {
  assert.equal(HEADER_BYTES, 12);
  assert.equal(frameByteLength(2, 0), 12);
  assert.equal(frameByteLength(1, 1), 16);
  assert.equal(frameByteLength(2, 512), 12 + 512 * 2 * 4);
  assert.equal(frameByteLength(2, 512), 4108);
  assert.equal(frameByteLength(16, 16384), 1048588);
  assert.equal(frameByteLength(2, 480), 3852); // 48 kHz 下 10 ms 立体声块
});

test("golden:(48000, 2, 512) 的 12 字节帧头 = 80 BB 00 00 | 02 00 00 00 | 00 02 00 00", () => {
  const frame = buildPcmFrame({
    sampleRate: 48000,
    channels: 2,
    samples: zeros(512, 2),
  });
  // 48000 = 0x0000BB80 -> 80 BB 00 00;2 -> 02 00 00 00;512 = 0x200 -> 00 02 00 00。
  assert.deepEqual(
    bytes(frame, 0, HEADER_BYTES),
    [0x80, 0xbb, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00],
  );
  assert.equal(frame.length, 4108);
  const h = decodeHeader(frame);
  assert.equal(h.sampleRate, 48000);
  assert.equal(h.channels, 2);
  assert.equal(h.numSamples, 512);
});

test("golden:(44100, 2, 256) 的 12 字节帧头 = 44 AC 00 00 | 02 00 00 00 | 00 01 00 00", () => {
  const frame = buildPcmFrame({
    sampleRate: 44100,
    channels: 2,
    samples: zeros(256, 2),
  });
  assert.deepEqual(
    bytes(frame, 0, HEADER_BYTES),
    [0x44, 0xac, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00],
  );
});

test("字段顺序:三个字段取互异的值,逐偏移断言;调换任意两个字段即红", () => {
  // numSamples = 0x33 = 51,channels = 0x22 = 34 -> 51 * 34 个样本。
  const frame = buildPcmFrame({
    sampleRate: 0x11,
    channels: 0x22,
    samples: zeros(0x33, 0x22),
  });
  assert.deepEqual(
    bytes(frame, 0, HEADER_BYTES),
    [0x11, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00, 0x33, 0x00, 0x00, 0x00],
  );
  assert.equal(frame.readUInt32LE(0), 0x11);
  assert.equal(frame.readUInt32LE(4), 0x22);
  assert.equal(frame.readUInt32LE(8), 0x33);
});

test("端序:sampleRate 0x01020304 必须写成 04 03 02 01(小端)", () => {
  const frame = buildPcmFrame({
    sampleRate: 0x01020304,
    channels: 1,
    samples: zeros(1, 1),
  });
  assert.deepEqual(bytes(frame, 0, 4), [0x04, 0x03, 0x02, 0x01]);
  assert.equal(decodeHeader(frame).sampleRate, 0x01020304);
});

test("客户端校验边界(契约 §二 第 2 条)的上限值可精确编码:(96000, 16, 16384)", () => {
  const frame = buildPcmFrame({
    sampleRate: 96000,
    channels: 16,
    samples: zeros(16384, 16),
  });
  // 96000 = 0x017700 -> 00 77 01 00;16 -> 10 00 00 00;16384 = 0x4000 -> 00 40 00 00。
  assert.deepEqual(
    bytes(frame, 0, HEADER_BYTES),
    [0x00, 0x77, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00],
  );
  assert.equal(frame.length, 1048588);
});

test("整帧:头后紧跟 payload,1.0f 在偏移 12 = 00 00 80 3F,-1.0f 在偏移 16 = 00 00 80 BF", () => {
  const samples = Float32Array.from([1.0, -1.0, 0.5, 0.0]); // 2 帧 x 2 声道
  const frame = buildPcmFrame({ sampleRate: 48000, channels: 2, samples });
  assert.equal(frame.length, 12 + 4 * 4);
  assert.deepEqual(
    bytes(frame, 0, HEADER_BYTES),
    [0x80, 0xbb, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00],
  );
  // IEEE754 单精度 1.0f = 0x3F800000,小端 -> 00 00 80 3F
  assert.deepEqual(bytes(frame, HEADER_BYTES, 4), [0x00, 0x00, 0x80, 0x3f]);
  // -1.0f = 0xBF800000 -> 00 00 80 BF
  assert.deepEqual(bytes(frame, HEADER_BYTES + 4, 4), [0x00, 0x00, 0x80, 0xbf]);
  // 整段 payload 反读逐个相等
  const back = [];
  for (let i = 0; i < samples.length; i++) {
    back.push(frame.readFloatLE(HEADER_BYTES + i * 4));
  }
  assert.deepEqual(back, [1.0, -1.0, 0.5, 0.0]);
  assert.equal(decodeHeader(frame).byteLength, frame.length);
});

test("roundtrip:若干组常见参数经 decodeHeader 反解回原值", () => {
  const cases = [
    [44100, 2, 64],
    [48000, 2, 128],
    [88200, 2, 1024],
    [96000, 2, 2048],
    [192000, 2, 4096],
    [1, 1, 1],
  ];
  for (const [sampleRate, channels, numSamples] of cases) {
    const frame = buildPcmFrame({
      sampleRate,
      channels,
      samples: zeros(numSamples, channels),
    });
    const h = decodeHeader(frame);
    assert.deepEqual(
      [h.sampleRate, h.channels, h.numSamples],
      [sampleRate, channels, numSamples],
    );
    assert.equal(h.byteLength, frameByteLength(channels, numSamples));
  }
});

test("输入校验:非法 sampleRate / channels / 样本数不整除声道数一律 RangeError", () => {
  assert.throws(
    () => buildPcmFrame({ sampleRate: 0, channels: 2, samples: zeros(1, 2) }),
    RangeError,
  );
  assert.throws(
    () =>
      buildPcmFrame({ sampleRate: 48000, channels: 0, samples: zeros(0, 1) }),
    RangeError,
  );
  assert.throws(
    () =>
      buildPcmFrame({
        sampleRate: 48000,
        channels: 2,
        samples: new Float32Array(3),
      }),
    RangeError,
  );
  assert.throws(() => decodeHeader(Buffer.alloc(11)), RangeError);
});
