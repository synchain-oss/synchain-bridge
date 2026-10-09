# Changelog

> **v1.3.1 及更早版本的 git 历史与 Release 位于 Synchain 私有单体仓库(`DLsnows/Synchain`)。** 本文件仅回填这些版本的 release body 文字内容;旧 tag 不迁移到本仓(D6 全新首 commit,08 §3.4)。
>
> 首个公开版本 = **v1.4.0**(U6)。协议类改动记录在对应版本的「契约变更」小节。

## [未发布]

<!-- AAX 线(feature/aax)的小节骨架:各子分支只往自己负责的小节追加,不新增/重排小节
     (「修复」由 AAX-08 经主控同意补进骨架);切版时把仍为空的小节删掉。 -->

### 新增

- **AAX(Avid Pro Tools)格式,Beta**:Windows x64 与 macOS arm64 都构建 AAX 目标(CMake 选项
  `SYNCHAIN_BRIDGE_AAX`,两平台默认 ON,`-DSYNCHAIN_BRIDGE_AAX=OFF` 可整体关掉)。SDK 用 JUCE 8.0.8
  自带的 AAX SDK 2.8.0(GPLv3 选项),不引外部 SDK、构建零 secret。产物**未签名**:PACE 签名之前只有
  Pro Tools Developer 能加载。JUCE 不支持 AAX 的平台照常静默跳过;若开关打开、平台也支持、目标却没建出来
  (例如升 JUCE 后过滤逻辑变了),configure 直接 FATAL,不会静默丢格式。
  - 身份:`AAX_IDENTIFIER com.synchain.bridge`,厂商/产品码沿用 `Snch` / `Snb1`;类别
    `AAX_ePlugInCategory_None`(SDK 没有 Analyzer/Utility 类,Pro Tools 按类别组织菜单时归入 "Other");
    禁用 multi-mono(否则立体声/环绕轨会按声道各开一个实例、各起一个 WebSocket 服务);不注册 AudioSuite
    (`JucePlugin_AAXDisableAudioSuite=1`,只加在 AAX wrapper 目标上)。
  - 声道:AAX 下只接受 mono→mono 与 stereo→stereo,即只登记 PlugIn ID `jcbb` / `jccc` 两个 stem 组合。
    PlugIn ID 会写进 Pro Tools 会话,**发布后只能加、不能删**。
  - 离线渲染:AAX 下宿主进入 non-realtime(offline bounce / Track Commit / Freeze)期间,音频原样直通,
    不计量、不推流,避免快于实时的数据灌进推流队列把接收端冲乱。
  - 诊断:新增 4 条按事件触发、只在 message 线程写的日志(前缀 `SynchainBridge:`,Windows 下经
    `OutputDebugString`,DebugView 可见)—— 开窗时的宿主 / 封装格式 / 尺寸 / 缩放 / 声道 / 全局缩放;
    缩放档位被宿主拒绝;音频设置(采样率 / 声道 / 延迟)变化;宿主 non-realtime 状态切换。音频线程零改动。
- 插件界面文案不再写死格式与旧版本号:副标题 `VST3 · AUDIO BRIDGE` → `DAW · AUDIO BRIDGE`;
  角标 `Synchain VST · v…` → `Synchain Bridge · v…`,首帧占位不再显示写死的 `v1.3.1`。

### 修复

- **AAX(Windows):系统显示缩放非 100%(实测 175%)时 Pro Tools 插件窗只显示网页左上约 57%**,右侧与下方被裁。
  根因是 WebView2 的光栅化缩放与 JUCE peer 缩放不一致:Pro Tools 是 System DPI-aware,JUCE peer 在它里面的物理/逻辑比为 1
  (编辑器 460 逻辑像素 = 460 物理像素);JUCE 的 WebView2 后端只设 bounds、不设 RasterizationScale,WebView2 按显示器缩放
  (1.75)光栅化,CSS 视口只剩约 263 px;网页按固定设计盒 460×560 × zoom(uiScale) 排版、不读视口,于是被裁。per-monitor
  DPI-aware 宿主(多数 VST3 宿主)里两者一致,所以一直没暴露。修复只在原生侧、只对 Windows AAX 生效:编辑器第一次挂上原生
  窗口时算补偿系数 comp = 显示器有效 DPI 缩放 / JUCE peer 缩放,编辑器尺寸改为 设计尺寸 × uiScale × comp(175% 下
  805×980),JUCE AAX 封装随之让 Pro Tools 把容器调大,WebView 视口回到 460×560 CSS px。comp 只在运行期用、不持久化;
  回报网页的 `uiScale` 与 `setUiScale` 回执的 `w` / `h` 都不含它,`web/` 与桥 #1 契约不变。
  - 诊断:开窗时各写一次 `editor peer: platformScale=… desktopScale=… logical=WxH`(所有格式)与
    `aax dpi compensation: monitorScale=… peerScale=… comp=… logical=WxH`(仅 Windows AAX),都在 message 线程。
  - 已知限制:插件窗拖到另一块 DPI 不同的显示器时不会重算(System-aware 宿主本来也收不到 per-monitor 的 DPI 变化),关掉重开即可。
- **AAX(Windows):构建期回移上游 JUCE 提交
  [`20872887e`](https://github.com/juce-framework/JUCE/commit/20872887e7b8e889b192cb3c4a435c99ec4e16e8)**(JUCE 9 才带,
  8.0.x 线没有):JUCE 8.0.8 的 AAX 封装报给宿主的编辑器尺寸只乘了 JUCE 全局缩放、漏乘窗口的平台 DPI 缩放,per-monitor
  DPI-aware 的宿主里插件窗会被裁。当前 Pro Tools 是 System DPI-aware、peer 平台缩放为 1,这个补丁在它里面不起作用(上一条才是
  Pro Tools 175% 的修复),保留是为 per-monitor-aware 宿主。`CMakeLists.txt` 只在 Windows + AAX 目标 + JUCE < 9 时读 JUCE
  原文件、按上游三处逐块替换(任一处对不上 configure 即 FATAL),生成到构建目录 `_deps/juce-aax-patched/` 并替代原文件编进
  AAX 目标。不升 JUCE、不改 JUCE 目录;VST3 / AU 与 macOS AAX 产物不受影响。升 JUCE 9 时整段删除。
- **插件界面:「界面缩放」下拉展开后的选项列表是浏览器默认样式**,与玻璃拟态界面不一致(在 Pro Tools AAX 里发现,所有宿主、
  所有格式都有)。原因是 `web/styles.css` 只给收起态的下拉去了原生外观,`option` 和弹出层没有样式,WebView2 用 Chromium 原生弹窗画。
  修复只改 `web/styles.css`:
  - 支持 `appearance: base-select` 的引擎(本机实测 Edge / WebView2 运行时 154)走 customizable select:列表在页面内渲染成与面板
    一致的玻璃面板(半透明浅色底 + 背景模糊,描边、圆角与卡片同系,等宽字体),选中项(✓ + 深一档底色)与悬停 / 键盘焦点项分得清,
    最多显示约 8 行、其余滚动。弹层在 top layer,不被卡片的 `overflow: hidden` 裁切;又随下拉继承卡片的 `zoom`,任意缩放档位都与
    界面同比例。收起态外观不变,自带的 `::picker-icon` 已隐藏,只留原来的小箭头。
  - 不支持的环境(旧版 WebView2,以及尚不支持该特性的 WKWebView)仍用原生弹窗,只给 `option` 设底色与字色,Windows 上的原生列表
    会随之贴近淡紫配色。
  - 行为不变:仍是同一个 `<select>`,`change` → 10 秒防呆确认、`aria-label`、桥 #1 契约都没动。唯一差别在键盘:增强路径下收起态
    按 ↑/↓ 先展开列表(列表内 ↑/↓ 移动、Enter 选定、Esc 关闭),不再像 Windows 原生下拉那样一按就换档并弹防呆确认。

### 安全

- **AAX 本机签名脚本 `scripts/sign-aax.ps1`(Windows x64)与 `scripts/sign-aax-macos.sh`(macOS arm64)**:把 CI 产出的
  `-UNSIGNED.zip` 经 PACE wraptool 签名,再交给 `package-aax.ps1 -Mode Signed` / `package-aax-macos.sh --mode signed` 出发行包。
  **U13 例外**:AAX 是本项目唯一签名的格式(零售版 Pro Tools 只加载 PACE 签名件),VST3 / AU 仍不签名不公证;签名只由维护者
  在本机手工执行,CI 不调用、流水线零 secret。
  - 凭据纪律:pfx 口令(及可选的 PACE 账号口令)只经 `Read-Host -AsSecureString` / `read -s` 交互读入,不进签名脚本的参数、
    日志、transcript 与 shell 历史(脚本不开 `Start-Transcript`、bash 侧显式 `set +x`)。但 wraptool 只收命令行参数,签名那几秒
    口令会以 `--keypassword`(`-KeyFile` 方式)或 `--pswd-no-save`(交互读入的账号口令)出现在 wraptool 的进程命令行里(本机进程
    列表短暂可见,wraptool 本身的限制),只在可信的单用户机器上签名、签名期间不要让他人登录本机;回显的命令里口令、PACE 账号与 wcguid 一律打码为 `****`,
    wraptool 自身的输出也逐行把这些值字面替换成 `****` 再显示(实测 `--verbose` 不回显口令,但回显 wcguid 与默认账号名);透传参数拒收
    含 `password` 的项和脚本自管的 flag(两平台都不区分大小写);Windows 的 pfx 必须在仓库目录之外(路径前缀 + git 公共目录
    两道判定,本仓库的其他 worktree 同样算仓库内)。
  - 预检(任一失败即退出 1):`.sha256` 逐字节格式 + 哈希(**只验完整性**:与 zip 同一份下载,防不了替换);从文件名解析版本;
    检出必须对应该版本(`-ci.<sha>` 件要求 HEAD 以该 sha 开头,其余版本要求 HEAD 上有 `v<版本>` tag),合规文件与 `scripts/`
    无未提交改动;**来源核对**(`-SourceRunId` / `--source-run-id`,可选,不给记 WARN):该 run 属于本仓库(非 fork)、是
    `ci.yml` / `release.yml`、结论 success、事件为 push / workflow_dispatch(pull_request 构建的是合并提交,不认)、
    `head_sha` 等于当前检出,再用 `gh run download` 取回它的 `aax-unsigned-*` artifact,同名 zip 必须与输入字节相同;
    wraptool 存在且 `help` 列出所需 flag;输入件确实未签名(Windows DLL 为 `NotSigned`;macOS arm64-only、无签名 Authority),且 `wraptool verify`
    必须失败(已签过的件重签会报错)。macOS 另要求钥匙串里与 `--signid` 同名的代码签名身份恰好 1 个。
  - 后检:`wraptool verify`;Windows 的 Authenticode 签名者指纹必须等于 `-CertThumbprint` / pfx 指纹、文件摘要默认必须是 SHA256 且时间戳为
    RFC 3161(`-LegacySha1Digest` 时为 SHA1)、默认要求带时间戳(`-AllowNoTimestamp`
    显式放行;拿不到也不事后用 signtool 补 —— 签名必须是最后一次修改);macOS `codesign --verify --deep --strict` 通过、
    `Authority=` 等于 `--signid` 且非 ad-hoc。打包后再解压回读复验,最后只**打印** `gh release upload` 命令,不自动上传;
    `-ci.<sha>` 件不给上传命令。成功删临时工作目录,失败保留供排查(里面只有 bundle,没有秘密)。
  - `-DryRun` / `--dry-run`:跑全部预检并汇总 PASS / WARN / FAIL,打印打码后的签名计划与打包脚本自己的 dry-run 输出;
    不读口令、不调用 `wraptool sign`、不产出文件。
  - Windows 侧已按 wraptool 6.0.1 实测对齐并完成首次真签名(见下面 AAX-17 / AAX-18 两条);仍未验证的项与 macOS 侧照搬的写法
    仍标 `TO-VALIDATE`,所有者核对后再删标记。
- **自签名代码签名证书助手 `scripts/new-selfsigned-codesign-cert.ps1`**(Windows 签名用的 Authenticode 证书):RSA 3072 /
  SHA256 / 默认 10 年,pfx 默认导出到 `$env:USERPROFILE\.synchain-signing\`,必须在仓库外(判定同签名脚本);脚本新建该目录时
  断开继承、只给当前用户完全控制;口令两次输入一致且至少 12 位;
  默认 AES256_SHA256 加密(wraptool 读不了时 `-PfxEncryption TripleDES_SHA1`);导出后用同一口令回读核对指纹;
  `-RemoveFromStore` 导出后把证书连同私钥从 `Cert:\CurrentUser\My` 删除。`SupportsShouldProcess` + `ConfirmImpact=High`:
  `-WhatIf` 只预演,不读口令、不写证书库、不生成文件。语法兼容 Windows PowerShell 5.1(文件带 UTF-8 BOM)。
  (`*.pfx` / `*.p12` / `*.pvk` 的 `.gitignore` 条目已随 AAX 打包脚本加入,见「发布 / 分发」。)
- **AAX 线终审修复(AAX-16)**:签名脚本在打包之后的步骤(回读复验等)失败时删掉本次产出的发行名 zip 与 `.sha256`;
  `sign-aax.ps1` 要求 pwsh 7.3+ 并对 wraptool 显式用 Standard 传参(含双引号 / 空格的口令不再被拆错),wraptool 输出里口令的
  转义形态与片段同样打码,git / gh 输出按 UTF-8 解码、来源核对只取 ASCII 字段(中文 Windows 下不再误报);gate 3h 中文文件名
  不再漏报、目录名不再误报;gate 5c 按当前 `-Config` 计数,AAX 开关为 OFF 时 `build.ps1 -InstallAax` 与 5c 报错而不用旧
  bundle(判据共用新增的 `scripts/aax-build-state.ps1`);`ci.yml` 的 pull_request 不再出 `aax-unsigned-*` 测试件;
  `docs/release.md` 补全借用 Mac 的清理清单、如实写明口令会出现在 wraptool 进程命令行里。上面各条已按修复后的行为改写。
- **签名脚本对齐 PACE wraptool 6.0.1 实测(AAX-17)**:`sign-aax.ps1` 的签名身份二选一 —— 新增 `-CertThumbprint <SHA1>`
  (推荐,经 `--signid` 用「个人」证书库里的证书,预检要求带私钥、未过期、用途含代码签名;不读证书口令,wraptool 命令行上不再有
  `--keypassword`),保留 `-KeyFile`;发布者二选一 —— `-WcGuid`,或 `-CustomerNumber` + `-CustomerName`(`-ProductName` 默认
  `Synchain Bridge`);`-Account` 改为可选(不给则用 iLok License Manager 的默认账号,wraptool 打印的默认账号名同样打码);
  `-PromptAccountPassword` 改经 `--pswd-no-save` 传,口令不写进 wraptool 的钥匙串(另一种用法:手动 `sync --password` 存一次)。
  wraptool 定位改为 `-WraptoolPath` → `PACE_FUSION_HOME\bin` → PATH → `%ProgramFiles%` 下版本号最高的 `Versions\<N>\bin`,
  进程里缺 `PACE_FUSION_HOME` 时从 Machine 级补上(两处都没有就 FAIL,提示新开终端);flag 检查改用 `wraptool help`(v6 里
  `help sign` 不合法)。Windows 上 verify / sign 对 bundle 里的内层 DLL 执行(wraptool 只收文件):整个 bundle 先复制到工作目录、
  对 DLL 原地签名,后检要求除 DLL 外逐字节不变、没有多出文件;未签名件的 verify 除了非零退出,还要求输出 NOT signed。透传参数
  另拦短写法与 `pswd`。`sign-aax-macos.sh` 同步(`help`、`--account` 可选、`--customer-number` 发布者方式、`--pswd-no-save`、
  `PACE_FUSION_HOME` 与 v6 默认路径候选;mac 上没法实测,仍标 TO-VALIDATE);`new-selfsigned-codesign-cert.ps1` 醒目打印
  Thumbprint、推荐 `-CertThumbprint`,加 `-RemoveFromStore` 时提醒之后只能用 `-KeyFile`。已实测的项去掉 TO-VALIDATE、注明实测
  日期;真签名能否成功、自签名证书签的件零售版 Pro Tools 是否接受、`--verbose` 是否回显参数、已签名件 verify 的退出码仍标
  TO-VALIDATE(待首次真签名;除零售版 Pro Tools 一项外已在 AAX-18 实测,见下一条)。上面各条已按此改写。
- **签名脚本显式指定 signtool、默认 SHA256 文件摘要(AAX-18,2026-10-08 首次真签名实测)**:
  - signtool:不给 `--signtool` 时,wraptool 6.0.1 在它自己的「默认位置」找不到 Windows SDK 10.0.19041 的 signtool,报的却是
    "Can't sign with the certificate identified by the thumbprint ..."(证书本身没问题)。`sign-aax.ps1` 新增 `-SignToolPath`,不给时按
    `%ProgramFiles(x86)%\Windows Kits\10\bin\<版本号最高的>\x64\signtool.exe` → PATH 的顺序自动找,都没有就 FAIL(提示装
    Windows SDK 的 Signing Tools 组件)。新增预检 5d,打印 signtool 的路径与版本;签名时始终传 `--signtool`。
  - 摘要算法:wraptool 默认让 signtool 用 SHA1 文件摘要 + 旧式 `/t` 时间戳(Sectigo)。现在默认经 `--explicitsigningoptions`
    改为 SHA256 文件摘要 + RFC 3161 时间戳(`/fd sha256 /tr http://timestamp.sectigo.com /td sha256`)。实测这个值会**整体替换**
    wraptool 默认的 signtool 参数(`sign /sha1 <指纹>` 要自己写,文件路径仍由 wraptool 追加),`wraptool verify` 照样退出 0。
    `-LegacySha1Digest` 回退到 wraptool 的默认命令。`-KeyFile` 方式必须带这个开关:要 SHA256 就得把 pfx 路径和口令写进
    `--explicitsigningoptions`,脚本不这么做。
  - 后检新增摘要核对:从 DLL 的 PE 证书表解出 PKCS#7,文件摘要与签名者摘要必须是 SHA256(回退时为 SHA1),时间戳必须是
    RFC 3161、摘要 SHA256,且与签名对得上;回读复验同样核对。`-ExtraWraptoolArgs` 另拦 `--signtool` / `--explicitsigningoptions` /
    `--extrasigningoptions`(`-J`)。
  - 已实测、去掉 TO-VALIDATE 的项:`--signid` + `--wcguid` + `--signtool` 真签名成功;对内层 DLL 原地签名;已签名件 verify
    退出码 0;`--verbose` 不回显口令;签名件确实带时间戳(V3)。iLok 上缺签名证书时的报错文案也写进了预检 6。仍标 TO-VALIDATE:
    零售版 Pro Tools / Intro 是否接受自签名的件;`-KeyFile` 与 customer number 两条备选路径;证书在 `Cert:\LocalMachine\My`
    时能否签(默认方式按 signtool 文档加 `/sm`);`--explicitsigningoptions` 下 `--timestampretry` 是否生效;macOS 侧全部。
  - 文档:`docs/release.md` §7 的命令改为在 pwsh 会话里用 `&` 调用(经 `pwsh -File` 传数组参数会错位,报出假的互斥错误),并新增
    排障表;`docs/build-windows.md` 同步;`new-selfsigned-codesign-cert.ps1` 打印的 `-KeyFile` 用法带上 `-LegacySha1Digest`。

### 构建

- **本地门禁 `scripts/gates.ps1` 加 AAX 支持**(既有 gate 与写死路径一行未动;新参数追加在参数表末尾,不改变既有的按位置调用):
  - **gate 3h「签名材料 / Avid 评估工具不入库」,默认恒跑**(只读、秒级,不挂开关;默认结果表因此只多这一行):
    `git ls-files` 列出已跟踪、未跟踪**以及被 `.gitignore` 忽略**的文件,命中 `*.pfx` / `*.p12` / `*.pvk`、`dsh.exe`、
    DigiShell / AAX Validator 的可执行文件或安装包、测试计划 PDF 即 FAIL。只按扩展名 + 文件名匹配:证书扩展名落在任意路径
    都算,DigiShell / AAX Validator / 测试计划的关键词必须落在文件名里(目录名不算),文档文件名里出现 validator 不会误报;
    文件名按 UTF-8 解码,中文名的证书文件在 CP936 控制台下同样命中。被忽略的文件也查:`.gitignore` 已忽略证书扩展名,只查「会被提交的」就看不见仓库里躺着的证书,
    而签名材料本就必须放仓库外(签名脚本与证书助手同样拒绝仓库内路径)。
  - **`-IncludeAax`(默认关)**:在 selftest 之后、pluginval 之前加跑三道 gate;只读 gate 失败、配置 / 构建失败时
    这三道各记一行 SKIP,开头的 Mode 段多打印一行 `AAX : 开/关`。
    - **5c AAX bundle 结构**:CMake 缓存里 `SYNCHAIN_BRIDGE_AAX` 为 ON 且生成的工程里有 AAX 目标(否则构建目录里的 bundle 是
      开关打开时留下的旧产物,直接 FAIL)、`Contents\x64\Synchain Bridge.aaxplugin` 的 PE 头 Machine = 0x8664、根目录有
      `desktop.ini` / `Plugin.ico`、当前 `-Config` 产物目录下已构建(含 `Contents\`)的 `.aaxplugin` 恰好 1 个(VS 多配置生成器
      给每个配置建的空壳目录不计;同一构建目录里其他配置的产物只写进明细)。
    - **5d AAX 打包冒烟**:以 `-BundlePath` 调 `scripts/package-aax.ps1`,输出到 `dist\gates-aax-<构建目录名>`(并行
      worktree 互不干扰、已被忽略)。Unsigned 跑一次,`.sha256` 与 `ci.yml` 的 AAX 冒烟同一套字节断言;Signed 反向断言 ——
      同一个未签名 bundle 必须因签名检查被拒,且不留发行名 zip。
    - **5e AAX Validator(可选)**:`-AaxValidatorPath <仓库外的 Validator 可执行文件>`(给了即隐含 `-IncludeAax`)。
      没给 → SKIP;给了空串、路径在仓库内或不存在 → FAIL。调用参数与通过 / 失败标记是文件头三个 `TODO-AAXVAL` 常量,
      未实测填写前恒 SKIP「调用方式未实测」,**绝不假绿**;填好后输出 Tee 到 `<构建目录>\gates-aaxval.log`,以输出标记
      判定、退出码只作参考(与 auval 同口径)。
- `scripts/build.ps1` 新增 `-InstallAax`:构建后把 `.aaxplugin` 复制到 64 位 Common Files 下的 `Avid\Audio\Plug-Ins`。
  必须管理员权限(Pro Tools 只扫描这一个目录,没有用户级目录可回退;非管理员在构建前就直接退出),装前检测主体 DLL
  是否被 Pro Tools 占用、先删旧版再整体复制,并提示本地构建的未签名件只有 Pro Tools Developer 能加载。

### 持续集成

- **`ci.yml` 两个 build job 各加三步 AAX 打包**(触发面一字不改,不加 secret,不加新 action,上传沿用已 pin 的
  `upload-artifact` v4.6.2 SHA):
  - **AAX 打包冒烟**(Windows 6c / macOS 8c,产物丢弃,与 VST3/AU 的 6b / 8b 同构):`-UNSIGNED` 模式按
    `0.0.0-ci → 0.0.0-ci2 → 0.0.0-ci` 三连跑,`.sha256` 字节形态与 summary 按段去重的断言逐字照搬 6b / 8b;另做一道
    独立于脚本自检的绊线 —— zip 层级、(mac)可执行位、`INSTALL-AAX.txt` 必须带 `(UNSIGNED)` 横幅。
    **反向断言**:同一个未签名 bundle 用 Signed 模式打包必须失败、失败原因必须是签名检查(匹配拒收消息,前置检查
    先挂掉不算数),且输出目录里不得出现发行名 zip ——
    「未签名件不可能长得像发行资产」由机器保证,而不是靠人记得。
  - **Package AAX (unsigned)**(6d / 8d,只在 push / `workflow_dispatch` 下运行):版本 = CMake `VERSION` + `-ci.<短 sha>`,
    `INSTALL-AAX.txt` 的源码链接钉本次构建的完整 commit sha(经 env 间接读入);随后断言产物名逐字等于预期(mac 侧顺带在
    BSD sed 上验证脚本从 `CMakeLists.txt` 回落读版本)。pull_request 构建的是合并提交 `refs/pull/N/merge`,源码链接与版本号
    都对不上字节,所以 PR 上只跑 6c / 8c 冒烟、不出测试件(与签名脚本来源核对拒收 pull_request run 同口径)。
  - **Upload**(6e / 8e,事件条件同 6d / 8d):artifact `aax-unsigned-win64` / `aax-unsigned-macos-arm64`(内含 `-UNSIGNED.zip` +
    `.sha256`),保留 30 天。名字刻意不叫 `dist-*`:`release.yml` 的 `publish` 只从 `dist-*` 取件,未签名件进不了 Release。
    `workflow_dispatch` 同样产出 —— 在子分支上 dispatch 一次即可取到 Pro Tools Developer 测试件。
- **`release.yml` 的 `release` / `release-macos` 各追加三步未签名 AAX**(触发面一字不改,不加 secret,不加新 action,
  上传沿用已 pin 的 `upload-artifact` v4.6.2 SHA):
  - **Package AAX (unsigned)**:版本取 `gate` 的 `outputs.version`(与 VST3/AU 的 Package 同一个值、同一道空值断言,经 step env
    间接读入),源码链接用脚本默认的 `v<版本>` 即本次 tag;随后断言 `dist/aax` 里恰好一个 AAX zip、名字逐字等于
    `SynchainBridge-AAX-v<版本>-{win64,macos-arm64}-UNSIGNED.zip` 且带 `.sha256`(与 `ci.yml` 6d / 8d 同口径)。
  - **Publish AAX job summary**:把 `dist/aax/package-summary.md` 追加进 job summary。
  - **Upload**:artifact `aax-unsigned-win64` / `aax-unsigned-macos-arm64`(`-UNSIGNED.zip` + `.sha256`),保留 **30 天**
    (`dist-*` 的 7 天不够:手工签名可能要等借到 Mac)。
  - **`publish` job 一行未改**:它只从 `dist-win64` / `dist-macos-arm64` 取件,四资产精确名白名单与 `files:` 不变,draft 仍只挂
    VST3/AU 四个资产;AAX 由维护者本机 PACE 签名后手工上传(`docs/release.md` 新增 §7「AAX(Pro Tools):本机签名 + 手工上传」)。
  - **失败语义 fail-hard**:任一平台的 AAX 打包 / 上传失败 = 整个 tag 无产物,不用 `continue-on-error`(理由见
    `docs/release.md` §6.1;同一脚本在 `ci.yml` 的每次 PR / push 上都冒烟过,回归在打 tag 前就会红)。

### 发布 / 分发(对下游可见)

- **新增 AAX 打包脚本 `scripts/package-aax.ps1`(Windows x64)与 `scripts/package-aax-macos.sh`(macOS arm64)**,是 AAX
  打包的唯一真源(本机签名流程与 CI 共用);现有 `package.ps1` / `package-macos.sh` 一行未改,VST3 / AU 发版链路零风险。
  - `-Mode Unsigned|Signed`(mac:`--mode unsigned|signed`)**必填、无默认值**。**`-UNSIGNED` 约定**:未签名件一律叫
    `SynchainBridge-AAX-v<版本>-{win64,macos-arm64}-UNSIGNED.zip`;不带后缀的发行名只在 Signed 模式、且 bundle 确实带
    签名时才产出 —— Windows 要求 DLL 有 Authenticode 签名者证书且签名完好(`NotSigned` / `HashMismatch` 拒收;自签名证书的
    `UnknownError` 属预期、放行),macOS 要求 `codesign --verify --strict` 通过、有 `Authority=` 且不是 ad-hoc、并有
    `_CodeSignature/CodeResources`(arm64 链接器自动加的 ad-hoc 签名必然被拒)。Signed 模式打包后再把 zip 解到临时目录
    **回读验签**并比对主体二进制字节;从建 staging 起任何一步失败都删掉本次的 zip / `.sha256`,失败路径上绝不留发行名 zip。
  - 版本:`-Version` 与 `-PrereleaseTag`(`ci.<sha7>` → `<CMake VERSION>-ci.<sha7>`)互斥,显式传空串直接失败(不静默回落);
    结果须匹配 `release.yml` 的 tag 口径。`-PrereleaseTag` 的构建必须同时给 `-SourceRef <40 位 commit>`(没有对应 tag,
    默认的 `v<版本>` 会是死链)。`-BundlePath` 供签名流程直接指定 bundle(签名产物不在构建目录里);走构建目录时
    Windows 只计含 `Contents\` 的已构建 bundle —— VS 多配置生成器在 generate 期就给每个配置各建一个只有 `desktop.ini`
    的空壳 `.aaxplugin` 目录(JUCE 的 `file(GENERATE)`),它们不是产物;已构建的必须恰好 1 个。
  - bundle 断言:Windows 为 `Contents\x64\Synchain Bridge.aaxplugin` 的 PE 头 Machine = 0x8664、根目录有 `desktop.ini` /
    `Plugin.ico`、不含 `*.pdb/*.ilk/*.exp/*.lib`;macOS 为 arm64-only、`CFBundleIdentifier` 等于 `CMakeLists.txt` 的
    `BUNDLE_ID`、`Contents/MacOS/Synchain Bridge` 可执行。
  - zip 内放 `INSTALL-AAX.txt`(中文;不叫 `INSTALL.txt`,与 VST3 包解压到同一目录时互不覆盖):Unsigned 版顶部是
    「未签名构建(UNSIGNED)—— 不是发行版」横幅,Signed 版是签名说明;两平台的 Pro Tools 插件目录安装命令(先删旧版)、
    mac 的 arm64 / Rosetta 与解隔离说明、Avid / Pro Tools / AAX / PACE / iLok 商标声明、AAX SDK 2.8.0 的 GPLv3 说明与
    精确到 ref 的源码链接。合规文件与现有包同一组(`LICENSE.txt` / `THIRD-PARTY-NOTICES.md` / `LICENSES/OFL-1.1.txt`)。
  - `.sha256` 与 `package-summary.md` 的格式与现有脚本逐字一致(默认输出目录 `dist/aax`,与 VST3 的 `dist/` 分开)。
    打包脚本**不调用 wraptool、不碰任何凭据**,所以 CI 能跑。
- `.gitignore` 追加 `*.aaxplugin/`、`*.pfx`、`*.p12`、`*.pvk`:AAX bundle 与代码签名材料都不入库(签名证书一律放仓库外)。

### 兼容性

- **无契约变更**:桥 #1 / 桥 #2 的 wire 协议、Init 键与 `BRIDGE_CONTRACT_VERSION` 均零改动,握手里不带
  格式字段;七个契约文件未触碰。
- **VST3 / AU 行为与 1.5.3 一致**:声道布局判定对 VST3 / AU 仍恒为接受(与 JUCE 默认逐字等价,已存工程的
  声道协商结果不变);离线早退只对 AAX 生效;`Snch` / `Snb1` / `BUNDLE_ID` 未变,已有 DAW 工程无需重建。
- AAX 是**新增格式**,不存在旧实例迁移问题。
- 从源码构建:`cmake --build` 默认会多编 AAX 目标(共享代码多一个 `JucePlugin_Build_AAX=1`,首次构建全量
  重编);configure 状态行改为 `Building Synchain Bridge for Windows: VST3 + AAX (static CRT, WebView2)` /
  `Building Synchain Bridge for macOS: VST3 + AU + AAX, …`。只要 VST3 / AU 的话加 `-DSYNCHAIN_BRIDGE_AAX=OFF`,
  状态行与产物都回到 1.5.3 的样子(Windows 行的措辞除外)。

### 文档 / 合规

- **AAX(Pro Tools)文档按已合入的脚本 / workflow / 代码定稿**:
  - README(中英,标题骨架对等)新增「Pro Tools (AAX) 安装」「Pro Tools (AAX) 已知限制」「AAX (Pro Tools) 源码构建」三节,
    同步徽章、简介(标 Beta)、安装表(两个 AAX 资产从首个带 AAX 的版本起提供,签名后手工上传)、`-UNSIGNED` 件与
    `aax-unsigned-*` artifact 的定位、AAX 身份(`Snch` / `Snb1` + `com.synchain.bridge`)不可改;Windows 安装命令与
    `INSTALL-AAX.txt` 同口径(`$env:CommonProgramW6432`);已知限制按代码实际行为写(只有 mono→mono / stereo→stereo、
    无 AudioSuite / multi-mono、AAX 离线渲染不推流、DPP、1024 块口径、自签名 / 未公证、诊断日志前缀 `SynchainBridge:`)。
  - `docs/build-windows.md` / `docs/build-macos.md` 新增 AAX 段:产物布局、`package-aax*.ps1/sh` 的 Unsigned 用法与参数要点、
    `build.ps1 -InstallAax`、本地门禁(3h / `-IncludeAax` 的 5c / 5d / 5e)、四行诊断日志的实际文案、自签名证书助手、
    AAX Validator 探查步骤(TODO-AAXVAL);CI 对照段补 6c–6e / 8c–8e 与 artifact 名。
  - `docs/DAW_TEST_GUIDE.md` 新增 Pro Tools 实测一节:被测件三种来源、两平台安装、已知口径与 P-mac + T01–T13 检查表
    (附每项应看到的诊断行),措辞为本项目自拟。
  - `docs/release.md` §7.3 第 4 步补 `-SourceRunId <run-id>` / `--source-run-id <run-id>`(run-id 取第 2 步查到的 release run,
    用于来源核对),并按 `sign-aax.ps1` / `sign-aax-macos.sh` 的实际预检 / 后检与开关逐项写准;§7.4 注明本机重建件没有 run
    可核对。各文档指向 release.md §7 的链接补上锚点。
  - `CLAUDE.md`(§0 安全铁律一字未动)/ `CONTRIBUTING.md` 同步 U13 的 AAX 例外、`feature/aax` 支线、gates 的 AAX 开关、
    workflow 的 AAX artifact 与 fail-hard、AAX 资产与打包 / 签名脚本;CONTRIBUTING 补「AAX 声道布局发版后只许加不许删」。
- **`THIRD-PARTY-NOTICES.md`**(随每个发行 zip 分发,`INSTALL-AAX.txt` 的许可证一节指向它):新增 Avid AAX SDK 2.8.0 一行
  (GPL-3.0-only;双授权取 GPL v3,原文核验自 JUCE 8.0.8 tag 下的 SDK `LICENSE.txt`,仅 AAX 产物);闭包差集改写为
  Windows VST3 / Windows AAX / macOS VST3+AU / macOS AAX 四个闭包;补说明 —— AAX 二进制整体按 GPL 第 3 版分发(只能 v3、
  JUCE 部分照旧 AGPLv3)、PACE wraptool 与 iLok 只在维护者本机使用、Avid 测试工具不入库,以及 Avid / Pro Tools / AAX、
  PACE / iLok、VST 商标行与「与 Avid 无隶属、赞助或背书关系」。不新增 `LICENSES/GPL-3.0-only.txt`(无入库文件声明该
  标识,`reuse lint` 会报未使用)。

## [1.5.3] — 2026-09-30

> 版本号由 1.5.0 升至 **1.5.3**(唯一真源 `CMakeLists.txt` 的 `project(... VERSION)`,四镜像同步:
> web-preview 的 mock-server.mjs / package.json / package-lock.json 与 `BRIDGE_CONTRACT.md` §三)。
> 1.5.1 / 1.5.2 / 1.5.3 三批改动都在本段:1.5.1 与 1.5.2 **都没有发过 tag / Release**,各出过一个
> 内部测试包 —— 1.5.3 这个号存在的理由就是让用户手上那个包与他已经测过的 1.5.2 能分辨开。
> **三批都不涉及契约变更**(wire 协议零改动;`__bridge__firstFrame` 时序信号及其载荷里的诊断字段
> 均为非契约面,判定与兼容性承诺见 `docs/contract-changes/20260914-sl386-reveal-gate.md` 与
> `docs/contract-changes/20260918-sl433-first-frame-paint-delta.md`)。

### 修复

- **首帧信号到达后的毫秒下界 `kRevealSettleMs` 32 → 64(SL-436,1.5.3)**:用户 2026-09-19
  拍板,依据是 Monitor 开窗曾经白过一次、按「合成延迟够得着这个窗口」的假设去解释它 ⇒ 把
  可容忍的合成延迟窗口整体翻倍,不是照着某一次测量的中位数微调。
  - **这个常量兜的是什么**:paint 记录 + 两层 rAF 只保证「帧已提交给合成器」,提交到上屏还
    差一拍——真正兜住「Blink 已经画了、但那一帧还没合成上屏」这一段的,是本常量。
  - **一个容易读错的地方**:若测到 `signal − first-paint` 这类差值是几毫秒到十几毫秒的
    小正数,那量的是**回调调度延迟 + 前端两层 rAF 的耗时**(`PerformanceObserver` 的 paint
    回调结构上不可能跑在 paint 记录存在之前,而回调之后还要再走两层 `requestAnimationFrame`
    才到取值那一刻,两项都非负),**不是**「合成上屏还要多久」的安全裕度;拿它当"余量充足"、
    据此把本常量调小,是把两个不同的量混了。
  - **代价**:旧值(32)时上界 ≈ 32 + 一个 25Hz tick(40 ms)≈ 72 ms;改成 64 后上界
    ≈ 64 + 40 ≈ 104 ms,每次开窗占位段多停约 32 ms(这是 tick 严格按周期到达的理想模型;
    实际是 message 线程上的 best-effort 定时器,宿主 UI 忙时会迟到,真实上界随之抬高,但
    只影响占位多停,不影响正确性)。
  - 判据:`tests/reveal_gate_selftest.cpp` 第一格钉常量值本身(改成任何非 64 都红)。

- **开窗第二段白:首帧信号改由「页面真的画过一帧」触发(SL-433,1.5.3)**:
  用户在 1.5.2 上回验,开窗仍是「白 → 背景色 → **白** → 正常」,中括号那一段没消失。
  - **先排除一层**:[SL-421] 补的 `DefaultBackgroundColor`(①-b)**不是这一段** —— 它铺在
    **任何 web 内容之下**,盖不住 WebView2 widget 自己的 base background。这正是「加了 ①-b
    照样看见白」的原因,那一层该在还在,本卡不动它。
  - **成因**:[SL-386] 的首帧信号是在 `DOMContentLoaded` 之后嵌套两层 `requestAnimationFrame`
    才发的,而**两层 rAF 并不保证页面已经画过任何一帧** —— 信号时刻 ≈ DCL + 两个 rAF,
    与 `first-paint` 之间没有任何约束。信号早于 first-paint 时,C++ 收到信号就把窗口揭开,
    而 widget 一个像素都还没画,露的是它自己的白。
  - **改法(与 SCVB SL-429 同一套,那边已经用户真机终验通过)**:武装的触发条件改成
    `PerformanceObserver({ type: "paint", buffered: true })` 收到 paint 记录之后,再走原来的
    两层 rAF。另配两条不许省的路 —— 没有 `PerformanceObserver` 时回落到旧的 `DOMContentLoaded`
    触发;paint 记录迟迟不来时由一条**排在 `try` 之前**的保险定时器**直接**发信号(不绕 rAF:
    「paint 不来」最可能的成因是 BeginFrame 停摆,那时 rAF 同样不回调)。
  - **放行判定本身零改动**:`src/WebViewRevealGate.h` 本次只改了头注说明(类体逐字未动);
    `src/WebViewEditor.cpp` 里闸门的五个调用点(`onNavigationStarted` / `onNavigationFinished` /
    `onFirstFrame` / `onTick` / `onFallbackShown`)一字未改 —— 唯一碰到 `mRevealGate` 的改动是
    诊断行里那次**只读**的 `parked()` 查询后面多拼了一段文案。本卡只改「信号什么时候发」。
  - **代价**:占位那一段多停一小会儿 —— SCVB 在**真插件宿主**上同机实测多 17~48 ms。
    ⚠ **Bridge 这一页的代价本机没测出来**:同宿主下换页面前后的差约 +59 ms,而这套设置
    跨构建的跑间波动约 ±230 ms —— **容差大过被测量,那个数不成立**,不作为承诺。
  - ⚠ **这一版对 Bridge 保证的是:「放行不早于 first-paint」**(paint 路上这是**构造性的**:
    武装挂在 paint 记录到达之后,再过两层 rAF 才发信号)。**唯一没有这个保证的是保险路**
    (见下一条)。
    ⚠ **别写成「放行只会更晚、不会更早」—— 那句按字面不成立**,本卡第 1 轮复审订正:
    旧锚点是 `DOMContentLoaded`、新锚点是 `first-paint`,而本页 `<head>` 内联脚本排在
    渲染阻塞的 `<link rel="stylesheet">` **之前**、主脚本又是 `type="module"`(要经资源提供器
    往返抓 `bridge.js` / `i18n.js`)⇒ **first-paint 完全可能早于 DCL** ⇒ 新信号**可以比 1.5.2
    更早**发出。那恰恰是本次修法要的(旧锚点本来就没道理地偏晚),但与那句话的字面意思相反。
  - ⚠ **保险路是唯一可能在「零 paint 记录」下放行的路,它没有上面那条下界保证**:
    「有 `PerformanceObserver`、但它不报 paint 记录」这一档,保险到点照常发信号 ⇒
    **本卡要治的那段白仍可能出现**,只是时限从 C++ 的 3 s 提前到页内的约 2.5 s。
    这不是改法错(任何定时兜底都有这个性质,它明显优于「永不放行」),但**必须写出来**。
  - **成因在本机被量到了(不再是推断)**:在真 WebView2 宿主(pluginval)上,让旧触发链
    (`DOMContentLoaded` + 两层 rAF)与 paint 记录**两条都跑、都只记时刻**,再送两者之差 ——
    **`oldTrigger − firstPaint` 12 次全为负,区间 −33 ~ −52 ms(中位 −46,非负 0 次)**。
    即**改前那条首帧信号确实早于 first-paint 约 33~52 ms 发出**,C++ 收到就揭窗而页面一帧未画,
    露的正是 widget 自己的底 —— 本卡的成因解释在 Bridge 上成立。
    同台的对照(⚠ **三批复测各有各的标签与 n,别合并成一个「×3」** —— 它们是不同批次,
    本卡第 3 轮复审就是因为两处共用「复原后复测 ×3」这个标签而读出了矛盾):
    基线 5 次 `+15..+18`、兼容性测完的复原复测 3 次 `+17/+14/+17`、本次测量后的复原复测
    3 次 `+18/+17/+18` ⇒ 修后合计 **11 次全为正,区间 +14~18 ms**。**符号翻正,幅度也对得上**
    (−44 → +16,差 ≈60 ms 正是「等 paint 记录到达」补上的那一段)。
    ⚠ 这组数**不含静默缺样本**:12 次里 `(no paint record)` 与 `(paint delta unreadable)` 各 0 次,
    两个时刻每次都拿到了(只等 DCL 的仪器测不出正值、只等 paint 的测不出负值,故两条都记)。
  - ⚠ **前提变窄了,但没有消失**:上面那组是 **pluginval 宿主**上的读数,**不是用户的 DAW**;
    SCVB 那边的真机数(13/13)同样不能外推到本仓。**用户机上是否同量级未测**,
    **第二段白是否就此消失,仍以真机回验为准** —— 别把这组数读成「已经证明能修好」。
  - **为此同时补上一格诊断**:首帧信号的载荷里带上页面量到的 `信号时刻 − first-paint 时刻`
    (毫秒差值,字段名真源 `BridgeApi.h` 的 `timing::FirstFramePaintDeltaKey`),C++ 拼进既有那行
    `first-frame signal after N ms ...`,变成 `... (signal-firstPaint +M ms)`;页面没有 paint 记录时
    打 `(no paint record)`。**只进日志,不参与任何放行判定。** 它送的是**差值不是绝对时刻** ——
    页面的 `performance` 时间轴与 C++ 的 `mStartMs` 不共享原点。有了它,用户下次贴一份日志就能
    直接读出「新路真的生效了、余量还剩多少」,而不是只剩「还白 / 不白」两个 bit。
    ⚠ `(no paint record)` **按字面读**:它只说明这一次载荷里没这个字段;反过来「带了差值」
    **不等于**走的是 paint 路(保险路也可能带着真差值发出),判是不是保险路看 `after N ms` 的量级。
    字段**在场但读不出来**(类型不对 / 非有限 double)另打 `(paint delta unreadable)`,
    与前者分开 —— 那是「真源没漂、载荷坏了」,要查的地方不是一处。
  - **回验怎么读(这是回滚判据,不是观察项)**:
    - `(signal-firstPaint +M ms)` ⇒ 新路生效,`M` 就是余量;
    - `(no paint record)` 且 `after N ms` 的 **N ≈ 2500** ⇒ **parked 状态下 paint 记录根本没来**,
      走的是页内保险路。这一档下新路对 Bridge 是**纯倒退**(每次开窗都要多等约 2.5 s 占位才放行)
      ⇒ **回滚到 [SL-386] 的 `DOMContentLoaded` 触发**。
      ⚠ **「调大保险时限」是错的应对** —— 那只会把「每次多等 2.5 s」变成「每次多等更久」,
      把倒退做得更深;
    - `(no paint record)` 但 `N` 是正常量级(几百 ms)⇒ 走的是回落路(该浏览器没有
      `PerformanceObserver`),不是本条判据说的那一档。
  - ⚠ **一条自陈:遮挡闸在 `pageAboutToLoad` 就把 widget 挪到与可视区零交集的位置,所以新路
    等于新引入一个依赖 —— 「这种状态下 Chromium 必须照常记 paint 记录」。** 本机在真 WebView2
    宿主(pluginval)上实测**三批 11 次全有 paint 记录**(`after N ms` ≈ 710~780 ms,不是保险路的
    ≈2500)⇒ 本机上成立。但**那不是用户的 DAW**,所以上面那条回滚判据照写不误。
  判据:`web-preview/reveal-first-frame.test.mjs` 第 ② 格由「`DOMContentLoaded` + 两层 rAF 在场」
  升级成六条(a~f),断的是**接线生效**不是片段在场 —— 「把 `PerformanceObserver` 留成死代码、
  武装改回 DCL」这种全片段在场的绕法必须红;保险的形态(排在 `try` 之前 / 回调直接发信号 /
  撤网落在 `signal()` 里 / **撤网与去重都排在 `postMessage` 之后**)各有一格;载荷字段名
  **两侧逐字对拍**(页面侧打错、C++ 侧改写字面量各有一格必红 —— 任一侧漂了都只会打
  `(no paint record)`,而那与合法回落路在日志里逐字同形)。
  **23 格删除式反向注入逐格核过「红在设计接住它的那条断言上」**(不是只看红;其中两格是
  **预期绿**的对照格,验的是两条**假红**确实被消掉 —— 注释里双引号写字段名、`.observe` 实参键换序)。
  ⚠ 一处**明说钉不住的**:`(paint delta unreadable)` 那条分支**没有判据守**,删掉它不会有任何
  东西变红 —— 它是纯诊断文案,不值得为它再往这一族加正则(判例 SL-431),写在这里代替机检。

- **补上遮挡闸盖不到的那一段白:WebView2 的 `DefaultBackgroundColor`(SL-421,1.5.2)**:
  用户报开窗仍是「白 → 背景色 → 白 → 正常」的四段跳。SL-386 的遮挡闸、三处同源占位与插件内
  关入场动画**都已在位**,缺的是 SCVB 三层白里的 **①-b** —— WebView2 在**任何** web 内容之下
  铺的那一层。`makeOptions()` 此前从不调 `withBackgroundColour`,于是 JUCE 把默认构造的
  `juce::Colour`(ARGB `0x00000000`,**全透明**)原样 put 进 `put_DefaultBackgroundColor`:
  从控制器建好到页面画出来为止,这一层什么都不挡,露的就是窗口的白。
  - **遮挡闸为什么盖不到它**:park 落在 `pageAboutToLoad`,而 WebView2 控制器是在 `Navigate`
    **之前**就建好并上屏的;`<head>` 内联底(①-c)管的是外链 css 未到那一段,正常路径上
    `<link rel="stylesheet">` 渲染阻塞期间屏上是 ①-b,它并不替 ①-b 顶班。
  - **改法(照搬 SCVB `PlatformWebView.cpp` 的 `withBackgroundColour(shellBackdropMid())`)**:
    取占位渐变沿轴 50% 的插值色(`DefaultBackgroundColor` 只收纯色,没有渐变形态),由
    `WebViewRevealGate.h` 新增的 `placeholderMidArgb()` 从 `kPlaceholderStops` **现算** ——
    不另写色值字面量,占位色仍只有一个真源。
  - **可观测性**:JUCE 对 `QueryInterface(ICoreWebView2Controller2)` 取不到是**静默跳过**
    (没有 else、没有日志、不看 HRESULT),故同时补上诊断行
    `webview2 default background: available|UNAVAILABLE|unknown ...`(打在 `goToURL` 之前)。
    ⚠ 它证的是**运行时有没有这个接口**,不是「JUCE 那次 QueryInterface 真成功了」,更不是
    「那一帧屏上真是这个颜色」—— 行里自带 `inferred / not directly observed`,别读过头。
  - 一并与 SCVB 形态对齐:编辑器构造里补 `setOpaque(true)`(SCVB 自己注明它**不治**开窗白闪,
    管的是兜底面板路径那块底)。
  - **平台面**:`withBackgroundColour`、`setOpaque(true)` 与诊断行调用点**三处都在
    `#if JUCE_WINDOWS` 内**,mac / Linux 行为与改动前逐字一致。⚠ `setOpaque` 必须与 `paint()`
    同条件 —— `paint()` 的绘制体本就只在 Windows,若 `setOpaque` 无条件生效,mac 上就成了
    「声明自己不透明、却一个像素都不画」;诊断行同理,非 Windows 上那个哨兵版本串会让它打出
    三句全假的一行(`UNAVAILABLE` / `inferred absent` / `JUCE drops argb ... silently`)。
  判据:`tests/reveal_gate_selftest.cpp` 新增两组(中点色 golden `0xffd9cadb` 独立算出、
  全不透明、必须是插值而非某个停靠点;版本串解析与支持三态的边界两侧各一格)+
  `web-preview/reveal-first-frame.test.mjs` 新增第 ⑤ 格源钉(接线在场 / 取值不许写字面量 /
  诊断行先于 `goToURL`)。⚠ **这一层缺席是静默的**:删掉那一句编译照过、C++ 自测照样全绿
  (删除式对照格实测),第 ⑤ 格是它唯一的机检。

- **开窗白闪改成与 SCVB 同一套遮挡闸(SL-386)**:开窗序列里 WebView2 那几帧白不受我方任何
  一层底色控制(WebView2 宿主 HWND 合成首帧前画什么,插件侧没有 API 管得到)。移植 SCVB
  的成熟方案(`WebViewRevealGate.h` @ 76ffb04,SL-370/376/378):
  1. **挪窗不隐藏** —— 导航开始(WebView2 控制器已建好)后把 WebView 子窗口整块挪出宿主
     可视区(尺寸一字不改,不 `setVisible(false)`、不零尺寸 —— 隐藏会把页面顶成
     `about:blank`),**宿主 `paint()` 自绘占位**(遮挡窗口内唯一会跑的一层;挪走的子组件
     与可视区零交集、JUCE 不再画它,`BridgeWebView::paint` 那层只守未遮挡时的
     fallbackPaint 白 —— 两层共用同一组色标);**只认首帧放行**,`navigationFinished` 只记账
     不放行(它不保证任何一帧已合成);前端 `DOMContentLoaded` 后嵌套两层 rAF 发
     `__bridge__firstFrame` 信号(⚠ 这个触发条件**已由上面的 SL-433 改掉**:两层 rAF 并不保证
     页面画过一帧,现在等 paint 记录到达才发 —— 本条记的是 SL-386 当时的形态),信号后再压一拍
     (tick 数 ∧ **32 ms**[⚠ 这个 32 ms 已由上面的 SL-436 改成 64 ms,本条记的是 SL-386
     当时的形态] 毫秒下界,回绕安全)才挪回;3 s 超时兜底(绝不允许「永远不放行」)。
  2. **占位与成品底同形** —— 占位不是单一中点色,而是与成品可见底(玻璃拟态卡片)同一个
     渐变 `linear-gradient(157deg, #b5acc9/#ccbfd5/#e3d2e0/#fde8ed)`,占位切内容不跳阶;
     三处同源:css token(`styles.css` 的 `--vb-card-surface`,卡片消费它)/ `<head>` 内联
     html 底(取代浏览器默认白)/ C++ 色标(`WebViewRevealGate.h`),由
     `web-preview/reveal-first-frame.test.mjs` 钉三处相等。
  3. **平台与既有机制** —— 挪窗激活只在 Windows(`#if JUCE_WINDOWS`);mac 路径保持现状
     (WKWebView 不挪窗、不铺占位)。看门狗(5s)/ 兜底面板 / 运行时探测 / 缩放机制行为不变;
     闸门 3s < 看门狗 5s 由 `static_assert` 在每次编译上守。
  判据:`tests/reveal_gate_selftest.cpp`(纯逻辑删除式断言,接入 gate 5b / ci 两平台 /
  compliance)+ `web-preview/reveal-first-frame.test.mjs`(三处同源与接线源钉)+ 真机
  pluginval `--repeat 10` 放行分布数表(firstFrame 10/10、navFinished 0、timeout 0)。

### 内部工程(无契约变更)

- **PCM 帧头编码收敛到一处并加 golden 测试**(issue #23 第二批第 1 条):`src/VstBridgeServer.cpp` 里
  同步遗留路径 `sendPcmPacket()`(无调用方,issue #168 后实时路径改走 `pushPcm`;保留仅为 API 兼容,
  声明处已加注勿在音频线程调用)与后台发送线程路径 `buildPcmFrame()` 此前各自手写一份 12 字节帧头
  (`u32 LE sampleRate | u32 LE channels | u32 LE numSamples`),彼此无机器约束。现抽成新头文件
  `src/PcmFrame.h`(`synchain::pcm`,纯标准库,零 JUCE / ixwebsocket 依赖:`kHeaderSize` / `writeHeader` /
  `readHeader` / `payloadSize` / `frameSize`,**C++ 侧唯一实现**),两条路径都改为调用它 —— **wire 逐字节相同,
  行为零变化**。JS 侧(本地 mock)的 `web-preview/pcm-frame.mjs` 是同布局的另一份实现,新增
  `web-preview/pcm-frame.test.mjs`(`node:test` + `node:assert`,零依赖,`npm test` / `node --test`)用
  **同一组 golden 字节**钉死它,`compliance` workflow 加一步 `node --test`(ubuntu 自带 node,不装依赖)。
  新增 `tests/pcm_frame_selftest.cpp`:固定输入 `(48000, 2, 512)` 的帧头逐字节钉死为
  `80 BB 00 00 | 02 00 00 00 | 00 02 00 00`,另覆盖 `0` / `0xFFFFFFFF` 边界、端序、字段顺序、
  `12 + numSamples*channels*4` 总长与 payload 偏移 —— 改任一字段顺序 / 端序 / 偏移即红。
  并入 `BRIDGE_BUILD_SELFTESTS`(同 `/W4` 或 `-Wall -Wextra -Wpedantic`),`scripts/gates.ps1` 的 gate 5b
  扩为跑两个 selftest,`compliance` workflow 新增同构的「PCM frame selftest」步骤(g++ 直接编译)。
  `ci.yml` 的 windows / mac 两个构建 job 现也以 `-DBRIDGE_BUILD_SELFTESTS=ON` 配置并在构建后运行两个
  selftest,MSVC `/W4` 与 clang `-Wall -Wextra -Wpedantic` 零警告门因此真覆盖 `tests/*.cpp`
  (`release.yml` 不开)。golden 钉不住「`VstBridgeServer.cpp` 真的经 `PcmFrame.h` 组帧」(要链 JUCE),
  由 `scripts/gates.ps1` 新增的 gate 3f 与 `compliance` 的同构 grep 步骤以文本断言补上:必须
  `#include "PcmFrame.h"`,且不得再出现 `writeU32(` 手写 lambda 或字面量 `headerSize = 12`。

- **`sendPcmPacket` 空 payload 不再调用 `memcpy`**(`src/VstBridgeServer.cpp`):`dataSize == 0` 时跳过拷贝,
  避免对空指针调用 `memcpy` 这一未定义行为。行为零变化(空帧本来就不携带数据)。

### 构建

- **Windows 侧 ixwebsocket 改 vcpkg manifest 模式钉死**(issue #23 第一批第 3 条):新增仓库根 `vcpkg.json`,
  `builtin-baseline` 钉到 microsoft/vcpkg 的 40 位 commit(该 baseline 下 `ports/ixwebsocket` = 12.0.1),再加一条
  `overrides`(12.0.1)双保险 —— 此前 CI 用 runner 镜像自带的 vcpkg 做经典模式 `vcpkg install`,版本随镜像每月轮换漂移,
  仓库里没有任何文件记录它。依赖由 CMake configure 期的 vcpkg toolchain 按 manifest 自动装进 `<build>/vcpkg_installed`
  (每个 `-BuildDir` 各自一份,并行 agent 互不干扰),本地与 CI 走同一条路径,不再手工 `vcpkg install ixwebsocket`。
  至此**两平台的 ixwebsocket 都钉到内容级**(Windows = vcpkg 仓库 commit + 版本,macOS = 上游 commit),升级时
  `vcpkg.json` 与 `CMakeLists.txt` 的 `IXWEBSOCKET_TAG` 须同一 PR 一起动。`scripts/gates.ps1` / `scripts/build.ps1` 的
  依赖预检检测到 `vcpkg.json` 即按 manifest 模式校验(vcpkg 已 bootstrap、声明了 ixwebsocket、baseline 是 40 位 SHA),
  无 manifest 的旧分支仍走经典模式检查;`scripts/gates.ps1` 另在 configure 之后加 **gate 4b**,调用
  `scripts/assert-vcpkg-installed.ps1` 断言 `<BuildDir>/vcpkg_installed/vcpkg/status` 里的安装版本(ixwebsocket 含
  port-version、传递依赖 mbedtls / zlib)与 `vcpkg.json` override / `THIRD-PARTY-NOTICES.md` 一致 —— 与 CI 同一份脚本、
  同一口径,断言失败视同配置失败,后续构建 / pluginval 一律 SKIP;`/W4` 零告警门的第三方排除项补 `vcpkg_installed`
  (manifest 模式下第三方头的路径里不再出现 `\vcpkg\`)。README(双语)、`docs/build-windows.md`、`CONTRIBUTING.md`、`CLAUDE.md` §6、
  `THIRD-PARTY-NOTICES.md`、`BEFORE_PUBLIC_CHECKLIST.md` §4.1 同步。

### 持续集成

- **依赖缓存**(issue #23 第一批第 4 条,`ci.yml` 与 `release.yml` 两平台 job 同 key,发版链路直接复用 CI 攒下的缓存;
  `actions/cache` 沿用已 pin 的 v4.3.0 SHA):① JUCE 目录按 `runner.os` + `.juce-version` 内容哈希缓存,clone 步骤按
  「目录里没有 `CMakeLists.txt`」判定而不是只看 cache-hit,miss 与残缺命中都照常 clone;无论来自缓存还是刚 clone,
  随后都做**身份断言**:HEAD 上的 tag(`git tag --points-at HEAD`,剥 v 前缀)须含 `.juce-version`,缓存条目对不上就删掉重 clone,
  重 clone 后仍对不上才红(两平台 × 两个 workflow 共四处,pwsh / bash 各一版逐条对应);② Windows 的 vcpkg
  **二进制缓存**(`VCPKG_DEFAULT_BINARY_CACHE` 指到 `runner.temp` 下固定目录,key 含 `runner.os` + 镜像身份
  `ImageOS-ImageVersion` + triplet + `vcpkg.json` 哈希,`restore-keys` 只回落一级到同镜像前缀 —— vcpkg 按包 ABI 哈希寻址,
  跨镜像的条目必然全量重编、回落过去只会撑大新条目,故不设跨镜像回落;镜像身份进 key 是因为 `actions/cache` 对已存在的
  exact key 不会重新保存,镜像月度轮换升一次 MSVC 就会让缓存退化成「永远重编、永远存不进去」),比缓存 installed 树稳;
  configure 后经 **`scripts/assert-vcpkg-installed.ps1`**(与本地 gate 4b 同一份脚本)断言 `build/vcpkg_installed/vcpkg/status`:
  ixwebsocket **核心段**(显式排掉无 `Version:` 行的 feature 段,且 `Status: install ok installed`)的 `Version` **与
  `Port-Version`**(缺行视为 #0)== `vcpkg.json` override 的 `version-semver` / `port-version`,传递依赖 mbedtls / zlib 的
  `Version` == `THIRD-PARTY-NOTICES.md` 登记版本(期望表手抄在脚本里,升 baseline 时同步);不符即红并打印实际值。
  Setup 步骤不再写 `VCPKG_DEFAULT_TRIPLET`(manifest 模式下 toolchain 只认 `-DVCPKG_TARGET_TRIPLET`,那是死配置);
  ③ macOS 把钉死的 ixwebsocket 源码预取到 `_deps/ixwebsocket-src`(key 含从 `CMakeLists.txt` 现读的
  `IXWEBSOCKET_TAG`,升 pin 自动换 key),经 `FETCHCONTENT_SOURCE_DIR_IXWEBSOCKET` 交给 configure;因 FetchContent 走
  该覆盖时不再核对 commit,workflow 自己断言 `HEAD == IXWEBSOCKET_TAG`,对不上先重拉、再对不上才红;只缓存源码,
  不缓存 `_deps/ixwebsocket-build`;`GIT_REPOSITORY` 的读取绑定到 ixwebsocket 的 `FetchContent_Declare` 段内,不会误拿
  将来别的 FetchContent 依赖的 URL。**缓存只是加速,miss 必须照常成功;不缓存 build 产物本身。**
  **验证状态**(2026-09-06,主支线 `feature/eng-debt-23` 真跑):首跑 run 34017204091 双平台绿,manifest 装入
  ixwebsocket=12.0.1#0 / mbedtls=3.6.5#0 / zlib=1.3.2#2、闭包恰三包、JUCE 身份断言通过、四个缓存条目保存;第二跑
  run 34017563395 四类缓存全部命中(vcpkg 恢复 5 个包,Windows job 7 → 5 min);`v0.0.0-test` 冒烟 run 34017566444
  四段绿、draft 四资产齐整。断言脚本另做**闭包完整性**:本 triplet 下 `install ok installed` 的非 feature 段集合不得超出
  ixwebsocket + 期望表(升 baseline 冒出第四个包时 `THIRD-PARTY-NOTICES.md` 不再静默漏登记),并把实际闭包打进日志;
  status 先把 CRLF 归一再分段与匹配。gate 3g 与 compliance 的 pin 一致性在无 `vcpkg.json` 时 SKIP(经典模式向后兼容,
  与 gate 1 / 4b 同口径)。已知边界:被污染的 JUCE 缓存条目不会自愈(`actions/cache` 对已存在的 exact key 不重存),
  之后每次都 warning + 全量重 clone,直到手工删缓存或 `.juce-version` 变动 —— 行为正确(缓存只加速),只是慢。
- **ixwebsocket 两平台版本一致性机器强制**:`vcpkg.json` 的 override 显式写 `"port-version": 0`(与 baseline 下的
  port 一致;version-semver 与 port-version 共同才唯一确定一份 port 内容),`compliance.yml` 新增
  "ixwebsocket cross-platform pin consistency" 步骤、`scripts/gates.ps1` 新增同参的 **gate 3g**:读 override 的
  `version-semver`,断言 override 显式带 `port-version`,且 `CMakeLists.txt` 恰有一处 `set(IXWEBSOCKET_TAG "<40 位 SHA>" ...)`
  并在同一行标注 `(= tag v<该版本>)` —— macOS 侧钉的是 SHA、机器反推不出版本号,升级时忘了动任何一侧即红。

- **打包脚本与门禁细节收口(issue #23)**:
  - `ci.yml` windows job 的 Package smoke 改为与 mac 侧同构的三次运行(`0.0.0-ci` → `0.0.0-ci2` → `0.0.0-ci`),
    断言 `package-summary.md` 恰好 2 段、`ci2` 段原样保留、`ci` 段恰好 1 条(逐行 `-ceq` 精确比对);
    五条字段行断言由 `-notmatch` 改 **`-cnotmatch`**(pwsh 默认大小写不敏感,`Version:` 漂移会静默走通)。
  - 两平台 Package smoke 增加 **`.sha256` 内容形态断言**:恰好一行、匹配 `^[0-9a-f]{64}  <zip 基名>$`
    (两个空格,`sha256sum -c` 认的格式),且 hash 与现算(`Get-FileHash` / `shasum -a 256`)一致 ——
    此前只断言文件存在,分隔符写错要到打 tag 那一刻才在 `publish` 炸出来。`package.ps1` 的 `.sha256`
    改为 **LF、无 BOM** 落盘(`WriteAllText`),Windows 侧断言读原始字节(`ReadAllBytes`,显式查 BOM、
    `\z` 锚定不放过结尾空行),`release.yml` 的 `tr -d '\r'` 兜底升级为「含 CR 即红」;
    `files:` 改为四个精确文件名与资产等式同口径。
  - `package-macos.sh` 从 `CMakeLists.txt` 回落读版本的 sed 先丢 `#` 整行注释、RE 改行首锚(POSIX ERE
    leftmost-longest 会让 `.*project` 吃到行尾注释里的旧 `project()`),`ci.yml` 的对照 grep 先剔行尾注释并加
    `|| true` 让 `::error` 守卫在 `set -e` 下真能执行;summary 重排的 awk 首行剥 UTF-8 BOM
    (旧 powershell.exe 5.1 产物)。
  - mac 侧 Package smoke 开头加跑一次**不传 `--version`** 的 `--dry-run`,断言输出里的 Version 行与
    `grep` 另取的 `CMakeLists.txt` 版本逐字相等:`release.yml` 与三次真跑全部显式传版本,脚本里从 CMake
    回落读版本的那条 BSD sed 否则在 CI 上永远不执行。
  - `release.yml` `publish` 的资产版本断言由子串包含(`*v<ver>*`)改为**整串精确等式**:按两个打包脚本的
    定式反推出四个文件名逐个要求存在,且 `dist/` 里不得有第五个文件。
  - `branch-gate.yml` DCO 步与 Frozen-contract 步的 `${{ github.repository }}` /
    `${{ github.event.pull_request.number }}` 改经 step `env`(`REPO` / `PR_NUMBER`)间接读入,
    与 `release.yml` 对 tag 名的纪律一致;逻辑不变(骨架改动,SCVB 线同步)。
  - `scripts/gates.ps1` 版本一致性 gate(3e)的 `Get-Mirror` 在 lockfile 结构变化 / JSON 不合法时不再抛异常
    中断整个 gates,改记该 gate 的 FAIL 并给出可读原因,其余 gate 照常跑完;reader 返回后再断言取值个数
    恰等于期望个数(`package-lock.json` 2 个、其余 1 个),字段消失而**不抛**的结构变化不再静默降级成少比一处。

### 发布 / 分发(对下游可见)

- `scripts/package.ps1` 的 `package-summary.md` 由整文件覆盖改为**按段追加 + 同名 `zipFileName` 段去重**,
  与 `scripts/package-macos.sh` 同口径(按记录首行 `version:` 切段、只删整行逐字相等的旧段、首条记录之前的
  内容原样透传);两个「打包唯一真源」在 summary 行为上不再分叉(issue #23)。两边物理布局也统一为
  「段间恰一个空行、文件末尾恰一个换行」;行尾一律 LF(`package.ps1` 改 `[IO.File]::WriteAllText` 写 UTF-8
  无 BOM + LF,读旧文件时 CRLF 归一;`package-macos.sh` 的 awk 先剥 CR 再比,旧 CRLF 文件的同名段也删得掉);
  `package.ps1` 写 summary 改为先写 `.tmp` 再 `Move-Item -Force`,与 mac 侧 tmp + mv 同口径。
- `scripts/package-macos.sh` 从 `CMakeLists.txt` 回落读版本号时改为带地址的单条 sed(`/re/{s//\1/p;q;}`,
  GNU / BSD 两端都通),不再 `| head -n 1`(issue #23)。

### 兼容性

- 无契约变更(wire 协议零改动),1.5.0 → 1.5.3 无需任何迁移。两个平台都建议先删除旧的 bundle 再放入新的:
  Windows 删除旧的 `Synchain Bridge.vst3` 文件夹后再复制(`Copy-Item -Recurse -Force` 覆盖同样是合并,会留下旧版本已删除的文件);
  macOS 照 README 的 Install / 安装 一节先删除旧的 `.vst3` / `.component` 再 `ditto` 新的(`ditto` 同样会合并进已有 bundle)。

## [1.5.0] — 2026-09-05

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
