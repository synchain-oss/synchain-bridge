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
#include "WebViewRevealGate.h"

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
// （含安装引导 + 重试）；运行时在但加载超时（看门狗）亦切兜底。
//
// [SL-386] 开窗遮挡闸（机理/理由只写在 src/WebViewRevealGate.h 一处）：导航开始后把
// WebView 子窗口挪出可视区（不 setVisible(false)、不零尺寸），占位渐变分两层铺：
//   • 宿主本类 paint() —— 遮挡窗口内唯一会跑的一层（BridgeWebView 被挪到 x=2W、与可视区
//     零交集，JUCE 整个跳过它的 paint）；
//   • BridgeWebView::paint —— 守「导航开始前 / 已放行」时自己表面上的白（fallbackPaint），
//     未遮挡时被 WebView2 表面盖住。
// 两层用同一组 kPlaceholderStops（成品可见底同形）。前端 DOMContentLoaded 后两层 rAF 发
// 首帧信号（timing::FirstFrameSignal），**只认首帧放行**（navFinished 只记账），信号后再压
// tick ∧ 32ms 一拍才挪回；3s 超时兜底，兜底面板逻辑不变。挪窗激活只在 Windows
// （#if JUCE_WINDOWS）；mac 路径保持现状。
// =============================================================================

class SynchainBridgeWebEditor final : public juce::AudioProcessorEditor, private juce::Timer
{
public:
    explicit SynchainBridgeWebEditor(SynchainBridgeAudioProcessor& processor);
    ~SynchainBridgeWebEditor() override;

    void resized() override;
    void paint(juce::Graphics&) override;

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

    // --- [SL-386] 加载时序与开窗遮挡闸（message 线程）---
    void beginLoadAttempt(); // 构造 / retry 共用：重置看门狗与闸门，重新 goToURL
    void onNavigationStarted(const juce::String& url); // BridgeWebView::pageAboutToLoad 转发
    void onNavigationFinished(const juce::String& url); // BridgeWebView::pageFinishedLoading 转发
    void handleFirstFrame(); // timing::FirstFrameSignal 事件（前端「首帧已绘」）
    void applyRevealGate(); // 把闸门的判定落到 mWebView 的 bounds 上（唯一出口）
    void noteRevealed(); // 放行诊断行（reason + 用时；timeout 行带 navFinished 分诊后缀）
    void logDiag(const juce::String& line) const;

    // 看门狗预算（行为不变，自 v1 起为固定 5s；这里提升为具名常量只为与遮挡闸的 3s 兜底
    // 建立编译期常量关系 —— 见下面 static_assert 与 beginLoadAttempt 处的起算前提）。
    static constexpr int kWatchdogBudgetMs = 5000;

    // [SL-378 同族] 遮挡闸的 timeout 兜底（3s）必须早于看门狗切兜底面板（5s），否则按住
    // 占位的那 3s 会被面板顶掉 —— 形态不是「多按一会儿占位」而是直接进兜底。这一半（常量
    // 关系）由本断言在每次编译上守；另一半（前提：两个预算同时起算 —— 都从 beginLoadAttempt
    // 落下的 mStartMs / 导航开始起算且闸门 3s 从导航开始算）写死在 beginLoadAttempt 的注释里。
    // 与 SCVB 不同，本仓看门狗不分冷/热预算，故没有「顺延复位」那半个缺口要守。
    static_assert(webview::kRevealFallbackMs < kWatchdogBudgetMs,
                  "遮挡闸的 timeout 兜底(kRevealFallbackMs)必须早于看门狗预算(kWatchdogBudgetMs),"
                  "否则占位段会被兜底面板顶掉");

    // 为「开窗遮挡闸 + 导航时序回调」而存在的薄子类（定义在 .cpp；机理见其 paint 注释）。
    class BridgeWebView;

    SynchainBridgeAudioProcessor& mProcessor;

    std::unique_ptr<BridgeWebView> mWebView; // 用 makeOptions() 构造（声明顺序在 mProcessor 之后）
    std::unique_ptr<juce::Component> mFallback; // WebView2 缺失时的原生兜底面板

    // [SL-386] 开窗遮挡闸：「WebView 子窗口此刻该不该待在可视区之外」的唯一判定处。
    webview::RevealGate mRevealGate;
    bool mRevealLogged = false; // 本次加载尝试是否已写过放行诊断行（只写第一次）

    // 就绪门控 + 变化节流（只在 message 线程访问，mBridgeReady 跨线程读写用 atomic）
    std::atomic<bool> mBridgeReady{false};
    float mLastLdb = 1.0e9f, mLastRdb = 1.0e9f;
    int mLastClients = -1, mLastSampleRate = -1, mLastChannels = -1, mLastVolume = -1;
    bool mLastRunning = false;
    juce::uint32 mStartMs = 0; // 看门狗计时基准（beginLoadAttempt 落点；诊断行 after 也从这里算）

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SynchainBridgeWebEditor)
};

} // namespace synchain
