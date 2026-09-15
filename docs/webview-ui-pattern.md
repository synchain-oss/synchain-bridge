# WebView UI 复刻清单（供 SCVB T26 直接引用）

> 目标读者：要从本仓复制「JUCE 8 + WebView2 玻璃拟态插件 UI」骨架的 SCVB 实施者。
> 用法：下面每一条给出**要复制哪些文件的哪些段落**（Bridge 仓内路径 + 符号 / 构造名定位）+ **坑**。
> 全文不写行号——§C 的教训同样适用于 §A/§B：失准的行号引用不会自证失效，读者照着跳过去只会落在别的段落上；
> 符号名则可随手 grep 复核。SCVB 按需逐字复制 / 改名复用；SCVB 侧设计盒定值（Output 1180×780、Input 460×560）
> 与事件/函数集按 SCVB 自己的契约重新设计，**只复用机制，不复用内容**。
>
> 与 SCVB 架构文档 01 §6.1 的复用清单逐条对应，映射表见文末「§D」。

## 0. 最小可复刻文件集（总览）

| 层 | 文件 | 作用 |
|---|---|---|
| C++ 装配 | `src/WebViewEditor.cpp` / `.h`、`src/BridgeApi.h` | WebView2 装配 / 探测 / 兜底 / resource provider / 原生桥 / Timer 节流 |
| 前端 | `web/index.html`、`web/styles.css`、`web/bridge.js`、`web/i18n.js` | 玻璃拟态卡片 + 双后端桥 + 三语字典 |
| JUCE 前端 helper | `web/js/juce/index.js`、`web/js/juce/check_native_interop.js` | JUCE 官方原生集成 helper（原样搬，不改） |
| 构建 | `CMakeLists.txt`（节选） | 静态 CRT / WebView2 NuGet / binary_data 嵌入 / 编译宏 |

---

## §A C++ WebView 装配（`src/WebViewEditor.cpp` / `.h`）

> 本仓已含**开窗遮挡闸**（SL-386，占位 + 首帧信号放行），纯逻辑与判据见 `src/WebViewRevealGate.h`
> 与 `web-preview/reveal-first-frame.test.mjs`；SCVB 是这套机制的上游（SL-370/376/378），勿重复实现。

### 1. 设计盒常量 `kDesignW/kDesignH`
- **复制来源**：`src/WebViewEditor.cpp` 的 `kDesignW` / `kDesignH`（匿名命名空间常量）
- **坑**：这里硬编码了 460×560，与 `web/index.html` 的 `DESIGN_W`/`DESIGN_H` **双处硬编码**（本仓技术债）。SCVB 侧不得再双处硬编码——设计盒唯一真源放 `web/shared/design-box.js`，构建期生成 C++ 头文件（SCVB 01 §6.1 已明确）。改任何一处必须同步另一处。

### 2. 显式选 WebView2 后端（最关键的坑）
- **复制来源**：`src/WebViewEditor.cpp` 的 `makeOptions()` 里 `withBackend(WBC::Options::Backend::webview2).withWinWebView2Options(wv2)` 段
- **坑**：Windows 上**不显式选**，`getBackend()==defaultBackend`，JUCE 8 回退到旧 IE ActiveX 控件（Win32WebView），它不支持 resource provider / native 集成，把 `https://juce.backend/` 当真实网址导航 → 「无法打开此页」。编译宏（`NEEDS_WEBVIEW2` / `JUCE_USE_WIN_WEBVIEW2`）只让代码路径存在 + 链接 loader，**不切换后端**。仅在 Windows 设 webview2 后端，非 Windows（WKWebView / WebKitGTK）走系统默认。

### 3. WebView2 user-data 目录指向临时目录
- **复制来源**：`src/WebViewEditor.cpp` 的 `makeOptions()` 里 `withUserDataFolder(...)`（`juce::File::tempDirectory` 下的 `SynchainBridgeWV2`）
- **坑**：DAW 安装目录只读会导致 WebView2 初始化失败。必须给可写目录（`juce::File::tempDirectory` 下）。

### 4. 运行时探测 + 5s 看门狗 + 原生兜底面板
- **复制来源**：探测 `src/WebViewEditor.cpp` 的 `webView2RuntimeAvailable()`；看门狗 `timerCallback()` 里的 `kWatchdogBudgetMs` 判定；兜底面板 `FallbackPanel` 类、`showFallback()`、`retryWebView()`
- **坑**：
  - 探测用**前置声明** `GetAvailableCoreWebView2BrowserVersionString`，避免引 `<WebView2.h>`/`<windows.h>` 造成 include 路径与宏污染（文件头 `extern "C"` 块）。
  - 运行时**缺失** → 立即给可操作兜底面板（引导装 Runtime + 重试），不做无意义等待；运行时**在但 5s 看门狗超时**（冷启动慢）→ 也切兜底，文案不误报「运行时缺失」。
  - 兜底面板是固定像素布局，切兜底时把窗口放大到 ≥ 设计盒（`showFallback()` 里 `kDesignW/kDesignH` 比较），否则 33% 等小档位会裁掉按钮。

### 5. resource provider + MIME 映射
- **复制来源**：`src/WebViewEditor.cpp` 的 `provideResource()`、`mimeForExtension()`
- **坑**：
  - 用 `BinaryData::originalFilenames[i]` **原始文件名匹配**，而非手工猜 JUCE 生成的 mangled 符号名（`provideResource()` 内的匹配循环）。
  - MIME 必须覆盖 html/css/js/mjs/json/svg/woff2/woff/ttf/png；`mjs` 与 `js` 都要给 `text/javascript`——**ES module 必须 JS MIME**，否则浏览器拒载（`mimeForExtension()`）。
  - resource provider 的 origin 要匹配 `WBC::getResourceProviderRoot()`（`makeOptions()` 里 `withResourceProvider(...)` 的第二参）。

### 6. 首帧同步 seed（`withInitialisationData`）
- **复制来源**：`src/WebViewEditor.cpp` 的 `makeOptions()` 里 `withInitialisationData(bridge::Init::...)` 段
- **坑**：在 WebView 首次导航前预置 `version/port/volume/lang`，JS 经 `window.__JUCE__.initialisationData` 直接读，免等一次异步往返、避免竞态。键名取自 `BridgeApi.h` 的 `Init::` 命名空间。SCVB 换成自己的首帧字段（版本、通道上限、角色 input|output、lang、uiScale 等）。

### 7. 原生函数注册 + `BridgeApi.h` 唯一真源常量
- **复制来源**：注册 `src/WebViewEditor.cpp` 的 `makeOptions()` 里 `withNativeFunction(...)` 链；常量表 `src/BridgeApi.h`（`Event::` / `Fn::` / `timing::` / `Init::`）
- **坑**：事件名 / 函数名 / 键名在 C++（`BridgeApi.h`）、`web/bridge.js`、`BRIDGE_CONTRACT.md` **三处一致**；改契约走 `BRIDGE_CONTRACT.md` §五（patch/minor/major）。每个 `withNativeFunction` 都是 lambda 转发到私有 handler，返回值经 `complete(juce::var(...))` 走 Promise。SCVB 函数集会大得多（多轨快照 / 采集 / 分析 / 波形编辑等），**复用注册模式，函数集从零设计**。

### 8. 25Hz Timer diff-then-emit 节流
- **复制来源**：`src/WebViewEditor.cpp` 的 `timerCallback()`
- **坑**：meter 用 `>0.3dB` 阈值、state/audio 用「值变化即发」，逐类独立节流，避免消息风暴。末尾 `volume` 广播是**桥 #2**（经 WS 同步网页音量条），不是桥 #1。SCVB 事件类别更多，每类独立节流。

### 9. `mBridgeReady` 就绪门控
- **复制来源**：声明 `src/WebViewEditor.h` 的 `mBridgeReady`；置 true 在 `handleRequestInitialState()`；拦截在 `timerCallback()` 开头
- **坑**：前端 `DOMContentLoaded` 后主动 `requestInitialState` 才置 true，**之前所有 emit 一律跳过**，race-free 首帧。直接复用。

### 10. 缩放机制：固定设计盒 × zoom + setSize 同步 + 10 秒防呆
- **复制来源**：C++ `src/WebViewEditor.cpp` 的 `handleSetUiScale()`、`handleCommitUiScale()`、`kDesignW/kDesignH`、`src/BridgeApi.h` 的 `plugin::MinUiScale/MaxUiScale`；web `web/index.html` 的 `layoutForMode()`/`applyScale()`（固定设计盒 + `zoom`）与 `data-confirm` 防呆段
- **坑**：
  - C++ `setSize(DESIGN×scale)` 改编辑器窗口，web 侧卡片保持**固定 DESIGN 设计盒 + `zoom:scale`** 铺满，**不读 `innerWidth`/CSS 视口**（DPI 稳健）。
  - 历史坑：v1.2.5 用过 `(100/scale)%` 视口百分比，WebView2 原生 resize 时 CSS 视口不一定同步 → F>1 露右下黑边 + 内容裁切；v1.2.6 改回固定设计盒 × zoom。
  - `setUiScale` **只实时预览、不落盘**；`commitUiScale`（防呆「保持」后）才写全局默认——避免未确认的极端档位在关窗时污染新实例（10s revert 定时器随 WebView 销毁失效）。
  - 10 秒防呆：改档位弹确认，10s 内不点或点「取消」自动回退上一个已确认档位，误选大档位也不会卡死。

---

## §B web 前端（`web/`）

### 11. 双后端桥 `bridge.js`（探测 `window.__JUCE__`，否则 mock）
- **复制来源**：`web/bridge.js` 的 `DEFAULT_PORT` 常量与 `EVT` 事件名、`makeEmitter()`、`makeJuceBackend()`、`makeWsPreviewBackend()`、`createBridge` 工厂 + `readInit`
- **坑**：UI（`index.html`）只依赖 `createBridge()`，**不直接碰** `window.__JUCE__` 或 WebSocket；事件名/函数名严格对应 `BridgeApi.h`。JUCE 前端 helper（`web/js/juce/index.js`）用**动态 import** 延迟加载（`makeJuceBackend()` 内），仅插件内存在 `window.__JUCE__` 时才 import。SCVB 把此结构复制到 `web/shared/bridge.js`，mock 后端进 `web-preview/`。

### 12. 三语字典 + `applyI18n`
- **复制来源**：`web/i18n.js` 的 `T` 字典、`dict()`、`applyI18n()`
- **坑**：静态文案走 `data-t="key"` 标签 + `applyI18n` 全量刷新；动态文案（状态/声道/按钮/提示）由 `index.html` 调 `dict(lang)` 自行渲染；未知语言回落中文。SCVB 换自己的字典键，机制不变。

### 13. 本地字体 + 字体栈回落
- **复制来源**：`web/styles.css` 的 `@font-face` 块、`:root` 字体变量（`--ff-grotesk/--ff-sans/--ff-mono`）、`html, body` 满高禁滚动段（与 §14 同一段）
- **坑**：DAW 离线，**无 Google Fonts / CDN**；子集 WOFF2 随插件打包（`CMakeLists.txt` 的 `juce_add_binary_data(SynchainBridgeWebAssets ...)` 里的四项 `web/fonts/*.woff2`）。CJK 走内嵌 `Noto Sans SC`（排在拉丁字体之后、系统字体之前），`font-display:swap` + `font-synthesis:none` 保证离线确定性渲染、不阻塞、不发糊。子集脚本见 `web/fonts/README.md`。
- **命名**：拉丁正文/等宽两族以 `Bridge Sans` / `Bridge Mono` 分发——子集 = OFL 意义上的 Modified Version，§3 的保留字体名不许沿用，故分发名与上游家族名不同（来源家族与核验见 `THIRD-PARTY-NOTICES.md`）。SCVB 复制时若子集同一上游家族，需自取一个不含保留字体名的分发名。

### 14. 视口锁死 + 玻璃拟态卡片
- **复制来源**：`web/index.html` 的 `#vst-root` 与 `data-card` 元素（含内联样式）、玻璃面板块；`web/styles.css` 的 `html, body` / `#vst-root` 段
- **坑**：`#vst-root` 用 `position:fixed; inset:0; overflow:hidden` 永不滚动/露白；卡片固定设计盒 + `zoom:F` 铺满（尺寸只用常量、不读视口，DPI 稳健）；内容列 `flex:1 + justify-content:space-between` 让各区块均匀铺满高度、页脚贴底，消除上下暗带。

### 15. 电平表 rAF 弹道
- **复制来源**：`web/index.html` 的 `buildMeters()`、`meterTick()`（内含 `requestAnimationFrame` 弹道）；`web/styles.css` 的设计说明注释
- **坑**：绿条 fast-follow + 白色 peak-hold 线，rAF 弹道驱动；按**真实声道数**动态建条（mono 1 条 / stereo 2 条）；停止态弹道复位归零（不再用 CSS 静息宽度）。SCVB 电平/响度曲线可在此模式上扩展。

### 16. 状态灯三态派生
- **复制来源**：语义 `BRIDGE_CONTRACT.md` §一 C++→JS 事件表的 `bridge.state` 行（`running + clients` 派生 online/waiting/offline）；渲染 `web/index.html` 的 `renderAll()`/`setRunning()`（写 `data-conn`/`data-run`）；样式 `web/styles.css` 的 `#vst-root[data-conn=...]` 段
- **坑**：状态灯反映**真实连接**（`clients==0` 时为 waiting 琥珀，让用户察觉链路已断），非仅服务启停。SCVB 组胶囊可复用「状态派生 + 数据来源标注」。

### 17. 缩放档位下拉 + 防呆确认 UI
- **复制来源**：`web/index.html` 的 `data-scale` 下拉与 `data-confirm` 弹层（含 `data-confirm-countdown` / `data-confirm-keep` / `data-confirm-cancel`）
- **坑**：改档位 → 立即应用 + 弹防呆确认（倒计时 + 保持/取消）；确认弹层是 `#vst-root` 的直接子元素（与卡片同级、不受卡片 `zoom` 影响），任意档位都居中可读。

---

## §C CMake 构建骨架（`CMakeLists.txt`）

> 本节一律按 **CMake 构造名**定位，不写行号：`CMakeLists.txt` 每加一个平台就整体移位（macOS 支持一次就把
> `project()` 之后的内容推下 12～48 行），而失准的行号引用不会自证失效——读者照着跳过去只会落在别的段落上。

### 18. 静态 CRT 在 `project()` 之前
- **复制来源**：`CMakeLists.txt` 开头、`project()` **之前**的那一段（`CMAKE_MSVC_RUNTIME_LIBRARY` + `CMAKE_CXX_STANDARD`）
- **坑**：`/MT` 必须写在 `project()` 之前，与 `x64-windows-static` triplet 和 WebView2 静态 loader 对齐；顺序颠倒 → LNK2038。

### 19. WebView2 NuGet 配置期自动拉取
- **复制来源**：`CMakeLists.txt` 的 `if(WIN32)` WebView2 块（`WEBVIEW2_VERSION` → `nuget install` → `JUCE_WEBVIEW2_PACKAGE_LOCATION`）
- **坑**：JUCE `NEEDS_WEBVIEW2` 只查找+链接、不下载；拉取到确定性目录 `build/packages` + `JUCE_WEBVIEW2_PACKAGE_LOCATION`，不依赖 `%USERPROFILE%`（CI 可复现）。

### 20. `juce_add_binary_data` 资源嵌入
- **复制来源**：`CMakeLists.txt` 的 `juce_add_binary_data(SynchainBridgeWebAssets SOURCES ...)` 整块
- **坑**：生成 `BinaryData::*` 静态库，resource provider 按 `originalFilenames` 反查原始文件名（见 §A 条目 5）。SCVB 只换 `SOURCES` 列表为自己的 web 资源文件名，并相应换 BinaryData 命名空间。

### 21. 编译宏组合
- **复制来源**：`CMakeLists.txt` 的 `# --- Compile Definitions ---` 段（`target_compile_definitions(... PUBLIC ...)` 加其后的 `if(WIN32)` 分支）
- **坑**：`JUCE_WEB_BROWSER=1` + `JUCE_USE_WIN_WEBVIEW2=1` + `JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING=1` 三者必要且易漏；`juce_add_plugin` 还要 `NEEDS_WEBVIEW2 TRUE` 参数。

---

## §D 与 SCVB 01 §6.1 复用清单的映射

| 01 §6.1 机制 | 本清单条目 |
|---|---|
| WebView2 后端显式选择 | §A 2（`makeOptions()` 后端段） |
| user data folder 指向临时目录 | §A 3（`makeOptions()` 的 `withUserDataFolder`） |
| 运行时探测 + 5s 看门狗 + FallbackPanel | §A 4（`webView2RuntimeAvailable()` / `timerCallback()` / `FallbackPanel`） |
| resource provider + MIME 映射 | §A 5（`provideResource()` / `mimeForExtension()`） |
| `withInitialisationData` 首帧 seed | §A 6（`makeOptions()` seed 段） |
| `withNativeFunction` 注册 + `BridgeApi.h` 真源 | §A 7（`makeOptions()` 注册链、`BridgeApi.h`） |
| 25Hz Timer diff-then-emit 节流 | §A 8（`timerCallback()`） |
| `mBridgeReady` 门控 | §A 9（`WebViewEditor.h` 的 `mBridgeReady`、`handleRequestInitialState()`） |
| 缩放：设计盒 + zoom + setSize + 10s 防呆 | §A 10（`handleSetUiScale()` / `handleCommitUiScale()`、`layoutForMode()` / `applyScale()`） |
| 双后端 bridge.js | §B 11（`web/bridge.js` 的 `createBridge`） |

> 另：`AudioMeter` 类（`src/AudioMeter.h/cpp`）是 dBFS 峰值+保持计算，SCVB 每轨电平/响度展示可复用或扩展（注意它只做瞬时 dBFS 峰值，不是 LUFS/RMS 响度）。
