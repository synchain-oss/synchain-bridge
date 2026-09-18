# Changelog

> **v1.3.1 及更早版本的 git 历史与 Release 位于 Synchain 私有单体仓库(`DLsnows/Synchain`)。** 本文件仅回填这些版本的 release body 文字内容;旧 tag 不迁移到本仓(D6 全新首 commit,08 §3.4)。
>
> 首个公开版本 = **v1.4.0**(U6)。协议类改动记录在对应版本的「契约变更」小节。

## [未发布]

> 版本号由 1.5.0 升至 **1.5.3**(唯一真源 `CMakeLists.txt` 的 `project(... VERSION)`,四镜像同步:
> web-preview 的 mock-server.mjs / package.json / package-lock.json 与 `BRIDGE_CONTRACT.md` §三)。
> 1.5.1 / 1.5.2 / 1.5.3 三批改动都在本段:1.5.1 与 1.5.2 **都没有发过 tag / Release**,各出过一个
> 内部测试包 —— 1.5.3 这个号存在的理由就是让用户手上那个包与他已经测过的 1.5.2 能分辨开。
> **三批都不涉及契约变更**(wire 协议零改动;`__bridge__firstFrame` 时序信号及其载荷里的诊断字段
> 均为非契约面,判定与兼容性承诺见 `docs/contract-changes/20260914-sl386-reveal-gate.md` 与
> `docs/contract-changes/20260918-sl433-first-frame-paint-delta.md`)。

### 修复

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
    宿主(pluginval)上实测 8/8 都有 paint 记录(`after N ms` ≈ 710~780 ms,不是保险路的 ≈2500),
    ⇒ 本机上成立。但**那不是用户的 DAW**,所以上面那条回滚判据照写不误。
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
     (tick 数 ∧ 32 ms 毫秒下界,回绕安全)才挪回;3 s 超时兜底(绝不允许「永远不放行」)。
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
- `scripts/package.ps1` 的 `package-summary.md` 由整文件覆盖改为**按段追加 + 同名 `zipFileName` 段去重**,
  与 `scripts/package-macos.sh` 同口径(按记录首行 `version:` 切段、只删整行逐字相等的旧段、首条记录之前的
  内容原样透传);两个「打包唯一真源」在 summary 行为上不再分叉(issue #23)。两边物理布局也统一为
  「段间恰一个空行、文件末尾恰一个换行」;行尾一律 LF(`package.ps1` 改 `[IO.File]::WriteAllText` 写 UTF-8
  无 BOM + LF,读旧文件时 CRLF 归一;`package-macos.sh` 的 awk 先剥 CR 再比,旧 CRLF 文件的同名段也删得掉);
  `package.ps1` 写 summary 改为先写 `.tmp` 再 `Move-Item -Force`,与 mac 侧 tmp + mv 同口径。
- `scripts/package-macos.sh` 从 `CMakeLists.txt` 回落读版本号时改为带地址的单条 sed(`/re/{s//\1/p;q;}`,
  GNU / BSD 两端都通),不再 `| head -n 1`(issue #23)。
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
