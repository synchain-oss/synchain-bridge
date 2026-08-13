// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_extra/juce_gui_extra.h> // WebBrowserComponent (juce_gui_extra module)
#include <atomic>
#include <memory>
#include <optional>
#include "PluginProcessor.h"
#include "BridgeApi.h"

namespace synchain
{

// =============================================================================
// Synchain Bridge — WebView 编辑器（桥 #1：编辑器内 WebView <-> processor）
// -----------------------------------------------------------------------------
// 用 juce::WebBrowserComponent 承载 web/ 里的玻璃拟态 UI，经 JUCE 原生集成
// (window.__JUCE__) 双向通信：
//   • C++ -> JS：25Hz Timer 读 processor 原子量后 emitEventIfBrowserIsVisible
//                （bridge.state / bridge.meter / bridge.audio / bridge.error）。
//   • JS -> C++：withNativeFunction 注册的 requestInitialState / toggleRun /
//                setPort / setMasterGain / setLang（见 BridgeApi.h）。
// 事件名 / 函数名 / 键名严格取自 BridgeApi.h（synchain::bridge::*）。
// Windows 显式选 WebView2 后端（makeOptions withBackend）；运行时缺失 -> 立即切最小原生兜底面板
// （含安装引导 + 重试）；运行时在但加载超时（5s 看门狗）亦切兜底。
// =============================================================================

class SynchainBridgeWebEditor final : public juce::AudioProcessorEditor, private juce::Timer
{
public:
    explicit SynchainBridgeWebEditor(SynchainBridgeAudioProcessor& processor);
    ~SynchainBridgeWebEditor() override;

    void resized() override;

private:
    void timerCallback() override;

    // --- WebView 装配 ---
    juce::WebBrowserComponent::Options makeOptions();
    std::optional<juce::WebBrowserComponent::Resource> provideResource(const juce::String& url) const;
    static const char* mimeForExtension(const juce::String& ext);

    // --- 原生函数处理（均在 message 线程被调用）---
    void handleRequestInitialState(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleToggleRun(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleSetPort(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleSetMasterGain(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleSetLang(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleSetUiScale(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    void handleCommitUiScale(const juce::Array<juce::var>&, juce::WebBrowserComponent::NativeFunctionCompletion);
    juce::var buildSnapshot() const;

    // --- WebView2 运行时探测 / 兜底面板 ---
    enum class FallbackReason
    {
        MissingRuntime,
        LoadTimeout
    };
    static bool webView2RuntimeAvailable();
    void showFallback(FallbackReason reason);
    void retryWebView();

    SynchainBridgeAudioProcessor& mProcessor;

    juce::WebBrowserComponent mWebView; // 用 makeOptions() 构造（声明顺序在 mProcessor 之后）
    std::unique_ptr<juce::Component> mFallback; // WebView2 缺失时的原生兜底面板

    // 就绪门控 + 变化节流（只在 message 线程访问，mBridgeReady 跨线程读写用 atomic）
    std::atomic<bool> mBridgeReady{false};
    float mLastLdb = 1.0e9f, mLastRdb = 1.0e9f;
    int mLastClients = -1, mLastSampleRate = -1, mLastChannels = -1, mLastVolume = -1;
    bool mLastRunning = false;
    juce::uint32 mStartMs = 0; // WebView2 看门狗计时基准

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SynchainBridgeWebEditor)
};

} // namespace synchain
