#!/bin/bash

# Datakit业务配置同步脚本 - 生产版本
# 功能：从运维平台获取业务可观测配置，同步到Datakit采集器

set -euo pipefail

# =============================================================================
# 加载核心模块
# =============================================================================
# 获取脚本所在目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CORE_DIR="$SCRIPT_DIR/../core"
# TODO 项目全局不使用 echo   luke
# 加载基础配置

load_module "loader" "$SCRIPT_DIR/../config/loader.sh"
load_all_configs "${ENV:-test}" "app_init"

# 设置日志文件路径（从配置文件中加载）
# 日志文件路径将在init_logging函数中动态生成
# export LOG_FILE="$APP_INIT_LOG_FILE"

# 加载核心模块
load_module "logging" "$CORE_DIR/logging.sh"
load_module "utils" "$CORE_DIR/utils.sh"
load_module "datakit_service" "$CORE_DIR/datakit_service.sh"

# =============================================================================
# 配置变量（从base_config.sh加载）
# =============================================================================
# 直接使用base_config.sh中的APP_INIT_变量，无需重新赋值

# 所有配置变量都通过 load_all_configs 从配置文件中加载
# 无需在此处定义任何变量

# =============================================================================
# 全局变量
# =============================================================================
HOST_IP=""
OPS_TOKEN=""
CONFIG_CHANGED=false

# 配置变更计数器
config_change_count=0
config_change_logging=0
config_change_metrics=0
config_change_health=0

# =============================================================================
# 工具函数
# =============================================================================
# 注意：die函数已废弃，使用handle_error替代

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录"
    
    # 创建应用特定的目录（移除不必要的临时和对比目录）
    local dirs=("$APP_INIT_BACKUP_DIR" "$APP_INIT_LOGGING_DIR" "$APP_INIT_METRICS_DIR" "$APP_INIT_HEALTH_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            safe_execute "mkdir -p '$dir'" "创建目录: $dir"
        fi
    done
    
    log_info "目录创建完成"
}

# =============================================================================
# 运维平台API
# =============================================================================
# 运维平台API配置获取（使用utils.sh中的get_ops_config函数）
# =============================================================================
# =============================================================================
# 配置文件处理
# =============================================================================
read_toml_config() {
    local toml_file="$1"
    [ -f "$toml_file" ] || {
        handle_error "FILE_ERROR" "配置文件不存在: $toml_file" "ERROR" "false"
        return 1
    }
    

    yj -t < "$toml_file" 2>/dev/null || {
        handle_error "FILE_ERROR" "TOML文件读取失败: $toml_file" "ERROR" "false"
        return 1
    }
}

# =============================================================================
# 配置项映射定义
# =============================================================================
# 配置项比较路径映射
declare -A COMPARE_PATHS=(
    ["logging.tags"]=".inputs.logging[0].tags"
    ["logging.logfiles"]=".inputs.logging[0].logfiles"
    ["logging.source"]=".inputs.logging[0].source"
    ["metrics.urls"]=".inputs.prom[0].urls"
    ["metrics.interval"]=".inputs.prom[0].interval"
    ["metrics.tags"]=".inputs.prom[0].tags"
    ["health.url"]=".inputs.host_healthcheck[0].http[0].url"
    ["health.interval"]=".inputs.host_healthcheck[0].interval"
    ["health.tags"]=".inputs.host_healthcheck[0].tags"
)

# =============================================================================
# 配置项级处理函数
# =============================================================================
process_config_item() {
    local service_name="$1"
    local config_type="$2"
    local config_data="$3"
    local target_file="$4"
    
    log_info "处理配置项: $service_name - $config_type"
    
    # 读取运行中配置
    local current_config
    if [ -f "$target_file" ]; then
        current_config=$(read_toml_config "$target_file") || {
            record_error "VALIDATION_ERROR" "读取运行中配置文件失败: $target_file" "ERROR"
            return 1
        }
    else
        # 如果文件不存在，创建基础结构
        case "$config_type" in
            "logging")
                current_config='{"inputs":{"logging":[{}]}}'
                ;;
            "metrics")
                current_config='{"inputs":{"prom":[{}]}}'
                ;;
            "health")
                current_config='{"inputs":{"host_healthcheck":[{"http":[{}]}]}}'
                ;;
        esac
    fi
    
    # 配置项级比较和更新
    local has_changes=false
    local updated_config="$current_config"
    
    # 根据配置类型选择比较路径
    local compare_paths=()
    case "$config_type" in
        "logging")
            compare_paths=(".inputs.logging[0].tags" ".inputs.logging[0].logfiles" ".inputs.logging[0].source" ".inputs.logging[0].service")
            ;;
        "metrics")
            compare_paths=(".inputs.prom[0].urls" ".inputs.prom[0].interval" ".inputs.prom[0].tags")
            ;;
        "health")
            compare_paths=(".inputs.host_healthcheck[0].http[0].url" ".inputs.host_healthcheck[0].interval" ".inputs.host_healthcheck[0].tags")
            ;;
    esac
    
    # 逐项比较和更新
    for path in "${compare_paths[@]}"; do
        local new_value current_value
        new_value=$(get_json_path_value "$config_data" "$path" 2>/dev/null || echo "")
        current_value=$(get_json_path_value "$updated_config" "$path" 2>/dev/null || echo "")
        
        if [ "$new_value" != "$current_value" ] && [ -n "$new_value" ]; then
            log_info "发现配置差异: $path"
            log_info "  当前值: $current_value"
            log_info "  新值: $new_value"
            
            # 更新配置（使用改进的逻辑处理复杂JSON对象）
            local temp_updated
            if [[ "$new_value" =~ ^\{.*\}$ ]] || [[ "$new_value" =~ ^\[.*\]$ ]]; then
                # 对于复杂对象，使用临时变量
                local temp_file=$(mktemp)
                echo "$new_value" > "$temp_file"
                temp_updated=$(echo "$updated_config" | jq --argjson val "$(cat "$temp_file")" "$path = \$val" 2>/dev/null)
                rm -f "$temp_file"
            else
                # 对于简单值，使用原有逻辑
                if [[ "$new_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    temp_updated=$(echo "$updated_config" | jq "$path = $new_value" 2>/dev/null)
                elif [[ "$new_value" =~ ^(true|false)$ ]]; then
                    temp_updated=$(echo "$updated_config" | jq "$path = $new_value" 2>/dev/null)
                else
                    temp_updated=$(echo "$updated_config" | jq "$path = \"$new_value\"" 2>/dev/null)
                fi
            fi
            
            if [ $? -eq 0 ] && [ -n "$temp_updated" ]; then
                updated_config="$temp_updated"
            else
                record_error "CONFIG_ERROR" "配置更新失败: $path" "ERROR"
                continue
            fi
            has_changes=true
        fi
    done
    
    # 如果有变更，更新文件
    if [ "$has_changes" = true ]; then
        # 确保目标目录存在
        local target_dir=$(dirname "$target_file")
        if [ ! -d "$target_dir" ]; then
            mkdir -p "$target_dir"
        fi
        
        # 直接写入JSON，然后转换为TOML
        echo "$updated_config" | yj -jt > "$target_file" || {
            record_error "CONFIG_ERROR" "配置文件更新失败: $target_file" "ERROR"
            return 1
        }
        
        log_info "配置更新成功: $target_file"
        CONFIG_CHANGED=true
        
        # 增加配置变更计数器
        case "$config_type" in
            "logging")
                config_change_logging=$((config_change_logging + 1))
                ;;
            "metrics")
                config_change_metrics=$((config_change_metrics + 1))
                ;;
            "health")
                config_change_health=$((config_change_health + 1))
                ;;
        esac
        config_change_count=$((config_change_count + 1))
    else
        log_info "配置无差异，跳过更新: $target_file"
    fi
}

# =============================================================================
# 日志配置处理
# =============================================================================
process_logging() {
    local service_name="$1"
    local service="$2"
    
    log_info "处理日志配置: $service_name"
    
    local logging_count
    logging_count=$(echo "$service" | jq -r ".\"$service_name\".logging | length" 2>/dev/null || echo "0")
    
    for i in $(seq 0 $((logging_count - 1))); do
        local logging
        logging=$(echo "$service" | jq -r ".\"$service_name\".logging[$i]" 2>/dev/null)
        
        if [ "$logging" = "null" ] || [ -z "$logging" ]; then
            continue
        fi
        
        log_info "处理日志配置项 $((i + 1))/$logging_count"
        
        # 获取日志类型
        local log_type
        log_type=$(echo "$logging" | jq -r ".logType" 2>/dev/null || echo "default")
        
        # 构建日志配置内容
        local logging_content
        logging_content=$(echo "{\"inputs\": {\"logging\": [$logging]}}" | jq -r ".")
        #如果.inputs.logging[0].tags.service 不存在，则把service_name 写入到logging_content 中
        if ! echo "$logging_content" | jq -r ".inputs.logging[0].tags.service" 2>/dev/null; then
            logging_content=$(echo "$logging_content" | jq --arg service_name "$service_name" ".inputs.logging[0].tags.service = \$service_name")
        fi
        
        if ! echo "$logging_content" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "日志配置内容不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 构建目标文件路径
        local target_file="${APP_INIT_LOGGING_DIR}/${service_name}_${log_type}_auto.conf"
        
        # 直接处理配置项
        process_config_item "$service_name" "logging" "$logging_content" "$target_file"
    done
}

# =============================================================================
# 指标配置处理
# =============================================================================
process_metrics() {
    local service_name="$1"
    local service="$2"
    
    log_info "处理指标配置: $service_name"
    
    local metrics_count
    metrics_count=$(echo "$service" | jq -r ".\"$service_name\".metrics | length" 2>/dev/null || echo "0")
    
    for i in $(seq 0 $((metrics_count - 1))); do
        local metrics
        metrics=$(echo "$service" | jq -r ".\"$service_name\".metrics[$i]" 2>/dev/null)
        
        if [ "$metrics" = "null" ] || [ -z "$metrics" ]; then
            continue
        fi
        
        log_info "处理指标配置项 $((i + 1))/$metrics_count"
        
        # 构建指标配置内容
        local metrics_content
        metrics_content=$(echo "{\"inputs\": {\"prom\": [$metrics]}}" | jq -r ".")
        
        if ! echo "$metrics_content" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "指标配置内容不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 构建目标文件路径
        local target_file="${APP_INIT_METRICS_DIR}/${service_name}_metrics_auto.conf"
        
        # 直接处理配置项
        process_config_item "$service_name" "metrics" "$metrics_content" "$target_file"
    done
}

# =============================================================================
# 健康检查配置处理
# =============================================================================
process_health() {
    local service_name="$1"
    local service="$2"
    
    log_info "处理健康检查配置: $service_name"
    
    local health_count
    health_count=$(echo "$service" | jq -r ".\"$service_name\".health | length" 2>/dev/null || echo "0")
    
    for i in $(seq 0 $((health_count - 1))); do
        local health
        health=$(echo "$service" | jq -r ".\"$service_name\".health[$i]" 2>/dev/null)
        
        if [ "$health" = "null" ] || [ -z "$health" ]; then
            continue
        fi
        
        log_info "处理健康检查配置项 $((i + 1))/$health_count"
        
        # 构建健康检查配置内容
        local health_content
        health_content=$(echo "{\"inputs\": {\"host_healthcheck\":[{\"interval\": \"1m\" ,\"http\": [$health]}]}}" | \
            jq -r '.inputs.host_healthcheck[0].tags = .inputs.host_healthcheck[0].http[0].tags' | \
            jq -r '.inputs.host_healthcheck[0].http[0].method = "GET"')
        
        if ! echo "$health_content" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "健康检查配置内容不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 构建目标文件路径
        local target_file="${APP_INIT_HEALTH_DIR}/${service_name}_health_auto.conf"
        
        # 直接处理配置项
        process_config_item "$service_name" "health" "$health_content" "$target_file"
    done
}

# =============================================================================
# 配置文件清理和备份
# =============================================================================
cleanup_old_configs() {
    log_info "开始清理和备份旧配置文件"
    
    # 读取JSON数据并解析
    local services
    local tmp_json_file="$RUNTIME_DIR/tmp/app_init/tmp.json"
    if jq -e '.data' "$tmp_json_file" >/dev/null 2>&1; then
        services=$(jq -c '.data[]' "$tmp_json_file" 2>/dev/null) || return 1
    else
        services=$(cat "$tmp_json_file" 2>/dev/null) || return 1
    fi
    
    # 构建运维平台配置的完整映射
    declare -A ops_logging_configs    # 格式: service_logtype -> true
    declare -A ops_metrics_configs    # 格式: service -> true
    declare -A ops_health_configs     # 格式: service -> true
    
    # 解析每个服务的配置
    for service in $services; do
        local service_name
        service_name=$(echo "$service" | jq -r 'keys[0]' 2>/dev/null)
        
        if [ -z "$service_name" ] || [ "$service_name" = "null" ]; then
            continue
        fi
        
        log_info "解析服务配置: $service_name"
        
        # 解析日志配置
        local logging_count
        logging_count=$(echo "$service" | jq -r ".\"$service_name\".logging | length" 2>/dev/null || echo "0")
        for i in $(seq 0 $((logging_count - 1))); do
            local logging
            logging=$(echo "$service" | jq -r ".\"$service_name\".logging[$i]" 2>/dev/null)
            if [ "$logging" != "null" ] && [ -n "$logging" ]; then
                local log_type
                log_type=$(echo "$logging" | jq -r ".logType" 2>/dev/null || echo "default")
                local config_key="${service_name}_${log_type}"
                ops_logging_configs["$config_key"]=true
                log_info "  日志配置: $config_key"
            fi
        done
        
        # 解析指标配置
        local metrics_count
        metrics_count=$(echo "$service" | jq -r ".\"$service_name\".metrics | length" 2>/dev/null || echo "0")
        if [ "$metrics_count" -gt 0 ]; then
            ops_metrics_configs["$service_name"]=true
            log_info "  指标配置: $service_name"
        fi
        
        # 解析健康检查配置
        local health_count
        health_count=$(echo "$service" | jq -r ".\"$service_name\".health | length" 2>/dev/null || echo "0")
        if [ "$health_count" -gt 0 ]; then
            ops_health_configs["$service_name"]=true
            log_info "  健康检查配置: $service_name"
        fi
    done
    
    # 清理日志配置
    cleanup_config_directory "$APP_INIT_LOGGING_DIR" "logging" ops_logging_configs
    
    # 清理指标配置
    cleanup_config_directory "$APP_INIT_METRICS_DIR" "metrics" ops_metrics_configs
    
    # 清理健康检查配置
    cleanup_config_directory "$APP_INIT_HEALTH_DIR" "health" ops_health_configs
    
    log_info "配置文件清理完成"
}

cleanup_config_directory() {
    local config_dir="$1"
    local config_type="$2"
    local -n ops_configs="$3"  # 使用引用传递关联数组
    
    if [ ! -d "$config_dir" ]; then
        log_info "$config_type 配置目录不存在: $config_dir"
        return 0
    fi
    
    log_info "清理 $config_type 配置目录: $config_dir"
    
    # 确保版本目录存在
    local version_tmp_dir=""
    if [ -n "${RUNTIME_RELEASE:-}" ]; then
        version_tmp_dir="$RUNTIME_RELEASE/tmp"
        mkdir -p "$version_tmp_dir"
    else
        # 如果没有版本目录，使用备份目录
        version_tmp_dir="$APP_INIT_BACKUP_DIR"
    fi
    
    # 遍历目录中的配置文件
    for config_file in "$config_dir"/*.conf; do
        if [ ! -f "$config_file" ]; then
            continue
        fi
        
        local filename=$(basename "$config_file")
        local config_key=""
        local should_check=false
        
        # 根据配置类型检查文件格式并提取配置键
        case "$config_type" in
            "logging")
                # 格式: xxx_*_auto.conf -> 提取 service_logtype
                if [[ "$filename" =~ .*_auto\.conf$ ]]; then
                    # 使用sed提取服务名和日志类型
                    local service_name=$(echo "$filename" | sed 's/^\(.*\)_\([^_]*\)_auto\.conf$/\1/')
                    local log_type=$(echo "$filename" | sed 's/^.*_\([^_]*\)_auto\.conf$/\1/')
                    if [ -n "$service_name" ] && [ -n "$log_type" ] && [ "$service_name" != "$filename" ] && [ "$log_type" != "$filename" ]; then
                        config_key="${service_name}_${log_type}"
                        should_check=true
                        log_info "解析日志配置: $filename -> $config_key"
                    else
                        log_info "跳过不符合日志格式的文件: $filename (应为 xxx_logtype_auto.conf)"
                        continue
                    fi
                else
                    log_info "跳过不符合日志格式的文件: $filename (应为 xxx_logtype_auto.conf)"
                    continue
                fi
                ;;
            "metrics")
                # 格式: xxx_metrics_auto.conf -> 提取 service
                if [[ "$filename" =~ .*_metrics_auto\.conf$ ]]; then
                    # 使用sed提取服务名
                    local service_name=$(echo "$filename" | sed 's/^\(.*\)_metrics_auto\.conf$/\1/')
                    if [ -n "$service_name" ] && [ "$service_name" != "$filename" ]; then
                        config_key="$service_name"
                        should_check=true
                        log_info "解析指标配置: $filename -> $config_key"
                    else
                        log_info "跳过不符合指标格式的文件: $filename (应为 xxx_metrics_auto.conf)"
                        continue
                    fi
                else
                    log_info "跳过不符合指标格式的文件: $filename (应为 xxx_metrics_auto.conf)"
                    continue
                fi
                ;;
            "health")
                # 格式: xxx_health_auto.conf -> 提取 service
                if [[ "$filename" =~ .*_health_auto\.conf$ ]]; then
                    # 使用sed提取服务名
                    local service_name=$(echo "$filename" | sed 's/^\(.*\)_health_auto\.conf$/\1/')
                    if [ -n "$service_name" ] && [ "$service_name" != "$filename" ]; then
                        config_key="$service_name"
                        should_check=true
                        log_info "解析健康检查配置: $filename -> $config_key"
                    else
                        log_info "跳过不符合健康检查格式的文件: $filename (应为 xxx_health_auto.conf)"
                        continue
                    fi
                else
                    log_info "跳过不符合健康检查格式的文件: $filename (应为 xxx_health_auto.conf)"
                    continue
                fi
                ;;
        esac
        
        # 只有符合格式的文件才进行检查
        if [ "$should_check" = true ]; then
            # 检查配置是否在运维平台配置中
            if [ -z "${ops_configs[$config_key]:-}" ]; then
                # 配置不在运维平台中，移动到版本目录
                local backup_file="${version_tmp_dir}/${filename}.removed_$(date +%Y%m%d_%H%M%S)"
                if mv "$config_file" "$backup_file"; then
                    log_info "移除旧配置文件: $filename -> $(basename "$backup_file")"
                    log_info "  原因: 配置 '$config_key' 不在运维平台中"
                    # 标记配置已变更，需要重启Datakit
                    CONFIG_CHANGED=true
                else
                    record_error "BACKUP_ERROR" "移除配置文件失败: $filename" "ERROR"
                fi
            else
                log_info "保留配置文件: $filename (配置 '$config_key' 在运维平台中)"
            fi
        fi
    done
}

# =============================================================================
# 主处理函数
# =============================================================================
process_services() {
    log_info "开始处理服务配置"
    
    # 读取JSON数据并解析
    local services
    local tmp_json_file="$RUNTIME_DIR/tmp/app_init/tmp.json"
    # 检查是否有data字段，如果没有则直接使用根对象
    if jq -e '.data' "$tmp_json_file" >/dev/null 2>&1; then
        services=$(jq -c '.data[]' "$tmp_json_file" 2>/dev/null) || {
        handle_error "VALIDATION_ERROR" "JSON数据解析失败" "ERROR" "false"
        return 1
    }
    else
        # 如果没有data字段，将整个JSON对象作为一个服务处理
        services=$(cat "$tmp_json_file" 2>/dev/null) || {
            handle_error "VALIDATION_ERROR" "JSON数据解析失败" "ERROR" "false"
            return 1
        }
    fi
    
    local service_count=0
    for service in $services; do
        service_count=$((service_count + 1))
        local service_name
        service_name=$(echo "$service" | jq -r 'keys[0]' 2>/dev/null)
        
        if [ -z "$service_name" ] || [ "$service_name" = "null" ]; then
            record_error "VALIDATION_ERROR" "跳过无效的服务配置" "WARNING"
            continue
        fi
        
        log_info "处理服务 $service_count: $service_name"
        
        # 处理各种配置类型
        process_logging "$service_name" "$service"
        process_metrics "$service_name" "$service"
        process_health "$service_name" "$service"
    done
    
    log_info "服务配置处理完成，共处理 $service_count 个服务"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    # 初始化日志系统（传入脚本类型）
    RUNTIME_RELEASE=$(get_global_state "RUNTIME_RELEASE")
    RUNTIME_RELEASE_DIR=$(get_global_state "RUNTIME_RELEASE_DIR")
    
    init_logging "app_init"
    
    log_info "开始执行 $APP_INIT_SCRIPT_NAME v$APP_INIT_SCRIPT_VERSION"
    ## 

    
    # 校验Datakit运行状态
    log_info "校验Datakit运行状态"
    if ! check_datakit_status; then
        handle_error "SERVICE_ERROR" "Datakit未正常运行，跳过业务配置同步" "WARNING" "false"
        return 0
    fi
    log_info "Datakit运行状态正常，继续执行业务配置同步"
    
    # # 初始化运行时环境（仅创建基础目录）
    # if command -v init_runtime_environment >/dev/null 2>&1; then
    #     init_runtime_environment
    # else
    #     # 兼容性处理：如果新函数不可用，使用旧函数
    #     if command -v init_runtime_dirs >/dev/null 2>&1; then
    #         init_runtime_dirs
    #     fi
    # fi
    
    # 创建必要的目录
    create_directories
    
    # 获取配置
    get_host_ip
    HOST_IP=$(get_global_state 'HOST_IP')
    
    # 获取业务配置数据
    log_info "获取业务配置数据"
    local ops_token=""
    local config_py_file="${CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}"
    
    # 从配置文件获取OPS_TOKEN
    if [ -f "$config_py_file" ]; then
        ops_token=$(grep -v '^\s*#' "$config_py_file" | grep -oP "ops_token = '\K[^']+" 2>/dev/null || echo "")
    fi
    
    # 如果从配置文件获取失败，尝试使用环境变量
    if [ -z "$ops_token" ]; then
        ops_token="${OPS_TOKEN:-}"
    fi
    
    if [ -z "$ops_token" ]; then
        handle_error "CONFIG_ERROR" "无法获取OPS_TOKEN" "ERROR" "false"
        return 1
    fi
    
    # 随机休眠避免并发请求
    local random_number=$((RANDOM % 60 + 1))
    log_info "随机休眠 $random_number 秒"
    sleep $random_number
    #sleep 2
    


    # 调用业务配置API
    local tmp_json_file="$RUNTIME_RELEASE_DIR/backup/app_init.json"
    local http_code

    log_info "开始请求业务配置API $APP_INIT_OPS_API_URL"

    # 判断curl执行是否成功，如果成功，则返回200，否则返回错误码
    http_code=$(curl -s -o "$tmp_json_file" -w "%{http_code}" -X POST "$APP_INIT_OPS_API_URL" \
        -H "Authorization: Token $ops_token" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$HOST_IP\"}" \
        --connect-timeout 10 \
        --max-time 30)

    log_info "开始请求业务配置API 完成✅"
    log_info "response: $(cat $tmp_json_file)"
    # 检查HTTP状态码
    if [ "$http_code" -eq 28 ]; then
        handle_error "TIMEOUT_ERROR" "请求超时，当前连接超时设置为10s，最大请求时间为30s" "ERROR" "false"
        return 1
    elif [ "$http_code" -ne 200 ]; then
        case "$http_code" in
            400) handle_error "API_ERROR" "错误请求，可能是请求参数有误" "ERROR" "false" ;;
            401) handle_error "API_ERROR" "未授权，检查Token是否有效" "ERROR" "false" ;;
            403) handle_error "API_ERROR" "禁止访问，您没有权限访问该资源" "ERROR" "false" ;;
            404) handle_error "API_ERROR" "未找到，检查URL是否正确" "ERROR" "false" ;;
            500) handle_error "API_ERROR" "服务器内部错误，请稍后重试" "ERROR" "false" ;;
            502) handle_error "API_ERROR" "错误网关，可能是上游服务器问题" "ERROR" "false" ;;
            503) handle_error "API_ERROR" "服务不可用，服务器当前无法处理请求" "ERROR" "false" ;;
            504) handle_error "API_ERROR" "网关超时，服务器未能及时响应" "ERROR" "false" ;;
            *) handle_error "API_ERROR" "其他错误，HTTP状态码: $http_code" "ERROR" "false" ;;
        esac
        return 1
    fi
    
    # 验证JSON格式
    if ! jq empty "$tmp_json_file" 2>/dev/null; then
        handle_error "VALIDATION_ERROR" "响应结果不是有效的JSON格式" "ERROR" "false"
        return 1
    fi
    
    log_info "业务配置获取成功"
    
    # 处理服务配置
    process_services
    
    # 清理和备份旧配置
    # TODO 确认是否整合
    # cleanup_old_configs
    
    # 注意：Runtime清理逻辑已移动到 error_handler.sh 的 cleanup_on_exit 中，会在脚本退出时自动执行
    
    # 输出配置变更统计信息
    log_info "配置变更统计:"
    log_info "  总变更数: $config_change_count"
    log_info "  日志变更数: $config_change_logging"
    log_info "  指标变更数: $config_change_metrics"
    log_info "  健康检查变更数: $config_change_health"
    log_info "  CONFIG_CHANGED: $CONFIG_CHANGED"
    # 如果有配置变更，创建版本目录并重启Datakit
    if [ "$CONFIG_CHANGED" = true ]; then
        set_global_state "CONFIG_CHANGED" "true"
        # log_info "检测到配置变更，创建版本目录"
        
        # # 创建版本目录
        # if command -v init_runtime_environment >/dev/null 2>&1; then
        #     init_runtime_environment "true" "app_init"
        # else
        #     # 兼容性处理：如果新函数不可用，使用旧函数
        #     if command -v init_runtime_dirs >/dev/null 2>&1; then
        #         init_runtime_dirs "$RUNTIME_DIR" "true"
        #     fi
        # fi

        log_info "开始备份tmp.json 到版本目录: $RUNTIME_RELEASE_DIR"
        # 复制tmp_json_file 到版本目录
        if cp -r "$tmp_json_file" "$RUNTIME_RELEASE_DIR/backup/app_init/tmp.json" 2>/dev/null; then
            log_info "tmp.json 备份完成: $RUNTIME_RELEASE_DIR/backup/app_init/tmp.json"
        else
            record_error "BACKUP_ERROR" "tmp.json 备份失败" "WARNING"
        fi

        # 删除临时文件到版本目录的逻辑（已移除）
        log_info "跳过临时文件移动，直接处理配置变更"
        
        log_info "检测到配置变更，重启Datakit"
        restart_datakit
        log_info "Datakit重启完成"
    else
        log_info "无配置变更，无需重启Datakit"
    fi
    
    log_info "业务配置同步完成"
}


# =============================================================================
# 脚本入口
# =============================================================================
main "$@"

