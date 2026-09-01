# web/fonts — 离线子集字体

插件 WebView UI 用的字体，**离线打包**进 VST3（DAW 联网敏感，绝不运行期拉 Google Fonts）。
每个 `.woff2` 都是 **text= 子集**：只含 UI 实际用到的字形，四款合计 ~73KB。

| 文件 | @font-face family | 来源家族（上游） | 字重 | 用途（styles.css 变量） |
|---|---|---|---|---|
| `SpaceGrotesk.woff2` | `Space Grotesk` | Space Grotesk | 600 | `--ff-grotesk`：标题 / 数字 / CTA |
| `BridgeSans.woff2` | `Bridge Sans` | IBM Plex Sans（改名分发，见下） | 400 | `--ff-sans`：正文默认 |
| `BridgeMono.woff2` | `Bridge Mono` | IBM Plex Mono（改名分发，见下） | 400 | `--ff-mono`：标签 / 端口 / dBFS 等 |
| `NotoSansSC.woff2` | `Noto Sans SC` | Noto Sans SC | 400–700（可变） | 所有 CJK（经三条字体栈的 fallback 命中）；字重跟随元素：小标签 400，`立体声`/`开始传输` 等 600 |

拉丁三款子集含：可打印 ASCII + 法语重音（`À Â Ä Ç È É Ê Ë Î Ï Ô Œ Ù Û Ü` 及小写）+ `· — …`。
`NotoSansSC.woff2` 子集含 UI 用到的 40 个汉字（`在线离客户端电平采样率声道立体单延迟本地口主控音量开始传输停止正到浏览器待机等中`）。

## 为什么叫 `Bridge Sans` / `Bridge Mono`

这两个文件是**上游 IBM Plex Sans / IBM Plex Mono 的 text= 子集**。按 OFL-1.1：

- **子集化 = 修改**：产物是许可证意义上的 *Modified Version*。
- **§3 保留字体名（Reserved Font Name）**：IBM Plex 家族的保留字体名是 **`Plex`**，Modified Version
  **不得**在名字里使用它。§3 明确「This restriction only applies to the primary font name as
  presented to the users」——受限的是**呈现给用户的主字体名**，也就是字体 `name` 表里的家族名 /
  全名 / PostScript 名，**不只是文件名和 CSS family**。因此本仓两层都去掉了 `Plex`：
  - 外层：文件名 `BridgeSans.woff2` / `BridgeMono.woff2`，`@font-face` family `Bridge Sans` /
    `Bridge Mono`，`styles.css` 的字体栈同步改名；
  - 二进制内：`scripts/fetch_fonts.py` 的 `rename_font()` 下载后用 fontTools 重写 `name` 表的
    nameID 1/3/4/6/16/17，改名后这些**呈现名**记录不含 `Plex`（该函数带 fail-closed 断言，
    没改干净就不产出）。
- **§2 署名**：`name` 表里的 nameID 0（上游版权）与 14（OFL 许可证 URL）**逐字保留**，并补齐上游
  子集缺失的 nameID 13（OFL 许可证声明）；OFL 全文另由 `scripts/package.ps1` 放进发布 zip。
  这三条不参与上面的 RFN 断言——OFL 惯例的版权行本身就含 `with Reserved Font Name` 字样。
  上游家族、许可证与版权行见 [`THIRD-PARTY-NOTICES.md`](../../THIRD-PARTY-NOTICES.md)。
  （注：§4 是**禁止背书**条款，不是署名条款；此处早前编号写错，现更正为 §2。）
- 另两款不受影响：**Space Grotesk 无保留字体名**；**Noto Sans SC 的保留字体名是 `Source`**，
  分发名与 `name` 表里都不含它。故两者继续沿用上游家族名，二进制原样分发。

引用这些字体时请用**分发名**（`Bridge Sans` / `Bridge Mono`）；上游家族名只出现在「来源说明」语境里。

## 重新生成

字形有增改时（新增 UI 文案/语言）重新子集：脚本用 Google Fonts CSS2 `text=` 接口直接取子集 WOFF2，
再对 `BridgeSans` / `BridgeMono` 两款做 OFL §3 改名（需 `fontTools` + `brotli`）。

```bash
pip install "fonttools[woff]"      # 仅改名两款需要
python scripts/fetch_fonts.py <这个目录的绝对路径>
```

改字符集：编辑脚本里的 `LATIN` / `CJK` 常量后重跑，再确认 `styles.css` 的 `@font-face` 文件名一致。
改完复核 `name` 表已无保留字体名（同一断言已接进本地 gate 与 `compliance` workflow）：

```bash
python scripts/check-font-names.py
```

> 新增字体家族时，除了本表与 `THIRD-PARTY-NOTICES.md`，还要把它的 RFN 登记进
> `scripts/check-font-names.py` 的 `RESERVED`——目录里出现未登记的 `.woff2` 会直接让门禁失败。
> 注意：`Noto Sans SC` 只挂在 `--ff-sans/--ff-mono/--ff-grotesk` 三条栈的**拉丁字体之后**——
> 拉丁字体无 CJK 字形，浏览器按栈逐字回退到 Noto，保证离线确定性渲染（不依赖宿主系统 CJK 字体）。
