// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "MonitorDpi.h"

#include <limits>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace synchain
{
namespace dpi
{

// compensation() 的边界在每次编译（两个平台、本地与 CI）时钉住。纯逻辑，但不另开 selftest：CI 跑哪些 selftest
// 是写死在 workflow 里的名单。
static_assert(compensation(1.75, 1.0) == 1.75, "System-aware host at 175%: compensate by 1.75");
static_assert(compensation(1.75, 1.75) == 1.0, "PMv2 host: peer ratio already equals monitor scale -> no compensation");
static_assert(compensation(1.005, 1.0) == 1.0 && compensation(0.995, 1.0) == 1.0, "1% dead band around 1");
static_assert(compensation(0.0, 1.0) == 1.0 && compensation(1.75, 0.0) == 1.0, "unknown scale -> no compensation");
static_assert(compensation(std::numeric_limits<double>::quiet_NaN(), 1.0) == 1.0, "NaN -> no compensation");

#if defined(_WIN32)
namespace
{

// 两个 API 都按名字动态取，不改链接：GetDpiForMonitor 在 Shcore.dll（Win 8.1+），SetThreadDpiAwarenessContext
// 在 user32（Win10 1607+）。缺哪个就退化（拿不到 DPI → 回 0 → 不补偿；切不了线程 → 照常查询）。
// 形参按二进制等价的类型声明（MONITOR_DPI_TYPE 是 int 大小的枚举，DPI_AWARENESS_CONTEXT 是句柄），
// 不依赖 SDK 头里按 WINVER 开关的那两个类型。
using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
using SetThreadDpiAwarenessContextFn = HANDLE(WINAPI*)(HANDLE);

constexpr int kMdtEffectiveDpi = 0; // MDT_EFFECTIVE_DPI

HANDLE perMonitorAwareV2Context() noexcept
{
    return reinterpret_cast<HANDLE>(static_cast<INT_PTR>(-4)); // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
}

GetDpiForMonitorFn getDpiForMonitorFn() noexcept
{
    // shcore 是系统 DLL：先看进程里是否已加载，没有再只从 System32 加载（不走 DLL 搜索路径）。
    // 句柄有意不释放 —— 进程生命周期内只取一次。
    static const GetDpiForMonitorFn fn = [] {
        HMODULE shcore = GetModuleHandleW(L"shcore.dll");
        if (shcore == nullptr)
            shcore = LoadLibraryExW(L"shcore.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        return shcore != nullptr ? reinterpret_cast<GetDpiForMonitorFn>(GetProcAddress(shcore, "GetDpiForMonitor"))
                                 : nullptr;
    }();
    return fn;
}

SetThreadDpiAwarenessContextFn setThreadDpiAwarenessContextFn() noexcept
{
    static const SetThreadDpiAwarenessContextFn fn = [] {
        const HMODULE user32 = GetModuleHandleW(L"user32.dll");
        return user32 != nullptr ? reinterpret_cast<SetThreadDpiAwarenessContextFn>(
                                       GetProcAddress(user32, "SetThreadDpiAwarenessContext"))
                                 : nullptr;
    }();
    return fn;
}

// 作用域内把调用线程切到 PER_MONITOR_AWARE_V2，析构时恢复原值（切换失败则什么也不做）。
class ScopedPerMonitorV2Thread
{
public:
    ScopedPerMonitorV2Thread() noexcept : mSet(setThreadDpiAwarenessContextFn())
    {
        if (mSet != nullptr)
            mPrevious = mSet(perMonitorAwareV2Context());
    }

    ~ScopedPerMonitorV2Thread()
    {
        if (mSet != nullptr && mPrevious != nullptr)
            mSet(mPrevious);
    }

    ScopedPerMonitorV2Thread(const ScopedPerMonitorV2Thread&) = delete;
    ScopedPerMonitorV2Thread& operator=(const ScopedPerMonitorV2Thread&) = delete;

private:
    SetThreadDpiAwarenessContextFn mSet = nullptr;
    HANDLE mPrevious = nullptr;
};

} // namespace

double effectiveMonitorScale(void* nativeWindowHandle)
{
    const auto getDpiForMonitor = getDpiForMonitorFn();
    const auto hwnd = static_cast<HWND>(nativeWindowHandle);
    if (getDpiForMonitor == nullptr || hwnd == nullptr || !IsWindow(hwnd))
        return 0.0;

    const ScopedPerMonitorV2Thread perMonitorV2;
    UINT dpiX = 0;
    UINT dpiY = 0;
    const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (monitor == nullptr || FAILED(getDpiForMonitor(monitor, kMdtEffectiveDpi, &dpiX, &dpiY)) || dpiX == 0)
        return 0.0;
    return static_cast<double>(dpiX) / 96.0;
}
#else
double effectiveMonitorScale(void*)
{
    return 0.0; // 只有 Windows 需要（mac 上 WKWebView 与 NSView 同用点坐标，不存在这层错位）
}
#endif

} // namespace dpi
} // namespace synchain
