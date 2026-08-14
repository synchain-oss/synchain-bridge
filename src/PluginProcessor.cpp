// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "PluginProcessor.h"
#include "WebViewEditor.h"

namespace synchain
{

namespace
{
// 界面缩放的「全局默认」持久化（跨实例/工程）：APVTS 存的是每工程值，这个文件存最近一次选择，
// 让新实例/新工程也开在用户上次的尺寸，免得每次都要重设。写在 message 线程、低频、失败即回落默认。
juce::File globalSettingsFile()
{
    return juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
        .getChildFile("Synchain")
        .getChildFile("SynchainBridge.settings");
}
float readGlobalUiScaleDefault()
{
    if (auto xml = juce::XmlDocument::parse(globalSettingsFile()))
        return static_cast<float>(xml->getDoubleAttribute("uiScale", plugin::DefaultUiScale));
    return plugin::DefaultUiScale;
}
void writeGlobalUiScaleDefault(float s)
{
    const auto f = globalSettingsFile();
    f.getParentDirectory().createDirectory();
    juce::XmlElement xml("SynchainBridge");
    xml.setAttribute("uiScale", static_cast<double>(s));
    xml.writeTo(f);
}
} // namespace

juce::AudioProcessorValueTreeState::ParameterLayout SynchainBridgeAudioProcessor::makeLayout()
{
    juce::AudioProcessorValueTreeState::ParameterLayout layout;
    layout.add(std::make_unique<juce::AudioParameterFloat>(juce::ParameterID{"masterGain", 1}, "Stream Master",
                                                           juce::NormalisableRange<float>{0.0f, 2.0f, 0.001f}, 1.0f));
    return layout;
}

SynchainBridgeAudioProcessor::SynchainBridgeAudioProcessor()
    : juce::AudioProcessor(BusesProperties()
                               .withInput("Input", juce::AudioChannelSet::stereo(), true)
                               .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      mApvts(*this, nullptr, "state", makeLayout())
{
    mGainParam = mApvts.getRawParameterValue("masterGain");

    // 全局默认档位（跨实例/工程）：新实例先开在用户上次选择的尺寸；
    // 若随后 setStateInformation 带来每工程 uiScale，会再覆盖它。
    setUiScale(readGlobalUiScaleDefault());

    mBridgeServer.callbacks.onHandshake = [this](const juce::String& projectId, const juce::String& userId,
                                                 const juce::String& username) {
        juce::ignoreUnused(projectId, userId, username);
        mBridgeServer.sendStatus(true, "Synchain Bridge", JucePlugin_VersionString,
                                 getVolumePct()); // 带上当前主控音量，网页据此初始化 DAW 音量条
        mBridgeServer.sendSettings(
            static_cast<int>(mCurrentSampleRate.load(std::memory_order_relaxed)),
            mCurrentBlockSize.load(std::memory_order_relaxed),
            mCurrentChannels.load(std::memory_order_relaxed), // 真实声道数（曾硬编码 2，致网页恒显示立体声）
            128000, latencyMs());
    };

    mBridgeServer.callbacks.onSettingsRequest = [this]() {
        mBridgeServer.sendSettings(
            static_cast<int>(mCurrentSampleRate.load(std::memory_order_relaxed)),
            mCurrentBlockSize.load(std::memory_order_relaxed),
            mCurrentChannels.load(std::memory_order_relaxed), // 真实声道数（曾硬编码 2，致网页恒显示立体声）
            128000, latencyMs());
    };

    // browser -> plugin：网页 DAW 音量条设主控音量。回调在 **WS 线程** 触发，而 setVolumePct →
    // APVTS setValueNotifyingHost 须在 message 线程。v1.2.9 曾用 juce::MessageManager::callAsync 转投，
    // 但实测某些宿主里该 callAsync 不可靠执行 → 网页调音量对插件无效。改为仅存原子，由编辑器 Timer
    // （确在 message 线程，VST→web 广播也走它）consume 并 setVolumePct（见 WebViewEditor::timerCallback）。
    mBridgeServer.callbacks.onVolumeChange = [this](int pct) { requestWebVolume(pct); };

    // message 线程周期消费 web 下发音量（编辑器关闭时的 fallback；编辑器 Timer 打开时也消费，双消费经
    // 原子 exchange 安全）。30Hz 足够跟手，且不引入可闻延迟。
    startTimerHz(30);
}

SynchainBridgeAudioProcessor::~SynchainBridgeAudioProcessor()
{
    stopTimer();
    mBridgeServer.stop();
}

void SynchainBridgeAudioProcessor::timerCallback()
{
    // message 线程：安全 setVolumePct（setValueNotifyingHost 须在此线程）。见类注释/onVolumeChange。
    if (const int webVol = consumePendingWebVolume(); webVol >= 0)
        setVolumePct(webVol);
}

void SynchainBridgeAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    mCurrentSampleRate.store(sampleRate, std::memory_order_relaxed);
    mCurrentBlockSize.store(samplesPerBlock, std::memory_order_relaxed);
    mCurrentChannels.store(getTotalNumInputChannels(), std::memory_order_relaxed);

    // Note: WebSocket server is started via the editor's "Start Bridge" button
    // (message thread), NOT here on the audio thread.

    // 交织立体声 staging 改为单声道、容量 2*maxBlock floats（Synchain issue 169）：不依赖声道内存
    // 连续性，且给 processBlock 的越界夹取一个稳定上界。
    mMaxBlockSamples = juce::jmax(0, samplesPerBlock);
    mWorkBuffer.setSize(1, 2 * mMaxBlockSamples, false, true, false);

    // Synchain issue 168：预分配 SPSC ring 的定长 slot 池（数据源与 mWorkBuffer 同为交织 2*maxBlock）。
    // 允许分配（JUCE 保证 prepareToPlay 与 processBlock 串行）；后台发送线程另绑 start()/stop()。
    mBridgeServer.prepareStreaming(mMaxBlockSamples, 32);
}

void SynchainBridgeAudioProcessor::releaseResources()
{
    // Synchain issue 168：释放 ring slot 池（受 mStreamMutex 保护，与后台发送线程互斥）。
    mBridgeServer.releaseStreaming();
}

void SynchainBridgeAudioProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& /*midiMessages*/)
{

    juce::ScopedNoDenormals noDenormals;
    const int numChannels = buffer.getNumChannels();
    int numSamples = buffer.getNumSamples();
    mCurrentChannels.store(numChannels, std::memory_order_relaxed);

    if (!mBridgeServer.isRunning())
        return; // standby: no metering, no send

    // 防越界（Synchain issue 169）：宿主可能给出比 prepareToPlay 宣告更大的块（或在 prepare 前回调）。
    // 夹取到已预分配容量上界；绝不在音频线程重新分配。numChannels<=0 无有效声道 → 早退。
    jassert(numChannels > 0 && numSamples <= mMaxBlockSamples);
    numSamples = juce::jmin(numSamples, mMaxBlockSamples);
    if (numChannels <= 0 || numSamples <= 0)
        return;

    // buffer is passed through untouched — gain only applies to the stream copy
    const float gain = mGainParam ? mGainParam->load(std::memory_order_relaxed) : 1.0f;
    const float* leftChannel = buffer.getReadPointer(0);
    const float* rightChannel = numChannels > 1 ? buffer.getReadPointer(1) : leftChannel;
    auto* workBuffer = mWorkBuffer.getWritePointer(0); // 容量 2*mMaxBlockSamples floats

    for (int i = 0; i < numSamples; ++i)
    {
        workBuffer[i * 2] = leftChannel[i] * gain;
        workBuffer[i * 2 + 1] = rightChannel[i] * gain;
    }

    // Meter reflects the post-gain (streamed) signal.
    // Synchain issue 168：音频线程只做无锁零分配握把——原子发布电平 + push 进 SPSC ring；
    // 组帧 / 加锁快照 / WS 发送全部移到后台发送线程。删除了原 getClientCount() 的锁与
    // sendMeterLevels/sendPcmPacket 的分配+锁+同步发送。发送门控由 pushMeter/pushPcm
    // 内部读 mAudioClientCount（原子）完成。
    mMeter.process(workBuffer, numSamples);
    if (++mMeterFrameCounter >= kMeterIntervalFrames)
    {
        mMeterFrameCounter = 0;
        auto levels = mMeter.getLevels();
        mMeterLdb.store(levels.left, std::memory_order_relaxed);
        mMeterRdb.store(levels.right, std::memory_order_relaxed);
        mMeterPeak.store(levels.peak, std::memory_order_relaxed);
        mBridgeServer.pushMeter(levels.left, levels.right, levels.peak);
    }

    // Frame header channels is always 2 (mono input is duplicated to the right channel above).
    mBridgeServer.pushPcm(workBuffer, numSamples, static_cast<int>(mCurrentSampleRate.load(std::memory_order_relaxed)),
                          2);
}

juce::AudioProcessorEditor* SynchainBridgeAudioProcessor::createEditor()
{
    return new SynchainBridgeWebEditor(*this);
}

void SynchainBridgeAudioProcessor::getStateInformation(juce::MemoryBlock& destData)
{
    auto state = mApvts.copyState();
    state.setProperty("port", mPort, nullptr);
    state.setProperty("lang", mLang, nullptr);
    state.setProperty("uiScale", mUiScale, nullptr);
    if (auto xml = state.createXml())
        copyXmlToBinary(*xml, destData);
}

void SynchainBridgeAudioProcessor::setStateInformation(const void* data, int sizeInBytes)
{
    if (auto xml = getXmlFromBinary(data, sizeInBytes))
    {
        auto tree = juce::ValueTree::fromXml(*xml);
        if (tree.isValid() && tree.hasType(mApvts.state.getType()))
        {
            mApvts.replaceState(tree);
            mPort = static_cast<int>(tree.getProperty("port", synchain::plugin::DefaultPort));
            mLang = tree.getProperty("lang", "zh").toString();
            setUiScale(
                static_cast<float>(static_cast<double>(tree.getProperty("uiScale", synchain::plugin::DefaultUiScale))));
        }
    } // parse failure / legacy format -> keep defaults, stay backward compatible
}

void SynchainBridgeAudioProcessor::persistUiScaleAsDefault()
{
    // 编辑器改档位后调用：把当前 mUiScale 写入全局设置文件，作为下次新实例/新工程的默认。
    writeGlobalUiScaleDefault(mUiScale);
}

} // namespace synchain

// JUCE plugin factory
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new synchain::SynchainBridgeAudioProcessor();
}
