# Changelog

> **v1.3.1 及更早版本的 git 历史与 Release 位于 Synchain 私有单体仓库(`DLsnows/Synchain`)。** 本文件仅回填这些版本的 release body 文字内容;旧 tag 不迁移到本仓(D6 全新首 commit,08 §3.4)。
>
> 首个公开版本 = **v1.4.0**(U6)。协议类改动记录在对应版本的「契约变更」小节。

## [未发布]

> 本段含两批改动:① 转 public 前的合规/安全整备(本身不改版本号);② **macOS 支持**,版本号随之由 1.4.0
> 升至 **1.5.0**(`CMakeLists.txt` 的 `project(... VERSION)` 是唯一真源)。两批**均不涉及契约变更**
> (wire 协议零改动)。

### 新增

- **macOS(Apple Silicon)支持**:同时构建 **VST3 + AU**(`FORMATS VST3 AU`,AU 类型显式写死
  `AU_MAIN_TYPE kAudioUnitType_Effect`,即 `aufx`),UI 走系统 **WKWebView**;目标架构 `arm64`,
  部署目标 macOS **11.0**(Big Sur,arm64 Mac 的物理下限)。安装位置为
  `~/Library/Audio/Plug-Ins/VST3` 与 `~/Library/Audio/Plug-Ins/Components`。
- **macOS 版本不签名、不公证**(沿用 v1 的不签名决策)。自己构建的 bundle 不带 quarantine,从 Releases
  下载来的 zip 才需要 `xattr -dr com.apple.quarantine` 解除一次隔离(README 的「安装」一节有完整命令;
  装到 `/Library` 全局路径时两条命令都要 `sudo`,家目录则不需要)。
- **macOS 已知限制**(README 双语各有详述):① 仅 arm64 —— Intel Mac 不支持,且在 Apple Silicon 上给
  DAW 勾「使用 Rosetta 打开」**同样加载不了**(Rosetta 宿主装不下 arm64 插件);② AU **不申报 sandbox-safe**
  (插件需 bind `127.0.0.1` 监听 socket 并托管 WebView,两者在 AU sandbox 内都会被拒),GarageBand 可能拒载,
  请用 Logic / Reaper / Live 等;③ **Safari 预计连不上桥**(尚未真机验证):https 页面连明文
  `ws://127.0.0.1`,与 Chromium 不同 Safari 未知对回环开 mixed content 豁免,mac 上建议用
  Chrome / Edge / Firefox 打开 Creative Space(这些浏览器首次也可能弹本地网络访问授权)。
  该条按**推断**标注,验证状态与反馈方式见 `docs/build-macos.md` 的「关键坑」第 5 条。
- 新增 `docs/build-macos.md`:前置依赖、配置构建命令、`ditto` 安装、`auval` 与全量(含 GUI)pluginval 验收
  (VST3 与 AU 各跑一次)、可选的 universal / Origin 注入覆盖、关键坑。

### 安全

- **Origin 白名单改「构建期注入」(决策 U4)**:`isAllowedOrigin()` 的默认白名单在仓库源码里只保留
  `synchain.cn` / `synchain.ca` 系精确域与本地回环(`localhost` / `127.0.0.1` / `[::1]`);部署平台的预览域名等
  额外来源不再硬编码进源码,改由配置期 `-DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS` 注入(见 `docs/build-windows.md`)。
  **默认构建不放行任何额外来源**,CSWSH 防护的其余语义(空 Origin 放行、拒 `null` 字面量、非 https 远程一律拒、
  大小写归一)完全不变。
- **通配段不再跨 `.`**:`*` 只匹配单个 DNS 标签内的一段非空字符。此前 `a-*-b.example.app` 会连
  `a-x.evil.com-b.example.app` 一起放行(通配区可含点),与文档描述的「通配**段**」不符;现补上
  「通配区不得含 `.`」的检查,实现与文档对齐。
- **注入模式须带真实域名锚点**:此前 fail-closed 只丢弃空段、多 `*` 与恰为 `"*"` 的模式,字面量全是标点的
  模式仍会通过并等效于开门 —— 例如 `*.` 会放行任何以 `.` 结尾的 host(浏览器对带尾点的 FQDN 确实原样发出
  `Origin: https://evil.com.`),`-*` / `*-` 只需 host 以 `-` 开头/结尾。现要求模式去掉 `*` 后的字面量含 `.`
  且末段是长度 ≥2 的纯字母 TLD,并拒绝以 `.` 结尾的模式。
- **注入模式的通配收紧到「最左 label + ≥2 段锚点」**:上一条的「末段是纯字母 TLD」仍拦不住把整个最左
  label 吃掉的模式 —— `*.com` 会放行**任意** `.com` 域,`*example.app` 会放行 `evilexample.app`。现要求
  含 `*` 的模式满足两条:`*` 落在最左 label 内(位置在第一个 `.` 之前),且第一个 `.` 之后的锚点自身仍含
  `.`(≥2 段)。故 `*.com` / `*example.app` / `preview.*.example.app` 一律 fail-closed 丢弃,
  `*.example.app` 与 `example-git-*-team.example.app` 照旧可用。无 `*` 的精确 host 模式行为不变。
- **Origin host 归一化剥掉 FQDN 尾点**:`https://synchain.cn.` 与 `https://synchain.cn` 现按同一来源判定,
  同时堵掉「尾点形式撞上宽模式」的绕过面。
- **Origin 匹配逻辑抽成可测头文件**:归一化 / 模式可用性 / 模式匹配移到新的 `src/OriginAllowlist.h`
  (`synchain::origin`,纯标准库,零 JUCE / ixwebsocket 依赖),业务语境的 `isAllowedOrigin()` 留在
  `src/VstBridgeServer.cpp` 调用它 —— 行为零变化。新增 `tests/origin_allowlist_selftest.cpp`(51 条断言)
  与 CMake 选项 `BRIDGE_BUILD_SELFTESTS`(默认 OFF),由 `scripts/gates.ps1` 的 gate 5b 构建并运行。

### 构建

- 新增 CMake cache 变量 `BRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS`(`;` 或 `,` 分隔的 host 模式,每个至多一个 `*`
  通配段,通配段须非空且不跨 `.`)。为空(默认)时不定义同名编译宏,Windows 构建行为与既有版本一致。
- 该注入值改经 **`configure_file` 生成的 `BridgeOriginConfig.h`** 落地,不再走带引号的
  `target_compile_definitions` —— 字符串定义里的双引号在 Visual Studio 与 Ninja/Makefile 生成器下转义路径不同,
  生成头则各生成器逐字节一致。值含双引号或反斜杠时配置期 `FATAL_ERROR`。
- **依赖按平台分支,但版本不分叉**:macOS 用 CMake `FetchContent` 拉取 ixwebsocket(由 `IXWEBSOCKET_TAG`
  钉死到 40 位 commit SHA,= 上游 tag **`v12.0.1`**;不用可变的 tag 名,同 action 的 SHA pin 口径 —— 与 Windows 侧 vcpkg `x64-windows-static` 实际安装的版本相同,两平台跑同一个
  WebSocket 实现的同一版本,permessage-deflate 协商 / close code / handshake header 解析这些 wire 层行为
  才是单一契约)。mac 侧另关掉 `USE_TLS` —— 桥 #2 只在 `127.0.0.1` 上服务明文 `ws://`,因此不链接 mbedtls、
  不需要 Security.framework,压缩用的 zlib 取 macOS SDK 自带系统库;并写死 `BUILD_SHARED_LIBS=OFF`,
  避免外层 `-DBUILD_SHARED_LIBS=ON` 把 ixwebsocket 变成不会被拷进 bundle、也无 rpath 处理的 dylib。
  **Windows 依赖链路完全不变**:仍是 vcpkg `x64-windows-static` 的 `find_package(ixwebsocket)`。
- 新增 CMake cache 变量 `CMAKE_OSX_ARCHITECTURES`(默认 `arm64`)与 `CMAKE_OSX_DEPLOYMENT_TARGET`(默认 `11.0`),
  均带 `NOT DEFINED` 守卫、置于 `project()` 之前(要参与编译器探测),命令行可覆盖;`IXWEBSOCKET_TAG` 只在
  `if(APPLE)` 分支内定义。**对 Windows 构建为 no-op**:VS2019 生成器下 configure 的 cache 差异只有前两个
  变量,生成的 `.sln` / `.vcxproj` 目标列表与改动前逐项相同、无任何 `*_AU*` 目标。

### 持续集成

- `ci.yml` 新增与 `build-and-validate` 同级的 **`build-and-validate-macos`**(`macos-15`,arm64 原生):
  Ninja 配置 → 构建 → **clang 零警告门** → arm64-only 架构断言 → pluginval 验 VST3 + `auval` 验 AU →
  三档 artifact(pr / dev 快照 / preview),条件与保留天数与 windows job 逐一对齐。现有 windows job 与
  `on:` 触发面**一行未改**。
  - clang 零警告门与 windows 的 `/W4` 门**同构**:黑名单式(只排除 `_deps` / `JUCE` / `vcpkg`,其余一律算),
    且只认编译器诊断行 `file:line:col: warning:`(与 windows 只匹配 `warning Cxxxx`、不匹配 `LNK4xxx` 同口径);
    排除模式写成 `(^|/)`,同时覆盖 Ninja 写出的相对路径 `_deps/...` 与绝对路径。
  - AU 的四字码不写死:`auval` 的 type / subtype / manufacturer 由 `CMakeLists.txt` 的
    `AU_MAIN_TYPE` / `PLUGIN_CODE` / `PLUGIN_MANUFACTURER_CODE` 现读,改码时 CI 报确切解析错误,
    而不是退化成语义无关的「auval 没报 SUCCEEDED」。
  - artifact 里的 zip 用 `ditto -c -k --norsrc --noextattr` 压(`upload-artifact` 不保留 POSIX 权限位,
    直接传 bundle 目录 = 下载方拿到不可执行的死壳);内层 zip 名带 ref slug 与短 sha,不同 PR 的产物
    解压到同一目录不再互相覆盖。
- **成本**:macOS runner 按 10 倍分钟数计费,该 job 当前继承整个 workflow 的触发面(每次 PR synchronize +
  push 到 `dev` / `feature/**`)全开,与 `CLAUDE.md` §4「runner 就低不就高」存在张力 —— 已在 §4 记为
  **待用户拍板的例外**,未擅自加 label 闸门。
- `CLAUDE.md` §1(fork 可跑 job 清单)、§4(触发范围与成本纪律)、§6(环境与依赖的 macOS 侧)随之更新;
  §0 安全铁律(三仓逐字相同)一字未动。
- `BEFORE_PUBLIC_CHECKLIST.md` 新增 §3.1:第三方 action pin 到 40 位 SHA 升为**转 public 硬门禁**并列出
  当前未 pin 的文件清单与验收断言(现状是只有 `release.yml` 与 mac job 做到了)。

### 发布 / 分发(对下游可见)

- **Release 页面新增 macOS 资产**:`SynchainBridge-VST3-AU-v<版本>-macos-arm64.zip` 及同名 `.sha256`
  (zip 内含 `Synchain Bridge.vst3` + `Synchain Bridge.component` + 与 Windows 侧同一组合规文件
  `LICENSE.txt` / `THIRD-PARTY-NOTICES.md` / `LICENSES/OFL-1.1.txt` / `INSTALL.txt`)。
  Windows 资产名与内容不变。
- **Release 标题变更**:`Synchain Bridge VST3 <tag> (Windows x64)` → `Synchain Bridge <tag> (Windows x64 · macOS arm64)`。
- **`release.yml` 由 1 个 job 拆成 4 段**:`gate`(版本门禁,`ubuntu-latest`)→ `release`(windows-2022)
  ∥ `release-macos`(macos-15)→ `publish`(`ubuntu-latest`,建 draft Release)。
  权限收敛:workflow 级降为 `contents: read`,`contents: write` 只授给 `publish` 一个 job ——
  跑第三方代码(JUCE / vcpkg / pluginval)的构建 job 一律拿不到写 Release 的权限。
- **⚠️ 行为权衡**:`publish` 是 `needs: [release, release-macos]`,**任一平台失败 = 整个 tag 一个产物
  都发不出去**,包括已成功的 Windows zip(旧实现里 windows job 自带 `softprops`,能独立出 Release)。
  换来的是权限收敛与「两平台产物一次性挂进同一个 Release」。两个构建 job 的 `timeout-minutes` 对齐到 60。
  处理办法(删 tag 重打)与「若要改成 mac 挂了 Windows 仍能发」的改法都写进了 `docs/release.md` §6.1。
- 新增 `scripts/package-macos.sh`:macOS 打包唯一真源,与 `scripts/package.ps1` 六条硬要求逐条对齐,
  另加 arm64-only 断言与全程 `ditto`(`cp -r` / `zip -r` 会丢符号链接与可执行位,用户解压后拿到的是
  加载不了的死壳)。压缩用 `ditto -c -k --norsrc --noextattr`:`--sequesterRsrc` 会把资源叉/扩展属性
  写进 `__MACOSX/`,那些条目权限恒为 `-rw-r--r--` 且同样匹配可执行位断言的筛选,会让打包**必然假失败**,
  也会给用户塞一堆垃圾。`--version` 传空串直接 die(不回落到 CMake 版本),避免产出版本号对不上的资产。
- **注入面加固覆盖到 `release.yml`**:`gate` 的 tag 名、两个平台 Package 步骤的版本号、`publish` 的
  job summary 全部改经 step `env` 间接读入。tag 允许 `$`、反引号、`"`,直插 bash 双引号串会真做命令替换,
  直插 pwsh 可闭合引号 —— 与 `ci.yml` 对 `github.ref_name` 的加固同口径,不能只加固一处。
- `docs/release.md`:新增 §5.1 冒烟 tag(`v0.0.0-test`)端到端实跑流程、§6.1 「任一平台失败 = 整个 tag
  无产物」的处理办法;macOS 构建段改为链到 `docs/build-macos.md`(与 Windows 侧结构对称,不再内联命令
  导致两份说明漂移);`auval` 四字码补明与 `CMakeLists.txt` 三个构造的对应关系与同步清单。

### 兼容性

- **无契约变更**:桥 #1 / 桥 #2 的 wire 协议与 `BRIDGE_CONTRACT_VERSION = "2.0"` 均零改动。
- 与 v1.4.0 工程完全兼容:厂商码/插件码(`Snch` / `Snb1`)与 `BUNDLE_ID`(`com.synchain.bridge`)未变,
  已有 DAW 工程无需重建。
- macOS 的 AU 是**新增格式**,首次出现即为本版本,不存在旧 AU 实例的迁移问题。

### 文档 / 合规

- 内嵌的拉丁正文/等宽子集字体按 OFL-1.1 §3(Reserved Font Name)改名分发:`BridgeSans.woff2` /
  `BridgeMono.woff2`,`@font-face` family 改为 `Bridge Sans` / `Bridge Mono`;来源家族与逐家族 RFN 核验见
  `THIRD-PARTY-NOTICES.md`。Space Grotesk(无 RFN)与 Noto Sans SC(RFN "Source")命名不受影响。
- **改名深入到 woff2 `name` 表**:§3 限制的是「呈现给用户的主字体名」,只改文件名与 CSS family 不够 ——
  两个二进制的 nameID 1/3/4/6/16/17 此前仍是上游家族名与其 PostScript 名(即仍带保留字体名)。
  现由 `scripts/fetch_fonts.py` 的 `rename_font()` 用 fontTools 重写这几条(带 fail-closed 断言),
  nameID 0(上游版权)与 14(许可证 URL)逐字保留,并补齐上游子集缺失的 nameID 13(OFL 许可证声明)。
  重新生成字体现需 `pip install "fonttools[woff]"`。
- **RFN 断言进门禁**:新增 `scripts/check-font-names.py`,用 fontTools 解开四个 woff2 的 `name` 表,
  断言呈现名(nameID 1/3/4/6/16/17)不含各家族 RFN(Space Grotesk 无 RFN 跳过);nameID 0/13/14 不参与
  ——OFL 惯例的版权行本身含 `with Reserved Font Name` 字样,那是 §2 署名。已接进 `scripts/gates.ps1`
  与 `compliance` workflow(依赖 `fonttools` + `brotli`,brotli 是解 woff2 的必需项)。
  同时修掉 `fetch_fonts.py` 生成期断言的两个漏洞:它此前把 nameID 0/13/14 里的合法署名当成残留误报,
  且 RFN 比对区分大小写(上游写成 `PLEX` 会漏检),现改为排除 KEEP 三条 + 双侧 casefold。
- **OFL 条款编号更正**:`THIRD-PARTY-NOTICES.md` 与 `web/fonts/README.md` 此前把「随拷贝附版权声明与许可证」
  写成 §4,实为 **§2**(§4 是禁止背书条款);本仓字体改名的 `chore(fonts)` 提交 message 里同样的错引以本条为准。
- `THIRD-PARTY-NOTICES.md`:补四款字体的 RFN 逐家族核验附注;许可证「核验来源」列由本机绝对路径改为上游权威公开引用,
  并把四款字体的引用钉到 `google/fonts` 的固定 commit、zlib 由官网当前版许可页改为 `madler/zlib` 的 `v1.3.2`
  tag(消除 `main` / 官网页的漂移引用)。
- `docs/DAW_TEST_GUIDE.md`:测试主步骤改为直接用 dev 部署 —— 默认构建不放行预览域,照旧写法会先撞 4403 才看到排障条。
- `BRIDGE_CONTRACT.md` §三登记表同步(**patch 级:纯文档澄清,wire 零变化**):`VERSION` 行由 `1.4.0` 补到
  当前真源 `1.5.0`、「产物」行登记 macOS 的 `Synchain Bridge.component`(AU)。为防这行再漂,`scripts/gates.ps1`
  的 gate 3e 把该行一并纳入版本一致性断言(此前只比 CMake ↔ web-preview 三处镜像)。
- README(双语)与 `docs/build-windows.md` 由「v1 只发布 Windows」更新为双平台:系统要求、安装、从源码构建各
  拆出 Windows / macOS 小节,并新增「macOS 已知限制」章节(两份 README 的标题层级保持对等)。
  **预编译分发同步扩到 mac**:「安装」一节改成两平台资产对照表(zip 名 + zip 内容 + 同名 `.sha256`),
  「状态」一节由「mac 只能从源码构建」改为「随 Windows zip 一同发布」;quarantine 步骤补上全局路径
  需 `sudo`、家目录不需要的区别;厂商码/插件码不可改动的警告仍在 `## Install` 正文(两个平台都适用)。
- `THIRD-PARTY-NOTICES.md`:补平台归属 —— mbedtls / vcpkg zlib / WebView2 SDK 三项标注**仅 Windows 构建**
  链接;macOS 闭包改为**差集派生**:「上表全部条目 − 标注『仅 Windows 构建』的三项」,不再正向枚举
  (正向清单会漏掉同样被编进 mac `.vst3` / `.component` 的四份 OFL-1.1 字体子集与 AGPL 的 JUCE JS helper ——
  `juce_add_binary_data` 不按平台分支)。ixwebsocket 的 Windows / macOS 两行合并回一行(同为 12.0.1)。
- 文档里对 `CMakeLists.txt` 的引用统一改为**按 CMake 构造名定位、不写行号**
  (`docs/webview-ui-pattern.md` §C、`docs/build-windows.md`、`docs/build-macos.md`、`docs/release.md`):
  本次加 macOS 支持把 `project()` 之后的内容整体推下 12～48 行,原有行号引用全部失准且不会自证失效。
- `docs/build-macos.md`:pluginval 命令改为 `./pluginval.app/Contents/MacOS/pluginval`
  (`pluginval_macOS.zip` 解压出来只有 `pluginval.app`,没有裸可执行文件,且需先解 quarantine),
  并补一条同参的 `.component`(AU)验收 —— AU 是本版本唯一的新格式;`ditto` 覆盖安装前补 `rm -rf` 旧 bundle
  (`ditto` 对已存在目录是合并语义,旧文件会残留),README 双语同步。
- `web-preview/` 的版本镜像(`mock-server.mjs` 的 `PLUGIN_VERSION`、`package.json`、`package-lock.json`)
  随真源升到 1.5.0,并在 `scripts/gates.ps1` 新增 **gate 3e「版本一致性(CMake ↔ web-preview)」**断言这三处 ——
  此前没有任何门禁覆盖(CI 的版本门禁只在打 tag 时比 tag ↔ CMake)。
- **遗留(待后续任务或 A2 一并处理)**:仓库已是双平台,但 `scripts/gates.ps1` 仍是纯 Windows 实现
  (依赖 vswhere / VS 生成器 / nuget / `pluginval.exe`),mac 贡献者跑不了;`CLAUDE.md` §2(本地 gates)、
  `docs/DAW_TEST_GUIDE.md`(仍写 win64.zip)、README 文档清单里 DAW_TEST_GUIDE 的「(Windows)」注记
  同样待更新。(`CLAUDE.md` §1 / §4 / §6 已随 CI 与发版链路改动更新;三仓逐字相同的 §0 安全铁律不动。)
- 兜底面板(`FallbackPanel`)的**加载超时**文案改为平台中立(不再提 WebView);「缺 WebView2 运行时」分支的
  文案保留 WebView2 表述 —— 该分支只可能在 Windows 出现。

## [1.4.0] — 首个公开版本

**首个在 `synchain-oss/synchain-bridge` 公开发布的版本。** 插件二进制与 v1.3.1 完全兼容:厂商码/插件码(`Snch` / `Snb1`)、`BUNDLE_ID`(`com.synchain.bridge`)与 wire 协议均未变,现有 DAW 工程无需重建。

### 新增

- 公开的 GitHub Release 分发渠道(tag `v1.4.0`,zip + sha256 草稿 Release,`release.yml`)。
- `web-preview/`:可脱离 DAW 独立预览 UI / 桥 #2 的 mock server(仅依赖 `ws`)。
- 独立仓库结构:源码迁入 `src/`,双语 README、CONTRIBUTING、SECURITY、CODE_OF_CONDUCT、CLAUDE、CHANGELOG 等协作文档齐备。
- 本版本不签名(U13);zip 内随附 LICENSE / THIRD-PARTY-NOTICES 与字体 OFL 全文。

### 契约变更

- 引入独立协议版本号 `BRIDGE_CONTRACT_VERSION = "2.0"`(与插件版本解耦);`status` 帧新增**可选字段** `contract:"2.0"`(只增不改,旧客户端 `??` 兜底忽略)。起点取 2.0:1.x 语义留给抽取前未版本化的历史。

### 兼容性

- 与 v1.3.1 完全兼容(见上);协议 2.0 为纯增量,对旧网页客户端零破坏。

## [1.3.1] — 2026-07-08(源仓库)

### 变更

- **版本号统一到单一真源**:`CMakeLists.txt` `project(VERSION 1.3.1)` → `JucePlugin_VersionString`,删除会漂移的手写常量 `plugin::Version="1.2.10"`。插件自身 WebView UI 与网页端现在都动态显示 v1.3.1。
- **兼容基线从 1.3.1 起**(不再兼容更早插件版本)。
- 基于 v1.3.0 的安全加固(Synchain issue 167 CSWSH 白名单 / issue 168 processBlock 实时安全 SPSC / issue 169 交织越界 / issue 170 心跳)。

## [1.3.0] — 2026-07-07(源仓库)

安全与实时稳定性加固版。

### 安全

- **Synchain issue 167(P1)CSWSH 防护**:本地 WebSocket 桥(`ws://127.0.0.1:9420`)严格校验握手 `Origin` —— 仅放行 prod 域 `synchain.cn` / `synchain.ca`、dev 域 `dev.synchain.cn` / `dev.synchain.ca`、精确匹配的 Vercel preview 前缀,以及 `localhost` / `127.0.0.1`。任意网页对插件桥的跨站 WebSocket 握手(CSWSH)被拒绝。(历史条目按原 release body 保留;**该 preview 前缀已于转 public 前移出源码,改为构建期注入** —— 见 [未发布] 段「Origin 白名单改『构建期注入』」。)

### 实时音频稳定性

- **Synchain issue 168(P1)processBlock 实时安全**:音频回调改走无锁 SPSC 环形缓冲(`juce::AbstractFifo`),发送线程仅在 start/stop 时创建/销毁 —— 音频线程内不再有锁、堆分配或阻塞调用。
- **Synchain issue 169 交织缓冲越界修复**:多声道交织写入的边界修正,消除潜在越界访问。
- **Synchain issue 170 心跳保活**:桥连接加入心跳机制,及时发现并处理断连。

## [1.2.10] — 2026-07-06(源仓库)

在 v1.2.0 基础上大量修复与增强,聚合 v1.2.1–v1.2.9 的改动。

### 连接性 / 前端(关键修复)

- **修「前端打不开 / 报无法打开此页」根因**:Windows 显式 `withBackend(webview2)`,不再回退到旧 IE 控件;加运行时探测 + 加载看门狗 + 兜底面板(缺运行时时引导安装)。
- **修 Windows 连不上房间**:桥接客户端由 `localhost` 改直连 `127.0.0.1`(避开 `localhost`→IPv6 `::1` 解析抖动)。

### 界面 / 电平表

- 电平表重做:按真实声道数渲染(单声道 1 条 / 立体声 2 条)、实时弹道 + 白色峰值保持线、未传输时归零。
- 铺满窗口 + **界面缩放档位 33%–300%**(固定设计盒 × zoom,高 DPI 稳健,无滚动条 / 黑边);尺寸**全局持久化**(新实例沿用);改档位有防呆确认弹窗(10s 自动恢复)。
- 连接状态灯反映**真实连接**(浏览器断开即回落「等待连接」);声道数**真实上报**(修此前网页恒显「立体声」)。

### 音量

- DAW 音量双向实时同步(网页音量条 ↔ 插件 `masterGain`),且避免回环/双向拖动打架;web→VST 音量改由编辑器 Timer 应用(修 `MessageManager::callAsync` 某些宿主不可靠执行)。

## [1.2.0] — 2026-07-02(源仓库)

首个 GitHub Release(Windows x64)。

### 功能

- WebView 玻璃拟态 UI(近乎复刻设计稿),中 / EN / FR 三语可切换并持久化。
- L/R 立体声电平表(dBFS,反映推流后电平)、采样率 / 声道 / 延迟实时显示。
- 主控音量 0–200%(可自动化,**只影响推流副本**,DAW 轨道穿透音频零改动)。
- 可编辑本地端口(默认 9420,占用自动避让)。
- 状态随工程保存。

### 验证

- 本地:VS2019 + JUCE 8.0.8 构建,`pluginval --strictness-level 5`(含 WebView2 编辑器)**全量通过**。
- CI(windows-2022):构建 + `pluginval --skip-gui-tests` strictness-5 通过(无头 Server 无法托管 WebView2 编辑器,编辑器在本地 Win11 验证)。

<!-- dco negative-path probe: 本行由 test/dco-negative 分支临时添加，验证后随分支删除 -->
