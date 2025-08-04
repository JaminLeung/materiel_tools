#!/bin/bash

# Datakit配置更新脚本 - 生产版本
# 功能：Datakit服务控制、全局配置修改、采集器配置管理
# 版本：2.0.0
# 作者：Datakit运维团队

set -euo pipefail

# =============================================================================
# 加载环境配置
# =============================================================================
# 配置加载函数
load_script_config() {
    # 检查是否通过installer.sh调用，如果是则配置已加载
    # 否则尝试加载默认配置或从环境变量获取
    if [[ -z "${DATAKIT_VERSION:-}" ]]; then
        # 尝试从环境变量获取配置文件路径
        local config_file="${DATAKIT_CONFIG_FILE:-}"
        
        if [[ -n "$config_file" ]]; then
            # 加载指定的配置文件
            if [[ -f "$config_file" ]]; then
                source "$config_file"
            elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config_file" ]]; then
                source "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config_file"
            else
                echo "[ERROR] 指定的配置文件不存在: $config_file" >&2
                exit 1
            fi
        else
            # 尝试加载默认配置
            local default_configs=("benjamin.sh" "production.sh" "development.sh")
            local config_loaded=false
            
            for config in "${default_configs[@]}"; do
                if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config" ]]; then
                    echo "[INFO] 加载默认配置文件: $config"
                    source "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config"
                    config_loaded=true
                    break
                fi
            done
            
            if [[ "$config_loaded" == "false" ]]; then
                echo "[ERROR] 未找到可用的配置文件，请设置 DATAKIT_CONFIG_FILE 环境变量" >&2
                exit 1
            fi
        fi
    fi
}

# 加载配置
load_script_config

# =============================================================================
# 脚本配置（从环境配置中获取）
# =============================================================================
# 注意：基础配置中的变量（SCRIPT_NAME, SCRIPT_VERSION, LOG_FILE等）会被环境配置覆盖
# 这里直接使用环境配置中的变量，不重新定义

# =============================================================================
# 路径配置（从环境配置中获取）
# =============================================================================
# 直接使用环境配置中的变量，不重新定义

# =============================================================================
# API配置（从环境配置中获取）
# =============================================================================
# 直接使用环境配置中的变量，不重新定义

# =============================================================================
# 全局变量
# =============================================================================
HOST_IP=""
ENV=""
WORKSPACE=""
DATAKIT_CONFIG=""
CONFIG_CHANGED=false

# =============================================================================
# 加载核心模块
# =============================================================================
source "$CONFIG_UPDATE_CORE_DIR/logging.sh"
source "$CONFIG_UPDATE_CORE_DIR/utils.sh"
source "$CONFIG_UPDATE_CORE_DIR/validation.sh"
# config_api.sh的功能已合并到utils.sh中
source "$CONFIG_UPDATE_CORE_DIR/health_check.sh"
source "$CONFIG_UPDATE_CORE_DIR/datakit_service.sh"
source "$CONFIG_UPDATE_CORE_DIR/config_file.sh"

# 初始化日志系统
init_logging

# =============================================================================
# 工具函数
# =============================================================================
die() {
    log_error "$1"
    exit 1
}



# 使用core模块中的get_host_ip函数

verify_datakit_health() {
    log_info "验证Datakit健康状态"
    sleep 3
    
    check_datakit_status || die "Datakit进程未运行"
    
    # 使用core模块中的timeout_execute函数
    if timeout_execute 10 "curl -s http://localhost:9529/v1/ping" "Datakit健康检查"; then
        log_success "Datakit健康检查通过"
        return 0
    else
        die "Datakit健康检查失败"
    fi
}

# =============================================================================
# 全局配置处理
# =============================================================================
handle_global_config() {
    log_info "处理全局配置"
    
    local global_config
    global_config=$(echo "$DATAKIT_CONFIG" | jq '.global_config // empty' 2>/dev/null) || return 0
    
    [ -n "$global_config" ] && [ "$global_config" != "null" ] || return 0
    
    local enabled_count
    enabled_count=$(echo "$global_config" | jq '[.[] | select(.enable == true)] | length' 2>/dev/null)
    [ "$enabled_count" -gt 0 ] || return 0
    
    log_info "发现 $enabled_count 个启用的全局配置项"
    
    [ -f "$CONFIG_UPDATE_DATAKIT_CONF" ] || die "Datakit配置文件不存在"
    
    local current_config
    current_config=$(read_toml_config "$CONFIG_UPDATE_DATAKIT_CONF") || die "读取配置文件失败"
    
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
        
        [ "$enable" = "true" ] && [ -n "$key" ] && [ -n "$value" ] || continue
        
        log_info "处理配置项: $key"
        
        # 确保key以点号开头
        local json_path="$key"
        [[ "$json_path" != .* ]] && json_path=".$json_path"
        
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
                log_error "配置更新失败: $key"
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
                log_error "配置添加失败: $key"
                continue
            }
            CONFIG_CHANGED=true
        fi
    done
    
    # 应用配置变更（不重启，等待所有配置完成后统一重启）
    if [ "$CONFIG_CHANGED" = "true" ]; then
        update_toml_config "$CONFIG_UPDATE_DATAKIT_CONF" "$updated_config" || die "配置文件更新失败"
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
                    log_error "配置文件创建失败，无法执行修改操作"
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
    
    # 优先使用备份目录中的备份文件
    local filename=$(basename "$input_path")
    local latest_backup=""
    local latest_timestamp=""
    
    # 在所有日期目录中查找最新的备份文件
    if [ -d "$CONFIG_UPDATE_BACKUP_BASE_DIR" ]; then
        while IFS= read -r -d '' backup_file; do
            [ -f "$backup_file" ] || continue
            local file_timestamp
            file_timestamp=$(stat -c %Y "$backup_file" 2>/dev/null || echo "0")
            if [ "$latest_timestamp" = "" ] || [ "$file_timestamp" -gt "$latest_timestamp" ]; then
                latest_timestamp="$file_timestamp"
                latest_backup="$backup_file"
            fi
        done < <(find "$CONFIG_UPDATE_BACKUP_BASE_DIR" -type f -path "*/config_update/${filename}.backup.*" -print0 2>/dev/null)
    fi
    
    # 恢复配置文件
    if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
        if safe_execute "cp '$latest_backup' '$input_path'" "从备份恢复配置文件"; then
            log_success "从备份恢复: $input_path"
            log_info "备份文件: $latest_backup"
            return 0
        fi
    fi
    
    # 使用sample文件
    local sample_path="${input_path}.sample"
    [ -f "$sample_path" ] || die "Sample文件不存在: $sample_path"
    
    if safe_execute "cp '$sample_path' '$input_path'" "从sample创建配置文件"; then
        log_success "从sample创建: $input_path"
        return 0
    else
        die "配置文件创建失败: $input_path"
    fi
}

handle_input_modify() {
    local input_path="$1"
    local key="$2"
    local value="$3"
    
    log_info "修改采集器配置: $key"
    
    local current_config
    current_config=$(read_toml_config "$input_path") || die "读取配置文件失败: $input_path"
    
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
            updated_config=$(set_json_path_value "$current_config" "$json_path" "$value") || die "配置更新失败: $key"
            update_toml_config "$input_path" "$updated_config" || die "配置文件更新失败: $input_path"
            log_success "配置更新成功: $key"
            CONFIG_CHANGED=true
        else
            log_info "配置相同，跳过更新: $key"
        fi
    else
        # 新增配置
        log_info "配置路径不存在，新增配置: $key"
        log_info "新增值: $value"
        local updated_config
        updated_config=$(set_json_path_value "$current_config" "$json_path" "$value") || die "配置新增失败: $key"
        update_toml_config "$input_path" "$updated_config" || die "配置文件更新失败: $input_path"
        log_success "配置新增成功: $key"
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
    
    log_success "配置文件已备份并删除: $backup_path"
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
    current_config=$(read_toml_config "$input_path") || die "读取配置文件失败: $input_path"
    
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
        updated_config=$(echo "$current_config" | jq "del(.$jq_path)" 2>/dev/null) || die "配置删除失败: $key"
        update_toml_config "$input_path" "$updated_config" || die "配置文件更新失败: $input_path"
        log_success "配置删除成功: $key"
    else
        log_info "配置路径不存在，无需删除: $key"
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    # 记录脚本开始
    record_script_start
    
    # 重置配置变更标志
    CONFIG_CHANGED=false
    
    log_info "开始执行 $CONFIG_UPDATE_SCRIPT_NAME v$CONFIG_UPDATE_SCRIPT_VERSION"
    
    # 检查依赖
    validate_required_commands || die "依赖检查失败"
    
    # 获取配置
    get_host_ip || die "获取主机IP失败"
    get_ops_config || die "获取运维平台配置失败"
    
    # 处理Datakit服务控制
    local config_enable
    
    # 从全局状态获取DATAKIT_CONFIG
    local datakit_config
    datakit_config=$(get_global_state 'DATAKIT_CONFIG')
    
    # 检查enable字段是否存在（包括false值）
    local has_enable
    has_enable=$(echo "$datakit_config" | jq 'has("enable")' 2>/dev/null)
    
    if [ "$has_enable" = "true" ]; then
        # enable字段存在，获取实际值
        config_enable=$(echo "$datakit_config" | jq -r '.enable' 2>/dev/null)
        
        if [ "$config_enable" = "false" ]; then
            # enable=false: 停止Datakit并停止健康检查定时任务
            log_info "配置enable=false，执行停止Datakit操作"
            
            # 检查当前状态
            local current_status
            check_datakit_status && current_status="running" || current_status="stopped"
            
            if [ "$current_status" = "running" ]; then
                stop_datakit
                log_info "Datakit已停止，检查健康检查定时任务状态"
                
                # 检查健康检查定时任务是否存在
                local health_check_script_path="$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT"
                if crontab -l 2>/dev/null | grep -q "$health_check_script_path"; then
                    log_info "发现健康检查定时任务，执行停止操作"
                    control_health_check_service stop
                else
                    log_info "健康检查定时任务不存在，无需停止"
                fi
            else
                log_info "Datakit已经处于停止状态"
            fi
            
            log_success "Datakit停止操作完成，跳过配置更新"
            return 0
            
        elif [ "$config_enable" = "true" ]; then
            # enable=true: 检查Datakit状态并执行配置更新
            log_info "配置enable=true，检查Datakit状态"
            
            local current_status
            check_datakit_status && current_status="running" || current_status="stopped"
            
            if [ "$current_status" = "stopped" ]; then
                log_info "Datakit未运行，启动Datakit和健康检查定时任务"
                
                start_datakit
                # verify_datakit_health
                
                # 检查健康检查定时任务是否存在
                local health_check_script_path="$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT"
                if crontab -l 2>/dev/null | grep -q "$health_check_script_path"; then
                    log_info "健康检查定时任务已存在，跳过安装"
                else
                    log_info "健康检查定时任务不存在，执行安装"
                    control_health_check_service start
                fi
                
                log_info "Datakit启动完成，执行配置更新"
            else
                log_info "Datakit正在运行，检查健康检查定时任务状态"
                
                # 检查健康检查定时任务是否存在
                local health_check_script_path="$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT"
                if crontab -l 2>/dev/null | grep -q "$health_check_script_path"; then
                    log_info "健康检查定时任务已存在，无需操作"
                else
                    log_info "健康检查定时任务不存在，执行安装"
                    control_health_check_service start
                fi
            fi
        fi
    else
        log_info "未指定enable状态，使用默认逻辑"
    fi
    
    # 处理所有配置修改（不重启）
    # 将datakit_config传递给处理函数
    DATAKIT_CONFIG="$datakit_config"
    handle_global_config
    handle_input_config
    
    # 所有配置完成后，统一重启Datakit（仅在enable=true且Datakit运行时）

    if [ "$CONFIG_CHANGED" = "true" ]; then
        if [ "$config_enable" = "true" ]; then
            log_info "所有配置已完成，重启Datakit"
            restart_datakit
            # verify_datakit_health
        else
            log_info "配置已更新，但enable=false，不重启Datakit"
        fi
    else
        log_info "无配置变更，无需重启"
    fi
    
    # 输出配置更新总结
    if [ "$CONFIG_CHANGED" = "true" ]; then
        log_success "配置更新完成 - 检测到配置变更"
    else
        log_success "配置更新完成 - 无配置变更，所有配置已是最新状态"
    fi
    
    # 记录脚本结束
    SCRIPT_EXIT_CODE=0
    record_script_end
}

# =============================================================================
# 脚本入口
# =============================================================================
# 设置错误处理
trap 'SCRIPT_EXIT_CODE=$?; SCRIPT_ERROR_MESSAGE="脚本执行出错"; record_script_end; exit $SCRIPT_EXIT_CODE' ERR

main "$@"
