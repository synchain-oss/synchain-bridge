// Copyright (c) 2026 Synchain
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// Origin 白名单的**纯字符串逻辑**：归一化 + 注入模式可用性 + 模式匹配。
// 只依赖标准库（无 JUCE / ixwebsocket / 任何第三方），故能被
// tests/origin_allowlist_selftest.cpp 单独编译成一个不链接任何依赖的自测可执行文件
// （见 CMakeLists.txt 的 BRIDGE_BUILD_SELFTESTS 选项）。
// 业务语境的白名单——本地回环、synchain.cn/.ca 系精确域、非 https 远程早退、空 Origin 放行、
// 拒 `null` 字面量——留在 src/VstBridgeServer.cpp 的 isAllowedOrigin()，本头不涉及。

#include <cctype> // std::tolower / std::isspace / std::isalpha
#include <cstddef>
#include <string>
#include <vector>

namespace synchain::origin
{

// scheme / host 归一化：两者大小写不敏感，统一转小写防 SYNCHAIN.CN 之类绕过。
inline std::string toLowerAscii(std::string v)
{
    for (auto& c : v)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return v;
}

// host 归一化：小写 + 剥掉 FQDN 尾点。浏览器对 `https://synchain.cn.` 会原样发出带尾点的
// Origin，剥掉后与白名单同形比较 —— 既让合法域的尾点写法不被误拒，也堵掉「尾点形式撞上
// 某条宽模式」的绕过面。全是点的退化 host 保留最后一个字符，不返回空串。
inline std::string normalizeHost(std::string host)
{
    host = toLowerAscii(std::move(host));
    while (host.size() > 1 && host.back() == '.')
        host.pop_back();
    return host;
}

// 注入模式的可用性检查（fail-closed）。「非空 + 至多一个 `*`」远远不够：
//   - 字面量全是标点的模式等效于开门 —— `*.` 的前缀空、后缀 `.`，任何以 `.` 结尾的 host 都
//     命中；`-*` / `*-` 只需 host 以 `-` 开头 / 结尾。
//   - 只查「末段是纯字母 TLD」同样不够 —— `*.com` 会放行**任意** .com 域，`*example.app`
//     会放行 `evilexample.app`：`*` 吃掉整个最左 label 的前缀后，锚点只剩一段 TLD。
// 故对**含 `*` 的模式**追加两条：`*` 必须落在最左 label 内（位置在第一个 `.` 之前），且第一个
// `.` 之后的锚点**自身仍含 `.`**（≥2 段，如 example.app）。无 `*` 的精确 host 模式不受这两条约束。
// 所有模式共同要求：非空、至多一个 `*`、不以 `.` 结尾（host 归一化会剥尾点，带尾点的模式永远
// 匹配不上）、去掉 `*` 后的字面量含 `.` 且最后一个 `.` 之后是长度 ≥2 的纯字母 TLD。
// 【拒绝】形态举例（域名均为虚构示例）：`*`、`*.`、`-*`、`*-`、`localhost`、`*.com`、
//   `*example.app`、`preview.*.example.app`、`*.*.example.app`、`example.app.`、`*.example.a1`、
//   `*.example.xn--p1ai`（punycode / IDN TLD 不在支持范围内）。
// 【通过】形态举例：`preview.example.app`、`*.example.app`、`example-git-*-team.example.app`。
inline bool isUsableHostPattern(const std::string& pattern)
{
    if (pattern.empty() || pattern.back() == '.')
        return false;

    const auto star = pattern.find('*');
    if (star != pattern.rfind('*'))
        return false; // 多于一个通配段：不在约定内

    if (star != std::string::npos)
    {
        const auto firstDot = pattern.find('.');
        if (firstDot == std::string::npos || star > firstDot)
            return false; // `*` 必须落在最左 label 内
        if (pattern.find('.', firstDot + 1) == std::string::npos)
            return false; // 锚点只剩一段（`*.com` / `*example.app`）= 放行整个 TLD
    }

    std::string literal;
    for (const char c : pattern)
        if (c != '*')
            literal.push_back(c);

    const auto dot = literal.rfind('.');
    if (dot == std::string::npos)
        return false; // 没有点 = 没有域名锚点

    if (literal.size() - dot - 1 < 2)
        return false; // TLD 至少两个字符
    for (std::size_t i = dot + 1; i < literal.size(); ++i)
        if (std::isalpha(static_cast<unsigned char>(literal[i])) == 0)
            return false; // TLD 段必须是纯字母
    return true;
}

// 单个模式与（已归一化的）host 匹配：无 `*` 时精确相等；含一个 `*` 时拆成前缀 + 后缀，
// 要求 host 长于「前缀+后缀」之和（即通配段非空、前后缀不重叠）后再分别夹逼。
// `*` 只匹配**单个 DNS label**：通配区内不得含 `.`。否则 `a-*-b.example.app` 会把
// `a-x.evil.example.com-b.example.app` 之类的三方子域一并放行，而文档写的是「通配段」。
inline bool hostMatchesPattern(const std::string& host, const std::string& pattern)
{
    const auto star = pattern.find('*');
    if (star == std::string::npos)
        return host == pattern;

    const std::string pre = pattern.substr(0, star);
    const std::string suf = pattern.substr(star + 1);
    const auto startsWith = [](const std::string& v, const std::string& p) {
        return v.size() >= p.size() && v.compare(0, p.size(), p) == 0;
    };
    const auto endsWith = [](const std::string& v, const std::string& t) {
        return v.size() >= t.size() && v.compare(v.size() - t.size(), t.size(), t) == 0;
    };
    if (host.size() <= pre.size() + suf.size() || !startsWith(host, pre) || !endsWith(host, suf))
        return false;

    const std::string wildcard = host.substr(pre.size(), host.size() - pre.size() - suf.size());
    return wildcard.find('.') == std::string::npos; // 通配段不得跨 label
}

// 构建期注入值（逗号分隔）→ 归一化后的模式表。两侧空白去掉；空段（尾逗号 / 连续逗号）丢弃；
// 不过 isUsableHostPattern 的一律 **fail-closed 静默丢弃**（握手路径不打日志，见
// docs/build-windows.md「额外 Origin 白名单」小节的排障建议）。
inline std::vector<std::string> parseHostPatterns(const std::string& raw)
{
    const auto trim = [](const std::string& v) {
        const auto isSpace = [](char ch) { return std::isspace(static_cast<unsigned char>(ch)) != 0; };
        std::size_t b = 0;
        while (b < v.size() && isSpace(v[b]))
            ++b;
        std::size_t e = v.size();
        while (e > b && isSpace(v[e - 1]))
            --e;
        return v.substr(b, e - b);
    };

    std::vector<std::string> out;
    for (std::size_t start = 0; start <= raw.size();)
    {
        const auto comma = raw.find(',', start);
        const auto end = (comma == std::string::npos) ? raw.size() : comma;
        const std::string item = trim(raw.substr(start, end - start));
        start = end + 1;

        if (item.empty())
            continue;
        if (!isUsableHostPattern(item))
            continue;
        out.push_back(toLowerAscii(item)); // host 侧已归一，模式一并归一
    }
    return out;
}

} // namespace synchain::origin
