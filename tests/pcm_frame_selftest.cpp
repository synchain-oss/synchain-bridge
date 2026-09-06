// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// src/PcmFrame.h 的 golden 自测:把 BRIDGE_CONTRACT.md §二 第 1 条的 12 字节帧头布局
// (u32 LE sampleRate | u32 LE channels | u32 LE numSamples,紧跟 float32 interleaved)逐字节钉死。
// 只 include 那一个头 + 标准库,不链接 JUCE / ixwebsocket,故能脱离插件目标单独构建运行
// (cmake -DBRIDGE_BUILD_SELFTESTS=ON,随后由 scripts/gates.ps1 的 gate 5b 与 compliance workflow 执行)。
//
// 断言口径:golden 字节写死为字面量而不是用 readHeader 反推——反解函数与编码函数若一起写错
// (例如同时把字段顺序调换)roundtrip 仍会绿,只有字面量能抓到。改任一字段顺序 / 端序 / 偏移即红。
//
// 覆盖不到的一层:VstBridgeServer 的两条组帧路径(同步遗留路径 sendPcmPacket 与后台发送线程路径
// buildPcmFrame)是否真的调用了 writeHeader(而非又手写一份)—— 本文件链不了 JUCE,改由
// scripts/gates.ps1 的 gate 3f 与 compliance workflow 的同构 grep 步骤做文本断言(必须 #include
// "PcmFrame.h",不得再出现 writeU32( 手写 lambda 或字面量 headerSize = 12);payload 的实际 memcpy
// 仍在 VstBridgeServer.cpp。JS 侧 web-preview/pcm-frame.mjs 由 web-preview/pcm-frame.test.mjs 用同一组
// golden 字节钉死。

#include "PcmFrame.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

namespace
{
int gChecks = 0;
int gFailures = 0;

void check(bool ok, const char* what, int line)
{
    ++gChecks;
    if (!ok)
    {
        ++gFailures;
        std::printf("FAIL  line %d: %s\n", line, what);
    }
}

// 逐字节比对并在失败时打印 hex dump(got / want),便于一眼看出哪个偏移错了。
void checkBytes(const char* got, const unsigned char* want, std::size_t n, const char* what, int line)
{
    ++gChecks;
    bool same = true;
    for (std::size_t i = 0; i < n; ++i)
    {
        if (static_cast<unsigned char>(got[i]) != want[i])
        {
            same = false;
            break;
        }
    }
    if (same)
        return;
    ++gFailures;
    std::printf("FAIL  line %d: %s\n", line, what);
    std::printf("      got  [");
    for (std::size_t i = 0; i < n; ++i)
        std::printf(" %02X", static_cast<unsigned char>(got[i]));
    std::printf(" ]\n      want [");
    for (std::size_t i = 0; i < n; ++i)
        std::printf(" %02X", want[i]);
    std::printf(" ]\n");
}

// 头之外的字节先填哨兵,断言 writeHeader 只写 [0, 12)。
constexpr char kCanary = static_cast<char>(0xA5);
} // namespace

#define CHECK(expr) check((expr), #expr, __LINE__)
#define CHECK_BYTES(got, want, n) checkBytes((got), (want), (n), #got " == " #want, __LINE__)

int main()
{
    using namespace synchain::pcm;

    // ---- 契约常量:12 字节头,字段偏移 0 / 4 / 8,样本 4 字节 ------------------
    CHECK(kHeaderSize == 12u);
    CHECK(kSampleRateOffset == 0u);
    CHECK(kChannelsOffset == 4u);
    CHECK(kNumSamplesOffset == 8u);
    CHECK(kSampleBytes == 4u);

    // ---- golden:(48000, 2, 512) 的 12 字节 ---------------------------------
    // 48000 = 0x0000BB80 -> 80 BB 00 00;2 -> 02 00 00 00;512 = 0x200 -> 00 02 00 00。
    {
        char buf[kHeaderSize + 4];
        std::memset(buf, kCanary, sizeof(buf));
        writeHeader(buf, 48000u, 2u, 512u);
        static const unsigned char want[kHeaderSize] = {0x80, 0xBB, 0x00, 0x00, 0x02, 0x00,
                                                        0x00, 0x00, 0x00, 0x02, 0x00, 0x00};
        CHECK_BYTES(buf, want, kHeaderSize);
        // 只写头:第 12..15 字节仍是哨兵
        CHECK(buf[12] == kCanary && buf[13] == kCanary && buf[14] == kCanary && buf[15] == kCanary);
        // 反解回原值
        const Header h = readHeader(buf);
        CHECK(h.sampleRate == 48000u && h.channels == 2u && h.numSamples == 512u);
    }

    // ---- golden:契约里的第二常见采样率 44100 = 0xAC44 ------------------------
    {
        char buf[kHeaderSize];
        writeHeader(buf, 44100u, 2u, 256u);
        static const unsigned char want[kHeaderSize] = {0x44, 0xAC, 0x00, 0x00, 0x02, 0x00,
                                                        0x00, 0x00, 0x00, 0x01, 0x00, 0x00};
        CHECK_BYTES(buf, want, kHeaderSize);
    }

    // ---- 字段顺序:三个字段取互异的值,逐偏移断言;调换任意两个字段即红 ----------
    {
        char buf[kHeaderSize];
        writeHeader(buf, 0x11u, 0x22u, 0x33u);
        static const unsigned char want[kHeaderSize] = {0x11, 0x00, 0x00, 0x00, 0x22, 0x00,
                                                        0x00, 0x00, 0x33, 0x00, 0x00, 0x00};
        CHECK_BYTES(buf, want, kHeaderSize);
        CHECK(readU32LE(buf + kSampleRateOffset) == 0x11u);
        CHECK(readU32LE(buf + kChannelsOffset) == 0x22u);
        CHECK(readU32LE(buf + kNumSamplesOffset) == 0x33u);
    }

    // ---- 端序:0x01020304 必须写成 04 03 02 01(小端);写成大端即红 -----------
    {
        char buf[4];
        writeU32LE(buf, 0x01020304u);
        static const unsigned char want[4] = {0x04, 0x03, 0x02, 0x01};
        CHECK_BYTES(buf, want, 4);
        CHECK(readU32LE(buf) == 0x01020304u);
    }

    // ---- 边界:全 0 与全 0xFFFFFFFF -----------------------------------------
    {
        char buf[kHeaderSize];
        std::memset(buf, kCanary, sizeof(buf));
        writeHeader(buf, 0u, 0u, 0u);
        static const unsigned char zeros[kHeaderSize] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        CHECK_BYTES(buf, zeros, kHeaderSize);
        const Header h = readHeader(buf);
        CHECK(h.sampleRate == 0u && h.channels == 0u && h.numSamples == 0u);
    }
    {
        char buf[kHeaderSize];
        std::memset(buf, 0, sizeof(buf));
        writeHeader(buf, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu);
        static const unsigned char ones[kHeaderSize] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                                        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
        CHECK_BYTES(buf, ones, kHeaderSize);
        const Header h = readHeader(buf);
        CHECK(h.sampleRate == 0xFFFFFFFFu && h.channels == 0xFFFFFFFFu && h.numSamples == 0xFFFFFFFFu);
    }
    // 高位字节 / 最高位置位的值不被 char 符号扩展污染(readU32LE 经 unsigned char 取字节)。
    {
        char buf[4];
        writeU32LE(buf, 0x80000000u);
        static const unsigned char want[4] = {0x00, 0x00, 0x00, 0x80};
        CHECK_BYTES(buf, want, 4);
        CHECK(readU32LE(buf) == 0x80000000u);
        writeU32LE(buf, 0xDEADBEEFu);
        CHECK(readU32LE(buf) == 0xDEADBEEFu);
    }

    // ---- 客户端校验边界(契约 §二 第 2 条)的上限值可精确编码 -------------------
    // numSamples 16384 = 0x4000 -> 00 40 00 00;channels 16 -> 10 00 00 00。
    {
        char buf[kHeaderSize];
        writeHeader(buf, 96000u, 16u, 16384u);
        static const unsigned char want[kHeaderSize] = {0x00, 0x77, 0x01, 0x00, 0x10, 0x00,
                                                        0x00, 0x00, 0x00, 0x40, 0x00, 0x00};
        CHECK_BYTES(buf, want, kHeaderSize);
    }

    // ---- 总长 = 12 + numSamples * channels * 4 ---------------------------------
    CHECK(payloadSize(0, 2) == 0u);
    CHECK(frameSize(0, 2) == 12u);
    CHECK(frameSize(1, 1) == 16u);
    CHECK(frameSize(512, 2) == 12u + 512u * 2u * 4u);
    CHECK(frameSize(512, 2) == 4108u);
    CHECK(frameSize(16384, 16) == 12u + 16384u * 16u * 4u);
    CHECK(frameSize(16384, 16) == 1048588u);
    CHECK(frameSize(480, 2) == 3852u); // 48 kHz 下 10 ms 立体声块
    // 编译期可用(constexpr)
    static_assert(frameSize(512, 2) == 4108u, "frameSize 必须是 constexpr");
    static_assert(kHeaderSize == 12u, "kHeaderSize 必须为 12");

    // ---- 组一整帧:头后紧跟 payload,偏移 12 起,与 VstBridgeServer 两条组帧路径同法 ----
    {
        const std::size_t numSamples = 2, channels = 2;
        const float pcm[numSamples * channels] = {1.0f, -1.0f, 0.5f, 0.0f};
        std::string frame(frameSize(numSamples, channels), '\0');
        CHECK(frame.size() == 12u + 4u * 4u);
        writeHeader(frame.data(), 48000u, static_cast<std::uint32_t>(channels), static_cast<std::uint32_t>(numSamples));
        std::memcpy(frame.data() + kHeaderSize, pcm, payloadSize(numSamples, channels));

        // 头仍正确
        static const unsigned char wantHead[kHeaderSize] = {0x80, 0xBB, 0x00, 0x00, 0x02, 0x00,
                                                            0x00, 0x00, 0x02, 0x00, 0x00, 0x00};
        CHECK_BYTES(frame.data(), wantHead, kHeaderSize);
        // 第一个样本 1.0f(IEEE754 单精度 0x3F800000)落在偏移 12,小端 -> 00 00 80 3F
        static const unsigned char wantFirst[4] = {0x00, 0x00, 0x80, 0x3F};
        CHECK_BYTES(frame.data() + kHeaderSize, wantFirst, 4);
        // 第二个样本 -1.0f(0xBF800000)在偏移 16
        static const unsigned char wantSecond[4] = {0x00, 0x00, 0x80, 0xBF};
        CHECK_BYTES(frame.data() + kHeaderSize + 4, wantSecond, 4);
        // 整段 payload 反拷回来逐个相等
        float back[numSamples * channels] = {};
        std::memcpy(back, frame.data() + kHeaderSize, sizeof(back));
        CHECK(back[0] == 1.0f && back[1] == -1.0f && back[2] == 0.5f && back[3] == 0.0f);
        // 末字节 = 偏移 frameSize-1,再往后没有字节
        CHECK(frame.size() == kHeaderSize + payloadSize(numSamples, channels));
    }

    // ---- roundtrip:若干组常见 / 极端参数 -------------------------------------
    {
        const std::uint32_t cases[][3] = {{44100u, 2u, 64u},     {48000u, 2u, 128u},          {88200u, 2u, 1024u},
                                          {96000u, 2u, 2048u},   {192000u, 2u, 4096u},        {1u, 1u, 1u},
                                          {0x7FFFFFFFu, 3u, 7u}, {12345u, 0xFFu, 0x12345678u}};
        for (const auto& c : cases)
        {
            char buf[kHeaderSize];
            writeHeader(buf, c[0], c[1], c[2]);
            const Header h = readHeader(buf);
            CHECK(h.sampleRate == c[0]);
            CHECK(h.channels == c[1]);
            CHECK(h.numSamples == c[2]);
        }
    }

    std::printf("pcm_frame_selftest: %d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
