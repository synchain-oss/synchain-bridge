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
# 流程(任一步失败即 exit 1):
#   预检 0 参数:--wcguid 是 GUID;--extra-arg 不含口令、不覆盖本脚本管理的 flag
#   预检 1 完整性:输入 zip 同目录的 .sha256 逐字节等于 "<小写 hash><两个空格><zip 名>\n"(shasum -a 256)。
#          只防损坏 / 下载不完整 —— .sha256 与 zip 是同一份下载,换得了 zip 就换得了 .sha256,防不了替换
#   预检 2 从文件名解析版本:SynchainBridge-AAX-v<版本>-macos-arm64-UNSIGNED.zip
#   预检 3 检出对应该版本:-ci.<sha> 版本要求 HEAD 以该 sha 开头(source ref = 完整 HEAD);其余版本要求 HEAD 上有
#          tag v<版本>;LICENSE / THIRD-PARTY-NOTICES.md / LICENSES / scripts 无未提交改动
#   预检 3b 来源(--source-run-id):该 run 属于本仓库(非 fork)、是 ci.yml / release.yml、结论 success、head_sha = HEAD;
#          再用 gh run download 取回它的 aax-unsigned-* artifact,其中同名 zip 必须与输入 zip 字节相同。
#          这是「哪些字节会被盖上签名」的信任根;不给 --source-run-id 只记 WARN(本地自建件没有 run 可核对)
#   预检 4 security find-identity -p codesigning(不加 -v,TO-VALIDATE V6)里名字与 --signid 完全相等的身份恰好 1 个
#   预检 5 wraptool 可执行,`wraptool help sign` 列出所需 flag(TO-VALIDATE)
#   预检 6 iLok 只提醒不硬检
#   预检 7 ditto -x -k 解到全新临时目录(保留可执行位):bundle 存在、arm64-only、没有签名 Authority,
#          且 `wraptool verify` 必须失败(已签过的件重签会报错)
#   签名   wraptool sign --verbose --account --wcguid --signid --in --out [--extra-arg ...](TO-VALIDATE);
#          第一次签名可能弹出钥匙串授权框,需要人点;回显的命令里 PACE 账号 / wcguid / 口令一律打码为 ****;
#          wraptool --verbose 是否回显收到的参数未知(TO-VALIDATE V1),它的输出逐行把这些值字面替换成 **** 后再显示
#   后检   wraptool verify;codesign --verify --deep --strict;codesign -dv 的 Authority= 等于 --signid 且不是 ad-hoc;
#          调 package-aax-macos.sh --mode signed 打包;解压回读后再跑一轮 wraptool 与 codesign 验证;
#          最后只**打印** gh release upload 命令,不自动执行
# 成功即删除临时工作目录;失败则保留并打印路径(里面只有 bundle,没有秘密)。
#
# --dry-run:跑全部预检(第 7 步的解压也在临时目录里做,结束即删)并汇总,打印签名计划与 package-aax-macos.sh
# --dry-run 的输出;不读口令、不调用 wraptool sign、不产出任何文件。
#
# TO-VALIDATE:所有 wraptool 子命令 / flag / 默认安装路径都来自公开资料,Eden 版本不同可能有差异;所有者拿到
# PACE 工具后逐条核对(V1 子命令与 flag、V2 是否需要 --password、V5 --extrasigningoptions "--timestamp" 对自签名 /
# Apple Development 身份是否可用(默认不加)、V6 find-identity 不加 -v 的行为、V11 上传到 draft、V12 默认安装路径),
# 核对完删掉对应标记。
#
# 绝不 set -x:xtrace 会把账号与口令(若用 --prompt-account-password)逐行回显进终端 / 日志。
#
# 用法:
#   bash scripts/sign-aax-macos.sh --unsigned-zip <SynchainBridge-AAX-v*-macos-arm64-UNSIGNED.zip>
#        --account <PACE 账号> --wcguid <GUID> --signid "<钥匙串身份名>" [--source-run-id <run ID>]
#        [--out-dir dist/aax-signed] [--wraptool <path>] [--extra-arg <arg>]... [--prompt-account-password] [--dry-run]

set -euo pipefail
set +x

die() {
    echo "sign-aax-macos: FAIL —— $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
用法: sign-aax-macos.sh --unsigned-zip <zip> --account <PACE 账号> --wcguid <GUID> --signid "<钥匙串身份名>" [选项]
  --unsigned-zip <path>      必填:SynchainBridge-AAX-v<版本>-macos-arm64-UNSIGNED.zip,同目录须有 .sha256
  --account <name>           必填:PACE 账号(日志里打码)
  --wcguid <GUID>            必填:PACE wrap 配置 GUID(日志里打码)
  --signid <name>            必填:钥匙串里代码签名身份的完整名字(security find-identity -p codesigning 列出的引号内文字)
  --source-run-id <id>       产出该 zip 的 ci / release run 的 ID:给了就核对来源(需 gh 已登录),不给只记 WARN
  --out-dir <path>           输出目录;相对路径按仓库根解析,默认 dist/aax-signed
  --wraptool <path>          wraptool 路径;默认先找 PATH,再找 Eden 默认安装路径(TO-VALIDATE)
  --extra-arg <arg>          原样透传给 wraptool sign,可重复(TO-VALIDATE);不得含 password
  --prompt-account-password  交互读入 PACE 账号口令并传 --password(V2:是否需要,TO-VALIDATE)
  --dry-run                  只跑预检并打印计划:不读口令、不调用 wraptool sign、不产出文件
USAGE
}

UNSIGNED_ZIP=""
ACCOUNT=""
WCGUID=""
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
[ -n "$ACCOUNT" ]      || { usage >&2; die "--account is required"; }
[ -n "$WCGUID" ]       || { usage >&2; die "--wcguid is required"; }
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
WRAPTOOL_DEFAULT="/Applications/PACEAntiPiracy/Eden/Fusion/Versions/5/bin/wraptool"   # TO-VALIDATE(V12)
REQUIRED_FLAGS="--account --wcguid --signid --in --out"                               # TO-VALIDATE(V1)

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
AP=""
on_exit() {
    local rc=$?
    AP=""
    [ -z "${PROV_DIR:-}" ] || rm -rf "$PROV_DIR"
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
[[ "$WCGUID" =~ $guid_re ]] || p0_err="--wcguid 不是 GUID(期望 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,不带花括号)"
if [ "$EXTRA_N" -gt 0 ]; then
    for a in "${EXTRA[@]}"; do
        lower="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            *password*) p0_err="--extra-arg 不得含口令类参数('$a'):口令只经交互读入,不进参数" ;;
        esac
        # 与 Windows 侧 -match 同口径:不区分大小写(--password 已由上面的 *password* 覆盖)
        case "$lower" in
            --account|--account=*|--wcguid|--wcguid=*|--signid|--signid=*|--in|--in=*|--out|--out=*)
                p0_err="--extra-arg 不得重复本脚本管理的 flag('$a')" ;;
        esac
    done
fi
case "$SOURCE_RUN_ID" in
    *[!0-9]*) p0_err="--source-run-id 应为纯数字的 workflow run ID:'$SOURCE_RUN_ID'" ;;
esac
if [ -z "$p0_err" ]; then check PASS "0 参数" "wcguid 格式正确;extra-arg $EXTRA_N 项"; else check FAIL "0 参数" "$p0_err"; fi

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
        elif [ "$r_sha" != "$HEAD_COMMIT" ]; then
            p3b_err="run $SOURCE_RUN_ID 构建的是 $r_sha,当前检出是 $HEAD_COMMIT:zip 与检出不是同一个 commit"
        else
            # 取回该 run 的 aax-unsigned-* artifact(ci.yml / release.yml 的命名都以此开头),其中同名 zip 必须与输入字节相同
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
WT=""
if [ -n "$WRAPTOOL_ARG" ]; then
    cand="$(abs_path "$WRAPTOOL_ARG")"
    if [ -f "$cand" ] && [ -x "$cand" ]; then
        WT="$cand"
        check PASS "5a wraptool" "$WT"
    else
        check FAIL "5a wraptool" "--wraptool 指向的文件不存在或不可执行:$cand"
    fi
elif WT="$(command -v wraptool 2>/dev/null)"; then
    check PASS "5a wraptool" "$WT"
elif [ -x "$WRAPTOOL_DEFAULT" ]; then
    WT="$WRAPTOOL_DEFAULT"
    check PASS "5a wraptool" "$WT"
else
    WT=""
    check FAIL "5a wraptool" "找不到 wraptool:PATH 里没有,默认路径 $WRAPTOOL_DEFAULT 也不存在(TO-VALIDATE:Eden 默认安装路径以实际版本为准)。先装好 PACE Eden 签名工具,再重试或用 --wraptool <path> 指定"
fi

if [ -n "$WT" ]; then
    # TO-VALIDATE(V1):子命令写法 `help sign`;不看退出码(有的工具打印帮助后返回非零),只看输出里的 flag
    echo "> wraptool help sign"
    help_out="$("$WT" help sign 2>&1 || true)"   # TO-VALIDATE(V1)
    need="$REQUIRED_FLAGS"
    if [ "$PROMPT_AP" -eq 1 ]; then need="$need --password"; fi   # TO-VALIDATE(V2)
    missing=""
    for f in $need; do
        grep -Eq -- "(^|[^[:alnum:]_-])${f}([^[:alnum:]_-]|\$)" <<< "$help_out" || missing="$missing $f"
    done
    if [ -z "$missing" ]; then
        check PASS "5b wraptool flag" "$need"
    else
        check FAIL "5b wraptool flag" "Eden 版本 flag 不符,按 TO-VALIDATE 更新脚本:「wraptool help sign」的输出里没有${missing}"
    fi
else
    check SKIP "5b wraptool flag" "wraptool 不可用"
fi

# ---------------------------------------------------------------- 预检 6:iLok(只提醒)
check INFO "6 iLok" "签名需要插着 iLok(或已激活 iLok Cloud 会话)并运行 iLok License Manager;本脚本不硬检,缺了 wraptool 自己会报错(TO-VALIDATE:报错文案)"

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
        # TO-VALIDATE(V1):verify 的语法,以及「未签名 bundle → 非零退出」这一约定。语法若写错这里也会是非零
        # (假 PASS),但签名后的后检要求 verify 返回 0,语法错误会在那里暴露。
        echo "> wraptool verify --in $(fmt_cmd "$IN_BUNDLE")"
        if "$WT" verify --in "$IN_BUNDLE" >/dev/null 2>&1; then   # TO-VALIDATE(V1)
            check FAIL "7b wraptool verify" "wraptool verify 对输入 bundle 返回成功 —— 它已经签过(重签会报错),中止"
        else
            check PASS "7b wraptool verify" "按预期失败:输入件未签名"
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

# 签名命令的打码版(回显用);真实参数只在签名那一步临时拼出
SHOW_ARGS=(sign --verbose                         # TO-VALIDATE(V1)
           --account '****' --wcguid '****'       # TO-VALIDATE(V1)
           --signid "$SIGNID"                     # TO-VALIDATE(V1)
           --in "${IN_BUNDLE:-<work>/in/$AAX_NAME}"     # TO-VALIDATE(V1):给 bundle 目录还是内层可执行文件
           --out "${OUT_BUNDLE:-<work>/out/$AAX_NAME}") # TO-VALIDATE(V1):能否指向新路径
if [ "$PROMPT_AP" -eq 1 ]; then SHOW_ARGS+=(--password '****'); fi   # TO-VALIDATE(V2)
if [ "$EXTRA_N" -gt 0 ]; then SHOW_ARGS+=("${EXTRA[@]}"); fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "[DryRun] 签名计划(未执行):"
    if [ -n "$SOURCE_RUN_ID" ]; then
        echo "  -) 来源已按 run $SOURCE_RUN_ID 核对(见预检 3b)"
    else
        echo "  -) 未给 --source-run-id:来源未核对(只验了完整性)"
    fi
    if [ "$PROMPT_AP" -eq 1 ]; then echo "  0) read -s 读 PACE 账号口令(--password,TO-VALIDATE V2)"; fi
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
    IFS= read -r -s -p "PACE 账号口令: " AP < /dev/tty   # TO-VALIDATE(V2)
    echo ""
fi
WT_ARGS=(sign --verbose                       # TO-VALIDATE(V1)
         --account "$ACCOUNT"                 # TO-VALIDATE(V1)
         --wcguid "$WCGUID"                   # TO-VALIDATE(V1)
         --signid "$SIGNID"                   # TO-VALIDATE(V1)
         --in "$IN_BUNDLE"                    # TO-VALIDATE(V1):给 bundle 目录还是内层可执行文件
         --out "$OUT_BUNDLE")                 # TO-VALIDATE(V1):能否指向新路径
if [ "$PROMPT_AP" -eq 1 ]; then WT_ARGS+=(--password "$AP"); fi   # TO-VALIDATE(V2)
# TO-VALIDATE(V5):--extrasigningoptions "--timestamp" 默认不加,需要时经 --extra-arg 透传
if [ "$EXTRA_N" -gt 0 ]; then WT_ARGS+=("${EXTRA[@]}"); fi
echo "> wraptool $(fmt_cmd "${SHOW_ARGS[@]}")"
echo "(第一次用该身份签名可能弹出钥匙串授权框,需要人点「始终允许」或「允许」)"
# TO-VALIDATE(V1):--verbose 是否回显收到的参数未知 —— 输出逐行把口令 / 账号 / wcguid 字面替换成 **** 再显示
redact_stream() {
    local line s
    while IFS= read -r line || [ -n "$line" ]; do
        for s in "$@"; do
            if [ -n "$s" ]; then line="${line//"$s"/****}"; fi   # 引号内的模式按字面匹配,不当通配
        done
        printf '%s\n' "$line"
    done
}
set +e
"$WT" "${WT_ARGS[@]}" 2>&1 | redact_stream "$AP" "$ACCOUNT" "$WCGUID"
sign_rcs=("${PIPESTATUS[@]}")
set -e
sign_rc="${sign_rcs[0]}"
AP=""
WT_ARGS=()
[ "$sign_rc" -eq 0 ] || die "wraptool sign 失败(exit $sign_rc)"
[ -d "$OUT_BUNDLE" ] || die "wraptool sign 返回 0,但没有产出 $OUT_BUNDLE(TO-VALIDATE:--out 语义)"

# ================================================================ 后检
assert_signed_bundle() {   # assert_signed_bundle <bundle> <标签>
    local b="$1" label="$2" info
    echo "> wraptool verify --verbose --in $(fmt_cmd "$b")"
    set +e
    "$WT" verify --verbose --in "$b" 2>&1 | redact_stream "$ACCOUNT" "$WCGUID"   # TO-VALIDATE(V1):语法与退出码
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
