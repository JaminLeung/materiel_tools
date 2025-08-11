#!/bin/bash

#=================================================
# 配置加载器
#=================================================
# 管理配置文件的加载顺序和依赖关系
#=================================================

# =============================================================================
# 配置加载器函数
# =============================================================================

# 加载基础配置
load_base_config() {
    local base_config_file="$CONFIG_DIR/base/base_config.sh"
    
    if [[ -f "$base_config_file" ]]; then
        source "$base_config_file"
        log_info "已加载基础配置: $base_config_file"
        return 0
    else
        log_error "基础配置文件不存在: $base_config_file"
        return 1
    fi
}

# 加载状态配置
load_state_config() {
    local state_config_file="$CONFIG_DIR/base/state_config.sh"
    
    if [[ -f "$state_config_file" ]]; then
        source "$state_config_file"
        log_info "已加载状态配置: $state_config_file"
        
        # 初始化状态
        if declare -F init_state >/dev/null; then
            init_state
            log_info "状态已初始化"
        else
            log_warn "init_state函数未找到"
        fi
        
        return 0
    else
        log_error "状态配置文件不存在: $state_config_file"
        return 1
    fi
}

# 加载环境配置
load_env_config() {
    local env_name="${1:-$ENV}"
    local env_config_file="$CONFIG_DIR/env/${env_name}.sh"
    
    if [[ -f "$env_config_file" ]]; then
        source "$env_config_file"
        log_info "已加载环境配置: $env_config_file"
        
        # 更新环境状态
        if declare -F update_current_step >/dev/null; then
            update_current_step "加载环境配置: $env_name"
        fi
        
        return 0
    else
        log_warn "环境配置文件不存在: $env_config_file，使用默认配置"
        return 0
    fi
}

# 加载脚本特定配置
load_script_config() {
    local script_name="$1"
    local script_config_file="$CONFIG_DIR/scripts/${script_name}.sh"
    
    if [[ -f "$script_config_file" ]]; then
        source "$script_config_file"
        log_info "已加载脚本配置: $script_config_file"
        
        # 更新脚本状态
        if declare -F update_current_step >/dev/null; then
            update_current_step "加载脚本配置: $script_name"
        fi
        
        return 0
    else
        log_warn "脚本配置文件不存在: $script_config_file"
        return 0
    fi
}

# 加载所有配置
load_all_configs() {
    local env_name="${1:-$ENV}"
    local script_name="${2:-}"
    
    log_info "开始加载配置..."
    
    # 1. 加载基础配置
    if ! load_base_config; then
        return 1
    fi
    
    # 2. 加载状态配置
    if ! load_state_config; then
        return 1
    fi
    
    # 3. 加载环境配置
    if ! load_env_config "$env_name"; then
        return 1
    fi
    
    # 4. 加载脚本特定配置（如果指定）
    if [[ -n "$script_name" ]]; then
        if ! load_script_config "$script_name"; then
            return 1
        fi
    fi
    
    log_info "配置加载完成"
    return 0
}

# 验证配置完整性
validate_config() {
    local missing_vars=()
    
    # 检查必需的基础配置
    local required_base_vars=(
        "DATAKIT_VERSION"
        "OPS_ADDR"
        "DATAWAY_URL"
        "DATAKIT_INSTALL_DIR"
        "LOG_FILE"
    )
    
    for var in "${required_base_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "缺少必需的配置变量: ${missing_vars[*]}"
        return 1
    fi
    
    # 检查状态配置
    if ! declare -F init_state >/dev/null; then
        log_error "状态管理函数未找到"
        return 1
    fi
    
    log_info "配置验证通过"
    return 0
}

# 显示当前配置
show_current_config() {
    log_info "当前配置信息:"
    log_info "  环境: $ENV"
    log_info "  Datakit版本: $DATAKIT_VERSION"
    log_info "  运维平台: $OPS_ADDR"
    log_info "  Dataway: $DATAWAY_URL"
    log_info "  安装目录: $DATAKIT_INSTALL_DIR"
    log_info "  日志文件: $LOG_FILE"
    log_info "  日志级别: $LOG_LEVEL"
    
    # 显示状态信息（如果可用）
    if declare -F get_state_summary >/dev/null; then
        log_info "状态信息:"
        get_state_summary
    fi
}

# 获取配置摘要
get_config_summary() {
    cat << EOF
配置摘要:
  基础配置: $(basename "$CONFIG_DIR/base/base_config.sh")
  状态配置: $(basename "$CONFIG_DIR/base/state_config.sh")
  环境配置: $ENV
  脚本配置: ${SCRIPT_NAME:-未指定}
  配置目录: $CONFIG_DIR
  项目根目录: $PROJECT_ROOT
EOF
}

# =============================================================================
# 日志函数（如果尚未定义）
# =============================================================================
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

# =============================================================================
# 主函数
# =============================================================================
main() {
    local env_name="${1:-$ENV}"
    local script_name="${2:-}"
    
    # 设置默认环境
    ENV="${ENV:-test}"
    
    # 加载所有配置
    if ! load_all_configs "$env_name" "$script_name"; then
        log_error "配置加载失败"
        exit 1
    fi
    
    # 验证配置
    if ! validate_config; then
        log_error "配置验证失败"
        exit 1
    fi
    
    # 显示当前配置
    show_current_config
    
    # 显示配置摘要
    get_config_summary
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 