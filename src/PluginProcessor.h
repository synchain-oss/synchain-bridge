// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <atomic>
#include "AudioMeter.h"
#include "BridgeApi.h"
#include "VstBridgeServer.h"

namespace synchain
{

// private juce::Timer：在 message 线程周期性 consume web 下发音量并应用（见 timerCallback）。
// 编辑器 Timer 也 consume，但仅在编辑器打开时跑；本 Processor Timer 覆盖**编辑器关闭**场景
// （Space 网页客户端在插件窗口未打开时调音量）。两者经原子 exchange 双消费安全（谁先跑谁应用）。
class SynchainBridgeAudioProcessor : public juce::AudioProcessor, private juce::Timer
{
public:
    SynchainBridgeAudioProcessor();
    ~SynchainBridgeAudioProcessor() override;

    // juce::AudioProcessor interface
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "Synchain Bridge"; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}

    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    // VST Bridge server access (for Editor)
    VstBridgeServer& getBridgeServer() { return mBridgeServer; }
    AudioMeter& getMeter() { return mMeter; }

    // Editor-facing snapshot API (frozen contract, see BRIDGE_CONTRACT.md)
    float meterLdb() const { return mMeterLdb.load(std::memory_order_relaxed); }
    float meterRdb() const { return mMeterRdb.load(std::memory_order_relaxed); }
    float meterPeak() const { return mMeterPeak.load(std::memory_order_relaxed); }
    int clientCount() const { return mBridgeServer.getClientCount(); }
    int currentSampleRate() const { return static_cast<int>(mCurrentSampleRate.load(std::memory_order_relaxed)); }
    int currentChannels() const { return mCurrentChannels.load(std::memory_order_relaxed); }
    double latencyMs() const
    {
        const double sr = mCurrentSampleRate.load(std::memory_order_relaxed);
        const int bs = mCurrentBlockSize.load(std::memory_order_relaxed);
        return sr > 0.0 ? 1000.0 * static_cast<double>(bs) / sr : 0.0;
    }

    int getPort() const { return mPort; }
    void setPort(int p) { mPort = juce::jlimit(1024, 65535, p); }

    juce::String getLang() const { return mLang; }
    void setLang(const juce::String& code) { mLang = code; }

    // 界面缩放档位：每工程值持久化于 APVTS state（get/setStateInformation），
    // 另有「全局默认」持久化于 userAppData/Synchain/SynchainBridge.settings（见 .cpp），
    // 由编辑器改档位后经 persistUiScaleAsDefault() 写入，使新实例/新工程沿用上次尺寸。
    float getUiScale() const { return mUiScale; }
    void setUiScale(float s) { mUiScale = juce::jlimit(plugin::MinUiScale, plugin::MaxUiScale, s); }
    // 把当前 uiScale 写入全局设置文件（message 线程调用；见 WebViewEditor::handleSetUiScale）
    void persistUiScaleAsDefault();

    int getVolumePct() const
    {
        return mGainParam != nullptr ? juce::roundToInt(mGainParam->load(std::memory_order_relaxed) * 100.0f) : 100;
    }
    void setVolumePct(int pct)
    {
        if (auto* param = mApvts.getParameter("masterGain"))
            param->setValueNotifyingHost(juce::jlimit(0, 200, pct) / 200.0f);
    }

    // browser→plugin 音量应用（v1.2.10 修）：onVolumeChange 在 **WS 线程** 触发，之前用
    // juce::MessageManager::callAsync 转 message 线程再 setVolumePct，但实测某些宿主里该 callAsync
    // 未能可靠执行 → 网页调音量对插件无效。改为：WS 线程仅把待应用值存原子（requestWebVolume），由
    // 编辑器 Timer（**确定在 message 线程**，VST→web 广播正走它）consume 并 setVolumePct。
    void requestWebVolume(int pct) { mPendingWebVolume.store(juce::jlimit(0, 200, pct), std::memory_order_relaxed); }
    // 返回待应用音量（0..200）并清空；无待应用返回 -1。仅编辑器 Timer（message 线程）调用。
    int consumePendingWebVolume() { return mPendingWebVolume.exchange(-1, std::memory_order_relaxed); }

    juce::AudioProcessorValueTreeState& getApvts() { return mApvts; }

private:
    // message 线程周期回调：应用 web 下发音量（编辑器关闭时的 fallback，见类注释）。
    void timerCallback() override;

    static juce::AudioProcessorValueTreeState::ParameterLayout makeLayout();

    AudioMeter mMeter;
    VstBridgeServer mBridgeServer;
    juce::AudioProcessorValueTreeState mApvts;
    std::atomic<float>* mGainParam = nullptr;

    // 音频线程写（processBlock/prepareToPlay），消息/网络线程读（编辑器 Timer、
    // server 回调）→ 用 atomic 消除 data race（与 mMeter* 保持一致）。
    std::atomic<double> mCurrentSampleRate{48000.0};
    std::atomic<int> mCurrentBlockSize{256};
    std::atomic<int> mCurrentChannels{2};

    // web 下发的待应用主控音量（-1 = 无）。WS 线程写（requestWebVolume），编辑器 Timer 读并清（message 线程）。
    std::atomic<int> mPendingWebVolume{-1};

    int mPort = synchain::plugin::DefaultPort;
    juce::String mLang{"zh"};
    float mUiScale = synchain::plugin::DefaultUiScale;

    // 交织立体声 staging：单声道缓冲，容量 = 2*mMaxBlockSamples 个 float
    // （work[2i]=L, work[2i+1]=R）。不依赖 JUCE 多声道内存连续布局；processBlock 按
    // mMaxBlockSamples 夹取 numSamples，2*numSamples 恒不越界（#169）。
    juce::AudioBuffer<float> mWorkBuffer;
    int mMaxBlockSamples = 0; // prepareToPlay 宣告的块上界，processBlock 越界夹取用

    // Meter levels, updated on the audio thread, read by the editor's timer
    std::atomic<float> mMeterLdb{-60.0f};
    std::atomic<float> mMeterRdb{-60.0f};
    std::atomic<float> mMeterPeak{-60.0f};

    // Meter broadcast throttle
    int mMeterFrameCounter = 0;
    static constexpr int kMeterIntervalFrames = 4; // ~20 Hz at 256-sample blocks

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SynchainBridgeAudioProcessor)
};

} // namespace synchain
