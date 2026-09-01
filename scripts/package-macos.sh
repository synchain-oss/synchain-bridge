#!/usr/bin/env bash
# Copyright (c) 2026 Synchain
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# scripts/package-macos.sh —— macOS 打包唯一真源(本地发版与 CI 共用同一脚本)。
# 与 scripts/package.ps1 并列:Windows 侧走 .ps1,macOS 侧走本脚本,两边互不改动、六条硬要求逐条对齐:
#   1. zip 名从 --version 算出来(SynchainBridge-VST3-AU-v$VERSION-macos-arm64.zip),绝不写字面量
#   2. 枚举 bundle 并断言恰好 1 个 .vst3 + 1 个 .component,名字精确,层级保住 Contents/
#   3. 生成 .sha256 独立资产 + $OUT_DIR/package-summary.md(version/zipFileName/sizeBytes/sha256/releaseDate)
#   4. 生成 INSTALL.txt(安装路径 + 不签名相关说明 + 精确到 tag 的源码声明)
#   5. 许可证与声明文件入 zip 根目录(LICENSE.txt / THIRD-PARTY-NOTICES.md / LICENSES/OFL-1.1.txt;
#      U2 = 不附 LICENSE-EXCEPTION.md,依赖 GPLv3 系统库例外默认解释)
#   6. 打包后断言:zip 内 bundle 层级 + 四个合规文件 + Contents/MacOS/* 仍是可执行位;缺一即退出 1
# mac 专属的两条:
#   - arm64-only 断言(U13:v1 不出 universal,也不出 x86_64)
#   - 一律用 ditto 拷贝与压缩:cp -r / zip -r 会丢符号链接与可执行位,
#     用户解压后拿到的是加载不了的死壳 —— 这是 mac 分发的第一杀手。
# 绝不在 workflow 里内联打包命令 —— 打包逻辑只在此处。
#
# 用法:
#   bash scripts/package-macos.sh [--version X.Y.Z] [--build-dir build] [--out-dir dist] [--dry-run]

set -euo pipefail

die() {
    echo "package-macos: $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
用法: package-macos.sh [选项]
  --version <X.Y.Z>   版本号(不带 v 前缀);留空则从 CMakeLists.txt 读唯一真源
  --build-dir <path>  构建目录(内含 .vst3 / .component bundle);相对路径按仓库根解析,默认 build
  --out-dir <path>    输出目录(zip / .sha256 / summary);相对路径按仓库根解析,默认 dist
  --dry-run           只打印计划并校验合规源文件存在,不产出任何产物(gate 用)
USAGE
}

VERSION=""
VERSION_GIVEN=0
BUILD_DIR="build"
OUT_DIR="dist"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version)   [ $# -ge 2 ] || die "--version 缺少取值";   VERSION="$2"; VERSION_GIVEN=1; shift 2 ;;
        --build-dir) [ $# -ge 2 ] || die "--build-dir 缺少取值"; BUILD_DIR="$2"; shift 2 ;;
        --out-dir)   [ $# -ge 2 ] || die "--out-dir 缺少取值";   OUT_DIR="$2";   shift 2 ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage >&2; die "unknown argument: $1" ;;
    esac
done

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

resolve_repo_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "$REPO_ROOT" "$1" ;;
    esac
}
BUILD_DIR="$(resolve_repo_path "$BUILD_DIR")"
OUT_DIR="$(resolve_repo_path "$OUT_DIR")"

# 1) Version:参数优先;**没传** --version 才从 CMakeLists.txt(版本唯一真源)回落。
#    传了 --version "" 属于调用方算版本失败(例如 CI 的 gate 没写出 outputs.version),
#    此时静默回落会产出版本号对不上的 zip —— 冒烟 tag v0.0.0-test 会产出名为
#    v1.5.0 的资产,而 sha256 复验照样过,错误一路带到 draft Release 才可能被人眼发现。
#    故「未传」与「传了空串」必须区分:后者直接 die。
#    容忍调用方直接把 tag 传进来,顺手去掉 v 前缀,免得 zip 名与源码 URL 出现 vv1.2.3。
if [ "$VERSION_GIVEN" -eq 1 ] && [ -z "$VERSION" ]; then
    die "--version 传入空串:调用方未算出版本号(不回落到 CMakeLists.txt,避免产出版本对不上的资产)"
fi
if [ -z "$VERSION" ]; then
    VERSION="$(sed -nE 's/.*project[[:space:]]*\([[:space:]]*[^[:space:]]+[[:space:]]+VERSION[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' \
        "$REPO_ROOT/CMakeLists.txt" | head -n 1)"
    [ -n "$VERSION" ] || die "cannot parse VERSION from CMakeLists.txt"
fi
VERSION="${VERSION#v}"

# 2) zip 名从 Version 算出来(硬要求 #1)
ZIP_NAME="SynchainBridge-VST3-AU-v$VERSION-macos-arm64.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
SHA_NAME="$ZIP_NAME.sha256"
SHA_PATH="$OUT_DIR/$SHA_NAME"
SUMMARY_PATH="$OUT_DIR/package-summary.md"

VST3_NAME="Synchain Bridge.vst3"
AU_NAME="Synchain Bridge.component"

# 3) 合规源文件清单(硬要求 #5)
LICENSE_SRC="$REPO_ROOT/LICENSE"                  # GPLv3 全文 → zip 内 LICENSE.txt
NOTICES_SRC="$REPO_ROOT/THIRD-PARTY-NOTICES.md"
OFL_SRC="$REPO_ROOT/LICENSES/OFL-1.1.txt"         # 字体子集嵌进二进制,OFL 全文须随分发

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DryRun] RepoRoot : $REPO_ROOT"
    echo "[DryRun] Version  : $VERSION"
    echo "[DryRun] BuildDir : $BUILD_DIR"
    echo "[DryRun] OutDir   : $OUT_DIR"
    echo "[DryRun] zip      : $ZIP_PATH"
    echo "[DryRun] sha256   : $SHA_PATH"
    for f in "$LICENSE_SRC" "$NOTICES_SRC" "$OFL_SRC"; do
        [ -f "$f" ] || die "compliance source missing: $f"
        echo "[DryRun] compliance ok : $f"
    done
    echo "[DryRun] OK —— 未创建任何产物。"
    exit 0
fi

for f in "$LICENSE_SRC" "$NOTICES_SRC" "$OFL_SRC"; do
    [ -f "$f" ] || die "compliance source missing: $f"
done
[ -d "$BUILD_DIR" ] || die "build dir not found: $BUILD_DIR"

# 4) 枚举 bundle 目录并断言恰好 1 个(硬要求 #2)。
#    BUNDLE_PATH 用全局变量回传:放进 $( ) 里 die 只会杀子 shell。
BUNDLE_PATH=""
require_single_bundle() {
    local ext="$1"
    local want="$2"
    local n base
    n="$(find "$BUILD_DIR" -type d -name "*.$ext" | wc -l | tr -d '[:space:]')"
    [ "$n" = "1" ] || die "expected exactly 1 .$ext bundle under '$BUILD_DIR', found $n"
    # 与 ci.yml 同口径用 `-print -quit`:`find | head -n 1` 在 pipefail 下会因 SIGPIPE(141)
    # 被 set -e 杀掉脚本(上面 n=1 的断言已保证只有一个匹配,但口径不该两处不一致)。
    BUNDLE_PATH="$(find "$BUILD_DIR" -type d -name "*.$ext" -print -quit)"
    base="$(basename "$BUNDLE_PATH")"
    [ "$base" = "$want" ] || die "unexpected bundle name '$base' (expected '$want')"
    [ -d "$BUNDLE_PATH/Contents" ] || die "bundle '$BUNDLE_PATH' missing Contents/ hierarchy"
    [ -d "$BUNDLE_PATH/Contents/MacOS" ] || die "bundle '$BUNDLE_PATH' missing Contents/MacOS/"
}

require_single_bundle vst3 "$VST3_NAME"
VST3_BUNDLE="$BUNDLE_PATH"
require_single_bundle component "$AU_NAME"
AU_BUNDLE="$BUNDLE_PATH"

# 5) 架构断言:必须是 arm64 单架构。带 x86_64 的胖二进制在此直接失败,
#    否则 arm64-only 的分发承诺(和 INSTALL.txt 里的说明)就成了假话。
assert_arm64_only() {
    local archs
    archs="$(file "$1"/Contents/MacOS/*)"
    printf '%s\n' "$archs"
    printf '%s\n' "$archs" | grep -q 'arm64' || die "'$1' is not arm64"
    ! printf '%s\n' "$archs" | grep -q 'x86_64' || die "'$1' contains an x86_64 slice; v1 ships arm64-only"
}
assert_arm64_only "$VST3_BUNDLE"
assert_arm64_only "$AU_BUNDLE"

# 6) 组装 staging 目录:bundle 一律 ditto(保住符号链接 / 可执行位 / 扩展属性)
STAGING="$OUT_DIR/_staging"
rm -rf "$STAGING"
mkdir -p "$OUT_DIR" "$STAGING/LICENSES"

ditto "$VST3_BUNDLE" "$STAGING/$VST3_NAME"
ditto "$AU_BUNDLE"   "$STAGING/$AU_NAME"
cp "$LICENSE_SRC" "$STAGING/LICENSE.txt"
cp "$NOTICES_SRC" "$STAGING/THIRD-PARTY-NOTICES.md"
cp "$OFL_SRC"     "$STAGING/LICENSES/OFL-1.1.txt"

# 7) INSTALL.txt(硬要求 #4;含精确到 tag 的源码获取声明)
cat > "$STAGING/INSTALL.txt" <<EOF
Synchain Bridge for macOS —— 安装说明
=====================================

版本:$VERSION

先读这一段:本包只有 Apple Silicon(arm64)版
------------------------------------------
包内 VST3 / AU 只含 arm64 一个架构,不含 x86_64。
如果宿主 DAW 是 Intel 版,或虽在 Apple Silicon 上、但被勾了「使用 Rosetta 打开」,
宿主进程就是 x86_64,插件不会出现在插件列表里 —— 这不是装错了,是架构不匹配。
处理:在「访达」里选中 DAW → 显示简介 → 取消勾选「使用 Rosetta 打开」,再以原生 arm64 重开 DAW。

安装路径
--------
把压缩包内的两个 bundle 整体复制到(全局安装,所有用户可见):

  VST3:  /Library/Audio/Plug-Ins/VST3/$VST3_NAME
  AU:    /Library/Audio/Plug-Ins/Components/$AU_NAME

/Library 下这两个目录属 root:admin,复制进去需要管理员授权(访达会弹密码框;
命令行则要 sudo)。只装给当前用户就换成家目录下的同名位置:

  VST3:  ~/Library/Audio/Plug-Ins/VST3/$VST3_NAME
  AU:    ~/Library/Audio/Plug-Ins/Components/$AU_NAME

家目录这条路径归你自己所有,复制与下面的 xattr 都不需要 sudo,宿主同样能扫到。

首次加载:去掉隔离属性(U13:v1 不签名、不公证)
--------------------------------------------
本插件未签名也未公证。浏览器下载的压缩包会被打上 com.apple.quarantine,
宿主会以「无法验证开发者」为由拒绝加载。安装到**全局**路径后,在「终端」各执行一条
(路径属 root,不加 sudo 会得到 Operation not permitted):

  sudo xattr -dr com.apple.quarantine "/Library/Audio/Plug-Ins/VST3/$VST3_NAME"
  sudo xattr -dr com.apple.quarantine "/Library/Audio/Plug-Ins/Components/$AU_NAME"

装在**家目录**则去掉 sudo、把路径换成 ~/Library/... 下的对应位置:

  xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/VST3/"$VST3_NAME"
  xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/Components/"$AU_NAME"

AU 没出现在宿主的插件列表里
---------------------------
macOS 的 AU 组件缓存不会自动刷新。执行下面一条强制重扫,再重启宿主:

  killall -9 AudioComponentRegistrar

浏览器
------
接收端是 Synchain 网页应用里项目的 Creative Space 页面。
macOS 上请用 Chrome / Edge / Firefox 打开;Safari 不在验证矩阵内,不建议使用。
浏览器必须与插件在同一台机器上 —— 桥 #2 只监听本机回环地址。

源码获取
--------
Complete corresponding source for this exact build: https://github.com/synchain-oss/synchain-bridge/tree/v$VERSION
EOF

# 8) 压缩:ditto -c -k(不加 --keepParent,staging 内容平铺到 zip 根,
#    与 package.ps1 的 includeBaseDirectory=false 一致)。
#    --norsrc --noextattr:插件 bundle 不需要资源叉。曾用的 --sequesterRsrc 的定义就是
#    把资源叉/扩展属性收进 zip 的 __MACOSX/ 目录 —— 只要产物带任何 xattr
#    (com.apple.provenance / FinderInfo 等;CI 里 pluginval / auval 已 dlopen 过 bundle,
#    必然带),zip 里就会多出 __MACOSX/<bundle>/Contents/MacOS/._<exe> 这类条目,
#    权限恒为 -rw-r--r-- 且同样匹配下面第 9 步的可执行位筛选,断言必然假失败;
#    发给用户的 zip 也会平白塞一堆 __MACOSX 垃圾。
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --noextattr "$STAGING" "$ZIP_PATH"

# 9) 打包后断言(硬要求 #6):层级 + 四个合规文件 + 可执行位;缺一即退出 1。
#    前缀/全名比对用 awk 做字面匹配,避免 bundle 名里的 '.' 被当成正则通配。
NAMES="$(unzip -Z1 "$ZIP_PATH")"
for b in "$VST3_NAME" "$AU_NAME"; do
    printf '%s\n' "$NAMES" | awk -v p="$b/Contents/" 'index($0, p) == 1 { hit = 1 } END { exit !hit }' \
        || die "zip assertion failed: no entries under '$b/Contents/'"
done
for r in 'LICENSE.txt' 'THIRD-PARTY-NOTICES.md' 'LICENSES/OFL-1.1.txt' 'INSTALL.txt'; do
    printf '%s\n' "$NAMES" | awk -v f="$r" '$0 == f { hit = 1 } END { exit !hit }' \
        || die "zip assertion failed: missing '$r'"
done

# 可执行位:只挑 Contents/MacOS/ 下的**文件**条目 —— 目录条目本身是 d 开头,拿它比会误报。
# 显式排除 __MACOSX/:上面已改用 --norsrc --noextattr 从源头不产生这些条目,这里再挡一道,
# 免得将来有人把 ditto 参数改回 --sequesterRsrc 就静默退化成必然假失败。
MACHO="$(unzip -Z "$ZIP_PATH" | grep -v '__MACOSX/' | grep -E '/Contents/MacOS/[^[:space:]]' || true)"
[ -n "$MACHO" ] || die "zip assertion failed: no Contents/MacOS/ file entries"
# 首字符放行 `-`(普通文件)与 `l`(符号链接):bundle 里出现指向可执行体的 symlink 时
# unzip -Z 打的是 `lrwxrwxrwx`,只认 `^-rwx` 会把它当成丢了可执行位而假失败(与 ci.yml 同口径)。
NOT_EXEC="$(printf '%s\n' "$MACHO" | grep -vE '^[-l]rwx' || true)"
[ -z "$NOT_EXEC" ] || die "zip assertion failed: exec bit lost on:
$NOT_EXEC"

rm -rf "$STAGING"

# 10) .sha256 独立资产 + package-summary.md(硬要求 #3)。
#     .sha256 的格式与 package.ps1 逐字一致:"<小写 hash><两个空格><zip 文件名>"。
HASH="$(shasum -a 256 "$ZIP_PATH" | awk '{ print $1 }')"
printf '%s  %s\n' "$HASH" "$ZIP_NAME" > "$SHA_PATH"

SIZE_BYTES="$(wc -c < "$ZIP_PATH" | tr -d '[:space:]')"
RELEASE_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# summary 以空行分段追加:同一个 OutDir 下可能已有别的平台(package.ps1)或本脚本上一次运行写的段落。
# 同名 zip 的旧段落先删掉,避免重复跑脚本时越堆越长 —— 但**只删同名的那一条**。
#
# 切段一律按记录首行 `version:` 切,**不能按空行切**:package.ps1 用 Set-Content 写的是紧贴的 5 行、
# 段间没有空行,本脚本首次追加时也不会补空行。若用 awk 的段落模式(RS=''),整个文件会被当成**一条**
# 记录,只要里面含本次的 zipFileName 就连 Windows 的段落、历史版本的段落一起删光(实测:文件被清空)。
# 同时匹配改为 `zipFileName:` 整行逐字相等,不再用子串包含。首条记录之前的内容(将来若加表头)原样保留。
if [ -f "$SUMMARY_PATH" ]; then
    awk -v z="zipFileName: $ZIP_NAME" '
        NF == 0 { next }                                    # 空行只是分隔符,重排时统一重新生成
        /^version:[[:space:]]/ {                            # 记录首行:先结算上一条
            if (started && !drop) printf "%s\n", rec
            rec = ""; drop = 0; started = 1
        }
        !started { print; next }                            # 首条记录之前的内容原样透传
        { rec = rec $0 "\n"; if ($0 == z) drop = 1 }
        END { if (started && !drop) printf "%s\n", rec }
    ' "$SUMMARY_PATH" > "$SUMMARY_PATH.tmp"
    mv "$SUMMARY_PATH.tmp" "$SUMMARY_PATH"
fi
cat >> "$SUMMARY_PATH" <<EOF
version: $VERSION
zipFileName: $ZIP_NAME
sizeBytes: $SIZE_BYTES
sha256: $HASH
releaseDate: $RELEASE_DATE
EOF

echo "Packaged: $ZIP_PATH ($SIZE_BYTES bytes)"
echo "SHA256:   $HASH"
