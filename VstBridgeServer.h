// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <juce_core/juce_core.h>
#include <ixwebsocket/IXWebSocketServer.h>
#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace synchain {

// Callbacks for incoming browser messages
struct VstBridgeCallbacks {
  std::function<void(const juce::String& projectId,
                     const juce::String& userId,
                     const juce::String& username)> onHandshake;
  std::function<void(int opusBitrate)> onBitrateChange;
  std::function<void()> onSettingsRequest;
  // browser -> plugin：设置主控音量（0..200 pct）。回调在 WS 线程触发，PluginProcessor 内需转到
  // message 线程再改 APVTS 参数（见其接线）。
  std::function<void(int volumePct)> onVolumeChange;
};

class VstBridgeServer {
public:
  VstBridgeServer();
  ~VstBridgeServer();

  VstBridgeServer(const VstBridgeServer&) = delete;
  VstBridgeServer& operator=(const VstBridgeServer&) = delete;

  // Returns actual port bound, or -1 if all ports failed.
  // Tries `port` through `port + 9`.
  int start(int port = 9420);
  void stop();

  // Send messages to all connected clients
  void sendStatus(bool connected, const juce::String& pluginName,
                  const juce::String& version, int volumePct = 100);

  // plugin -> browser：主控音量变化时广播 {type:"volume", volume}，网页据此实时更新音量条（v1.2.9）。
  void sendVolume(int volumePct);

  // Send raw PCM to all connected clients as binary WebSocket frame.
  // Frame format: u32 sampleRate | u32 channels | u32 numSamples | float32 interleaved
  void sendPcmPacket(const float* interleaved, int numSamples,
                     int sampleRate, int channels);

  // -------------------------------------------------------------------------
  // #168 实时安全 PCM/电平交接：音频线程(processBlock)只做「无锁、零分配」的握把，
  // 把 PCM/电平交给后台发送线程。AbstractFifo(SPSC) + 预分配定长 slot 池。
  //
  //   prepareStreaming / releaseStreaming —— 在 prepareToPlay / releaseResources 调用
  //   （JUCE 保证与 processBlock 串行），(重)分配 / 释放 slot 池，受 mStreamMutex 保护
  //   以与后台发送线程互斥（音频线程不碰该锁）。
  //   pushPcm / pushMeter —— 音频线程调用，noexcept、无锁、无分配、非阻塞。
  //   后台发送线程生命周期绑 start()/stop()（见 .cpp），stop() 先 join 再 reset(mServer)。
  // -------------------------------------------------------------------------
  void prepareStreaming(int maxBlockSize, int numSlots = 32);
  void releaseStreaming();
  void pushPcm(const float* interleaved, int numSamples,
               int sampleRate, int channels) noexcept;
  void pushMeter(float left, float right, float peak) noexcept;
  uint64_t droppedPacketCount() const noexcept {
    return mDropped.load(std::memory_order_relaxed);
  }

  void sendMeterLevels(float left, float right, float peak);
  void sendSettings(int sampleRate, int bufferSize, int channels,
                    int opusBitrate, double latencyMs = 0.0);
  void sendError(const juce::String& code, const juce::String& message);

  bool isRunning() const { return mRunning; }
  int getClientCount() const;
  int getPort() const { return mPort; }

  VstBridgeCallbacks callbacks;

private:
  void onClientMessage(std::shared_ptr<ix::ConnectionState> connectionState,
                       ix::WebSocket& client,
                       const ix::WebSocketMessagePtr& msg);
  void broadcast(const juce::String& message);

  std::unique_ptr<ix::WebSocketServer> mServer;
  std::atomic<bool> mRunning{false};
  std::atomic<int> mPort{-1};
  mutable std::mutex mClientsMutex;

  // --- #168：无锁 SPSC PCM ring + 后台发送线程 -----------------------------
  struct PcmSlot {
    int sampleRate = 0;
    int channels   = 2;
    int numSamples = 0;
    std::vector<float> data; // 容量 = 2*maxBlockSamples floats（交织 L/R）
  };
  std::vector<PcmSlot> mSlots;
  juce::AbstractFifo mPcmFifo{1};
  // 保护 mSlots / mPcmFifo 的(重)分配与 reset 相对后台发送线程互斥。
  // 音频线程(pushPcm)【不】上锁——它与 prepareStreaming/releaseStreaming 由 JUCE 串行化，
  // 与后台发送线程之间由 AbstractFifo(SPSC) 的原子索引保证安全。
  std::mutex mStreamMutex;
  std::atomic<uint64_t> mDropped{0};
  // 音频线程发送门控：>0 才 push。Open/Close 增减，后台心跳线程用 getClients() 周期校正漂移。
  std::atomic<int> mAudioClientCount{0};
  std::atomic<float> mMeterL{-60.0f}, mMeterR{-60.0f}, mMeterPeak{-60.0f};
  std::atomic<bool> mMeterDirty{false};
  std::thread mSender;
  std::atomic<bool> mSenderRunning{false};
  juce::WaitableEvent mSenderWake;
  std::string mSendFrame; // 后台线程复用的组帧缓冲（只增长）
  void senderThreadRun();
  void buildPcmFrame(const PcmSlot& slot); // 在 mStreamMutex 下把 slot 打包进 mSendFrame
  void sendFrameToClients();               // 锁外做 WS 二进制发送
  void broadcastMeter(float left, float right, float peak);
  void startSenderThread();
  void stopSenderThread();

  // --- #170：服务端应用层心跳（独立线程，绝不进音频线程）-------------------
  std::thread mHeartbeat;
  std::atomic<bool> mHeartbeatRunning{false};
  juce::WaitableEvent mHeartbeatWake;
  // per-client 最后一次 pong 时刻（ms, hi-res）。键 = &client（== getClients() 的 shared_ptr.get()）。
  // 受 mClientsMutex 保护（与 client 快照同锁）。
  std::unordered_map<ix::WebSocket*, double> mLastPongMs;
  void heartbeatThreadRun();
  void startHeartbeatThread();
  void stopHeartbeatThread();

  static constexpr int kSenderPollMs        = 5;      // 后台发送线程轮询周期
  static constexpr int kHeartbeatIntervalMs = 5000;   // 服务端每 5s 发 ping
  static constexpr double kHeartbeatTimeoutMs = 12000.0; // 距上次 pong >12s 关连接（有效 ~15s）
};

} // namespace synchain
