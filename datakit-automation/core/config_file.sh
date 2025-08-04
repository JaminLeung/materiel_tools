#!/bin/bash

# 配置文件处理相关函数

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