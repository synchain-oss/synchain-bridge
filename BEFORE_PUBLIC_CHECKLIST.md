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
- 绝不使用 `pull_request_target`（本仓库已禁用，请保持）

### 3.1 第三方 action 全部 pin 到 40 位 SHA（⛔ 转 public 硬门禁，**尚未完成**）

CLAUDE.md §0 铁律 3 要求所有第三方 action pin 到 40 位 commit SHA。当前**只有 `release.yml`
与 `ci.yml` 的 macOS job 做到了**，其余仍是可变 ref，转 public 前必须清零：

| 文件 | 未 pin 的可变 ref |
|---|---|
| `.github/workflows/ci.yml` | windows job 的 `actions/checkout@v4` / `actions/cache@v4` / `actions/upload-artifact@v4`（共 7 处）|
| `.github/workflows/compliance.yml` / `branch-gate.yml` / `format.yml` / `claude-review.yml` 等 | 同类可变 ref |

处理方式：**另开一个只做 pin 的 PR**（不与功能改动混在一起），逐个换成
`owner/repo@<40 位 SHA> # vX.Y.Z`，`release.yml` 是现成范本。验收断言（零命中即通过）：

```bash
grep -rnE 'uses:[[:space:]]*[^@]+@(v[0-9]|main|master)' .github/workflows
```

> 现有功能分支以「不改现有 job 任何一行」为施工纪律不动它们，是合理的；但这条不能停在
> 疑点清单里 —— 公开后可变 ref 意味着上游被劫持即可在本仓 CI 里执行任意代码。

## 4. 依赖安全
- Dependabot alerts + security updates 保持开启（现已配置）

## 5. 历史清扫（⛔ 转 public 的硬门禁，**尚未完成**）

- 公开前扫描 git 历史中的敏感信息（secret scanning 回溯 + gitleaks/trufflehog）
- 确认历史中从未提交过 .env、私钥、数据库连接串等

### 5.1 已知未清除项（转 public 前必须先处理）

转 public 暴露的是**全部 ref 与全部历史**，不是工作树。下面三类串在工作树里已清干净，但**仍在历史里**，
且在三个已发布 ref 的顶端（`origin/dev`、`origin/feature/extraction`、tag `v1.4.0`；`v1.4.0` 已是 HEAD 的祖先）：

| 泄漏串（此处只描述形态，**真值不入库** —— 见 5.3） | 位置 | 历史命中 |
|---|---|---|
| 部署预览域 slug（`-<owner>-projects.<平台域>` 形态，出现在旧的 Origin 白名单规则里） | `src/VstBridgeServer.cpp`、`docs/DAW_TEST_GUIDE.md` | 15 个 commit（含首个抽取 commit `380d250`、`1ea25fc`、`cb2b46e`） |
| 构建机的 Windows 用户目录绝对路径（含用户名，两处工具链目录） | `THIRD-PARTY-NOTICES.md`（5 行） | 同批历史，`v1.4.0` 顶端仍带 |
| 维护者个人邮箱（非 noreply 地址） | `CLAUDE.md` | 15 个 commit（自首个抽取 commit 起） |

> ⚠️ 只扫工作树会对这一层完全失明 —— 任何加了 `--exclude-dir=.git` 的 grep 断言都**不构成**历史清扫证据。

### 5.2 二选一，并把决策记进 08 文档

- **① 重写历史**：`git filter-repo --replace-text`（把上述三类串换成占位）重写
  `dev` / `feature/extraction` 全历史 → 删除 `v1.4.0` 并按新 SHA 重打 → force-push →
  **所有 worktree 必须重新 clone**（旧本地副本会把污染历史推回来）。
- **② 不接受重写**：推迟 `v1.4.0` tag 与转 public，先在私有仓 squash 重建首 commit，再重新发首个公开 tag。

### 5.3 验收断言（必须扫**历史**，不是工作树）

待扫串本身**不写进仓库**（写进来就等于在公开仓复制了一份要清除的东西）。放进本地
`.leakscan-patterns`（已在 `.gitignore` 中，一行一个 grep 模式；真值来自 08 决策文档）后执行 ——
两条都必须**零命中**才允许转 public：

```bash
# ① 历史（唯一有效的清扫证据）
git grep -I -n -f .leakscan-patterns $(git rev-list --all)

# ② 工作树（转 public 前也要保持零命中，但不能替代 ①）
grep -rn -f .leakscan-patterns --exclude-dir=.git .
```

`.leakscan-patterns` 至少要覆盖：部署预览域 slug、Windows 用户目录路径前缀、维护者个人邮箱与其域名、
以及上游保留字体名的无空格拼法。

> 字体那条只对文本文件有意义：`web/fonts/*.woff2` 是 brotli 压缩的，grep 不命中**不等于**
> 字体 `name` 表已改名。二进制侧的真实断言见 `THIRD-PARTY-NOTICES.md` 的 fontTools 复核命令。