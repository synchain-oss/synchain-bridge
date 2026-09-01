# -*- coding: utf-8 -*-
"""生成 web/fonts/ 下的离线子集 WOFF2。

用 Google Fonts CSS2 `text=` 接口：Google 直接返回按传入字符子集好的 WOFF2，
无需本地安装 fonttools/brotli。字形有增改时改下面 LATIN / CJK 常量后重跑本脚本，
再确认 web/styles.css 的 @font-face 文件名一致即可。

输出名与来源家族名不一定相同：子集化 = 对字体的修改（OFL-1.1 意义上的 Modified Version），
而 OFL-1.1 §3 禁止 Modified Version 使用上游的保留字体名（Reserved Font Name）。
故 IBM Plex Sans / IBM Plex Mono 的子集以 BridgeSans.woff2 / BridgeMono.woff2 输出，
CSS 里的 family 相应为 'Bridge Sans' / 'Bridge Mono'（下方 FONTS 表左列 = 分发名，
中列 = 上游来源家族，取子集仍从上游家族取）。Space Grotesk 无保留字体名、
Noto Sans SC 的保留字体名为 "Source"，两者分发名保持与来源一致。详见 THIRD-PARTY-NOTICES.md。

用法:
    python scripts/fetch_fonts.py [输出目录]
    # 输出目录默认为脚本同级 ../web/fonts
"""
import os, sys, re, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "web", "fonts")

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

# ---- 字符集 ----------------------------------------------------------------
# 拉丁：可打印 ASCII + 法语重音 + 用到的符号（· — …）
LATIN = ("".join(chr(c) for c in range(0x20, 0x7F))
         + "ÀÂÄÇÈÉÊËÎÏÔŒÙÛÜàâäçèéêëîïôœùûü"
         + "·—…")
# CJK：UI 实际用到的 40 个汉字（zh 字典 + 静态 HTML + 语言按钮 中）
CJK = "在线离客户端电平采样率声道立体单延迟本地口主控音量开始传输停止正到浏览器待机等中"

FONTS = [
    # (输出文件名=分发名, Google 上游家族+字重, 子集字符)
    ("SpaceGrotesk.woff2", "Space Grotesk:wght@600", LATIN),
    # 下面两行的分发名按 OFL-1.1 §3 保留字体名改名（见模块顶部说明），来源家族不变
    ("BridgeSans.woff2",   "IBM Plex Sans:wght@400", LATIN),
    ("BridgeMono.woff2",   "IBM Plex Mono:wght@400", LATIN),
    # 可变字重 400..700：CJK 字重跟随元素（小标签 400，立体声/开始传输 600 加粗）
    ("NotoSansSC.woff2",   "Noto Sans SC:wght@400..700",  CJK + LATIN),
]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def main():
    out = os.path.abspath(OUT)
    os.makedirs(out, exist_ok=True)
    for fname, family, text in FONTS:
        q = {"family": family, "display": "swap", "text": text}
        url = "https://fonts.googleapis.com/css2?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote)
        css = fetch(url).decode("utf-8")
        m = re.search(r"src:\s*url\((https://[^)]+)\)", css)
        if not m:
            print("!! CSS 里没找到 woff2 url:", family)
            print(css[:800])
            sys.exit(2)
        data = fetch(m.group(1))
        with open(os.path.join(out, fname), "wb") as f:
            f.write(data)
        print("OK %-20s %6d bytes" % (fname, len(data)))
    print("-> ", out)


if __name__ == "__main__":
    main()
