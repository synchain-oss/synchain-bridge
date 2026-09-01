# Third-Party Notices

本文件列出 Synchain Bridge 分发产物中随附的第三方依赖的许可证信息。
每条许可证结论均以实际安装版本的 LICENSE / copyright 文件逐条核实(核验来源路径见末列),无「待验证」项。
静态链接闭包经机器枚举 vcpkg x64-windows-static 实际安装的全部包(ixwebsocket + 传递依赖),与 08 §3.1 表一致。

| 依赖 | 版本 | 许可证(SPDX) | URL | 核验来源(LICENSE 路径) |
|---|---|---|---|---|
| JUCE Framework(静态链接) | 8.0.8 | AGPL-3.0-or-later(双授权:AGPLv3 / 商业;本项目取 AGPLv3) | https://github.com/juce-framework/JUCE | [REDACTED-PATH]/juce/LICENSE.md(git tag 8.0.8) |
| JUCE JS helper(web/js/juce/*.js) | 随 JUCE 8.0.8 | AGPL-3.0-or-later(双授权) | https://github.com/juce-framework/JUCE | 文件头 "Copyright (c) Raw Material Software Limited"(web/js/juce/index.js、check_native_interop.js 第 4–5 行)+ 同上 LICENSE.md |
| ixwebsocket(vcpkg 静态链接) | 12.0.1 | BSD-3-Clause | https://github.com/machinezone/IXWebSocket | [REDACTED-PATH]/vcpkg/installed/x64-windows-static/share/ixwebsocket/copyright(Copyright (c) 2018 Machine Zone, Inc.) |
| mbedtls(ixwebsocket 内置 TLS,静态链接) | 3.6.5 | Apache-2.0 OR GPL-2.0-or-later(双授权) | https://github.com/Mbed-TLS/mbedtls | [REDACTED-PATH]/vcpkg/installed/x64-windows-static/share/mbedtls/copyright(双授权声明见文件首 2 行) |
| zlib(ixwebsocket 传递依赖,静态链接) | 1.3.2 | Zlib | https://zlib.net | [REDACTED-PATH]/vcpkg/installed/x64-windows-static/share/zlib/copyright(Copyright (C) 1995-2026 Jean-loup Gailly and Mark Adler) |
| Microsoft WebView2 SDK(静态 loader) | 1.0.2957.106 | BSD-3-Clause(Microsoft) | https://www.nuget.org/packages/Microsoft.Web.WebView2 | [REDACTED-PATH]/packages/microsoft.web.webview2/1.0.2957.106/LICENSE.txt |
| Space Grotesk(子集 web/fonts/SpaceGrotesk.woff2) | Google Fonts text= 子集 | OFL-1.1(无 Reserved Font Name) | https://github.com/google/fonts/tree/main/ofl/spacegrotesk | 上游 OFL.txt:"Copyright 2020 The Space Grotesk Project Authors (https://github.com/floriankarsten/space-grotesk)" |
| IBM Plex Sans(来源家族;子集按 §3 改名分发 web/fonts/BridgeSans.woff2 / family "Bridge Sans") | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/main/ofl/ibmplexsans | 上游 OFL.txt:"Copyright © 2017 IBM Corp. with Reserved Font Name 'Plex'" |
| IBM Plex Mono(来源家族;子集按 §3 改名分发 web/fonts/BridgeMono.woff2 / family "Bridge Mono") | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/main/ofl/ibmplexmono | 上游 OFL.txt:"Copyright © 2017 IBM Corp. with Reserved Font Name 'Plex'" |
| Noto Sans SC(子集 web/fonts/NotoSansSC.woff2) | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Source") | https://github.com/google/fonts/tree/main/ofl/notosanssc | 上游 OFL.txt:"Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'" |
| pluginval(仅 CI 下载执行) | v1.0.4 | GPL-3.0-or-later | https://github.com/Tracktion/pluginval | 仅 CI 使用,不链接进 .vst3、不分发(08 §3.1 定论) |

## 说明

- WebView2 Runtime(Evergreen):不随本仓库分发。插件通过静态 loader(上表 SDK 项)加载宿主机器上已安装的
  WebView2 Runtime(Windows 平台组件 / 系统库,运行时由微软 Evergreen 引导器安装),故 Runtime 不进第三方声明闭包。
  这与 U2「不附 LICENSE-EXCEPTION.md,依赖 GPLv3 系统库例外默认解释」一致。
- 字体子集化 = 对字体的修改(OFL 1.1 意义上的 Modified Version)。**RFN 逐家族核验**(OFL 1.1 §3
  Reserved Font Name;核验依据 = 各家族上游 OFL.txt 的版权行,见上表末列):
  - **Space Grotesk**:上游版权行**不含** "with Reserved Font Name",即无 RFN,子集命名不受限
    → 分发名沿用 SpaceGrotesk.woff2 / family 'Space Grotesk'。
  - **IBM Plex Sans / IBM Plex Mono**:RFN = "Plex"。Modified Version 不得使用 RFN,故本仓子集
    **改名分发**:文件名 BridgeSans.woff2 / BridgeMono.woff2,@font-face family 'Bridge Sans' /
    'Bridge Mono',CSS 字体栈与 BinaryData 源列表同步改名。改名范围 = 文件名 + family + 引用 +
    子集脚本输出名;**woff2 二进制不改动**——其 name 表内的上游版权与家族署名按 §4 随产物原样分发,
    上表「来源家族」列保留 IBM Plex 原名正是为此署名可追溯。
  - **Noto Sans SC**:RFN = "Source"。分发名 NotoSansSC.woff2 / family 'Noto Sans SC' 不含 "Source",
    不触发 §3 限制,无需改名(注:"Noto" 为 Google 商标,非 RFN)。
  - 结论:四款字体的分发名均不含各自上游的 RFN,OFL 1.1 §3 已满足;§4 署名经未改动的 name 表 +
    本文件 + LICENSES/OFL-1.1.txt 随产物分发。
- 字体 OFL 全文见 LICENSES/OFL-1.1.txt;各家族版权行以 Google Fonts 上游 OFL.txt 为准(来源 URL 见上表)。
