// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "WebViewEditor.h"
#include "BinaryData.h" // 由 juce_add_binary_data(SynchainBridgeWebAssets) 生成

#include <cmath>
#include <cstdint>
#include <functional>
#include <type_traits>
#include <vector>

#if JUCE_WINDOWS
// WebView2 静态 loader（JUCE NEEDS_WEBVIEW2 + 静态链接）导出；ole32 提供 CoTaskMemFree。
// 直接前置声明，免引 <WebView2.h>/<windows.h>（避开 include 路径与宏污染）。
extern "C" {
long __stdcall GetAvailableCoreWebView2BrowserVersionString(const wchar_t* browserExecutableFolder,
                                                            wchar_t** versionInfo);
void __stdcall CoTaskMemFree(void* pv);
}
#endif

namespace synchain
{

using WBC = juce::WebBrowserComponent;

namespace
{

// 100% 设计基准尺寸：编辑器窗口 = DESIGN × uiScale；web 侧 zoom = innerWidth/kDesignW 精确铺满。
// 卡片按 space-between 铺满该盒；改这两个数即整体改窗口比例（web 常量需同步，见 index.html DESIGN_W/H）。
constexpr int kDesignW = 460;
constexpr int kDesignH = 560;

// [SL-386] 遮挡期间 WebView 子窗口该占的矩形：几何真源在 WebViewRevealGate.h 的
// parkedRect（零依赖、有 selftest），这里只做 juce::Rectangle 的壳。JUCE 把它换算成
// 宿主 HWND 客户区坐标喂给 ICoreWebView2Controller::put_Bounds，子窗口恒被 Windows 裁到
// 父窗口客户区内 ⇒ 屏上看不见。⚠ 这依赖「JUCE 把一次只改 x 的 setBounds 也转发到
// put_Bounds」——读 JUCE 实现核过成立（ComponentMovementWatcher 按顶层坐标重算 wasMoved,
// 纯位移即真;WebView2 后端覆写不看标志一律 setControlBounds）。
juce::Rectangle<int> parkedBounds(juce::Rectangle<int> visible) noexcept
{
    const auto r = webview::parkedRect(visible.getX(), visible.getY(), visible.getWidth(), visible.getHeight());
    return {r.x, r.y, r.width, r.height};
}

#if JUCE_WINDOWS
// [SL-386] 占位渐变的**唯一绘制实现**,两个调用点共用(不许各写一份——三处同源的 C++ 侧
// 只有一个消费者入口):① 宿主 SynchainBridgeWebEditor::paint(遮挡窗口内唯一会跑的一层);
// ② BridgeWebView::paint(守导航开始前/已放行时自己表面上的 fallbackPaint 白)。
// 色标与几何真源 = webview::kPlaceholderStops / placeholderGradientEndpoints。
void paintPlaceholderGradient(juce::Graphics& g, int width, int height)
{
    const auto e = webview::placeholderGradientEndpoints(width, height);
    const auto p0 = juce::Point<float>(static_cast<float>(e.x0), static_cast<float>(e.y0));
    const auto p1 = juce::Point<float>(static_cast<float>(e.x1), static_cast<float>(e.y1));
    auto grad = juce::ColourGradient(juce::Colour(webview::kPlaceholderStops[0].argb), p0,
                                     juce::Colour(webview::kPlaceholderStops[webview::kPlaceholderStopCount - 1].argb),
                                     p1, false);
    for (int i = 1; i < webview::kPlaceholderStopCount - 1; ++i)
        grad.addColour(webview::kPlaceholderStops[i].position, juce::Colour(webview::kPlaceholderStops[i].argb));
    g.setGradientFill(grad);
    g.fillAll();
}
#endif

// -----------------------------------------------------------------------------
// FallbackPanel — WebView 起不来时的最小原生兜底面板。
// 仅提供 Start/Stop + 端口 + 状态，保证 UI 加载失败时仍可控制桥 #2。
// missingRuntime 分支（缺 WebView2 运行时）只可能在 Windows 出现，故其文案保留 WebView2 表述；
// LoadTimeout 分支两个平台都可达（mac 的 WKWebView 冷启动同样可能超时），文案保持平台中立。
// -----------------------------------------------------------------------------
class FallbackPanel final : public juce::Component, private juce::Timer
{
public:
    FallbackPanel(SynchainBridgeAudioProcessor& p, bool missingRuntime, std::function<void()> onInstall,
                  std::function<void()> onRetry)
        : mProcessor(p), mMissingRuntime(missingRuntime), mOnInstall(std::move(onInstall)), mOnRetry(std::move(onRetry))
    {
        mTitle.setText("Synchain Bridge", juce::dontSendNotification);
        mTitle.setJustificationType(juce::Justification::centred);
        mTitle.setFont(juce::Font(juce::FontOptions(20.0f, juce::Font::bold)));
        mTitle.setColour(juce::Label::textColourId, juce::Colours::white);
        addAndMakeVisible(mTitle);

        mMessage.setText(missingRuntime
                             ? "Microsoft Edge WebView2 Runtime was not found, so the full UI cannot load.\n"
                               "This plugin needs an internet connection to work anyway - install the runtime "
                               "once, then reopen this plugin window."
                             : "The plugin UI is taking too long to load (possibly a first-time cold start).\n"
                               "Click Retry, or close and reopen this plugin window.",
                         juce::dontSendNotification);
        mMessage.setJustificationType(juce::Justification::centredTop);
        mMessage.setColour(juce::Label::textColourId, juce::Colour(0xffb8b8c4));
        addAndMakeVisible(mMessage);

        if (mMissingRuntime)
        {
            mInstall.setButtonText("Download WebView2 Runtime");
            mInstall.onClick = [this] {
                if (mOnInstall)
                    mOnInstall();
            };
            addAndMakeVisible(mInstall);
        }
        mRetry.setButtonText("Retry");
        mRetry.onClick = [this] {
            if (mOnRetry)
                mOnRetry();
        };
        addAndMakeVisible(mRetry);

        mPort.setText(juce::String(mProcessor.getPort()), juce::dontSendNotification);
        mPort.setInputRestrictions(5, "0123456789");
        mPort.setJustification(juce::Justification::centred);
        addAndMakeVisible(mPort);

        mToggle.onClick = [this] {
            auto& server = mProcessor.getBridgeServer();
            if (server.isRunning())
            {
                server.stop();
            }
            else
            {
                const int port = mPort.getText().getIntValue();
                if (port >= plugin::MinPort && port <= plugin::MaxPort)
                    mProcessor.setPort(port);
                server.start(mProcessor.getPort());
            }
            refresh();
        };
        addAndMakeVisible(mToggle);

        mStatus.setJustificationType(juce::Justification::centred);
        mStatus.setColour(juce::Label::textColourId, juce::Colour(0xffd0d0da));
        addAndMakeVisible(mStatus);

        refresh();
        startTimerHz(4);
    }

    ~FallbackPanel() override { stopTimer(); }

    void paint(juce::Graphics& g) override { g.fillAll(juce::Colour(0xff18161d)); }

    void resized() override
    {
        auto b = getLocalBounds().reduced(24);
        mTitle.setBounds(b.removeFromTop(34));
        mMessage.setBounds(b.removeFromTop(76));
        b.removeFromTop(10);
        if (mMissingRuntime)
        {
            mInstall.setBounds(b.removeFromTop(38).reduced(24, 0));
            b.removeFromTop(8);
        }
        mRetry.setBounds(b.removeFromTop(34).reduced(96, 0));
        b.removeFromTop(16);
        mPort.setBounds(b.removeFromTop(34).reduced(70, 0));
        b.removeFromTop(10);
        mToggle.setBounds(b.removeFromTop(40).reduced(50, 0));
        b.removeFromTop(12);
        mStatus.setBounds(b.removeFromTop(28));
    }

private:
    void timerCallback() override { refresh(); }

    void refresh()
    {
        auto& server = mProcessor.getBridgeServer();
        const bool running = server.isRunning();
        mToggle.setButtonText(running ? "Stop Bridge" : "Start Bridge");
        mStatus.setText(running ? "Running - port " + juce::String(server.getPort()) + " - clients " +
                                      juce::String(mProcessor.clientCount())
                                : "Idle",
                        juce::dontSendNotification);
    }

    SynchainBridgeAudioProcessor& mProcessor;
    bool mMissingRuntime;
    std::function<void()> mOnInstall, mOnRetry;
    juce::Label mTitle, mMessage, mStatus;
    juce::TextEditor mPort;
    juce::TextButton mToggle, mInstall, mRetry;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(FallbackPanel)
};

} // namespace

// =============================================================================
// BridgeWebView —— 为「开窗遮挡闸 + 导航时序回调」而存在的薄子类（[SL-386] 移植 SCVB 的
// HostWebView；机理与理由只写在 src/WebViewRevealGate.h 一处，这里不复述）。
// -----------------------------------------------------------------------------
//   • pageAboutToLoad / pageFinishedLoading：JUCE 唯一暴露导航时序的两个虚函数。闸门靠
//     「导航开始」（= WebView2 控制器已建好）才知道何时可以挪窗；navFinished 只记账不放行。
//   • paint：**先调基类，再整块盖上占位底**。基类 = WebView2 后端的 fallbackPaint：每帧
//     无条件 fillAll(Colours::white) —— 开窗白闪的白的来源就是它；它尾巴上的
//     checkWindowAssociation 又是 WebView2 控制器的重试泵，所以**必须**调基类（拆掉泵是
//     真机开窗风险），白由下一句盖掉。两次 fillAll 落在同一次 paint 里，先白后占位、
//     中间不上屏（Windows 侧两条渲染路都是整帧画完才出），上屏的只有后盖的那层。
//     mac（#else 路径）：保持现状，只走基类 paint —— 不铺占位（SL-386 派工口径）。
// =============================================================================
class SynchainBridgeWebEditor::BridgeWebView final : public juce::WebBrowserComponent
{
public:
    BridgeWebView(SynchainBridgeWebEditor& owner, juce::WebBrowserComponent::Options options)
        : juce::WebBrowserComponent(std::move(options)), mOwner(owner)
    {
    }

    void paint(juce::Graphics& g) override
    {
        // 基类 = fallbackPaint：WebView2 后端的 fillAll(Colours::white) + 控制器重试泵。
        // 这一句**必须在前**：它画的白由下面整块盖掉，而泵要的是「每帧都被调到」。
        juce::WebBrowserComponent::paint(g);

#if JUCE_WINDOWS
        // [SL-386] 这一层守的是「**没被挪走时**自己表面上的白」：控制器已建好但导航尚未开始
        // （闸门还没 parked）、以及放行之后的稳态过渡。⚠ 遮挡窗口内它**不被绘制**——本组件被
        // 挪到 x=2W、与可视区零交集，JUCE 按 bounds 裁剪整个跳过它的 paint（bot 第 1 轮
        // 【重要】抓到的正是这一点）；遮挡窗口的占位由宿主 paint() 铺，见本文件
        // SynchainBridgeWebEditor::paint。占位底 = 成品可见底（web/styles.css
        // --vb-card-surface 的玻璃拟态渐变，三处同源判据 = web-preview/reveal-first-frame.test.mjs）。
        paintPlaceholderGradient(g, getWidth(), getHeight());
#endif
    }

    bool pageAboutToLoad(const juce::String& url) override
    {
        mOwner.onNavigationStarted(url);
        return true; // 本插件只导航到 resource provider 根，不拦
    }

    void pageFinishedLoading(const juce::String& url) override { mOwner.onNavigationFinished(url); }

    // [SL-386] 删除式判据。paint 一旦不再由本类覆写，decltype 经名字查找落到基类签名，
    // 本断言当场编译红（gate 5 / CI 都会拦下）。放在类体内与 SCVB 的 HostWebView 同款：
    // 注入类名在此可见，且类体外够不着这个私有嵌套类。它守的是「paint 由本类覆写」这件事
    // 本身；函数体里那句基类调用删没删，它守不到 —— 那半边靠上面的注释与真机验收兜。
    static_assert(std::is_same_v<decltype(&BridgeWebView::paint), void (BridgeWebView::*)(juce::Graphics&)>,
                  "[SL-386] BridgeWebView::paint 必须由本类覆写:少了它,JUCE WebView2 后端的 fallbackPaint "
                  "每帧 fillAll(Colours::white),开窗白闪回归。");

private:
    SynchainBridgeWebEditor& mOwner;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BridgeWebView)
};

// =============================================================================
// SynchainBridgeWebEditor
// =============================================================================

SynchainBridgeWebEditor::SynchainBridgeWebEditor(SynchainBridgeAudioProcessor& p)
    : juce::AudioProcessorEditor(&p), mProcessor(p)
{
#if JUCE_WINDOWS
    // [SL-421] 声明本组件完全不透明：JUCE 因此不会去画它下面的东西（宿主给的编辑器容器）。
    // ⚠ 它**不治**开窗白闪 —— 白闪那几段里本组件的 paint 要么被 WebView2 表面盖住、要么
    // 画的就是占位（见下面 paint()）。它管的是兜底面板路径下这块底。与 SCVB
    // WebViewHost 构造里那一句同形、同理由，一并搬过来免得两仓形态分家。
    // ⚠ **必须与 paint() 同平台条件**（第 1 轮复审两家都点了）：paint() 的绘制体在
    // #if JUCE_WINDOWS 里，非 Windows 是空实现；若这句无条件生效，mac 上就成了「声明自己
    // 不透明、却一个像素都不画」—— 构造→attach、retryWebView() 里 mFallback.reset()→resized()
    // 这两个窗口里，WKWebView 还没盖住的区域拿到的是未定义的后备缓冲内容。
    setOpaque(true);
#endif

    mWebView = std::make_unique<BridgeWebView>(*this, makeOptions());
    addAndMakeVisible(*mWebView);

    setResizable(false, false); // 仅经缩放档位下拉（setUiScale）编程改尺寸，不开自由拖角
    {
        const float s = mProcessor.getUiScale();
        setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));
    }

    // 先探测 WebView2 运行时：有则正常加载（看门狗容忍冷启动）；无则直接给可操作的兜底面板，
    // 并引导一次性安装，不做无意义等待。加载路径收进 beginLoadAttempt（构造 / retry 共用，
    // [SL-386] 含遮挡闸重新武装），missing 分支里 showFallback 自己会 setVisible(false)。
    beginLoadAttempt();
}

SynchainBridgeWebEditor::~SynchainBridgeWebEditor()
{
    stopTimer();
}

// [SL-421] 运行时版本串（空 = 没探到运行时）。原先这里只回一个 bool，把 loader 给的版本串
// 丢掉了；DefaultBackgroundColor 那一层在不在只能从主版本号推（见 WebViewRevealGate.h 的
// defaultBackgroundSupport 头注），所以把版本串留下来。「在不在」的判定仍是**同一个**
// GetAvailableCoreWebView2BrowserVersionString 调用、同一个「hr >= 0 且非空」判定，
// 「运行时在不在」的语义与改动前逐字一致 —— 调用方改判 isEmpty()。
juce::String SynchainBridgeWebEditor::webView2RuntimeVersion()
{
#if JUCE_WINDOWS
    wchar_t* version = nullptr;
    const long hr = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    juce::String out;
    if (hr >= 0 && version != nullptr && version[0] != L'\0')
        out = juce::String(version);
    if (version != nullptr)
        CoTaskMemFree(version);
    return out;
#else
    return "0"; // macOS(WKWebView)/Linux(WebKitGTK)：系统 WebView 恒可用，非空即「在」
#endif
}

// [SL-421] 把「DefaultBackgroundColor 这一层在不在」变成一行可抓的诊断 —— JUCE 对
// QueryInterface(ICoreWebView2Controller2) 取不到是**静默跳过**（没有 else、没有日志、
// 不看 HRESULT），不打这行就分不出「设了没生效」和「压根没设」（判例：JUCE 吞掉 WebView2
// 的 HRESULT）。⚠ 行里必须自带「inferred / not directly observed」：它证的是运行时有没有
// 这个接口，**不是** JUCE 那次 QueryInterface 真成功了，更不是那一帧屏上真是这个颜色；
// 贴 DebugView 片段回来的人多半不会同时读头注，所以这句写在**行里**而不是只写在注释里。
// 文案一律 ASCII（运行期字面量走 printf 族拼接时，含非 ASCII 的相邻窄字面量触发 MSVC C4819）。
void SynchainBridgeWebEditor::logDefaultBackgroundSupport(const juce::String& runtimeVersion) const
{
    using Support = webview::DefaultBackgroundSupport;

    const auto utf8 = runtimeVersion.toStdString();
    const auto support = webview::defaultBackgroundSupport(utf8.empty() ? nullptr : utf8.c_str());
    const juce::String shown = runtimeVersion.isNotEmpty() ? runtimeVersion : juce::String("unknown");
    // ⚠ 走 juce::int64 重载，**别用 static_cast<int>**：中点色最高位是 1(0xff……)，转 int
    // 是超值域窄化(C++17 实现定义)，得靠两次实现定义转换才凑出 ffd9cadb。int64 逐字节同
    // 输出且与符号无关。同族问题 SCVB 刚在 #264 的 abiForJson 上修过（u32 超 INT_MAX 转 int）。
    const juce::String argb =
        juce::String::toHexString(static_cast<juce::int64>(webview::placeholderMidArgb())).paddedLeft('0', 8);
    const juce::String floor = juce::String(webview::kDefaultBackgroundMinRuntimeMajor);

    if (support == Support::available)
        logDiag("webview2 default background: available -- ICoreWebView2Controller2 inferred present (from runtime " +
                shown + " >= major " + floor + ", not directly observed), JUCE puts argb " + argb);
    else if (support == Support::unavailable)
        logDiag("webview2 default background: UNAVAILABLE -- ICoreWebView2Controller2 inferred absent (from runtime " +
                shown + " < major " + floor + ", not directly observed), JUCE drops argb " + argb + " silently");
    else if (runtimeVersion.isEmpty())
        // 当前调用点在 missing 分支之后，走不到这里 —— 但把它写对是给将来挪调用点的人：
        // 否则这条会打成 "version unknown not parsable"，把原因指错。
        logDiag("webview2 default background: unknown (no WebView2 runtime detected)");
    else
        logDiag("webview2 default background: unknown (runtime version " + shown + " not parsable)");
}

void SynchainBridgeWebEditor::showFallback(FallbackReason reason)
{
    if (mFallback != nullptr)
        return;
    // [SL-386] 面板自己铺满本组件，闸门不该再按住 WebView 的位置（否则 retry 回来时
    // bounds 还停在可视区外，而那条路上不一定再有导航事件把它推回来）；noteRevealed 在
    // 这里调：走到兜底的典型场景恰恰是首帧信号不会来，`webview revealed (fallback)` 这行
    // 只可能在此处打出来。missing 那条路闸门从未 parked ⇒ 该行不打（reason 留空）。
    mRevealGate.onFallbackShown();
    noteRevealed();
    mWebView->setVisible(false);
    const bool missing = (reason == FallbackReason::MissingRuntime);
    mFallback = std::make_unique<FallbackPanel>(
        mProcessor, missing,
        [] { juce::URL("https://go.microsoft.com/fwlink/p/?LinkId=2124703").launchInDefaultBrowser(); },
        [this] { retryWebView(); });
    addAndMakeVisible(*mFallback);
    // 兜底面板是固定像素布局（~388px 高），不随 uiScale 缩放。小缩放档位（如 33%）下窗口会过小、
    // 挤压/裁掉 Start/Stop/端口/状态等最小控制面，故切兜底时把窗口放大到至少基准设计尺寸以保证可用
    // （更大的缩放窗口保持不变）。retryWebView 成功回到 WebView 时再按 uiScale 恢复。
    if (getWidth() < kDesignW || getHeight() < kDesignH)
        setSize(juce::jmax(getWidth(), kDesignW), juce::jmax(getHeight(), kDesignH));
    resized();
}

void SynchainBridgeWebEditor::retryWebView()
{
    mFallback.reset();
    // 回到 WebView：恢复按 uiScale 的窗口尺寸（切兜底时可能已把窗口放大到基准尺寸）。
    {
        const float s = mProcessor.getUiScale();
        setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));
    }
    beginLoadAttempt(); // 重探运行时 + 重置看门狗与遮挡闸；若又是 missing 会就地再切兜底
    resized();
}

// [SL-386] 一次新的加载尝试（构造 / retry 共用）：重置看门狗与遮挡闸后重新 goToURL。
// 起算前提（WebViewEditor.h static_assert 的另一半）：看门狗 kWatchdogBudgetMs 与遮挡闸
// kRevealFallbackMs 都以**本次 beginLoadAttempt 落下的 mStartMs** 一侧为共同参照 —— 看门狗
// 直接从 mStartMs 起算，闸门 3s 从导航开始（≥ mStartMs）起算，故「导航开始不晚于 mStartMs+2s」
// 时闸门必然先到期；导航开始更晚（冷启动 >2s）时看门狗先到，形态是切兜底面板（不是白），
// 那是「兜底顶替」路，见 showFallback 处注释。本仓看门狗不分冷/热预算，无顺延复位缺口。
void SynchainBridgeWebEditor::beginLoadAttempt()
{
    mBridgeReady = false;
    mRevealGate.beginLoadAttempt(); // 重新武装：下一次导航开始时再挪一次
    mRevealLogged = false;
    mStartMs = juce::Time::getMillisecondCounter();

    const juce::String runtimeVersion = webView2RuntimeVersion(); // [SL-421] 空 = 没探到运行时
    if (runtimeVersion.isEmpty())
    {
        showFallback(FallbackReason::MissingRuntime); // 面板里会 setVisible(false)，不进看门狗
        return;
    }

#if JUCE_WINDOWS
    // [SL-421] 必须在 goToURL **之前**打：控制器一建好 JUCE 就 put 那个颜色，诊断行打在后面
    // 会让读表的人分不清先后。每次加载尝试各打一行（retry 也重探一次运行时）。
    // ⚠ **只在 Windows 打**（第 1 轮复审两家都点了）：非 Windows 上 webView2RuntimeVersion()
    // 回的是哨兵 "0"，走下来会打成 `UNAVAILABLE ... ICoreWebView2Controller2 inferred absent
    // ... JUCE drops argb ... silently` —— mac 上既没有 WebView2、也没有那个接口、更没有谁去
    // put 这个 argb，**三个分句全假**。这行的全部价值是给贴 log 回来的人读，在 mac 上它会把
    // 人指向一个不存在的缺口。⚠ 修法只能是给**调用点**加平台闸门：**不许改哨兵值** ——
    // 哨兵改成空串会让上面那个 isEmpty() 判成「运行时缺失」，直接切兜底面板。
    logDefaultBackgroundSupport(runtimeVersion);
#endif

    // 必须在任何 emit 之前完成首个 goToURL（前端脚本随后加载并注册监听）。
    mWebView->setVisible(true);
    mWebView->goToURL(WBC::getResourceProviderRoot());
    if (!isTimerRunning())
        startTimerHz(25);
}

// -----------------------------------------------------------------------------
// [SL-386] 开窗遮挡闸的动作面（message 线程）。判定全在 mRevealGate（纯逻辑、可单测），
// 这几个函数只负责把判定落到组件几何上并写诊断行；机理与理由只写在 WebViewRevealGate.h。
// -----------------------------------------------------------------------------
void SynchainBridgeWebEditor::onNavigationStarted(const juce::String& url)
{
    logDiag("navigation started: " + url);

#if JUCE_WINDOWS
    // 导航开始 = WebView2 控制器已建好 ⇒ 基类 paint 里的重试泵已是空调用，此刻才可以把
    // WebView 挪出可视区（挪走之后 JUCE 不再画它）。mac：路径保持现状，不挪窗、不铺占位
    // （闸门保持未武装，纯逻辑其余调用点照常记账）。
    mRevealGate.onNavigationStarted(juce::Time::getMillisecondCounter());
    applyRevealGate();
#endif
}

void SynchainBridgeWebEditor::onNavigationFinished(const juce::String& url)
{
    // [SL-376] **这一条不放行，只记账**：pageFinishedLoading 只说明文档下载完，不保证任何
    // 一帧已合成；记下的这一位只进 timeout 行诊断。这里也不调 applyRevealGate/noteRevealed
    // —— 本函数不改闸门状态，那两句无论闸门开着还是关着都是空调用。
    mRevealGate.onNavigationFinished();
    logDiag("navigation finished: " + url);
}

// [SL-433] 载荷从「整个不看」改成**只看一个诊断字段**：`paintDeltaMs` = 页面那一侧量到的
// `信号时刻 − first-paint 时刻`。它**只进日志，不参与任何放行判定** —— 判定仍全在 mRevealGate。
//
// 【为什么要它】用户机上的这个余量**从来没有被量过**：日志此前只记信号时刻与放行时刻，于是
// 「他那台上信号到底早于还是晚于首帧、差多少」只能靠推断。有了这一格，用户下次贴一份日志就能
// **直接读出来**，而不是继续拿「还白 / 不白」两个 bit 做判断。
//
// 【为什么送差值而不是 paint 的绝对时刻】页面的 `performance` 时间轴与这里的 `mStartMs`
// **不共享原点**，送绝对值过来无法与任何东西相减。
//
// 【`(no paint record)` 怎么读 —— 按字面读，别读成「走了兜底路」】它只说明**这一次的载荷里
// 没有这个字段**。页面在没有 paint 记录时不带它，所以「没有 paint 记录 ⇒ 打这一行」成立；
// **反过来不成立**：页面侧的去重落在 signal() 里，保险定时器的回调不再查 armed ⇒
// 「paint 已到、两层 rAF 还没跑完就到保险时限」这一路会**带着一个真实的差值**由保险发出。
// ⇒ 判「走的是不是保险路」要看 `after N ms` 的量级，不是看这个字段在不在。
// [SL-433 第 1 轮复审] 「字段在场、但读不出来」**不打这一行**，打 `(paint delta unreadable)`
// —— 它的含义是「真源没漂、载荷坏了」，与本行要查的地方不是一处（见下面 else if 分支）。
// 字段名的真源是 BridgeApi.h 的 timing::FirstFramePaintDeltaKey，web/index.html 逐字引用，
// 由 web-preview/reveal-first-frame.test.mjs 第 ② 格逐字对拍（理由见该常量的注释：
// 打错字母的失败形态与合法回落路在日志里同形）。
void SynchainBridgeWebEditor::handleFirstFrame(const juce::var& payload)
{
    // 日志文案一律 ASCII（printf 族拼接非 ASCII 字面量会触发 MSVC C4819），同 logDiag 的口径。
    juce::String paintNote(" (no paint record)");
    const auto delta = payload.getProperty(juce::Identifier(bridge::timing::FirstFramePaintDeltaKey), juce::var());
    // **非有限、或有限但超出目标类型值域**的 double 直接 static_cast 成 int 是 UB，所以先在
    // double 域夹，再由这里窄化。入口是真的：JSON 里造得出 ±Inf（`{"x": 1e400}` 经 strtod
    // 溢出成 HUGE_VAL）；我们自己的 web 侧发不出（JS 的 JSON.stringify(Infinity) 出 null），
    // 但这条载荷毕竟跨了 web → C++ 这道边界，本仓对同类边界的口径是「先校验再用」。
    const auto usable =
        delta.isInt() || delta.isInt64() || (delta.isDouble() && std::isfinite(static_cast<double>(delta)));
    if (usable)
    {
        // 夹到 ±60 s：这是「信号 − 首帧」的毫秒差值，再大也没有诊断意义，而夹完必然落在 int
        // 的可表示范围内 ⇒ 下面这次窄化不再触碰 UB。
        const auto n = static_cast<int>(juce::jlimit(-60000.0, 60000.0, static_cast<double>(delta)));
        paintNote = juce::String(" (signal-firstPaint ") + (n >= 0 ? "+" : "") + juce::String(n) + " ms)";
    }
    else if (!delta.isVoid())
    {
        // [SL-433 第 1 轮复审] **第三种形态要与前两种分开**:字段**在场、但读不出来**
        //(类型不对 / 非有限 double)。它与 `(no paint record)` 的含义完全不同 ——
        // 后者是「页面没带这个字段」(走了回落路 / 保险路,或者真源名字漂了),
        // 前者是「真源没漂、载荷坏了」,要查的地方不是一处。立这个常量的全部理由就是
        // 「别让几种成因在日志里同形」,那就不该自己再把第三种并进去。
        // ⚠ **这个三态划分还剩一个已知口子,本轮有意没收**(第 3/4 轮复审【建议】,转 **SL-438**):
        // `payload` **整个不是对象**(载荷是数组 / 字符串)或字段是 JSON `null` 时,getProperty
        // 的返回与「字段压根不在」不可分 ⇒ 仍落进上面那行 `(no paint record)`。纯诊断面、
        // 不影响任何判定,故不搭在收口推上 —— 但**要改这段的人得知道它在**。
        paintNote = " (paint delta unreadable)";
    }

    // 先记「信号到了」，再谈放行 —— 两件事分开数：信号可能在 3s 兜底或兜底面板之后才到，
    // 只看放行行会把「信号来晚了」误读成「信号没来」。真机/pluginval 验收数的就是这一行
    // 与 noteRevealed() 放行行的条数比（开 N 次窗应有 N 行 first-frame signal）。
    logDiag(juce::String("first-frame signal after ") +
            juce::String(static_cast<int>(juce::Time::getMillisecondCounter() - mStartMs)) + " ms" +
            (mRevealGate.parked() ? juce::String(" (still parked)") : juce::String(" (already revealed)")) + paintNote);
    // onFirstFrame 只武装不放行（tick ∧ kRevealSettleMs 一拍在 timerCallback 的 onTick 里结算）；
    // 传 nowMs 是因为毫秒下界要从信号到达那一刻起算。
    // 防御性保留，效果为零 —— 信号在 settling 期到达时 noteRevealed() 的 parked() 条件早退；
    // 信号在兜底/超时放行之后才到（onFirstFrame 的 !parked_ 分支）时 mRevealLogged 已置位。
    // applyRevealGate() 留着是为了保住「闸门状态一变就落地」只有一个出口这条不变式，
    // 代价是一次多余的 repaint()。
    mRevealGate.onFirstFrame(juce::Time::getMillisecondCounter());
    applyRevealGate();
    noteRevealed();
}

// 把闸门的判定落到组件几何上。**只经这一个函数改 mWebView 的 bounds**，别在各个触发点
// 各写一次 setBounds —— 那样闸门就有了第二个真源。
void SynchainBridgeWebEditor::applyRevealGate()
{
    if (mWebView == nullptr)
        return;
    resized();
    repaint(); // 挪走的那一刻要让占位底色立刻补上，别等下一次自然重绘
}

// 放行诊断行。reason 有三种：firstFrame = 正常路；timeout = 首帧信号没来、3s 兜底（**必须
// 当异常读**，自带 navFinished seen|not seen 分诊后缀）；fallback = 被兜底面板顶掉（不是
// 「放行」，数表时单列）。`after` 一律从 mStartMs（本次加载尝试起点）算，而闸门的 3s 从
// 导航开始算 —— 所以 timeout 行打出来是「3000 + 导航前耗时」，两个起点不同是有意的。
void SynchainBridgeWebEditor::noteRevealed()
{
    // lastRevealReason() 为空 = 这一轮从来没挪走过（例如运行时缺失直接切了兜底面板），
    // 那就没有「放行」这回事，别写一行原因是空串的诊断。
    if (mRevealLogged || mRevealGate.parked() || juce::String(mRevealGate.lastRevealReason()).isEmpty())
        return;
    mRevealLogged = true;
    const juce::String reason(mRevealGate.lastRevealReason());
    juce::String line = "webview revealed (" + reason + ") after " +
                        juce::String(static_cast<int>(juce::Time::getMillisecondCounter() - mStartMs)) + " ms";
    if (reason == "timeout")
        line << " -- no first-frame signal before the 3s deadline (navFinished "
             << (mRevealGate.navigationFinishedSeen() ? "seen" : "not seen") << ")";
    logDiag(line);
}

void SynchainBridgeWebEditor::logDiag(const juce::String& line) const
{
    // 既有日志通道：juce::Logger。pluginval 不设 Logger ⇒ writeToLog 落 OutputDebugString
    // （DebugView / DBWin 捕获可见），宿主设了 Logger 则进宿主日志 —— 诊断不能只活在
    // Debug 构建里。文案一律 ASCII（printf 族拼接非 ASCII 字面量会触发 MSVC C4819）。
    juce::Logger::writeToLog("SynchainBridge: " + line);
}

void SynchainBridgeWebEditor::resized()
{
    // [SL-386] WebView 的落点由遮挡闸决定：遮挡期间整块挪到可视区之外（尺寸不变），
    // 那块地方由下面的 paint()（宿主层）铺占位渐变。几何与理由见 WebViewRevealGate.h。
    // mac 上闸门从不 parked，恒走原位分支（行为与改动前一致）。
    if (mWebView != nullptr)
        mWebView->setBounds(mRevealGate.parked() ? parkedBounds(getLocalBounds()) : getLocalBounds());
    if (mFallback != nullptr)
        mFallback->setBounds(getLocalBounds());
}

// [SL-386] 宿主层的占位 paint —— **遮挡窗口内唯一会跑的一层**：BridgeWebView 被挪到
// x=2W、与本组件可视区零交集，JUCE 的 paintComponentAndChildren 按子组件 bounds 裁剪,
// 整个跳过它的 paint（bot 第 1 轮【重要】:没有这一层,屏上就是 wrapper 残留像素）。
// 未遮挡时它仍会整块 fill —— WebBrowserComponent 不是 JUCE 意义上的 opaque 组件,JUCE
// 不会把它的矩形从父层裁掉 —— 只是绘制结果被 WebView2 自己的 HWND 盖住;频次为一次开窗
// 2–3 次,可忽略。刻意**不加**「未遮挡就 return」的早退:放行路径本轮不动,别为省一次
// fill 引入新分支面。与 BridgeWebView::paint 共用 paintPlaceholderGradient(同一组色标
// 真源,不许各写一份)。mac:保持现状,不铺占位(Component::paint 默认空实现)。
void SynchainBridgeWebEditor::paint(juce::Graphics& g)
{
    juce::ignoreUnused(g);
#if JUCE_WINDOWS
    paintPlaceholderGradient(g, getWidth(), getHeight());
#endif
}

// -----------------------------------------------------------------------------
// WebView 装配
// -----------------------------------------------------------------------------
juce::WebBrowserComponent::Options SynchainBridgeWebEditor::makeOptions()
{
    WBC::Options options;

#if JUCE_WINDOWS
    // Windows：给 WebView2 一个可写的 user-data 目录，避免 DAW 安装目录只读导致初始化失败。
    WBC::Options::WinWebView2 wv2;
    wv2 = wv2.withUserDataFolder(
        juce::File::getSpecialLocation(juce::File::tempDirectory).getChildFile("SynchainBridgeWV2"));

    // [SL-421] WebView2 在**任何** web 内容之下铺的那一层（= put_DefaultBackgroundColor）。
    // 不设的话 JUCE 把默认构造的 juce::Colour = ARGB 0x00000000（**全透明**）原样 put 进去，
    // 于是从控制器建好到页面画出来为止，这一层什么都不挡，露的是窗口的白 —— 遮挡闸守不到
    // 它（park 落在 pageAboutToLoad，而控制器是在 Navigate **之前**就建好并上屏的），
    // <head> 内联底也守不到它（那一层管的是外链 css 未到那一段）。取值 = 占位渐变沿轴 50%
    // 的插值色（DefaultBackgroundColor 只收纯色，没有渐变形态），由 kPlaceholderStops 现算；
    // 理由与「这条只证到哪一步」见 WebViewRevealGate.h 的 placeholderMidArgb 头注一处。
    // ⚠ 这一句删掉编译照过、既有判据全绿（删除式对照格实测）—— 守它的是
    // web-preview/reveal-first-frame.test.mjs 的源钉格 **⑤**（④ 是入场动画那格，别记串），
    // 以及运行期 logDefaultBackgroundSupport() 那行诊断。
    wv2 = wv2.withBackgroundColour(juce::Colour(webview::placeholderMidArgb()));

    // 关键：Windows 上必须显式选 WebView2 后端。否则 getBackend()==defaultBackend，
    // JUCE 回退到旧 IE ActiveX 控件（Win32WebView），它不支持 resource provider /
    // native 集成，会把 https://juce.backend/ 当真实网址导航 → "无法打开此页"。
    // 编译宏 JUCE_USE_WIN_WEBVIEW2 / NEEDS_WEBVIEW2 只让 WebView2 代码路径存在 + 链接
    // loader，并不切换后端。参见 JUCE examples/Plugins/WebViewPluginDemo.h。
    // 仅在 Windows 上设 webview2 后端 / WinWebView2 选项：非 Windows（Mac WKWebView /
    // Linux WebKitGTK）走系统默认后端，强设 webview2 会让 WebBrowserComponent 无法初始化。
    options = options.withBackend(WBC::Options::Backend::webview2).withWinWebView2Options(wv2);
#endif

    return options.withNativeIntegrationEnabled()
        .withResourceProvider([this](const juce::String& url) { return provideResource(url); },
                              juce::URL(WBC::getResourceProviderRoot()).getOrigin())
        // 首帧同步 seed（window.__JUCE__.initialisationData 可直接读）
        .withInitialisationData(bridge::Init::Version, juce::var(juce::String(JucePlugin_VersionString)))
        .withInitialisationData(bridge::Init::Port, juce::var(mProcessor.getPort()))
        .withInitialisationData(bridge::Init::Volume, juce::var(mProcessor.getVolumePct()))
        .withInitialisationData(bridge::Init::Lang, juce::var(mProcessor.getLang()))
        // JS -> C++
        .withNativeFunction(juce::Identifier(bridge::Fn::RequestInitialState),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleRequestInitialState(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::ToggleRun),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleToggleRun(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::SetPort),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleSetPort(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::SetMasterGain),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleSetMasterGain(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::SetLang),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleSetLang(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::SetUiScale),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleSetUiScale(a, std::move(c));
                            })
        .withNativeFunction(juce::Identifier(bridge::Fn::CommitUiScale),
                            [this](const juce::Array<juce::var>& a, WBC::NativeFunctionCompletion c) {
                                handleCommitUiScale(a, std::move(c));
                            })
        // [SL-386] 时序面（非契约）：前端「首帧已绘」上行 —— 遮挡闸唯一的正常放行路。
        // 通道选择与「为何不进 Fn:: 契约名表」见 BridgeApi.h timing::FirstFrameSignal 处注释。
        // [SL-433] 载荷从「不看」改成**只看一个诊断字段**（timing::FirstFramePaintDeltaKey）：
        // 它只进日志、不参与放行判定，理由与读法见 handleFirstFrame 的注释。
        .withEventListener(juce::Identifier(bridge::timing::FirstFrameSignal),
                           [this](const juce::var& payload) { handleFirstFrame(payload); });
}

std::optional<juce::WebBrowserComponent::Resource>
SynchainBridgeWebEditor::provideResource(const juce::String& url) const
{
    // url 形如 "/" 或 "/index.html" 或 "/js/juce/index.js"（root-relative 路径）
    const auto path =
        (url == "/" || url.isEmpty()) ? juce::String("index.html") : url.fromFirstOccurrenceOf("/", false, false);
    const auto baseName = path.fromLastOccurrenceOf("/", false, false);

    // 用 BinaryData 的原始文件名匹配（避免手工复刻 JUCE 的符号名 mangling）
    for (int i = 0; i < BinaryData::namedResourceListSize; ++i)
    {
        if (juce::String(BinaryData::originalFilenames[i]) == baseName)
        {
            int size = 0;
            if (const char* data = BinaryData::getNamedResource(BinaryData::namedResourceList[i], size))
            {
                std::vector<std::byte> bytes(reinterpret_cast<const std::byte*>(data),
                                             reinterpret_cast<const std::byte*>(data) + size);
                const auto ext = baseName.fromLastOccurrenceOf(".", false, false);
                return WBC::Resource{std::move(bytes), juce::String(mimeForExtension(ext))};
            }
        }
    }
    return std::nullopt;
}

const char* SynchainBridgeWebEditor::mimeForExtension(const juce::String& ext)
{
    const auto e = ext.toLowerCase();
    if (e == "html" || e == "htm")
        return "text/html";
    if (e == "css")
        return "text/css";
    if (e == "js" || e == "mjs")
        return "text/javascript"; // ES module 必须是 JS MIME
    if (e == "json")
        return "application/json";
    if (e == "svg")
        return "image/svg+xml";
    if (e == "woff2")
        return "font/woff2";
    if (e == "woff")
        return "font/woff";
    if (e == "ttf")
        return "font/ttf";
    if (e == "png")
        return "image/png";
    return "application/octet-stream";
}

// -----------------------------------------------------------------------------
// 原生函数处理（message 线程）
// -----------------------------------------------------------------------------
void SynchainBridgeWebEditor::handleRequestInitialState(const juce::Array<juce::var>&,
                                                        WBC::NativeFunctionCompletion complete)
{
    mBridgeReady = true; // 前端确认就绪 -> 此后 timer 才允许 emit
    complete(buildSnapshot());
}

void SynchainBridgeWebEditor::handleToggleRun(const juce::Array<juce::var>& args,
                                              WBC::NativeFunctionCompletion complete)
{
    const bool shouldRun = args.size() > 0 && static_cast<bool>(args[0]);
    auto& server = mProcessor.getBridgeServer();
    auto* obj = new juce::DynamicObject();

    if (shouldRun)
    {
        const int bound = server.start(mProcessor.getPort()); // 尝试 port..port+9
        if (bound < 0)
        {
            obj->setProperty("running", false);
            obj->setProperty("port", mProcessor.getPort());
            obj->setProperty("error", "PORT_IN_USE");
        }
        else
        {
            obj->setProperty("running", true);
            obj->setProperty("port", bound);
        }
    }
    else
    {
        server.stop();
        obj->setProperty("running", false);
        obj->setProperty("port", mProcessor.getPort());
    }
    complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetPort(const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete)
{
    const int port = args.size() > 0 ? static_cast<int>(args[0]) : plugin::DefaultPort;
    const bool ok = port >= plugin::MinPort && port <= plugin::MaxPort;
    if (ok)
        mProcessor.setPort(port);

    auto* obj = new juce::DynamicObject();
    obj->setProperty("ok", ok);
    obj->setProperty("port", mProcessor.getPort());
    complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetMasterGain(const juce::Array<juce::var>& args,
                                                  WBC::NativeFunctionCompletion complete)
{
    const int pct = args.size() > 0 ? juce::jlimit(0, 200, static_cast<int>(args[0])) : 100;
    mProcessor.setVolumePct(pct);

    auto* obj = new juce::DynamicObject();
    obj->setProperty("ok", true);
    complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetLang(const juce::Array<juce::var>& args, WBC::NativeFunctionCompletion complete)
{
    const juce::String code = args.size() > 0 ? args[0].toString() : juce::String("zh");
    mProcessor.setLang(code);

    auto* obj = new juce::DynamicObject();
    obj->setProperty("ok", true);
    complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleSetUiScale(const juce::Array<juce::var>& args,
                                               WBC::NativeFunctionCompletion complete)
{
    const double f = args.size() > 0 ? static_cast<double>(args[0]) : 1.0;
    mProcessor.setUiScale(static_cast<float>(f)); // clamp 到 [MinUiScale, MaxUiScale]
    const float s = mProcessor.getUiScale();
    // 仅缩放编辑器窗口为 DESIGN×s（实时预览）；web 侧卡片用 (100/s)%+zoom:s 相对窗口自适应铺满（DPI 无关）。
    // 注意：这里**不**写全局默认——防呆确认「保持」时才经 commitUiScale 落盘，避免未确认的极端档位
    // 在用户 10s 内关窗（revert 定时器随 WebView 销毁而失效）时污染全局、导致新实例仍开大（v1.2.5 修）。
    setSize(juce::roundToInt(kDesignW * s), juce::roundToInt(kDesignH * s));

    auto* obj = new juce::DynamicObject();
    obj->setProperty("ok", true);
    obj->setProperty("scale", s);
    obj->setProperty("w", getWidth());
    obj->setProperty("h", getHeight());
    complete(juce::var(obj));
}

void SynchainBridgeWebEditor::handleCommitUiScale(const juce::Array<juce::var>& args,
                                                  WBC::NativeFunctionCompletion complete)
{
    juce::ignoreUnused(args);
    // 防呆确认「保持」后调用：把当前（已确认）uiScale 写入全局默认，新实例/新工程沿用。
    mProcessor.persistUiScaleAsDefault();
    auto* obj = new juce::DynamicObject();
    obj->setProperty("ok", true);
    obj->setProperty("scale", mProcessor.getUiScale());
    complete(juce::var(obj));
}

juce::var SynchainBridgeWebEditor::buildSnapshot() const
{
    auto& server = mProcessor.getBridgeServer();
    const bool running = server.isRunning();

    auto* obj = new juce::DynamicObject();
    obj->setProperty("running", running);
    obj->setProperty("clients", mProcessor.clientCount());
    obj->setProperty("port", running && server.getPort() > 0 ? server.getPort() : mProcessor.getPort());
    obj->setProperty("volume", mProcessor.getVolumePct());
    obj->setProperty("lang", mProcessor.getLang());
    obj->setProperty("uiScale", mProcessor.getUiScale());
    obj->setProperty("version", juce::String(JucePlugin_VersionString));
    obj->setProperty("sampleRate", mProcessor.currentSampleRate());
    obj->setProperty("channels", mProcessor.currentChannels());
    obj->setProperty("latencyMs", mProcessor.latencyMs());
    return juce::var(obj);
}

// -----------------------------------------------------------------------------
// 25Hz Timer（message 线程）：读 processor 原子量 -> 变化时 emit
// -----------------------------------------------------------------------------
void SynchainBridgeWebEditor::timerCallback()
{
    // [SL-386] 遮挡闸在这个 tick 上做两件事，都收在 mRevealGate.onTick 里：
    //   · 首帧信号已到时结算那一拍（tick 数 ∧ kRevealSettleMs 毫秒下界）——「信号 = 帧已提交」，
    //     提交到上屏还差一拍，所以放行落在这里而不是 handleFirstFrame 里；
    //   · 信号没来时到点强制放行（kRevealFallbackMs），绝不允许「永远挪在外面」——
    //     那会是一块彻底不动的占位板，比白闪坏得多。
    // 放行只可能发生在这个 tick 上（fallback 那条除外）；判定与几何的落点见 applyRevealGate。
    if (mRevealGate.parked())
    {
        mRevealGate.onTick(juce::Time::getMillisecondCounter());
        if (!mRevealGate.parked())
        {
            applyRevealGate();
            noteRevealed();
        }
    }

    // WebView2 看门狗：kWatchdogBudgetMs（5s，行为不变）。后端选对（withBackend webview2）后
    // 前端确实走 WebView2 加载，正常冷启动远快于此；超时即判定加载失败，切兜底面板
    // （可重试 / 重开窗口），文案不误报"运行时缺失"。比较走 uint32 差值再转 int32：
    // getMillisecondCounter 每 ~49 天回绕，直接比大小会在回绕点把「还没到点」算成「早就超时」。
    if (!mBridgeReady && mFallback == nullptr &&
        static_cast<juce::int32>(juce::Time::getMillisecondCounter() - mStartMs) > kWatchdogBudgetMs)
    {
        showFallback(FallbackReason::LoadTimeout);
        return;
    }
    if (!mBridgeReady)
        return;

    // --- 应用 web 下发的主控音量（v1.2.10 修 web→VST 不生效）---
    // onVolumeChange 在 WS 线程只存原子；此处是 message 线程，可安全 setVolumePct（setValueNotifyingHost
    // 须在 message 线程）。取代不可靠的 callAsync。应用后下方 volume 广播块会把新值回传网页（echo）。
    if (const int webVol = mProcessor.consumePendingWebVolume(); webVol >= 0)
        mProcessor.setVolumePct(webVol);

    auto& server = mProcessor.getBridgeServer();
    const bool running = server.isRunning();

    // --- meter（运行中 + 变化超阈值才发）---
    const float ldb = mProcessor.meterLdb();
    const float rdb = mProcessor.meterRdb();
    const float peak = mProcessor.meterPeak();
    if (running && (std::abs(ldb - mLastLdb) > 0.3f || std::abs(rdb - mLastRdb) > 0.3f))
    {
        auto* m = new juce::DynamicObject();
        m->setProperty("l", juce::Decibels::decibelsToGain(ldb));
        m->setProperty("r", juce::Decibels::decibelsToGain(rdb));
        m->setProperty("ldb", ldb);
        m->setProperty("rdb", rdb);
        m->setProperty("peak", peak);
        mWebView->emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::Meter), juce::var(m));
        mLastLdb = ldb;
        mLastRdb = rdb;
    }

    // --- state（变化时发）---
    const int clients = mProcessor.clientCount();
    if (running != mLastRunning || clients != mLastClients)
    {
        auto* s = new juce::DynamicObject();
        s->setProperty("running", running);
        s->setProperty("clients", clients);
        s->setProperty("port", running && server.getPort() > 0 ? server.getPort() : mProcessor.getPort());
        mWebView->emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::State), juce::var(s));
        mLastRunning = running;
        mLastClients = clients;
    }

    // --- audio info（变化时发）---
    const int sampleRate = mProcessor.currentSampleRate();
    const int channels = mProcessor.currentChannels();
    if (sampleRate != mLastSampleRate || channels != mLastChannels)
    {
        auto* a = new juce::DynamicObject();
        a->setProperty("sampleRate", sampleRate);
        a->setProperty("channels", channels);
        a->setProperty("latencyMs", mProcessor.latencyMs());
        mWebView->emitEventIfBrowserIsVisible(juce::Identifier(bridge::Event::Audio), juce::var(a));
        mLastSampleRate = sampleRate;
        mLastChannels = channels;
    }

    // --- volume（主控音量变化时广播给浏览器 WS 客户端 → VST↔网页音量条实时双向同步；桥 #2）---
    // 插件 UI（或宿主）改主控音量 → 这里广播 {type:"volume"}；网页仅更新音量条显示、不回送，避免回环。
    const int volume = mProcessor.getVolumePct();
    if (volume != mLastVolume)
    {
        if (running && clients > 0)
            server.sendVolume(volume);
        mLastVolume = volume;
    }
}

} // namespace synchain
