#!/usr/bin/env bash
# Copyright (c) 2026 Synchain
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# scripts/package-aax-macos.sh —— AAX(Avid Pro Tools)macOS 打包唯一真源(本机签名流程与 CI 共用同一脚本)。
# 与 scripts/package-aax.ps1 并列:Windows 侧走 .ps1,macOS 侧走本脚本;两者都与 VST3/AU 的
# package.ps1 / package-macos.sh 互不改动(那条发版链路已验过,AAX 的新组合不带进去)。硬要求逐条对齐 .ps1:
#   1. 版本:--version 优先;没传才从 CMakeLists.txt 回落(回落逻辑逐字照 package-macos.sh 第 1 步,传了空串就 die);
#      --prerelease-tag 与 --version 互斥,给了就是 <CMake VERSION>-<tag>;结果必须匹配
#      ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$(与 release.yml 的 tag 校验去掉 v 之后同口径)
#   2. zip 名由 mode + 版本算出,绝不写字面量:
#        signed   → SynchainBridge-AAX-v$VERSION-macos-arm64.zip
#        unsigned → SynchainBridge-AAX-v$VERSION-macos-arm64-UNSIGNED.zip
#   3. bundle 定位:--bundle-path 显式给出;否则在 --build-dir 下 find 恰好 1 个 *.aaxplugin 目录;
#      名字必须是 'Synchain Bridge.aaxplugin',Contents/Info.plist 存在,Contents/MacOS/Synchain Bridge 存在且可执行
#   4. arm64-only(逐字复用 package-macos.sh 的 file 断言);CFBundleIdentifier 必须等于 CMakeLists.txt 的 BUNDLE_ID(防打错包)
#   5. mode 断言(在建 staging 之前):signed 要求 codesign --verify --strict 通过、codesign -dv 有 Authority= 且不是
#      Signature=adhoc、Contents/_CodeSignature/CodeResources 存在 —— 链接器在 arm64 上自动加的 ad-hoc 签名
#      没有 CodeResources,所以未签名 bundle 必然被拒(CI 的反向断言靠的就是这一条)。unsigned 不查签名
#   6. 写 INSTALL-AAX.txt(不叫 INSTALL.txt:与 VST3/AU 包解压到同一目录时互不覆盖)
#   7. 合规文件入 zip 根目录,与现有包同一组:LICENSE.txt / THIRD-PARTY-NOTICES.md / LICENSES/OFL-1.1.txt
#   8. 全程 ditto;压缩用 ditto -c -k --norsrc --noextattr(理由同 package-macos.sh 第 8 步;签名封存在 Mach-O 与
#      CodeResources 里,去掉 xattr 不影响签名,signed 模式的回读验证兜底);打包后断言 bundle 层级 + 四个合规文件 +
#      Contents/MacOS/* 仍是可执行位
#   9. 仅 signed:zip 内必须有 _CodeSignature/CodeResources;再 ditto -x -k 解到 mktemp -d 回读,
#      对解出的 bundle 重做第 5 条断言并比对主体可执行文件的 SHA256 与源相等。
#      从建 staging 起任何失败都删掉本次的 zip / .sha256:失败路径上绝不留下发行名 zip
#  10. .sha256 与 package-macos.sh 逐字同口径:"<小写 hash><两个空格><zip 文件名>" + LF
#  11. package-summary.md 与 package-macos.sh 第 10 步逐字同构(按段追加、同名段去重)——
#      **改一处必须改全部四处**(package.ps1 / package-macos.sh / package-aax.ps1 / 本脚本)
#  12. --dry-run 只打印计划并校验合规源文件存在;本脚本**不调用 wraptool、不碰任何凭据**(CI 可跑)
# 绝不在 workflow 里内联打包命令 —— AAX 打包逻辑只在此处。
#
# 用法:
#   bash scripts/package-aax-macos.sh --mode unsigned|signed [--version X.Y.Z | --prerelease-tag ci.<sha7>]
#        [--source-ref vX.Y.Z|<40-hex>] [--build-dir build | --bundle-path <.aaxplugin>] [--out-dir dist/aax] [--dry-run]

set -euo pipefail

die() {
    echo "package-aax-macos: $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
用法: package-aax-macos.sh --mode unsigned|signed [选项]
  --mode <m>              必填:unsigned(产出 -UNSIGNED 件)或 signed(只接受已签名 bundle,产出发行名)
  --version <X.Y.Z>       版本号(不带 v 前缀);与 --prerelease-tag 互斥;都不给则从 CMakeLists.txt 读唯一真源
  --prerelease-tag <tag>  例:ci.fe933da → 版本 = <CMake VERSION>-ci.fe933da;此时必须同时给 --source-ref
  --source-ref <ref>      INSTALL-AAX.txt 源码链接的 ref(tag vX.Y.Z[-pre] 或 40 位 commit);默认 v<版本>
  --build-dir <path>      构建目录(内含 .aaxplugin bundle);相对路径按仓库根解析,默认 build
  --bundle-path <path>    显式 .aaxplugin 目录(签名流程用);给了就忽略 --build-dir
  --out-dir <path>        输出目录(zip / .sha256 / summary);相对路径按仓库根解析,默认 dist/aax
  --dry-run               只打印计划并校验合规源文件存在,不产出任何产物
USAGE
}

MODE=""
VERSION=""
VERSION_GIVEN=0
PRE_TAG=""
PRE_GIVEN=0
SOURCE_REF=""
REF_GIVEN=0
BUILD_DIR="build"
BUNDLE_ARG=""
OUT_DIR="dist/aax"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)           [ $# -ge 2 ] || die "--mode 缺少取值";           MODE="$2"; shift 2 ;;
        --version)        [ $# -ge 2 ] || die "--version 缺少取值";        VERSION="$2"; VERSION_GIVEN=1; shift 2 ;;
        --prerelease-tag) [ $# -ge 2 ] || die "--prerelease-tag 缺少取值"; PRE_TAG="$2"; PRE_GIVEN=1; shift 2 ;;
        --source-ref)     [ $# -ge 2 ] || die "--source-ref 缺少取值";     SOURCE_REF="$2"; REF_GIVEN=1; shift 2 ;;
        --build-dir)      [ $# -ge 2 ] || die "--build-dir 缺少取值";      BUILD_DIR="$2"; shift 2 ;;
        --bundle-path)    [ $# -ge 2 ] || die "--bundle-path 缺少取值";    BUNDLE_ARG="$2"; shift 2 ;;
        --out-dir)        [ $# -ge 2 ] || die "--out-dir 缺少取值";        OUT_DIR="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; die "unknown argument: $1" ;;
    esac
done

# mode 无默认值,强制显式;只认小写两种拼写(与 .ps1 的大小写敏感 ValidateSet 同一纪律)
case "$MODE" in
    unsigned|signed) ;;
    "") usage >&2; die "--mode unsigned|signed is required" ;;
    *)  die "invalid --mode '$MODE' (expected unsigned|signed)" ;;
esac

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

# 1) Version(硬要求 #1)。「未传」与「传了空串」必须区分:后者是调用方算版本失败,静默回落会产出版本号
#    对不上的资产(理由详见 package-macos.sh 第 1 步)。--prerelease-tag / --source-ref 同理。
if [ "$VERSION_GIVEN" -eq 1 ] && [ "$PRE_GIVEN" -eq 1 ]; then die "--version and --prerelease-tag are mutually exclusive"; fi
if [ "$VERSION_GIVEN" -eq 1 ] && [ -z "$VERSION" ]; then
    die "--version 传入空串:调用方未算出版本号(不回落到 CMakeLists.txt,避免产出版本对不上的资产)"
fi
if [ "$PRE_GIVEN" -eq 1 ] && [ -z "$PRE_TAG" ]; then die "--prerelease-tag 传入空串"; fi
if [ "$REF_GIVEN" -eq 1 ] && [ -z "$SOURCE_REF" ]; then die "--source-ref 传入空串"; fi
if [ -z "$VERSION" ]; then
    # 以下两行与 package-macos.sh 第 1 步逐字相同(注释见该处):行首锚 + 先丢注释行 + `/re/{s//\1/p;q;}`,GNU/BSD sed 两端都通
    version_re='^[[:space:]]*project[[:space:]]*\([[:space:]]*[^[:space:]]+[[:space:]]+VERSION[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*'
    VERSION="$(sed -nE '/^[[:space:]]*#/d; /'"$version_re"'/{s//\1/p;q;}' "$REPO_ROOT/CMakeLists.txt")"
    [ -n "$VERSION" ] || die "cannot parse VERSION from CMakeLists.txt"
    if [ "$PRE_GIVEN" -eq 1 ]; then
        pre_re='^[0-9A-Za-z][0-9A-Za-z.-]*$'
        [[ "$PRE_TAG" =~ $pre_re ]] || die "invalid --prerelease-tag '$PRE_TAG'"
        VERSION="$VERSION-$PRE_TAG"
    fi
fi
VERSION="${VERSION#v}"
semver_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'
[[ "$VERSION" =~ $semver_re ]] || die "invalid version '$VERSION' (expected X.Y.Z or X.Y.Z-prerelease, no 'v' prefix)"

# SourceRef:正式版默认指向 tag v$VERSION;--prerelease-tag 的构建没有对应 tag,默认值会是死链 —— 必须显式给 commit
if [ "$PRE_GIVEN" -eq 1 ] && [ "$REF_GIVEN" -eq 0 ]; then
    die "--prerelease-tag builds have no matching tag: pass --source-ref <40-hex commit> so INSTALL-AAX.txt points at real source"
fi
[ -n "$SOURCE_REF" ] || SOURCE_REF="v$VERSION"
ref_re='^(v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?|[0-9a-f]{40})$'
[[ "$SOURCE_REF" =~ $ref_re ]] || die "invalid --source-ref '$SOURCE_REF' (expected a tag vX.Y.Z[-pre] or a 40-hex commit)"

# 2) zip 名由 mode + 版本算出来(硬要求 #2)
if [ "$MODE" = "unsigned" ]; then SUFFIX="-UNSIGNED"; else SUFFIX=""; fi
ZIP_NAME="SynchainBridge-AAX-v$VERSION-macos-arm64$SUFFIX.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
SHA_NAME="$ZIP_NAME.sha256"
SHA_PATH="$OUT_DIR/$SHA_NAME"
SUMMARY_PATH="$OUT_DIR/package-summary.md"

AAX_NAME="Synchain Bridge.aaxplugin"
EXE_NAME="Synchain Bridge"

# 3) 合规源文件清单(硬要求 #7)
LICENSE_SRC="$REPO_ROOT/LICENSE"                  # GPLv3 全文 → zip 内 LICENSE.txt
NOTICES_SRC="$REPO_ROOT/THIRD-PARTY-NOTICES.md"
OFL_SRC="$REPO_ROOT/LICENSES/OFL-1.1.txt"         # 字体子集嵌进二进制,OFL 全文须随分发

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DryRun] RepoRoot  : $REPO_ROOT"
    echo "[DryRun] Mode      : $MODE"
    echo "[DryRun] Version   : $VERSION"
    echo "[DryRun] SourceRef : $SOURCE_REF"
    if [ -n "$BUNDLE_ARG" ]; then
        echo "[DryRun] Bundle    : $(resolve_repo_path "$BUNDLE_ARG")"
    else
        echo "[DryRun] BuildDir  : $BUILD_DIR"
    fi
    echo "[DryRun] OutDir    : $OUT_DIR"
    echo "[DryRun] zip       : $ZIP_PATH"
    echo "[DryRun] sha256    : $SHA_PATH"
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

# 4) bundle 定位(硬要求 #3)。计数与取路径都用 find,取路径用 `-print -quit`(与 package-macos.sh 同口径:
#    `find | head -n 1` 在 pipefail 下会因 SIGPIPE(141)被 set -e 杀掉脚本)。
if [ -n "$BUNDLE_ARG" ]; then
    B="$(resolve_repo_path "$BUNDLE_ARG")"
    B="${B%/}"
    [ -d "$B" ] || die "--bundle-path '$B' is not a directory"
else
    [ -d "$BUILD_DIR" ] || die "build dir not found: $BUILD_DIR"
    n="$(find "$BUILD_DIR" -type d -name '*.aaxplugin' | wc -l | tr -d '[:space:]')"
    [ "$n" = "1" ] || die "expected exactly 1 .aaxplugin bundle under '$BUILD_DIR', found $n (pass --bundle-path to pick one)"
    B="$(find "$BUILD_DIR" -type d -name '*.aaxplugin' -print -quit)"
fi
base="$(basename "$B")"
[ "$base" = "$AAX_NAME" ] || die "unexpected bundle name '$base' (expected '$AAX_NAME')"
[ -f "$B/Contents/Info.plist" ] || die "bundle '$B' missing Contents/Info.plist"
[ -f "$B/Contents/MacOS/$EXE_NAME" ] || die "bundle '$B' missing Contents/MacOS/$EXE_NAME"
[ -x "$B/Contents/MacOS/$EXE_NAME" ] || die "'$B/Contents/MacOS/$EXE_NAME' is not executable"

# 5) 架构断言(硬要求 #4):arm64 单架构 —— 与 package-macos.sh 第 5 步逐字相同
assert_arm64_only() {
    local archs
    archs="$(file "$1"/Contents/MacOS/*)"
    printf '%s\n' "$archs"
    printf '%s\n' "$archs" | grep -q 'arm64' || die "'$1' is not arm64"
    ! printf '%s\n' "$archs" | grep -q 'x86_64' || die "'$1' contains an x86_64 slice; v1 ships arm64-only"
}
assert_arm64_only "$B"

# 身份:CFBundleIdentifier 必须等于 CMakeLists.txt 的 BUNDLE_ID(JUCE 对 AAX 与 VST3/AU 用同一个 bundle id)
WANT_ID="$(awk '$1=="BUNDLE_ID"{gsub(/"/,"",$2);print $2;exit}' "$REPO_ROOT/CMakeLists.txt")"
[ -n "$WANT_ID" ] || die "cannot parse BUNDLE_ID from CMakeLists.txt"
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$B/Contents/Info.plist" 2>/dev/null || true)"
[ "$GOT_ID" = "$WANT_ID" ] || die "CFBundleIdentifier '$GOT_ID' != BUNDLE_ID '$WANT_ID' from CMakeLists.txt (wrong bundle?)"

# 6) mode 断言(硬要求 #5)—— 必须在建 staging 之前:拒收时不留下任何产物。
#    输出先落进变量再用 here-string 匹配,不经 `printf | grep -q`:grep 命中即退出可能给上游送 SIGPIPE,
#    pipefail 下整条管道判非零。codesign -dv 的输出在 stderr,故 2>&1;它自身失败(未签名)时也要能走到判定。
REFUSE="refusing to package an unsigned bundle under a release name"
assert_signed_bundle() {
    local b="$1" info
    codesign --verify --strict --verbose=2 "$b" || die "$REFUSE: codesign --verify --strict failed for '$b'"
    info="$(codesign -dv --verbose=4 "$b" 2>&1 || true)"
    printf '%s\n' "$info"
    grep -q '^Authority=' <<< "$info" || die "$REFUSE: '$b' has no signing Authority (ad-hoc or unsigned)"
    if grep -q 'Signature=adhoc' <<< "$info"; then die "$REFUSE: '$b' carries only an ad-hoc signature"; fi
    [ -f "$b/Contents/_CodeSignature/CodeResources" ] \
        || die "$REFUSE: '$b' has no Contents/_CodeSignature/CodeResources (resources are not sealed)"
}
if [ "$MODE" = "signed" ]; then
    assert_signed_bundle "$B"
fi

# 从这里起开始产出:任何失败(die / set -e)都经 EXIT trap 删掉本次的 zip / .sha256 与临时目录(硬要求 #9)。
STAGING="$OUT_DIR/_staging"
READBACK_DIR=""
PACKAGED_OK=0
on_exit() {
    local rc=$?
    rm -rf "$STAGING"
    [ -z "$READBACK_DIR" ] || rm -rf "$READBACK_DIR"
    if [ "$PACKAGED_OK" -ne 1 ]; then rm -f "$ZIP_PATH" "$SHA_PATH"; fi
    exit "$rc"
}
trap on_exit EXIT

# 7) 组装 staging 目录:bundle 一律 ditto(保住符号链接 / 可执行位 / 签名封存)
rm -rf "$STAGING"
rm -f "$ZIP_PATH" "$SHA_PATH"
mkdir -p "$OUT_DIR" "$STAGING/LICENSES"

ditto "$B" "$STAGING/$AAX_NAME"
cp "$LICENSE_SRC" "$STAGING/LICENSE.txt"
cp "$NOTICES_SRC" "$STAGING/THIRD-PARTY-NOTICES.md"
cp "$OFL_SRC"     "$STAGING/LICENSES/OFL-1.1.txt"

# 8) INSTALL-AAX.txt(硬要求 #6;中文,只有源码那一行是英文,与 package-macos.sh 的 INSTALL.txt 同口径)
AAX_DIR="/Library/Application Support/Avid/Audio/Plug-Ins"
# 模式相关段落用函数 + 普通 heredoc 输出,再经 $( ) 取值:不把 heredoc 直接嵌进 $( ) 里 ——
# macOS 自带的 bash 3.2 解析 $( ) 内的 heredoc 有已知缺陷(正文里的括号 / 引号会被当成语法)。
install_mode_block() {
    if [ "$MODE" = "unsigned" ]; then
        cat <<'EOF'
⚠ 未签名构建(UNSIGNED)—— 不是发行版
------------------------------------
本包里的 AAX 没有经过 PACE 签名,零售版 Pro Tools 不会加载。它只用于:
  ① 维护者用 scripts/sign-aax-macos.sh 签名后再打发行包;
  ② AAX 开发者在 Avid 的 Pro Tools Developer 版本里测试。
正式版请到 GitHub Releases 下载不带 -UNSIGNED 后缀的 zip。
本包同样未经 Apple 公证:下面安装步骤里的 xattr 那一条必须执行,否则 Pro Tools 会拒绝加载。
EOF
    else
        cat <<'EOF'
签名说明(AAX 是本项目唯一签名的格式)
------------------------------------
零售版 Pro Tools 只加载经 PACE 签名的 AAX 插件;本包由维护者在本机用 PACE wraptool 签名,
构建流水线不持有任何签名凭据。本包**未经 Apple 公证**(项目没有 Apple Developer Program 会员):
浏览器下载的文件带 com.apple.quarantine 隔离属性,不执行下面安装步骤里的 xattr 那一条,
Pro Tools 会拒绝加载;去掉隔离属性不影响 PACE 签名。
签名后改动 bundle 内任何文件都会让签名失效 —— 请用 ditto 整体复制,不要增删或编辑其中的文件。
VST3 / AU 版本仍不签名、不公证(U13)。
EOF
    fi
}
MODE_BLOCK="$(install_mode_block)"

cat > "$STAGING/INSTALL-AAX.txt" <<EOF
Synchain Bridge AAX(Avid Pro Tools)—— 安装说明(macOS,Apple Silicon)
======================================================================

版本:$VERSION

$MODE_BLOCK

先读这一段:本包只有 Apple Silicon(arm64)版
------------------------------------------
包内 AAX 只含 arm64 一个架构,不含 x86_64。
如果 Pro Tools 是 Intel 版,或虽在 Apple Silicon 上、但被勾了「使用 Rosetta 打开」,
Pro Tools 进程就是 x86_64,插件不会出现在插件列表里 —— 这不是装错了,是架构不匹配。
处理:在「访达」里选中 Pro Tools → 显示简介 → 取消勾选「使用 Rosetta 打开」,再以原生 arm64 重开 Pro Tools。

系统要求
--------
Apple Silicon Mac、macOS 11 或更高;Pro Tools(原生 arm64 运行、AAX Native)。

安装路径(需要管理员权限)
------------------------
Pro Tools 只扫描下面这一个目录,没有用户级目录:

  $AAX_DIR/

先退出 Pro Tools,在「终端」里依次执行(<解压路径> 换成本压缩包解压出来的目录):

  sudo rm -rf "$AAX_DIR/$AAX_NAME"
  sudo ditto "<解压路径>/$AAX_NAME" "$AAX_DIR/$AAX_NAME"
  sudo xattr -dr com.apple.quarantine "$AAX_DIR/$AAX_NAME"

必须先删旧版:ditto 对已存在的 bundle 是合并,旧文件会残留。务必用 ditto 而不是 cp -r ——
cp -r 会丢符号链接与可执行位。路径属 root,不加 sudo 会得到 Operation not permitted。
重启 Pro Tools,在插入点的插件菜单里按名称 Synchain Bridge 查找。

浏览器
------
接收端是 Synchain 网页应用里项目的 Creative Space 页面。
macOS 上请用 Chrome / Edge / Firefox 打开;Safari 不在验证矩阵内,不建议使用。
浏览器必须与插件在同一台机器上 —— 桥 #2 只监听本机回环地址。

商标
----
Avid、Pro Tools 与 AAX 是 Avid Technology, Inc. 的商标或注册商标;PACE 与 iLok 是 PACE Anti-Piracy, Inc.
的商标。Synchain Bridge 是独立项目,与 Avid 无隶属、赞助或背书关系。

许可证
------
AAX 构建额外包含 Avid AAX SDK 2.8.0(随 JUCE 8.0.8),按其 GPLv3 选项使用,故 AAX 二进制整体按
GPL 第 3 版分发(LICENSE.txt),详见 THIRD-PARTY-NOTICES.md。

源码获取
--------
Complete corresponding source for this exact build: https://github.com/synchain-oss/synchain-bridge/tree/$SOURCE_REF
EOF

# 9) 压缩(硬要求 #8):ditto -c -k,不加 --keepParent(staging 内容平铺到 zip 根);
#    --norsrc --noextattr 的理由同 package-macos.sh 第 8 步(否则 __MACOSX/ 条目会让可执行位断言必然假失败)。
ditto -c -k --norsrc --noextattr "$STAGING" "$ZIP_PATH"

# 10) 打包后断言:层级 + 四个合规文件 + 可执行位;缺一即退出 1(EXIT trap 随之删掉 zip)。
#     全名比对用 awk 做字面匹配,避免 bundle 名里的 '.' 被当成正则通配。
NAMES="$(unzip -Z1 "$ZIP_PATH")"
for r in "$AAX_NAME/Contents/Info.plist" "$AAX_NAME/Contents/MacOS/$EXE_NAME" \
         'LICENSE.txt' 'THIRD-PARTY-NOTICES.md' 'LICENSES/OFL-1.1.txt' 'INSTALL-AAX.txt'; do
    printf '%s\n' "$NAMES" | awk -v f="$r" '$0 == f { hit = 1 } END { exit !hit }' \
        || die "zip assertion failed: missing '$r'"
done

# 可执行位:与 package-macos.sh 第 9 步逐字相同(只挑 Contents/MacOS/ 下的文件条目;排除 __MACOSX/;
# 首字符放行 `-` 与 `l`)。
MACHO="$(unzip -Z "$ZIP_PATH" | grep -v '__MACOSX/' | grep -E '/Contents/MacOS/[^[:space:]]' || true)"
[ -n "$MACHO" ] || die "zip assertion failed: no Contents/MacOS/ file entries"
NOT_EXEC="$(printf '%s\n' "$MACHO" | grep -vE '^[-l]rwx' || true)"
[ -z "$NOT_EXEC" ] || die "zip assertion failed: exec bit lost on:
$NOT_EXEC"

# 11) 仅 signed:zip 内必须带 CodeResources,再解压回读,对解出的 bundle 重做第 5 条断言并比对字节(硬要求 #9)
if [ "$MODE" = "signed" ]; then
    printf '%s\n' "$NAMES" | awk -v f="$AAX_NAME/Contents/_CodeSignature/CodeResources" '$0 == f { hit = 1 } END { exit !hit }' \
        || die "zip assertion failed: missing '$AAX_NAME/Contents/_CodeSignature/CodeResources'"
    READBACK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/synchain-aax-readback.XXXXXX")"
    ditto -x -k "$ZIP_PATH" "$READBACK_DIR"
    assert_signed_bundle "$READBACK_DIR/$AAX_NAME"
    SRC_H="$(shasum -a 256 "$B/Contents/MacOS/$EXE_NAME" | awk '{ print $1 }')"
    RB_H="$(shasum -a 256 "$READBACK_DIR/$AAX_NAME/Contents/MacOS/$EXE_NAME" | awk '{ print $1 }')"
    [ "$SRC_H" = "$RB_H" ] || die "readback: executable in zip hashes to $RB_H, source bundle is $SRC_H"
    echo "Readback OK: zipped bundle verifies and its executable is byte-identical to the signed source ($SRC_H)"
fi

# 12) .sha256 独立资产 + package-summary.md(硬要求 #10 / #11)—— 与 package-macos.sh 第 10 步逐字相同,
#     改一处必须改全部四处。.sha256 的格式:"<小写 hash><两个空格><zip 文件名>"。
HASH="$(shasum -a 256 "$ZIP_PATH" | awk '{ print $1 }')"
printf '%s  %s\n' "$HASH" "$ZIP_NAME" > "$SHA_PATH"

SIZE_BYTES="$(wc -c < "$ZIP_PATH" | tr -d '[:space:]')"
RELEASE_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# summary 以空行分段追加:同一个 OutDir 下可能已有别的平台或本脚本上一次运行写的段落。
# 同名 zip 的旧段落先删掉,避免重复跑脚本时越堆越长 —— 但**只删同名的那一条**。
# 切段一律按记录首行 `version:` 切,**不能按空行切**(旧文件段间可能没有空行);匹配用 `zipFileName:` 整行逐字相等;
# 行尾先把 CR 剥掉再比(Windows 侧旧文件可能是 CRLF);首条记录之前的内容原样保留。详细理由见 package-macos.sh 第 10 步。
if [ -f "$SUMMARY_PATH" ]; then
    awk -v z="zipFileName: $ZIP_NAME" '
        function flush() { if (started && !drop) { print rec; print "" } }   # 保留段 + 段后一个空行
        NR == 1 { sub(/^\357\273\277/, "") }                 # 旧 powershell.exe 5.1 写出的 UTF-8 BOM 只可能在首行
        { sub(/\r$/, "") }                                  # CRLF 归一成 LF,再做下面的一切比对
        NF == 0 { next }                                    # 空行只是分隔符,重排时统一重新生成
        /^version:[[:space:]]/ {                            # 记录首行:先结算上一条
            flush(); rec = ""; drop = 0; started = 1
        }
        !started { print; next }                            # 首条记录之前的内容原样透传
        { rec = rec (rec == "" ? "" : "\n") $0; if ($0 == z) drop = 1 }
        END { flush() }
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

PACKAGED_OK=1
echo "Packaged: $ZIP_PATH ($SIZE_BYTES bytes, mode=$MODE)"
echo "SHA256:   $HASH"
