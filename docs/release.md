# 发布流程

> 发布由 `push: tags: ['v*']` 触发 [.github/workflows/release.yml](../.github/workflows/release.yml)，全自动完成「版本一致性门禁 → 构建 → pluginval → 打包 zip/sha256 → 草稿 Release」。发版者在本地只需两步：**改版本号 + 打 tag**。
>
> 版本号唯一真源 = 顶层 `CMakeLists.txt` 的 `project(... VERSION)`；tag 格式 `vX.Y.Z`（去掉旧 `vst-` 前缀）。首个公开 tag = `v1.4.0`。

## 0. release.yml 做什么

| 步骤 | 动作 | 失败即 job fail？ |
|---|---|---|
| 版本门禁 | 校验 tag 与 `CMakeLists.txt` 的 VERSION 一致 | 是（冒烟 tag `*-test` 除外，恒产 draft） |
| 构建 | clone JUCE → vcpkg → WebView2 → CMake → 构建（/W4 零警告） | 是 |
| pluginval | strictness 5 `--skip-gui-tests` | 是 |
| 打包 | 调 `scripts/package.ps1`（唯一打包真源） | 是 |
| Release | 创建 **draft** GitHub Release + zip + `.sha256` | 是 |

## 1. 改版本号

把 `CMakeLists.txt:9` 的 VERSION 改成目标版本：

```
project(SynchainBridgeVST VERSION 1.4.0)
```

版本经 `JucePlugin_VersionString` 自动流入插件 UI 与 `status` 帧上报，无需再改任何手写常量（见 `BRIDGE_CONTRACT.md` §三）。

## 2. 构建（本地验证）

按 [build-windows.md](build-windows.md) 构建 Release 版，确认产物存在。

## 3. pluginval 验证

```powershell
./pluginval/pluginval.exe --strictness-level 5 --timeout-ms 60000 --skip-gui-tests "build\SynchainBridgeVST_artefacts\Release\VST3\Synchain Bridge.vst3"
```

> 含 WebView2 编辑器的**全量** strictness-5（去掉 `--skip-gui-tests`）必须在真实 Win11 本地跑——无头 runner 无法托管编辑器，这是本地门禁，CI 只能跑非 GUI 部分。

## 4. 打包（唯一真源 = scripts/package.ps1）

```powershell
pwsh scripts/package.ps1 -Version 1.4.0 -BuildDir build -OutDir dist
# gate 用：只校验合规源文件、不产出任何产物
pwsh scripts/package.ps1 -DryRun
```

产出：`dist/SynchainBridge-VST3-v1.4.0-win64.zip` + `.zip.sha256` + `package-summary.md`。zip 内已含 `Synchain Bridge.vst3`（保住 `Contents/` 层级）+ `LICENSE.txt` + `THIRD-PARTY-NOTICES.md` + `LICENSES/OFL-1.1.txt` + `INSTALL.txt`。打包逻辑只在脚本里，绝不内联到 workflow。

## 5. 打 tag 触发 release.yml

```powershell
git tag v1.4.0
git push origin v1.4.0
```

触发后 `release.yml` 会：校验版本 → 构建 → pluginval → 打包 → 建 **draft** Release。到 GitHub Releases 页面把草稿转正式即可。

## 6. 发布后

- 把 draft Release 转正式（public 仓库的 Release 附件才可匿名下载）。
- 同步下游版本镜像：网页侧（闭源仓库）存在一份下游版本镜像，发版后必须同步（见 [web-client.md](web-client.md)）。
- 本版本**不签名**（U13）：INSTALL.txt 已写明 SmartScreen 提示与「更多信息 → 仍要运行」的引导。
