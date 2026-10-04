# 发布流程

> 发布由 `push: tags: ['v*']` 触发 [.github/workflows/release.yml](../.github/workflows/release.yml)，全自动完成「版本一致性门禁 → 两平台构建 → pluginval / auval → 打包 zip/sha256 → 草稿 Release」。发版者在本地只需两步：**改版本号 + 打 tag**。
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

## 5. 打 tag 触发 release.yml

```powershell
# <X.Y.Z> = CMakeLists.txt 当前 project(... VERSION)——两者不相等 gate 必红
git tag v<X.Y.Z>
git push origin v<X.Y.Z>
```

触发后：`gate` 校验版本 → `release` / `release-macos` 并行构建、验证、打包 → `publish` 复验哈希并建 **draft** Release。到 GitHub Releases 页面把草稿转正式即可；本版要发 AAX 时，转正式之前先按 §7.3 签名并把 AAX 传上 draft。

### 5.1 冒烟 tag（`v0.0.0-test`）：首次改动发版链路后必须实跑

`gate` 对 `*-test` 结尾的 tag 跳过严格版本相等，产物恒为 draft。改过 `release.yml` / 打包脚本 / `CMakeLists.txt` 的平台相关部分之后，先打一个冒烟 tag 端到端验证四段链路（`gate` → `release` ∥ `release-macos` → `publish`），确认 **draft Release 真被建出来、两个平台的 zip 与 `.sha256` 都挂上了**，再打真实版本 tag。

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

处理：修掉失败原因后，**删掉 draft Release（如果有）与该 tag，再重新打同名 tag**：

```powershell
git push origin :refs/tags/v1.5.0
git tag -d v1.5.0
# 修复后重新打
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

> **TO-VALIDATE**：签名脚本用到的 wraptool 子命令与 flag、PACE 工具的默认安装路径、`gh release upload` 能否直传 draft 等，来自公开资料或尚未实测，Eden 版本不同可能有差异。维护者拿到 PACE 工具后逐条核对（签名脚本的预检在 flag 不符时会中止并提示），核对完删除脚本与本节里的标记。

### 7.1 一次性准备（Windows）

1. 安装 PACE 提供的 Eden 签名工具（含 `wraptool`）与 iLok License Manager。`sign-aax.ps1` 先在 PATH 里找 `wraptool`，找不到再试 Eden 的默认安装路径（TO-VALIDATE），也可以用 `-WraptoolPath` 显式指定。
2. 生成自签名代码签名证书（先 `-WhatIf` 预演，不写证书库）：

   ```powershell
   pwsh scripts/new-selfsigned-codesign-cert.ps1 -WhatIf
   pwsh scripts/new-selfsigned-codesign-cert.ps1   # 默认输出 $env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx
   ```

   pwsh 7 里没有 PKI cmdlet 时，改用 `powershell.exe -File scripts/new-selfsigned-codesign-cert.ps1`（TO-VALIDATE）。证书是自签名的：用户在「属性 → 数字签名」里会看到不受信任的签名者，属预期，不影响 Pro Tools 加载（TO-VALIDATE，以签名件实测为准）。

3. 把 pfx 和口令备份进密码管理器。pfx 只放在仓库外（`.gitignore` 也已忽略 `*.pfx` / `*.p12` / `*.pvk`）；PACE 账号和 wcguid 只在签名时作为命令行参数传入，**不写进任何入库文件**。

### 7.2 一次性准备（借用的 Mac）

- 在一个独立的 macOS 用户下操作，签完整体清理。
- 安装 PACE 工具（Eden / `wraptool`，默认路径 TO-VALIDATE，可用 `--wraptool` 指定）与 iLok License Manager。
- 准备 Keychain 代码签名身份，二选一：Xcode → Settings → Accounts 登录 Apple ID 后创建 **Apple Development** 证书；或「钥匙串访问 → 证书助理 → 创建证书」生成自签名的代码签名证书。
- 用 `security find-identity -p codesigning` 确认身份的完整名字，签名时原样传给 `--signid`。不加 `-v`：自签名身份未被信任时不会出现在 `-v` 列表里（TO-VALIDATE）。
- 第一次签名可能弹出钥匙串授权框，需要人工点「允许」。
- macOS 版**未经 Apple 公证**（没有 Developer Program 会员）：用户必须按 `INSTALL-AAX.txt` 去掉隔离属性 Pro Tools 才会加载；去掉隔离属性不影响签名。
- **用完删除签名身份和临时 keychain，退出 iLok / PACE 登录**，不在别人的机器上留下任何凭据。

### 7.3 每次发版

1. **确认 tag 运行全绿、draft 已建出**（§5）。此时 draft 上只有 VST3 / AU 的四个资产。
2. **找到这次 tag 的 run，下载未签名件**：

   ```powershell
   gh run list --repo synchain-oss/synchain-bridge --workflow release.yml --branch v<X.Y.Z>   # 查不到就去掉 --branch 按时间找
   gh run download <run-id> --repo synchain-oss/synchain-bridge -n aax-unsigned-win64 -D "$env:TEMP\aax-v<X.Y.Z>"
   # macOS 件:-n aax-unsigned-macos-arm64(在 Mac 上直接下载,或在 Windows 下好后拷过去)
   ```

   artifact 里是 `SynchainBridge-AAX-v<X.Y.Z>-<平台>-UNSIGNED.zip` 与同名 `.sha256`，两者要留在同一目录（签名脚本先校验哈希）。

3. **准备与 tag 一致的检出**。签名脚本要求 HEAD 正好是 `v<X.Y.Z>`，且 `LICENSE` / `THIRD-PARTY-NOTICES.md` / `LICENSES` / `scripts` 没有本地改动 —— 发行 zip 里的合规文件与打包脚本必须是这个版本的：

   ```powershell
   git fetch origin --tags
   git worktree add ..\bridge-v<X.Y.Z> v<X.Y.Z>
   ```

   Mac 上：`git clone --depth 1 --branch v<X.Y.Z> https://github.com/synchain-oss/synchain-bridge.git bridge-v<X.Y.Z>`。

4. **签名并打发行包**（在上一步检出的根目录执行；证书口令交互输入，绝不进参数、日志或 transcript）：

   ```powershell
   pwsh scripts/sign-aax.ps1 -UnsignedZip "$env:TEMP\aax-v<X.Y.Z>\SynchainBridge-AAX-v<X.Y.Z>-win64-UNSIGNED.zip" `
     -Account <PACE 账号> -WcGuid <wcguid> `
     -KeyFile "$env:USERPROFILE\.synchain-signing\synchain-aax-codesign.pfx"
   ```

   ```bash
   bash scripts/sign-aax-macos.sh --unsigned-zip "<下载目录>/SynchainBridge-AAX-v<X.Y.Z>-macos-arm64-UNSIGNED.zip" \
     --account "<PACE 账号>" --wcguid "<wcguid>" --signid "<Keychain 身份名>"
   ```

   脚本依次做：预检（`.sha256`、版本与检出一致、输入件确实未签名）→ `wraptool sign` → 后检（`wraptool verify`；Windows 比对证书指纹，macOS 跑 `codesign` 校验）→ 调用打包脚本的 Signed 模式 → 把产出的 zip 解压回读再验一轮。产物在 `dist/aax-signed/`：`SynchainBridge-AAX-v<X.Y.Z>-win64.zip`（macOS 为 `-macos-arm64.zip`）与同名 `.sha256`。加 `-DryRun` / `--dry-run` 可只跑预检。

5. **上传到 draft**（签名脚本只打印这条命令，不自动执行）：

   ```powershell
   gh release upload v<X.Y.Z> dist/aax-signed/SynchainBridge-AAX-v<X.Y.Z>-win64.zip dist/aax-signed/SynchainBridge-AAX-v<X.Y.Z>-win64.zip.sha256 --repo synchain-oss/synchain-bridge
   ```

   macOS 件同理（文件名换成 `-macos-arm64`）。`gh` 找不到 draft 时（TO-VALIDATE），在网页上打开 draft → Edit，把两个文件拖进附件区。

6. **验收**：两个平台都签了时 draft 上应有 8 个资产（VST3 / AU 两个 zip + AAX 两个 zip，各带 `.sha256`）；本版只发 Windows AAX 时为 6 个，并在 Release notes 里注明 macOS AAX 稍后提供。把 AAX 资产下载到一个新目录跑 `sha256sum -c *.sha256`，再用签名件按 [DAW_TEST_GUIDE.md](DAW_TEST_GUIDE.md) 的 Pro Tools 一节跑完 T01–T13。
7. 可选：Release 标题追加「· AAX」。
8. 转为正式发布（§6）。

### 7.4 失败处理

- **本机签名失败不影响 draft**：修掉原因后从同一个 `-UNSIGNED.zip` 重跑即可。签名脚本每次都解压到一个新的临时工作目录，从不修改输入件；失败时保留工作目录并打印路径（里面只有 bundle，没有秘密），排查完直接删掉。
- **签名必须是对 bundle 的最后一次修改**：签完之后再改 bundle 里的任何文件都会让签名失效，所以也**不要事后用 signtool 补时间戳**。Windows 签名件没带时间戳时 `sign-aax.ps1` 默认判失败；确认接受无时间戳的签名，再显式加 `-AllowNoTimestamp` 从原始 `-UNSIGNED.zip` 重跑（TO-VALIDATE：wraptool 能否带时间戳）。
- **正式发布之后也能补传 AAX**：同样用第 5 步的 `gh release upload`，并在 Release notes 里注明补发。
- **artifact 30 天后过期**：只能在第 3 步的 tag 检出里本机重新构建（[build-windows.md](build-windows.md) / [build-macos.md](build-macos.md)），用 §4 的 AAX 打包命令以 Unsigned 模式（`-Version <X.Y.Z>`，源码链接默认指向 `v<X.Y.Z>`）重新打出 `-UNSIGNED.zip`，再从第 4 步继续。本机工具链与 CI 不同，须在 Release notes 里注明。**不要用 Re-run 重跑这次 tag 的 release run 来续 artifact**：GitHub 只允许在原 run 发起后 30 天内重跑（与 artifact 保留期一样长，过期时已经不能重跑）；而且重跑任何构建 job 都会连带重跑依赖它的 `publish`。`softprops/action-gh-release`（v2.6.2）找到同 tag 的现有 Release 时走更新路径：不会把已发布的 Release 改回 draft，但 `overwrite_files` 默认为 true，会删掉并重传四个同名 VST3 / AU 资产 —— 重新构建出的 zip 字节通常不同，用户手里文件的 sha256 就对不上了。
