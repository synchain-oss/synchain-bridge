// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// =============================================================================
// Synchain Bridge — 开窗遮挡闸(SL-386;纯逻辑,零依赖,不碰任何 JUCE 类型)
// =============================================================================
// 现状病:开窗序列里 WebView2 那几帧白不受我方任何一层底色控制 —— WebView2 的宿主 HWND
// 一旦上屏,它在合成首帧之前画什么,插件侧没有任何 API 管得到(JUCE 的 fallbackPaint 每帧
// 无条件 fillAll(Colours::white),控制器建好前的白由它画;DefaultBackgroundColor 只在
// 控制器建好之后才生效)。修法(移植自 SCVB 的 SL-370/376/378 方案,参考实现
// scvb @ feature/v1 76ffb04 src/plugin-common/WebViewRevealGate.h):**根本不让它上屏** ——
// 导航开始到「页面首帧已绘」之间,把 WebView 子窗口挪出宿主客户区之外,那块地方由**宿主**
// (SynchainBridgeWebEditor::paint)自绘占位底色(与页面成品可见底同形,见本文件下半段)。
// 占位共两层,各守一段、共用同一组色标(WebViewEditor.cpp 的 paintPlaceholderGradient):
//   • 宿主 paint —— 遮挡窗口内唯一会跑的一层(挪走的子组件与可视区零交集,JUCE 按 bounds
//     裁剪会整个跳过它的 paint;没有宿主这一层,屏上就是 wrapper 残留像素——bot 第 1 轮
//     【重要】的定谳);
//   • BridgeWebView::paint —— 未遮挡时子窗口自己的 fallbackPaint 白(导航开始前/放行之后)。
//
// 【为什么挪走而不是 setVisible(false) / 零尺寸】
//   • setVisible(false) 走 JUCE componentVisibilityChanged → checkWindowAssociation,
//     而 Options 里 keepPageLoadedWhenBrowserIsHidden 成员默认值就是 false ⇒
//     unloadPageWhenHidden 为真 ⇒ JUCE 会把页面 goToURL("about:blank") 顶掉 ——
//     隐藏一下就把正在加载的页面弄没了(读 juce_WebBrowserComponent 实现核过)。
//   • put_IsVisible(false):WebView2 文档说「不可见时停止渲染」;渲染停了之后 rAF 还
//     发不发没有实测条件,一旦不发就与「等 rAF 里的首帧信号」互相等死。挪 bounds 不用赌。
//   • 零尺寸把视口压成 0×0,页面按 0 宽布局、放回来时整页 reflow。
//   挪走则三条都不沾:尺寸不变、owner.isShowing() 不变、Chromium 仍认为自己可见。
//   ⚠ 已知风险(不是已排除项,#241 复审【重要】①):Chromium 对「可视矩形为空」的
//   widget 同样可能停 BeginFrame ⇒ rAF 停摆 ⇒ firstFrame 永不到达 ⇒ 每次开窗吃满 3s
//   超时兜底。命中形态是**静默降级**(屏上仍是「占位 → 内容」,不白不卡),且没有任何
//   一格静态判据会红 —— 验收硬指标是数表:**开 N 次窗就该有 N 行 first-frame signal**,
//   放行原因里出现 timeout 即命中(那一行自带 navFinished seen|not seen 帮分诊)。
//   [SL-433] 页面侧新增的保险定时器**不由 BeginFrame 驱动**(setTimeout 不是 rAF),到点直接
//   发信号 ⇒ 这一档下信号有机会在页内保险时限到达、放行原因仍是 firstFrame。但**别把它
//   读成「这条风险已排除」**:两边不共享时间原点(页内从脚本执行起算、这里从导航开始起算,
//   中间那一段读不出来),保险跑输时放行原因照样掉成 timeout。数表指标一个字不改。
//
// 【为什么等到导航开始才挪】JUCE 的 WebView2 控制器重试泵挂在基类 paint 的
// fallbackPaint 尾部(checkWindowAssociation),控制器建好之前挪走组件会让 JUCE 不再
// 画它 ⇒ 泵停。导航开始 = 控制器已建好(泵本就是空调用),此刻才挪,泵此前照常被驱动。
//
// 【只认首帧放行(SL-376)】pageFinishedLoading 只说明文档下载完、load 事件发了,
// 不保证任何一帧已合成 —— SCVB 的 pluginval 数表里它有 4/10 次抢在首帧信号前 3–6 ms
// 放行,放回来的正是「白一瞬」。⇒ navFinished **不再放行**,只记账(供超时行分诊);
// 放行只认 firstFrame,外加 timeout 兜底与 fallback 顶替。
//
// 【首帧信号什么时候发(SL-433 改判)】SL-386 当时写的是「前端 DOMContentLoaded 后嵌套两层
// rAF ⇒ 前一帧确已合成」—— **后半句是假的**:两层 rAF 只保证「又过了两个渲染时机」,
// **不保证页面已经画过任何一帧**。按 DCL 触发时信号时刻 ≈ DCL + 两个 rAF,与 first-paint
// 之间没有任何约束;信号早于 first-paint 时,这里收到信号就把窗口揭开,而 Chromium widget
// 一个像素都还没画,露的是它自己的 base background(白)—— 那就是用户在 1.5.2 上仍然看得见的
// 「第二段白」(白 → 背景色 → **白** → 正常 里中括号那一段)。
// ⚠ 与它**无关**的一层:[SL-421] 的 put_DefaultBackgroundColor(①-b)铺在 web 内容**之下**,
// 盖不住 widget 自己的 base background —— 这正是「1.5.2 加了 ①-b 用户照样看见白」的原因。
// ⇒ [SL-433] 起,前端武装的触发条件改成「**页面真的画过一帧**」:
// PerformanceObserver({type:"paint", buffered:true}) 收到 paint 记录之后,再走原来的两层 rAF。
// 页面侧另有一条回落路(没有 PerformanceObserver ⇒ 退回 DOMContentLoaded)与一条保险定时器
// (paint 记录迟迟不来时直接发信号、不绕 rAF);三条路各自的理由写在 web/index.html 那段脚本
// 里,判据在 web-preview/reveal-first-frame.test.mjs 第 ② 格。
// 代价:占位段多停一小段(SCVB 同一改法在真宿主上实测 +17~48 ms;Bridge 这一页本机没测出来 ——
// 换页面前后的差被跨构建跑间波动盖住了,容差大过被测量)。
//
// 【这条改法保证了什么、没保证什么 —— 按字面读】
//   · 保证:**放行不早于 first-paint**。paint 路上这是**构造性的**(武装挂在 paint 记录到达
//     之后,再过两层 rAF 才发信号),不是靠调时间调出来的。
//   · **不**保证「放行只会更晚、不会更早」。⚠ 那句话是错的,别再写(SL-433 第 1 轮复审订正):
//     旧锚点是 DOMContentLoaded、新锚点是 first-paint,而页面 <head> 的内联脚本排在渲染阻塞的
//     <link rel="stylesheet"> **之前**、主脚本又是 type="module"(要经资源提供器往返抓依赖)
//     ⇒ **first-paint 完全可能早于 DCL** ⇒ 新信号可以比改前**更早**发出。那正是本次要的
//     (旧锚点本来就没道理地偏晚),但与那句话的字面意思相反。
//   · **唯一没有上面那条下界保证的是保险路**:「有 PerformanceObserver、但它不报 paint 记录」
//     这一档,保险到点照常发信号 ⇒ 本卡要治的那段白**仍可能出现**,只是时限从这里的 3s
//     提前到页内的约 2.5s。这不是改法错(任何定时兜底都这样,它明显优于「永不放行」),
//     但钉不住的那半要明说钉不住。
//
// 【回滚判据(不是观察项)】日志里 `(no paint record)` 且 `after N ms` 的 **N ≈ 2500**
//   ⇒ parked 状态下 paint 记录根本没来、走的是页内保险路 ⇒ 新路对本仓是**纯倒退**
//   (每次开窗多等约 2.5s 占位)⇒ **回滚到 SL-386 的 DOMContentLoaded 触发**。
//   ⚠ **「调大保险时限」是错的应对** —— 那只会把「每次多等 2.5s」变成「每次多等更久」,
//   把倒退做得更深。
//   ⚠ 自陈:挪窗后 widget 与可视区零交集,所以新路等于**新引入一个依赖** ——「这种状态下
//   Chromium 必须照常记 paint 记录」。本机真 WebView2 宿主(pluginval)实测 8/8 有记录
//   (N ≈ 710~780 ms,不是保险路的 ≈2500),本机上成立;但那不是用户的 DAW,这条判据照留。
//
// 【为什么首帧信号到了还要再压一拍】paint 记录 + 两层 rAF 保证「帧已提交给合成器」,提交到
// 上屏还差一拍;信号一到就挪回来仍可能露底。onFirstFrame 只武装,放行落在 25Hz tick 上,
// **tick 数 ∧ 毫秒下界**两个条件缺一不可(#247 复审【重要】②:只数 tick 的下界是 0)。
// 32 ms = 一个 60Hz 合成帧(16.7 ms)再加约一帧余量;代价上界 ≈ 32 + 一个 25Hz tick ≈ 72 ms。
//
// 【SL-386 与 SCVB 的口径差】挪窗激活与占位铺色只在 Windows(#if JUCE_WINDOWS,调用点在
// WebViewEditor.cpp);mac 路径保持现状(WKWebView 不挪窗、不铺占位),纯逻辑闸本身
// 平台无关、两平台照常编译。看门狗:本仓维持既有 5s 固定预算(不移植 SCVB 的冷/热分段),
// kRevealFallbackMs < kWatchdogBudgetMs 由 WebViewEditor.h 的 static_assert 在每次编译上守;
// 预算同时起算的前提(都从 beginLoadAttempt 落 mStartMs 起算)在调用点注释里写明。
//
// 本类不进插件目标之外的任何东西:tests/reveal_gate_selftest.cpp 直接编译本头(零依赖),
// 接线那一半(谁在何时调 onNavigationStarted / onFirstFrame / onTick)在 WebViewEditor.cpp,
// 运行期够不着 —— 与 SCVB 同族,真机/pluginval 数表是那半边的判据。
// =============================================================================

#include <cmath>
#include <cstdint>

namespace synchain
{
namespace webview
{

// 首帧信号没来时的兜底上界。取 3s:必须早于看门狗(5s)切兜底面板,否则占位段会被面板
// 顶掉 —— 常量关系由 WebViewEditor.h 的 static_assert 在每次编译上守;「同时起算」的前提
// (看门狗从 beginLoadAttempt 落的 mStartMs 起算,闸门从导航开始算)见 WebViewEditor.cpp。
static constexpr int kRevealFallbackMs = 3000;

// 首帧信号到达后压住的两个条件,onTick 里必须同时满足才放行。
// 只数 tick 的下界是 0(信号到达点相对 tick 相位随机),所以必须有毫秒下界那一半。
static constexpr int kRevealSettleTicks = 1; // 至少再回一次消息循环
static constexpr int kRevealSettleMs = 32; // 一个 60Hz 合成帧(16.7 ms)再加约一帧余量

class RevealGate
{
public:
    // 一次新的加载尝试开始(构造 / retry 共用):重新武装,允许下一次导航再挪一次。
    void beginLoadAttempt() noexcept
    {
        parked_ = false;
        revealed_ = false;
        settling_ = false;
        settleTicksSeen_ = 0;
        settleAtMs_ = 0;
        navFinishedSeen_ = false;
        revealReason_ = "";
    }

    // 导航开始(WebView2 控制器已建好)。已经放行过就不再挪 —— 页面自己再导航一次时
    // 重新挪走比那点白更难看。
    void onNavigationStarted(std::uint32_t nowMs) noexcept
    {
        if (revealed_ || parked_)
            return;
        parked_ = true;
        parkedAtMs_ = nowMs;
    }

    // 前端「首帧已绘」信号(timing::FirstFrameSignal)。**这里不放行**,只武装 ——
    // 真正放行在后面的 onTick 上(tick 数 ∧ 毫秒下界)。还没挪走时也要记账:记成已放行,
    // 后面那次 onNavigationStarted 就不会再把已经画好的页面挪走。
    // 取 nowMs 是为了毫秒下界从**信号到达那一刻**起算 —— 从「下一个 tick」起算等于把要量的
    // 那段时间自己抹掉(#247 复审【重要】② 的落地细节)。
    void onFirstFrame(std::uint32_t nowMs) noexcept
    {
        if (!parked_)
        {
            revealed_ = true;
            return;
        }
        if (!settling_)
        {
            settling_ = true;
            settleTicksSeen_ = 0;
            settleAtMs_ = nowMs;
        }
    }

    // JUCE 的 pageFinishedLoading。**不放行,只记账**(理由见文件头【只认首帧放行】);
    // 记下的这一位只进 noteRevealed() 的 timeout 行,帮着分「页面 load 完了但信号没发」
    // 与「导航压根没走完」。
    void onNavigationFinished() noexcept { navFinishedSeen_ = true; }

    // 25Hz tick:先结算首帧信号的那一拍,再看超时兜底(settle 分支**必须先于**超时判定,
    // 否则信号踩着 3s 线到达时会被记成 timeout,数表里凭空多一次「信号缺席」)。
    // 差值走 uint32 → int32:getMillisecondCounter 每 ~49 天回绕,直接比大小会在回绕点
    // 把「刚挪走」算成「早该放行」(或反过来永不放行)。
    void onTick(std::uint32_t nowMs) noexcept
    {
        if (!parked_)
            return;
        if (settling_)
        {
            const bool ticksDone = (++settleTicksSeen_ >= kRevealSettleTicks);
            const bool msDone = (static_cast<std::int32_t>(nowMs - settleAtMs_) >= kRevealSettleMs);
            if (ticksDone && msDone)
                reveal("firstFrame");
            return;
        }
        if (static_cast<std::int32_t>(nowMs - parkedAtMs_) >= kRevealFallbackMs)
            reveal("timeout");
    }

    // 切兜底面板:面板自己铺满本组件,闸门不该再按住 WebView 的位置(否则 retry 回来时
    // bounds 还停在可视区外)。
    void onFallbackShown() noexcept { reveal("fallback"); }

    bool parked() const noexcept { return parked_; }

    // 最近一次放行的原因(诊断行用;从未放行过是空串)。reason ∈ firstFrame / timeout /
    // fallback(fallback 不是「放行」,是被兜底面板顶掉,数表时单列)。
    const char* lastRevealReason() const noexcept { return revealReason_; }

    // pageFinishedLoading 到过没有。与放行无关,只进 timeout 那一行诊断。
    bool navigationFinishedSeen() const noexcept { return navFinishedSeen_; }

private:
    void reveal(const char* why) noexcept
    {
        revealed_ = true;
        settling_ = false;
        if (!parked_)
            return;
        parked_ = false;
        revealReason_ = why;
    }

    bool parked_ = false;
    bool revealed_ = false;
    bool settling_ = false; // 首帧信号已到、正在压那一拍
    bool navFinishedSeen_ = false;
    int settleTicksSeen_ = 0;
    std::uint32_t settleAtMs_ = 0; // 首帧信号到达的时刻(毫秒下界的起点)
    std::uint32_t parkedAtMs_ = 0;
    const char* revealReason_ = "";
};

// -----------------------------------------------------------------------------
// [SL-386] 占位底 —— 成品可见底的 C++ 侧真源。
//
// 成品可见底 = web/index.html 玻璃拟态卡片背景,token 化为 web/styles.css 的
// `--vb-card-surface`:linear-gradient(157deg, #b5acc9 0%, #ccbfd5 32%, #e3d2e0 64%,
// #fde8ed 100%)。占位与它**同形**(同一渐变,不是单一中点色 —— 渐变画得出深浅,
// 占位切内容才不跳阶),三处同源:
//   ① 本文件 kPlaceholderStops / kPlaceholderGradientDeg(C++ 占位色标);
//   ② web/styles.css 的 --vb-card-surface(css token,卡片背景消费它);
//   ③ web/index.html <head> 内联的 html 底(外链 css 未到时的第一层底)。
// 三处相等由 web-preview/reveal-first-frame.test.mjs 钉死(删除式:改任一处即红)。
// [SL-421] 还有第 ④ 个消费者,但它**不是第四份拷贝**:WebView2 的 DefaultBackgroundColor
// 只收纯色,取值由下面的 placeholderMidArgb() 从 ① 现算,没有独立字面量可漂。
// -----------------------------------------------------------------------------

struct PlaceholderStop
{
    double position; // 0..1,同 CSS 渐变线上的百分比
    std::uint32_t argb; // 0xAARRGGBB,全不透明
};

inline constexpr PlaceholderStop kPlaceholderStops[] = {
    {0.0, 0xffb5acc9u}, // #b5acc9
    {0.32, 0xffccbfd5u}, // #ccbfd5
    {0.64, 0xffe3d2e0u}, // #e3d2e0
    {1.0, 0xfffde8edu}, // #fde8ed
};

inline constexpr int kPlaceholderStopCount = static_cast<int>(sizeof(kPlaceholderStops) / sizeof(kPlaceholderStops[0]));

inline constexpr double kPlaceholderGradientDeg = 157.0; // 同 --vb-card-surface 的角度

// -----------------------------------------------------------------------------
// [SL-421] 占位渐变沿轴 50% 的插值色 —— 第 ④ 个消费者,给 WebView2 的
// `DefaultBackgroundColor`(makeOptions 里的 withBackgroundColour)。
//
// 【为什么要有这一层】它是 WebView2 在**任何** web 内容之下铺的那一层,管的是
// 「控制器已建好、文档还没画出来」这一段(SCVB 白闪分层图里的 ①-b;遮挡闸守的是 ①-a
// 的 fallbackPaint、<head> 内联底守的是 ①-c 的外链 css 未到)。**不设它**的话 JUCE 会把
// 默认构造的 juce::Colour = ARGB 0x00000000(全透明)原样 put 进 put_DefaultBackgroundColor
// —— 这一层什么都不挡,露的是窗口的白。移植自 SCVB
// src/plugin-common/PlatformWebView.cpp 的 withBackgroundColour(shellBackdropMid())。
//
// 【为什么是中点色而不是渐变】WebView2 的 DefaultBackgroundColor **只收纯色**,没有渐变
// 形态。取占位渐变轴上 50% 的插值色,与渐变占位相邻处不跳阶。真源仍是上面那一组
// kPlaceholderStops —— 这里算出来,不另写一个字面量。
//
// 相邻停靠点写成同一 position(CSS 里合法的硬边界写法)时 b-a == 0 ⇒ t 为 inf/NaN,
// 故命中条件带 `b.position > a.position`;解析不出段时 fail-closed 取首色,不算 NaN。
// alpha 通道同样插值:四个停靠点全不透明 ⇒ 结果恒 0xff,顺带守住「全不透明」这个前提
// (JUCE 的 withBackgroundColour 只接受全不透明或全透明)。
// -----------------------------------------------------------------------------
inline std::uint32_t placeholderMidArgb() noexcept
{
    for (int i = 0; i + 1 < kPlaceholderStopCount; ++i)
    {
        const PlaceholderStop& a = kPlaceholderStops[i];
        const PlaceholderStop& b = kPlaceholderStops[i + 1];
        if (a.position <= 0.5 && 0.5 <= b.position && b.position > a.position)
        {
            const double t = (0.5 - a.position) / (b.position - a.position);
            std::uint32_t out = 0;
            for (int shift = 0; shift <= 24; shift += 8)
            {
                const double va = static_cast<double>((a.argb >> shift) & 0xffu);
                const double vb = static_cast<double>((b.argb >> shift) & 0xffu);
                const double mix = std::floor(va + t * (vb - va) + 0.5); // 四舍五入(值域恒非负)
                out |= static_cast<std::uint32_t>(mix) << shift;
            }
            return out;
        }
    }
    return kPlaceholderStops[0].argb; // 解析不出段时 fail-closed 取首色
}

// -----------------------------------------------------------------------------
// [SL-421] `DefaultBackgroundColor` 这一层到底在不在(移植自 SCVB
// src/plugin-common/PlatformWebView.h 的 BackgroundColourSupport)。
//
// 【为什么需要判】上面那句 withBackgroundColour 最终落到 JUCE 的
// `WebView2::setWebViewPreferences`:它先 `QueryInterface(ICoreWebView2Controller2)`,
// **取不到就静默跳过** put_DefaultBackgroundColor —— 那个 `if (controller2 != nullptr)`
// 没有 else、没有日志、HRESULT 也不看。于是「我方到底铺没铺上这一层」在真机上完全
// 不可观测。本函数把它变成 WebViewEditor 里一行可抓的诊断。
//
// 【它证到哪一步 —— 别读过头】判的是**运行时有没有这个接口**,不是「JUCE 那次
// QueryInterface 真的成功了」,更不是「那一帧屏上真是这个颜色」。接口在场是
// QueryInterface 成功的**必要条件**,反向不成立。
//
// 纯函数,只吃版本串,便于离线单测(真 loader 与真 WebView2 都够不着)。
// -----------------------------------------------------------------------------

// ICoreWebView2Controller2(即 DefaultBackgroundColor)的运行时主版本下限。
// ⚠ **这个数字是本条判定里唯一没有机检、也无法离线核实的一环**:它来自该接口首发的
// WebView2 SDK 1.0.774.44 所对应的 Edge 通道(87),仓里没有任何东西能把这条映射钉住。
// 判错只影响诊断行的措辞,不改变任何行为(Evergreen Runtime 会自动升级,现实中不存在
// 停在这一档的机器)。
inline constexpr int kDefaultBackgroundMinRuntimeMajor = 87;

// 版本串 → 主版本号;解析不出返回 -1。loader 可能返回 "137.0.3296.83",也可能带通道后缀
// 写成 "137.0.3296.83 dev",只取首段数字;首段含任何非数字字符即判解析不出(**不猜**)。
//
// ⚠ 首段位数有上界 kMaxMajorDigits:超过就**拒绝**,既不截断也不继续乘。
// 理由不是「现实中会发生」(WebView2 的 loader 给不出 10 位以上的主版本),而是**与本函数
// 自己的既定口径一致** —— 它对一切解析不出的输入都回 -1「不猜」,那就不该在一个它同样
// 判不了的输入上悄悄算出个数来。没有上界时 `value * 10 + …` 对 11 位以上首段是**有符号
// 溢出 = UB**;而这是个取外部字符串的 noexcept 纯函数,UB 留着迟早被人当成「已验证过的
// 输入路径」。9 位足够容下任何真实主版本(现值 152)还有五个数量级余量。
inline constexpr int kMaxMajorDigits = 9;

inline int majorVersionOf(const char* version) noexcept
{
    if (version == nullptr)
        return -1;
    const char* p = version;
    while (*p == ' ' || *p == '\t')
        ++p;
    int value = 0;
    int digits = 0;
    for (; *p != '\0' && *p != '.'; ++p)
    {
        if (*p < '0' || *p > '9')
            return -1; // 首段混进非数字:不猜
        if (digits >= kMaxMajorDigits)
            return -1; // 首段过长:同样不猜(挡在 int 溢出之前)
        value = value * 10 + (*p - '0');
        ++digits;
    }
    return digits > 0 ? value : -1;
}

enum class DefaultBackgroundSupport
{
    available, // 运行时够新 ⇒ ICoreWebView2Controller2 在 ⇒ JUCE 那句不会静默跳过
    unavailable, // 运行时太旧 ⇒ 接口不在 ⇒ 这一层整层缺席,控制器建好到首帧之间露的是白
    unknown // 没探到运行时 / 版本串解析不出 ⇒ 不猜,如实说不知道
};

// version == nullptr / 空串 = 没探到运行时;首段解析不出同样归 unknown。
inline DefaultBackgroundSupport defaultBackgroundSupport(const char* version) noexcept
{
    const int major = majorVersionOf(version);
    if (major < 0)
        return DefaultBackgroundSupport::unknown;
    return major >= kDefaultBackgroundMinRuntimeMajor ? DefaultBackgroundSupport::available
                                                      : DefaultBackgroundSupport::unavailable;
}

struct PlaceholderGradientEndpoints
{
    double x0, y0, x1, y1; // 渐变线两端(组件本地坐标,y 向下)
};

// 遮挡期间 WebView 子窗口该占的矩形（纯整数版，selftest 可钉）：**尺寸一字不改**
// （页面不 reflow、Chromium 仍按真实视口出帧，rAF 照跑），整块平移到可视区右侧一个
// 窗口宽之外。WebViewEditor.cpp 的 juce::Rectangle<int> 入口经它实现 —— 几何只有这一处真源。
// 宽度为 0（还没 setSize）时退一步用 1，保证平移量恒为正、不会原地不动（遮挡完全失效）。
struct ParkedRect
{
    int x, y, width, height;
};

inline ParkedRect parkedRect(int x, int y, int width, int height) noexcept
{
    const int step = width > 0 ? width : 1;
    return {x + step * 2, y, width, height};
}

// CSS linear-gradient(θ) 几何(屏幕坐标,y 向下):
//   方向向量 d = (sinθ, −cosθ)(θ=0 即「to top」= (0,−1),顺时针转);
//   渐变线过盒中心,长 L = |W·sinθ| + |H·cosθ|(CSS 规范公式);
//   0% 落在 p0 = 中心 − (L/2)·d,100% 落在 p1 = 中心 + (L/2)·d。
// 460×560 的 golden 值在 tests/reveal_gate_selftest.cpp 里以独立算好的字面量钉死。
inline PlaceholderGradientEndpoints placeholderGradientEndpoints(double w, double h) noexcept
{
    if (w < 1.0)
        w = 1.0; // 退化尺寸(尚未布局)时不产生零长度渐变
    if (h < 1.0)
        h = 1.0;
    constexpr double kPi = 3.14159265358979323846;
    const double rad = kPlaceholderGradientDeg * kPi / 180.0;
    const double dx = std::sin(rad);
    const double dy = -std::cos(rad);
    const double len = std::fabs(w * dx) + std::fabs(h * dy);
    const double cx = w / 2.0;
    const double cy = h / 2.0;
    const double hx = dx * len / 2.0;
    const double hy = dy * len / 2.0;
    return {cx - hx, cy - hy, cx + hx, cy + hy};
}

} // namespace webview

} // namespace synchain
