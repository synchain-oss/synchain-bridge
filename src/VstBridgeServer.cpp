// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "VstBridgeServer.h"
#include "WebSocketProtocol.h"
#include <cctype> // std::tolower
#include <cstring> // std::memcpy

namespace synchain
{

namespace
{
// CSWSH 防护：只放行 Synchain 自己确切的来源，阻止用户浏览器里的任意第三方站点
// 静默连上本地端口偷 DAW 母线实时 PCM。白名单（Synchain issue 167）：
//   - localhost / 127.0.0.1 / [::1]（本地开发/预览，任意 scheme/端口）
//   - https://synchain.cn|.ca 、https://www.synchain.cn|.ca 、https://dev.synchain.cn|.ca（精确 host）
//   - https://synchain-git-<branch>-[REDACTED-TEAM].vercel.app（Vercel 预览，
//     团队 slug 固定，攻击者无法在该 slug 下部署 → 前后缀夹逼安全）
// 明确【拒绝】：apex vercel.app 与任意其它 *.vercel.app、非 https 远程、以及一切其它。
// 原生/桌面客户端不带 Origin 头（空串）→ 放行；但【不放行字面量 "null"】——沙箱
// iframe / opaque-origin 文档握手会带 Origin: null，放行它会重开 CSWSH（攻击页可用
// sandbox=allow-scripts 的 iframe 驱动 ws 连本地端口）。
bool isAllowedOrigin(const std::string& origin)
{
    if (origin.empty())
        return true; // 原生/桌面客户端（无 Origin 头）；浏览器无法伪造空 Origin

    // 浏览器 Origin 一定是 scheme://host[:port]；缺 "://" 即畸形 → 拒。
    const auto sep = origin.find("://");
    if (sep == std::string::npos)
        return false;
    std::string scheme = origin.substr(0, sep);
    std::string s = origin.substr(sep + 3);
    if (const auto slash = s.find('/'); slash != std::string::npos)
        s = s.substr(0, slash);

    std::string host;
    if (!s.empty() && s.front() == '[')
    { // IPv6 字面量 [::1](:port)
        const auto rb = s.find(']');
        host = (rb == std::string::npos) ? s : s.substr(0, rb + 1);
    }
    else
    {
        const auto colon = s.find(':');
        host = (colon == std::string::npos) ? s : s.substr(0, colon);
    }

    const auto toLower = [](std::string v) {
        for (auto& c : v)
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return v;
    };
    scheme = toLower(scheme); // scheme/host 大小写不敏感，归一化防 SYNCHAIN.CN 之类绕过
    host = toLower(host);

    // 本地开发/预览：任意 scheme/端口。
    if (host == "localhost" || host == "127.0.0.1" || host == "[::1]")
        return true;

    // 其余远程来源一律要求 https。
    if (scheme != "https")
        return false;

    // 精确自定义域（prod + www + dev）。
    if (host == "synchain.cn" || host == "synchain.ca" || host == "www.synchain.cn" || host == "www.synchain.ca" ||
        host == "dev.synchain.cn" || host == "dev.synchain.ca")
        return true;

    // Vercel 预览：synchain-git-<branch>-[REDACTED-TEAM].vercel.app。
    // 要求 branch 段非空（host 长于前缀+后缀），排除前后缀重叠的边界串。
    const std::string pre = "synchain-git-";
    const std::string suf = "-[REDACTED-TEAM].vercel.app";
    const auto startsWith = [](const std::string& v, const std::string& p) {
        return v.size() >= p.size() && v.compare(0, p.size(), p) == 0;
    };
    const auto endsWith = [](const std::string& v, const std::string& t) {
        return v.size() >= t.size() && v.compare(v.size() - t.size(), t.size(), t) == 0;
    };
    if (host.size() > pre.size() + suf.size() && startsWith(host, pre) && endsWith(host, suf))
        return true;

    return false; // 含 apex vercel.app 与任意其它 *.vercel.app
}
} // namespace

VstBridgeServer::VstBridgeServer() = default;

VstBridgeServer::~VstBridgeServer()
{
    stop();
}

int VstBridgeServer::start(int port)
{
    if (mRunning)
        return mPort;

    for (int offset = 0; offset < 10; ++offset)
    {
        int tryPort = port + offset;
        mServer = std::make_unique<ix::WebSocketServer>(tryPort, "127.0.0.1");

        mServer->setOnClientMessageCallback(
            [this](std::shared_ptr<ix::ConnectionState> connectionState, ix::WebSocket& client,
                   const ix::WebSocketMessagePtr& msg) { onClientMessage(connectionState, client, msg); });

        auto res = mServer->listen();
        if (res.first)
        {
            mServer->start();
            mRunning = true;
            mPort = tryPort;
            // 后台线程生命周期绑 start()/stop()（Synchain issue 168/Synchain issue 170）：mServer 就绪后再起线程；
            // stop() 里先 join 再 reset(mServer) —— 反复 start/stop 都干净重建，杜绝对
            // mServer 的 use-after-free / data race。slot 池预分配另在 prepareStreaming。
            startSenderThread();
            startHeartbeatThread();
            return tryPort;
        }
        mServer.reset();
    }

    mPort = -1;
    return -1;
}

void VstBridgeServer::stop()
{
    if (!mRunning)
        return;

    mRunning = false;

    // 关键顺序（Synchain issue 168/Synchain issue 170）：后台发送/心跳线程会解引用 mServer（getClients/sendBinary/
    // send/close），必须在 mServer.reset() 之前先停并 join 它们，否则并发访问已析构的
    // mServer → UAF/data race（编辑器 Stop Bridge 走 message 线程，与后台线程并发）。
    stopSenderThread();
    stopHeartbeatThread();

    if (mServer)
    {
        mServer->stop();
        mServer.reset();
    }

    mAudioClientCount.store(0, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(mClientsMutex);
        mLastPongMs.clear();
    }
}

int VstBridgeServer::getClientCount() const
{
    if (!mServer)
        return 0;
    std::lock_guard<std::mutex> lock(mClientsMutex);
    return static_cast<int>(mServer->getClients().size());
}

void VstBridgeServer::onClientMessage(std::shared_ptr<ix::ConnectionState> /*connectionState*/, ix::WebSocket& client,
                                      const ix::WebSocketMessagePtr& msg)
{

    using namespace Protocol;

    if (msg->type == ix::WebSocketMessageType::Open)
    {
        // CSWSH 防护：在发送任何音频前校验握手 Origin，非白名单直接关闭。
        const auto& headers = msg->openInfo.headers;
        const auto it = headers.find("Origin");
        const std::string origin = (it != headers.end()) ? it->second : std::string();
        if (!isAllowedOrigin(origin))
        {
            client.close(4403, "origin not allowed");
            return;
        }
        // 通过 origin 校验：登记心跳时间戳 + 递增音频发送门控计数（Synchain issue 168/Synchain issue 170）。
        // 计数漂移由心跳线程用 getClients().size() 周期校正兜底。
        {
            std::lock_guard<std::mutex> lock(mClientsMutex);
            mLastPongMs[&client] = juce::Time::getMillisecondCounterHiRes();
        }
        mAudioClientCount.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    if (msg->type == ix::WebSocketMessageType::Close)
    {
        {
            std::lock_guard<std::mutex> lock(mClientsMutex);
            mLastPongMs.erase(&client);
        }
        if (mAudioClientCount.fetch_sub(1, std::memory_order_relaxed) - 1 < 0)
            mAudioClientCount.store(0, std::memory_order_relaxed);
        return;
    }

    if (msg->type == ix::WebSocketMessageType::Message)
    {
        auto json = parseMessage(msg->str);
        auto type = parseType(json["type"].toString());

        switch (type)
        {
        case MessageType::Handshake: {
            auto h = Handshake::fromJson(json);
            if (callbacks.onHandshake)
            {
                callbacks.onHandshake(h.projectId, h.userId, h.username);
            }
            break;
        }
        case MessageType::SetSettings: {
            auto s = SettingsMessage::fromJson(json);
            if (callbacks.onBitrateChange)
            {
                callbacks.onBitrateChange(s.opusBitrate);
            }
            break;
        }
        case MessageType::GetSettings: {
            if (callbacks.onSettingsRequest)
            {
                callbacks.onSettingsRequest();
            }
            break;
        }
        case MessageType::SetVolume: {
            // browser -> plugin：设主控音量（0..200 pct）。回调在 WS 线程，PluginProcessor 内转 message 线程改参数。
            if (callbacks.onVolumeChange)
            {
                callbacks.onVolumeChange(static_cast<int>(json["volume"]));
            }
            break;
        }
        case MessageType::Pong: {
            // Synchain issue 170：更新该连接的最后 pong 时刻，供心跳线程判定存活。
            std::lock_guard<std::mutex> lock(mClientsMutex);
            auto pit = mLastPongMs.find(&client);
            if (pit != mLastPongMs.end())
                pit->second = juce::Time::getMillisecondCounterHiRes();
            break;
        }
        default:
            break;
        }
    }
}

// -- Broadcast helpers --

void VstBridgeServer::broadcast(const juce::String& message)
{
    if (!mServer)
        return;

    std::vector<std::shared_ptr<ix::WebSocket>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mClientsMutex);
        for (const auto& client : mServer->getClients())
        {
            snapshot.push_back(client);
        }
    }

    for (auto& client : snapshot)
    {
        client->send(message.toStdString());
    }
}

void VstBridgeServer::sendStatus(bool connected, const juce::String& pluginName, const juce::String& version,
                                 int volumePct)
{
    Protocol::StatusMessage msg{connected, pluginName, version, volumePct};
    broadcast(Protocol::serialize(msg.toJson()));
}

void VstBridgeServer::sendVolume(int volumePct)
{
    // plugin -> browser：{type:"volume", volume}，网页据此实时更新 DAW 音量条（v1.2.9 双向实时同步）。
    auto* obj = new juce::DynamicObject();
    obj->setProperty("type", "volume");
    obj->setProperty("volume", volumePct);
    broadcast(Protocol::serialize(juce::var(obj)));
}

void VstBridgeServer::sendPcmPacket(const float* interleaved, int numSamples, int sampleRate, int channels)
{
    if (!mServer)
        return;

    // Pack header: 3 x u32 LE (sampleRate, channels, numSamples)
    const size_t headerSize = 12;
    const size_t dataSize = static_cast<size_t>(numSamples) * static_cast<size_t>(channels) * sizeof(float);
    std::string frame(headerSize + dataSize, '\0');

    auto writeU32 = [&](int offset, uint32_t val) {
        frame[offset] = static_cast<char>(val & 0xFF);
        frame[offset + 1] = static_cast<char>((val >> 8) & 0xFF);
        frame[offset + 2] = static_cast<char>((val >> 16) & 0xFF);
        frame[offset + 3] = static_cast<char>((val >> 24) & 0xFF);
    };

    writeU32(0, static_cast<uint32_t>(sampleRate));
    writeU32(4, static_cast<uint32_t>(channels));
    writeU32(8, static_cast<uint32_t>(numSamples));

    std::memcpy(&frame[headerSize], interleaved, dataSize);

    // Snapshot clients under lock
    std::vector<std::shared_ptr<ix::WebSocket>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mClientsMutex);
        for (const auto& client : mServer->getClients())
        {
            snapshot.push_back(client);
        }
    }

    for (auto& client : snapshot)
    {
        client->sendBinary(frame);
    }
}

void VstBridgeServer::sendMeterLevels(float left, float right, float peak)
{
    Protocol::MeterMessage msg{left, right, peak};
    broadcast(Protocol::serialize(msg.toJson()));
}

void VstBridgeServer::sendSettings(int sampleRate, int bufferSize, int channels, int opusBitrate, double latencyMs)
{
    Protocol::SettingsMessage msg{sampleRate, bufferSize, channels, opusBitrate, latencyMs};
    broadcast(Protocol::serialize(msg.toJson()));
}

void VstBridgeServer::sendError(const juce::String& code, const juce::String& message)
{
    Protocol::ErrorMessage msg{code, message};
    broadcast(Protocol::serialize(msg.toJson()));
}

// =============================================================================
// Synchain issue 168 实时安全 PCM/电平交接
// =============================================================================

void VstBridgeServer::prepareStreaming(int maxBlockSize, int numSlots)
{
    // 在 prepareToPlay（JUCE 保证与 processBlock 串行）里(重)分配定长 slot 池。
    // 受 mStreamMutex 保护以与运行中的后台发送线程互斥（音频线程不碰该锁）。
    const int inter = juce::jmax(1, maxBlockSize) * 2; // 交织 L/R 上界
    const int slots = juce::jmax(2, numSlots);
    std::lock_guard<std::mutex> lock(mStreamMutex);
    mSlots.assign(static_cast<size_t>(slots), PcmSlot{});
    for (auto& s : mSlots)
        s.data.assign(static_cast<size_t>(inter), 0.0f);
    mPcmFifo.setTotalSize(slots);
    mPcmFifo.reset();
    mDropped.store(0, std::memory_order_relaxed);
}

void VstBridgeServer::releaseStreaming()
{
    std::lock_guard<std::mutex> lock(mStreamMutex);
    mSlots.clear();
    mSlots.shrink_to_fit();
    mPcmFifo.setTotalSize(1);
    mPcmFifo.reset();
}

void VstBridgeServer::pushPcm(const float* interleaved, int numSamples, int sampleRate, int channels) noexcept
{
    // 音频线程：noexcept、无锁、无分配、非阻塞。
    if (!mSenderRunning.load(std::memory_order_relaxed))
        return; // 无消费者
    if (mAudioClientCount.load(std::memory_order_relaxed) <= 0)
        return; // 无客户端
    if (interleaved == nullptr || channels <= 0 || numSamples <= 0)
        return;

    if (mPcmFifo.getFreeSpace() < 1)
    { // ring 满：丢最新（SPSC 最简、无竞态、不阻塞）
        mDropped.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    int s1, bs1, s2, bs2;
    mPcmFifo.prepareToWrite(1, s1, bs1, s2, bs2);
    const int idx = (bs1 > 0) ? s1 : s2;
    if (idx < 0 || idx >= static_cast<int>(mSlots.size()))
    { // 防御：slot 未就绪
        mPcmFifo.finishedWrite(0);
        return;
    }
    auto& slot = mSlots[static_cast<size_t>(idx)];
    const int cap = static_cast<int>(slot.data.size());
    const int maxSamples = cap / channels; // 保 header 与数据一致
    const int outSamples = juce::jmin(numSamples, maxSamples);
    if (outSamples > 0)
        std::memcpy(slot.data.data(), interleaved,
                    static_cast<size_t>(outSamples) * static_cast<size_t>(channels) * sizeof(float));
    slot.sampleRate = sampleRate;
    slot.channels = channels;
    slot.numSamples = outSamples;
    mPcmFifo.finishedWrite(1);
}

void VstBridgeServer::pushMeter(float left, float right, float peak) noexcept
{
    if (!mSenderRunning.load(std::memory_order_relaxed))
        return;
    if (mAudioClientCount.load(std::memory_order_relaxed) <= 0)
        return;
    mMeterL.store(left, std::memory_order_relaxed);
    mMeterR.store(right, std::memory_order_relaxed);
    mMeterPeak.store(peak, std::memory_order_relaxed);
    mMeterDirty.store(true, std::memory_order_release);
}

void VstBridgeServer::startSenderThread()
{
    mSenderRunning.store(true, std::memory_order_release);
    mSender = std::thread([this] { senderThreadRun(); });
}

void VstBridgeServer::stopSenderThread()
{
    mSenderRunning.store(false, std::memory_order_release);
    mSenderWake.signal(); // 唤醒轮询等待，快速退出
    if (mSender.joinable())
        mSender.join();
}

void VstBridgeServer::buildPcmFrame(const PcmSlot& slot)
{
    // 调用方须持有 mStreamMutex（读取 slot.data）。组帧到复用的 mSendFrame。
    const size_t headerSize = 12;
    const size_t dataSize = static_cast<size_t>(slot.numSamples) * static_cast<size_t>(slot.channels) * sizeof(float);
    mSendFrame.resize(headerSize + dataSize);

    auto writeU32 = [this](size_t off, uint32_t val) {
        mSendFrame[off] = static_cast<char>(val & 0xFF);
        mSendFrame[off + 1] = static_cast<char>((val >> 8) & 0xFF);
        mSendFrame[off + 2] = static_cast<char>((val >> 16) & 0xFF);
        mSendFrame[off + 3] = static_cast<char>((val >> 24) & 0xFF);
    };
    writeU32(0, static_cast<uint32_t>(slot.sampleRate));
    writeU32(4, static_cast<uint32_t>(slot.channels));
    writeU32(8, static_cast<uint32_t>(slot.numSamples));
    if (dataSize > 0)
        std::memcpy(&mSendFrame[headerSize], slot.data.data(), dataSize);
}

void VstBridgeServer::sendFrameToClients()
{
    if (!mServer)
        return;
    std::vector<std::shared_ptr<ix::WebSocket>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mClientsMutex);
        for (const auto& client : mServer->getClients())
            snapshot.push_back(client);
    }
    for (auto& client : snapshot)
        client->sendBinary(mSendFrame);
}

void VstBridgeServer::broadcastMeter(float left, float right, float peak)
{
    Protocol::MeterMessage msg{left, right, peak};
    broadcast(Protocol::serialize(msg.toJson()));
}

void VstBridgeServer::senderThreadRun()
{
    while (mSenderRunning.load(std::memory_order_acquire))
    {
        mSenderWake.wait(kSenderPollMs); // 纯轮询：音频线程不 signal（规避 RT 不安全原语）
        if (!mSenderRunning.load(std::memory_order_acquire))
            break;

        // 抽干 PCM ring：在 mStreamMutex 下把 slot 拷进 mSendFrame，锁外做 WS 发送。
        for (;;)
        {
            bool haveFrame = false;
            {
                std::lock_guard<std::mutex> lock(mStreamMutex);
                if (mPcmFifo.getNumReady() < 1)
                    break;
                int s1, bs1, s2, bs2;
                mPcmFifo.prepareToRead(1, s1, bs1, s2, bs2);
                const int idx = (bs1 > 0) ? s1 : s2;
                if (idx >= 0 && idx < static_cast<int>(mSlots.size()))
                {
                    buildPcmFrame(mSlots[static_cast<size_t>(idx)]);
                    haveFrame = true;
                }
                mPcmFifo.finishedRead(1);
            }
            if (haveFrame)
                sendFrameToClients();
        }

        if (mMeterDirty.exchange(false, std::memory_order_acquire))
        {
            broadcastMeter(mMeterL.load(std::memory_order_relaxed), mMeterR.load(std::memory_order_relaxed),
                           mMeterPeak.load(std::memory_order_relaxed));
        }
    }
}

// =============================================================================
// Synchain issue 170 服务端应用层心跳（独立线程）
// =============================================================================

void VstBridgeServer::startHeartbeatThread()
{
    mHeartbeatRunning.store(true, std::memory_order_release);
    mHeartbeat = std::thread([this] { heartbeatThreadRun(); });
}

void VstBridgeServer::stopHeartbeatThread()
{
    mHeartbeatRunning.store(false, std::memory_order_release);
    mHeartbeatWake.signal();
    if (mHeartbeat.joinable())
        mHeartbeat.join();
}

void VstBridgeServer::heartbeatThreadRun()
{
    while (mHeartbeatRunning.load(std::memory_order_acquire))
    {
        mHeartbeatWake.wait(kHeartbeatIntervalMs);
        if (!mHeartbeatRunning.load(std::memory_order_acquire))
            break;
        if (!mServer)
            continue;

        const double now = juce::Time::getMillisecondCounterHiRes();

        std::vector<std::shared_ptr<ix::WebSocket>> toPing;
        std::vector<std::shared_ptr<ix::WebSocket>> toClose;
        int liveCount = 0;
        {
            std::lock_guard<std::mutex> lock(mClientsMutex);
            auto clients = mServer->getClients(); // 持 shared_ptr 快照，保活到锁外发送
            liveCount = static_cast<int>(clients.size());

            // 剪除已不在客户端列表里的陈旧条目（防漏 Close 泄漏）。
            for (auto it = mLastPongMs.begin(); it != mLastPongMs.end();)
            {
                bool present = false;
                for (const auto& c : clients)
                    if (c.get() == it->first)
                    {
                        present = true;
                        break;
                    }
                if (!present)
                    it = mLastPongMs.erase(it);
                else
                    ++it;
            }

            for (const auto& c : clients)
            {
                ix::WebSocket* key = c.get();
                auto it = mLastPongMs.find(key);
                if (it == mLastPongMs.end())
                {
                    // 刚 Open、本轮尚未登记：视为「刚见过」，本轮跳过，绝不误关新连接。
                    mLastPongMs[key] = now;
                    continue;
                }
                if (now - it->second > kHeartbeatTimeoutMs)
                    toClose.push_back(c);
                else
                    toPing.push_back(c);
            }
        }

        // 用真实连接数校正音频发送门控（Synchain issue 168 计数漂移兜底）。
        mAudioClientCount.store(liveCount, std::memory_order_relaxed);

        // 组一次 ping 帧，锁外发送 / 关连接（用 shared_ptr 副本，对象保活）。
        juce::String pingMsg;
        {
            auto* obj = new juce::DynamicObject();
            obj->setProperty("type", "ping");
            obj->setProperty("timestamp", static_cast<juce::int64>(now));
            pingMsg = Protocol::serialize(juce::var(obj));
        }
        const std::string pingStd = pingMsg.toStdString();
        for (auto& c : toPing)
            c->send(pingStd);
        for (auto& c : toClose)
            c->close(4408, "heartbeat timeout");
    }
}

} // namespace synchain
