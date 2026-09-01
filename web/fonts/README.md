# web/fonts — 离线子集字体

插件 WebView UI 用的字体，**离线打包**进 VST3（DAW 联网敏感，绝不运行期拉 Google Fonts）。
每个 `.woff2` 都是 **text= 子集**：只含 UI 实际用到的字形，四款合计 ~78KB。

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
  **不得**在名字里使用它。因此本仓的分发名去掉了 `Plex`：文件名 `BridgeSans.woff2` / `BridgeMono.woff2`，
  `@font-face` family `Bridge Sans` / `Bridge Mono`，`styles.css` 的字体栈同步改名。
- **§4 署名**：woff2 二进制**未改动**，其 `name` 表里的上游版权与家族署名随产物原样分发；
  上游家族、许可证与版权行另见 [`THIRD-PARTY-NOTICES.md`](../../THIRD-PARTY-NOTICES.md)。
- 另两款不受影响：**Space Grotesk 无保留字体名**；**Noto Sans SC 的保留字体名是 `Source`**，
  分发名里不含它。故两者继续沿用上游家族名。

引用这些字体时请用**分发名**（`Bridge Sans` / `Bridge Mono`）；上游家族名只出现在「来源说明」语境里。

## 重新生成

字形有增改时（新增 UI 文案/语言）重新子集：脚本用 Google Fonts CSS2 `text=` 接口直接取子集 WOFF2，
无需本地装 `fonttools`。

```bash
python scripts/fetch_fonts.py <这个目录的绝对路径>
```

改字符集：编辑脚本里的 `LATIN` / `CJK` 常量后重跑，再确认 `styles.css` 的 `@font-face` 文件名一致。
> 注意：`Noto Sans SC` 只挂在 `--ff-sans/--ff-mono/--ff-grotesk` 三条栈的**拉丁字体之后**——
> 拉丁字体无 CJK 字形，浏览器按栈逐字回退到 Noto，保证离线确定性渲染（不依赖宿主系统 CJK 字体）。
