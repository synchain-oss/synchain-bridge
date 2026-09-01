# CLAUDE.md —— Synchain Bridge 协作规范

> 本文件是协作 agent 与外部贡献者的常驻法条。§0 安全铁律五条三仓逐字相同(真源 = 12 §2.1 / 06 §8.4)。

## 0. 基本约定

- 沟通语言:内部沟通用中文;面向外部贡献者的 issue/PR 回复用对方使用的语言。
- Git 提交身份:`DLsnows <noreply@synchain.ca>`(D8:转 org 后继续用 DLsnows 操作,身份不变)。**本仓一律用
  noreply 地址提交**,不得把个人邮箱写进 commit 或任何入库文档;GitHub 账号侧同时开启
  *Keep my email address private* 与 *Block command line pushes that expose my email*。
- 项目一句话:JUCE 8 + WebView2 的 VST3 插件,经本地 WebSocket(默认端口 9420)推流 DAW 音频;接收端是闭源的 Synchain 网页应用。
- 签名证书/公证凭据:本项目 v1 **不签名**(U13)。若将来引入代码签名,证书与凭据必须走 secret,绝不落盘明文、绝不进仓库。

### §0 安全铁律

1. 任何 key/token 绝不明文入库,包括测试用的假 key(secret scanning push protection 会直接拒推)。
2. workflow 里引用 secret 只能用 `${{ secrets.X }}`;禁止 echo 到日志、禁止写进 artifact。
3. 新增第三方 action 必须 pin 到 40 位 commit SHA(注释写版本号便于 dependabot 升级);`@v2` / `@main` 这类可变 ref 一律不接受,org 白名单里的 `owner/repo@*` 通配不构成防护。
4. 【J20 安全禁令,ADR-011 v1 新增安全条款】任何 workflow 一律不得使用 `pull_request_target`。这不是"不推荐"、不是"审计过就能用"——本项目不接受逐版本审计作为豁免理由。fork PR 的 AI 审查只走方案 D(维护者 `/review` 显式触发,实现 = `.github/workflows/review-dispatch.yml`)或方案 C(workflow_run 两阶段,全程不 checkout PR 代码);其余情况 fork PR 只跑无 secrets 的构建/测试(J31)。机器检查:`grep -r pull_request_target .github/workflows` 零命中。
5. 所有消费仓库外部文本的自动化(review bot、release notes 生成等)的 prompt 末尾必须带「不可信数据声明」(06 §3.4 固定结尾)。

## 1. 分支模型与工作流程

- 默认主干 = `dev`;Bridge 主支线 = `feature/extraction`(ADR-013 / J13)。
- same-repo 只收 `feat/*` / `feature/*`(以及 `dependabot/*`)到 `dev`;子 PR(base = `feature/extraction`)只跑 review bot,不跑完整 CI(D2)。
- **fork PR 门禁政策(J31/J41,唯一政策)**：
  - fork → **任意分支名**(不要用 `dev`/`stage`/`prod`/`feature/v1`/`feature/extraction`)→ PR 到 `dev`;
  - `branch-gate` 对 fork **不 exit 1**,只校验 head 分支名不在上述长期分支名集合(防同名伪装晋升),不强制 `feat/*` 命名;
  - fork PR 只跑无 secrets 的构建/测试(`build-and-validate` / `build-and-validate-macos` / `clang-format` / `branch-gate` / `compliance`);三个 review bot 因 `head.repo.full_name == base.repo.full_name` 条件一律不自动跑;
  - `external` label 由**维护者手工添加**(fork PR 的 `GITHUB_TOKEN` 只读,workflow 内加不了标签,不要用 `pull_request_target` 绕);
  - fork PR 唯一的 AI 审查通道 = 维护者评论 `/review` 显式触发(方案 D,`.github/workflows/review-dispatch.yml`)。
- commit 规范:`type(scope): 中文描述`,全部 `git commit -s`(Signed-off-by)。

## 2. 提 PR 前的本地 Gates

- 一律经 `pwsh scripts/gates.ps1`(06 §5.1 的 gate 结构,单 bundle;含 vcpkg `ixwebsocket` 预检与默认端口 9420 一致性检查:`src/BridgeApi.h` ↔ `web/bridge.js` ↔ `web-preview/mock-server.mjs`)。
- 并行 agent 必须各用独立 git worktree 与 `-BuildDir`;GUI pluginval 全局串行。
- **子 PR 不触发完整 CI 是设计,不是缺陷;不要为了让它跑 CI 去改 workflow 触发规则。**

## 3. 评审规则

- 处理完所有 comment,不止 bot 的(D2);子 PR 的 merge 由用户人工审核并亲自执行。

## 4. 各 Workflow 触发范围一览

- `ci`(job `build-and-validate` = windows-2022;job `build-and-validate-macos` = macos-15,VST3 + AU,arm64-only)/ `format`(job `clang-format`)/ `branch-gate`:`pull_request → dev` + `push → dev, 'feature/**'`。
- `compliance`(gitleaks + reuse lint):同触发面,无 secrets,fork PR 同样跑。
- `claude-review`:所有 base 分支、仅 same-repo(J31);`deepseek-review` / `pr-agent` 默认 disable。
- `release`:push tags `v*` 触发草稿 Release(版本一致性门禁 + pluginval + zip/sha256)。
- `review-dispatch`:维护者评论 `/review` 显式触发(fork PR 唯一 AI 审查通道)。
- 成本纪律:runner 就低不就高(V-4 确认前一律 `ubuntu-latest`)、按量计费 bot 克制使用。**例外(待用户拍板)**:`build-and-validate-macos` 必须跑 GitHub 托管 macOS runner(按 **10 倍分钟数**计费),且当前继承整个 `ci` 工作流的触发面、全开;若要收敛,给 job 加 label/事件闸门是最小改动。

## 5. 协议变更规范

`BRIDGE_CONTRACT.md` 是唯一协议真源。协议改动分级:

| 级别 | 定义 | 流程 |
|---|---|---|
| patch | 纯文档澄清,wire 零变化 | Bridge 仓单仓 PR 即可 |
| minor | 只增可选字段 / 新增消息类型(旧客户端忽略即可正常工作) | Bridge 仓 PR 合并 → 主仓开跟进 issue,可异步落地 |
| major | 改字段名/类型/字节布局/删消息/改必填语义 | 禁止直接做:必须先 RFC PR → 主仓同步实现新旧双读 → 两侧都上线后才移除旧路径;兼容窗口 ≥ 1 个插件 minor 版本 |

任何协议改动必须:① 写兼容性说明(旧客户端遇到新插件、新客户端遇到旧插件各自的行为);② 在本仓 CHANGELOG 的「契约变更」小节记录;③ 在 PR 描述里 @ 主仓维护者同步。

## 6. 环境与依赖

- Windows:JUCE(版本见 `.juce-version`)、CMake ≥3.22、MSVC 2022(静态 CRT `/MT`)、WebView2 SDK(NuGet,版本常量单一真源)+ WebView2 Evergreen Runtime、pluginval(版本见 `.pluginval-version`)、ixwebsocket(vcpkg `x64-windows-static`)。
- macOS(Apple Silicon):JUCE 同一真源、CMake ≥3.22 + **Ninja**、Xcode command line tools(clang,`-Wall -Wextra -Wpedantic`)、pluginval 同一真源 + **`auval`**(AU 唯一验收工具,以输出里的 `AU VALIDATION SUCCEEDED` 判定,退出码不可靠)、ixwebsocket 走 CMake `FetchContent`(tag 钉死,与 Windows 侧 vcpkg 同版本)。产物为 **VST3 + AU**、**arm64-only**(v1 不出 universal / x86_64),不签名不公证;CI runner = `macos-15`。构建细节见 `docs/build-macos.md`。
- 本地 gates(`scripts/gates.ps1`)目前仍是纯 Windows 实现(vswhere / VS 生成器 / nuget / `pluginval.exe`),mac 侧本地验收按 `docs/build-macos.md` 手工执行。
- 构建流水线不需要任何 secret(06 §3.1);review bot 用 org secrets(`CLAUDE_CODE_OAUTH_TOKEN` / `DEEPSEEK_KEY`)。

## 7. 跨仓库协议规范

`BRIDGE_CONTRACT.md` 是桥 #1(编辑器内 JS↔C++)+ 桥 #2(WebSocket)的唯一真源;默认端口 **9420** 在本仓断言三处一致(`src/BridgeApi.h` 的 `DefaultPort`、`web/bridge.js`、`web-preview/mock-server.mjs`,由本地 gate 检查);**另一端位于 Synchain 网页应用(闭源仓库),跨仓一致性由 `BRIDGE_CONTRACT.md` §四的文字约定保证**。

> ⚠️ 内容安全:本公开仓的 CLAUDE.md 不得写闭源主仓的文件路径或函数名。

## 8. 实时线程规则

`processBlock` / 音频回调内 —— 禁止:任何堆分配/释放(new/delete/malloc/free、std::vector 扩容、juce::String 构造、std::function 装非平凡可调用体、任何容器 insert/resize)、任何锁(std::mutex、juce::CriticalSection、SpinLock 的阻塞路径)、文件/网络/控制台 I-O、日志输出、抛出或捕获异常、调用 MessageManager / 触发 UI 更新 / beginChangeGesture 系列、任何可能阻塞的等待。

processBlock 内 —— 允许:预分配缓冲区上的定长运算、juce::ScopedNoDenormals、无锁 SPSC 环形缓冲读写(acquire/release 语义)、std::atomic 的 load/store/CAS(必须 is_always_lock_free)。

Bridge 特有:PCM 发送由后台发送线程经 SPSC ring 转投(移出音频线程,实时安全);慢/停滞客户端背压时丢最新帧(计入 `droppedPacketCount`),绝不阻塞音频回调。WebSocket 心跳由服务端独立线程每 ~5s 发 `ping`、超 ~12s 无 `pong` 则 `close(4408)`,不在音频线程做网络 I/O。

## 9. 分发链路

- 抽取为公开仓库后 **GitHub Releases 才是真正公开可下载的渠道**(private 仓的 Release 附件匿名下载走不通)。
- 版本号真源 = 顶层 `CMakeLists.txt` 的 `project(... VERSION)`;网页侧(闭源仓库)存在一份下游版本镜像,发版后必须同步。
- tag 格式 `vX.Y.Z`(去掉 `vst-` 前缀);首个公开 tag = `v1.4.0`(U6)。
- R2 固定 key 覆盖上传是否保留由 08 文档决策;本仓不默认启用。
