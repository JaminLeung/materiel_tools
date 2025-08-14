#!/bin/bash

# Datakit业务配置同步脚本 - 生产版本
# 功能：从运维平台获取业务可观测配置，同步到Datakit采集器
# 版本：2.0.0
# 作者：Datakit运维团队

set -euo pipefail

# =============================================================================
# 加载核心模块
# =============================================================================
# 获取脚本所在目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CORE_DIR="$SCRIPT_DIR/../core"

# TODO 项目全局不使用 echo
# 加载基础配置
source "$SCRIPT_DIR/../config/loader.sh" 2>/dev/null || echo "警告: 无法加载loader.sh" >&2
load_all_configs "${ENV:-test}" "app_init"

# 设置日志文件路径（从配置文件中加载）
export LOG_FILE="$APP_INIT_LOG_FILE"

# 加载核心模块
source "$CORE_DIR/logging.sh" 2>/dev/null || echo "警告: 无法加载logging.sh" >&2
source "$CORE_DIR/utils.sh" 2>/dev/null || echo "警告: 无法加载utils.sh" >&2
source "$CORE_DIR/datakit_service.sh" 2>/dev/null || echo "警告: 无法加载datakit_service.sh" >&2

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

# 计数器 记录diff 差异
diff_count=0
diff_count_logging=0
diff_count_metrics=0
diff_count_health=0

# 日志差异文件列表
logging_diff_file_list=()
# 指标差异文件列表
metrics_diff_file_list=()
# 健康检查差异文件列表
health_diff_file_list=()

# =============================================================================
# 工具函数
# =============================================================================
# 注意：die函数已废弃，使用handle_error替代

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录"
    
    # 创建运行时目录（移除 APP_INIT_TEMP_DIR）
    local dirs=("$APP_INIT_BACKUP_DIR" "$APP_INIT_LOGGING_TMP_DIR" "$APP_INIT_METRICS_TMP_DIR" "$APP_INIT_HEALTH_TMP_DIR" 
                "$APP_INIT_LOGGING_PREV_DIR" "$APP_INIT_METRICS_PREV_DIR" "$APP_INIT_HEALTH_PREV_DIR"
                "$APP_INIT_LOGGING_DIR" "$APP_INIT_METRICS_DIR" "$APP_INIT_HEALTH_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
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
    
    check_command yj
    yj -t < "$toml_file" 2>/dev/null || {
        handle_error "FILE_ERROR" "TOML文件读取失败: $toml_file" "ERROR" "false"
        return 1
    }
}

update_toml_config() {
    local toml_file="$1"
    local json_data="$2"
    
    # 备份原文件到备份目录
    local filename=$(basename "$toml_file")
    local backup_file="${APP_INIT_BACKUP_DIR}/${filename}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$toml_file" "$backup_file"
    log_info "备份配置文件: $filename -> $(basename "$backup_file")"
    
    # 更新配置文件
    echo "$json_data" | yj -jt > "$toml_file" 2>/dev/null || {
        handle_error "FILE_ERROR" "配置文件更新失败: $toml_file" "ERROR" "false"
        return 1
    }
    
    log_info "配置文件更新成功: $toml_file"
    return 0
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
        log_type=$(echo "$logging" | jq -r ".tags.logType" 2>/dev/null || echo "default")
        
        # 构建日志配置内容
        local logging_content
        logging_content=$(echo "{\"inputs\": {\"logging\": [$logging]}}" | jq -r ".")
        
        if ! echo "$logging_content" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "日志配置内容不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 转换为TOML格式
        local logging_content_toml
        logging_content_toml=$(echo "$logging_content" | yj -jt 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            record_error "VALIDATION_ERROR" "日志配置TOML转换失败" "ERROR"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${APP_INIT_LOGGING_TMP_DIR}/${service_name}_${log_type}_auto.conf"
        echo "$logging_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${APP_INIT_LOGGING_PREV_DIR}/${service_name}_${log_type}_auto.conf" "logging"
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
        
        # 转换为TOML格式
        local metrics_content_toml
        metrics_content_toml=$(echo "$metrics_content" | yj -jt 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            record_error "VALIDATION_ERROR" "指标配置TOML转换失败" "ERROR"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${APP_INIT_METRICS_TMP_DIR}/${service_name}_metrics_auto.conf"
        echo "$metrics_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${APP_INIT_METRICS_PREV_DIR}/${service_name}_metrics_auto.conf" "metrics"
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
        
        # 转换为TOML格式
        local health_content_toml
        health_content_toml=$(echo "$health_content" | yj -jt 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            record_error "VALIDATION_ERROR" "健康检查配置TOML转换失败" "ERROR"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${APP_INIT_HEALTH_TMP_DIR}/${service_name}_health_auto.conf"
        echo "$health_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${APP_INIT_HEALTH_PREV_DIR}/${service_name}_health_auto.conf" "health"
    done
}

# =============================================================================
# 配置差异处理
# =============================================================================
handle_config_diff() {
    local tmp_file="$1"
    local prev_file="$2"
    local config_type="$3"
    
    # 确保前一次存储目录存在
    local prev_dir=$(dirname "$prev_file")
    if [ ! -d "$prev_dir" ]; then
        mkdir -p "$prev_dir"
        log_info "创建前一次存储目录: $prev_dir"
    fi
    

    
    # 如果前一次存储目录存在同名文件，检查差异
    if [ -f "$prev_file" ]; then
        log_info "对比配置文件: $tmp_file vs $prev_file"
        local diff_result
        diff_result=$(diff "$tmp_file" "$prev_file" 2>/dev/null || echo "")
        
        if [ -n "$diff_result" ]; then
            log_info "发现配置差异: $tmp_file"
            
            # 更新前一次存储目录
            cp "$tmp_file" "$prev_file"
            
            # 增加计数器
            case "$config_type" in
                "logging")
                    diff_count_logging=$((diff_count_logging + 1))
                    logging_diff_file_list+=("$tmp_file")
                    ;;
                "metrics")
                    diff_count_metrics=$((diff_count_metrics + 1))
                    metrics_diff_file_list+=("$tmp_file")
                    ;;
                "health")
                    diff_count_health=$((diff_count_health + 1))
                    health_diff_file_list+=("$tmp_file")
                    ;;
            esac
            diff_count=$((diff_count + 1))
            CONFIG_CHANGED=true
        else
            log_info "配置无差异，跳过处理"
        fi
    else
        # 首次处理，直接复制
        log_info "首次处理配置: $tmp_file -> $prev_file"
        cp "$tmp_file" "$prev_file"
        
        # 增加计数器
        case "$config_type" in
            "logging")
                diff_count_logging=$((diff_count_logging + 1))
                logging_diff_file_list+=("$tmp_file")
                ;;
            "metrics")
                diff_count_metrics=$((diff_count_metrics + 1))
                metrics_diff_file_list+=("$tmp_file")
                ;;
            "health")
                diff_count_health=$((diff_count_health + 1))
                health_diff_file_list+=("$tmp_file")
                ;;
        esac
        diff_count=$((diff_count + 1))
        CONFIG_CHANGED=true
    fi
}

# =============================================================================
# 配置文件合并
# =============================================================================
merge_config_files() {
    log_info "开始合并配置文件"
    
    # 合并日志配置
    if [ ${#logging_diff_file_list[@]} -gt 0 ]; then
        log_info "合并日志配置文件"
        for file in "${logging_diff_file_list[@]}"; do
            merge_logging_config "$file"
        done
    fi
    
    # 合并指标配置
    if [ ${#metrics_diff_file_list[@]} -gt 0 ]; then
        log_info "合并指标配置文件"
        for file in "${metrics_diff_file_list[@]}"; do
            merge_metrics_config "$file"
        done
    fi
    
    # 合并健康检查配置
    if [ ${#health_diff_file_list[@]} -gt 0 ]; then
        log_info "合并健康检查配置文件"
        for file in "${health_diff_file_list[@]}"; do
            merge_health_config "$file"
        done
    fi
    
    log_info "配置文件合并完成"
}

merge_logging_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${APP_INIT_LOGGING_DIR}/${file}"
    
    log_info "合并日志配置: $file"
    
    if [ -f "$datakit_file" ]; then
        # 检查差异
        local diff_result
        diff_result=$(diff "$source" "$datakit_file" 2>/dev/null || echo "")
        
        if [ -n "$diff_result" ]; then
            log_info "合并日志配置到: $datakit_file"
            
            # 解析并合并JSON
            local source_json datakit_json merged_json
            source_json=$(cat "$source" | yj -tj 2>/dev/null)
            datakit_json=$(cat "$datakit_file" | yj -tj 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                merged_json=$(echo "$datakit_json" "$source_json" | jq -s '.[0].inputs.logging[0] * .[1].inputs.logging[0]' 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo "{\"inputs\":{\"logging\":[$merged_json]}}" | yj -jt > "$datakit_file"
                    log_info "日志配置合并成功"
                else
                    record_error "CONFIG_ERROR" "日志配置合并失败" "ERROR"
                fi
            else
                record_error "VALIDATION_ERROR" "JSON解析失败" "ERROR"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_info "日志配置复制成功"
    fi
}

merge_metrics_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${APP_INIT_METRICS_DIR}/${file}"
    
    log_info "合并指标配置: $file"
    
    if [ -f "$datakit_file" ]; then
        # 检查差异
        local diff_result
        diff_result=$(diff "$source" "$datakit_file" 2>/dev/null || echo "")
        
        if [ -n "$diff_result" ]; then
            log_info "合并指标配置到: $datakit_file"
            
            # 解析并合并JSON
            local source_json datakit_json merged_json
            source_json=$(cat "$source" | yj -tj 2>/dev/null)
            datakit_json=$(cat "$datakit_file" | yj -tj 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                merged_json=$(echo "$datakit_json" "$source_json" | jq -s '.[0].inputs.prom[0] * .[1].inputs.prom[0]' 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo "{\"inputs\":{\"prom\":[$merged_json]}}" | yj -jt > "$datakit_file"
                    log_info "指标配置合并成功"
                else
                    record_error "CONFIG_ERROR" "指标配置合并失败" "ERROR"
                fi
            else
                record_error "VALIDATION_ERROR" "JSON解析失败" "ERROR"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_info "指标配置复制成功"
    fi
}

merge_health_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${APP_INIT_HEALTH_DIR}/${file}"
    
    log_info "合并健康检查配置: $file"
    
    if [ -f "$datakit_file" ]; then
        # 检查差异
        local diff_result
        diff_result=$(diff "$source" "$datakit_file" 2>/dev/null || echo "")
        
        if [ -n "$diff_result" ]; then
            log_info "合并健康检查配置到: $datakit_file"
            
            # 解析并合并JSON
            local source_json datakit_json merged_json
            source_json=$(cat "$source" | yj -tj 2>/dev/null)
            datakit_json=$(cat "$datakit_file" | yj -tj 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                merged_json=$(echo "$datakit_json" "$source_json" | jq -s '.[0].inputs.host_healthcheck[0] * .[1].inputs.host_healthcheck[0]' 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo "{\"inputs\":{\"host_healthcheck\":[$merged_json]}}" | yj -jt > "$datakit_file"
                    log_info "健康检查配置合并成功"
                else
                    record_error "CONFIG_ERROR" "健康检查配置合并失败" "ERROR"
                fi
            else
                record_error "VALIDATION_ERROR" "JSON解析失败" "ERROR"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_info "健康检查配置复制成功"
    fi
}

# =============================================================================
# 配置文件清理和备份
# =============================================================================
cleanup_old_configs() {
    log_info "开始清理和备份旧配置文件"
    
    # 获取当前服务列表
    local current_services=()
    local services
    
    # 读取JSON数据并解析
    local tmp_json_file="${APP_INIT_BACKUP_DIR}/tmp.json"
    if jq -e '.data' "$tmp_json_file" >/dev/null 2>&1; then
        services=$(jq -c '.data[]' "$tmp_json_file" 2>/dev/null) || return 1
    else
        services=$(cat "$tmp_json_file" 2>/dev/null) || return 1
    fi
    
    # 提取服务名称
    for service in $services; do
        local service_name
        service_name=$(echo "$service" | jq -r 'keys[0]' 2>/dev/null)
        if [ -n "$service_name" ] && [ "$service_name" != "null" ]; then
            current_services+=("$service_name")
        fi
    done
    
    log_info "当前服务列表: ${current_services[*]}"
    
    # 清理日志配置
    cleanup_config_directory "$APP_INIT_LOGGING_DIR" "logging" "${current_services[@]}"
    
    # 清理指标配置
    cleanup_config_directory "$APP_INIT_METRICS_DIR" "metrics" "${current_services[@]}"
    
    # 清理健康检查配置
    cleanup_config_directory "$APP_INIT_HEALTH_DIR" "health" "${current_services[@]}"
    
    log_info "配置文件清理和备份完成"
}

cleanup_config_directory() {
    local config_dir="$1"
    local config_type="$2"
    shift 2
    local current_services=("$@")
    
    if [ ! -d "$config_dir" ]; then
        log_info "$config_type 配置目录不存在: $config_dir"
        return 0
    fi
    
    log_info "清理 $config_type 配置目录: $config_dir"
    
    # 遍历目录中的配置文件
    for config_file in "$config_dir"/*.conf; do
        if [ ! -f "$config_file" ]; then
            continue
        fi
        
        local filename=$(basename "$config_file")
        local service_name
        local should_backup=false
        
        # 根据配置类型检查文件格式并提取服务名称
        case "$config_type" in
            "logging")
                # 格式: xxx_*_auto.conf (任何以服务名开头并以_auto.conf结尾的文件)
                if [[ "$filename" =~ ^[^_]+_.*_auto\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_.*_auto\.conf$/\1/p')
                    should_backup=true
                else
                    log_info "跳过不符合日志格式的文件: $filename (应为 xxx_*_auto.conf)"
                    continue
                fi
                ;;
            "metrics")
                # 格式: xxx_metrics_auto.conf
                if [[ "$filename" =~ ^[^_]+_metrics_auto\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_metrics_auto\.conf$/\1/p')
                    should_backup=true
                else
                    log_info "跳过不符合指标格式的文件: $filename (应为 xxx_metrics_auto.conf)"
                    continue
                fi
                ;;
            "health")
                # 格式: xxx_health_auto.conf
                if [[ "$filename" =~ ^[^_]+_health_auto\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_health_auto\.conf$/\1/p')
                    should_backup=true
                fi
                ;;
        esac
        
        # 只有符合格式的文件才进行备份逻辑
        if [ "$should_backup" = true ]; then
            # 检查服务是否在当前服务列表中
            local found=false
            for service in "${current_services[@]}"; do
                if [ "$service" = "$service_name" ]; then
                    found=true
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                # 服务不在当前列表中，备份文件到备份目录
                local backup_file="${APP_INIT_BACKUP_DIR}/${filename}.backup_$(date +%Y%m%d_%H%M%S)"
                if mv "$config_file" "$backup_file"; then
                    log_info "备份旧配置文件: $filename -> $(basename "$backup_file")"
                    # 标记配置已变更，需要重启Datakit
                    CONFIG_CHANGED=true
                else
                    record_error "BACKUP_ERROR" "备份配置文件失败: $filename" "ERROR"
                fi
            else
                log_info "保留当前服务配置文件: $filename"
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
    local tmp_json_file="${APP_INIT_BACKUP_DIR}/tmp.json"
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
    log_info "开始执行 $APP_INIT_SCRIPT_NAME v$APP_INIT_SCRIPT_VERSION"
    
    # 检查依赖
    command_exists jq || {
        handle_error "DEPENDENCY_ERROR" "命令 'jq' 不存在" "ERROR" "false"
        return 1
    }
    command_exists yj || {
        handle_error "DEPENDENCY_ERROR" "命令 'yj' 不存在" "ERROR" "false"
        return 1
    }
    command_exists curl || {
        handle_error "DEPENDENCY_ERROR" "命令 'curl' 不存在" "ERROR" "false"
        return 1
    }
    
    # 校验Datakit运行状态
    log_info "校验Datakit运行状态"
    if ! check_datakit_status; then
        handle_error "SERVICE_ERROR" "Datakit未正常运行，跳过业务配置同步" "WARNING" "false"
        return 0
    fi
    log_info "Datakit运行状态正常，继续执行业务配置同步"
    
    # 初始化运行时目录（仅创建基础目录）
    if command -v init_runtime_dirs >/dev/null 2>&1; then
        init_runtime_dirs
    fi
    
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

    # 调用业务配置API
    local tmp_json_file="${APP_INIT_BACKUP_DIR}/tmp.json"
    local http_code


    http_code=$(curl -s -o "$tmp_json_file" -w "%{http_code}" -X POST "$APP_INIT_OPS_API_URL" \
        -H "Authorization: Token $ops_token" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$HOST_IP\"}" \
        --connect-timeout 10 \
        --max-time 30)
    
    log_info "response: $(cat $tmp_json_file )"
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
    
    # 合并配置文件
    merge_config_files
    
    # 清理和备份旧配置
    cleanup_old_configs
    
    # 清理旧备份目录
    cleanup_old_backup_dirs "$RUNTIME_ROOT" "$APP_INIT_BACKUP_KEEP_DAYS"
    
    # 输出统计信息
    log_info "配置差异统计:"
    log_info "  总差异数: $diff_count"
    log_info "  日志差异数: $diff_count_logging"
    log_info "  指标差异数: $diff_count_metrics"
    log_info "  健康检查差异数: $diff_count_health"
    
    # 如果有配置变更，创建版本目录并重启Datakit
    if [ "$CONFIG_CHANGED" = true ]; then
        log_info "检测到配置变更，创建版本目录"
        
        # 创建版本目录
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
