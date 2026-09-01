# Third-Party Notices

本文件列出 Synchain Bridge 分发产物中随附的第三方依赖的许可证信息。
每条许可证结论均以**实际安装/链接版本对应的上游许可证原文**逐条核实(核验出处见末列,均为可公开访问的上游权威来源:
版本 tag 下的 LICENSE 文件、上游官网许可页或包分发页),无「待验证」项。
静态链接闭包经机器枚举 vcpkg x64-windows-static 实际安装的全部包(ixwebsocket + 传递依赖),与 08 §3.1 表一致。

| 依赖 | 版本 | 许可证(SPDX) | URL | 核验来源(上游许可证原文) |
|---|---|---|---|---|
| JUCE Framework(静态链接) | 8.0.8 | AGPL-3.0-or-later(双授权:AGPLv3 / 商业;本项目取 AGPLv3) | https://github.com/juce-framework/JUCE | tag 8.0.8 的 LICENSE.md:https://github.com/juce-framework/JUCE/blob/8.0.8/LICENSE.md(原文:"The JUCE Framework modules are dual-licensed under the AGPLv3 and the commercial JUCE licence") |
| JUCE JS helper(web/js/juce/*.js) | 随 JUCE 8.0.8 | AGPL-3.0-or-later(双授权) | https://github.com/juce-framework/JUCE | 文件头 "Copyright (c) Raw Material Software Limited"(web/js/juce/index.js、check_native_interop.js 第 4–5 行)+ 同上 LICENSE.md |
| ixwebsocket(vcpkg 静态链接) | 12.0.1 | BSD-3-Clause | https://github.com/machinezone/IXWebSocket | tag v12.0.1 的 LICENSE.txt:https://github.com/machinezone/IXWebSocket/blob/v12.0.1/LICENSE.txt(首行 "Copyright (c) 2018 Machine Zone, Inc. All rights reserved.",正文为 BSD 三条款) |
| mbedtls(ixwebsocket 内置 TLS,静态链接) | 3.6.5 | Apache-2.0 OR GPL-2.0-or-later(双授权) | https://github.com/Mbed-TLS/mbedtls | tag mbedtls-3.6.5 的 LICENSE:https://github.com/Mbed-TLS/mbedtls/blob/mbedtls-3.6.5/LICENSE(双授权声明见文件首 2 行:"provided under a dual Apache-2.0 OR GPL-2.0-or-later license",两份全文附于其后,取哪一份由使用者选择) |
| zlib(ixwebsocket 传递依赖,静态链接) | 1.3.2 | Zlib | https://zlib.net | tag v1.3.2 的 LICENSE:https://github.com/madler/zlib/blob/v1.3.2/LICENSE(版权行 "(C) 1995-2026 Jean-loup Gailly and Mark Adler")。zlib.net 的许可页永远反映官网**当前**版本,会随上游发版与本表锁定的 1.3.2 脱钩,故只列作项目 URL、不作核验出处 |
| Microsoft WebView2 SDK(静态 loader) | 1.0.2957.106 | BSD-3-Clause(Microsoft) | https://www.nuget.org/packages/Microsoft.Web.WebView2 | 该版本 NuGet 包的 License 页(即包内 LICENSE.txt 原文):https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2957.106/License(BSD 三条款,版权归 Microsoft) |
| Space Grotesk(子集 web/fonts/SpaceGrotesk.woff2) | Google Fonts text= 子集 | OFL-1.1(无 Reserved Font Name) | https://github.com/google/fonts/tree/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/spacegrotesk | 固定 commit 下的 OFL.txt:https://github.com/google/fonts/blob/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/spacegrotesk/OFL.txt(首行「Copyright 2020 The Space Grotesk Project Authors (https://github.com/floriankarsten/space-grotesk)」) |
| IBM Plex Sans(来源家族;子集按 §3 改名分发 web/fonts/BridgeSans.woff2 / family "Bridge Sans") | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/ibmplexsans | 固定 commit 下的 OFL.txt:https://github.com/google/fonts/blob/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/ibmplexsans/OFL.txt(首行「Copyright © 2017 IBM Corp. with Reserved Font Name "Plex"」) |
| IBM Plex Mono(来源家族;子集按 §3 改名分发 web/fonts/BridgeMono.woff2 / family "Bridge Mono") | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Plex") | https://github.com/google/fonts/tree/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/ibmplexmono | 固定 commit 下的 OFL.txt:https://github.com/google/fonts/blob/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/ibmplexmono/OFL.txt(首行「Copyright © 2017 IBM Corp. with Reserved Font Name "Plex"」) |
| Noto Sans SC(子集 web/fonts/NotoSansSC.woff2) | Google Fonts text= 子集 | OFL-1.1(Reserved Font Name "Source") | https://github.com/google/fonts/tree/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/notosanssc | 固定 commit 下的 OFL.txt:https://github.com/google/fonts/blob/ade3d1533e06b2b1462ffcde8e08b129627ca360/ofl/notosanssc/OFL.txt(首行「Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'」) |
| pluginval(仅 CI 下载执行) | v1.0.4 | GPL-3.0-or-later | https://github.com/Tracktion/pluginval | 仅 CI 使用,不链接进 .vst3、不分发(08 §3.1 定论) |

## 说明

- WebView2 Runtime(Evergreen):不随本仓库分发。插件通过静态 loader(上表 SDK 项)加载宿主机器上已安装的
  WebView2 Runtime(Windows 平台组件 / 系统库,运行时由微软 Evergreen 引导器安装),故 Runtime 不进第三方声明闭包。
  这与 U2「不附 LICENSE-EXCEPTION.md,依赖 GPLv3 系统库例外默认解释」一致。
- 字体子集化 = 对字体的修改(OFL 1.1 意义上的 Modified Version)。**RFN 逐家族核验**(OFL 1.1 §3
  Reserved Font Name;核验依据 = 各家族上游 OFL.txt 的版权行,见上表末列):
  - **Space Grotesk**:上游版权行**不含** "with Reserved Font Name",即无 RFN,子集命名不受限
    → 分发名沿用 SpaceGrotesk.woff2 / family 'Space Grotesk',二进制原样分发。
  - **IBM Plex Sans / IBM Plex Mono**:RFN = "Plex"。§3 限制的对象是**呈现给用户的主字体名**
    (LICENSES/OFL-1.1.txt 原文:"This restriction only applies to the primary font name as
    presented to the users"),即字体 `name` 表里的家族名 / 全名 / PostScript 名,**不只是文件名
    与 CSS family**。故本仓子集在两层都去掉了 RFN:
    - 外层:文件名 BridgeSans.woff2 / BridgeMono.woff2,`@font-face` family 'Bridge Sans' /
      'Bridge Mono',`web/styles.css` 字体栈与 `CMakeLists.txt` 的 BinaryData 源列表同步改名;
    - 二进制内:`scripts/fetch_fonts.py` 的 `rename_font()` 在下载后用 fontTools 重写 `name` 表的
      nameID 1 / 3 / 4 / 6(家族名、唯一 ID、全名、PostScript 名),改名后 name 表内**不含 "Plex"**。
    §2 要求的署名不动:nameID 0(版权行 "Copyright 2019 IBM Corp. All rights reserved." /
    "Copyright 2017 IBM Corp. All rights reserved.")与 nameID 14(OFL 许可证 URL)逐字保留,
    并补齐上游子集里缺失的 nameID 13(OFL 许可证声明);改名函数对这三条有前后比对断言。
    上表「来源家族」列保留 IBM Plex 原名正是为此署名可追溯。
  - **Noto Sans SC**:RFN = "Source"。分发名 NotoSansSC.woff2 / family 'Noto Sans SC' 与其 name 表
    内的家族名均不含 "Source",不触发 §3 限制,无需改名,二进制原样分发
    (注:"Noto" 为 Google 商标,非 RFN;其 nameID 0 里的 "Reserved Font Name 'Source'" 是上游版权
    声明原文,属 §2 署名,不是分发名)。
  - **§3 结论**:四款字体**呈现给用户的主字体名**(name 表 nameID 1/4/6 + 文件名 + CSS family)
    均不含各自上游的 RFN,OFL 1.1 §3 已满足。机器复核(勿只 grep 二进制 —— woff2 是 brotli 压缩的,
    grep 不命中并不等于名字已清除):

    ```bash
    python -c "from fontTools.ttLib import TTFont; import glob; \
    print([(p, TTFont(p)['name'].getDebugName(1)) for p in sorted(glob.glob('web/fonts/*.woff2'))])"
    ```

  - **§2 署名随分发**:「每份拷贝都包含上述版权声明与本许可证」的要求经三条路径满足 ——
    (a) 未改动的 name 表 nameID 0 / 13 / 14;(b) 本文件;(c) `LICENSES/OFL-1.1.txt`,由
    `scripts/package.ps1` 复制进发布 zip 根目录的 `LICENSES/` 并在打包后逐个断言存在(缺一即 throw)。
  - **条款编号更正**:OFL-1.1 的 **§4 是禁止背书条款**(不得用版权人 / 作者的名义为 Modified Version
    背书或做广告),要求随拷贝附版权声明与许可证的是 **§2**。本文件与 `web/fonts/README.md` 早前把
    这两条编号写反(commit 838bc8c 的 message 同),现已更正。
- 字体 OFL 全文见 LICENSES/OFL-1.1.txt;各家族版权行以上表末列固定 commit 下的上游 OFL.txt 为准。
