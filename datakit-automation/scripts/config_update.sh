#!/bin/bash

# Datakit配置更新脚本 - 生产版本
# 功能：Datakit服务控制、全局配置修改、采集器配置管理

set -euo pipefail

# =============================================================================
# 加载基础配置
# =============================================================================
# 获取脚本所在目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# 加载基础配置
source "$SCRIPT_DIR/../config/loader.sh" 2>/dev/null || echo "警告: 无法加载loader.sh" >&2
load_all_configs "${ENV:-test}" "config_update"

# =============================================================================
# 加载核心模块
# =============================================================================
source "$CONFIG_UPDATE_CORE_DIR/logging.sh"
source "$CONFIG_UPDATE_CORE_DIR/utils.sh"
source "$CONFIG_UPDATE_CORE_DIR/validation.sh"
source "$CONFIG_UPDATE_CORE_DIR/health_check.sh"
source "$CONFIG_UPDATE_CORE_DIR/datakit_service.sh"


# =============================================================================
# 全局变量
# =============================================================================
CONFIG_CHANGED=false


# 初始化日志系统
# TODO 整合
init_logging


# =============================================================================
# 全局配置处理
# =============================================================================
# TODO  按照配置场景拆分
handle_global_config() {
    log_info "处理全局配置"
    
    # 检查并更新dataway配置
    handle_dataway_config
    
    local global_config
    global_config=$(echo "$DATAKIT_CONFIG" | jq '.global_config // empty' 2>/dev/null) || return 0
    
    [ -n "$global_config" ] && [ "$global_config" != "null" ] || return 0
    
    local enabled_count
    enabled_count=$(echo "$global_config" | jq '[.[] | select(.enable == true)] | length' 2>/dev/null)
    [ "$enabled_count" -gt 0 ] || return 0
    
    log_info "发现 $enabled_count 个启用的全局配置项"
    
    [ -f "$CONFIG_UPDATE_DATAKIT_CONF" ] || {
        handle_error "FILE_ERROR" "Datakit配置文件不存在" "ERROR" "false"
        return 1
    }
    
    local current_config
    current_config=$(read_toml_config "$CONFIG_UPDATE_DATAKIT_CONF") || {
        handle_error "FILE_ERROR" "读取配置文件失败" "ERROR" "false"
        return 1
    }
    
    local updated_config="$current_config"
    local config_count
    config_count=$(echo "$global_config" | jq 'length' 2>/dev/null)
    
    for i in $(seq 0 $((config_count - 1))); do
        local config_item
        config_item=$(echo "$global_config" | jq ".[$i]" 2>/dev/null)
        
        local enable key value
        enable=$(echo "$config_item" | jq -r '.enable // false' 2>/dev/null)
        key=$(echo "$config_item" | jq -r '.key // empty' 2>/dev/null)
        value=$(echo "$config_item" | jq -r '.value // empty' 2>/dev/null)
        
        # 检查运维平台配置中的key字段是否为空
        [ -n "$key" ] || continue
        
        # 确保key以点号开头
        local json_path="$key"
        [[ "$json_path" != .* ]] && json_path=".$json_path"
        
        if [ "$enable" = "false" ]; then
            # enable=false: 检查配置项是否存在，如果存在则删除
            if get_json_path_value "$current_config" "$json_path" >/dev/null; then
                log_info "删除配置项: $key"
                # 删除配置项（移除点号前缀，确保正确的jq路径格式）
                local jq_path="${json_path#.}"
                updated_config=$(echo "$updated_config" | jq "del(.$jq_path)" 2>/dev/null) || {
                    record_error "CONFIG_ERROR" "配置删除失败: $key" "ERROR"
                    continue
                }
                CONFIG_CHANGED=true
            else
                log_info "配置项不存在，跳过删除: $key"
            fi
            continue
        fi
        
        # enable=true: 处理配置项更新
        [ "$enable" = "true" ] && [ -n "$value" ] || continue
        
        log_info "处理配置项: $key"
        
        # 检查并更新配置
        if get_json_path_value "$current_config" "$json_path" >/dev/null; then
            local current_value_raw expected_value_raw
            current_value_raw=$(echo "$current_config" | jq -r "$json_path" 2>/dev/null)
            expected_value_raw="$value"
            
            if [ "$current_value_raw" != "$expected_value_raw" ]; then
                log_info "配置不一致，需要更新: $key"
                log_info "当前值: $current_value_raw"
                log_info "期望值: $expected_value_raw"
                updated_config=$(set_json_path_value "$updated_config" "$json_path" "$value") || {
                    record_error "CONFIG_ERROR" "配置更新失败: $key" "ERROR"
                    continue
                }
                CONFIG_CHANGED=true
            else
                log_info "配置相同，跳过更新: $key"
            fi
        else
            # 配置路径不存在，添加新配置
            log_info "配置路径不存在，添加新配置: $key"
            log_info "新增值: $value"
            updated_config=$(set_json_path_value "$updated_config" "$json_path" "$value") || {
                record_error "CONFIG_ERROR" "配置添加失败: $key" "ERROR"
                continue
            }
            CONFIG_CHANGED=true
        fi
    done
    
    # 应用配置变更（不重启，等待所有配置完成后统一重启）
    if [ "$CONFIG_CHANGED" = "true" ]; then
        update_toml_config "$CONFIG_UPDATE_DATAKIT_CONF" "$updated_config" || {
        handle_error "CONFIG_ERROR" "配置文件更新失败" "ERROR" "false"
        return 1
    }
    fi
}

# =============================================================================
# Dataway配置处理
# =============================================================================
handle_dataway_config() {
    log_info "处理Dataway配置"
    
    # 从全局状态获取dataway_url和workspace_token
    local ops_dataway_url
    local ops_workspace_token
    ops_dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    ops_workspace_token=$(get_global_state 'WORKSPACE_TOKEN')
    
    if [ -z "$ops_dataway_url" ] || [ -z "$ops_workspace_token" ]; then
        record_error "CONFIG_ERROR" "未获取到Dataway配置信息，跳过Dataway配置更新" "WARNING"
        return 0
    fi
    
    log_info "运维平台Dataway配置:"
    log_info "  URL: $ops_dataway_url"
    log_info "  Token: $ops_workspace_token"
    
    [ -f "$CONFIG_UPDATE_DATAKIT_CONF" ] || {
        record_error "FILE_ERROR" "Datakit配置文件不存在，跳过Dataway配置更新" "WARNING"
        return 0
    }
    
    local current_config
    current_config=$(read_toml_config "$CONFIG_UPDATE_DATAKIT_CONF") || {
        handle_error "FILE_ERROR" "读取Datakit配置文件失败" "ERROR" "false"
        return 1
    }
    
    # 获取当前配置文件中的dataway配置
    local current_dataway_url=""
    
    # 尝试从.dataway.urls[0]获取当前URL
    if get_json_path_value "$current_config" ".dataway.urls[0]" >/dev/null; then
        current_dataway_url=$(echo "$current_config" | jq -r '.dataway.urls[0]' 2>/dev/null)
        log_info "当前配置文件Dataway URL: $current_dataway_url"
    else
        log_info "配置文件中未找到.dataway.urls[0]配置"
    fi
    
    # 构建期望的完整URL（基础URL + token）
    local expected_dataway_url="${ops_dataway_url}"
    log_info "期望的Dataway URL: $expected_dataway_url"
    
    local updated_config="$current_config"
    local config_changed=false
    
    # 比较并更新URL
    if [ "$current_dataway_url" != "$expected_dataway_url" ]; then
        log_info "Dataway URL不一致，需要更新"
        log_info "当前值: $current_dataway_url"
        log_info "期望值: $expected_dataway_url"
        
        # 更新.dataway.urls[0]
        updated_config=$(set_json_path_value "$updated_config" ".dataway.urls[0]" "$expected_dataway_url") || {
            handle_error "CONFIG_ERROR" "更新Dataway URL失败" "ERROR" "false"
            return 1
        }
        config_changed=true
    else
        log_info "Dataway URL相同，无需更新"
    fi
    
    # 应用配置变更
    if [ "$config_changed" = "true" ]; then
        update_toml_config "$CONFIG_UPDATE_DATAKIT_CONF" "$updated_config" || {
            handle_error "CONFIG_ERROR" "更新Datakit配置文件失败" "ERROR" "false"
            return 1
        }
        CONFIG_CHANGED=true
        log_info "Dataway配置更新完成"
    else
        log_info "Dataway配置无需更新"
    fi
}

# =============================================================================
# 采集器配置处理
# =============================================================================
handle_input_config() {
    log_info "处理采集器配置"
    
    local input_config
    input_config=$(echo "$DATAKIT_CONFIG" | jq '.input_config // empty' 2>/dev/null) || return 0
    
    [ -n "$input_config" ] && [ "$input_config" != "null" ] || return 0
    
    local config_count
    config_count=$(echo "$input_config" | jq 'length' 2>/dev/null)
    [ "$config_count" -gt 0 ] || return 0
    
    log_info "发现 $config_count 个采集器配置项"
    
    # 按input_path分组处理配置
    local -A input_groups
    local -A input_paths
    
    # 第一遍：收集所有input_path
    for i in $(seq 0 $((config_count - 1))); do
        local config_item
        config_item=$(echo "$input_config" | jq ".[$i]" 2>/dev/null)
        
        local input_path
        input_path=$(echo "$config_item" | jq -r '.input_path // empty' 2>/dev/null)
        
        if [ -n "$input_path" ]; then
            input_paths["$input_path"]=1
        fi
    done
    
    # 第二遍：按input_path分组处理
    for input_path in "${!input_paths[@]}"; do
        log_info "处理采集器路径: $input_path"
        
        local delete_file_configs=()    # 删除整个文件的配置
        local delete_key_configs=()     # 删除特定key的配置
        local create_configs=()         # 新增配置
        local modify_configs=()         # 修改配置
        
        # 收集该input_path的所有配置
        for i in $(seq 0 $((config_count - 1))); do
            local config_item
            config_item=$(echo "$input_config" | jq ".[$i]" 2>/dev/null)
            
            local enable input_name key value
            enable=$(echo "$config_item" | jq -r '.enable // false' 2>/dev/null)
            input_name=$(echo "$config_item" | jq -r '.input_name // empty' 2>/dev/null)
            key=$(echo "$config_item" | jq -r '.key // empty' 2>/dev/null)
            value=$(echo "$config_item" | jq -r '.value // empty' 2>/dev/null)
            local current_input_path
            current_input_path=$(echo "$config_item" | jq -r '.input_path // empty' 2>/dev/null)
            
            # 只处理当前input_path的配置
            [ "$current_input_path" = "$input_path" ] || continue
            
            # 分类配置
            if [ "$enable" = "false" ] && [ -z "$key" ]; then
                # 删除整个文件场景：enable=false 且 key为空
                delete_file_configs+=("$i")
            elif [ "$enable" = "false" ] && [ -n "$key" ]; then
                # 删除特定key场景：enable=false 且 key不为空
                delete_key_configs+=("$i")
            elif [ "$enable" = "true" ] && [ -z "$key" ]; then
                # 新增场景：enable=true 且 key为空
                create_configs+=("$i")
            elif [ -n "$key" ]; then
                # 修改场景：key不为空
                modify_configs+=("$i")
            fi
        done
        
        # 处理逻辑：优先处理删除，然后处理新增，最后处理修改
        local should_skip_others=false
        
        # 1. 如果有删除整个文件的配置，执行删除并跳过其他配置
        if [ ${#delete_file_configs[@]} -gt 0 ]; then
            log_info "发现删除整个文件配置，执行删除操作"
            local config_item
            config_item=$(echo "$input_config" | jq ".[${delete_file_configs[0]}]" 2>/dev/null)
            local input_name
            input_name=$(echo "$config_item" | jq -r '.input_name // empty' 2>/dev/null)
            
            if handle_input_delete "$input_path" "$input_name"; then
                CONFIG_CHANGED=true
                should_skip_others=true
                log_info "删除整个文件操作完成，跳过其他配置"
            fi
        fi
        
        # 2. 如果没有删除整个文件，处理删除key、新增和修改
        if [ "$should_skip_others" = false ]; then
            # 处理删除特定key的配置
            for config_index in "${delete_key_configs[@]}"; do
                local config_item
                config_item=$(echo "$input_config" | jq ".[$config_index]" 2>/dev/null)
                
                local key input_name
                key=$(echo "$config_item" | jq -r '.key // empty' 2>/dev/null)
                input_name=$(echo "$config_item" | jq -r '.input_name // empty' 2>/dev/null)
                
                if [ -f "$input_path" ]; then
                    handle_input_delete_key "$input_path" "$key" "$input_name"
                else
                    log_info "配置文件不存在，跳过删除key操作: $key"
                fi
            done
            
            # 处理新增配置
            if [ ${#create_configs[@]} -gt 0 ]; then
                log_info "发现新增配置，执行新增操作"
                local config_item
                config_item=$(echo "$input_config" | jq ".[${create_configs[0]}]" 2>/dev/null)
                local input_name
                input_name=$(echo "$config_item" | jq -r '.input_name // empty' 2>/dev/null)
                
                if [ ! -f "$input_path" ]; then
                    handle_input_create "$input_path" "$input_name"
            else
                    log_info "配置文件已存在，跳过新增操作"
                fi
            fi
            
            # 处理修改配置
            for config_index in "${modify_configs[@]}"; do
                local config_item
                config_item=$(echo "$input_config" | jq ".[$config_index]" 2>/dev/null)
                
                local key value input_name
                key=$(echo "$config_item" | jq -r '.key // empty' 2>/dev/null)
                value=$(echo "$config_item" | jq -r '.value // empty' 2>/dev/null)
                input_name=$(echo "$config_item" | jq -r '.input_name // empty' 2>/dev/null)
                
                # 如果配置文件不存在，先执行新增逻辑
                if [ ! -f "$input_path" ]; then
                    log_info "修改场景：配置文件不存在，先执行新增操作"
                    handle_input_create "$input_path" "$input_name"
                fi
                
                # 执行修改操作
                if [ -f "$input_path" ]; then
                    handle_input_modify "$input_path" "$key" "$value"
                else
                    record_error "FILE_ERROR" "配置文件创建失败，无法执行修改操作" "ERROR"
                fi
            done
        fi
    done
}

handle_input_create() {
    local input_path="$1"
    local input_name="$2"
    
    log_info "创建采集器配置: $input_name"
    
    # 确保备份目录存在
    safe_execute "mkdir -p '$CONFIG_UPDATE_BACKUP_DIR'" "创建备份目录" || return 1
    
    # 使用sample文件
    local sample_path="${input_path}.sample"
    [ -f "$sample_path" ] || {
        handle_error "FILE_ERROR" "Sample文件不存在: $sample_path" "ERROR" "false"
        return 1
    }
    
    if safe_execute "cp '$sample_path' '$input_path'" "从sample创建配置文件"; then
        log_info "从sample创建: $input_path"
        return 0
    else
        handle_error "FILE_ERROR" "配置文件创建失败: $input_path" "ERROR" "false"
        return 1
    fi
}

handle_input_modify() {
    local input_path="$1"
    local key="$2"
    local value="$3"
    
    log_info "修改采集器配置: $key"
    
    local current_config
    current_config=$(read_toml_config "$input_path") || {
        handle_error "FILE_ERROR" "读取配置文件失败: $input_path" "ERROR" "false"
        return 1
    }
    
    # 确保key以点号开头
    local json_path="$key"
    [[ "$json_path" != .* ]] && json_path=".$json_path"
    
    # 尝试修正数组路径
    if [[ "$json_path" =~ \.([^.]+)\.([^.]+)$ ]]; then
        local test_path="${json_path%%.${BASH_REMATCH[2]}}[0].${BASH_REMATCH[2]}"
        if get_json_path_value "$current_config" "$test_path" >/dev/null; then
            json_path="$test_path"
            log_info "路径修正: $key -> $json_path"
        fi
    fi
    
    # 检查配置路径是否存在
    if get_json_path_value "$current_config" "$json_path" >/dev/null; then
        # 修改现有配置
        local current_value_raw expected_value_raw
        current_value_raw=$(echo "$current_config" | jq -r "$json_path" 2>/dev/null)
        expected_value_raw="$value"
        
        log_info "检查配置路径: $json_path"
        log_info "当前值: $current_value_raw"
        log_info "期望值: $expected_value_raw"
        
        if [ "$current_value_raw" != "$expected_value_raw" ]; then
            log_info "配置不一致，需要更新: $key"
            local updated_config
            updated_config=$(set_json_path_value "$current_config" "$json_path" "$value") || {
                handle_error "CONFIG_ERROR" "配置更新失败: $key" "ERROR" "false"
                return 1
            }
            update_toml_config "$input_path" "$updated_config" || {
                handle_error "CONFIG_ERROR" "配置文件更新失败: $input_path" "ERROR" "false"
                return 1
            }
            log_info "配置更新成功: $key"
            CONFIG_CHANGED=true
        else
            log_info "配置相同，跳过更新: $key"
        fi
    else
        # 新增配置
        log_info "配置路径不存在，新增配置: $key"
        log_info "新增值: $value"
        local updated_config
        updated_config=$(set_json_path_value "$current_config" "$json_path" "$value") || {
            handle_error "CONFIG_ERROR" "配置新增失败: $key" "ERROR" "false"
            return 1
        }
        update_toml_config "$input_path" "$updated_config" || {
            handle_error "CONFIG_ERROR" "配置文件更新失败: $input_path" "ERROR" "false"
            return 1
        }
        log_info "配置新增成功: $key"
        CONFIG_CHANGED=true
    fi
}

handle_input_delete() {
    local input_path="$1"
    local input_name="$2"
    
    log_info "删除采集器配置: $input_name"
    
    [ -f "$input_path" ] || {
        log_info "配置文件不存在，无需删除: $input_path"
        return 0
    }
    
    # 确保备份目录存在
    safe_execute "mkdir -p '$CONFIG_UPDATE_BACKUP_DIR'" "创建备份目录" || return 1
    
    # 生成备份文件名
    local filename=$(basename "$input_path")
    local backup_path="$CONFIG_UPDATE_BACKUP_DIR/${filename}.deleted.$(date +%Y%m%d_%H%M%S)"
    
    # 备份并删除文件
    safe_execute "cp '$input_path' '$backup_path' && rm '$input_path'" "备份并删除配置文件" || return 1
    
    log_info "配置文件已备份并删除: $backup_path"
    return 0
}

handle_input_delete_key() {
    local input_path="$1"
    local key="$2"
    local input_name="$3"
    
    log_info "删除采集器配置键: $key"
    
    [ -f "$input_path" ] || {
        log_info "配置文件不存在，无需删除: $input_path"
    return 0
    }

    local current_config
    current_config=$(read_toml_config "$input_path") || {
        handle_error "FILE_ERROR" "读取配置文件失败: $input_path" "ERROR" "false"
        return 1
    }
    
    # 确保key以点号开头
    local json_path="$key"
    [[ "$json_path" != .* ]] && json_path=".$json_path"
    
    # 尝试修正数组路径
    if [[ "$json_path" =~ \.([^.]+)\.([^.]+)$ ]]; then
        local test_path="${json_path%%.${BASH_REMATCH[2]}}[0].${BASH_REMATCH[2]}"
        if get_json_path_value "$current_config" "$test_path" >/dev/null; then
            json_path="$test_path"
            log_info "路径修正: $key -> $json_path"
        fi
    fi
    
    # 检查配置路径是否存在
    if get_json_path_value "$current_config" "$json_path" >/dev/null; then
        # 获取当前值用于日志记录
        local current_value_raw
        current_value_raw=$(echo "$current_config" | jq -r "$json_path" 2>/dev/null)
        log_info "删除配置键: $key"
        log_info "当前值: $current_value_raw"
        
        # 删除配置键（移除点号前缀，确保正确的jq路径格式）
        local jq_path="${json_path#.}"
        # 确保路径格式正确，例如：inputs.ddtrace[0].customer_tags
        local updated_config
        updated_config=$(echo "$current_config" | jq "del(.$jq_path)" 2>/dev/null) || {
            handle_error "CONFIG_ERROR" "配置删除失败: $key" "ERROR" "false"
            return 1
        }
        update_toml_config "$input_path" "$updated_config" || {
            handle_error "CONFIG_ERROR" "配置文件更新失败: $input_path" "ERROR" "false"
            return 1
        }
        log_info "配置删除成功: $key"
        CONFIG_CHANGED=true
    else
        log_info "配置路径不存在，无需删除: $key"
    fi
}

# TODO 配置解析和操作行为解耦
# =============================================================================
# Datakit服务状态控制函数
# =============================================================================
handle_datakit_service_control() {
    local datakit_config="$1"
    local config_enable=""
    
    # 检查enable字段是否存在（包括false值）
    local has_enable
    has_enable=$(echo "$datakit_config" | jq 'has("enable")' 2>/dev/null)
    
    if [ "$has_enable" = "true" ]; then
        # enable字段存在，获取实际值
        config_enable=$(echo "$datakit_config" | jq -r '.enable' 2>/dev/null)
        
        if [ "$config_enable" = "false" ]; then
            # enable=false: 停止Datakit服务
            log_info "配置enable=false，执行停止Datakit操作" >&2
            
            # 检查当前状态
            local current_status
            check_datakit_status && current_status="running" || current_status="stopped"
            
            if [ "$current_status" = "running" ]; then
                stop_datakit
                log_info "Datakit已停止" >&2
            else
                log_info "Datakit已经处于停止状态" >&2
            fi
            
            log_info "Datakit停止操作完成，跳过配置更新" >&2
            # enable=false的情况，返回false
            echo "false"
            return 0
            
        elif [ "$config_enable" = "true" ]; then
            # enable=true: 检查Datakit状态并执行配置更新
            log_info "配置enable=true，检查Datakit状态" >&2
            
            local current_status
            check_datakit_status && current_status="running" || current_status="stopped"
            
            if [ "$current_status" = "stopped" ]; then
                log_info "Datakit未运行，启动Datakit" >&2
                
                start_datakit
                
                log_info "Datakit启动完成，执行配置更新" >&2
            else
                log_info "Datakit正在运行，继续执行配置更新" >&2
            fi
        fi
    else
        log_info "未指定enable状态，使用默认逻辑" >&2
    fi
    
    # 返回config_enable值供主函数使用
    echo "$config_enable"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    # 重置配置变更标志
    # CONFIG_CHANGED=false
    
    log_info "开始执行 $CONFIG_UPDATE_SCRIPT_NAME v$CONFIG_UPDATE_SCRIPT_VERSION"
    
    # 获取配置
    get_host_ip || {
        handle_error "NETWORK_ERROR" "获取主机IP失败" "ERROR" "false"
        return 1
    }

    get_ops_config || {
        handle_error "API_ERROR" "获取运维平台配置失败" "ERROR" "false"
        return 1
    }
    
    # 从全局状态获取DATAKIT_CONFIG
    local datakit_config
    datakit_config=$(get_global_state 'DATAKIT_CONFIG')
    
    # 处理Datakit服务控制
    local config_enable
    
    # 调用服务控制函数并获取返回值
    config_enable=$(handle_datakit_service_control "$datakit_config")
    
    log_info "config_enable: '$config_enable'"
    
    # 如果enable=false，直接退出脚本
    if [ "$config_enable" = "false" ]; then
        log_info "Datakit已停止，跳过配置更新，脚本执行完成"
        SCRIPT_EXIT_CODE=0
        # TODO handle_error xxxx
        return 0
    fi
    
    # 处理所有配置修改（不重启）
    # 将datakit_config传递给处理函数
    DATAKIT_CONFIG="$datakit_config"
    handle_global_config
    handle_input_config
    
    # 所有配置完成后，统一重启Datakit（仅在enable=true且Datakit运行时）

    if [ "$CONFIG_CHANGED" = "true" ]; then
        log_info "检测到配置变更，创建版本目录"
        
        # 创建版本目录
        # TODO runtime_dirs 统一配置
        if command -v init_runtime_dirs >/dev/null 2>&1; then
            init_runtime_dirs "$RUNTIME_ROOT" "true"
        fi
        
        # 备份当前Datakit配置目录到版本目录
        if [ -n "${RUNTIME_RELEASE:-}" ] && [ -d "/usr/local/datakit/conf.d" ]; then
            log_info "备份Datakit配置目录到版本目录: $RUNTIME_CONF_DIR"
            
            # 备份整个conf.d目录
            if cp -r "/usr/local/datakit/conf.d" "$RUNTIME_CONF_DIR/datakit_conf.d" 2>/dev/null; then
                log_info "Datakit配置目录备份完成: $RUNTIME_CONF_DIR/datakit_conf.d"
            else
                record_error "BACKUP_ERROR" "Datakit配置目录备份失败" "WARNING"
            fi
        fi
        
        # 删除临时文件到版本目录的逻辑（已移除）
        log_info "跳过临时文件移动，直接处理配置变更"
        
        if [ "$config_enable" = "true" ]; then
            log_info "所有配置已完成，重启Datakit"
            restart_datakit

        else
            log_info "配置已更新，但enable=false，不重启Datakit"
        fi
    else
        log_info "无配置变更，无需重启"
    fi
    
    # 输出配置更新总结
    if [ "$CONFIG_CHANGED" = "true" ]; then
        log_info "配置更新完成 - 检测到配置变更"
    else
        log_info "配置更新完成 - 无配置变更，所有配置已是最新状态"
    fi
    
    # 记录脚本结束
    SCRIPT_EXIT_CODE=0
    
}

# =============================================================================
# 脚本入口
# =============================================================================


main "$@"
