# Third-Party Notices

本文件列出 Synchain Bridge 分发产物中随附的第三方依赖的许可证信息。
每条许可证结论均以实际安装版本的 LICENSE / copyright 文件逐条核实(核验来源路径见末列),无「待验证」项。
静态链接闭包经机器枚举 vcpkg x64-windows-static 实际安装的全部包(ixwebsocket + 传递依赖),与 08 §3.1 表一致。

| 依赖 | 版本 | 许可证(SPDX) | URL | 核验来源(LICENSE 路径) |
|---|---|---|---|---|
| JUCE Framework(静态链接) | 8.0.8 | AGPL-3.0-or-later(双授权:AGPLv3 / 商业;本项目取 AGPLv3) | https://github.com/juce-framework/JUCE | C:/Users/lenovo/deepseekHarness/juce/LICENSE.md(git tag 8.0.8) |
| JUCE JS helper(web/js/juce/*.js) | 随 JUCE 8.0.8 | AGPL-3.0-or-later(双授权) | https://github.com/juce-framework/JUCE | 文件头 "Copyright (c) Raw Material Software Limited"(web/js/juce/index.js、check_native_interop.js 第 4–5 行)+ 同上 LICENSE.md |
| ixwebsocket(vcpkg 静态链接) | 12.0.1 | BSD-3-Clause | https://github.com/machinezone/IXWebSocket | C:/Users/lenovo/deepseekHarness/vcpkg/installed/x64-windows-static/share/ixwebsocket/copyright(Copyright (c) 2018 Machine Zone, Inc.) |
| mbedtls(ixwebsocket 内置 TLS,静态链接) | 3.6.5 | Apache-2.0 OR GPL-2.0-or-later(双授权) | https://github.com/Mbed-TLS/mbedtls | C:/Users/lenovo/deepseekHarness/vcpkg/installed/x64-windows-static/share/mbedtls/copyright(双授权声明见文件首 2 行) |
| zlib(ixwebsocket 传递依赖,静态链接) | 1.3.2 | Zlib | https://zlib.net | C:/Users/lenovo/deepseekHarness/vcpkg/installed/x64-windows-static/share/zlib/copyright(Copyright (C) 1995-2026 Jean-loup Gailly and Mark Adler) |
| Microsoft WebView2 SDK(静态 loader) | 1.0.2957.106 | BSD-3-Clause(Microsoft) | https://www.nuget.org/packages/Microsoft.Web.WebView2 | C:/Users/lenovo/.nuget/packages/microsoft.web.webview2/1.0.2957.106/LICENSE.txt |
| Space Grotesk(子集 web/fonts/SpaceGrotesk.woff2) | Google Fonts text= 子集 | OFL-1.1(无 Reserved Font Name) | https://github.com/google/fonts/tree/main/ofl/spacegrotesk | 上游 OFL.txt:"Copyright 2020 The Space Grotesk Project Authors (https://github.com/floriankarsten/space-grotesk)" |
| IBM Plex Sans(子集 web/fonts/IBMPlexSans.woff2) | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/main/ofl/ibmplexsans | 上游 OFL.txt:"Copyright © 2017 IBM Corp. with Reserved Font Name 'Plex'" |
| IBM Plex Mono(子集 web/fonts/IBMPlexMono.woff2) | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/main/ofl/ibmplexmono | 上游 OFL.txt:"Copyright © 2017 IBM Corp. with Reserved Font Name 'Plex'" |
| Noto Sans SC(子集 web/fonts/NotoSansSC.woff2) | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Source") | https://github.com/google/fonts/tree/main/ofl/notosanssc | 上游 OFL.txt:"Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'" |
| pluginval(仅 CI 下载执行) | v1.0.4 | GPL-3.0-or-later | https://github.com/Tracktion/pluginval | 仅 CI 使用,不链接进 .vst3、不分发(08 §3.1 定论) |

## 说明

- WebView2 Runtime(Evergreen):不随本仓库分发。插件通过静态 loader(上表 SDK 项)加载宿主机器上已安装的
  WebView2 Runtime(Windows 平台组件 / 系统库,运行时由微软 Evergreen 引导器安装),故 Runtime 不进第三方声明闭包。
  这与 U2「不附 LICENSE-EXCEPTION.md,依赖 GPLv3 系统库例外默认解释」一致。
- 字体子集化 = 对字体的修改(OFL 1.1 §3,Reserved Font Name 核验):
  - Space Grotesk:无 Reserved Font Name,子集命名不受限。
  - IBM Plex Sans / IBM Plex Mono:Reserved Font Name "Plex"。当前子集文件仍以
    IBMPlexSans.woff2 / IBMPlexMono.woff2 及 @font-face family 'IBM Plex Sans' / 'IBM Plex Mono'
    分发,使用了 RFN "Plex"。按 OFL 1.1 §3,Modified Version 不得使用 Reserved Font Name,需改名(文件名 +
    @font-face family + 相关引用)。此项为转 public 前须处理项,已登记至 masterPlan/ops/B02-repo.md。
  - Noto Sans SC:Reserved Font Name "Source"。子集名 NotoSansSC.woff2 / family 'Noto Sans SC'
    不含 "Source",不触发 RFN 限制(注:"Noto" 为 Google 商标,非 RFN)。
- 字体 OFL 全文见 LICENSES/OFL-1.1.txt;各家族版权行以 Google Fonts 上游 OFL.txt 为准(来源 URL 见上表)。
