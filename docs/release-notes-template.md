# GitHub Release 正文模板（中英双语）

> 用在 [release.md](release.md) §5 之后：`release.yml` 建出 draft 时，正文是 `generate_release_notes` 自动生成的 PR 列表。发布之前用本模板把它整段换掉（Releases 页面 Edit，或 `gh release edit v<X.Y.Z> --repo synchain-oss/synchain-bridge --notes-file <文件>`）。结构照 v1.5.3 与 v1.6.0 的正文：英文在前、中文在后，中间用 `---` 隔开。

## 怎么填

- `<…>` 全部替换；不适用的行整行删掉。`X.Y.Z` 是本次版本，`A.B.C` 是**上一个已发布**的版本（跳过的内部号不算：1.5.3 的 compare 是 `v1.5.0...v1.5.3`）。
- **SHA-256 不手抄**：从 draft 上的 `.sha256` 资产复制（`gh release download v<X.Y.Z> --repo synchain-oss/synchain-bridge -p '*.sha256' -D <新建的空目录>`），粘贴后再与资产页显示的 digest 逐个核对。资产被重传过（补传 AAX、Re-run）就重核一次。
- **资产表只列实际挂在 Release 上的资产**：没发的平台或格式不写进表，名字里不能有 `-UNSIGNED`。
- **链接钉 tag**：CHANGELOG 链接用 `blob/vX.Y.Z/CHANGELOG.md`，不用 `blob/dev/…`。
- **协议声明与 CHANGELOG 一致**：CHANGELOG 版本节写「不涉及契约变更」，正文就写「No protocol change / 无协议变更」；有协议变更时改写这一条，并链到 [contract-changes](contract-changes/) 下对应的说明。
- **对官网的承诺要成立**：写「Full steps … on https://www.synchain.ca/download」的前提是官网那时已经上线了对应步骤，否则删掉这半句。中文段链 `https://www.synchain.ca/zh/download`。
- **标题**：`release.yml` 默认是「Synchain Bridge vX.Y.Z (Windows x64 · macOS arm64)」；发 AAX 时追加（1.6.0 为「… · AAX Beta」，§7.3 第 7 步）。
- **预发布**：tag 带 `-<后缀>` 时 `release.yml` 已把 draft 标为 prerelease、`make_latest: false`，不要手动取消；正文第一段写明这是预发布版本。正式版不勾 prerelease，发布后成为 Latest。
- 中文段不重复下载表，写「（同上表）」或「文件和 SHA-256 见上表」。

## 模板

```markdown
## Synchain Bridge vX.Y.Z

**<One sentence: the change that matters most to users in this release.>** <Two or three sentences: who is affected, what they saw before, what happens now. Say explicitly which platform is not affected.>

### What's in this release
- **<Fix / New / UI / Hardening / Internal> (<platform or host, if specific>):** <one item per line; for internal changes add "No behaviour change.">
- **No protocol change.** Works with the current Synchain web app; no migration needed.
- On both platforms, remove the old bundle before putting the new one in place — copying over it merges and leaves files from the old version behind. Windows: delete the old `Synchain Bridge.vst3` folder, then copy the new one. macOS: delete the old `.vst3` / `.component` bundles, then `ditto` the new ones in. See `INSTALL.txt`.
- <Skipped version numbers, e.g. "1.5.1 and 1.5.2 were internal test builds and were never released.">

### Downloads
| Platform | File | SHA-256 |
|---|---|---|
| Windows x64 (VST3) | `SynchainBridge-VST3-vX.Y.Z-win64.zip` | `<sha256>` |
| macOS Apple Silicon (VST3 + AU) | `SynchainBridge-VST3-AU-vX.Y.Z-macos-arm64.zip` | `<sha256>` |
| Windows x64 (AAX for Pro Tools, Beta) | `SynchainBridge-AAX-vX.Y.Z-win64.zip` | `<sha256>` |
| macOS Apple Silicon (AAX for Pro Tools, Beta) | `SynchainBridge-AAX-vX.Y.Z-macos-arm64.zip` | `<sha256>` |

To verify: run `sha256sum -c SynchainBridge-*.zip.sha256` (on macOS: `shasum -a 256 -c …`).

**Signing:**
- The VST3 / AU builds are not code-signed. On Windows, click "More info → Run anyway" if SmartScreen asks. On macOS, run `xattr -dr com.apple.quarantine` on the installed plug-in.
- On Windows, the AAX build is PACE-signed, as Pro Tools requires, with a SHA-256 Authenticode signature and an RFC 3161 timestamp. The Authenticode certificate is self-signed, so "Properties → Digital Signatures" shows an untrusted publisher. This is expected and does not affect loading in Pro Tools.

Full steps are in `INSTALL.txt` (and `INSTALL-AAX.txt`) inside each zip and on https://www.synchain.ca/download.

Full changelog: [CHANGELOG.md](https://github.com/synchain-oss/synchain-bridge/blob/vX.Y.Z/CHANGELOG.md) ·
[vA.B.C...vX.Y.Z](https://github.com/synchain-oss/synchain-bridge/compare/vA.B.C...vX.Y.Z)

---

## Synchain Bridge vX.Y.Z（中文）

**<一句话：这一版对用户最重要的变化。>** <两三句展开：谁受影响、以前是什么现象、现在怎样；明确写出哪个平台不受影响。>

### 本版内容
- **<修复 / 新增 / 界面 / 加固 / 内部>（<平台或宿主，如有>）：** <与英文逐条对应；内部改动写「行为零变化」>
- **无协议变更**：与当前 Synchain 网页端兼容，无需迁移。
- 两个平台都先删除旧的 bundle 再放入新的（直接覆盖是合并，会留下旧版本的文件）：Windows 删除旧的 `Synchain Bridge.vst3` 文件夹后再复制；macOS 删除旧的 `.vst3` / `.component` 后再用 `ditto` 复制新的。见 `INSTALL.txt`。
- <跳过的版本号，例如「1.5.1、1.5.2 为内部测试包，未正式发布。」>

### 下载与校验
文件和 SHA-256 见上表。校验命令：`sha256sum -c SynchainBridge-*.zip.sha256`（macOS 用 `shasum -a 256 -c …`）。

**签名：**
- VST3 / AU 未做代码签名：Windows 上 SmartScreen 拦截时点「更多信息 → 仍要运行」；macOS 上对已安装的插件执行 `xattr -dr com.apple.quarantine`。
- AAX 按 Pro Tools 的要求做了 PACE 签名，Windows 签名为 SHA-256 并带 RFC 3161 时间戳。签名证书是自签名的，所以在「属性 → 数字签名」里会显示不受信任的签名者。这是预期现象，不影响 Pro Tools 加载。

完整步骤见 zip 里的 `INSTALL.txt`（与 `INSTALL-AAX.txt`）和 https://www.synchain.ca/zh/download 。
```

## 发 AAX 的版本另加两节

放在「What's in this release」之后、「Downloads」之前（中文段同样位置）。下面是 v1.6.0 的写法，平台、目录与限制按本版实际改：

```markdown
### Install the AAX (Pro Tools, Windows)
1. Quit Pro Tools.
2. If an older `Synchain Bridge.aaxplugin` folder is in `C:\Program Files\Common Files\Avid\Audio\Plug-Ins\`, delete it first. Copying over it merges the two and leaves old files behind.
3. Copy the new `Synchain Bridge.aaxplugin` folder into that directory. This may need administrator rights.
4. Restart Pro Tools and insert **Synchain Bridge**. With "organize plug-ins by category" turned on, it is under *Other*.

### Known limitations (Pro Tools, Beta)
- <one limitation per line, from README's "Pro Tools (AAX) known limitations">
```

```markdown
### 安装 AAX（Pro Tools，Windows）
1. 退出 Pro Tools。
2. 如果 `C:\Program Files\Common Files\Avid\Audio\Plug-Ins\` 里已有旧的 `Synchain Bridge.aaxplugin` 文件夹，先把它删掉。直接覆盖会把新旧文件合并，留下旧版本的文件。
3. 把新的 `Synchain Bridge.aaxplugin` 文件夹复制到这个目录，可能需要管理员权限。
4. 重启 Pro Tools，插入 **Synchain Bridge**。如果插件菜单按类别组织，它在 *Other* 下。

### 已知限制（Pro Tools，Beta）
- <与英文逐条对应>
```

「Signing」与「签名」里的 AAX 那一条按 Windows 签名件写（Authenticode、「属性 → 数字签名」都只存在于 Windows）；发 macOS AAX 时另写一条，按 `scripts/sign-aax-macos.sh` 的实际签名方式（codesign 身份、未经 Apple 公证、须去掉隔离属性）写，不要照抄 Windows 那条。

只发一个平台的 AAX 时，在「What's in this release」里写一句另一个平台的情况（v1.6.0：「**macOS AAX** is built but not released yet; it will follow after testing on real hardware.」）。补传 AAX 时（[release.md](release.md) §7.4），在正文里注明补发日期。

## 不发 AAX 的版本

- 资产表删掉两行 AAX；「Signing」只留 VST3 / AU 那一条，可以并回一段（v1.5.3 的写法）。
- 「Full steps」一句去掉 `INSTALL-AAX.txt`。
