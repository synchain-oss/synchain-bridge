# Synchain Bridge — 桥接契约（冻结）

> 本文件是插件端与 Synchain 网页客户端之间的**接口契约真源**；改动流程见 §五。
> C++ 常量真源见 `BridgeApi.h`。

插件里存在**两条独立的桥**，切勿混淆：

| | 桥 #1：编辑器内 WebView ↔ C++ | 桥 #2：VstBridgeServer ↔ 浏览器 |
|---|---|---|
| 作用 | 驱动插件窗口 UI（本地进程内） | 把 DAW 音频推流给外部 Creative Space 浏览器客户端 |
| 传输 | JUCE 原生集成 `window.__JUCE__`（`withNativeFunction` / `emitEvent`） | 本地 WebSocket（ixwebsocket，`127.0.0.1`） |
| 数据源 | processor 原子量（电平/状态**不走 WebSocket**） | PCM 二进制帧 + JSON |
| 契约方 | `WebViewEditor.cpp` ↔ `web/bridge.js` | `VstBridgeServer.cpp` ↔ Synchain 网页应用（闭源） |

---

## 一、桥 #1：编辑器内 JS ↔ C++ API

### C++ → JS 事件（编辑器 `juce::Timer` @25Hz 读 processor 原子量后 `emitEventIfBrowserIsVisible`，仅 message 线程）

| event id (`BridgeApi.h` Event::) | payload | 触发 |
|---|---|---|
| `bridge.state` | `{running:bool, clients:int, port:int}` | `running` 或 `clients` 变化时。状态灯由 JS 按 **running + clients** 派生：`online`（有浏览器客户端在桥，绿）/ `waiting`（已启动但 `clients==0`，琥珀——让用户察觉链路未通/已断）/ `offline`（未启动，灰）；文案按当前语言派生、**不发本地化文案**（v1.2.7 起状态灯反映真实连接，非仅服务启停） |
| `bridge.meter` | `{l:number 0..1, r:number 0..1, ldb:number dBFS, rdb:number dBFS, peak:number dBFS}` | 运行中且电平变化超阈值时。**web 侧以 `ldb/rdb`（dBFS）为准**驱动 rAF 弹道（fast-follow 绿条 + peak-hold 白线，dB→% 映射 -60..0）；`l/r`（线性）保留兼容、当前 UI 不用。停止时不发，JS 弹道复位归零 |
| `bridge.audio` | `{sampleRate:int, channels:int, latencyMs:number}` | prepareToPlay / 总线变化时。`latencyMs = 1000*blockSize/sampleRate` |
| `bridge.error` | `{code:string, message:string}` | 端口占用等 |

### JS → C++ 原生函数（`withNativeFunction` 注册；JS `getNativeFunction(id)(...args)` 返回 Promise，由 C++ completion 决议）

| fn (`BridgeApi.h` Fn::) | 参数 | 返回 | 作用 |
|---|---|---|---|
| `requestInitialState` | `[]` | `{running,clients,port,volume,lang,uiScale,version,sampleRate,channels,latencyMs}` | **DOMContentLoaded 调用一次**：race-free 首帧 + 置 C++ `mBridgeReady=true`（此后才允许 emit） |
| `toggleRun` | `[shouldRun:bool]` | `{running:bool, port:int, error?:string}` | start→`server.start(port)`（尝试 `port..port+9`，返回实际绑定端口）；stop→`server.stop()` |
| `setPort` | `[port:int]` | `{ok:bool, port:int}` | 校验 `1024..65535`；存入插件状态；运行中改端口的策略：defer 到下次 start（占用时回 `bridge.error`） |
| `setMasterGain` | `[pct:int 0..200]` | `{ok:bool}` | 写 APVTS `masterGain = pct/200`（归一化 0..1 ↔ 0..2 gain）；**只作用推流副本** |
| `setLang` | `[code:"zh"\|"en"\|"fr"]` | `{ok:bool}` | 持久化语言，重开编辑器恢复 |
| `setUiScale` | `[scale:float 0.33..3.0]` | `{ok:bool, scale:float, w:int, h:int}` | 仅缩放编辑器窗口（`setSize = DESIGN×scale`，DESIGN=460×560）做**实时预览**。web 侧卡片为**固定 DESIGN 设计盒 + `zoom:scale`**（渲染=DESIGN×scale=编辑器窗口，精确铺满、内容不裁；**不读 `innerWidth`/CSS 视口**）。v1.2.5 曾用 `(100/scale)%` 视口百分比，但 WebView2 原生 resize 时 CSS 视口不一定同步 → F>1 露右下黑边+内容裁切，**v1.2.6 改回固定设计盒×zoom**。web 改档位先弹**防呆确认**（10s 不点或取消→回退上一个已确认档位）。**注意：`setUiScale` 不写全局默认**——避免未确认极端档位在关窗时污染新实例 |
| `commitUiScale` | `[]` | `{ok:bool, scale:float}` | 防呆确认「保持」后调用：把当前（已确认）`uiScale` 写入**全局默认**设置文件 `userAppData/Synchain/SynchainBridge.settings`（`persistUiScaleAsDefault`），新实例/新工程沿用上次尺寸。每工程比例另存于 APVTS state（`uiScale`，`get/setStateInformation`），`requestInitialState` 快照含 `uiScale` |

### 关键约束（JUCE 8，已核对头文件）
- `emitEventIfBrowserIsVisible` 只能在 **message 线程** 调用，且必须在首个 `goToURL()` + 前端脚本就绪之后 → 所有 emit 用 `mBridgeReady` 门控。
- 首帧用 `withInitialisationData`（`version/port/volume/lang`）同步 seed，再由 `requestInitialState` 拉活快照。
- 沿用核对过的 API：`Options.withBackend/withNativeIntegrationEnabled/withNativeFunction/withResourceProvider/withWinWebView2Options/withInitialisationData`；`WebBrowserComponent.goToURL/emitEventIfBrowserIsVisible/getResourceProviderRoot`。**Windows 必须显式 `withBackend(Options::Backend::webview2)`**——否则 `getBackend()==defaultBackend`，JUCE 回退旧 IE ActiveX 控件（`Win32WebView`，不支持 resource provider / native 集成，会把 `https://juce.backend/` 当真实网址导航失败）。编译宏 `JUCE_USE_WIN_WEBVIEW2` / `NEEDS_WEBVIEW2` 只让 WebView2 代码路径存在 + 链接 loader，**不切换后端**。
- 前端引入 JUCE 官方 helper `web/js/juce/index.js`（`import { getNativeFunction } from "./js/juce/index.js"`）。

### 主音量语义（决策 #4）
- `masterGain` 是 APVTS `AudioParameterFloat`，`NormalisableRange{0,2}`，默认 `1.0`；获 DAW 自动化 + 状态持久化。
- `processBlock`：**`buffer` 原样穿透，绝不缩放**；仅把 `L*gain / R*gain` 写入推流 work buffer 再 `sendPcmPacket`。
- 电平表测**推流后**电平（gain=0 时表归零，符合「主控音量=推流电平」语义）。

---

## 二、桥 #2：WS 浏览器协议不变量（改动后必须仍满足 Synchain 网页应用的 WS 客户端实现）

本次所有插件改动**只增不改**协议，对浏览器客户端零破坏。

1. **二进制 PCM 帧**：小端；12 字节头 = `u32 sampleRate | u32 channels | u32 numSamples`，紧跟 `numSamples*channels` 个 `float32` interleaved。总字节 = `12 + numSamples*channels*4`。字段顺序/端序/偏移不可变。主音量增益作用在**样本值**，帧格式完全不变。
2. **客户端校验边界**（`handleBinaryFrame`）：帧 `<12` 丢；`numSamples===0 || >16384` 丢；`channels===0 || >16` 丢；`byteLength < 12+numSamples*channels*4` 丢。
3. **JSON 文本帧**含 `type` 字段，精确 snake_case：
   - plugin→browser：`status` / `meter` / `settings` / `volume` / `error` / `ping`
   - browser→plugin：`handshake` / `get_settings` / `set_settings` / `set_volume` / `pong`
   （`get_settings`/`set_settings`/`set_volume` 等名字不可改）
4. `status`：`{type:"status", connected:bool, pluginName:string, version:string, volume:int(0..200)}`。客户端收到即置 connected、回请 settings，并按 `volume` 初始化 DAW 音量条与插件同步（`volume` 为 v1.2.8 新增可选字段，旧客户端 `??` 兜底忽略）。
   - `set_volume`（browser→plugin，v1.2.8）：`{type:"set_volume", volume:int(0..200)}`。让**网页 DAW 音量条直接控制 VST 主控音量参数**（`masterGain`）：clamp[0,200]，作用于推流 PCM（同时电平表随之变化，因计量的是增益后 PCM）。浏览器侧不再施加 GainNode 增益（避免双重增益）。**应用路径（v1.2.10 修）**：回调在 WS 线程只存原子（`requestWebVolume`），由 message 线程的 Timer `consumePendingWebVolume`+`setVolumePct`——取代 v1.2.9 的 `MessageManager::callAsync`（实测某些宿主不可靠执行、致网页调音量对插件无效）。**双 Timer 消费**：编辑器 Timer（打开时）+ Processor 自身 Timer（覆盖编辑器关闭场景），经原子 exchange 双消费安全。
   - `volume`（plugin→browser，v1.2.9）：`{type:"volume", volume:int(0..200)}`。插件 UI/宿主改主控音量时，插件经编辑器 Timer 检测变化并广播此帧，网页据此**实时更新** DAW 音量条显示（不再需重连才同步）。**单向显示语义**：网页收到只 `setVstVolume`、**不回送** `set_volume`；仅用户拖网页滑杆才 `set_volume` → 避免回环/双向拖动打架（v1.2.9 双向实时同步）。
5. `meter`：`{type:"meter", left:number, right:number, peak:number}`（dBFS，约 -60..0，容忍 `-Infinity`）。
6. `settings`：`{type:"settings", sampleRate:int, bufferSize:int, channels:int, opusBitrate:int}` 四字段**名字/类型不变**；**新增 `latencyMs:number` 为可选附加字段**（旧客户端 `??` 兜底忽略）。
7. `handshake`：`{type:"handshake", projectId, userId, username}`。
8. `ping`/`pong`：plugin 发 `{type:"ping", timestamp}`，browser 回 `{type:"pong", timestamp}`。
   - **心跳时序（Synchain issue 170，非 wire 破坏——仅把已冻结的 ping/pong 契约真正实现）**：服务端独立线程每 ~5s 向每个连接发 `ping` 并跟踪 per-client 最后 `pong` 时刻；距上次 `pong` 超 ~12s（有效 ~15s，两个 ping 周期）则 `close(4408,"heartbeat timeout")`。web 侧在**观测到至少一次服务端 ping 后**启动「入站静默」监测：入站帧沉默 >20s 判定半开 → 主动 `ws.close()` 触发既有有界重连。能力探测（先见 ping 再启监测）确保「新 web + 旧插件（不发 ping）」在 DAW 空闲时不会误重连。阈值均为常量、无 wire 变更，旧客户端（已能被动应答 ping）保持兼容。
9. server 只绑 `127.0.0.1`，尝试 `base..base+9`，UI 显示实际绑定端口。

> **PCM 投递语义（Synchain issue 168）**：为把 WS 发送移出音频线程（实时安全），PCM 现由后台发送线程经 SPSC ring 转投，属**解耦的 best-effort**——慢/停滞客户端下背压时服务端**丢最新帧**（计入 `droppedPacketCount`）而非阻塞音频回调，并增加 ring 深度 + ≤5ms 轮询的少量投递延迟。帧字节格式完全不变，web 端无需改动。

> 注意：`settings.channels` = 展示用真实输入声道；**PCM 帧头 channels 恒为 2**（mono 时复制右声道）。二者语义不同，勿混用。

---

## 三、命名 / 版本常量（命名真源 `BridgeApi.h` synchain::plugin::；版本真源 CMake）

| 项 | 值 |
|---|---|
| PRODUCT_NAME | `Synchain Bridge` |
| COMPANY_NAME | `Synchain` |
| VERSION | `1.3.1`（单一真源：`CMakeLists.txt` `project(VERSION)` → `JucePlugin_VersionString`；status 上报与插件 WebView UI 统一取此宏，`BridgeApi.h` 不再手写版本常量） |
| BUNDLE_ID | `com.synchain.bridge` |
| PLUGIN_MANUFACTURER_CODE | `Snch` |
| PLUGIN_CODE | `Snb1` |
| 默认端口 | `9420`（可配置 1024..65535） |
| C++ namespace | `synchain` |
| 产物 | `Synchain Bridge.vst3` |

> ⚠️ 改厂商码/插件码 → 新 VST3 唯一 ID，DAW 视为**全新插件**（旧工程不自动映射）。README 需注明。

---

## 四、默认端口取舍：9420

设计稿显示 8765，但现有 web 契约三处锁死 9420（`preferredPort`、mock server 的 `PORT`、连接面板 placeholder，均位于网页侧闭源仓库）。**采纳默认 9420**：把设计 HTML 转 `web/index.html` 时，两处纯展示默认值 8765→9420（零协议风险）。
