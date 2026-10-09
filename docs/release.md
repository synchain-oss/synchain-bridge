# 发布流程

> 发布由 `push: tags: ['v*']` 触发 [.github/workflows/release.yml](../.github/workflows/release.yml)，全自动完成「版本一致性门禁 → 两平台构建 → pluginval / auval → 打包 zip/sha256 → 草稿 Release」。发版者要做的只有：**改版本号 → 晋升 `prod` → 在 `prod` 上打 tag**。
>
> 发版分支流程：`feature/aax`（或其他 `feature/*`）→ `dev`（PR）→ `prod`（PR，只允许来自 `dev`，由 `branch-gate` 强制）→ 在 `prod` 的合并提交上打 `vX.Y.Z`。**正式 tag 只打在 `prod` 上**，见 [§5](#5-晋升-prod在-prod-上打-tag-触发-releaseyml)；冒烟 tag（§5.1）不受此限。
>
> AAX（Pro Tools）是唯一例外：CI 只产出**未签名**件（artifact `aax-unsigned-*`，不进 Release），PACE 签名、打发行包、上传到 draft 由维护者在本机手工完成，见 [§7](#7-aaxpro-tools本机签名--手工上传)。
>
> 版本号唯一真源 = 顶层 `CMakeLists.txt` 的 `project(... VERSION)`；tag 格式 `vX.Y.Z`（去掉旧 `vst-` 前缀）。首个公开 tag = `v1.4.0`（历史事实；**打 tag 前先读 CMake 当前 VERSION**——版本不相等会在 `gate` 直接红）。

## 0. release.yml 做什么

workflow 分四个 job：版本门禁独立前置，两个平台并行构建，最后由一个 job 统一建 Release。

| job | runner | 动作 | 失败即 job fail？ |
|---|---|---|---|
| `gate` | ubuntu-latest | 校验 tag 与 `CMakeLists.txt` 的 VERSION 一致，把版本号导出给下游两个构建 job | 是（冒烟 tag `*-test` 除外，恒产 draft） |
| `release` | windows-2022 | clone JUCE（`actions/cache` 命中即跳过）→ WebView2 → CMake（vcpkg 按 `vcpkg.json` 装 ixwebsocket，二进制缓存走 `actions/cache`，随后断言版本 == manifest）→ 构建（/W4 零警告；同一次构建产出 VST3 与 AAX）→ pluginval → `scripts/package.ps1` → 上传 `dist-win64` → `scripts/package-aax.ps1 -Mode Unsigned` → 上传 `aax-unsigned-win64`（不进 publish） | 是（含 AAX 打包，见 §6.1） |
| `release-macos` | macos-15 | clone JUCE + 预取钉死的 ixwebsocket 源码（均 `actions/cache`，与 `ci.yml` 同 key）→ Ninja → 构建（clang 零警告；同一次构建产出 VST3 / AU / AAX）→ pluginval 验 VST3 + auval 验 AU → `scripts/package-macos.sh` → 上传 `dist-macos-arm64` → `scripts/package-aax-macos.sh --mode unsigned` → 上传 `aax-unsigned-macos-arm64`（不进 publish） | 是（含 AAX 打包，见 §6.1） |
| `publish` | ubuntu-latest | 下载全部 artifact → 只从 `dist-win64` / `dist-macos-arm64` 取件 → `sha256sum -c` 跨 job 复验 → 四资产精确名白名单 → 创建 **draft** GitHub Release（挂两平台 VST3 / AU 的 zip + `.sha256`；`aax-unsigned-*` 虽被一并下载，但不在取件目录与白名单内，绝不上 Release） | 是 |

两条与安全/成本有关的结构性约定：

- **权限**：workflow 级降为 `contents: read`，`contents: write` 只授给 `publish` 一个 job。构建 job 要跑第三方代码（JUCE / vcpkg / pluginval），一律拿不到写 Release 的权限。
- **门禁前置**：tag 打错时 `gate` 先红，windows / macOS 两个构建 job 根本不会起，不浪费分钟数。

产物命名（版本号由 `gate` 算出，脚本内绝不写字面量）：

| 平台 | zip | zip 内容 |
|---|---|---|
| Windows x64 | `SynchainBridge-VST3-v<版本>-win64.zip` | `Synchain Bridge.vst3` + 合规文件 |
| macOS arm64 | `SynchainBridge-VST3-AU-v<版本>-macos-arm64.zip` | `Synchain Bridge.vst3` + `Synchain Bridge.component` + 合规文件 |
| Windows x64（AAX，**签名后手工上传**，§7） | `SynchainBridge-AAX-v<版本>-win64.zip` | `Synchain Bridge.aaxplugin`（PACE 签名）+ 合规文件 |
| macOS arm64（AAX，**签名后手工上传**，§7） | `SynchainBridge-AAX-v<版本>-macos-arm64.zip` | `Synchain Bridge.aaxplugin`（PACE 签名）+ 合规文件 |

前两行由 `publish` 自动挂到 draft；AAX 两行不是 CI 产物 —— `release.yml` 只产出带 `-UNSIGNED` 后缀的签名输入件（`SynchainBridge-AAX-v<版本>-{win64,macos-arm64}-UNSIGNED.zip` + `.sha256`，分别在 artifact `aax-unsigned-win64` / `aax-unsigned-macos-arm64` 里，保留 30 天，且受仓库 / org 的 artifact 保留上限约束），它们**不是发行资产**，永远不进 Release。

所有 zip 的「合规文件」都是同一组：`LICENSE.txt` + `THIRD-PARTY-NOTICES.md` + `LICENSES/OFL-1.1.txt` + 安装说明。VST3 / AU 包的安装说明叫 `INSTALL.txt`（按平台各写各的）；AAX 包用 `INSTALL-AAX.txt`（同样按平台各写各的，与 VST3 包解压到同一目录时互不覆盖）。

## 1. 改版本号

把 `CMakeLists.txt` 顶层 `project()` 调用里的 VERSION 改成目标版本（**按构造名定位，不按行号**：加平台支持会让这行整体移位）：

```
project(SynchainBridgeVST VERSION 1.4.0)
```

> 本节以 `1.4.0` 为例，与下文第 4/5 步的示例版本一致；实际发版时全部换成目标版本。

同一版本号在 `web-preview/`（`mock-server.mjs` 的 `PLUGIN_VERSION`、`package.json` / `package-lock.json` 的 `version`）有一份镜像，改完由 `pwsh scripts/gates.ps1` 的版本一致性 gate 断言，不一致会直接 FAIL。

版本经 `JucePlugin_VersionString` 自动流入插件 UI 与 `status` 帧上报，无需再改任何手写常量（见 `BRIDGE_CONTRACT.md` §三）。

改版本号和其他改动一样，在 `feat/*` 分支上提交、经 PR 合入功能支线，再随支线进 `dev`；不要直接改 `dev` / `prod`。

## 2. 构建（本地验证）

Windows：按 [build-windows.md](build-windows.md) 构建 Release 版，确认产物存在。

macOS（Apple Silicon）：按 [build-macos.md](build-macos.md) 构建 Release 版，确认两个 bundle（`.vst3` 与 `.component`）都在。构建命令不在本文重复 —— 两份 macOS 构建说明会立刻开始漂移。

架构参数与部署目标写在 `CMakeLists.txt`（`project()` 之前的 `CMAKE_OSX_ARCHITECTURES` / `CMAKE_OSX_DEPLOYMENT_TARGET`，见 build-macos.md），命令行不重复传 —— 单一真源。v1 只出 **arm64**：Intel Mac 与被勾了「使用 Rosetta 打开」的宿主都加载不了，这一点由打包脚本的 `file` 断言强制，也写进了 macOS 版 INSTALL.txt。

## 3. pluginval / auval 验证

Windows / VST3：

```powershell
./pluginval/pluginval.exe --strictness-level 5 --timeout-ms 60000 --skip-gui-tests "build\SynchainBridgeVST_artefacts\Release\VST3\Synchain Bridge.vst3"
```

macOS / VST3 + AU：

```bash
# VST3:pluginval(macOS 版解压后要先补可执行位)
chmod +x pluginval.app/Contents/MacOS/pluginval
./pluginval.app/Contents/MacOS/pluginval --strictness-level 5 --timeout-ms 60000 --skip-gui-tests \
  "build/SynchainBridgeVST_artefacts/Release/VST3/Synchain Bridge.vst3"

# AU:先 ditto 装进 ~/Library(cp -r 会丢符号链接,bundle 会散架),再踢一次注册器强制重扫
ditto "build/SynchainBridgeVST_artefacts/Release/AU/Synchain Bridge.component" \
      ~/Library/Audio/Plug-Ins/Components/"Synchain Bridge.component"
killall -9 AudioComponentRegistrar
auval -v aufx Snb1 Snch
```

> 含 WebView 编辑器的**全量** strictness-5（去掉 `--skip-gui-tests`）必须在真实机器上本地跑——无头 runner 无法托管编辑器，这是本地门禁，CI 只能跑非 GUI 部分。
>
> `auval` 的退出码历史上不可靠，CI 与人工都以输出里的 `AU VALIDATION SUCCEEDED` 为准。
>
> `auval -v` 的三个四字码不是常量：`aufx` 由 `CMakeLists.txt` 的 `AU_MAIN_TYPE`（`kAudioUnitType_Effect`）决定，`Snb1` / `Snch` 分别是 `PLUGIN_CODE` / `PLUGIN_MANUFACTURER_CODE`。CI（`ci.yml` 与 `release.yml` 的 mac job）从 `CMakeLists.txt` **现读**这三个值，不写死；**手动改这三个构造之一时**，本文这条命令与 `docs/build-macos.md` 里的同名命令要一起改，CI 侧无需改动。改四字码等于换插件身份，会让用户工程里的既有实例全部丢失，非必要不动。

## 4. 打包（唯一真源 = 各平台的打包脚本）

Windows：

```powershell
pwsh scripts/package.ps1 -Version 1.4.0 -BuildDir build -OutDir dist
# gate 用：只校验合规源文件、不产出任何产物
pwsh scripts/package.ps1 -DryRun
```

macOS：

```bash
bash scripts/package-macos.sh --version 1.4.0 --build-dir build --out-dir dist
# gate 用：同上
bash scripts/package-macos.sh --dry-run
```

两个脚本的产出结构一致：`dist/<平台 zip>` + `.zip.sha256` + `package-summary.md`。macOS 侧一律用 `ditto` 拷贝与压缩——`cp -r` / `zip -r` 会丢符号链接与可执行位，用户解压后拿到的是加载不了的死壳；压缩用 `ditto -c -k --norsrc --noextattr`（bundle 不需要资源叉，也不给用户塞 `__MACOSX/` 垃圾），打包后脚本会断言 zip 内 `Contents/MacOS/*` 仍是 `-rwx`。打包逻辑只在脚本里，绝不内联到 workflow。

`--version` **不传**才回落到 `CMakeLists.txt` 的版本真源；传了空串直接 `die` —— CI 里 `gate` 万一没写出 `outputs.version`，静默回落会产出版本号对不上的资产（冒烟 tag `v0.0.0-test` 产出名为 `v1.5.0` 的 zip，`sha256sum -c` 照样过），这类错误只会在 draft Release 页面被人眼发现。`release.yml` 的两个 Package 步骤另有一道空值断言。

AAX 用两个独立脚本（与上面两个脚本互不改动；默认输出目录 `dist/aax`，与 VST3 / AU 的 `dist/` 分开）：

```powershell
pwsh scripts/package-aax.ps1 -Mode Unsigned -Version 1.4.0 -BuildDir build -OutDir dist/aax
```

```bash
bash scripts/package-aax-macos.sh --mode unsigned --version 1.4.0 --build-dir build --out-dir dist/aax
```

`-Mode` / `--mode` 必填、无默认值；版本规则（显式传空串直接失败）与 `.sha256` / `package-summary.md` 格式同上。Unsigned 产出 `SynchainBridge-AAX-v<版本>-<平台>-UNSIGNED.zip`；不带后缀的发行名只在 Signed 模式、且 bundle 确实带签名时才产出 —— Signed 由 §7 的签名脚本在签完之后调用，不要手工对未签名 bundle 跑 Signed（会被拒收）。

## 5. 晋升 `prod`，在 `prod` 上打 tag 触发 release.yml

发版分支流程：`feature/aax`（或其他 `feature/*`）→ `dev`（PR）→ `prod`（PR，只允许来自 `dev`）→ 在 `prod` 的合并提交上打 `vX.Y.Z`。正式 tag 只打在 `prod` 上，不打在 `dev` / `feature/*` 上。

1. 版本号改动（§1）随功能支线经 PR 合入 `dev`。
2. 开 `dev` → `prod` 的 PR。`branch-gate` 在 base = `prod` 时只放行本仓的 `dev`：其他分支、fork、机器人开到 `prod` 的 PR 一律红。DCO 与冻结契约守卫照常跑：
   - DCO 跳过 merge commit，其余提交逐个检查 sign-off。commit 列表有 250 条上限，超过直接红；每次发版都晋升一次 `prod` 就不会触顶。
   - `dev` 相对 `prod` 的 diff 碰到七个契约文件之一时，`contract-guard` 与 `branch-gate` 都会读 PR body 里的 `contract-impact`。按这批改动里最严的级别写；只动了 `BRIDGE_CONTRACT.md` §三的登记快照（例如改版本号）时写 `contract-impact: none`。
   - 这个 PR 上不跑 `ci` / `format` / `compliance`（它们的 PR 触发面只有 `dev`）：同一批提交合入 `dev` 时已经验过，打 tag 后 `release.yml` 还会完整构建一次。
3. 合并方式用 merge commit（`gh pr merge <N> --merge`），不要 squash / rebase：否则 `prod` 与 `dev` 的历史分叉，下一次 `dev` → `prod` 会把已经发布的提交再带一遍。
4. 在 `prod` 的合并提交上打 tag：

```powershell
# <X.Y.Z> = CMakeLists.txt 当前 project(... VERSION)——两者不相等 gate 必红
git switch prod
git pull --ff-only
git log -1 --format='%H %s'   # 应为刚合并的 dev → prod 合并提交
git tag v<X.Y.Z>
git push origin v<X.Y.Z>
```

**首次建立 `prod`**（1.6.0 之前本仓没有 `prod`，只做一次）：从**上一个已发布 tag** 的提交切出 `prod`，推上去后按第 2 步开 `dev` → `prod` 的 PR。上一个已发布的版本以 GitHub Releases 页面为准（1.6.0 时为 `v1.5.3`）：

```powershell
git fetch origin --tags
git merge-base --is-ancestor v1.5.3 origin/dev; $LASTEXITCODE   # 必须为 0(tag 在 dev 的历史里);非 0 就停下排查,否则 dev → prod 会把已发布的内容再带一遍
git switch -c prod v1.5.3
git push -u origin prod
```

建好后给 `prod` 配分支保护：必须经 PR 合并、禁止 force push 与删除，required check **只设 `branch-gate`**。不要照搬 `dev` 的 required check 列表：`compliance` / `clang-format` / `build-and-validate` / `build-and-validate-macos` 不在 `prod` 的 PR 上跑，设成 required 会让 PR 一直 pending。

触发后：`gate` 校验版本 → `release` / `release-macos` 并行构建、验证、打包 → `publish` 复验哈希并建 **draft** Release。到 GitHub Releases 页面把草稿转正式即可；本版要发 AAX 时，转正式之前先按 §7.3 签名并把 AAX 传上 draft。

### 5.1 冒烟 tag（`v0.0.0-test`）：首次改动发版链路后必须实跑

`gate` 对 `*-test` 结尾的 tag 跳过严格版本相等，产物恒为 draft。冒烟 tag 可以打在任何分支上（不要求在 `prod` 上），通常打在要验证的那条分支的最新提交上。改过 `release.yml` / 打包脚本 / `CMakeLists.txt` 的平台相关部分之后，先打一个冒烟 tag 端到端验证四段链路（`gate` → `release` ∥ `release-macos` → `publish`），确认 **draft Release 真被建出来、两个平台的 zip 与 `.sha256` 都挂上了**，再打真实版本 tag。

AAX 另确认两点：这次 run 里有 `aax-unsigned-win64` 与 `aax-unsigned-macos-arm64` 两个 artifact（各含一个 `-UNSIGNED.zip` + `.sha256`）；draft 上**仍然只有那四个** VST3 / AU 资产 —— 未签名 AAX 不会自动上 Release。手边有 PACE 工具时，可以顺手对这个测试 draft 彩排一遍 §7.3 的第 2–5 步（版本即 `0.0.0-test`）。

```powershell
git tag v0.0.0-test
git push origin v0.0.0-test
# AAX artifact 是否齐全(<run-id> 用 gh run list --workflow release.yml --branch v0.0.0-test 查)
gh api repos/synchain-oss/synchain-bridge/actions/runs/<run-id>/artifacts --jq '.artifacts[].name'
# 验完删掉：先在 Releases 页面删 draft(彩排时传上去的 AAX 资产随 draft 一起删掉)，再删 tag
git push origin :refs/tags/v0.0.0-test
git tag -d v0.0.0-test
```

## 6. 发布后

- 把 draft Release 转正式（public 仓库的 Release 附件才可匿名下载）。要发 AAX 的版本先完成 §7.3；也可以先发 VST3 / AU，事后补传 AAX（§7.4）。
- 同步下游版本镜像：网页侧（闭源仓库）存在一份下游版本镜像，发版后必须同步（见 [web-client.md](web-client.md)）。
- VST3 / AU **不签名**（U13）：Windows 的 INSTALL.txt 写明 SmartScreen 提示与「更多信息 → 仍要运行」的引导；macOS 的 INSTALL.txt 写明 `xattr -dr com.apple.quarantine` 两条命令（全局路径要 `sudo`，家目录不要）、AU 缓存重扫，以及 arm64-only / Rosetta 的注意事项。
- AAX 是唯一例外：由维护者本机用 PACE wraptool 签名（§7）。`INSTALL-AAX.txt` 写明签名说明、Pro Tools 插件目录的安装命令（先删旧版，需要管理员 / `sudo`），macOS 版另写明 arm64-only、未经 Apple 公证、必须去掉隔离属性。

### 6.1 ⚠️ 任一平台失败 = 整个 tag 无产物

`publish` 是 `needs: [release, release-macos]`，两个平台都绿才建 Release。**macOS 侧任何偶发失败（runner 镜像抖动、brew、`auval` 不稳、超时）都会让整个 tag 一个产物都发不出去**，包括已经构建打包成功的 Windows zip —— 这相对「Windows job 自带 `softprops`、能独立出 Release」的旧实现是一次有意的行为收敛（换来的是权限只授给 `publish` 一个 job、两平台产物一次性挂进同一个 Release）。

**AAX 同样 fail-hard**：任一平台的 AAX 构建、未签名打包或 artifact 上传失败，同样让整个 tag 无产物，不使用 `continue-on-error`。理由：

1. AAX 与 VST3 / AU 在同一个 `cmake --build` 里编译，本来就分不开；
2. `ci.yml` 在每次 PR / push 上都用同一个打包脚本做 AAX 冒烟（含「Signed 模式必须拒收未签名 bundle」的反向断言），回归在打 tag 之前就会红 —— 与 VST3 打包冒烟的论证相同；
3. `continue-on-error` 会把红灯变成「带注释的绿灯」，违背全仓 fail-closed 的纪律，而 artifact 缺失要到签名那天才会被发现；
4. 拆成独立 job 要多付一次两平台的完整构建。

处理：修掉失败原因后，**删掉 draft Release（如果有）与该 tag，再重新打同名 tag**。修复同样走 `feature/*` → `dev` → `prod`（§5），新 tag 仍打在 `prod` 的合并提交上；只是 runner 抖动、代码不用改时，直接在原提交上重打：

```powershell
git push origin :refs/tags/v1.5.0
git tag -d v1.5.0
# 修复合入 prod 后重新打
git switch prod
git pull --ff-only
git tag v1.5.0 && git push origin v1.5.0
```

两个构建 job 的 `timeout-minutes` 都是 60（对称；两边都要编译多个 format wrapper —— Windows 为 VST3 + AAX，mac 为 VST3 + AU + AAX，mac 侧还多一次 ixwebsocket 的编译；JUCE / ixwebsocket 源码 / vcpkg 二进制有 `actions/cache`，但 miss 时也得够用）。若将来希望「mac 挂了 Windows 仍能发」，改法是把 `publish` 换成 `if: always() && needs.release.result == 'success'` 并按存在的 artifact 动态挂载 —— 属于**需要用户拍板**的行为变更，未擅自实施。

## 7. AAX（Pro Tools）：本机签名 + 手工上传

### 7.0 为什么手工

零售版 Pro Tools 只加载经 PACE 签名的 AAX。签名要用到 PACE 账号、wcguid（在 PACE 侧为本产品建的签名配置 GUID）、iLok 和代码签名证书，全部是个人凭据；而构建流水线保持零 secret（CLAUDE.md §0 / §6），所以 `release.yml` 只产出 `-UNSIGNED` 件，**签名、打发行包、上传到 draft 都在维护者本机完成**。U13「不签名」只对 VST3 / AU 保留，AAX 是唯一例外。

未签名件永远不会长得像发行资产，有四道保险：

1. 文件名带 `-UNSIGNED` 后缀；
2. 不带后缀的发行名只在打包脚本的 Signed 模式、且 bundle 确实带非 ad-hoc 签名时才产出（`ci.yml` 的 AAX 冒烟每次都用未签名 bundle 做反向断言）；
3. artifact 叫 `aax-unsigned-*` 而不是 `dist-*`，`publish` 不从它取件；
4. `publish` 的四资产精确名白名单不变，混进任何第五个文件都会红。

> **已实测 / 待验证**：Windows 签名脚本已按 PACE wraptool 6.0.1 实测对齐（2026-10-08）：默认安装路径与 `PACE_FUSION_HOME`、`wraptool help` 列出的 flag、不给账号时用 iLok License Manager 的默认账号、Windows 上签的是 bundle 里的内层 DLL、未签名件 `verify` 的退出码、`--signid` 收证书指纹、时间戳默认就加、`--password` 与 `--pswd-no-save` 的区别（两者都带口令值）。
>
> 同日完成首次真签名（wraptool 6.0.1 + Windows SDK 10.0.19041 的 signtool + 自签名证书），以下已实测：`--signid` 指纹 + `--wcguid` + `--signtool` 的真签名成功；对内层 DLL 原地签名；已签名件 `wraptool verify` 退出码 0（输出 "The digital signature was verified" 与 "The binary was signed, but not wrapped."）；`--verbose` 不回显口令（会回显 wcguid、默认账号名和它调用 signtool 的整条命令行，前两者脚本已打码）；签名件确实带时间戳。文件摘要默认为 SHA256 + RFC 3161 时间戳，做法见 §7.3 第 4 步。
>
> 仍标 **TO-VALIDATE** 的：自签名证书签的件零售版 Pro Tools / Pro Tools Intro 是否接受；`-KeyFile` 身份与 customer number 发布者这两条备选路径还没真签过；证书放在 `Cert:\LocalMachine\My`（而不是 `CurrentUser\My`）时能否签；`gh release upload` 能否直传 draft；macOS 侧全部（脚本照搬同一套写法，但 mac 上没法实测，相关项全部保留标记）。签名脚本的预检在 flag 不符时会中止并提示；核对完删除脚本与本节里的标记。

### 7.1 一次性准备（Windows）

1. 安装 PACE 的 AAX 代码签名工具（含 `wraptool`，本节按 6.0.1 编写）与 iLok License Manager；签名授权在维护者的 iLok 上，签名时插着。
   - 安装器把 `wraptool.exe` 放在 `%ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\6\bin\`，并设置 Machine 级环境变量 `PACE_FUSION_HOME`。**装完要新开一个终端**：装之前就开着的终端里没有这个变量，wraptool 会报 "The PACE_FUSION_HOME environment variable is not defined"。`sign-aax.ps1` 发现进程里没有它时会从 Machine 级补上（退出时撤掉）；两处都没有就 FAIL，提示新开终端或重装签名工具。
   - `sign-aax.ps1` 依次找 `-WraptoolPath`、`$env:PACE_FUSION_HOME\bin\wraptool.exe`、PATH、`%ProgramFiles%\PACEAntiPiracy\Eden\Fusion\Versions\<版本号最高的>\bin\wraptool.exe`，最后试 `%ProgramFiles(x86)%` 下的同一路径。
   - 另需 Windows SDK 的 `signtool.exe`（安装 Windows SDK 时勾选「Windows SDK Signing Tools for Desktop Apps」组件）。wraptool 6.0.1 在它自己的「默认位置」找不到 SDK 10.0.19041 的 signtool，所以 `sign-aax.ps1` 每次都经 `--signtool` 显式指定。查找顺序：`-SignToolPath`、`%ProgramFiles(x86)%\Windows Kits\10\bin\<版本号最高的>\x64\signtool.exe`、PATH；都找不到就 FAIL。预检会打印找到的路径和版本。
2. 在 PACE Central 里为本产品建好产品与 wrap 配置，拿到 wcguid。没有 wcguid 时，可以改用 PACE 发的 customer number（`-CustomerNumber` 加 `-CustomerName`）。
3. 生成自签名代码签名证书（先 `-WhatIf` 预演，不写证书库）：

   ```powershell
   pwsh scripts/new-selfsigned-codesign-cert.ps1 -WhatIf
   pwsh scripts/new-selfsigned-codesign-cert.ps1   # 证书留在 Cert:\CurrentUser\My;pfx 默认导出到 $env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx
   ```

   记下脚本最后打印的 **Thumbprint**，签名时传给 `sign-aax.ps1 -CertThumbprint`（推荐方式：wraptool 直接用「个人」证书库里的证书签名，不读 pfx 口令，wraptool 的命令行上也没有 `--keypassword`）。这种方式要求证书留在 `Cert:\CurrentUser\My`，所以**不要加 `-RemoveFromStore`**；加了就只能用 `-KeyFile <pfx>` 方式。pwsh 7 里没有 PKI cmdlet 时，改用 `powershell.exe -File scripts/new-selfsigned-codesign-cert.ps1`（TO-VALIDATE）。证书是自签名的：用户在「属性 → 数字签名」里会看到不受信任的签名者，属预期；零售版 Pro Tools 是否照常加载待首次真签名验证（TO-VALIDATE）。

4. 把 pfx 和口令备份进密码管理器：pfx 是证书的仓库外备份（换机器时导入「个人」证书库，就能接着用 `-CertThumbprint`），也可以直接交给 `-KeyFile`。pfx 只放在仓库外（`.gitignore` 也已忽略 `*.pfx` / `*.p12` / `*.pvk`）；PACE 账号、wcguid 与 customer number 只在签名时作为命令行参数传入，**不写进任何入库文件**。
5. **PACE 账号口令**。`-WcGuid` 方式签名要连 PACE 服务器，需要账号口令。两种处理方式：
   - 推荐：先手动执行一次带 `--password` 的 `sync`，口令存进 wraptool 自己的钥匙串（与 iLok License Manager 的口令分开保存），之后签名不用再给：

     ```powershell
     $p = Read-Host -AsSecureString 'PACE 账号口令'
     & "$env:PACE_FUSION_HOME\bin\wraptool.exe" sync --account <PACE 账号> --password ([System.Net.NetworkCredential]::new('', $p).Password)
     Remove-Variable p
     ```

     这样写，口令不进 PowerShell 历史（历史里只有表达式）；`sync` 运行的那几秒它同样出现在 wraptool 的进程命令行里。要清除时执行 `wraptool remove-pswd --account <PACE 账号>`。
   - 不想存进钥匙串：签名时加 `-Account <PACE 账号> -PromptAccountPassword`，脚本交互读入口令，经 `--pswd-no-save` 交给 wraptool，不保存。

   不给 `-Account` 时，wraptool 用 iLok License Manager 的默认账号（实测 6.0.1；维护者本机上这样不给账号口令也连得上 PACE 服务器、取得到 wrap 配置）。

### 7.2 一次性准备（借用的 Mac）

- 在一个独立的 macOS 用户下操作（不要用机主自己的用户），签完按本节最后一条清理。
- 安装 PACE 的 AAX 代码签名工具（含 `wraptool`）与 iLok License Manager。`sign-aax-macos.sh` 依次找 `--wraptool`、`$PACE_FUSION_HOME/bin/wraptool`、PATH、`/Applications/PACEAntiPiracy/Eden/Fusion/Versions/<版本号最高的>/bin/wraptool`（照 Windows 实测的布局推断，TO-VALIDATE）。装完新开一个终端。
- 准备 Keychain 代码签名身份，二选一：Xcode → Settings → Accounts 登录 Apple ID 后创建 **Apple Development** 证书；或「钥匙串访问 → 证书助理 → 创建证书」生成自签名的代码签名证书。
- 用 `security find-identity -p codesigning` 确认身份的完整名字，签名时原样传给 `--signid`。不加 `-v`：自签名身份未被信任时不会出现在 `-v` 列表里（TO-VALIDATE）。
- 第一次签名可能弹出钥匙串授权框，需要人工点「允许」。
- macOS 版**未经 Apple 公证**（没有 Developer Program 会员）：用户必须按 `INSTALL-AAX.txt` 去掉隔离属性 Pro Tools 才会加载；去掉隔离属性不影响签名。
- PACE 账号口令：借用的 Mac 上不要用 `sync --password` 把口令存进 wraptool 的钥匙串，签名时加 `--account "<PACE 账号>" --prompt-account-password`，口令交互读入、经 `--pswd-no-save` 传，不保存（TO-VALIDATE）。签名期间不要让他人登录这台 Mac：口令在签名那几秒会以 `--pswd-no-save <明文>` 出现在 wraptool 的进程命令行里，本机其他用户用 `ps` 就能看到（wraptool 只收命令行参数）。
- `gh`（§7.3 第 2、4、5 步会用到）在这台 Mac 上**不要 `gh auth login`**：改用只授权本仓库、短有效期的 fine-grained PAT（Actions: read；要在 Mac 上上传再加 Contents: read and write），只经当次 shell 的 `GH_TOKEN` 环境变量传入（`read -rs GH_TOKEN && export GH_TOKEN`，不进历史、不落盘），用完到 GitHub 上吊销。
- **签完必须清理，不在别人的机器上留下任何凭据。** 首选直接删除这个独立的 macOS 用户（系统设置 → 用户与群组 → 删除该用户，选「删除个人文件夹」）。不删用户时，下面各项逐一做完：
  1. **GitHub 令牌**：`gh auth logout --hostname github.com`，再用 `gh auth status` 确认已无登录（登录时用过 `--insecure-storage` 的，再删 `~/.config/gh/hosts.yml`）；用的是 `GH_TOKEN` 的，到 GitHub 上吊销该 PAT。
  2. **Apple ID**：Xcode → Settings → Accounts 移除 Apple ID。
  3. **签名证书**：在「钥匙串访问」里删除代码签名证书**及其私钥**（Xcode 创建的 Apple Development 证书与自签名证书都在登录钥匙串里）。
  4. **iLok / PACE**：退出 iLok License Manager 与 PACE 登录；万一把账号口令存进过 wraptool 的钥匙串，用 `wraptool remove-pswd --account <PACE 账号>` 清掉。
  5. **shell 历史**：签名命令里的 `--account` / `--wcguid` / `--customer-number` 是明文，zsh 会把它们写进 `~/.zsh_history` 与 `~/.zsh_sessions/`，删掉这两处（`rm -f ~/.zsh_history; rm -rf ~/.zsh_sessions`）。也可以签名前先执行 `setopt HIST_IGNORE_SPACE`，再在签名命令前加一个空格，让它不进历史。

### 7.3 每次发版

1. **确认 tag 运行全绿、draft 已建出**（§5）。此时 draft 上只有 VST3 / AU 的四个资产。
2. **找到这次 tag 的 run，下载未签名件**：

   ```powershell
   gh run list --repo synchain-oss/synchain-bridge --workflow release.yml --branch v<X.Y.Z>   # 查不到就去掉 --branch 按时间找
   gh run download <run-id> --repo synchain-oss/synchain-bridge -n aax-unsigned-win64 -D "$env:TEMP\aax-v<X.Y.Z>"
   # macOS 件:-n aax-unsigned-macos-arm64(在 Mac 上直接下载,或在 Windows 下好后拷过去)
   ```

   artifact 里是 `SynchainBridge-AAX-v<X.Y.Z>-<平台>-UNSIGNED.zip` 与同名 `.sha256`，两者要留在同一目录（签名脚本先校验哈希）。**记下这里的 `<run-id>`**：第 4 步要原样传给签名脚本做来源核对。

3. **从 `prod` 上的 tag 检出**。正式 tag 只打在 `prod` 上（§5）。签名脚本要求 HEAD 正好是 `v<X.Y.Z>`，且 `LICENSE` / `THIRD-PARTY-NOTICES.md` / `LICENSES` / `scripts` 没有本地改动 —— 发行 zip 里的合规文件与打包脚本必须是这个版本的：

   ```powershell
   git fetch origin --tags
   git merge-base --is-ancestor v<X.Y.Z> origin/prod; $LASTEXITCODE   # 0 = tag 在 prod 上;非 0 就停下,先查 tag 打在了哪里
   git worktree add ..\bridge-v<X.Y.Z> v<X.Y.Z>
   ```

   Mac 上：`git clone --depth 1 --branch v<X.Y.Z> https://github.com/synchain-oss/synchain-bridge.git bridge-v<X.Y.Z>`。

4. **签名并打发行包**（在上一步检出的根目录、pwsh 7.3+ 会话里用 `&` 执行）：

   ```powershell
   & ./scripts/sign-aax.ps1 -UnsignedZip "$env:TEMP\aax-v<X.Y.Z>\SynchainBridge-AAX-v<X.Y.Z>-win64-UNSIGNED.zip" `
     -SourceRunId <run-id> `
     -CertThumbprint <证书 SHA1 指纹> -WcGuid <wcguid>
   # 可选:-SignToolPath "<signtool.exe 的完整路径>"(不给就按 §7.1 第 1 步的顺序自动找)
   ```

   ```bash
   bash scripts/sign-aax-macos.sh --unsigned-zip "<下载目录>/SynchainBridge-AAX-v<X.Y.Z>-macos-arm64-UNSIGNED.zip" \
     --source-run-id <run-id> \
     --signid "<Keychain 身份名>" --wcguid "<wcguid>"
   ```

   参数各有备选（每组只能选一种，脚本预检会拦下混用）：
   - **签名身份**（Windows）：`-CertThumbprint` 换成 `-KeyFile "$env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx" -LegacySha1Digest`，签名时交互读 pfx 口令。`-KeyFile` 必须带 `-LegacySha1Digest`，原因见下面「摘要算法」一段。
   - **发布者**：`-WcGuid` 换成 `-CustomerNumber <customer number> -CustomerName <公司名>`（`-ProductName` 默认 `Synchain Bridge`）；macOS 为 `--customer-number` / `--customer-name` / `--product-name`。
   - **账号**：不给 `-Account` / `--account` 时 wraptool 用 iLok License Manager 的默认账号；账号口令没按 §7.1 第 5 步存进 wraptool 钥匙串时，加 `-Account <PACE 账号> -PromptAccountPassword`（macOS 为 `--account` + `--prompt-account-password`），口令经 `--pswd-no-save` 传、不保存。

   **Windows 上 wraptool 签的是内层 DLL**：`.aaxplugin` 是个目录，Windows 版 wraptool 的 `--in` 只收文件（给目录会报 "A file must be specified ..."）。脚本先把整个 bundle 复制到临时工作目录的 `out\`，只对其中的 `Contents\x64\Synchain Bridge.aaxplugin`（主体 DLL）原地签名；后检要求 bundle 里除这个 DLL 之外的文件与输入件逐字节相同，也没有多出文件。

   **摘要算法（Windows）**：wraptool 6.0.1 默认调用的 signtool 命令是 `sign /sha1 "<指纹>" /t http://timestamp.sectigo.com <文件>`，也就是 SHA1 文件摘要加旧式（`/t`）时间戳。脚本默认经 `--explicitsigningoptions` 改成 SHA256 文件摘要加 RFC 3161 时间戳，交给 wraptool 的值是 `sign /sha1 <指纹> /fd sha256 /tr http://timestamp.sectigo.com /td sha256`。证书在 `Cert:\LocalMachine\My` 时，脚本会在指纹后加 `/sm`：signtool 默认只查当前用户的库，加 `/sm` 才查本机库。这条路径没有实测过（TO-VALIDATE）。2026-10-08 实测结论：
   - 这个值按空格切开后**整体替换** wraptool 默认的 signtool 参数，所以 `sign` 子命令和 `/sha1` 都要自己写；只给 `/fd sha256 ...` 时 signtool 报 "Invalid command: /fd"；
   - 文件路径仍由 wraptool 追加在最后；
   - 这种方式下 `--signid` 不参与签名，不给也能签，脚本照传；
   - 连签四次，结果都是 SHA256 文件摘要（`signtool verify /pa /v` 显示 "Hash of file (sha256)"）加 Sectigo 的 RFC 3161 时间戳（摘要 SHA256），`wraptool verify` 退出码都是 0。

   后检从 DLL 的 PE 证书表解出 PKCS#7，要求文件摘要与签名者摘要都是 SHA256、时间戳是 RFC 3161（摘要 SHA256，且与签名对得上）。`-LegacySha1Digest` 回退到 wraptool 的默认命令（不传 `--explicitsigningoptions`），后检相应改为要求 SHA1。`-KeyFile` 方式只能走回退：要 SHA256，就得把 pfx 路径和口令写进 `--explicitsigningoptions`（`/f <pfx> /p <口令>`）。wraptool 按空格切分这个值，含空格的值怎么切没有实测过；`--verbose` 还会把整条 signtool 命令行打印出来。脚本不这么做；`-KeyFile` 不带 `-LegacySha1Digest` 时，预检 0 直接拦下。要 SHA256，就把 pfx 导入「个人」证书库，改用 `-CertThumbprint`。

   **口令**：`-CertThumbprint` 方式不读证书口令，wraptool 的命令行上也没有 `--keypassword`。`-KeyFile` 方式的 pfx 口令与 `-PromptAccountPassword` / `--prompt-account-password` 的账号口令交互读取，不进签名脚本的参数、脚本日志、transcript 与 shell 历史；但 wraptool 只接受命令行参数（6.0.1 的 help 里没有 stdin / 环境变量通道），签名的那几秒里它们会以 `--keypassword <明文>` / `--pswd-no-save <明文>` 出现在 wraptool 的进程命令行中：本机进程列表短暂可见，开着进程命令行审计（Security 4688 勾选了「包含命令行」、Sysmon EID 1、Defender for Endpoint 等 EDR）时还会被记录下来。这是 wraptool 本身的限制。只在可信的单用户机器上签名，签名期间不要让他人登录本机；事后发现开着这类审计，就当口令已泄露：pfx 口令泄露就重新生成证书，账号口令泄露就改 PACE 账号口令。

   `<run-id>` 就是第 2 步查到并下载过的那个 release run（需要 `gh` 已登录；借用的 Mac 上按 §7.2 用短有效期的 `GH_TOKEN`）。给了它，签名脚本会做**来源核对**：该 run 属于本仓库（不是 fork）、是 `release.yml`（或 `ci.yml`）、结论为 success、事件为 push / workflow_dispatch（tag 触发的 release run 是 push）、`head_sha` 等于当前检出（即 tag 所指的提交），再用 `gh run download` 重新取回它的 `aax-unsigned-*` artifact，同名 zip 必须与输入件字节相同 —— 由此确认被盖上签名的字节确实出自这次 tag 的 CI 构建。`.sha256` 只防下载损坏（它与 zip 是同一份下载，防不了替换）。不给 `-SourceRunId` / `--source-run-id` 时这一项只记 WARN、不拦截；只在没有 run 可核对时这样用（§7.4 的本机重建件）。

   脚本依次做：预检（参数组合、`.sha256` 完整性、版本与检出一致、来源核对、签名身份可用（Windows `-CertThumbprint` 的证书在「个人」证书库里、带私钥、未过期、用途含代码签名；`-KeyFile` 在仓库外；macOS 要求钥匙串里与 `--signid` 同名的代码签名身份恰好 1 个）、补齐 `PACE_FUSION_HOME`、wraptool 存在且 `wraptool help` 列出本次要用的 flag、Windows 找到 signtool、输入件确实未签名且 `wraptool verify` 必须失败（Windows 对内层 DLL 执行，要求输出 NOT signed））→ 交互读入口令（只在 `-KeyFile` / `-PromptAccountPassword` 时）→ `wraptool sign` → 后检（`wraptool verify`；Windows 核对 bundle 只有内层 DLL 变了、Authenticode 签名者指纹等于 `-CertThumbprint` / pfx 指纹、摘要算法与时间戳形态符合上一段、默认要求带时间戳，macOS 跑 `codesign --verify --deep --strict` 并核对 `Authority=` 等于 `--signid`、不是 ad-hoc）→ 调用打包脚本的 Signed 模式 → 把产出的 zip 解压回读再验一轮 → 打印第 5 步的上传命令（不自动执行）。产物在 `dist/aax-signed/`（`-OutDir` / `--out-dir` 可改）：`SynchainBridge-AAX-v<X.Y.Z>-win64.zip`（macOS 为 `-macos-arm64.zip`）与同名 `.sha256`。

   其他开关：`-DryRun` / `--dry-run` 只跑预检并打印打码后的签名计划（不读口令、不调用 `wraptool sign`、不产出文件）；`-WraptoolPath` / `--wraptool` 显式指定 wraptool；Windows 的 `-SignToolPath` 显式指定 signtool，`-LegacySha1Digest` 回退到 SHA1 文件摘要（见上面「摘要算法」）；`-ExtraWraptoolArgs` / `--extra-arg`（可重复）原样透传给 `wraptool sign`，例如 `--timestampretry 120`（含 `password` / `pswd` 的项与脚本自管的 flag 会被拒收，长短写法都算；Windows 上 `--signtool` / `--explicitsigningoptions` / `--extrasigningoptions` 也归脚本管）。`-ExtraWraptoolArgs` 是数组：只能在 pwsh 会话里用 `&` 调用时传（`-ExtraWraptoolArgs '--timestampretry','120'`），经 `pwsh scripts/sign-aax.ps1 ...` 传会错位（见 §7.4 排障表）。`--explicitsigningoptions` 方式下 wraptool 的 `--timestampretry` 是否还生效没有实测过（TO-VALIDATE）。Windows 确认接受无时间戳的签名时加 `-AllowNoTimestamp`（见 §7.4）。

5. **上传到 draft**（签名脚本只打印这条命令，不自动执行）：

   ```powershell
   gh release upload v<X.Y.Z> dist/aax-signed/SynchainBridge-AAX-v<X.Y.Z>-win64.zip dist/aax-signed/SynchainBridge-AAX-v<X.Y.Z>-win64.zip.sha256 --repo synchain-oss/synchain-bridge
   ```

   macOS 件同理（文件名换成 `-macos-arm64`）。`gh` 找不到 draft 时（TO-VALIDATE），在网页上打开 draft → Edit，把两个文件拖进附件区。

6. **验收**：两个平台都签了时 draft 上应有 8 个资产（VST3 / AU 两个 zip + AAX 两个 zip，各带 `.sha256`）；本版只发 Windows AAX 时为 6 个，并在 Release notes 里注明 macOS AAX 稍后提供。把 AAX 资产下载到一个新目录跑 `sha256sum -c *.sha256`，再用签名件按 [DAW_TEST_GUIDE.md 的 Pro Tools 一节](DAW_TEST_GUIDE.md#pro-toolsaax实测windows--macos)跑完 T01–T13。
7. 可选：Release 标题追加「· AAX」。
8. 转为正式发布（§6）。

### 7.4 失败处理

- **本机签名失败不影响 draft**：修掉原因后从同一个 `-UNSIGNED.zip` 重跑即可。签名脚本每次都解压到一个新的临时工作目录，从不修改输入件；失败时保留工作目录并打印路径（里面只有 bundle，没有秘密），排查完直接删掉。
- **签名脚本失败时 `dist/aax-signed/` 里不会留下本次的发行名 zip**：打包之后的回读复验没通过，脚本会删掉刚产出的 zip 与 `.sha256`（`package-summary.md` 里本次追加的段落会留下，只是记录）。看到 FAIL 就不要去找文件上传。
- **签名必须是对 bundle 的最后一次修改**：签完之后再改 bundle 里的任何文件都会让签名失效，所以也**不要事后用 signtool 补时间戳**。Windows 签名件没带时间戳时 `sign-aax.ps1` 默认判失败；确认接受无时间戳的签名，再显式加 `-AllowNoTimestamp` 从原始 `-UNSIGNED.zip` 重跑。wraptool 默认就加时间戳（6.0.1 help：时间戳服务器不可用时每 10 秒重试一次，最多 600 秒，可用 `--timestampretry` / `--timestampretrysleep` 调整）；2026-10-08 实测签名件确实带 Sectigo 的时间戳。
- **wraptool 报 "The PACE_FUSION_HOME environment variable is not defined"**：终端是装签名工具之前开的。签名脚本会自己补上这个变量；手动跑 wraptool 时新开一个终端，新终端里仍没有就重装签名工具。
- **自签名证书的正常现象**：`signtool verify /pa` 报 "A certificate chain processed, but terminated in a root certificate which is not trusted by the trust provider"，`Get-AuthenticodeSignature` 的 Status 是 `UnknownError`。这只说明根证书不受本机信任，签名本身完好，脚本按预期放行（只拦 `NotSigned` / `HashMismatch` / `NotSupportedFileFormat`）。

**排障表**（Windows，2026-10-08 实测）：

| 报错原文 | 原因 | 解决办法 |
|---|---|---|
| `BinaryDsigException::CodesignToolError ... Can't sign with the certificate identified by the thumbprint <指纹>` | 看着像证书有问题，其实证书没问题（signtool 直接 `/sha1 <指纹>` 能签）：不给 `--signtool` 时，wraptool 在它自己的「默认位置」找不到 Windows SDK 10.0.19041 的 `signtool.exe` | `sign-aax.ps1` 每次都经 `--signtool` 显式传 signtool，正常不会再遇到。手动跑 wraptool 时加 `--signtool "<signtool.exe 的完整路径>"`；脚本找不到 signtool 时（预检 5d FAIL）装 Windows SDK 的「Windows SDK Signing Tools for Desktop Apps」组件，或用 `-SignToolPath` 指定 |
| `AuthorizationException::CouldNotFindSignerCredentials ... use the iLok License Manager to perform a Synchronize operation on your iLok` | iLok 上还没有同步下来签名证书 | 在 iLok License Manager 里对这个 iLok USB 做一次 Synchronize。完成后 iLok 详情里会出现 "Digital Signing Certified Expires ..."，再从同一个 `-UNSIGNED.zip` 重跑 |
| 用 `pwsh scripts/sign-aax.ps1 ... -ExtraWraptoolArgs '--timestampretry','120'` 调用时报「-CertThumbprint 与 -KeyFile 互斥」一类的参数错误，实际并没有同时给这两个参数 | `pwsh <脚本>` 等同 `pwsh -File`：命令行上的数组参数不会被解析成数组，后面的参数随之错位 | 在 pwsh 7.3+ 会话里用 `& ./scripts/sign-aax.ps1 ...` 调用（§7.3 第 4 步的写法）。signtool 路径直接用 `-SignToolPath`，不要经 `-ExtraWraptoolArgs` 传（`--signtool` 归脚本管，会被拒收） |
- **正式发布之后也能补传 AAX**：同样用第 5 步的 `gh release upload`，并在 Release notes 里注明补发。
- **artifact 30 天后过期**：只能在第 3 步的 tag 检出里本机重新构建（[build-windows.md](build-windows.md) / [build-macos.md](build-macos.md)），用 §4 的 AAX 打包命令以 Unsigned 模式（`-Version <X.Y.Z>`，源码链接默认指向 `v<X.Y.Z>`）重新打出 `-UNSIGNED.zip`，再从第 4 步继续 —— 这时没有 CI run 可核对，签名命令不带 `-SourceRunId` / `--source-run-id`（来源核对记 WARN）。本机工具链与 CI 不同，须在 Release notes 里注明。**不要用 Re-run 重跑这次 tag 的 release run 来续 artifact**：GitHub 只允许在原 run 发起后 30 天内重跑（与 artifact 保留期一样长，过期时已经不能重跑）；而且重跑任何构建 job 都会连带重跑依赖它的 `publish`。`softprops/action-gh-release`（v2.6.2）找到同 tag 的现有 Release 时走更新路径：不会把已发布的 Release 改回 draft，但 `overwrite_files` 默认为 true，会删掉并重传四个同名 VST3 / AU 资产 —— 重新构建出的 zip 字节通常不同，用户手里文件的 sha256 就对不上了。
