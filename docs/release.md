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

macOS（Apple Silicon）：

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DJUCE_PATH="$JUCE_PATH"
cmake --build build --parallel
```

架构参数与部署目标都写在 `CMakeLists.txt` 里，命令行不重复传 —— 单一真源。v1 只出 **arm64**：Intel Mac 与被勾了「使用 Rosetta 打开」的宿主都加载不了，这一点由打包脚本的 `file` 断言强制，也写进了 macOS 版 INSTALL.txt。

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

两个脚本的产出结构一致：`dist/<平台 zip>` + `.zip.sha256` + `package-summary.md`。macOS 侧一律用 `ditto` 拷贝与压缩——`cp -r` / `zip -r` 会丢符号链接与可执行位，用户解压后拿到的是加载不了的死壳；打包后脚本会断言 zip 内 `Contents/MacOS/*` 仍是 `-rwx`。打包逻辑只在脚本里，绝不内联到 workflow。

## 5. 打 tag 触发 release.yml

```powershell
git tag v1.4.0
git push origin v1.4.0
```

触发后：`gate` 校验版本 → `release` / `release-macos` 并行构建、验证、打包 → `publish` 复验哈希并建 **draft** Release。到 GitHub Releases 页面把草稿转正式即可。

## 6. 发布后

- 把 draft Release 转正式（public 仓库的 Release 附件才可匿名下载）。
- 同步下游版本镜像：网页侧（闭源仓库）存在一份下游版本镜像，发版后必须同步（见 [web-client.md](web-client.md)）。
- 本版本**不签名**（U13）：Windows 的 INSTALL.txt 写明 SmartScreen 提示与「更多信息 → 仍要运行」的引导；macOS 的 INSTALL.txt 写明 `xattr -dr com.apple.quarantine` 两条命令、AU 缓存重扫，以及 arm64-only / Rosetta 的注意事项。
