# Synchain Bridge —— DAW 端到端实测指南

目标：在真实 DAW 里插入 **Synchain Bridge**，把 DAW 播放的声音经本地 WebSocket → 浏览器 → LiveKit 推到 Creative Space 房间，验证「另一名参与者能听到你 DAW 的声音」。

下面的「步骤」以 Windows + VST3 为例；Pro Tools（AAX，Windows / macOS）的安装与检查表见文末 [Pro Tools（AAX）实测](#pro-toolsaax实测windows--macos)，浏览器与房间侧的操作（步骤 4–6）两者通用。

前置：

- 从 [GitHub Releases](https://github.com/synchain-oss/synchain-bridge/releases) 下载最新的 `SynchainBridge-VST3-<版本>-win64.zip` 并解压出 `Synchain Bridge.vst3`。
- 有一个可登录的 Synchain 账号，且是目标项目的**可编辑成员**（viewer / 非成员无法建立 DAW 音频轨）。
- 一条有实际音频素材、正在出声的轨道或母线。

---

## 步骤

### 1. 安装 .vst3 到系统目录或扫描路径

`Synchain Bridge.vst3` 是 **bundle 目录**（不是单文件），二选一：

- **系统目录（需管理员）**：整个文件夹拷到 `C:\Program Files\Common Files\VST3\`。换版本测试前先删除旧文件夹 ——
  `Copy-Item -Force` 会合并进已有 bundle，留下旧版本的文件：
  ```powershell
  Remove-Item "C:\Program Files\Common Files\VST3\Synchain Bridge.vst3" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "<解压路径>\Synchain Bridge.vst3" "C:\Program Files\Common Files\VST3\" -Recurse -Force
  ```
- **免管理员**：放任意目录，在 DAW 里把该目录加为 VST3 扫描路径后重扫
  （Reaper：选项 → 偏好 → 插件/VST → 添加路径 → 重新扫描）

### 2. 在 DAW 新建工程并插入插件

- 用 Reaper / Ableton Live / Cubase 等任一支持 VST3 的宿主，新建工程。
- 在**一条有音频的立体声轨道或母线**上插入 **Synchain Bridge**（厂商码 `Snch` / 插件码 `Snb1`）。
- 确保该轨 / 母线正在播放并有信号经过（能在 DAW 里听到声音）。

### 3. 打开插件窗口并开启桥

- 打开 **Synchain Bridge** 插件窗口。
- 点「**开始传输**」——插件在 `127.0.0.1:9420` 起 WebSocket 服务（端口占用会自动重试 9420–9429，面板显示实际端口）。
- 记下面板显示的端口号（若不是 9420，浏览器侧要用这个）。
- **界面缩放**：面板右下角有缩放档位下拉（33%–300%），按显示器大小选择即可即时缩放窗口。
  - 改档位后弹**确认弹窗**（类 Windows 改分辨率）：**10 秒**内不点或点「取消」自动恢复上一个尺寸，点「保持」生效——即使误选过大档位看不到按钮，10 秒后也会自动回退，不会卡死。
  - 所选比例**双重记忆**：随工程保存（同一工程重开恢复）+ 全局记住（新实例 / 新工程也开在上次尺寸，不用每次重设）。
  - 任意档位、任意 DAW 窗口都**不应出现滚动条或四边白边**（v1.2.5 修复高 DPI 缩放溢出）；改档位后卡片**铺满整个编辑器窗口、右下无黑边、内容完整**（START 按钮 / 页脚可见）（v1.2.6 把缩放改为固定设计盒×zoom，修右下黑边+内容裁切）。

### 4. 浏览器打开 Creative Space 房间

- 打开 Synchain 网页端的 **dev 部署**（`https://dev.synchain.cn` / `https://dev.synchain.ca`），**先登录**。
  > 别用预览部署：Releases 提供的是**默认构建**，其 Origin 白名单只含 `synchain.cn`/`.ca` 系域与本地回环，
  > 预览域名一律被 4403 拒（见下方「Origin 被拒 / 连不上」）。确实要用预览域，需以
  > `-DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS` 注入该域**重新构建插件**，见 [build-windows.md](build-windows.md)。
- 进入目标项目的 **Creative Space** 房间；确认账号是该项目的**可编辑成员**。

### 5. 房间左栏「DAW 音频桥」卡开启推流

- 在房间左栏找到「**DAW 音频桥**」卡。
- 确认端口为 **9420**（若插件自动避让到别的端口，把该端口填进来）。
- 开启 **推流 / broadcast**。若自动连接失败，把插件显示的端口手动填入后重连。

### 6. 期望结果

- **插件侧**：状态灯（v1.2.7 起反映真实连接）——点「开始传输」后先显示**琥珀「等待连接」**（桥已起、浏览器尚未连），浏览器一连上即转**绿「在线」**、客户端数 ≥ 1；若浏览器关闭/断开，状态灯会回落「等待连接」（便于察觉链路断了）。电平表随 DAW 播放**实时跳动**（绿条 + 白色峰值保持线），条数随输入声道自适应：**单声道 1 条、立体声 2 条**；网页 DAW 卡的「声道」也随之显示**单声道/立体声真实值**（v1.2.7 修早前恒显立体声）；未开始传输时电平表归零。
  - **面板三个读数均为 host 真实值**：采样率 = host 传给 `prepareToPlay` 的采样率；声道 = host 输入声道数；**缓冲延迟** = `1000 × 缓冲块大小 ÷ 采样率`（即一个音频缓冲块的时长，如 256 samples @ 48 kHz = 5.3 ms）。注意「缓冲延迟」是**音频缓冲块时长**，**不是**插件附加延迟（本插件不引入额外延迟，pluginval 报告 0），也**不是**到浏览器 / LiveKit 的端到端延迟。插件加载但 host 尚未 `prepareToPlay` 前，显示占位默认 48.0 kHz / 5.3 ms。
- **房间侧**：房间里出现一条名为 **「DAW Audio (VST)」** 的音轨。
- **音量双向实时同步（v1.2.9）**：网页「DAW 音频桥」卡的音量条与插件主控音量**实时联动**——在网页拖音量条，插件的主控音量（及推流电平）立即随动；反过来在**插件面板**（或宿主自动化）改主控音量，网页音量条也**立即更新显示**（不再需断开重连才同步）。两侧拖动不会互相打架。
- **协作者侧**：另一名参与者（或用另一设备 / 另一账号开第二个会话）进入同一房间后，**能听到你 DAW 播放的声音**。

---

## 常见排障

- **插件窗口显示英文兜底面板 / 报「无法打开此页 `https://juce.backend`」/ 看不到玻璃 UI**：v1.2.3 修复了根因——此前 Windows 未显式选 WebView2 后端，JUCE 回退到旧 IE 控件、无法加载前端；v1.2.3 起显式走 WebView2，并保留运行时探测 + 5s 加载看门狗。若面板提示缺 WebView2 运行时，点「Download WebView2 Runtime」一次性安装（本插件本就需联网使用），装好后**重新打开插件窗口**即恢复完整界面；绝大多数 Win10/11 已自带该运行时。
- **端口占用**：插件默认 9420，被占用时自动在 **9420–9429** 逐个避让；以插件面板显示的端口为准，并在浏览器「DAW 音频桥」卡填相同端口。
- **房间获取 token 返回 503**：多为**预览环境缺 LiveKit env**（LiveKit 密钥 / URL 未注入预览部署）。改用已配置 LiveKit 环境变量的 **dev 部署**重试。
- **Origin 被拒 / 连不上**：WS 服务端只接受确切白名单来源（`localhost` / `127.0.0.1` / `[::1]`、`https://synchain.cn`|`.ca`、`https://www.synchain.cn`|`.ca`、`https://dev.synchain.cn`|`.ca`，以及无 Origin 的原生客户端）。**预览部署等额外来源不写进源码，由构建期注入**（配置时传 `-DBRIDGE_EXTRA_ALLOWED_ORIGIN_HOSTS`，见 [build-windows.md](build-windows.md)）——**公开仓的默认构建不放行任何额外来源**，装的若是默认构建，预览域名一律连不上（安全收窄，见 Synchain issue 167）。不在白名单的域名打开会被 4403 拒——请用 `localhost`/`127.0.0.1` 或上述 Synchain 域访问。
- **电平不跳 / 无信号**：确认插件插在**有音频经过**的轨 / 母线上，且 DAW 正在播放；主音量滑块只影响推流副本，若为 0% 则推流静音。
- **听不到声音但轨道已出现**：确认协作者已加入同一房间、未静音该轨；第二会话建议用不同账号 / 设备，避免同机回声抑制影响判断。

---

## Pro Tools（AAX）实测（Windows / macOS）

本节只用于 AAX 版本（Beta），两个平台通用。表中的检查项和期望结果是本项目自己的验收口径，不是任何第三方测试计划的转述。

### 前置条件

- 被测件三选一：
  - **签名的发行件** `SynchainBridge-AAX-v<版本>-win64.zip` / `SynchainBridge-AAX-v<版本>-macos-arm64.zip`（Releases，零售版 Pro Tools 可加载）；
  - **CI 产出的未签名件**：`ci.yml` 的 artifact `aax-unsigned-win64` / `aax-unsigned-macos-arm64` 里的
    `SynchainBridge-AAX-v<版本>-ci.<短 sha>-<平台>-UNSIGNED.zip`；
  - **本地构建**（Windows 可用 `pwsh scripts/build.ps1 -InstallAax` 一步装好，见 [build-windows.md](build-windows.md#aaxpro-tools)）。

  后两种都是**未签名件，只能在 Pro Tools Developer 里加载**。
- Pro Tools **原生**运行（macOS 上不得勾 Rosetta）。
- 同上文的 Synchain 账号、项目成员身份和一条有信号的轨道。
- 抓诊断日志：Windows 上开 Sysinternals DebugView（Capture Win32），过滤 `SynchainBridge:`；macOS 上从「终端」启动 Pro Tools，
  日志在终端里（诊断行的完整文案见 [build-windows.md 的「诊断日志」](build-windows.md#诊断日志)）。

### 安装

先校验 `.sha256`（与 zip 放在同一目录：Windows 用 `Get-FileHash`，macOS 用 `shasum -a 256 -c`），解压后整体复制，不要改动 bundle 里的任何文件。
zip 里的 `INSTALL-AAX.txt` 是同一组命令。

- **Windows（管理员 PowerShell，先退出 Pro Tools；`$env:CommonProgramW6432` 恒指向 64 位的 Common Files）**：
  ```powershell
  Remove-Item "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\Synchain Bridge.aaxplugin" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "<解压路径>\Synchain Bridge.aaxplugin" "$env:CommonProgramW6432\Avid\Audio\Plug-Ins\" -Recurse -Force
  ```
- **macOS（先退出 Pro Tools）**：
  ```bash
  sudo rm -rf "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
  sudo ditto "<解压路径>/Synchain Bridge.aaxplugin" "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
  sudo xattr -dr com.apple.quarantine "/Library/Application Support/Avid/Audio/Plug-Ins/Synchain Bridge.aaxplugin"
  ```

重启 Pro Tools 后，在插入点按名称查找 **Synchain Bridge**。插件的 AAX 类别登记为 None，菜单按类别组织时可能出现在 *Other* 下，而不是某个分类组。

### 已知口径（测试时不要误报为缺陷）

- 只有 mono→mono / stereo→stereo 的 insert；没有 AudioSuite、没有 multi-mono。
- 离线渲染（离线 bounce、Track Commit、Freeze）期间音频原样直通，不计量、不向网页推流，渲染结束后恢复；只对 AAX 版生效。
- Dynamic Plug-in Processing（DPP）开启时，没有音频送进插件（轨道静音或无声）可能让 Pro Tools 停止调用插件，推流随之暂停。
- JUCE 的 AAX 封装恒以 1024 采样初始化插件，面板的缓冲延迟读数按 1024 计（48 kHz 约 21.3 ms），与硬件缓冲无关。
- Windows 的签名证书是自签名的，「数字签名」页显示不受信任属预期；macOS 未经公证，需要 `sudo xattr`。

### 检查表

步骤 4–6 指上文「步骤」一节里的浏览器与房间操作。「日志」列是 DebugView / 终端里应看到的诊断行（前缀 `SynchainBridge:` 省略）。

| ID | 测试项 | 期望结果 | 日志 |
|---|---|---|---|
| P-mac | Pro Tools 原生运行（仅 macOS） | 「显示简介」里没勾 Rosetta；活动监视器里「种类」为 Apple | — |
| T01 | 扫描与分类 | 名称 Synchain Bridge、厂商 Synchain；类别与登记值（None）一致；没有签名或授权报错 | — |
| T02 | mono 轨和 stereo 轨各插一个 | 电平条数分别为 1 / 2；网页 DAW 卡的声道显示为单声道 / 立体声 | 打开编辑器时 `editor opened: host=ProTools wrapper=AAX … io=1/1`（stereo 轨为 `io=2/2`） |
| T03 | 可用形态 | AudioSuite 里找不到；插入菜单里没有 multi-mono 形态 | — |
| T04 | 编辑器开关 ×10 | 无白闪、无崩溃，内存基本稳定 | 每次打开一行 `editor opened: …` |
| T05 | 系统显示缩放 100 / 150 / 200%（macOS 用 Retina 屏和外接屏各试），再在插件里切几档缩放 | 无滚动条、无白边；缩放档位正常生效 | 不应出现 `ui scale resize not applied by host: …` |
| T06 | 端口框输入 | 数字、空格、回车不会被 Pro Tools 的快捷键吞掉；回车后端口生效 | — |
| T07 | 推流 | 按步骤 4–6 操作，房间里出现音轨，协作者能听到 | — |
| T08 | 同时开两个实例 | 第二个实例显示 9421（避让范围 9420–9429） | — |
| T09 | 保存工程后重开 | 端口、主音量、缩放、语言等设置恢复 | — |
| T10 | 离线 bounce | bounce 期间网页侧收不到帧；bounce 结束后实时推流恢复 | `host non-realtime on (wrapper=AAX)` → 结束后 `… off (wrapper=AAX)`（处理器侧 30 Hz 轮询，极短的切换可能漏记） |
| T11 | 对 Stream Master 写自动化再回放 | 插件滑块与网页音量都随自动化变化 | — |
| T12 | 改 H/W 缓冲（64–1024）和采样率（44.1 / 48 / 96 kHz） | 面板读数更新、不崩溃、推流不断 | 采样率变化时 `audio: sampleRate=… channels=… latencyMs=…`（缓冲读数恒按 1024 计） |
| T13 | 移除实例 | 端口被释放（Windows：`netstat -ano \| findstr 9420`；macOS：`lsof -iTCP:9420`，都查不到），新实例重新拿到 9420 | — |
| 可选 | AAX Validator | 把结果附在 PR 描述里（工具与日志不入库；接入方式见 [build-windows.md](build-windows.md#可选aax-validatortodo-aaxval)） | — |

---

> 说明：本插件是**本地 PCM 中转**设计 —— 插件在 `127.0.0.1` 上作为 WebSocket 服务端暴露 DAW 母线 PCM，由**同机浏览器里已进房的 Creative Space 页面**接收并作为 `"DAW Audio (VST)"` 轨道发布进 LiveKit 房间。插件本身不直连后端，也不持有房间身份 / 聊天 / 在线状态。
