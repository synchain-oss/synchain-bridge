// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// 桥 #2 二进制 PCM 帧的**帧头编码**——BRIDGE_CONTRACT.md §二 第 1 条的 C++ 侧唯一实现：
//   12 字节头 = u32 sampleRate | u32 channels | u32 numSamples(全部小端),
//   紧跟 numSamples*channels 个 float32 interleaved;总字节 = 12 + numSamples*channels*4。
// 字段顺序 / 端序 / 偏移不可变(契约冻结)。
// JS 侧(web-preview mock)另有一份同布局实现 web-preview/pcm-frame.mjs,两者用**同一组 golden 字节**
// 分别钉死(tests/pcm_frame_selftest.cpp ↔ web-preview/pcm-frame.test.mjs),改布局时两处一起红。
//
// 只依赖标准库(无 JUCE / ixwebsocket / 任何第三方),故能被 tests/pcm_frame_selftest.cpp
// 单独编译成一个不链接任何依赖的自测可执行文件,用 golden 字节逐字节钉死 wire 布局
// (见 CMakeLists.txt 的 BRIDGE_BUILD_SELFTESTS 选项、scripts/gates.ps1 的 gate 5b 与 ci.yml 的
// Run selftests 步骤)。
// src/VstBridgeServer.cpp 的同步遗留路径 sendPcmPacket(无调用方,仅为 API 兼容保留)与后台发送
// 线程路径 buildPcmFrame(实时路径,processBlock → pushPcm → ring → 这里)都必须经本头组帧,
// 不得再各自手写偏移 —— scripts/gates.ps1 的 gate 3f 与 compliance workflow 以文本断言守住这一点。
//
// 样本区(payload)按宿主本机 float 字节序 memcpy,与既有行为一致;插件仅面向 x64 / arm64
// 这两个小端平台,故 payload 与帧头同为小端。本头不负责拷 payload,只算偏移与长度。

#include <cstddef>
#include <cstdint>

namespace synchain::pcm
{

static_assert(sizeof(float) == 4, "PCM payload 是 float32,sizeof(float) 必须为 4");

// 帧头字节数(3 x u32 LE)。
constexpr std::size_t kHeaderSize = 12;

// 三个 u32 字段在帧头内的字节偏移——契约冻结,改动即为 major 级协议变更。
constexpr std::size_t kSampleRateOffset = 0;
constexpr std::size_t kChannelsOffset = 4;
constexpr std::size_t kNumSamplesOffset = 8;

// 一个样本(单声道单帧)的字节数。
constexpr std::size_t kSampleBytes = sizeof(float);

// 已解码的帧头(供测试反解与将来的接收侧复用)。
struct Header
{
    std::uint32_t sampleRate = 0;
    std::uint32_t channels = 0;
    std::uint32_t numSamples = 0;
};

// 小端写入一个 u32;dst 须至少可写 4 字节。
inline void writeU32LE(char* dst, std::uint32_t value) noexcept
{
    dst[0] = static_cast<char>(value & 0xFFu);
    dst[1] = static_cast<char>((value >> 8) & 0xFFu);
    dst[2] = static_cast<char>((value >> 16) & 0xFFu);
    dst[3] = static_cast<char>((value >> 24) & 0xFFu);
}

// 小端读出一个 u32;src 须至少可读 4 字节。经 unsigned char 拿字节,避免 char 有符号时的符号扩展。
inline std::uint32_t readU32LE(const char* src) noexcept
{
    const auto b = [src](std::size_t i) { return static_cast<std::uint32_t>(static_cast<unsigned char>(src[i])); };
    return b(0) | (b(1) << 8) | (b(2) << 16) | (b(3) << 24);
}

// 把 12 字节帧头写进 dst(须至少可写 kHeaderSize 字节)。只写头,不碰 dst[kHeaderSize] 及之后。
inline void writeHeader(char* dst, std::uint32_t sampleRate, std::uint32_t channels, std::uint32_t numSamples) noexcept
{
    writeU32LE(dst + kSampleRateOffset, sampleRate);
    writeU32LE(dst + kChannelsOffset, channels);
    writeU32LE(dst + kNumSamplesOffset, numSamples);
}

// 从 src(须至少可读 kHeaderSize 字节)反解帧头。writeHeader 的精确逆运算。
inline Header readHeader(const char* src) noexcept
{
    return Header{readU32LE(src + kSampleRateOffset), readU32LE(src + kChannelsOffset),
                  readU32LE(src + kNumSamplesOffset)};
}

// payload 字节数 = numSamples * channels * 4。参数用 size_t 由调用方转换,与既有两条路径的算法逐字相同。
constexpr std::size_t payloadSize(std::size_t numSamples, std::size_t channels) noexcept
{
    return numSamples * channels * kSampleBytes;
}

// 整帧字节数 = 12 + payload。
constexpr std::size_t frameSize(std::size_t numSamples, std::size_t channels) noexcept
{
    return kHeaderSize + payloadSize(numSamples, channels);
}

} // namespace synchain::pcm
