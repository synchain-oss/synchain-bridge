# 发布流程

> 发布由 `push: tags: ['v*']` 触发 [.github/workflows/release.yml](../.github/workflows/release.yml)，全自动完成「版本一致性门禁 → 两平台构建 → pluginval / auval → 打包 zip/sha256 → 草稿 Release」。发版者在本地只需两步：**改版本号 + 打 tag**。
>
> 版本号唯一真源 = 顶层 `CMakeLists.txt` 的 `project(... VERSION)`；tag 格式 `vX.Y.Z`（去掉旧 `vst-` 前缀）。首个公开 tag = `v1.4.0`。

## 0. release.yml 做什么

workflow 分四个 job：版本门禁独立前置，两个平台并行构建，最后由一个 job 统一建 Release。

| job | runner | 动作 | 失败即 job fail？ |
|---|---|---|---|
| `gate` | ubuntu-latest | 校验 tag 与 `CMakeLists.txt` 的 VERSION 一致，把版本号导出给下游两个构建 job | 是（冒烟 tag `*-test` 除外，恒产 draft） |
| `release` | windows-2022 | clone JUCE → vcpkg → WebView2 → CMake → 构建（/W4 零警告）→ pluginval → `scripts/package.ps1` → 上传 `dist-win64` | 是 |
| `release-macos` | macos-15 | clone JUCE → Ninja → 构建（clang 零警告）→ pluginval 验 VST3 + auval 验 AU → `scripts/package-macos.sh` → 上传 `dist-macos-arm64` | 是 |
| `publish` | ubuntu-latest | 下载两平台产物 → `sha256sum -c` 跨 job 复验 → 创建 **draft** GitHub Release（挂两平台的 zip + `.sha256`） | 是 |

两条与安全/成本有关的结构性约定：

- **权限**：workflow 级降为 `contents: read`，`contents: write` 只授给 `publish` 一个 job。构建 job 要跑第三方代码（JUCE / vcpkg / pluginval），一律拿不到写 Release 的权限。
- **门禁前置**：tag 打错时 `gate` 先红，windows / macOS 两个构建 job 根本不会起，不浪费分钟数。

产物命名（版本号由 `gate` 算出，脚本内绝不写字面量）：

| 平台 | zip | zip 内容 |
|---|---|---|
| Windows x64 | `SynchainBridge-VST3-v<版本>-win64.zip` | `Synchain Bridge.vst3` + 合规文件 |
| macOS arm64 | `SynchainBridge-VST3-AU-v<版本>-macos-arm64.zip` | `Synchain Bridge.vst3` + `Synchain Bridge.component` + 合规文件 |

两个 zip 的「合规文件」都是同一组：`LICENSE.txt` + `THIRD-PARTY-NOTICES.md` + `LICENSES/OFL-1.1.txt` + `INSTALL.txt`（INSTALL.txt 按平台各写各的）。

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

## 5. 打 tag 触发 release.yml

```powershell
git tag v1.4.0
git push origin v1.4.0
```

触发后：`gate` 校验版本 → `release` / `release-macos` 并行构建、验证、打包 → `publish` 复验哈希并建 **draft** Release。到 GitHub Releases 页面把草稿转正式即可。

### 5.1 冒烟 tag（`v0.0.0-test`）：首次改动发版链路后必须实跑

`gate` 对 `*-test` 结尾的 tag 跳过严格版本相等，产物恒为 draft。改过 `release.yml` / 打包脚本 / `CMakeLists.txt` 的平台相关部分之后，先打一个冒烟 tag 端到端验证四段链路（`gate` → `release` ∥ `release-macos` → `publish`），确认 **draft Release 真被建出来、两个平台的 zip 与 `.sha256` 都挂上了**，再打真实版本 tag：

```powershell
git tag v0.0.0-test
git push origin v0.0.0-test
# 验完删掉：先在 Releases 页面删 draft，再删 tag
git push origin :refs/tags/v0.0.0-test
git tag -d v0.0.0-test
```

## 6. 发布后

- 把 draft Release 转正式（public 仓库的 Release 附件才可匿名下载）。
- 同步下游版本镜像：网页侧（闭源仓库）存在一份下游版本镜像，发版后必须同步（见 [web-client.md](web-client.md)）。
- 本版本**不签名**（U13）：Windows 的 INSTALL.txt 写明 SmartScreen 提示与「更多信息 → 仍要运行」的引导；macOS 的 INSTALL.txt 写明 `xattr -dr com.apple.quarantine` 两条命令（全局路径要 `sudo`，家目录不要）、AU 缓存重扫，以及 arm64-only / Rosetta 的注意事项。

### 6.1 ⚠️ 任一平台失败 = 整个 tag 无产物

`publish` 是 `needs: [release, release-macos]`，两个平台都绿才建 Release。**macOS 侧任何偶发失败（runner 镜像抖动、brew、`auval` 不稳、超时）都会让整个 tag 一个产物都发不出去**，包括已经构建打包成功的 Windows zip —— 这相对「Windows job 自带 `softprops`、能独立出 Release」的旧实现是一次有意的行为收敛（换来的是权限只授给 `publish` 一个 job、两平台产物一次性挂进同一个 Release）。

处理：修掉失败原因后，**删掉 draft Release（如果有）与该 tag，再重新打同名 tag**：

```powershell
git push origin :refs/tags/v1.5.0
git tag -d v1.5.0
# 修复后重新打
git tag v1.5.0 && git push origin v1.5.0
```

两个构建 job 的 `timeout-minutes` 都是 60（对称；两边都要从零 clone JUCE 并编译两个 format wrapper，mac 侧还多一次 ixwebsocket 的 FetchContent 编译）。若将来希望「mac 挂了 Windows 仍能发」，改法是把 `publish` 换成 `if: always() && needs.release.result == 'success'` 并按存在的 artifact 动态挂载 —— 属于**需要用户拍板**的行为变更，未擅自实施。
