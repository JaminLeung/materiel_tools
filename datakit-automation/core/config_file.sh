#!/bin/bash

# 配置文件处理相关函数

# 全局配置变量
declare -A CONFIG_VALUES

# 默认配置文件路径
DEFAULT_CONFIG_FILE=""

read_toml_config() {
    local toml_file="$1"
    [ -f "$toml_file" ] || die "配置文件不存在: $toml_file"
    command_exists yj || die "命令 'yj' 不存在"
    yj -t < "$toml_file" 2>/dev/null || die "TOML文件读取失败: $toml_file"
}

update_toml_config() {
    local toml_file="$1"
    local json_data="$2"
    local current_config
    if [ -f "$toml_file" ]; then
        current_config=$(read_toml_config "$toml_file") || {
            log_error "读取当前配置文件失败: $toml_file"
            return 1
        }
    else
        log_info "配置文件不存在，将创建新文件: $toml_file"
        current_config="{}"
    fi
    if [ "$current_config" = "$json_data" ]; then
        log_info "配置相同，跳过更新: $toml_file"
        return 0
    fi
    # 使用CONFIG_UPDATE_BACKUP_DIR，如果未定义则使用默认值
    local backup_dir="${CONFIG_UPDATE_BACKUP_DIR:-/var/backups/datakit}"
    safe_execute "mkdir -p '$backup_dir'" "创建备份目录" || return 1
    local filename=$(basename "$toml_file")
    local backup_file="$backup_dir/${filename}.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "$toml_file" ]; then
        safe_execute "cp '$toml_file' '$backup_file'" "备份配置文件" || return 1
        log_info "备份文件: $backup_file"
    else
        log_info "原文件不存在，无需备份"
    fi
    safe_execute "echo '$json_data' | yj -jt > '$toml_file'" "更新配置文件" || return 1
    log_success "配置文件更新成功: $toml_file"
    log_info "备份文件: $backup_file"
    return 0
}

get_json_path_value() {
    local json_data="$1"
    local json_path="$2"
    local value
    value=$(echo "$json_data" | jq "$json_path" 2>/dev/null)
    local jq_ret=$?
    if [ $jq_ret -eq 0 ] && [ "$value" != "null" ]; then
        local first_char="${value:0:1}"
        if [ "$first_char" = "[" ] || [ "$first_char" = "{" ]; then
            echo "$value"
        else
            echo "$json_data" | jq -r "$json_path" 2>/dev/null
        fi
        return 0
    fi
    return 1
}

set_json_path_value() {
    local json_data="$1"
    local json_path="$2"
    local new_value="$3"
    local updated_json
    if [[ "$new_value" =~ ^\[.*\]$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    elif [[ "$new_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    elif [[ "$new_value" =~ ^(true|false)$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    else
        updated_json=$(echo "$json_data" | jq "$json_path = \"$new_value\"" 2>/dev/null)
    fi
    if [ $? -eq 0 ]; then
        echo "$updated_json"
        return 0
    fi
    return 1
}

# =============================================================================
# 配置管理函数
# =============================================================================

# 设置默认配置文件路径
set_default_config_file() {
    local config_file="$1"
    DEFAULT_CONFIG_FILE="$config_file"
}

# 加载配置文件
load_config_file() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [ -z "$config_file" ]; then
        log_error "未指定配置文件路径"
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        return 1
    fi
    
    log_info "加载配置文件: $config_file"
    
    # 清空现有配置
    CONFIG_VALUES=()
    
    # 读取TOML配置文件并转换为JSON
    local json_config
    json_config=$(yj -t < "$config_file" 2>/dev/null) || {
        log_error "配置文件格式错误: $config_file"
        return 1
    }
    
    # 解析配置项并存储到关联数组中
    local sections
    sections=$(echo "$json_config" | jq -r 'keys[]' 2>/dev/null)
    
    for section in $sections; do
        local section_data
        section_data=$(echo "$json_config" | jq -r ".[\"$section\"]" 2>/dev/null)
        
        if [ "$section_data" != "null" ]; then
            local keys
            keys=$(echo "$section_data" | jq -r 'keys[]' 2>/dev/null)
            
            for key in $keys; do
                local value
                value=$(echo "$section_data" | jq -r ".[\"$key\"]" 2>/dev/null)
                CONFIG_VALUES["${section}_${key}"]="$value"
                log_debug "加载配置: ${section}_${key} = $value"
            done
        fi
    done
    
    log_success "配置文件加载完成: $config_file"
    return 0
}

# 获取配置值
get_config_value() {
    local key="$1"
    local default_value="${2:-}"
    
    if [ -z "$key" ]; then
        log_error "配置键不能为空"
        return 1
    fi
    
    local value="${CONFIG_VALUES[$key]:-}"
    
    if [ -z "$value" ]; then
        if [ -n "$default_value" ]; then
            log_debug "配置键 '$key' 未找到，使用默认值: $default_value"
            echo "$default_value"
            return 0
        else
            log_error "配置键 '$key' 未找到且无默认值"
            return 1
        fi
    fi
    
    echo "$value"
    return 0
}

# 设置配置值
set_config_value() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ]; then
        log_error "配置键不能为空"
        return 1
    fi
    
    CONFIG_VALUES["$key"]="$value"
    log_debug "设置配置: $key = $value"
    return 0
}

# 检查配置键是否存在
has_config_key() {
    local key="$1"
    
    if [ -z "$key" ]; then
        return 1
    fi
    
    [ -n "${CONFIG_VALUES[$key]:-}" ]
}

# 列出所有配置键
list_config_keys() {
    local pattern="${1:-*}"
    
    for key in "${!CONFIG_VALUES[@]}"; do
        if [[ "$key" == $pattern ]]; then
            echo "$key"
        fi
    done
}

# 导出配置为环境变量
export_config_as_env() {
    local prefix="${1:-CONFIG_}"
    
    for key in "${!CONFIG_VALUES[@]}"; do
        local env_key="${prefix}${key^^}"
        export "$env_key"="${CONFIG_VALUES[$key]}"
        log_debug "导出环境变量: $env_key = ${CONFIG_VALUES[$key]}"
    done
    
    log_info "配置已导出为环境变量 (前缀: $prefix)"
}

# 验证必需配置项
validate_required_config() {
    local required_keys=("$@")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if ! has_config_key "$key"; then
            missing_keys+=("$key")
        fi
    done
    
    if [ ${#missing_keys[@]} -gt 0 ]; then
        log_error "缺少必需的配置项: ${missing_keys[*]}"
        return 1
    fi
    
    log_success "所有必需配置项验证通过"
    return 0
}

# 生成配置模板
generate_config_template() {
    local output_file="$1"
    local template_content="$2"
    
    if [ -z "$output_file" ]; then
        log_error "输出文件路径不能为空"
        return 1
    fi
    
    if [ -z "$template_content" ]; then
        log_error "模板内容不能为空"
        return 1
    fi
    
    # 创建目录
    local dir=$(dirname "$output_file")
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            log_error "创建目录失败: $dir"
            return 1
        }
    fi
    
    # 写入模板文件
    echo "$template_content" > "$output_file" || {
        log_error "写入模板文件失败: $output_file"
        return 1
    }
    
    log_success "配置模板已生成: $output_file"
    return 0
}