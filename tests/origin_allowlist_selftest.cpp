// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

// src/OriginAllowlist.h 的纯函数自测：归一化 / 注入模式可用性 / 模式匹配 / 注入值拆分。
// 只 include 那一个头 + 标准库，不链接 JUCE / ixwebsocket，故能脱离插件目标单独构建运行
// （cmake -DBRIDGE_BUILD_SELFTESTS=ON，随后由 scripts/gates.ps1 的「origin selftest」gate 执行）。
//
// 覆盖不到的一层：isAllowedOrigin() 的业务语境（空 Origin 放行、拒字面量 "null"、非 https 早退、
// 本地回环与 synchain.cn/.ca 系精确域）。那部分依赖插件目标的编译环境，仍靠 DAW 侧手工验证。
//
// 域名一律用 example.* 虚构值：真实的额外来源按决策 U4 走构建期注入，不入库。

#include "OriginAllowlist.h"
#include <cstdio>
#include <string>
#include <vector>

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

void checkList(const std::vector<std::string>& got, const std::vector<std::string>& want, const char* what, int line)
{
    ++gChecks;
    if (got == want)
        return;
    ++gFailures;
    std::printf("FAIL  line %d: %s\n", line, what);
    std::printf("      got  [");
    for (const auto& v : got)
        std::printf(" '%s'", v.c_str());
    std::printf(" ]\n      want [");
    for (const auto& v : want)
        std::printf(" '%s'", v.c_str());
    std::printf(" ]\n");
}
} // namespace

#define CHECK(expr) check((expr), #expr, __LINE__)
#define CHECK_LIST(expr, ...) checkList((expr), __VA_ARGS__, #expr, __LINE__)

int main()
{
    using namespace synchain::origin;

    // ---- toLowerAscii：scheme / host 大小写归一 -----------------------------
    CHECK(toLowerAscii("EXAMPLE.APP") == "example.app");
    CHECK(toLowerAscii("MiXeD-Case.Example.App") == "mixed-case.example.app");
    CHECK(toLowerAscii("127.0.0.1") == "127.0.0.1"); // 非字母原样
    CHECK(toLowerAscii("") == "");

    // ---- normalizeHost：小写 + 剥 FQDN 尾点 --------------------------------
    CHECK(normalizeHost("SYNCHAIN.CN") == "synchain.cn");
    CHECK(normalizeHost("Example.App.") == "example.app");
    CHECK(normalizeHost("example.app...") == "example.app");
    CHECK(normalizeHost(".") == "."); // 退化输入不塌成空串

    // ---- isUsableHostPattern：拒绝无锚点 / 标点模式 -------------------------
    CHECK(!isUsableHostPattern(""));
    CHECK(!isUsableHostPattern("*"));
    CHECK(!isUsableHostPattern("*."));
    CHECK(!isUsableHostPattern("-*"));
    CHECK(!isUsableHostPattern("*-"));
    CHECK(!isUsableHostPattern("localhost")); // 没有点 = 没有域名锚点
    CHECK(!isUsableHostPattern("example.app.")); // 尾点模式永远匹配不上归一后的 host

    // ---- isUsableHostPattern：锚点必须 ≥2 段（本轮收紧的核心）---------------
    CHECK(!isUsableHostPattern("*.com")); // 否则放行任意 .com
    CHECK(!isUsableHostPattern("*.app")); // 同上
    CHECK(!isUsableHostPattern("*example.app")); // 否则放行 evilexample.app
    CHECK(!isUsableHostPattern("*-team.app")); // 锚点只剩一段 TLD
    CHECK(isUsableHostPattern("*-team.example.app"));

    // ---- isUsableHostPattern：`*` 必须落在最左 label 内 ---------------------
    CHECK(!isUsableHostPattern("preview.*.example.app"));
    CHECK(!isUsableHostPattern("example.*.app"));
    CHECK(!isUsableHostPattern("example.app-*"));

    // ---- isUsableHostPattern：至多一个 `*` ---------------------------------
    CHECK(!isUsableHostPattern("*.*.example.app"));
    CHECK(!isUsableHostPattern("**.example.app"));
    CHECK(!isUsableHostPattern("*.example.*"));

    // ---- isUsableHostPattern：TLD 必须是 ≥2 的纯字母 -----------------------
    CHECK(!isUsableHostPattern("*.example.a1")); // 含数字
    CHECK(!isUsableHostPattern("*.example.a")); // 太短
    CHECK(!isUsableHostPattern("*.192.168.0.1")); // IPv4 字面量不是域名锚点
    CHECK(!isUsableHostPattern("*.example.xn--p1ai")); // punycode / IDN TLD 不在支持范围内

    // ---- isUsableHostPattern：正例 -----------------------------------------
    CHECK(isUsableHostPattern("example.app"));
    CHECK(isUsableHostPattern("preview.example.app"));
    CHECK(isUsableHostPattern("a.b.example.app"));
    CHECK(isUsableHostPattern("*.example.app"));
    CHECK(isUsableHostPattern("example-git-*-team.example.app"));

    // ---- hostMatchesPattern：无 `*` 时精确相等 ------------------------------
    CHECK(hostMatchesPattern("example.app", "example.app"));
    CHECK(!hostMatchesPattern("evil.example.app", "example.app"));
    CHECK(!hostMatchesPattern("example.appx", "example.app"));
    CHECK(!hostMatchesPattern("example.app", "Example.App")); // 两侧都已归一后才比较

    // ---- hostMatchesPattern：通配段非空且不跨 label -------------------------
    CHECK(hostMatchesPattern("example-git-feat-x-team.example.app", "example-git-*-team.example.app"));
    CHECK(!hostMatchesPattern("example-git-a.evil.example.com-team.example.app", "example-git-*-team.example.app"));
    CHECK(!hostMatchesPattern("example-git--team.example.app", "example-git-*-team.example.app")); // 通配段为空
    CHECK(hostMatchesPattern("x.example.app", "*.example.app"));
    CHECK(!hostMatchesPattern("a.b.example.app", "*.example.app")); // 通配段跨 `.`
    CHECK(!hostMatchesPattern(".example.app", "*.example.app")); // 通配段为空
    CHECK(hostMatchesPattern(normalizeHost("X.Example.App."), "*.example.app")); // 归一后才命中

    // ---- parseHostPatterns：空段丢弃 + 归一 + fail-closed -------------------
    CHECK_LIST(parseHostPatterns(""), {});
    CHECK_LIST(parseHostPatterns("  ,, "), {});
    CHECK_LIST(parseHostPatterns(" *.EXAMPLE.APP , "), {"*.example.app"});
    CHECK_LIST(parseHostPatterns("*.com,*example.app,-*,*.,a.b,*.example.app"), {"*.example.app"});
    CHECK_LIST(parseHostPatterns("preview.example.app,*.example.app"),
               {"preview.example.app", "*.example.app"}); // 顺序保持

    std::printf("origin_allowlist_selftest: %d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
