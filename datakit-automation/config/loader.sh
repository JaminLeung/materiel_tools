#!/bin/bash

#=================================================
# Datakit 配置加载器
#=================================================
# 统一加载所有配置文件
# 使用方式: source loader.sh
#=================================================

# 获取配置目录
LOADER_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 设置必要的环境变量（避免core模块中的错误）
export DATAKIT_LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"

# 加载基础配置（包含日志函数）
if [ -z "$SCRIPT_NAME" ]; then
    source "$LOADER_CONFIG_DIR/base/base_config.sh"
fi

# 加载日志模块
if [ -z "$(declare -f log_info 2>/dev/null)" ]; then
    source "$LOADER_CONFIG_DIR/../core/logging.sh"
fi

# 加载core模块
if [ -z "$(declare -f validate_config 2>/dev/null)" ]; then
    source "$LOADER_CONFIG_DIR/../core/validation.sh"
fi

# 加载基础配置
load_base_config() {
    echo "✅ 基础配置已加载"
}

# 加载状态配置
load_state_config() {
    echo "✅ 状态配置已加载"
}

# 加载环境变量配置
load_env_config() {
    local env_config="$1"
    
    # 如果指定了环境配置文件，则加载它
    if [[ -n "$env_config" && -f "$env_config" ]]; then
        source "$env_config"
        echo "✅ 环境配置已加载: $env_config"
    else
        # 尝试加载默认的生产配置
        local default_config="$CONFIG_DIR/env/production.sh"
        if [[ -f "$default_config" ]]; then
            source "$default_config"
            echo "✅ 默认配置已加载: $default_config"
        else
            echo "ℹ️  未指定环境配置文件"
        fi
    fi
}

# 验证配置完整性
validate_configs() {
    # 简化的配置验证函数，避免core模块中的问题
    log_info "验证配置参数..."
    local validation_passed=true
    local missing_required=()
    local warnings=()
    
    # 检查必需的配置项
    local required_configs=(
        "DATAKIT_VERSION"
        "S3_BUCKET"
        "S3_ACCESS_KEY"
        "S3_SECRET_KEY"
    )
    
    for config_key in "${required_configs[@]}"; do
        if [ -z "${!config_key}" ]; then
            missing_required+=("$config_key")
            validation_passed=false
        fi
    done
    
    # 检查版本格式
    if [ -n "${DATAKIT_VERSION}" ]; then
        if ! [[ "${DATAKIT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warnings+=("DATAKIT_VERSION格式可能不正确 (应为x.y.z格式): ${DATAKIT_VERSION}")
        fi
    fi
    
    # 检查S3配置
    if [ -n "${S3_BUCKET}" ]; then
        if [[ "${S3_BUCKET}" =~ [^a-zA-Z0-9\-\.] ]]; then
            warnings+=("S3_BUCKET包含特殊字符，可能无效: ${S3_BUCKET}")
        fi
    fi
    
    # 检查S3密钥长度
    if [ -n "${S3_ACCESS_KEY}" ] && [ ${#S3_ACCESS_KEY} -lt 10 ]; then
        warnings+=("S3_ACCESS_KEY长度过短，可能无效")
    fi
    
    if [ -n "${S3_SECRET_KEY}" ] && [ ${#S3_SECRET_KEY} -lt 10 ]; then
        warnings+=("S3_SECRET_KEY长度过短，可能无效")
    fi
    
    # 检查URL格式
    if [ -n "${DATAWAY_URL}" ]; then
        if ! [[ "${DATAWAY_URL}" =~ ^https?:// ]]; then
            warnings+=("DATAWAY_URL格式错误 (应以http://或https://开头): ${DATAWAY_URL}")
        fi
    fi
    
    if [ -n "${OPS_ADDR}" ]; then
        if ! [[ "${OPS_ADDR}" =~ ^https?:// ]]; then
            warnings+=("OPS_ADDR格式错误 (应以http://或https://开头): ${OPS_ADDR}")
        fi
    fi
    
    # 显示验证结果
    if [ ${#missing_required[@]} -gt 0 ]; then
        log_error "缺少必需配置: ${missing_required[*]}"
        validation_passed=false
    fi
    
    if [ ${#warnings[@]} -gt 0 ]; then
        log_warning "配置警告:"
        for warning in "${warnings[@]}"; do
            log_warning "  $warning"
        done
    fi
    
    if [ "$validation_passed" = true ]; then
        log_success "配置验证通过"
        return 0
    else
        log_error "配置验证失败"
        return 1
    fi
}

# 显示配置信息
show_configs() {
    echo "📋 当前配置:"
    echo "  📦 版本: ${DATAKIT_VERSION:-未设置}"
    echo "  ☁️  存储桶: ${S3_BUCKET:-未设置}"
    echo "  🌐 Dataway: ${DATAWAY_URL:-未设置}"
    echo "  🔧 运维平台: ${OPS_ADDR:-未设置}"
    echo "  📝 日志级别: ${LOG_LEVEL:-1}"
    echo "  🔒 锁文件: ${LOCK_FILE:-未设置}"
    echo "  💾 备份目录: ${BACKUP_DIR:-未设置}"
}

# 主加载函数
load_all_configs() {
    local env_config_file="$1"
    
    echo "🚀 加载配置..."
    
    # 加载配置
    load_base_config
    load_state_config
    
    echo "env_config_file: $env_config_file"
    load_env_config "$env_config_file"
    
    # 验证配置
    validate_configs || return 1
    
    # 初始化状态
    if command -v init_state >/dev/null 2>&1; then
        init_state
    fi
    
    echo "✅ 配置加载完成"
    return 0
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        --show)
            load_all_configs "$2" && show_configs
            ;;
        --help)
            echo "用法: $0 [选项] [配置文件]"
            echo "选项: --show, --help"
            echo "配置文件: 可选的环境配置文件路径"
            echo ""
            echo "配置优先级:"
            echo "  1. 环境变量 (最高优先级)"
            echo "  2. 配置文件"
            echo "  3. 默认值 (最低优先级)"
            echo ""
            echo "示例:"
            echo "  source $0                    # 加载默认配置"
            echo "  source $0 config/env/production.sh  # 加载生产配置"
            echo "  source $0 config/env/development.sh # 加载开发配置"
            echo "  $0 --show                    # 显示默认配置"
            echo "  $0 --show config/env/production.sh  # 显示指定配置"
            echo ""
            echo "环境变量示例:"
            echo "  export DATAKIT_VERSION=1.78.0"
            echo "  export S3_BUCKET=my-bucket"
            echo "  export S3_ACCESS_KEY=your-key"
            echo "  export S3_SECRET_KEY=your-secret"
            echo "  export DATAWAY_URL=https://dataway.example.com"
            echo "  export OPS_ADDR=http://ops.example.com:5000"
            ;;
        *)
            load_all_configs "$1"
            ;;
    esac
fi 