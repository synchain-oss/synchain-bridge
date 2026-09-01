# -*- coding: utf-8 -*-
"""断言 web/fonts/ 下分发的 woff2 `name` 表不含上游保留字体名(OFL-1.1 §3)。

§3 限制的是「呈现给用户的主字体名」——字体 `name` 表里的家族名 / 唯一 ID / 全名 /
PostScript 名 / 排版家族与子族(nameID 1/3/4/6/16/17),不只是文件名与 CSS family。
`scripts/fetch_fonts.py` 的 rename_font() 在生成期已做同样的断言;本脚本把它搬进门禁,
让「重新生成字体」与「审查分发物」两条路都被守住:woff2 是 brotli 压缩的,grep 二进制
不命中**不等于**名字已清除,只有解出 name 表逐条比对才算证据。

nameID 0(版权) / 13(许可证声明) / 14(许可证 URL)**不参与断言**:OFL 惯例的版权行本身
就写着 "with Reserved Font Name ...",那是 §2 要求逐字保留的署名,不是违规残留。

依赖:
    fontTools + brotli(woff2 解压必需):`pip install fonttools brotli`

用法:
    python scripts/check-font-names.py [字体目录]
    # 字体目录默认为脚本同级 ../web/fonts;命中即打印详情并以非零码退出
"""
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "web", "fonts")

# 分发文件 -> 上游保留字体名(RFN)。None = 上游版权行不含 "with Reserved Font Name",
# 名字不受 §3 限制。逐家族核验依据见 THIRD-PARTY-NOTICES.md 的字体表末列。
RESERVED = {
    "SpaceGrotesk.woff2": None,      # Space Grotesk:无 RFN,二进制原样分发
    "BridgeSans.woff2":   "Plex",    # IBM Plex Sans 子集,已按 §3 改名
    "BridgeMono.woff2":   "Plex",    # IBM Plex Mono 子集,已按 §3 改名
    "NotoSansSC.woff2":   "Source",  # 分发名与 name 表本就不含它;断言守住不回归
}

# 与 fetch_fonts.py 的 NAME_IDS_FAMILY / NAME_IDS_KEEP 同义(改一处要同步另一处)
PRESENTED_IDS = (1, 3, 4, 6, 16, 17)
KEEP_IDS = (0, 13, 14)


def main():
    try:
        from fontTools.ttLib import TTFont
        import brotli  # noqa: F401 —— 缺它时 TTFont 打开 woff2 才报错,提前暴露
    except ImportError as exc:
        sys.exit("!! 依赖缺失(%s):pip install fonttools brotli" % exc)

    font_dir = os.path.abspath(FONT_DIR)
    ids = "/".join(str(i) for i in PRESENTED_IDS)
    problems, hits = [], []

    # 目录里出现未登记的字体 = 覆盖缺口(新增家族没登记 RFN),同样 fail-closed。
    present = {os.path.basename(p) for p in glob.glob(os.path.join(font_dir, "*.woff2"))}
    for extra in sorted(present - set(RESERVED)):
        problems.append("%s 未登记 RFN(补进本脚本的 RESERVED 与 THIRD-PARTY-NOTICES.md)" % extra)

    for fname in sorted(RESERVED):
        path = os.path.join(font_dir, fname)
        if fname not in present:
            problems.append("%s 不存在于 %s" % (fname, font_dir))
            continue
        reserved = RESERVED[fname]
        if reserved is None:
            print("SKIP %-20s 上游无保留字体名" % fname)
            continue
        needle = reserved.casefold()
        for r in TTFont(path)["name"].names:
            if r.nameID in KEEP_IDS or r.nameID not in PRESENTED_IDS:
                continue
            value = r.toUnicode()
            if needle in value.casefold():  # 双侧 casefold:"plex"/"PLEX" 同样命中
                hits.append((fname, r.nameID, r.platformID, r.platEncID, r.langID, reserved, value))
        print("OK   %-20s nameID %s 均不含 %r" % (fname, ids, reserved))

    for fname, nid, pid, eid, lid, reserved, value in hits:
        problems.append("%s nameID %d (platform %d/%d lang %d) 仍含保留字体名 %r: %r"
                        % (fname, nid, pid, eid, lid, reserved, value))

    if problems:
        print("")
        for p in problems:
            print("!! " + p)
        sys.exit("字体 name 表 RFN 断言失败(%d 项);重新生成见 web/fonts/README.md" % len(problems))
    print("-> %s:呈现名(nameID %s)全部通过 OFL-1.1 §3 断言" % (font_dir, ids))


if __name__ == "__main__":
    main()
