// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// =============================================================================
// Synchain Bridge — 显示器 DPI 查询与 WebView2 DPI 补偿系数（AAX-08）
// -----------------------------------------------------------------------------
// 用途、口径与已知限制写在 WebViewEditor.cpp 的 applyDpiCompensation 一处；这里只放两个
// 无 JUCE 依赖的小函数。Win32 调用收在 MonitorDpi.cpp，免得 <windows.h> 的宏进 WebViewEditor.cpp。
// =============================================================================

namespace synchain
{
namespace dpi
{

// 窗口所在显示器的有效 DPI 缩放（MDT_EFFECTIVE_DPI / 96，175% → 1.75）。查询期间把调用线程临时切到
// PER_MONITOR_AWARE_V2（System-aware 线程直接问只会拿到系统 DPI），返回前恢复。取不到（非 Windows /
// 系统缺 API / 句柄无效）回 0。只在 message 线程调用。
double effectiveMonitorScale(void* nativeWindowHandle);

// 补偿系数 comp = monitorScale / peerScale；任一输入不是正数（含 NaN），或 |comp - 1| < 0.01 时回 1（视为不补偿）。
// constexpr：边界用例由 MonitorDpi.cpp 的 static_assert 在每次编译时钉住。
constexpr double compensation(double monitorScale, double peerScale) noexcept
{
    if (!(monitorScale > 0.0) || !(peerScale > 0.0))
        return 1.0;
    const double comp = monitorScale / peerScale;
    return (comp - 1.0 < 0.01 && 1.0 - comp < 0.01) ? 1.0 : comp;
}

} // namespace dpi
} // namespace synchain
