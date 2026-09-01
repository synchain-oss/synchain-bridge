# -*- coding: utf-8 -*-
"""生成 web/fonts/ 下的离线子集 WOFF2。

用 Google Fonts CSS2 `text=` 接口：Google 直接返回按传入字符子集好的 WOFF2。
字形有增改时改下面 LATIN / CJK 常量后重跑本脚本，再确认 web/styles.css 的
@font-face 文件名一致即可。

输出名与来源家族名不一定相同：子集化 = 对字体的修改（OFL-1.1 意义上的 Modified Version），
而 OFL-1.1 §3 禁止 Modified Version 使用上游的保留字体名（Reserved Font Name）——
且该限制针对的是**呈现给用户的主字体名**，即字体 `name` 表里的家族名 / 全名 / PostScript 名，
不只是文件名和 CSS family。故 IBM Plex Sans / IBM Plex Mono 的子集除了以
BridgeSans.woff2 / BridgeMono.woff2 输出、CSS family 用 'Bridge Sans' / 'Bridge Mono' 之外，
**下载后还要用 fontTools 重写 name 表**（见 RENAME 表与 rename_font()）。
Space Grotesk 无保留字体名、Noto Sans SC 的保留字体名为 "Source" 且分发名不含它，
这两款不改名、二进制原样落盘。详见 THIRD-PARTY-NOTICES.md。

依赖:
    改名两款需要 fontTools + brotli（`pip install "fonttools[woff]"`）；
    其余两款只用标准库。

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
    # 下面两行的分发名按 OFL-1.1 §3 保留字体名改名（见模块顶部说明与 RENAME 表），来源家族不变
    ("BridgeSans.woff2",   "IBM Plex Sans:wght@400", LATIN),
    ("BridgeMono.woff2",   "IBM Plex Mono:wght@400", LATIN),
    # 可变字重 400..700：CJK 字重跟随元素（小标签 400，立体声/开始传输 600 加粗）
    ("NotoSansSC.woff2",   "Noto Sans SC:wght@400..700",  CJK + LATIN),
]

# ---- OFL-1.1 §3 改名 --------------------------------------------------------
# 只有上游带 RFN 且分发名要去掉 RFN 的家族才进这张表。
# 输出文件名 -> (分发家族名, 分发 PostScript 名, 上游保留字体名 RFN)
RENAME = {
    "BridgeSans.woff2": ("Bridge Sans", "BridgeSans-Regular", "Plex"),
    "BridgeMono.woff2": ("Bridge Mono", "BridgeMono-Regular", "Plex"),
}

# OFL-1.1 §2 要求「每份拷贝都包含上述版权声明与本许可证」。上游子集的 name 表里
# 有 nameID 0（版权）与 14（许可证 URL）但缺 13（许可证声明），改名时一并补齐；
# 版权（0）与许可证（13/14）三条**永不改写**，随分发原样保留。
OFL_LICENSE_DESC = (
    "This Font Software is licensed under the SIL Open Font License, Version 1.1. "
    "This license is available with a FAQ at https://scripts.sil.org/OFL"
)
# 呈现给用户的主字体名相关记录：家族 / 唯一 ID / 全名 / PostScript 名 / 排版家族与子族
NAME_IDS_FAMILY, NAME_IDS_KEEP = (1, 3, 4, 6, 16, 17), (0, 13, 14)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def _unique_id(existing, ps_name):
    """nameID 3 惯例是 "<version>;<vendor>;<postscript name>"，只换后两段。"""
    version = existing.split(";")[0].strip() if existing else ""
    return ";".join(p for p in (version, "Synchain", ps_name) if p)


def rename_font(path, family, ps_name, reserved):
    """就地重写子集 woff2 的 `name` 表，去掉上游保留字体名（OFL-1.1 §3）。

    §3 限制的是「呈现给用户的主字体名」，故必须改 name 表，只改文件名 / CSS family 不够。
    §2 要求的版权声明与许可证（nameID 0/13/14）原样保留并补齐 13。
    """
    from fontTools.ttLib import TTFont  # 仅改名家族需要；见模块顶部「依赖」

    font = TTFont(path)
    name = font["name"]
    # §2 的版权 / 许可证记录：改名前后必须逐字不变（下面 keep_before/keep_after 对比）
    keep_before = {(r.nameID, r.platformID, r.platEncID, r.langID): r.toUnicode()
                   for r in name.names if r.nameID in NAME_IDS_KEEP}
    # name 记录按 (platformID, platEncID, langID) 分槽，逐槽改，Mac/Windows 记录都覆盖到
    for slot in sorted({(r.platformID, r.platEncID, r.langID) for r in name.names}):
        def current(nid, default=""):
            rec = name.getName(nid, *slot)
            return rec.toUnicode() if rec is not None else default

        subfamily = current(2, "Regular")
        values = {
            1: family,
            3: _unique_id(current(3), ps_name),
            4: "%s %s" % (family, subfamily),
            6: ps_name,
            16: family,
            17: subfamily,
        }
        for nid in NAME_IDS_FAMILY:
            if name.getName(nid, *slot) is not None:
                name.setName(values[nid], nid, *slot)
        if name.getName(13, *slot) is None:
            name.setName(OFL_LICENSE_DESC, 13, *slot)

    stray = sorted({r.toUnicode() for r in name.names if reserved in r.toUnicode()})
    if stray:  # fail-closed：改名没改干净就不要产出一个仍带 RFN 的分发物
        raise SystemExit("!! %s 的 name 表仍含保留字体名 %r: %s" % (path, reserved, stray))
    keep_after = {(r.nameID, r.platformID, r.platEncID, r.langID): r.toUnicode()
                  for r in name.names if r.nameID in NAME_IDS_KEEP}
    if any(keep_after.get(k) != v for k, v in keep_before.items()):  # §2 署名被动过 = 不合规
        raise SystemExit("!! %s 的版权/许可证记录(nameID %s)被改动" % (path, NAME_IDS_KEEP))
    font.save(path)


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
        path = os.path.join(out, fname)
        with open(path, "wb") as f:
            f.write(data)
        note = ""
        if fname in RENAME:
            rename_font(path, *RENAME[fname])
            note = "  (name 表已按 OFL §3 改名为 %r)" % RENAME[fname][0]
        print("OK %-20s %6d bytes%s" % (fname, os.path.getsize(path), note))
    print("-> ", out)


if __name__ == "__main__":
    main()
