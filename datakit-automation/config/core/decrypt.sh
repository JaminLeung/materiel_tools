#!/bin/bash

#=================================================
# 配置解密模块
#=================================================
# 在项目运行时自动解密敏感配置
#=================================================

# =============================================================================
# 解密配置
# =============================================================================

# 默认加密密钥文件位置
DECRYPTION_KEY_FILE="${DECRYPTION_KEY_FILE:-$HOME/.datakit_encryption_key}"

# 支持的加密算法
SUPPORTED_ALGORITHMS=("aes-256-gcm" "aes-256-cbc" "chacha20-poly1305")

# 日志函数（如果尚未定义）
if ! declare -F log_info >/dev/null; then
    log_info() {
        echo "[INFO] $1" >&2
    }
fi

if ! declare -F log_warn >/dev/null; then
    log_warn() {
        echo "[WARN] $1" >&2
    }
fi

if ! declare -F log_error >/dev/null; then
    log_error() {
        echo "[ERROR] $1" >&2
    }
fi

# 检查依赖
check_decrypt_dependencies() {
    local missing_deps=()
    
    # 检查openssl
    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    # 检查base64
    if ! command -v base64 >/dev/null 2>&1; then
        missing_deps+=("base64")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少解密必需的依赖: ${missing_deps[*]}"
        log_error "请安装缺少的依赖后重试"
        return 1
    fi
    
    return 0
}

# 获取解密密钥
get_decryption_key() {
    local key_file="$1"
    
    # 首先尝试从环境变量获取
    if [[ -n "${DATAKIT_ENCRYPTION_KEY:-}" ]]; then
        log_warn "从环境变量获取解密密钥（不推荐用于生产环境）"
        echo "$DATAKIT_ENCRYPTION_KEY"
        return 0
    fi
    
    # 从密钥文件获取
    if [[ -f "$key_file" ]]; then
        local key
        key=$(cat "$key_file" | tr -d '\n\r')
        if [[ -n "$key" ]]; then
            echo "$key"
            return 0
        fi
    fi
    
    log_error "无法获取解密密钥"
    log_error "请设置 DECRYPTION_KEY_FILE 环境变量或确保密钥文件存在: $key_file"
    return 1
}

# 检查文件是否为加密文件
is_encrypted_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # 检查文件头
    if grep -q "^# Datakit 加密配置文件" "$file" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# 解密单个文件
decrypt_single_file() {
    local encrypted_file="$1"
    local key_file="$2"
    local output_dir="${3:-$(dirname "$encrypted_file")}"
    
    log_info "解密文件: $encrypted_file"
    
    # 检查是否为加密文件
    if ! is_encrypted_file "$encrypted_file"; then
        log_warn "文件不是加密文件，跳过: $encrypted_file"
        return 0
    fi
    
    # 检查依赖
    if ! check_decrypt_dependencies; then
        return 1
    fi
    
    # 获取解密密钥
    local key
    key=$(get_decryption_key "$key_file") || return 1
    
    # 解析文件头
    local algorithm iv
    algorithm=$(grep "^# 算法:" "$encrypted_file" | cut -d: -f2 | tr -d ' ')
    iv=$(grep "^# IV:" "$encrypted_file" | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$algorithm" || -z "$iv" ]]; then
        log_error "无法解析加密文件头: $encrypted_file"
        return 1
    fi
    
    # 检查算法支持
    local supported=false
    for supported_alg in "${SUPPORTED_ALGORITHMS[@]}"; do
        if [[ "$algorithm" == "$supported_alg" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" == false ]]; then
        log_error "不支持的加密算法: $algorithm"
        return 1
    fi
    
    log_info "检测到加密算法: $algorithm, IV: $iv"
    
    # 提取加密数据
    local temp_encrypted
    temp_encrypted=$(mktemp)
    
    # 跳过文件头，提取加密数据
    sed -n '/^[^#]/p' "$encrypted_file" > "$temp_encrypted"
    
    # 解密数据
    local temp_decrypted
    temp_decrypted=$(mktemp)
    
    case "$algorithm" in
        "aes-256-gcm")
            if ! openssl enc -aes-256-gcm -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败: $encrypted_file"
                rm -f "$temp_encrypted" "$temp_decrypted"
                return 1
            fi
            ;;
        "aes-256-cbc")
            if ! openssl enc -aes-256-cbc -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败: $encrypted_file"
                rm -f "$temp_encrypted" "$temp_decrypted"
                return 1
            fi
            ;;
        "chacha20-poly1305")
            if ! openssl enc -chacha20-poly1305 -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败: $encrypted_file"
                rm -f "$temp_encrypted" "$temp_decrypted"
                return 1
            fi
            ;;
        *)
            log_error "不支持的加密算法: $algorithm"
            rm -f "$temp_encrypted" "$temp_decrypted"
            return 1
            ;;
    esac
    
    # 生成输出文件名
    local base_name
    base_name=$(basename "$encrypted_file" .encrypted)
    local output_file="$output_dir/$base_name"
    
    # 保存解密后的文件
    mv "$temp_decrypted" "$output_file"
    
    # 清理临时文件
    rm -f "$temp_encrypted"
    
    log_info "文件解密成功: $output_file"
    
    return 0
}

# 批量解密目录中的加密文件
decrypt_directory() {
    local source_dir="$1"
    local key_file="$2"
    local output_dir="${3:-$source_dir}"
    
    log_info "扫描目录中的加密文件: $source_dir"
    
    # 检查源目录
    if [[ ! -d "$source_dir" ]]; then
        log_error "源目录不存在: $source_dir"
        return 1
    fi
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 查找所有加密文件
    local encrypted_files=()
    while IFS= read -r -d '' file; do
        if is_encrypted_file "$file"; then
            encrypted_files+=("$file")
        fi
    done < <(find "$source_dir" -name "*.encrypted" -type f -print0)
    
    if [[ ${#encrypted_files[@]} -eq 0 ]]; then
        log_info "未找到加密文件"
        return 0
    fi
    
    log_info "找到 ${#encrypted_files[@]} 个加密文件"
    
    # 解密每个文件
    local success_count=0
    local fail_count=0
    
    for file in "${encrypted_files[@]}"; do
        if decrypt_single_file "$file" "$key_file" "$output_dir"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log_info "解密完成: 成功 $success_count 个，失败 $fail_count 个"
    
    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# 自动解密配置
auto_decrypt_config() {
    local config_dir="$1"
    local key_file="$2"
    
    log_info "自动解密配置目录: $config_dir"
    
    # 检查配置目录
    if [[ ! -d "$config_dir" ]]; then
        log_warn "配置目录不存在: $config_dir"
        return 0
    fi
    
    # 解密环境配置
    local env_dir="$config_dir/env"
    if [[ -d "$env_dir" ]]; then
        log_info "解密环境配置..."
        decrypt_directory "$env_dir" "$key_file" "$env_dir"
    fi
    
    # 解密脚本配置
    local scripts_dir="$config_dir/scripts"
    if [[ -d "$scripts_dir" ]]; then
        log_info "解密脚本配置..."
        decrypt_directory "$scripts_dir" "$key_file" "$scripts_dir"
    fi
    
    log_info "配置解密完成"
    
    return 0
}

# 检查并解密敏感配置
check_and_decrypt_sensitive_config() {
    local config_dir="$1"
    local key_file="${2:-$DECRYPTION_KEY_FILE}"
    
    log_info "检查敏感配置..."
    
    # 检查是否有加密文件需要解密
    local has_encrypted=false
    while IFS= read -r -d '' file; do
        if is_encrypted_file "$file"; then
            has_encrypted=true
            break
        fi
    done < <(find "$config_dir" -name "*.encrypted" -type f -print0 2>/dev/null)
    
    if [[ "$has_encrypted" == false ]]; then
        log_info "未发现需要解密的配置文件"
        return 0
    fi
    
    log_info "发现加密配置文件，开始解密..."
    
    # 自动解密配置
    if auto_decrypt_config "$config_dir" "$key_file"; then
        log_info "敏感配置解密成功"
        return 0
    else
        log_error "敏感配置解密失败"
        return 1
    fi
}

# 清理解密后的临时文件
cleanup_decrypted_files() {
    local config_dir="$1"
    local pattern="${2:-*.decrypted}"
    
    log_info "清理解密后的临时文件..."
    
    local cleaned_count=0
    while IFS= read -r -d '' file; do
        if rm -f "$file"; then
            ((cleaned_count++))
        fi
    done < <(find "$config_dir" -name "$pattern" -type f -print0 2>/dev/null)
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_info "清理了 $cleaned_count 个临时文件"
    else
        log_info "没有需要清理的临时文件"
    fi
}

# 主解密函数
decrypt_config() {
    local config_dir="$1"
    local key_file="${2:-$DECRYPTION_KEY_FILE}"
    local cleanup="${3:-true}"
    
    log_info "开始配置解密流程..."
    
    # 检查依赖
    if ! check_decrypt_dependencies; then
        return 1
    fi
    
    # 检查并解密敏感配置
    if ! check_and_decrypt_sensitive_config "$config_dir" "$key_file"; then
        return 1
    fi
    
    # 清理临时文件
    if [[ "$cleanup" == "true" ]]; then
        cleanup_decrypted_files "$config_dir"
    fi
    
    log_info "配置解密流程完成"
    
    return 0
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 显示帮助信息
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        cat << EOF
用法: $0 <配置目录> [密钥文件] [是否清理]

参数:
    配置目录    要解密的配置目录路径
    密钥文件    加密密钥文件路径 (可选，默认: $DECRYPTION_KEY_FILE)
    是否清理    是否清理临时文件 (可选，默认: true)

示例:
    $0 ./config
    $0 ./config ~/.my_key
    $0 ./config ~/.my_key false

环境变量:
    DECRYPTION_KEY_FILE    默认加密密钥文件路径
    DATAKIT_ENCRYPTION_KEY 直接指定加密密钥（不推荐）
EOF
        exit 0
    fi
    
    # 执行解密
    local config_dir="$1"
    local key_file="${2:-$DECRYPTION_KEY_FILE}"
    local cleanup="${3:-true}"
    
    if decrypt_config "$config_dir" "$key_file" "$cleanup"; then
        echo "配置解密成功"
        exit 0
    else
        echo "配置解密失败"
        exit 1
    fi
fi 