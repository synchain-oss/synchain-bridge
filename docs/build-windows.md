# Windows 源码构建指南

> 面向 Windows x64 + Visual Studio 2022。产物是 `Synchain Bridge.vst3` 与 `Synchain Bridge.aaxplugin`（都是 **bundle 目录**，不是单文件）。
> 只想下载预编译版并插进 DAW 的读者，请看 [README](../README.md) 的 Install 一节。
> macOS（Apple Silicon，VST3 + AU）另见 [build-macos.md](build-macos.md)。
> Pro Tools（AAX）的产物、打包、安装与本地门禁见本文的 [AAX（Pro Tools）](#aaxpro-tools) 一节。

## 前置依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| Windows | x64 | 本文只覆盖 Windows 侧；macOS（arm64，VST3 + AU）的构建见 [build-macos.md](build-macos.md) |
| Visual Studio 2022 | 「使用 C++ 的桌面开发」（MSVC v143 + Windows SDK） | VS2019 BuildTools（v142）亦可 |
| CMake | ≥ 3.22 | 见 `CMakeLists.txt` 的 `cmake_minimum_required` |
| JUCE | 8.0.8（版本真源 `.juce-version`） | `git clone --branch 8.0.8` |
| vcpkg | 已 bootstrap 的 vcpkg 克隆（**manifest 模式**，无需手工 `vcpkg install`） | ixwebsocket 由仓库根 `vcpkg.json` 钉死（`builtin-baseline` 40 位 commit + `overrides` 12.0.1），CMake 配置期经 vcpkg toolchain 自动装进 `<build>/vcpkg_installed`；triplet 必须 `x64-windows-static`，与静态 CRT 对齐 |
| NuGet CLI | `nuget.exe` 在 PATH | CMake 配置期自动拉 `Microsoft.Web.WebView2`，无需手工装 SDK |
| WebView2 Runtime | Evergreen | Win11 已内置；Win10 缺时插件会弹原生兜底面板引导安装 |

## 一次性准备

```powershell
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
git clone --depth 1 --branch 8.0.8 https://github.com/juce-framework/JUCE C:\dev\JUCE
```

**不需要 `vcpkg install ixwebsocket`**：仓库根的 `vcpkg.json` 是 manifest，下一步 `cmake` 配置时 vcpkg toolchain 会按它的
`builtin-baseline`（microsoft/vcpkg 的 40 位 commit）自动把 `ixwebsocket` 12.0.1 及其传递依赖（mbedtls / zlib）装进
`build/vcpkg_installed/`（首次会编译几分钟，之后走 `%LOCALAPPDATA%\vcpkg\archives` 的二进制缓存）。
vcpkg 克隆本身**不必**停在 baseline 那个 commit ——它只需要能取到那个 commit（缺失时 vcpkg 会自行 `git fetch`）。
要升 ixwebsocket 版本，改 `vcpkg.json`（baseline + overrides 的 `version-semver` **与 `port-version`**）与 `CMakeLists.txt` 的
`IXWEBSOCKET_TAG`（macOS 侧；同一行注释里的 `(= tag vX.Y.Z)` 也要改，本地 gate 3g 与 `compliance` 会拿它和 override 比）
**同一 PR 一起动**，并同步 `THIRD-PARTY-NOTICES.md` 与 `scripts/assert-vcpkg-installed.ps1` 里的传递依赖（mbedtls / zlib）期望版本表
——该脚本在 configure 之后（本地 gate 4b 与 CI 同一份）断言 `build/vcpkg_installed/vcpkg/status` 里实际装进来的版本。

## 配置 + 构建（在仓库根目录执行）

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DCMAKE_TOOLCHAIN_FILE="C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release
```

产物：`build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3`（AAX 产物见下方 [AAX（Pro Tools）](#aaxpro-tools)）

## 可选：额外 Origin 白名单（构建期注入）

WebSocket 桥的 Origin 白名单（CSWSH 防护）在源码里只含 `synchain.cn` / `synchain.ca` 系默认域与本地回环；
**预览部署等额外来源不写进仓库**，需要时在配置期注入：

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DJUCE_PATH="C:/dev/JUCE" `
  -DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS="example-git-*-example-team.example.app;preview.example.com"
```

- 值为 `;` 或 `,` 分隔的 **host 模式**列表；每个模式**至多一个 `*`**，无 `*` 时按精确 host 匹配；
  匹配前统一小写归一，FQDN 尾点（`https://example.com.`）会被剥掉后再比。
- `*` 只匹配**单个 DNS 标签内**的一段非空字符：**通配段不跨 `.`**。即 `a-*-b.example.app` 匹配
  `a-x-b.example.app`，但**不**匹配 `a-x.evil.com-b.example.app`。
- 模式必须带**真实域名锚点**才会被采纳，且 `*` 必须落在**最左 label 内**（位置在第一个 `.` 之前）。
- 额外来源同样**只在 https 下生效**（非 https 的远程来源一律拒）。
- 值里**不得含双引号或反斜杠**：该值最终会进生成头 `BridgeOriginConfig.h` 的字符串字面量，
  CMake 配置期检测到会直接 `FATAL_ERROR`。
- **不传即不定义该宏**：默认构建不放行任何额外来源。实现见 `src/OriginAllowlist.h`（纯匹配逻辑，
  断言见 `tests/origin_allowlist_selftest.cpp`）与 `src/VstBridgeServer.cpp` 的 `isAllowedOrigin()`。

### 不合法模式会被静默丢弃（fail-closed）

**校验不通过的模式不会报错，也不会留下任何运行期日志**——它只是不进白名单，用它的来源随后握手会
收到 `close(4403, "origin not allowed")`。这是刻意的（握手路径不打日志，避免把注入值写进日志），
代价是**拼错的模式看起来和没注入一样**。会被丢弃的形态：

| 形态 | 例子（域名均为虚构） | 原因 |
|---|---|---|
| 多于一个 `*` | `*.*.example.app`、`**.example.app` | 不在约定内 |
| 无 ≥2 段域名锚点 | `*.com`、`*.app`、`*example.app`、`*-team.app` | 第一个 `.` 之后只剩一段 TLD，等于放行整个 TLD |
| `*` 不在最左 label | `preview.*.example.app`、`example.*.app`、`example.app-*` | 通配跨到锚点里 |
| 字面量全是标点 / 无点 | `*`、`*.`、`-*`、`*-`、`localhost` | 没有域名锚点，等于全通配 |
| TLD 非 2+ 纯字母 | `*.example.a`、`*.example.a1`、`*.192.168.0.1` | 末段不是合法 TLD |
| punycode / IDN TLD | `*.example.xn--p1ai` | **不支持**：TLD 段含 `-` 与数字，一律丢弃 |
| 以 `.` 结尾 | `example.app.` | host 归一化会剥掉尾点，带尾点的模式永远匹配不上 |

**注入后请实测一次**，别只看构建成功。在目标页面的浏览器控制台跑：

```js
new WebSocket("ws://127.0.0.1:9420").addEventListener("close", (e) => console.log(e.code, e.reason));
```

握手被接受时不会打印 `4403`；打印 `4403 origin not allowed` 就说明该 Origin 没进白名单
（模式被丢弃、拼错，或页面不是 https）。

## 关键坑（必读）

### 1. 静态 CRT 必须在 `project()` **之前**设置

见 `CMakeLists.txt` 开头、`project()` **之前**的那一段。`CMAKE_MSVC_RUNTIME_LIBRARY` 的 `/MT` 必须写在 `project()` 之前才生效，与 vcpkg `x64-windows-static` triplet 和 WebView2 静态 loader 三者对齐。顺序颠倒会导致链接期 `/MT` vs `/MD` 冲突（LNK2038）。同一块里 `project()` 之前还设了 macOS 的架构 / 部署目标（同样要参与编译器探测），那两个变量在 Windows 上完全无作用。

### 2. vcpkg triplet 必须 `x64-windows-static`

ixwebsocket 用静态 triplet 编译（内嵌 mbedtls，无需单独 OpenSSL）。动态 triplet 会与静态 CRT 冲突。
依赖块按平台分支：**Windows 走 vcpkg 的 `find_package(ixwebsocket)`（本节），macOS 走 `FetchContent`**，两条路径互不影响。
版本两侧都钉到内容级：Windows 由 `vcpkg.json` 的 `builtin-baseline`（40 位 commit）+ `overrides` 钉 12.0.1，macOS 由
`IXWEBSOCKET_TAG`（40 位 commit = 上游 tag v12.0.1）钉。`-DCMAKE_TOOLCHAIN_FILE` 指向的 vcpkg 克隆若没有 `vcpkg.exe`
（未 bootstrap），配置期会在 `Running vcpkg install` 处失败。

### 3. WebView2 是配置期 NuGet 自动拉取，不是「装 SDK」

见 `CMakeLists.txt` 的 `if(WIN32)` WebView2 块。JUCE 的 `NEEDS_WEBVIEW2` 只会**查找 + 链接**已经存在的 NuGet 包，不会自己下载。本仓在配置期用 `nuget.exe` 把 `Microsoft.Web.WebView2` 拉到确定性目录 `build/packages`，再经 `JUCE_WEBVIEW2_PACKAGE_LOCATION` 指过去——不依赖 `%USERPROFILE%`，本地与 CI 可复现。缺 `nuget.exe` 会直接 FATAL_ERROR。

### 4. 编译宏组合（必要且易漏）

见 `CMakeLists.txt` 的 `# --- Compile Definitions ---` 段。三个宏缺一不可（后两个只在 `if(WIN32)` 内定义）：

- `JUCE_WEB_BROWSER=1` —— 启用 `WebBrowserComponent`
- `JUCE_USE_WIN_WEBVIEW2=1` —— 启用 WebView2 代码路径
- `JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING=1` —— 静态 loader，运行时不需要 `WebView2Loader.dll`

注意：这些宏**只让代码路径存在 + 链接 loader，并不切换后端**。真正选后端靠 `WebViewEditor.cpp` 里的 `withBackend(webview2)`（见 [webview-ui-pattern.md](webview-ui-pattern.md) 条目 2）。

### 5. 常见失败排查

- **`JUCE_PATH must be set`**：没传 `-DJUCE_PATH`，或路径指向了 JUCE 子目录而非根。
- **`nuget.exe not found`**：装 NuGet CLI 并确保在 PATH；或预先往 `build/packages` 放好 WebView2 包（离线 / 缓存场景）。
- **LNK2038（`/MT` vs `/MD` 不匹配）**：回到坑 1/2 检查 CRT 设置位置与 triplet。
- **`无法打开此页 https://juce.backend`**（运行期，非构建期）：未显式选 WebView2 后端，回退到了旧 IE 控件。见 [webview-ui-pattern.md](webview-ui-pattern.md) 条目 2。
- **插件窗口是英文兜底面板**：WebView2 Runtime 缺失或加载超时。装 Runtime 后重开插件窗口。

## AAX（Pro Tools）

AAX SDK（2.8.0）随 JUCE 8.0.8 自带，不需要另外下载；上面的配置 + 构建会一并产出 AAX 目标，不需要额外 CMake 参数
（CMake 选项 `SYNCHAIN_BRIDGE_AAX` 默认 ON；只要 VST3 时传 `-DSYNCHAIN_BRIDGE_AAX=OFF`。这个值会留在 CMake 缓存里，之后
要 AAX 时须显式传 `-DSYNCHAIN_BRIDGE_AAX=ON` 重新配置 —— 关掉期间构建目录里的旧 AAX bundle 不会被删，`build.ps1 -InstallAax`
与门禁 5c 见到缓存为 OFF 会直接报错，不拿旧 bundle 充数）。配置期日志应出现：

```
-- Building Synchain Bridge for Windows: VST3 + AAX (static CRT, WebView2)
```

### 产物

```
build/SynchainBridgeVST_artefacts/Release/AAX/Synchain Bridge.aaxplugin/
├── desktop.ini
├── Plugin.ico
└── Contents/x64/Synchain Bridge.aaxplugin     # 主体 DLL（单个文件，后缀同样是 .aaxplugin）
```

- JUCE 在构建后给 bundle 目录与 `desktop.ini` 加了 System 属性（`attrib +s`），用 PowerShell 枚举 / 复制时要加 `-Force`，否则可能被跳过。
- VS 多配置生成器在配置期就给每个配置（Debug / Release / …）各建一个只有 `desktop.ini` 的空壳 `.aaxplugin` 目录，它们不是产物；
  真正构建出来的是含 `Contents\` 的那一个。打包脚本与门禁都只认含 `Contents\` 的 bundle：打包脚本走 `-BuildDir` 搜索时要求
  整个构建目录里恰好 1 个；门禁 5c 只数当前 `-Config` 的产物目录（同一个构建目录里另有 Debug 产物不算）。
- 主体 DLL 应导出 `ACFRegisterPlugin` 等 AAX 入口，可用 `dumpbin /exports` 抽查。

### 打包未签名件

```powershell
pwsh scripts/package-aax.ps1 -Mode Unsigned -BuildDir build
# 产物：dist/aax/SynchainBridge-AAX-v<版本>-win64-UNSIGNED.zip（+ .sha256 + package-summary.md）
```

- `-Mode Unsigned|Signed` 必填、无默认值、大小写敏感。`Unsigned` 产出的文件名带 `-UNSIGNED`，只用作签名输入或在
  Pro Tools Developer 里自测，**不是发行版**；`Signed` 只接受 DLL 带 Authenticode 签名的 bundle，由签名脚本在签完之后调用，
  不要手工对未签名 bundle 跑（会被拒收）。
- 版本不传时读 `CMakeLists.txt`；`-Version` 与 `-PrereleaseTag` 互斥，显式传空串直接失败。构建目录里有多个已构建的
  bundle（例如 Debug 与 Release 都构建过）时，用 `-BundlePath <.aaxplugin 目录>` 指定。
- zip 里是 bundle、`INSTALL-AAX.txt`（中文安装说明，含 Pro Tools 插件目录的安装命令、商标与许可证说明）与三份合规文件
  （`LICENSE.txt` / `THIRD-PARTY-NOTICES.md` / `LICENSES/OFL-1.1.txt`）。脚本不调用任何签名工具、不碰凭据。

### 安装（管理员）

Pro Tools 只扫描 64 位 Common Files 下的 `Avid\Audio\Plug-Ins\`（通常是 `C:\Program Files\Common Files\Avid\Audio\Plug-Ins\`），
没有用户级目录。最省事的是在**管理员 PowerShell** 里让构建脚本代劳：

```powershell
pwsh scripts/build.ps1 -InstallAax
```

它在构建前先验管理员权限（不是管理员直接退出）；配置后若 CMake 缓存里 `SYNCHAIN_BRIDGE_AAX` 不是 ON（或生成的工程里没有
AAX 目标）就报错退出，不把开关打开时留下的旧 bundle 装进去；装前检查主体 DLL 是否被 Pro Tools 占用，先删旧版再整体复制。
手工安装（先退出 Pro Tools；`$env:CommonProgramW6432` 恒指向 64 位的 Common Files）：

```powershell
Remove-Item "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\Synchain Bridge.aaxplugin" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "<产物路径>\Synchain Bridge.aaxplugin" "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\" -Recurse -Force
```

先删旧版：`Copy-Item` 对已存在的 bundle 是合并，旧版残留的文件会混进来。**本地构建的未签名件只有 Pro Tools Developer
能加载**，零售版 Pro Tools 只认 PACE 签名的 AAX。

### 本地门禁

```powershell
pwsh scripts/gates.ps1 -PluginOnly -IncludeAax -BuildDir build-aax
```

- gate 3h「签名材料 / Avid 评估工具不入库」默认恒跑（不需要开关）：仓库里（含被 `.gitignore` 忽略的文件）出现
  `*.pfx` / `*.p12` / `*.pvk`、`dsh.exe`、DigiShell / AAX Validator 的可执行文件或安装包、测试计划 PDF 即 FAIL。证书扩展名
  落在任意路径都算；DigiShell / AAX Validator / 测试计划的关键词必须出现在文件名里，目录名（例如 `build-aax-validator\`）
  不算。文件名按 UTF-8 解码，中文 Windows（CP936 控制台）下中文名的证书文件同样命中。
- `-IncludeAax`（默认关）在 selftest 之后、pluginval 之前加跑三道：**5c** bundle 结构（CMake 缓存里 `SYNCHAIN_BRIDGE_AAX`
  为 ON 且工程里有 AAX 目标、PE x64、`desktop.ini` / `Plugin.ico`、当前 `-Config` 下已构建 bundle 恰好 1 个）、**5d** 打包
  冒烟（Unsigned 跑一次并断言 `.sha256` 字节形态；Signed 反向断言
  必须拒收）、**5e** AAX Validator（见下）。`-Quick` 只跳过 pluginval，不影响这三道。
- pluginval 托管不了 AAX，Pro Tools 里的验收靠手工，见 [DAW_TEST_GUIDE.md](DAW_TEST_GUIDE.md#pro-toolsaax实测windows--macos)。

### 签名（维护者）

签名与上传由维护者在本机完成，流程见 [release.md §7](release.md#7-aaxpro-tools本机签名--手工上传)：
`scripts/sign-aax.ps1` 把 CI 产出的 `-UNSIGNED.zip` 经 PACE wraptool 签名后，调用 `package-aax.ps1 -Mode Signed` 出发行包。
`.aaxplugin` 是目录，Windows 版 wraptool 只收文件：脚本把整个 bundle 复制到临时工作目录，只对其中的内层 DLL
（`Contents\x64\Synchain Bridge.aaxplugin`）原地签名。

- **签名工具**：装 PACE 的 AAX 代码签名工具（wraptool 6.0.1 装在 `%ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\6\bin\`）
  后要**新开一个终端**：安装器设的 Machine 级环境变量 `PACE_FUSION_HOME` 在之前开着的终端里没有，wraptool 会报它未定义。
  签名脚本缺它时会从 Machine 级补上，两处都没有就 FAIL。
- **signtool**：wraptool 在 Windows 上调 Windows SDK 的 `signtool.exe` 加 Authenticode 签名。6.0.1 在它自己的「默认位置」找不到
  SDK 10.0.19041 的 signtool，报的却是 "Can't sign with the certificate identified by the thumbprint ..."（2026-10-08 实测），所以签名脚本每次都经
  `--signtool` 显式指定。查找顺序：`-SignToolPath`、`%ProgramFiles(x86)%\Windows Kits\10\bin\<版本号最高的>\x64\signtool.exe`、PATH。
  都找不到就 FAIL；这时装 Windows SDK 的「Windows SDK Signing Tools for Desktop Apps」组件。
- **代码签名证书**：wraptool 在 Windows 上还需要一张 Authenticode 代码签名证书，本项目用自签名证书，一次性生成：

  ```powershell
  pwsh scripts/new-selfsigned-codesign-cert.ps1 -WhatIf   # 先预演：不读口令、不写证书库、不生成文件
  pwsh scripts/new-selfsigned-codesign-cert.ps1           # 证书留在 Cert:\CurrentUser\My;pfx 备份默认导出到 $env:USERPROFILE\.synchain-signing\
  ```

  记下最后打印的 Thumbprint，签名时用 `-CertThumbprint <指纹>`（推荐：不读 pfx 口令，wraptool 命令行上没有口令）；只有 pfx
  时用 `-KeyFile <pfx> -LegacySha1Digest`（备选，签名时交互读口令，只能出 SHA1 文件摘要）。pfx 必须放在仓库目录之外（脚本会拒绝仓库内路径），口令只交互输入、不写进任何入库文件。
- **签名命令**（在 pwsh 7.3+ 会话里、仓库根目录下用 `&` 调用；发布者用 `-WcGuid`，备选 `-CustomerNumber` 加 `-CustomerName`；
  `-SignToolPath` 可选，不给就自动找）：

  ```powershell
  & ./scripts/sign-aax.ps1 -UnsignedZip <...-win64-UNSIGNED.zip> -SourceRunId <run-id> -CertThumbprint <证书 SHA1 指纹> -WcGuid <wcguid> -DryRun
  ```

  不要用 `pwsh scripts/sign-aax.ps1 ...` 传数组参数（`-ExtraWraptoolArgs`）：在 `pwsh -File` 下数组不会被解析，参数会错位。
- **摘要算法**：默认经 `--explicitsigningoptions` 让 signtool 用 SHA256 文件摘要 + RFC 3161 时间戳（Sectigo）。wraptool 自己的默认是
  SHA1 + 旧式 `/t` 时间戳，`-LegacySha1Digest` 回退到它。后检会核对摘要算法与时间戳形态。细节与实测结论见
  [release.md §7.3 第 4 步](release.md#73-每次发版)，常见报错见 [§7.4 排障表](release.md#74-失败处理)。

- **PACE 账号口令**：推荐先手动执行一次带 `--password` 的 `wraptool sync --account <PACE 账号>`，把口令存进 wraptool 的钥匙串，
  之后签名不用再给；或者签名时加 `-Account <PACE 账号> -PromptAccountPassword`，交互读入、经 `--pswd-no-save` 传、不保存。
  不给 `-Account` 时 wraptool 用 iLok License Manager 的默认账号。细节见 [release.md §7.1](release.md#71-一次性准备windows)。

### 诊断日志

插件在少数事件上经 JUCE `Logger` 写一行诊断，前缀统一为 `SynchainBridge:`，全部在 message 线程、音频线程零日志。
没有设置 Logger 时落到 `OutputDebugString`，Release 构建同样可见：用 Sysinternals DebugView（Capture → Capture Win32）
按 `SynchainBridge:` 过滤。日志不止下表几行（例如 WebView 首帧放行的 `webview revealed (…)`），与 Pro Tools 排障最相关的是这四行 ——
前三行由编辑器写，**只在插件窗口开着时**出现；最后一行由处理器的 30 Hz timer 写，窗口关着也会出现（极短的切换可能漏记）：

| 时机 | 文案（`…` 为实际值） |
|---|---|
| 打开编辑器 | `SynchainBridge: editor opened: host=… wrapper=… size=WxH uiScale=… io=<入>/<出> desktopScale=…`（Pro Tools 下 `host=ProTools wrapper=AAX`） |
| 缩放档位被宿主拒绝（只在实际尺寸 ≠ 请求尺寸时） | `SynchainBridge: ui scale resize not applied by host: requested WxH, got wxh` |
| 插件窗口开着时，采样率 / 声道变化（只在变化时） | `SynchainBridge: audio: sampleRate=… channels=… latencyMs=…` |
| 宿主 non-realtime（离线渲染）状态切换 | `SynchainBridge: host non-realtime on (wrapper=AAX)` / `… off (wrapper=AAX)` |

### 可选：AAX Validator（TODO-AAXVAL）

AAX Validator / DigiShell 是 Avid 向 AAX 开发者提供的工具，**不入库、不分发、CI 不下载**。本地可选，用
`scripts/gates.ps1 -AaxValidatorPath <仓库外的可执行文件绝对路径>` 接入（给了路径即隐含 `-IncludeAax`）：没给 → 5e SKIP；
给了空串、路径在仓库内或不存在 → FAIL。调用参数与通过 / 失败标记是 `scripts/gates.ps1` 文件头三个 `TODO-AAXVAL` 常量，
未实测填写前 5e 恒为 SKIP「调用方式未实测」，不会假绿；填好后输出 Tee 到 `<构建目录>\gates-aaxval.log`，以输出标记判定、
退出码只作参考。首次接入时按下面的步骤自己摸清（TODO-AAXVAL，owner 实测后回填三个常量并删掉本段 TODO）：

1. 把工具包解压到**仓库外**，例如 `$env:USERPROFILE\avid-tools\`。
2. 用 `Get-ChildItem -Recurse` 找到可执行入口（`dsh.exe`）、aaxval 模块和随包文档。
3. 依次试 `-h`、`--help`、`/?`；进入交互环境后试 `help`，再确认加载 aaxval 模块的命令（推测，待验证）。
4. 弄清是否要先把插件装进 Avid 的 Plug-Ins 目录、是否要求签名件或 iLok。
5. 定下非交互调用方式和成功 / 失败的输出判据，回填脚本头部常量；顺带确认工具输出的编码（UTF-16 或夹带控制字符时
   正则可能永远匹配不到）。
6. 只记录**我们自己写的**命令和判据；不要复制或改写 Avid 的文档与测试计划原文。

## CI 对照

CI（`.github/workflows/ci.yml`，job `build-and-validate`）与上述步骤同构：clone JUCE（版本读 `.juce-version`，`actions/cache` 命中时跳过）→ 装 WebView2 Evergreen Runtime → CMake 配置（vcpkg toolchain 按 `vcpkg.json` 装 ixwebsocket，二进制缓存经 `actions/cache` 复用；随后断言装进来的版本 == `vcpkg.json` 的 override）→ 构建 → pluginval `--skip-gui-tests`（strictness 5）。缓存只是加速，miss 时照常 clone / 编译。含 WebView2 编辑器的全量 strictness-5 在真实 Win11 本地验证——无桌面的 Server runner 无法托管编辑器。

AAX 方面，同一个 job 在 VST3 打包冒烟之后另有三步（AAX 由同一次 `cmake --build` 产出）：

- **6c 打包冒烟**（产物丢弃）：`package-aax.ps1 -Mode Unsigned` 按 `0.0.0-ci → 0.0.0-ci2 → 0.0.0-ci` 三连跑，断言 `.sha256`
  字节形态与 summary 按段去重，抽查 zip 层级与 `INSTALL-AAX.txt` 的 UNSIGNED 横幅（脚本自带 PE x64 与 bundle 结构断言）；
  再做**反向断言**：`-Mode Signed` 必须因签名检查拒收同一个未签名 bundle，且不留发行名 zip。
- **6d 打未签名包**（只在 push / `workflow_dispatch` 下运行）：版本 = CMake `VERSION` + `-ci.<短 sha>`，`INSTALL-AAX.txt`
  的源码链接钉本次构建的完整 commit sha。
- **6e 上传** artifact `aax-unsigned-win64`（`-UNSIGNED.zip` + `.sha256`，保留 30 天；事件条件同 6d）。名字刻意不叫 `dist-*`，
  `release.yml` 的 `publish` 不会取它；在子分支上 `workflow_dispatch` 一次即可取到测试件。pull_request 构建的是与 `dev` 的
  合并提交（`refs/pull/N/merge`），不是 PR head，源码链接与版本号都对不上字节，所以 PR 上只跑 6c 冒烟、不出测试件 ——
  与签名脚本来源核对拒收 pull_request run 同口径。

pluginval 无法托管 AAX，所以 CI 不对 AAX 跑它；Pro Tools 里的验收靠手工，见 [DAW_TEST_GUIDE.md](DAW_TEST_GUIDE.md#pro-toolsaax实测windows--macos)。
