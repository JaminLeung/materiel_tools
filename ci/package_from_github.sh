#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GITHUB_REPO="${GITHUB_REPO:-https://github.com/JaminLeung/materiel_tools.git}"
GIT_BRANCH="${GIT_BRANCH:-dev_2.8.0}"
BUILD_ENV="${BUILD_ENV:-ox_tencent}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR}"
WORK_DIR="${WORK_DIR:-}"
LOCAL_ENV_FILE="${LOCAL_ENV_FILE:-}"
USE_LOCAL_ENV_OVERLAY=true
ALLOW_PLACEHOLDER_CONFIG=false
GIT_PROXY="${GIT_PROXY:-}"
GIT_HTTP_VERSION="${GIT_HTTP_VERSION:-HTTP/1.1}"
CURL_PROXY="${CURL_PROXY:-}"
KEEP_WORK_DIR=false
SPARSE_PATH="datakit-automation"

usage() {
    cat <<'EOF'
用法:
  ./ci/package_from_github.sh [选项]

默认行为:
  - 从 GitHub 只拉取 JaminLeung/materiel_tools 的 dev_2.8.0 分支最新 HEAD
  - 使用 sparse checkout 只检出 datakit-automation 目录
  - 只保留 ox_tencent 环境配置
  - 如果本地存在 datakit-automation/config/env/ox_tencent.sh，则覆盖到临时克隆目录用于本地打包
  - 只在本地生成安装包，不提交、不 push

选项:
  --repo <URL>                Git 仓库地址
  --branch <BRANCH>           Git 分支，默认 dev_2.8.0
  --env <ENV>                 环境名，默认 ox_tencent
  --output-dir <DIR>          输出目录，默认 ci
  --work-dir <DIR>            临时工作目录，默认 mktemp
  --local-env-file <FILE>     本地真实环境配置文件路径
  --no-local-env-overlay      不覆盖本地真实环境配置，直接使用 GitHub 中的配置
  --allow-placeholder-config  允许配置文件中出现 __REPLACE_ME__ 占位符
  --git-proxy <PROXY>         Git HTTP 代理，例如 socks5h://127.0.0.1:18080
  --curl-proxy <PROXY>        curl 下载代理，例如 socks5h://127.0.0.1:18080
  --keep-work-dir             保留临时工作目录，便于排查
  -h, --help                  显示帮助

环境变量:
  GITHUB_REPO, GIT_BRANCH, BUILD_ENV, OUTPUT_DIR, WORK_DIR, LOCAL_ENV_FILE,
  GIT_PROXY, GIT_HTTP_VERSION, CURL_PROXY
EOF
}

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            GITHUB_REPO="${2:?缺少 --repo 参数值}"
            shift 2
            ;;
        --branch)
            GIT_BRANCH="${2:?缺少 --branch 参数值}"
            shift 2
            ;;
        --env)
            BUILD_ENV="${2:?缺少 --env 参数值}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?缺少 --output-dir 参数值}"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="${2:?缺少 --work-dir 参数值}"
            shift 2
            ;;
        --local-env-file)
            LOCAL_ENV_FILE="${2:?缺少 --local-env-file 参数值}"
            shift 2
            ;;
        --no-local-env-overlay)
            USE_LOCAL_ENV_OVERLAY=false
            shift
            ;;
        --allow-placeholder-config)
            ALLOW_PLACEHOLDER_CONFIG=true
            shift
            ;;
        --git-proxy)
            GIT_PROXY="${2:?缺少 --git-proxy 参数值}"
            shift 2
            ;;
        --curl-proxy)
            CURL_PROXY="${2:?缺少 --curl-proxy 参数值}"
            shift 2
            ;;
        --keep-work-dir)
            KEEP_WORK_DIR=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "未知参数: $1"
            ;;
    esac
done

need_cmd git
need_cmd curl
need_cmd gzip
need_cmd tar
need_cmd python3

OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_CONFIG="$SCRIPT_DIR/build_config.json"
[[ -f "$BUILD_CONFIG" ]] || die "找不到构建配置: $BUILD_CONFIG"

if [[ -z "$LOCAL_ENV_FILE" ]]; then
    LOCAL_ENV_FILE="$REPO_ROOT/datakit-automation/config/env/${BUILD_ENV}.sh"
fi

if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/datakit_pkg_${BUILD_ENV}.XXXXXX")"
else
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    WORK_DIR="$(cd "$WORK_DIR" && pwd)"
fi

cleanup() {
    if [[ "$KEEP_WORK_DIR" == "true" ]]; then
        warn "保留临时目录: $WORK_DIR"
    else
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

git_cmd=(git)
if [[ -n "$GIT_PROXY" ]]; then
    git_cmd=(git -c "http.proxy=$GIT_PROXY")
fi

curl_cmd=(curl -fL --connect-timeout 20 --speed-time 45 --speed-limit 1024 --retry 3 --retry-all-errors --retry-delay 2 --silent --show-error)
if [[ -n "$CURL_PROXY" ]]; then
    curl_cmd+=(--proxy "$CURL_PROXY")
fi

json_value() {
    local key="$1"
    python3 - "$BUILD_CONFIG" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

value = data
for part in sys.argv[2].split("."):
    value = value[part]

if isinstance(value, list):
    for item in value:
        print(item)
else:
    print(value)
PY
}

expected_length() {
    local url="$1"
    "${curl_cmd[@]}" -I --max-time 30 "$url" |
        awk 'tolower($1)=="content-length:" {gsub(/\r/,"",$2); v=$2} END{print v}'
}

gzip_check_if_needed() {
    local file="$1"
    if [[ "$file" == *.tar.gz ]]; then
        gzip -t "$file"
    fi
}

download_with_resume() {
    local url="$1"
    local target_dir="$2"
    local name
    local target
    local expected
    local current
    local attempt

    name="${url##*/}"
    target="$target_dir/$name"
    expected="$(expected_length "$url")"
    [[ -n "$expected" ]] || die "无法获取 Content-Length: $url"

    log "下载物料: $name expected=${expected}"

    if [[ -f "$target" ]]; then
        current="$(stat -f '%z' "$target" 2>/dev/null || stat -c '%s' "$target")"
        if [[ "$current" -gt "$expected" ]]; then
            warn "发现超大残留文件，删除重下: $name current=${current}"
            rm -f "$target"
        fi
    fi

    for attempt in $(seq 1 60); do
        current=0
        [[ -f "$target" ]] && current="$(stat -f '%z' "$target" 2>/dev/null || stat -c '%s' "$target")"

        if [[ "$current" == "$expected" ]] && gzip_check_if_needed "$target" >/dev/null 2>&1; then
            log "下载完成: $name size=${current}"
            return 0
        fi

        if [[ "$current" == "$expected" ]]; then
            warn "gzip 校验失败，删除重下: $name"
            rm -f "$target"
        fi

        log "断点下载: $name attempt=${attempt} current=${current}/${expected}"
        "${curl_cmd[@]}" -C - -o "$target" "$url" || true

        current=0
        [[ -f "$target" ]] && current="$(stat -f '%z' "$target" 2>/dev/null || stat -c '%s' "$target")"
        if [[ "$current" == "$expected" ]] && gzip_check_if_needed "$target" >/dev/null 2>&1; then
            log "下载完成: $name size=${current}"
            return 0
        fi

        if [[ "$current" -gt "$expected" ]]; then
            warn "文件大小异常，删除重下: $name current=${current} expected=${expected}"
            rm -f "$target"
        fi
    done

    die "下载失败: $name"
}

md5_of_file() {
    local file="$1"
    if command -v md5 >/dev/null 2>&1; then
        md5 -q "$file"
    else
        md5sum "$file" | awk '{print $1}'
    fi
}

sha256_of_file() {
    local file="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        sha256sum "$file" | awk '{print $1}'
    fi
}

checkout_branch_head_once() {
    local repo_url="$1"
    local branch="$2"
    local target_dir="$3"
    local sparse_path="$4"
    local use_partial_clone="$5"

    rm -rf "$target_dir"
    mkdir -p "$target_dir" || return 1

    "${git_cmd[@]}" -C "$target_dir" init -q || return 1
    "${git_cmd[@]}" -C "$target_dir" remote add origin "$repo_url" || return 1
    "${git_cmd[@]}" -C "$target_dir" config core.sparseCheckout true || return 1
    if [[ -n "$GIT_HTTP_VERSION" ]]; then
        "${git_cmd[@]}" -C "$target_dir" config http.version "$GIT_HTTP_VERSION" || return 1
    fi

    mkdir -p "$target_dir/.git/info" || return 1
    printf '/%s/\n' "$sparse_path" > "$target_dir/.git/info/sparse-checkout" || return 1

    if [[ "$use_partial_clone" == "true" ]]; then
        "${git_cmd[@]}" -C "$target_dir" fetch --depth 1 --filter=blob:none --no-tags origin "refs/heads/${branch}" || return 1
    else
        "${git_cmd[@]}" -C "$target_dir" fetch --depth 1 --no-tags origin "refs/heads/${branch}" || return 1
    fi

    "${git_cmd[@]}" -C "$target_dir" checkout -q FETCH_HEAD || return 1
}

checkout_latest_branch_head() {
    local repo_url="$1"
    local branch="$2"
    local target_dir="$3"
    local sparse_path="$4"

    if checkout_branch_head_once "$repo_url" "$branch" "$target_dir" "$sparse_path" true; then
        return 0
    fi

    warn "partial sparse checkout 失败，退回普通 shallow sparse checkout"
    checkout_branch_head_once "$repo_url" "$branch" "$target_dir" "$sparse_path" false
}

DATKIT_VERSION="$(json_value datakit_version)"
INSTALLER_VERSION="$(json_value installer_version)"
PACKAGE_NAME="$(json_value package_name)"
FINAL_PACKAGE_NAME="$(json_value final_package_name)"

CLONE_DIR="$WORK_DIR/materiel_tools"
log "从 GitHub 拉取最新 HEAD: repo=$GITHUB_REPO branch=$GIT_BRANCH path=$SPARSE_PATH"
checkout_latest_branch_head "$GITHUB_REPO" "$GIT_BRANCH" "$CLONE_DIR" "$SPARSE_PATH"
GITHUB_COMMIT="$(git -C "$CLONE_DIR" rev-parse HEAD)"
log "GitHub 代码版本: $GITHUB_COMMIT"

CODE_DIR="$CLONE_DIR/datakit-automation"
ENV_DIR="$CODE_DIR/config/env"
TARGET_ENV_FILE="$ENV_DIR/${BUILD_ENV}.sh"
[[ -d "$ENV_DIR" ]] || die "缺少环境配置目录: $ENV_DIR"

if [[ "$USE_LOCAL_ENV_OVERLAY" == "true" ]]; then
    if [[ -f "$LOCAL_ENV_FILE" ]]; then
        log "覆盖本地真实环境配置: $LOCAL_ENV_FILE -> $TARGET_ENV_FILE"
        cp "$LOCAL_ENV_FILE" "$TARGET_ENV_FILE"
    else
        warn "本地环境配置不存在，使用 GitHub 配置: $LOCAL_ENV_FILE"
    fi
fi

[[ -f "$TARGET_ENV_FILE" ]] || die "目标环境配置不存在: $TARGET_ENV_FILE"

find "$ENV_DIR" -maxdepth 1 -type f -name '*.sh' ! -name "${BUILD_ENV}.sh" -delete
if grep -q '__REPLACE_ME__' "$TARGET_ENV_FILE" && [[ "$ALLOW_PLACEHOLDER_CONFIG" != "true" ]]; then
    die "环境配置仍包含 __REPLACE_ME__，请提供本地真实配置或使用 --allow-placeholder-config"
fi

PACKAGE_DIR="$CODE_DIR/package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    download_with_resume "$url" "$PACKAGE_DIR"
done < <(json_value binary_urls)

BUNDLE="$PACKAGE_DIR/${PACKAGE_NAME}-${DATKIT_VERSION}.tar.gz"
BUNDLE_MD5="$BUNDLE.md5"
rm -f "$BUNDLE" "$BUNDLE_MD5"

log "生成内层 bundle: $BUNDLE"
(
    cd "$PACKAGE_DIR"
    bundle_files=()
    for file in *; do
        [[ -f "$file" ]] || continue
        [[ "$file" == "$(basename "$BUNDLE")" ]] && continue
        [[ "$file" == "$(basename "$BUNDLE_MD5")" ]] && continue
        bundle_files+=("$file")
    done
    [[ ${#bundle_files[@]} -gt 0 ]] || die "package 目录为空，无法生成内层 bundle"
    COPYFILE_DISABLE=1 tar -czf "$(basename "$BUNDLE")" "${bundle_files[@]}"
)

BUNDLE_MD5_VALUE="$(md5_of_file "$BUNDLE")"
printf '%s  %s\n' "$BUNDLE_MD5_VALUE" "$(basename "$BUNDLE")" > "$BUNDLE_MD5"
log "bundle MD5: $BUNDLE_MD5_VALUE"

find "$PACKAGE_DIR" -maxdepth 1 -type f \
    ! -name "$(basename "$BUNDLE")" \
    ! -name "$(basename "$BUNDLE_MD5")" \
    -delete

FINAL_PACKAGE="$OUTPUT_DIR/${FINAL_PACKAGE_NAME}_${INSTALLER_VERSION}_${BUILD_ENV}.tgz"
TOOLS_PACKAGE="$OUTPUT_DIR/${FINAL_PACKAGE_NAME}_tools_${INSTALLER_VERSION}.tgz"
rm -f "$FINAL_PACKAGE" "$TOOLS_PACKAGE"

log "生成最终安装包: $FINAL_PACKAGE"
(
    cd "$CLONE_DIR"
    COPYFILE_DISABLE=1 tar -czf "$FINAL_PACKAGE" datakit-automation
)

log "生成 tools 包: $TOOLS_PACKAGE"
(
    cd "$CODE_DIR"
    COPYFILE_DISABLE=1 tar -czf "$TOOLS_PACKAGE" tools/*.sh
)

FINAL_SHA256="$(sha256_of_file "$FINAL_PACKAGE")"
TOOLS_SHA256="$(sha256_of_file "$TOOLS_PACKAGE")"
BUNDLE_SIZE="$(stat -f '%z' "$BUNDLE" 2>/dev/null || stat -c '%s' "$BUNDLE")"

log "打包完成"
cat <<EOF
GitHub commit: $GITHUB_COMMIT
环境: $BUILD_ENV
主安装包: $FINAL_PACKAGE
主安装包 SHA256: $FINAL_SHA256
Tools 包: $TOOLS_PACKAGE
Tools 包 SHA256: $TOOLS_SHA256
内层 bundle: $BUNDLE_SIZE bytes
EOF
