#!/usr/bin/env bash
# Copyright (c) 2026 Synchain
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# scripts/sign-aax-macos.sh —— AAX(macOS arm64)本机签名:CI 产出的 -UNSIGNED.zip → PACE wraptool 签名 →
# package-aax-macos.sh --mode signed 出发行包。与 scripts/sign-aax.ps1(Windows)同构。
# 只由维护者在本机手工执行;CI 不调用、流水线不持有任何签名凭据(CLAUDE.md §0 铁律 1)。
# AAX 是本项目唯一签名的格式(零售版 Pro Tools 只加载 PACE 签名件),VST3 / AU 仍按 U13 不签名不公证。
#
# 发布者二选一(互斥):--wcguid <GUID>(推荐,PACE Central 里为本产品建的 wrap 配置)或 --customer-number +
# --customer-name [+ --product-name,默认 "Synchain Bridge"]。--account 可选:不给就不传,wraptool 用 iLok License Manager 的
# 默认账号。PACE 账号口令两种给法:事先手动执行一次带 --password 的 `wraptool sync --account <PACE 账号>`,口令存进 wraptool
# 自己的钥匙串(推荐,之后签名不用再给;`wraptool remove-pswd --account <PACE 账号>` 清除);或 --prompt-account-password
# (须同时给 --account)交互读入,经 --pswd-no-save 传,不写进钥匙串。
# 这几条与 `help` 写法、v6 安装路径都已在 Windows 版 wraptool 6.0.1 上实测(2026-10-08,见 scripts/sign-aax.ps1),mac 上没法
# 实测,下面照样标 TO-VALIDATE。
#
# 流程(任一步失败即 exit 1):
#   预检 0 参数:发布者恰好一种;--wcguid 是 GUID;--customer-number 须配 --customer-name;--prompt-account-password 须配
#          --account;--extra-arg 不含口令、不覆盖本脚本管理的 flag(长短写法都算)
#   预检 1 完整性:输入 zip 同目录的 .sha256 逐字节等于 "<小写 hash><两个空格><zip 名>\n"(shasum -a 256)。
#          只防损坏 / 下载不完整 —— .sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256,防不了替换
#   预检 2 从文件名解析版本:SynchainBridge-AAX-v<版本>-macos-arm64-UNSIGNED.zip
#   预检 3 检出对应该版本:-ci.<sha> 版本要求 HEAD 以该 sha 开头(source ref = 完整 HEAD);其余版本要求 HEAD 上有
#          tag v<版本>;LICENSE / THIRD-PARTY-NOTICES.md / LICENSES / scripts 无未提交改动
#   预检 3b 来源(--source-run-id):该 run 属于本仓库(非 fork)、是 ci.yml / release.yml、结论 success、事件为 push / workflow_dispatch
#          (pull_request 构建的是合并提交,不认)、head_sha = HEAD;
#          再用 gh run download 取回它的 aax-unsigned-* artifact,其中同名 zip 必须与输入 zip 字节相同。
#          这是「哪些字节会被盖上签名」的信任根;不给 --source-run-id 只记 WARN(本地自建件没有 run 可核对)
#   预检 4 security find-identity -p codesigning(不加 -v,TO-VALIDATE V6)里名字与 --signid 完全相等的身份恰好 1 个
#   预检 5 定位 wraptool(TO-VALIDATE:mac 上未实测):--wraptool → $PACE_FUSION_HOME/bin/wraptool → PATH →
#          /Applications/PACEAntiPiracy/Eden/Fusion/Versions/<版本号最高的>/bin/wraptool;`wraptool help` 的输出里有本次要用的
#          全部 flag(按发布者 / 账号方式决定;v6 的 `help sign` 不合法,Windows 实测 exit 9),传值的 flag 在 help 里标着 arg
#   预检 6 iLok 只提醒不硬检
#   预检 7 ditto -x -k 解到全新临时目录(保留可执行位):bundle 存在、arm64-only、没有签名 Authority,
#          且 `wraptool verify` 必须失败、输出里有 NOT signed(已签过的件重签会报错)
#   签名   wraptool sign --verbose [--account] --signid (--wcguid | --customernumber --customername --productname)
#          [--pswd-no-save] --in --out [--extra-arg ...](TO-VALIDATE);
#          第一次签名可能弹出钥匙串授权框,需要人点;回显的命令里 PACE 账号 / wcguid / customer number / 口令一律打码为 ****;
#          wraptool --verbose 是否回显收到的参数未知(TO-VALIDATE,待首次真签名),它的输出逐行把这些值字面替换成 **** 后再显示,
#          不给 --account 时它打印的默认账号名同样打码
#   后检   wraptool verify;codesign --verify --deep --strict;codesign -dv 的 Authority= 等于 --signid 且不是 ad-hoc;
#          调 package-aax-macos.sh --mode signed 打包;解压回读后再跑一轮 wraptool 与 codesign 验证;
#          最后只**打印** gh release upload 命令,不自动执行
# 成功即删除临时工作目录;失败则保留并打印路径(里面只有 bundle,没有秘密)。
# 打包之后的任何一步(回读复验等)失败,都删掉本次产出的发行名 zip 与 .sha256:失败路径上 out-dir 里不留可上传的发行名 zip
# (package-summary.md 里本次追加的段落会留下,只是记录,不是可上传的文件)。
#
# 口令:--prompt-account-password 的 PACE 账号口令只经 read -s 交互读取,不进本脚本的参数、日志与 shell 历史;但 wraptool
# 只收命令行参数(6.0.1 的 help 里没有 stdin / 环境变量通道),签名期间它会以 --pswd-no-save <明文> 出现在 wraptool 的进程
# 命令行里 —— macOS 上本机其他用户用 ps 也看得到。签名期间不要让他人登录这台机器(借用的 Mac 尤其注意)。
#
# --dry-run:跑全部预检(第 7 步的解压也在临时目录里做,结束即删)并汇总,打印签名计划与 package-aax-macos.sh
# --dry-run 的输出;不读口令、不调用 wraptool sign、不产出任何文件。
#
# TO-VALIDATE(mac 上都还没实测):wraptool 的 v6 默认安装路径与 PACE_FUSION_HOME、`help` 的 flag、--account / --pswd-no-save /
# --customernumber 的用法(Windows 6.0.1 已实测,mac 版照搬);verify / sign 给 bundle 目录还是内层可执行文件、--out 能否指向
# 新路径;待首次真签名:真签名能否成功、已签名件 verify 的退出码、--verbose 是否回显参数;V5 --extrasigningoptions
# "--timestamp" 对自签名 / Apple Development 身份是否可用(默认不加)、V6 find-identity 不加 -v 的行为、V11 上传到 draft。
# 核对完删掉对应标记。
#
# 绝不 set -x:xtrace 会把账号与口令(若用 --prompt-account-password)逐行回显进终端 / 日志。
#
# 用法:
#   bash scripts/sign-aax-macos.sh --unsigned-zip <SynchainBridge-AAX-v*-macos-arm64-UNSIGNED.zip>
#        --signid "<钥匙串身份名>" (--wcguid <GUID> | --customer-number <号> --customer-name <公司名> [--product-name <名>])
#        [--account <PACE 账号> [--prompt-account-password]] [--source-run-id <run ID>]
#        [--out-dir dist/aax-signed] [--wraptool <path>] [--extra-arg <arg>]... [--dry-run]

set -euo pipefail
set +x

die() {
    echo "sign-aax-macos: FAIL —— $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
用法: sign-aax-macos.sh --unsigned-zip <zip> --signid "<钥匙串身份名>" (--wcguid <GUID> | --customer-number <号> --customer-name <公司名>) [选项]
  --unsigned-zip <path>      必填:SynchainBridge-AAX-v<版本>-macos-arm64-UNSIGNED.zip,同目录须有 .sha256
  --signid <name>            必填:钥匙串里代码签名身份的完整名字(security find-identity -p codesigning 列出的引号内文字)
  --wcguid <GUID>            发布者(推荐):PACE wrap 配置 GUID(日志里打码);与 --customer-number 二选一
  --customer-number <号>     发布者(备选):PACE customer number(日志里打码);须同时给 --customer-name
  --customer-name <公司名>   与 --customer-number 同用
  --product-name <名>        与 --customer-number 同用,默认 "Synchain Bridge"
  --account <name>           可选:PACE 账号(日志里打码);不给则用 iLok License Manager 的默认账号
  --prompt-account-password  交互读入 PACE 账号口令,经 --pswd-no-save 传(不写进 wraptool 钥匙串);须同时给 --account
  --source-run-id <id>       产出该 zip 的 ci / release run 的 ID:给了就核对来源(需 gh 已登录),不给只记 WARN
  --out-dir <path>           输出目录;相对路径按仓库根解析,默认 dist/aax-signed
  --wraptool <path>          wraptool 路径;默认依次找 $PACE_FUSION_HOME/bin、PATH、PACE 默认安装路径(TO-VALIDATE)
  --extra-arg <arg>          原样透传给 wraptool sign,可重复(TO-VALIDATE);不得含 password / pswd
  --dry-run                  只跑预检并打印计划:不读口令、不调用 wraptool sign、不产出文件
USAGE
}

UNSIGNED_ZIP=""
ACCOUNT=""
WCGUID=""
CUSTOMER_NUMBER=""
CUSTOMER_NAME=""
PRODUCT_NAME="Synchain Bridge"
PRODUCT_NAME_GIVEN=0
SIGNID=""
SOURCE_RUN_ID=""
OUT_DIR="dist/aax-signed"
WRAPTOOL_ARG=""
EXTRA=()
EXTRA_N=0
PROMPT_AP=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --unsigned-zip) [ $# -ge 2 ] || die "--unsigned-zip 缺少取值"; UNSIGNED_ZIP="$2"; shift 2 ;;
        --account)      [ $# -ge 2 ] || die "--account 缺少取值";      ACCOUNT="$2"; shift 2 ;;
        --wcguid)       [ $# -ge 2 ] || die "--wcguid 缺少取值";       WCGUID="$2"; shift 2 ;;
        --customer-number) [ $# -ge 2 ] || die "--customer-number 缺少取值"; CUSTOMER_NUMBER="$2"; shift 2 ;;
        --customer-name)   [ $# -ge 2 ] || die "--customer-name 缺少取值";   CUSTOMER_NAME="$2"; shift 2 ;;
        --product-name)    [ $# -ge 2 ] || die "--product-name 缺少取值";    PRODUCT_NAME="$2"; PRODUCT_NAME_GIVEN=1; shift 2 ;;
        --signid)       [ $# -ge 2 ] || die "--signid 缺少取值";       SIGNID="$2"; shift 2 ;;
        --source-run-id) [ $# -ge 2 ] || die "--source-run-id 缺少取值"; SOURCE_RUN_ID="$2"; shift 2 ;;
        --out-dir)      [ $# -ge 2 ] || die "--out-dir 缺少取值";      OUT_DIR="$2"; shift 2 ;;
        --wraptool)     [ $# -ge 2 ] || die "--wraptool 缺少取值";     WRAPTOOL_ARG="$2"; shift 2 ;;
        --extra-arg)    [ $# -ge 2 ] || die "--extra-arg 缺少取值";    EXTRA+=("$2"); EXTRA_N=$((EXTRA_N + 1)); shift 2 ;;
        --prompt-account-password) PROMPT_AP=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              usage >&2; die "unknown argument: $1" ;;
    esac
done

[ -n "$UNSIGNED_ZIP" ] || { usage >&2; die "--unsigned-zip is required"; }
[ -n "$SIGNID" ]       || { usage >&2; die "--signid is required"; }
# ditto / codesign / security / file 都是 macOS 专有,任何模式下都不在别的平台上跑
[ "$(uname -s)" = "Darwin" ] || die "只支持 macOS(Windows 用 scripts/sign-aax.ps1)"

# 仓库根 = 本脚本上一级目录(与调用时的 CWD 无关)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

resolve_repo_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "$REPO_ROOT" "$1" ;;
    esac
}
# 用户给的路径(--unsigned-zip / --wraptool)按当前目录解析
abs_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "$PWD" "$1" ;;
    esac
}
OUT_DIR="$(resolve_repo_path "$OUT_DIR")"

AAX_NAME="Synchain Bridge.aaxplugin"
EXE_NAME="Synchain Bridge"
UPLOAD_REPO="synchain-oss/synchain-bridge"
# PACE 默认安装布局(TO-VALIDATE:照 Windows 6.0.1 实测的 Versions/<版本>/bin/wraptool 推断,mac 上未实测)
WRAPTOOL_VERSIONS_DIR="/Applications/PACEAntiPiracy/Eden/Fusion/Versions"

# 本次要用的 wraptool flag(预检 5b 在 `wraptool help` 的输出里逐个找)
required_flags() {
    local f="--verbose --signid --in --out"
    if [ -n "$WCGUID" ]; then f="$f --wcguid"; else f="$f --customernumber --customername --productname"; fi
    if [ -n "$ACCOUNT" ]; then f="$f --account"; fi
    if [ "$PROMPT_AP" -eq 1 ]; then f="$f --pswd-no-save"; fi
    printf '%s' "$f"
}

# $WRAPTOOL_VERSIONS_DIR/<版本>/bin/wraptool 里版本号最高的一个(目录名按数字逐段比较,不是版本号的跳过);找不到返回 1
find_wraptool_default() {
    local d n best ver_re='^[0-9]+(\.[0-9]+)*$'
    [ -d "$WRAPTOOL_VERSIONS_DIR" ] || return 1
    best="$(for d in "$WRAPTOOL_VERSIONS_DIR"/*; do
                n="${d##*/}"
                if [[ "$n" =~ $ver_re ]] && [ -x "$d/bin/wraptool" ]; then printf '%s\n' "$n"; fi
            done | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
    [ -n "$best" ] || return 1
    printf '%s' "$WRAPTOOL_VERSIONS_DIR/$best/bin/wraptool"
}

# 回显命令:含空白的参数加双引号;传进来的必须是打过码的参数表,真实参数(含口令)绝不经这里输出
fmt_cmd() {
    local out="" a
    for a in "$@"; do
        case "$a" in
            *[[:space:]]*|'') out="$out \"$a\"" ;;
            *)                out="$out $a" ;;
        esac
    done
    printf '%s' "${out# }"
}

# wraptool 的输出逐行把这些值(口令 / 账号 / wcguid / customer number)字面替换成 **** 再显示
redact_stream() {
    local line s acct_re='^(.*[Aa]ccount for this operation:[[:space:]]*).+$'
    while IFS= read -r line || [ -n "$line" ]; do
        for s in "$@"; do
            # 引号内的模式按字面匹配,不当通配;子串替换,账号很短或是常见词时会连带替换无关文字,只影响可读性
            if [ -n "$s" ]; then line="${line//"$s"/****}"; fi
        done
        # 不给 --account 时 wraptool 会打印它用的默认账号(Windows 6.0.1 实测:"Using the default iLok License Manager
        # account for this operation: <账号>"),脚本不知道账号名,按这句文案把冒号后整行打码(账号名带空格 / 引号也不漏)
        if [[ "$line" =~ $acct_re ]]; then line="${BASH_REMATCH[1]}****"; fi
        printf '%s\n' "$line"
    done
}

# ---- 预检结果登记 ----
# 非 dry-run:第一项 FAIL 即 die;dry-run:只登记,跑完全部预检后汇总。
# 注意 set -e:计数用 X=$((X + 1)),不用 ((X++))(后者在 X 为 0 时返回 1,会被 set -e 杀掉)。
CHECK_LOG=()
FAILS=0
WARNS=0
check() {   # check <PASS|FAIL|WARN|SKIP|INFO> <编号> <说明>
    printf '[%s] %s —— %s\n' "$1" "$2" "$3"
    CHECK_LOG+=("$(printf '%-4s  %s' "$1" "$2")")
    case "$1" in
        FAIL) FAILS=$((FAILS + 1)); [ "$DRY_RUN" -eq 1 ] || die "预检 $2 未通过:$3" ;;
        WARN) WARNS=$((WARNS + 1)) ;;
    esac
    return 0
}

WORK=""
SUCCEEDED=0
PACKAGED=0      # 本次运行已产出发行名 zip:之后任何一步失败都要删掉它(见 on_exit)
SIGNED_ZIP=""
AP=""
on_exit() {
    local rc=$?
    AP=""
    [ -z "${PROV_DIR:-}" ] || rm -rf "$PROV_DIR"
    # 打包之后的步骤(回读复验等)没通过:删掉本次产出的发行名 zip / .sha256 —— 它的文件名与 docs/release.md §7.3 第 5 步的
    # 上传路径逐字相同,留着就可能被照文档传上去。只在本次确实打过包时删,早期失败不碰上一次成功留下的件。
    if [ "$PACKAGED" -eq 1 ] && [ "$SUCCEEDED" -ne 1 ] && [ -n "$SIGNED_ZIP" ]; then
        rm -f -- "$SIGNED_ZIP" "$SIGNED_ZIP.sha256"
        echo "打包后的复验未通过:已删除 $SIGNED_ZIP 及 .sha256(失败路径不留发行名 zip;package-summary.md 里本次追加的段落只是记录)" >&2
        [ "$rc" -ne 0 ] || rc=1
    fi
    if [ -n "$WORK" ] && [ -d "$WORK" ]; then
        if [ "$SUCCEEDED" -eq 1 ]; then
            rm -rf "$WORK"
        else
            echo "工作目录已保留供排查(里面只有 bundle,没有秘密):$WORK" >&2
        fi
    fi
    exit "$rc"
}
trap on_exit EXIT

# ---------------------------------------------------------------- 预检 0:参数
p0_err=""
guid_re='^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$'
if [ -n "$WCGUID" ] && [ -n "$CUSTOMER_NUMBER" ]; then
    p0_err="--wcguid 与 --customer-number 互斥:发布者信息只能选一种"
elif [ -z "$WCGUID" ] && [ -z "$CUSTOMER_NUMBER" ]; then
    p0_err="缺发布者信息:给 --wcguid <GUID>(推荐),或 --customer-number 加 --customer-name(备选)"
elif [ -n "$WCGUID" ] && ! [[ "$WCGUID" =~ $guid_re ]]; then
    p0_err="--wcguid 不是 GUID(期望 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,不带花括号)"
elif [ -n "$CUSTOMER_NUMBER" ] && [ -z "$CUSTOMER_NAME" ]; then
    p0_err="--customer-number 须同时给 --customer-name(公司名)"
elif [ -z "$CUSTOMER_NUMBER" ] && { [ -n "$CUSTOMER_NAME" ] || [ "$PRODUCT_NAME_GIVEN" -eq 1 ]; }; then
    p0_err="--customer-name / --product-name 只与 --customer-number 同用(--wcguid 方式下发布者与产品信息来自 wrap 配置)"
elif [[ "$CUSTOMER_NUMBER" =~ [[:space:]] || "$CUSTOMER_NUMBER" == -* ]]; then
    p0_err="--customer-number 不得含空白、不得以 - 开头"
elif [ -n "$CUSTOMER_NUMBER" ] && [[ "$CUSTOMER_NAME" == -* || "$PRODUCT_NAME" == -* ]]; then
    # 以 - 开头的值会被 wraptool(boost 风格)当成短 flag
    p0_err="--customer-name / --product-name 不得以 - 开头"
elif [ -z "$PRODUCT_NAME" ]; then
    p0_err="--product-name 传入了空串"
elif [ "$PROMPT_AP" -eq 1 ] && [ -z "$ACCOUNT" ]; then
    p0_err="--prompt-account-password 须同时给 --account:读入的口令属于哪个 PACE 账号要明确"
fi
# 本脚本管理的长 flag 不区分大小写(与 Windows 侧 -match 同口径;--password / --pswd-no-save 由 *password* / *pswd* 覆盖);
# 短写法照 wraptool 6.0.1 `help` 的别名表,区分大小写(-p 是 --password、-P 是 --keypassword、-i 是 --in、-I 是 --signid),
# boost 风格允许值紧贴短 flag(-pXXX),所以按前缀拦
managed_re='^--(account|wcguid|wcfile|customernumber|customername|productname|signid|keyfile|keypassword|in|out)(=|$)'
if [ "$EXTRA_N" -gt 0 ]; then
    for a in "${EXTRA[@]}"; do
        lower="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            *password*|*pswd*) p0_err="--extra-arg 不得含口令类参数('$a'):口令只经交互读入,不进参数" ;;
        esac
        if [[ "$lower" =~ $managed_re ]]; then p0_err="--extra-arg 不得重复本脚本管理的 flag('$a')"; fi
        case "$a" in
            -[apPGWCNUIkio]*) p0_err="--extra-arg 不得重复本脚本管理的 flag('$a',短写法)" ;;
        esac
    done
fi
case "$SOURCE_RUN_ID" in
    *[!0-9]*) p0_err="--source-run-id 应为纯数字的 workflow run ID:'$SOURCE_RUN_ID'" ;;
esac
if [ -n "$WCGUID" ]; then p0_publisher="wcguid 格式正确"; else p0_publisher="customer number / customer name \"$CUSTOMER_NAME\" / product name \"$PRODUCT_NAME\""; fi
if [ -n "$ACCOUNT" ]; then p0_account="--account(打码)"; else p0_account="iLok License Manager 默认账号"; fi
if [ "$PROMPT_AP" -eq 1 ]; then p0_account="$p0_account + 交互口令(--pswd-no-save)"; fi
if [ -z "$p0_err" ]; then
    check PASS "0 参数" "发布者 $p0_publisher;账号 $p0_account;extra-arg $EXTRA_N 项"
else
    check FAIL "0 参数" "$p0_err"
fi

# ---------------------------------------------------------------- 预检 1:.sha256(完整性)
# 只防损坏 / 下载不完整:.sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256 —— 来源由预检 3b 核对
ZIP="$(abs_path "$UNSIGNED_ZIP")"
ZIP_NAME="$(basename "$ZIP")"
ZIP_OK=0
if [ ! -f "$ZIP" ]; then
    check FAIL "1 sha256" "找不到输入 zip:$ZIP"
elif [ ! -f "$ZIP.sha256" ]; then
    check FAIL "1 sha256" "缺少同目录的 $ZIP_NAME.sha256(CI artifact 里与 zip 成对下载;不要手工生成)"
else
    ACTUAL="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
    # 逐字节比:必须恰为 package-aax-macos.sh 写出的 "<hash>  <zip 名>\n"(无 CRLF / BOM / 多余行)
    if printf '%s  %s\n' "$ACTUAL" "$ZIP_NAME" | cmp -s - "$ZIP.sha256"; then
        check PASS "1 sha256" "完整性:$ZIP_NAME = $ACTUAL"
        ZIP_OK=1
    else
        recorded="$(LC_ALL=C head -c 64 "$ZIP.sha256")"
        hex_re='^[0-9a-f]{64}$'
        if [[ "$recorded" =~ $hex_re ]] && [ "$recorded" != "$ACTUAL" ]; then
            check FAIL "1 sha256" "SHA256 不符:.sha256 记录 $recorded,实际 $ACTUAL —— zip 损坏或下载不完整(本项只验完整性),拒绝签名"
        else
            check FAIL "1 sha256" "$ZIP_NAME.sha256 格式不符:应恰为「64 位小写 hex + 两个空格 + $ZIP_NAME + LF」"
        fi
    fi
fi

# ---------------------------------------------------------------- 预检 2:版本
VER=""
name_re='^SynchainBridge-AAX-v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?)-macos-arm64-UNSIGNED\.zip$'
if [[ "$ZIP_NAME" =~ $name_re ]]; then
    VER="${BASH_REMATCH[1]}"
    check PASS "2 版本" "v$VER"
else
    check FAIL "2 版本" "文件名不是 SynchainBridge-AAX-v<版本>-macos-arm64-UNSIGNED.zip:'$ZIP_NAME'(只接受 package-aax-macos.sh --mode unsigned 的产物,不要改名)"
fi

# ---------------------------------------------------------------- 预检 3:检出与版本对应
SOURCE_REF=""
HEAD_COMMIT=""   # 已确认与版本对应的 HEAD commit(预检 3b 用;合规文件脏不影响它)
IS_CI=0
if [ -z "$VER" ]; then
    check SKIP "3 检出" "版本未解析出来"
elif ! command -v git >/dev/null 2>&1; then
    check FAIL "3 检出" "git 不在 PATH 上"
elif ! HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    check FAIL "3 检出" "git rev-parse HEAD 失败:$REPO_ROOT 不是 git 检出?"
else
    p3_err=""
    ci_re='-ci\.([0-9a-f]{7,40})$'
    if [[ "$VER" =~ $ci_re ]]; then
        # CI 预发布件(<CMake VERSION>-ci.<sha7>):没有对应 tag,源码链接钉完整 commit(与 ci.yml 8d 同口径)
        IS_CI=1
        want="${BASH_REMATCH[1]}"
        case "$HEAD_SHA" in
            "$want"*) SOURCE_REF="$HEAD_SHA"; HEAD_COMMIT="$HEAD_SHA" ;;
            *) p3_err="版本 $VER 来自 commit $want,当前 HEAD = $HEAD_SHA:先 git checkout $want(合规文件与 INSTALL-AAX.txt 的源码链接必须对应该 commit)" ;;
        esac
    else
        # 正式版与 tag 预发布(含 v0.0.0-test 彩排):HEAD 上必须有 v<版本> tag。here-string 而非管道:grep -q 提前退出
        # 会给上游送 SIGPIPE,pipefail 下整条管道判非零
        tags="$(git -C "$REPO_ROOT" tag --points-at HEAD 2>/dev/null || true)"
        if grep -Fxq -- "v$VER" <<< "$tags"; then
            SOURCE_REF="v$VER"
            HEAD_COMMIT="$HEAD_SHA"
        else
            p3_err="HEAD 上没有 tag v$VER(现有:$(printf '%s' "${tags:-(无)}" | tr '\n' ' ')):先 git checkout v$VER"
        fi
    fi
    if [ -z "$p3_err" ]; then
        if ! dirty="$(git -C "$REPO_ROOT" status --porcelain -- LICENSE THIRD-PARTY-NOTICES.md LICENSES scripts 2>/dev/null)"; then
            p3_err="git status 失败"
        elif [ -n "$dirty" ]; then
            p3_err="合规文件 / scripts 有未提交改动(打进发行包的合规文件必须就是该版本的):$(printf '%s' "$dirty" | tr '\n' ';')"
        fi
    fi
    if [ -z "$p3_err" ]; then
        check PASS "3 检出" "source ref = $SOURCE_REF;合规文件与 scripts/ 无改动"
    else
        SOURCE_REF=""
        check FAIL "3 检出" "$p3_err"
    fi
fi

# ---------------------------------------------------------------- 预检 3b:来源(哪次构建产出了这些字节)
PROV_DIR=""
r_path=""
r_event=""
r_sha=""
if [ -z "$SOURCE_RUN_ID" ]; then
    check WARN "3b 来源" "未给 --source-run-id:只验了完整性,没核对这个 zip 出自哪次 CI 构建(.sha256 与 zip 同一份下载,防不了替换)。签 CI / release 产物时请传产出它的 run ID"
elif case "$SOURCE_RUN_ID" in *[!0-9]*) true ;; *) false ;; esac; then
    check SKIP "3b 来源" "--source-run-id 无效(见预检 0)"
elif [ "$ZIP_OK" -ne 1 ] || [ -z "$HEAD_COMMIT" ]; then
    check SKIP "3b 来源" "输入 zip 完整性或检出未通过,无从核对"
else
    p3b_err=""
    if ! command -v gh >/dev/null 2>&1; then
        p3b_err="gh 不在 PATH 上(来源核对用 GitHub CLI,需已 gh auth login)"
    elif ! run_info="$(gh api "repos/$UPLOAD_REPO/actions/runs/$SOURCE_RUN_ID" \
            --jq '[.repository.full_name, .head_repository.full_name, .path, .status, .conclusion, .head_sha, .event] | join(" ")' 2>&1)"; then
        p3b_err="读取 run $SOURCE_RUN_ID 失败:$run_info"
    else
        # 字段都不含空白(仓库名 / workflow 路径 / 枚举值 / sha),按空格切分即可
        read -r r_repo r_head_repo r_path r_status r_concl r_sha r_event <<< "$run_info"
        if [ "$r_repo" != "$UPLOAD_REPO" ] || [ "$r_head_repo" != "$UPLOAD_REPO" ]; then
            p3b_err="run $SOURCE_RUN_ID 属于 $r_repo(head 来自 $r_head_repo),不是 $UPLOAD_REPO 本仓库的构建"
        elif [ "$r_path" != ".github/workflows/ci.yml" ] && [ "$r_path" != ".github/workflows/release.yml" ]; then
            p3b_err="run $SOURCE_RUN_ID 的 workflow 是 '$r_path',只接受 ci.yml / release.yml 的产物"
        elif [ "$r_concl" != "success" ]; then
            p3b_err="run $SOURCE_RUN_ID 的结论是 '$r_status/$r_concl',只接受成功完成的构建"
        elif [ "$r_event" != "push" ] && [ "$r_event" != "workflow_dispatch" ]; then
            # pull_request 事件下 ci.yml 构建的是合并提交 refs/pull/N/merge,run 的 head_sha 却是 PR head:对上也不代表字节由
            # 当前检出构建。只认 push / workflow_dispatch(这两种事件构建的就是 head_sha)
            p3b_err="run $SOURCE_RUN_ID 的事件是 '$r_event':pull_request 构建的是合并提交,不是当前检出;只接受 push / workflow_dispatch 的 run(要签某个分支的件,对该分支 gh workflow run ci.yml --ref <分支> 再取它的 artifact)"
        elif [ "$r_sha" != "$HEAD_COMMIT" ]; then
            p3b_err="run $SOURCE_RUN_ID 构建的是 $r_sha,当前检出是 $HEAD_COMMIT:zip 与检出不是同一个 commit"
        else
            # 取回该 run 的 aax-unsigned-* artifact,其中同名 zip 必须与输入字节相同。ci.yml 6e / 8e(push / workflow_dispatch)与
            # release.yml 的 release / release-macos 都产出它(aax-unsigned-win64 / aax-unsigned-macos-arm64);签 tag 版本时传该 tag 的
            # release run ID(见 docs/release.md §7.3)。哪些 run 算合法来源,以上面几条判据为准
            PROV_DIR="$(mktemp -d "${TMPDIR:-/tmp}/synchain-aax-provenance.XXXXXX")"
            if ! dl_out="$(gh run download "$SOURCE_RUN_ID" -R "$UPLOAD_REPO" -p 'aax-unsigned-*' -D "$PROV_DIR" 2>&1)"; then
                p3b_err="gh run download $SOURCE_RUN_ID 失败(artifact 过期了?):$dl_out"
            else
                n_hits="$(find "$PROV_DIR" -type f -name "$ZIP_NAME" | wc -l | tr -d '[:space:]')"
                if [ "$n_hits" != "1" ]; then
                    p3b_err="run $SOURCE_RUN_ID 的 aax-unsigned-* artifact 里找到 $n_hits 个 $ZIP_NAME(应恰好 1 个)"
                else
                    run_zip="$(find "$PROV_DIR" -type f -name "$ZIP_NAME" -print -quit)"
                    run_hash="$(shasum -a 256 "$run_zip" | awk '{ print $1 }')"
                    if [ "$run_hash" != "$ACTUAL" ]; then
                        p3b_err="输入 zip($ACTUAL)与 run $SOURCE_RUN_ID 的 artifact($run_hash)字节不同:不是这次构建的产物,拒绝签名"
                    fi
                fi
            fi
            rm -rf "$PROV_DIR"
            PROV_DIR=""
        fi
    fi
    if [ -z "$p3b_err" ]; then
        check PASS "3b 来源" "run $SOURCE_RUN_ID($r_path,$r_event,head ${r_sha:0:7})的 artifact 与输入 zip 字节相同"
    else
        check FAIL "3b 来源" "$p3b_err"
    fi
fi

# ---------------------------------------------------------------- 预检 4:钥匙串身份
# TO-VALIDATE(V6):**不加 -v** —— 自签名身份未被信任时不会出现在 -v 列表里。不加 -v 时同一身份会在
# "Matching identities" 与 "Valid identities only" 两段各出现一次,按 SHA-1 去重后再数。
# 行形如:  1) 0123…ABCD "名字" [(CSSMERR_TP_NOT_TRUSTED)];名字取第一个引号到最后一个引号之间。
ids="$(security find-identity -p codesigning 2>/dev/null || true)"   # TO-VALIDATE(V6)
matches="$(printf '%s\n' "$ids" | awk -v want="$SIGNID" '
    $0 ~ /^[[:space:]]*[0-9]+\) [0-9A-F]+ "/ {
        hash = $2
        rest = substr($0, index($0, "\"") + 1)
        e = 0
        for (i = length(rest); i > 0; i--) if (substr(rest, i, 1) == "\"") { e = i; break }
        if (e == 0) next
        if (substr(rest, 1, e - 1) == want && !(hash in seen)) { seen[hash] = 1; print hash }
    }')"
n_ids=0
[ -z "$matches" ] || n_ids="$(printf '%s\n' "$matches" | wc -l | tr -d '[:space:]')"
if [ "$n_ids" = "1" ]; then
    check PASS "4 签名身份" "\"$SIGNID\"($matches)"
elif [ "$n_ids" = "0" ]; then
    check FAIL "4 签名身份" "钥匙串里没有名为 \"$SIGNID\" 的代码签名身份(security find-identity -p codesigning;名字须逐字相等)"
else
    check FAIL "4 签名身份" "钥匙串里有 $n_ids 个名为 \"$SIGNID\" 的代码签名身份,wraptool 无法区分:删掉多余的再签"
fi

# ---------------------------------------------------------------- 预检 5:wraptool
# PACE_FUSION_HOME:Windows 版 wraptool 6.0.1 没有它就报 "The PACE_FUSION_HOME environment variable is not defined"(实测);
# mac 版是否需要未实测(TO-VALIDATE),这里只提醒、不拦,并把 $PACE_FUSION_HOME/bin/wraptool 当第一个候选
if [ -n "${PACE_FUSION_HOME:-}" ]; then
    check INFO "5 PACE_FUSION_HOME" "$PACE_FUSION_HOME"
else
    check INFO "5 PACE_FUSION_HOME" "未设置(mac 版 wraptool 是否需要它未实测,TO-VALIDATE):wraptool 报它未定义时,装完签名工具新开终端;仍没有就重装签名工具"
fi
WT=""
WT_SRC=""
if [ -n "$WRAPTOOL_ARG" ]; then
    cand="$(abs_path "$WRAPTOOL_ARG")"
    if [ -f "$cand" ] && [ -x "$cand" ]; then
        WT="$cand"
        WT_SRC="--wraptool"
    else
        check FAIL "5a wraptool" "--wraptool 指向的文件不存在或不可执行:$cand"
    fi
elif [ -n "${PACE_FUSION_HOME:-}" ] && [ -f "${PACE_FUSION_HOME%/}/bin/wraptool" ] && [ -x "${PACE_FUSION_HOME%/}/bin/wraptool" ]; then
    WT="${PACE_FUSION_HOME%/}/bin/wraptool"
    WT_SRC="PACE_FUSION_HOME"
elif WT="$(command -v wraptool 2>/dev/null)"; then
    WT_SRC="PATH"
elif WT="$(find_wraptool_default)"; then
    WT_SRC="$WRAPTOOL_VERSIONS_DIR 下版本号最高的"   # TO-VALIDATE:mac 上的 v6 安装布局
else
    WT=""
    check FAIL "5a wraptool" "找不到 wraptool:\$PACE_FUSION_HOME/bin、PATH、$WRAPTOOL_VERSIONS_DIR/<版本>/bin 都没有(TO-VALIDATE:mac 上的安装路径以实际为准)。先装好 PACE 签名工具,再重试或用 --wraptool <path> 指定"
fi
if [ -n "$WT" ]; then check PASS "5a wraptool" "$WT(来自 $WT_SRC)"; fi

if [ -n "$WT" ]; then
    # Windows 6.0.1 实测:`help` 打印全部选项,`help sign` 在 v6 里不合法(exit 9)。mac 版照搬(TO-VALIDATE);
    # 不看退出码,只看输出里有没有本次要用的 flag
    echo "> wraptool help"
    help_out="$("$WT" help 2>&1 || true)"
    need="$(required_flags)"
    missing=""
    no_arg=""
    for f in $need; do
        grep -Eq -- "(^|[^[:alnum:]_-])${f}([^[:alnum:]_-]|\$)" <<< "$help_out" || missing="$missing $f"
        # 本脚本给它传值的 flag,help 的选项表里要标着带值(`-I [ --signid ] arg` / `--pswd-no-save arg`)
        if [ "$f" != "--verbose" ]; then
            grep -Eq -- "(^|[^[:alnum:]_-])${f}( *\\])? +arg([^[:alnum:]_-]|\$)" <<< "$help_out" || no_arg="$no_arg $f"
        fi
    done
    if [ -n "$missing" ]; then
        check FAIL "5b wraptool flag" "「wraptool help」的输出里没有${missing}:wraptool 版本与本脚本不符(本脚本按 wraptool 6.0.1 编写)"
    elif [ -n "$no_arg" ]; then
        check FAIL "5b wraptool flag" "「wraptool help」里${no_arg} 没有标成带值的选项(arg),本脚本却要给它传值:wraptool 版本与本脚本不符"
    else
        check PASS "5b wraptool flag" "$need"
    fi
else
    check SKIP "5b wraptool flag" "wraptool 不可用"
fi

# ---------------------------------------------------------------- 预检 6:iLok(只提醒)
check INFO "6 iLok" "签名需要插着带签名授权的 iLok(或已激活 iLok Cloud 会话)并运行 iLok License Manager;本脚本不硬检,缺了 wraptool 自己会报错(TO-VALIDATE:报错文案)"

# ---------------------------------------------------------------- 预检 7:解压 + 输入件确实未签名
IN_BUNDLE=""
OUT_BUNDLE=""
BUNDLE_OK=0
if [ "$ZIP_OK" -eq 1 ]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/synchain-aax-sign.XXXXXX")"
    mkdir -p "$WORK/in" "$WORK/out"
    IN_BUNDLE="$WORK/in/$AAX_NAME"
    OUT_BUNDLE="$WORK/out/$AAX_NAME"
    p7_err=""
    if ! ditto -x -k "$ZIP" "$WORK/in"; then
        p7_err="ditto -x -k 解压失败"
    elif [ ! -d "$IN_BUNDLE" ]; then
        p7_err="zip 根目录下没有 '$AAX_NAME'"
    elif [ ! -x "$IN_BUNDLE/Contents/MacOS/$EXE_NAME" ]; then
        p7_err="bundle 缺 Contents/MacOS/$EXE_NAME 或它不可执行"
    else
        # arm64-only:与 package-aax-macos.sh 的 file 断言同口径
        # file -b:只看类型描述,不让带临时目录名的路径参与 arm64 / x86_64 的匹配
        archs="$(file -b "$IN_BUNDLE"/Contents/MacOS/* || true)"
        if ! grep -q 'arm64' <<< "$archs"; then
            p7_err="主体可执行文件不是 arm64:$archs"
        elif grep -q 'x86_64' <<< "$archs"; then
            p7_err="主体可执行文件含 x86_64 切片(v1 只出 arm64)"
        else
            sinfo="$(codesign -dv --verbose=4 "$IN_BUNDLE" 2>&1 || true)"
            if grep -q '^Authority=' <<< "$sinfo"; then
                p7_err="输入 bundle 已带签名 Authority(已签过或被改过),拒绝:$(grep '^Authority=' <<< "$sinfo" | head -n 1)"
            fi
        fi
    fi
    if [ -z "$p7_err" ]; then
        check PASS "7a 输入 bundle" "已解压到 $WORK/in;arm64-only;无签名 Authority(只有链接器的 ad-hoc 或无签名)"
        BUNDLE_OK=1
    else
        check FAIL "7a 输入 bundle" "$p7_err"
    fi

    if [ "$BUNDLE_OK" -eq 1 ] && [ -n "$WT" ]; then
        # TO-VALIDATE(mac):verify 能否直接收 bundle 目录(Windows 6.0.1 实测只收文件,mac 上 help 示例给的是 .app),
        # 以及未签名件的输出文案(Windows 实测:未签名 DLL 退出码 2,输出 "The architecture is NOT signed")。
        # 只看退出码非零会把别的失败(PACE_FUSION_HOME 缺失、--in 不被接受、参数错误)当成「未签名」,所以与 Windows
        # 同口径:非零且输出里有 NOT signed(区分大小写,「not signed in」一类的未登录报错不算)才 PASS,文案对不上就 FAIL
        # (实测后按真实文案改这里)
        echo "> wraptool verify --in $(fmt_cmd "$IN_BUNDLE")"
        v_rc=0
        v_raw="$("$WT" verify --in "$IN_BUNDLE" 2>&1)" || v_rc=$?
        v_out="$(printf '%s\n' "$v_raw" | redact_stream "$ACCOUNT" "$WCGUID" "$CUSTOMER_NUMBER")"
        if [ "$v_rc" -eq 0 ]; then
            check FAIL "7b wraptool verify" "wraptool verify 对输入 bundle 返回成功 —— 它已经签过(重签会报错),中止"
        elif ! grep -q 'NOT signed' <<< "$v_out"; then
            check FAIL "7b wraptool verify" "wraptool verify 失败(exit $v_rc),但输出里没有 NOT signed,失败原因不是「未签名」:$(printf '%s\n' "$v_out" | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' '|')"
        else
            check PASS "7b wraptool verify" "按预期失败(exit $v_rc,输出 NOT signed):输入件未签名"
        fi
    elif [ "$BUNDLE_OK" -eq 1 ]; then
        check SKIP "7b wraptool verify" "wraptool 不可用"
    else
        check SKIP "7b wraptool verify" "输入 bundle 未就绪"
    fi
else
    check SKIP "7a 输入 bundle" "输入 zip 未通过完整性校验,不解压"
    check SKIP "7b wraptool verify" "输入 zip 未通过完整性校验"
fi

SIGNED_ZIP=""
[ -z "$VER" ] || SIGNED_ZIP="$OUT_DIR/SynchainBridge-AAX-v$VER-macos-arm64.zip"

# 签名命令的打码版(回显用);真实参数(WT_ARGS)只在签名那一步临时拼出,两处的 flag 顺序保持一致
SHOW_ARGS=(sign --verbose)                        # TO-VALIDATE(待首次真签名):--verbose 是否回显收到的参数
if [ -n "$ACCOUNT" ]; then SHOW_ARGS+=(--account '****'); fi
SHOW_ARGS+=(--signid "$SIGNID")
if [ -n "$WCGUID" ]; then
    SHOW_ARGS+=(--wcguid '****')
else
    SHOW_ARGS+=(--customernumber '****' --customername "$CUSTOMER_NAME" --productname "$PRODUCT_NAME")
fi
if [ "$PROMPT_AP" -eq 1 ]; then SHOW_ARGS+=(--pswd-no-save '****'); fi
SHOW_ARGS+=(--in "${IN_BUNDLE:-<work>/in/$AAX_NAME}"       # TO-VALIDATE(mac):给 bundle 目录还是内层可执行文件
            --out "${OUT_BUNDLE:-<work>/out/$AAX_NAME}")   # TO-VALIDATE(mac):能否指向新路径
if [ "$EXTRA_N" -gt 0 ]; then SHOW_ARGS+=("${EXTRA[@]}"); fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "[DryRun] 签名计划(未执行):"
    if [ -n "$SOURCE_RUN_ID" ]; then
        echo "  -) 来源已按 run $SOURCE_RUN_ID 核对(见预检 3b)"
    else
        echo "  -) 未给 --source-run-id:来源未核对(只验了完整性)"
    fi
    if [ "$PROMPT_AP" -eq 1 ]; then
        echo "  0) read -s 读 PACE 账号口令,经 --pswd-no-save 传(不写进 wraptool 钥匙串;签名那几秒会出现在 wraptool 进程命令行里,签名期间不要让他人登录本机)"
    else
        echo "  0) 不传账号口令:wraptool 用它钥匙串里存过的口令(--wcguid 方式要连 PACE 服务器;没存过就先手动 sync 一次,见 docs/release.md §7.2)"
    fi
    echo "  1) wraptool $(fmt_cmd "${SHOW_ARGS[@]}")"
    echo "     (第一次用该身份签名可能弹出钥匙串授权框,需要人点;--extrasigningoptions \"--timestamp\" 默认不加,TO-VALIDATE V5)"
    echo "  2) 后检:wraptool verify --verbose --in <out>;codesign --verify --deep --strict;Authority= \"$SIGNID\" 且非 ad-hoc"
    echo "  3) package-aax-macos.sh --mode signed --version ${VER:-<版本>} --source-ref ${SOURCE_REF:-<source ref>} --bundle-path <out> --out-dir $OUT_DIR"
    echo "  4) 回读:ditto -x -k 解到新临时目录,复验 wraptool verify 与 codesign"
    if [ "$IS_CI" -eq 1 ]; then
        echo "  5) 版本 $VER 是 CI 预发布件,没有对应 Release:只打印提示,不给上传命令"
    else
        echo "  5) 打印(不执行):gh release upload v${VER:-<版本>} <zip> <zip>.sha256 --repo $UPLOAD_REPO"
    fi

    # 用打包脚本自己的 --dry-run 校验「版本 + source ref」组合会被 signed 模式接受(它不碰 bundle、不产出文件)
    if [ -n "$VER" ] && [ -n "$SOURCE_REF" ]; then
        echo ""
        echo "[DryRun] package-aax-macos.sh --mode signed --dry-run:"
        if bash "$SCRIPT_DIR/package-aax-macos.sh" --mode signed --version "$VER" --source-ref "$SOURCE_REF" \
                --bundle-path "${OUT_BUNDLE:-${TMPDIR:-/tmp}/$AAX_NAME}" --out-dir "$OUT_DIR" --dry-run; then
            check PASS "8 打包计划" "package-aax-macos.sh --mode signed --dry-run 接受该版本与 source ref"
        else
            check FAIL "8 打包计划" "package-aax-macos.sh --dry-run 失败"
        fi
    else
        check SKIP "8 打包计划" "版本或 source ref 未确定"
    fi

    echo ""
    echo "[DryRun] 预检汇总:"
    for line in "${CHECK_LOG[@]}"; do echo "  $line"; done
    SUCCEEDED=1   # dry-run 的临时目录一律删
    if [ "$FAILS" -gt 0 ]; then
        echo "[DryRun] 结论:$FAILS 项 FAIL —— 真签名会在第一项 FAIL 处中止。未读口令、未调用 wraptool sign、未产出文件。" >&2
        exit 1
    fi
    if [ "$WARNS" -gt 0 ]; then
        echo "[DryRun] 结论:预检全部通过(另有 $WARNS 项 WARN,真签名前处理)。未读口令、未调用 wraptool sign、未产出文件。"
    else
        echo "[DryRun] 结论:预检全部通过。未读口令、未调用 wraptool sign、未产出文件。"
    fi
    exit 0
fi

# ================================================================ 签名
if [ "$PROMPT_AP" -eq 1 ]; then
    [ -r /dev/tty ] || die "读取 PACE 账号口令需要交互终端"
    IFS= read -r -s -p "PACE 账号口令(经 --pswd-no-save 传,不存钥匙串): " AP < /dev/tty
    echo ""
fi
WT_ARGS=(sign --verbose)
if [ -n "$ACCOUNT" ]; then WT_ARGS+=(--account "$ACCOUNT"); fi
WT_ARGS+=(--signid "$SIGNID")
if [ -n "$WCGUID" ]; then
    WT_ARGS+=(--wcguid "$WCGUID")
else
    WT_ARGS+=(--customernumber "$CUSTOMER_NUMBER" --customername "$CUSTOMER_NAME" --productname "$PRODUCT_NAME")
fi
if [ "$PROMPT_AP" -eq 1 ]; then WT_ARGS+=(--pswd-no-save "$AP"); fi
WT_ARGS+=(--in "$IN_BUNDLE"      # TO-VALIDATE(mac):给 bundle 目录还是内层可执行文件
          --out "$OUT_BUNDLE")   # TO-VALIDATE(mac):能否指向新路径
# TO-VALIDATE(V5):--extrasigningoptions "--timestamp" 默认不加,需要时经 --extra-arg 透传
if [ "$EXTRA_N" -gt 0 ]; then WT_ARGS+=("${EXTRA[@]}"); fi
echo "> wraptool $(fmt_cmd "${SHOW_ARGS[@]}")"
echo "(第一次用该身份签名可能弹出钥匙串授权框,需要人点「始终允许」或「允许」)"
# TO-VALIDATE(待首次真签名):--verbose 是否回显收到的参数未知 —— 输出经 redact_stream 逐行打码再显示
set +e
"$WT" "${WT_ARGS[@]}" 2>&1 | redact_stream "$AP" "$ACCOUNT" "$WCGUID" "$CUSTOMER_NUMBER"
sign_rcs=("${PIPESTATUS[@]}")
set -e
sign_rc="${sign_rcs[0]}"
AP=""
WT_ARGS=()
[ "$sign_rc" -eq 0 ] || die "wraptool sign 失败(exit $sign_rc)"
[ -d "$OUT_BUNDLE" ] || die "wraptool sign 返回 0,但没有产出 $OUT_BUNDLE(TO-VALIDATE(mac):--out 语义)"

# ================================================================ 后检
assert_signed_bundle() {   # assert_signed_bundle <bundle> <标签>
    local b="$1" label="$2" info
    echo "> wraptool verify --verbose --in $(fmt_cmd "$b")"
    set +e
    # TO-VALIDATE(待首次真签名):已签名件 verify 的退出码,这里按 0 判通过
    "$WT" verify --verbose --in "$b" 2>&1 | redact_stream "$ACCOUNT" "$WCGUID" "$CUSTOMER_NUMBER"
    local rcs=("${PIPESTATUS[@]}")
    set -e
    [ "${rcs[0]}" -eq 0 ] || die "$label:wraptool verify 失败(exit ${rcs[0]})"
    codesign --verify --deep --strict --verbose=2 "$b" || die "$label:codesign --verify --deep --strict 失败"
    info="$(codesign -dv --verbose=4 "$b" 2>&1 || true)"
    if grep -q 'Signature=adhoc' <<< "$info"; then die "$label:只有 ad-hoc 签名"; fi
    awk -v want="Authority=$SIGNID" '$0 == want { hit = 1 } END { exit !hit }' <<< "$info" \
        || die "$label:codesign -dv 的 Authority= 里没有 \"$SIGNID\""
    echo "$label OK:Authority=$SIGNID,codesign --verify --deep --strict 通过"
}
assert_signed_bundle "$OUT_BUNDLE" "后检"

# 打包:signed 模式会再做一遍签名断言与 zip 回读比对字节
bash "$SCRIPT_DIR/package-aax-macos.sh" --mode signed --version "$VER" --source-ref "$SOURCE_REF" \
    --bundle-path "$OUT_BUNDLE" --out-dir "$OUT_DIR" || die "package-aax-macos.sh --mode signed 失败"
[ -f "$SIGNED_ZIP" ] || die "打包后找不到 $SIGNED_ZIP"
PACKAGED=1   # 从这里起失败,on_exit 删掉本次的发行名 zip / .sha256(打包脚本自己的失败路径由它自己清理)

# 回读:产出的 zip 解到新临时目录,再跑一轮 wraptool 与 codesign 验证(发出去的字节还带着签名)
mkdir -p "$WORK/readback"
ditto -x -k "$SIGNED_ZIP" "$WORK/readback"
assert_signed_bundle "$WORK/readback/$AAX_NAME" "回读"

echo ""
echo "签名完成:$SIGNED_ZIP"
echo "          $SIGNED_ZIP.sha256"
[ -n "$SOURCE_RUN_ID" ] || echo "注意:本次未给 --source-run-id,输入 zip 的来源没有核对过(只验了完整性)" >&2
if [ "$IS_CI" -eq 1 ]; then
    echo "版本 $VER 是 CI 预发布件,没有对应的 Release tag:只用于本机 / Pro Tools 实测,不要上传。"
else
    # TO-VALIDATE(V11):gh release upload 能否直接传到 draft Release
    echo "确认无误后手动上传到 draft Release(本脚本不自动执行):"
    echo "  gh release upload v$VER \"$SIGNED_ZIP\" \"$SIGNED_ZIP.sha256\" --repo $UPLOAD_REPO"
fi
SUCCEEDED=1
