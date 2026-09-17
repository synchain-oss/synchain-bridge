// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// src/WebViewRevealGate.h 的纯逻辑自测（[SL-386] 开窗遮挡闸）:只认首帧放行 / navFinished
// 只记账 / settle 双条件(tick 数 ∧ 32ms 毫秒下界,回绕安全)/ 3s 超时兜底 / 挪窗几何 /
// 占位渐变(CSS 同形)的 C++ 侧 golden;[SL-421] 起还含 WebView2 DefaultBackgroundColor
// 那一层的两件纯逻辑:占位渐变轴中点色 golden、与「这一层在不在」的版本判定三态。
// 只 include 那一个头 + 标准库,不链接 JUCE /
// ixwebsocket,故能脱离插件目标单独构建运行(cmake -DBRIDGE_BUILD_SELFTESTS=ON,随后由
// scripts/gates.ps1 的 gate 5b、ci.yml 两个平台 job 与 compliance workflow 执行)。
//
// 多数用例是**删除式**的:把对应行为改回去(例如让 onNavigationFinished 放行、让 onFirstFrame
// 直接放行、删掉毫秒下界、改回加法式比较),该格当场红 —— 用例头上各写一句改哪里会红。
// 接线那一半(谁在何时调 onNavigationStarted / onFirstFrame / onTick)编不进本文件,由
// WebViewEditor.cpp 的调用点、真机/pluginval 数表与 web-preview/reveal-first-frame.test.mjs
// 的源钉判据兜 —— 与 SCVB 同族,别把这几格读成「整条链都验过了」。

#include "WebViewRevealGate.h"
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

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

void checkEqInt(long long got, long long want, const char* what, int line)
{
    ++gChecks;
    if (got != want)
    {
        ++gFailures;
        std::printf("FAIL  line %d: %s (got %lld, want %lld)\n", line, what, got, want);
    }
}

void checkNear(double got, double want, const char* what, int line)
{
    ++gChecks;
    if (!(std::fabs(got - want) <= 1e-6))
    {
        ++gFailures;
        std::printf("FAIL  line %d: %s (got %.9f, want %.9f)\n", line, what, got, want);
    }
}

using synchain::webview::RevealGate;

bool reasonIs(const RevealGate& gate, const char* want)
{
    return std::strcmp(gate.lastRevealReason(), want) == 0;
}

} // namespace

int main()
{
    using synchain::webview::kRevealFallbackMs;
    using synchain::webview::kRevealSettleMs;
    using synchain::webview::kRevealSettleTicks;

    // ------------------------------------------------------------------
    // 常量关系(与 WebViewEditor.h 的 static_assert 同族的本文件可测半边)。
    // ------------------------------------------------------------------
    checkEqInt(kRevealSettleMs, 32, "kRevealSettleMs = 32(一个 60Hz 合成帧再加约一帧余量)", __LINE__);
    check(kRevealSettleMs > 0, "毫秒下界必须为正(只数 tick 的下界是 0)", __LINE__);
    check(kRevealSettleTicks >= 1, "settle 至少要再回一次消息循环", __LINE__);
    check(kRevealFallbackMs < 5000, "kRevealFallbackMs 必须早于看门狗 5s(常量关系;前提见 beginLoadAttempt)", __LINE__);

    // ------------------------------------------------------------------
    // [SL-370] 导航开始挪走;首帧信号(+那一拍)放行。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        check(!gate.parked(), "控制器建好之前必须留在原位:重试泵挂在 paint 上", __LINE__);

        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFirstFrame(1000);
        gate.onTick(1000 + kRevealSettleMs);
        check(!gate.parked(), "信号 + 一拍之后应放行", __LINE__);
        check(reasonIs(gate, "firstFrame"), "放行原因应为 firstFrame", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-376] **navFinished 不再是一条放行路**。
    // 删除式:把 onNavigationFinished() 改回 reveal("navFinished"),本格立刻红。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        check(!gate.navigationFinishedSeen(), "初始状态不该有 navFinished 记账", __LINE__);

        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onNavigationFinished();
        check(gate.parked(), "navFinished 只记账,不放行(← 放行路被拿掉的那一格)", __LINE__);
        check(gate.navigationFinishedSeen(), "但要记账:超时行诊断靠它分两种失败", __LINE__);
        check(reasonIs(gate, ""), "不应写下放行原因", __LINE__);

        // 之后一路 tick 到超时前一毫秒都还得按住 —— 「不放行」不能靠「还没 tick 过」蒙混。
        gate.onTick(1500);
        gate.onTick(1000 + static_cast<std::uint32_t>(kRevealFallbackMs) - 1);
        check(gate.parked(), "超时线之前必须一直按住", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-376] 信号到了还要再压一拍 —— **tick 数**那一半。
    // 删除式:让 onFirstFrame() 直接 reveal("firstFrame"),第一条 CHECK 立刻红。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFirstFrame(1000);
        check(gate.parked(), "信号到了,还没放(那一拍)", __LINE__);
        check(reasonIs(gate, ""), "不应写下放行原因", __LINE__);

        // 毫秒下界早已满足(每个 tick 都远在其后),所以这里量的纯粹是 tick 数那一半。
        for (int i = 0; i < kRevealSettleTicks; ++i)
        {
            check(gate.parked(), "settle 的 tick 数未满,必须按住", __LINE__);
            gate.onTick(1000 + static_cast<std::uint32_t>(kRevealSettleMs) + static_cast<std::uint32_t>(i));
        }
        check(!gate.parked(), "tick 数 ∧ 毫秒下界都满足后应放行", __LINE__);
        check(reasonIs(gate, "firstFrame"), "放行原因应为 firstFrame", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-376] 那一拍的**毫秒下界**那一半(#247 复审【重要】②)。
    // 删除式:把 onTick 里 msDone 条件删掉(只留 ticksDone),本格第一条 CHECK 立刻红。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFirstFrame(2000);

        // 紧跟着就来一个 tick(只差 1 ms):tick 数够了,毫秒下界还差得远 ⇒ **不许放**。
        gate.onTick(2001);
        check(gate.parked(), "信号后 1ms 的 tick 不许放行(下界为 0 的旧病)", __LINE__);
        check(reasonIs(gate, ""), "不应写下放行原因", __LINE__);

        // 下界前一毫秒仍然按住 —— 边界格:少了它,把判据写成 `> 0` 也照绿。
        gate.onTick(2000 + static_cast<std::uint32_t>(kRevealSettleMs) - 1);
        check(gate.parked(), "下界前一毫秒必须按住", __LINE__);

        // 到点才放。
        gate.onTick(2000 + static_cast<std::uint32_t>(kRevealSettleMs));
        check(!gate.parked(), "毫秒下界到点应放行", __LINE__);
        check(reasonIs(gate, "firstFrame"), "放行原因应为 firstFrame", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-376] 毫秒下界也要**回绕安全**(与超时判定同一手法)。
    // 删除式:把 msDone 改成加法式 nowMs >= settleAtMs_ + (uint32)kRevealSettleMs ——
    // settleAtMs_ + 32 溢出成极小值,「信号后 1ms 来 tick」那一格当场误放行 ⇒ 红。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        const std::uint32_t nearWrap = 0xfffffff8u; // 距回绕点 8 ms < kRevealSettleMs
        gate.beginLoadAttempt();
        gate.onNavigationStarted(nearWrap - 1000); // 离超时线还远,不会被 timeout 抢走
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFirstFrame(nearWrap);

        // 信号后 1 ms 就来一个 tick:真差值是 1,远不到下界 ⇒ **不许放**。
        gate.onTick(nearWrap + 1);
        check(gate.parked(), "回绕点附近 1ms 差值不许误放行", __LINE__);

        // 跨过回绕点之后仍要按同一个下界判(边界前一毫秒按住、到点才放)。
        gate.onTick(nearWrap + static_cast<std::uint32_t>(kRevealSettleMs) - 1);
        check(gate.parked(), "跨回绕后下界前一毫秒必须按住", __LINE__);
        gate.onTick(nearWrap + static_cast<std::uint32_t>(kRevealSettleMs));
        check(!gate.parked(), "跨回绕后下界到点应放行", __LINE__);
        check(reasonIs(gate, "firstFrame"), "放行原因应为 firstFrame", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-376] 信号踩在 3s 线上到达时,结算那一拍**必须先于**超时判定。
    // 否则数表里凭空多一次「信号缺席」,而真机验收数的就是这张表。
    // 删除式:把 onTick 里的 settling 分支挪到超时判定之后,本格 reason 变成 "timeout" 即红。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFirstFrame(1000 + static_cast<std::uint32_t>(kRevealFallbackMs) - 1); // 超时线前一瞬到达
        for (int i = 0; i < kRevealSettleTicks; ++i)
            // 已过超时线,且毫秒下界也已满足 —— 唯一还能决定 reason 的就是分支序。
            gate.onTick(1000 + static_cast<std::uint32_t>(kRevealFallbackMs) +
                        static_cast<std::uint32_t>(kRevealSettleMs) + static_cast<std::uint32_t>(i));

        check(!gate.parked(), "应放行", __LINE__);
        check(reasonIs(gate, "firstFrame"), "settle 分支先于超时判定:reason 必须是 firstFrame", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-370] 超时兜底:绝不允许「永远不放行」。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        // 上界前一毫秒仍然按住 —— 边界格:少了它,把判据写成 `> 0` 也照绿。
        gate.onTick(1000 + static_cast<std::uint32_t>(kRevealFallbackMs) - 1);
        check(gate.parked(), "超时线前一毫秒必须按住", __LINE__);

        gate.onTick(1000 + static_cast<std::uint32_t>(kRevealFallbackMs));
        check(!gate.parked(), "超时线到点必须放行(不允许永远挪在外面)", __LINE__);
        check(reasonIs(gate, "timeout"), "放行原因应为 timeout", __LINE__);
        check(!gate.navigationFinishedSeen(), "此格未发生导航完成,记账位应为假", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-370] 超时判定的回绕安全。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        const std::uint32_t nearWrap = 0xffffff00u;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(nearWrap);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onTick(nearWrap + static_cast<std::uint32_t>(kRevealFallbackMs) - 1);
        check(gate.parked(), "回绕点附近超时线前一毫秒必须按住", __LINE__);
        gate.onTick(nearWrap + static_cast<std::uint32_t>(kRevealFallbackMs));
        check(!gate.parked(), "回绕点附近超时线到点必须放行", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-370] 放行过就不再 re-park;只有新的加载尝试才重新武装。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        gate.onFirstFrame(1000);
        gate.onTick(1000 + static_cast<std::uint32_t>(kRevealSettleMs));
        check(!gate.parked(), "首帧路应已放行", __LINE__);

        gate.onNavigationStarted(2000);
        check(!gate.parked(), "页面自己再导航一次不许把画好的界面挪走", __LINE__);

        gate.beginLoadAttempt();
        gate.onNavigationStarted(3000);
        check(gate.parked(), "新的加载尝试(构造/retry)要重新武装", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-370] 信号先于导航回调到达:不能反过来把已画好的页面挪走(记账为已放行)。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onFirstFrame(900);
        gate.onNavigationStarted(1000);
        check(!gate.parked(), "先到的信号记为已放行,导航开始不许 re-park", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-370] 兜底面板顶替:面板铺满本组件,闸门必须放手。
    // ------------------------------------------------------------------
    {
        RevealGate gate;
        gate.beginLoadAttempt();
        gate.onNavigationStarted(1000);
        check(gate.parked(), "导航开始后应挪出可视区", __LINE__);

        gate.onFallbackShown();
        check(!gate.parked(), "切兜底面板时闸门必须放手(retry 回来 bounds 不能停在可视区外)", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-386] 挪窗几何:尺寸一字不改、整块挪出可视区、宽度 0 也挪得动。
    // 删除式:把 parkedRect 的平移删掉(原地返回),本格立刻红。
    // ------------------------------------------------------------------
    {
        using synchain::webview::parkedRect;
        const auto p = parkedRect(0, 0, 460, 560);
        checkEqInt(p.width, 460, "遮挡期间宽度不许改(视口不变,页面不 reflow)", __LINE__);
        checkEqInt(p.height, 560, "遮挡期间高度不许改", __LINE__);
        checkEqInt(p.x, 920, "应整块右移两个窗口宽(460×2)", __LINE__);
        checkEqInt(p.y, 0, "y 不变", __LINE__);
        // 真的挪出去了:与可视区零交集(横向)。
        check(p.x >= 460, "遮挡矩形必须完全在可视区右侧之外", __LINE__);

        const auto empty = parkedRect(0, 0, 0, 40);
        check(empty.x > 0, "宽度为 0(还没 setSize)时也必须挪得动,否则原地不动 = 遮挡失效", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-386] 占位渐变 golden(CSS linear-gradient(157deg) 的 C++ 侧几何)。
    // 断言口径:端点数值是**独立算好的字面量**(PowerShell 按 CSS 规范式另算一遍),
    // 不是用 placeholderGradientEndpoints 反推 —— 公式与实现一起写错时 roundtrip 仍会绿。
    // 460×560(设计盒)下的 golden:x0=94.178140555, y0=-39.976248903, x1=365.821859445,
    // y1=599.976248903。
    // ------------------------------------------------------------------
    {
        using synchain::webview::placeholderGradientEndpoints;
        const auto e = placeholderGradientEndpoints(460.0, 560.0);
        checkNear(e.x0, 94.178140555, "157deg@460x560 端点 x0", __LINE__);
        checkNear(e.y0, -39.976248903, "157deg@460x560 端点 y0", __LINE__);
        checkNear(e.x1, 365.821859445, "157deg@460x560 端点 x1", __LINE__);
        checkNear(e.y1, 599.976248903, "157deg@460x560 端点 y1", __LINE__);
        // 0% 端在 100% 端的左上(157deg 朝右下)。
        check(e.x0 < e.x1 && e.y0 < e.y1, "渐变方向应为左上 -> 右下(157deg)", __LINE__);
        // 退化尺寸不许产生 NaN。
        const auto d = placeholderGradientEndpoints(0.0, 0.0);
        check(std::isfinite(d.x0) && std::isfinite(d.y0) && std::isfinite(d.x1) && std::isfinite(d.y1),
              "退化尺寸(0x0)不许产生非有限值", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-386] 占位渐变色标 golden(与 web/styles.css --vb-card-surface 同值;三处同源的
    // C++ 侧半边,另两半由 web-preview/reveal-first-frame.test.mjs 钉)。
    // ------------------------------------------------------------------
    {
        using synchain::webview::kPlaceholderStops;
        struct GoldenStop
        {
            double pos;
            std::uint32_t argb;
        };
        static constexpr GoldenStop kGolden[] = {
            {0.0, 0xffb5acc9u}, // #b5acc9
            {0.32, 0xffccbfd5u}, // #ccbfd5
            {0.64, 0xffe3d2e0u}, // #e3d2e0
            {1.0, 0xfffde8edu}, // #fde8ed
        };
        constexpr int kGoldenN = static_cast<int>(sizeof(kGolden) / sizeof(kGolden[0]));
        const int n = synchain::webview::kPlaceholderStopCount;
        checkEqInt(n, kGoldenN, "占位渐变色标个数应与 golden 一致(4)", __LINE__);
        const int m = n < kGoldenN ? n : kGoldenN;
        for (int i = 0; i < m; ++i)
        {
            checkNear(kPlaceholderStops[i].position, kGolden[i].pos, "stop position", __LINE__);
            checkEqInt(static_cast<long long>(kPlaceholderStops[i].argb), static_cast<long long>(kGolden[i].argb),
                       "stop argb", __LINE__);
        }
        checkEqInt(static_cast<long long>(synchain::webview::kPlaceholderGradientDeg), 157ll, "占位渐变角度 = 157deg",
                   __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-421] 占位渐变轴中点色 golden —— WebView2 的 DefaultBackgroundColor 取的就是它
    // (那个属性只收纯色,没有渐变形态)。
    // 断言口径:0xffd9cadb 是**独立算好的字面量**,不是拿 placeholderMidArgb() 反推:
    //   0.5 落在 0.32 与 0.64 两个停靠点之间 ⇒ t = (0.5-0.32)/(0.64-0.32) = 0.5625;
    //   R 0xcc→0xe3: 204 + 0.5625*23 = 216.9375 → 217 = 0xd9
    //   G 0xbf→0xd2: 191 + 0.5625*19 = 201.6875 → 202 = 0xca
    //   B 0xd5→0xe0: 213 + 0.5625*11 = 219.1875 → 219 = 0xdb
    //   A 0xff→0xff: 恒 255                          = 0xff
    // 删除式:改 kPlaceholderStops 任一停靠点 / 把插值换成「取首色」/ 把四舍五入改成截断
    // (217→216 = 0xd8)/ 漏掉 alpha 通道,本格都当场红。
    // ⚠ 钉不住的那半:相邻停靠点写成同一 position 时的 fail-closed 分支、以及「解析不出段」
    // 那条兜路 —— kPlaceholderStops 是文件级常量,本文件注入不进去,那两条只靠头注与实现。
    // ------------------------------------------------------------------
    {
        using synchain::webview::kPlaceholderStops;
        using synchain::webview::placeholderMidArgb;
        const std::uint32_t mid = placeholderMidArgb();
        checkEqInt(static_cast<long long>(mid), static_cast<long long>(0xffd9cadbu),
                   "占位渐变轴中点色应等于独立算出的 0xffd9cadb", __LINE__);
        checkEqInt(static_cast<long long>((mid >> 24) & 0xffu), 0xffll,
                   "中点色必须全不透明(JUCE withBackgroundColour 只收全不透明或全透明)", __LINE__);
        // 它必须是**插值**出来的,不是某个停靠点本身 —— 把插值换成 fail-closed 取首色时这格红。
        for (int i = 0; i < synchain::webview::kPlaceholderStopCount; ++i)
            check(mid != kPlaceholderStops[i].argb, "中点色不许等于任何一个停靠点(那说明插值没跑)", __LINE__);
        // 明暗必须落在两侧停靠点之间(取 R 通道:本组色标沿轴单调变亮)。
        const std::uint32_t midR = (mid >> 16) & 0xffu;
        check(midR > ((kPlaceholderStops[1].argb >> 16) & 0xffu) && midR < ((kPlaceholderStops[2].argb >> 16) & 0xffu),
              "中点色应落在 32% 与 64% 两个停靠点之间", __LINE__);
    }

    // ------------------------------------------------------------------
    // [SL-421] 版本串 → 主版本号 / DefaultBackgroundColor 支持三态。
    // ⚠ 这两个纯函数只决定**诊断行的措辞**,不改任何行为 —— 别把本组读成「那一层真铺上了」。
    // 删除式:把 defaultBackgroundSupport 的 `>=` 改成 `>`(87 那格红)/ 把「解析不出」的
    // -1 改成猜一个默认值(nullptr、空串、"dev137" 三格红)/ 删掉首段非数字的拒收
    // ("137x.0" 那格红)。
    // ------------------------------------------------------------------
    {
        using synchain::webview::defaultBackgroundSupport;
        using synchain::webview::kDefaultBackgroundMinRuntimeMajor;
        using synchain::webview::majorVersionOf;
        using Support = synchain::webview::DefaultBackgroundSupport;

        checkEqInt(majorVersionOf("137.0.3296.83"), 137, "loader 常见形态:取首段", __LINE__);
        checkEqInt(majorVersionOf("137"), 137, "没有小数点时整串就是首段", __LINE__);
        checkEqInt(majorVersionOf("  137.0"), 137, "前导空白应被跳过", __LINE__);
        checkEqInt(majorVersionOf("137x.0"), -1, "首段混进非数字:不猜,回 -1", __LINE__);
        checkEqInt(majorVersionOf("dev 137.0"), -1, "首段不是数字:不猜,回 -1", __LINE__);
        checkEqInt(majorVersionOf(""), -1, "空串:回 -1", __LINE__);
        checkEqInt(majorVersionOf(nullptr), -1, "nullptr:回 -1(不许解引用)", __LINE__);

        checkEqInt(kDefaultBackgroundMinRuntimeMajor, 87, "ICoreWebView2Controller2 的运行时主版本下限 = 87", __LINE__);
        // 下限两侧各一格:写成 `>` 时上面那格红,写成 `>=` 少一档时下面那格红。
        check(defaultBackgroundSupport("87.0.1.1") == Support::available, "恰好等于下限:available(边界含等号)",
              __LINE__);
        check(defaultBackgroundSupport("86.0.1.1") == Support::unavailable, "低于下限一档:unavailable", __LINE__);
        check(defaultBackgroundSupport("137.0.3296.83") == Support::available, "现实中的运行时:available", __LINE__);
        check(defaultBackgroundSupport(nullptr) == Support::unknown, "没探到运行时:unknown(不猜)", __LINE__);
        check(defaultBackgroundSupport("") == Support::unknown, "空版本串:unknown", __LINE__);
        check(defaultBackgroundSupport("dev137") == Support::unknown, "解析不出:unknown,不许落到 unavailable",
              __LINE__);
    }

    std::printf("%d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
