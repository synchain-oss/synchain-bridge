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

## 3. GitHub Actions
- `allowed_actions` 保持 `selected`（现已配置）
- fork PR 审批改为 **all_external_contributors**（Settings → Actions → General）
- 第三方 action 全部锁定 commit SHA（本仓库已 pin，后续升级时保持 pin）
- 绝不使用 `pull_request_target`（本仓库已禁用，请保持）

## 4. 依赖安全
- Dependabot alerts + security updates 保持开启（现已配置）

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