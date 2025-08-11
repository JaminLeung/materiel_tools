#!/bin/bash

#=================================================
# 配置加密工具
#=================================================
# 用于加密S3等敏感配置信息
#=================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 脚本信息
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# 默认配置
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-$HOME/.datakit_encryption_key}"
ENCRYPTION_ALGORITHM="aes-256-gcm"
OUTPUT_FORMAT="base64"

# 帮助信息
show_help() {
    cat << EOF
用法: $SCRIPT_NAME [选项] <操作> [文件]

操作:
    encrypt <文件>    加密配置文件
    decrypt <文件>    解密配置文件
    generate-key      生成新的加密密钥
    rotate-key        轮换加密密钥

选项:
    -k, --key-file <文件>    指定加密密钥文件 (默认: $ENCRYPTION_KEY_FILE)
    -a, --algorithm <算法>   加密算法 (默认: $ENCRYPTION_ALGORITHM)
    -f, --format <格式>      输出格式 (默认: $OUTPUT_FORMAT)
    -v, --verbose            详细输出
    -h, --help               显示此帮助信息

示例:
    # 生成加密密钥
    $SCRIPT_NAME generate-key
    
    # 加密配置文件
    $SCRIPT_NAME encrypt config.env
    
    # 解密配置文件
    $SCRIPT_NAME decrypt config.env.encrypted
    
    # 使用自定义密钥文件
    $SCRIPT_NAME -k /path/to/key encrypt config.env

支持的加密算法:
    - aes-256-gcm (推荐，默认)
    - aes-256-cbc
    - chacha20-poly1305

支持的输出格式:
    - base64 (默认)
    - hex
    - raw

环境变量:
    ENCRYPTION_KEY_FILE    加密密钥文件路径
    DATAKIT_ENCRYPTION_KEY 直接指定加密密钥（不推荐）

安全注意事项:
    1. 请妥善保管加密密钥文件
    2. 不要将加密密钥提交到版本控制系统
    3. 定期轮换加密密钥
    4. 在生产环境中使用强随机密钥
EOF
}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
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
        log_error "缺少必需的依赖: ${missing_deps[*]}"
        log_error "请安装缺少的依赖后重试"
        exit 1
    fi
}

# 生成加密密钥
generate_encryption_key() {
    local key_file="$1"
    local key_size=32  # 256位
    
    log_info "生成新的加密密钥..."
    
    # 生成随机密钥
    local key
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        key=$(openssl rand -hex $key_size)
    else
        # Linux
        key=$(openssl rand -hex $key_size)
    fi
    
    # 保存密钥到文件
    echo "$key" > "$key_file"
    chmod 600 "$key_file"
    
    log_success "加密密钥已生成并保存到: $key_file"
    log_info "密钥哈希: $(echo "$key" | sha256sum | cut -d' ' -f1)"
    
    return 0
}

# 获取加密密钥
get_encryption_key() {
    local key_file="$1"
    
    # 首先尝试从环境变量获取
    if [[ -n "${DATAKIT_ENCRYPTION_KEY:-}" ]]; then
        log_warning "从环境变量获取加密密钥（不推荐用于生产环境）"
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
    
    log_error "无法获取加密密钥"
    log_error "请设置 ENCRYPTION_KEY_FILE 环境变量或使用 generate-key 命令生成密钥"
    return 1
}

# 加密文件
encrypt_file() {
    local input_file="$1"
    local output_file="${input_file}.encrypted"
    local key_file="$2"
    local algorithm="$3"
    local format="$4"
    
    log_info "加密文件: $input_file"
    
    # 检查输入文件
    if [[ ! -f "$input_file" ]]; then
        log_error "输入文件不存在: $input_file"
        return 1
    fi
    
    # 获取加密密钥
    local key
    key=$(get_encryption_key "$key_file") || return 1
    
    # 生成随机IV
    local iv
    if [[ "$OSTYPE" == "darwin"* ]]; then
        iv=$(openssl rand -hex 16)
    else
        iv=$(openssl rand -hex 16)
    fi
    
    # 加密文件
    local temp_encrypted
    temp_encrypted=$(mktemp)
    
    case "$algorithm" in
        "aes-256-gcm")
            # 使用AES-256-GCM加密
            if ! openssl enc -aes-256-gcm -K "$key" -iv "$iv" -in "$input_file" -out "$temp_encrypted" 2>/dev/null; then
                log_error "加密失败"
                rm -f "$temp_encrypted"
                return 1
            fi
            ;;
        "aes-256-cbc")
            # 使用AES-256-CBC加密
            if ! openssl enc -aes-256-cbc -K "$key" -iv "$iv" -in "$input_file" -out "$temp_encrypted" 2>/dev/null; then
                log_error "加密失败"
                rm -f "$temp_encrypted"
                return 1
            fi
            ;;
        "chacha20-poly1305")
            # 使用ChaCha20-Poly1305加密
            if ! openssl enc -chacha20-poly1305 -K "$key" -iv "$iv" -in "$input_file" -out "$temp_encrypted" 2>/dev/null; then
                log_error "加密失败"
                rm -f "$temp_encrypted"
                return 1
            fi
            ;;
        *)
            log_error "不支持的加密算法: $algorithm"
            rm -f "$temp_encrypted"
            return 1
            ;;
    esac
    
    # 创建加密文件头
    cat > "$output_file" << EOF
# Datakit 加密配置文件
# 算法: $algorithm
# IV: $iv
# 创建时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# 警告: 此文件包含加密数据，请勿手动编辑
EOF
    
    # 添加加密数据
    case "$format" in
        "base64")
            base64 "$temp_encrypted" >> "$output_file"
            ;;
        "hex")
            xxd -p "$temp_encrypted" | tr -d '\n' >> "$output_file"
            ;;
        "raw")
            cat "$temp_encrypted" >> "$output_file"
            ;;
        *)
            log_error "不支持的输出格式: $format"
            rm -f "$temp_encrypted" "$output_file"
            return 1
            ;;
    esac
    
    # 清理临时文件
    rm -f "$temp_encrypted"
    
    log_success "文件加密成功: $output_file"
    log_info "算法: $algorithm, IV: $iv, 格式: $format"
    
    return 0
}

# 解密文件
decrypt_file() {
    local input_file="$1"
    local output_file="${input_file%.encrypted}"
    local key_file="$2"
    
    log_info "解密文件: $input_file"
    
    # 检查输入文件
    if [[ ! -f "$input_file" ]]; then
        log_error "输入文件不存在: $input_file"
        return 1
    fi
    
    # 检查文件头
    if ! grep -q "^# Datakit 加密配置文件" "$input_file"; then
        log_error "无效的加密配置文件: $input_file"
        return 1
    fi
    
    # 解析文件头
    local algorithm iv format
    algorithm=$(grep "^# 算法:" "$input_file" | cut -d: -f2 | tr -d ' ')
    iv=$(grep "^# IV:" "$input_file" | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$algorithm" || -z "$iv" ]]; then
        log_error "无法解析加密文件头"
        return 1
    fi
    
    log_info "检测到加密算法: $algorithm, IV: $iv"
    
    # 获取加密密钥
    local key
    key=$(get_encryption_key "$key_file") || return 1
    
    # 提取加密数据
    local temp_encrypted
    temp_encrypted=$(mktemp)
    
    # 跳过文件头，提取加密数据
    sed -n '/^[^#]/p' "$input_file" > "$temp_encrypted"
    
    # 解密数据
    local temp_decrypted
    temp_decrypted=$(mktemp)
    
    case "$algorithm" in
        "aes-256-gcm")
            if ! openssl enc -aes-256-gcm -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败"
                rm -f "$temp_encrypted" "$temp_decrypted"
                return 1
            fi
            ;;
        "aes-256-cbc")
            if ! openssl enc -aes-256-cbc -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败"
                rm -f "$temp_encrypted" "$temp_decrypted"
                return 1
            fi
            ;;
        "chacha20-poly1305")
            if ! openssl enc -chacha20-poly1305 -d -K "$key" -iv "$iv" -in "$temp_encrypted" -out "$temp_decrypted" 2>/dev/null; then
                log_error "解密失败"
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
    
    # 保存解密后的文件
    mv "$temp_decrypted" "$output_file"
    
    # 清理临时文件
    rm -f "$temp_encrypted"
    
    log_success "文件解密成功: $output_file"
    
    return 0
}

# 轮换加密密钥
rotate_encryption_key() {
    local old_key_file="$1"
    local new_key_file="${old_key_file}.new"
    
    log_info "开始轮换加密密钥..."
    
    # 生成新密钥
    generate_encryption_key "$new_key_file"
    
    log_info "请使用新密钥重新加密所有配置文件，然后替换旧密钥文件"
    log_info "新密钥文件: $new_key_file"
    log_info "旧密钥文件: $old_key_file"
    
    return 0
}

# 主函数
main() {
    local operation=""
    local input_file=""
    local verbose=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--key-file)
                ENCRYPTION_KEY_FILE="$2"
                shift 2
                ;;
            -a|--algorithm)
                ENCRYPTION_ALGORITHM="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$operation" ]]; then
                    operation="$1"
                elif [[ -z "$input_file" ]]; then
                    input_file="$1"
                else
                    log_error "多余的参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查操作参数
    if [[ -z "$operation" ]]; then
        log_error "请指定操作"
        show_help
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 执行操作
    case "$operation" in
        "generate-key")
            generate_encryption_key "$ENCRYPTION_KEY_FILE"
            ;;
        "encrypt")
            if [[ -z "$input_file" ]]; then
                log_error "请指定要加密的文件"
                exit 1
            fi
            encrypt_file "$input_file" "$ENCRYPTION_KEY_FILE" "$ENCRYPTION_ALGORITHM" "$OUTPUT_FORMAT"
            ;;
        "decrypt")
            if [[ -z "$input_file" ]]; then
                log_error "请指定要解密的文件"
                exit 1
            fi
            decrypt_file "$input_file" "$ENCRYPTION_KEY_FILE"
            ;;
        "rotate-key")
            rotate_encryption_key "$ENCRYPTION_KEY_FILE"
            ;;
        *)
            log_error "未知操作: $operation"
            show_help
            exit 1
            ;;
    esac
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 