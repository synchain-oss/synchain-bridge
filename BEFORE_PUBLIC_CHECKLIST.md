# ⚠️ Before Making This Repository Public — Checklist

> 本文件是自动添加的安全提醒。把仓库改成 public 之前，请逐项完成。
> 一旦公开：历史提交、Secrets、CI 行为全部暴露；公开前没做的防护，事后补会有泄露窗口。

## 1. Secret Scanning 与 Push Protection（最重要）
- Settings → Code security and analysis：
  - 开启 **Secret scanning**（public 仓库免费，且会回溯扫描历史提交）
  - 开启 **Push protection**（防止未来误推密钥）
- 开启后到 **Security 标签页**检查历史扫描命中项并逐个处理。
- 本仓库当前有 2 个 Actions secrets：公开前确认没有密钥出现在代码或历史中。

## 2. 分支保护
- 给默认分支 `dev` 与未来的生产分支加保护（Settings → Branches）：
  - 强制 PR 合并（单人开发时 required approvals = 0，否则自己无法批准自己的 PR，永久卡死）
  - enforce_admins = true（禁强推、禁删分支，对管理员同样生效）
  - required status checks 先确认该 CI 在目标分支真的会触发再加，否则 PR 会卡住
  - ⚠️ macOS job 合入后，required checks 需**手工**补 `build-and-validate-macos`（新 job 不会自动成为必需检查；
    不加的话 mac 侧回归红了照样能合——发版侧「任一平台失败 = 整个 tag 无产物」的口径在 CI 侧就靠这一条）

## 3. GitHub Actions
- `allowed_actions` 保持 `selected`（现已配置）
- fork PR 审批改为 **all_external_contributors**（Settings → Actions → General）
- 第三方**与 first-party** action 全部锁定 40 位 commit SHA —— **✅ 已完成（2026-09-01）**，见 §3.1
- 绝不使用 `pull_request_target`（本仓库已禁用，请保持）

### 3.1 action pin 实扫清单（转 public 硬门禁 —— **✅ 已完成（2026-09-01）**）

`@v4` / `@v6` 这类可变 tag 上游随时可以重指，等于把本仓 runner 上的代码执行权交给对方；
`actions/*` 是 first-party 也不例外（CLAUDE.md §0 铁律第 3 条）。本次把 `.github/workflows/`
下**全部 21 条 `uses:`** 统一钉到 40 位 commit SHA，注释写版本号供 dependabot 升级。
落地 commit：`ci(security): 全部 workflow action pin 到 40 位 commit SHA(转 public 硬门禁)`
（分支 `feat/prepublic-pin`，`git log --grep 'pin 到 40 位 commit SHA'` 可定位）。

| action | commit SHA | 版本 | 出现于 |
|---|---|---|---|
| `actions/checkout` | `11d5960a326750d5838078e36cf38b85af677262` | v4.4.0 | ci / compliance / format / pr-agent / release / review-dispatch |
| `actions/checkout` | `d23441a48e516b6c34aea4fa41551a30e30af803` | v6.1.0 | claude-review / deepseek-review |
| `actions/cache` | `0057852bfaa89a56745cba8c7296529d2fc39830` | v4.3.0 | ci / release |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` | v4.6.2 | ci（5 处） |
| `actions/github-script` | `f28e40c7f34bde8b3046d885e986cb6290c5673b` | v7.1.0 | contract-guard |
| `anthropics/claude-code-action` | `239e3a730883eeb5c53db12b0fc9573b3024b126` | v1.0.191 | claude-review / deepseek-review / review-dispatch |
| `qodo-ai/pr-agent` | `8e4d32e5497defd43c023a404f73560c62728961` | v0.39.0 | pr-agent |
| `softprops/action-gh-release` | `3bb12739c298aeb8a4eeaf626c5b8d85266b0e65` | v2.6.2 | release |

口径说明：

- 每个 SHA 均由 `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` 现场解析；annotated tag
  （`anthropics/claude-code-action`）再经 `gh api repos/<o>/<r>/git/tags/<sha>` 解一层取
  `object.sha`。**不凭记忆写 SHA**：写错一位就是钉到一个不存在或不受控的对象上。
- `actions/checkout` 保留 v4 / v6 两条 major 线，是**刻意不动版本**：本次只把可变 ref 换成
  等价的 SHA，不顺手升级——升级要单独走 PR 并跑一遍 CI，混进 pin 里会让「绿变红」无从归因。
- 已 pin 的三个（claude-code-action / pr-agent / action-gh-release）SHA 未动，只把注释补成
  具体版本号；`# pin SHA` 这类注释说不出是哪一版，dependabot 与人都无从判断该不该升。

复核断言（应为「21 条全部 40 位 hex，无 unpinned」）：

```bash
grep -rn "uses:" .github/workflows/                              # 逐行看
# 抽出每条 uses 的 ref，滤掉已是 40 位 hex 的；零命中（exit 1）即通过
grep -rhoE "uses:[[:space:]]*[^[:space:]]+" .github/workflows/ | grep -vE "@[0-9a-f]{40}$"
```

### 3.2 `ci.yml` windows job 的 `${{ github.ref_name }}` 直插改 env 间接（来源：PR #21 审查）

`.github/workflows/ci.yml` 的 windows job 把 `${{ github.ref_name }}` 直接插进 `run:` 的
PowerShell 字面量里算 artifact slug：

```powershell
$slug = "${{ github.ref_name }}" -replace '[/\\]','-'
```

`${{ }}` 是在脚本落盘**之前**做的文本替换，含引号/反引号的 ref 名可以就地闭合字符串、在 runner 上
执行任意 PowerShell。**注入面目前很窄**（`push` 事件的 ref 来自有推送权限的人；`pull_request` 事件下
`github.ref_name` 是 `<PR 号>/merge`，不是 fork 的 head 分支名），所以这不是当前可被外部触发的漏洞，
但它是同一类问题里唯一没跟上的一处 —— 同文件的 macOS job 已经走 `env: REF_NAME` 间接、脚本里读
`$env:REF_NAME`。**这一处早于本批 macOS 工作（dev 上已如此），不是本栈引入的。**

处理方式：windows job 照 macOS job 的写法加 `env: REF_NAME: ${{ github.ref_name }}`，脚本内改读
`$env:REF_NAME`。与 §3.1 的 pin 一样，宜并进那个「只改 workflow、不掺功能」的 PR。

## 4. 依赖安全
- Dependabot alerts + security updates 保持开启（现已配置）

### 4.1 ixwebsocket 的 `FetchContent` 由 tag 改 40 位 SHA pin（来源：PR #21 审查）

`CMakeLists.txt` 的 `APPLE` 分支用 `GIT_TAG ${IXWEBSOCKET_TAG}`（`v12.0.1`）拉 ixwebsocket。
**git tag 是可变 ref**：上游把 tag 重新指向别处，mac 构建就会静默换掉一个链进产物的依赖 ——
与 §3.1 对 action 的要求同源（CLAUDE.md §0 铁律 3），只是对象换成了源码依赖。

处理方式：把 `GIT_TAG` 换成该 tag 当前指向的 40 位 commit SHA（注释里保留 `# v12.0.1` 便于人读与升级）。
**必须同时去掉 `GIT_SHALLOW TRUE`**：浅克隆是 `git fetch --depth 1 <ref>`，只对分支名/tag 名成立，
给裸 commit SHA 会 fetch 失败，配置期直接炸。代价是 mac 侧配置期多克隆一份完整历史。

Windows 侧不受影响（走 vcpkg port，版本由 vcpkg 的 baseline 钉住，不经 `FetchContent`）。

## 5. 历史清扫（原转 public 硬门禁 —— **✅ 已完成（2026-09-01）**）

转 public 暴露的是**全部 ref 与全部历史**，不是工作树；工作树清干净不构成历史清扫证据。
该清扫已于 2026-09-01 执行完毕，记录如下。

### 5.1 已执行的重写（历史记录，相关串均已清除）

用 `git filter-repo --replace-text` 重写了当时的**全部 21 个 commit**，把三类串替换为占位：

| 类别（只记类别，**真值与旧 SHA 均不入库**） | 曾出现于 | 替换为 |
|---|---|---|
| 部署平台的团队预览域 slug（旧 Origin 白名单规则里的硬编码值） | `src/VstBridgeServer.cpp`、`docs/DAW_TEST_GUIDE.md` | 占位串；该类来源改走构建期注入（决策 U4） |
| 构建机的 Windows 用户目录绝对路径（含用户名） | `THIRD-PARTY-NOTICES.md` | 占位串；该表的核验来源已改为上游公开引用 |
| 维护者个人邮箱（非 noreply 地址） | `CLAUDE.md` | `noreply@synchain.ca` |

随后的收尾动作：

- force-push 了 `dev` 与 `feature/extraction`；tag `v1.4.0` 按重写后的新 commit 重打，
  当前指向 `5bb8e3675513e5f85e7acc87435d55776fd544b8`（`git rev-list -1 v1.4.0` 可复核）。
- 重写前的**全量备份 bundle** 已在仓库外的本地留存（路径不入库）。
- 重写前的旧 draft release 已删除，改由 CI 从重写后的干净源码重新构建产物。
- ⚠️ 重写会改写全部 commit SHA：**任何旧的本地副本 / worktree 必须重新 clone**，
  否则一次 push 就会把污染历史送回去。历史文档里引用旧 SHA 的地方也已改为描述性引用。

### 5.2 采纳的方案

采纳「① 重写历史」（另一选项「推迟 tag 与转 public、squash 重建首 commit」未采纳）。决策已记进 08 文档。

### 5.3 验收断言：**已执行，零命中**

待扫串本身**不写进仓库**（写进来就等于在公开仓复制了一份要清除的东西）。真值放进本地
`.leakscan-patterns`（已在 `.gitignore` 中，一行一个 grep 模式；来自 08 决策文档）后执行的两条断言
**均为零命中**：

```bash
# ① 历史（唯一有效的清扫证据）
git grep -I -n -f .leakscan-patterns $(git rev-list --all)

# ② 工作树（不能替代 ①）
grep -rn -f .leakscan-patterns --exclude-dir=.git .
```

覆盖的四类模式：部署平台预览域 slug、Windows 用户目录路径前缀、维护者个人邮箱与其域名、
以及上游保留字体名的无空格拼法。

后续由 **`compliance` workflow 的 `Secret scan (git history)` 步骤持续看守**（`fetch-depth: 0` 全历史，
规则见 `.gitleaks.toml` 的非密钥型自定义规则），不再依赖人工记得复扫。

> ⚠️ **两者不等价，别把 CI 绿灯当成 §5.3 的替代品。** CI 历史扫描的绿灯只说明「`.gitleaks.toml` 的三条
> 类别规则所覆盖的**形态**零命中」；§5.3 是拿**真值**逐串比对的一次性本地验收，覆盖面更窄但更确切
> （结果已留档于此）。类别规则写不出的变体（例如换了写法的 slug、别的路径前缀）只有真值断言拦得住，
> 反之真值断言也看不见未来新引入的其它形态——两者互补，缺一不可。
> 另注：本地 `gates.ps1` 的历史扫描走 `git log` 全部 ref，**含本地未推送分支**，CI 只看 checkout 的那份，
> 因此「本地红 / CI 绿」是可能的，方向是 fail-closed。

> 字体那条只对文本文件有意义：`web/fonts/*.woff2` 是 brotli 压缩的，grep 不命中**不等于**
> 字体 `name` 表已改名。二进制侧的真实断言由 `scripts/check-font-names.py` 做，同样已接进
> `compliance` workflow 与本地 gate。

### 5.4 残留风险（转 public 后仍需处理）

**GitHub 上转 public 之前的旧 PR（#1–#17）diff 页面在仓库转 public 后仍会展示重写前的内容。**
force-push 只改分支与 tag 指向，不删除 GitHub 侧那些 PR 快照所引用的孤儿对象。

- 处置：转 public 后向 GitHub support 申请清理孤儿对象 / 隐藏旧 PR diff。**（待办）**
- 在该申请完成前，把仓库转 public 等于把这三类串以 PR diff 的形式重新公开一次。