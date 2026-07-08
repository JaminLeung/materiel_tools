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
HOST_IP="${HOST_IP:-}"
OPS_TOKEN="${OPS_TOKEN:-}"
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
    
    # 根据配置类型选择比较策略
    case "$config_type" in
        "logging")
            # 日志配置：数组级别比较
            local new_logging_array current_logging_array
            
            # 获取新配置的logging数组
            new_logging_array=$(echo "$config_data" | jq -c '.inputs.logging' 2>/dev/null || echo "[]")
            
            # 获取当前配置的logging数组
            current_logging_array=$(echo "$updated_config" | jq -c '.inputs.logging' 2>/dev/null || echo "[]")
            
            log_info "日志配置比较:"
            log_info "  新配置项数: $(echo "$new_logging_array" | jq 'length' 2>/dev/null || echo "0")"
            log_info "  当前配置项数: $(echo "$current_logging_array" | jq 'length' 2>/dev/null || echo "0")"
            
            # 使用规范化比较，避免因JSON字段顺序导致的误判
            local normalized_new normalized_current
            
            # 规范化新配置：对每个logging配置项进行标准化处理
            normalized_new=$(echo "$new_logging_array" | jq -c '
                map({
                    logType: (.logType // ""),
                    logfiles: (.logfiles // []) | sort,
                    source: (.source // ""),
                    tags: (.tags // {}) | to_entries | sort_by(.key) | from_entries
                }) | sort_by(.logType, .logfiles, .source, .tags)')
            
            # 规范化当前配置
            normalized_current=$(echo "$current_logging_array" | jq -c '
                map({
                    logType: (.logType // ""),
                    logfiles: (.logfiles // []) | sort,
                    source: (.source // ""),
                    tags: (.tags // {}) | to_entries | sort_by(.key) | from_entries
                }) | sort_by(.logType, .logfiles, .source, .tags)')
            
            log_info "规范化后的配置:"
            log_info "  新配置: $normalized_new"
            log_info "  当前配置: $normalized_current"
            
            # 比较规范化后的配置
            if [ "$normalized_new" != "$normalized_current" ]; then
                log_info "发现日志配置差异，需要更新"
                log_info "  新配置: $normalized_new"
                log_info "  当前配置: $normalized_current"
                
                # 更新整个logging数组
                updated_config=$(echo "$updated_config" | jq --argjson new_array "$new_logging_array" '.inputs.logging = $new_array' 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$updated_config" ]; then
                    has_changes=true
                    log_info "日志配置更新成功"
                else
                    record_error "CONFIG_ERROR" "日志配置更新失败" "ERROR"
                fi
            else
                log_info "日志配置无差异，跳过更新"
            fi
            ;;
        "metrics")
            # 指标配置：基于关键字段的增量对比
            local new_prom_array current_prom_array
            
            # 过滤新配置中的空URLs配置项
            new_prom_array=$(echo "$config_data" | jq -c '.inputs.prom | map(select(.urls // [] | length > 0 and all(. != "" and . != null)))' 2>/dev/null || echo "[]")
            
            # 过滤当前配置中的空URLs配置项
            current_prom_array=$(echo "$updated_config" | jq -c '.inputs.prom | map(select(.urls // [] | length > 0 and all(. != "" and . != null)))' 2>/dev/null || echo "[]")
            
            log_info "过滤空URLs后的配置:"
            log_info "  新配置项数: $(echo "$new_prom_array" | jq 'length' 2>/dev/null || echo "0")"
            log_info "  当前配置项数: $(echo "$current_prom_array" | jq 'length' 2>/dev/null || echo "0")"
            
            # 使用规范化比较，避免因JSON字段顺序导致的误判
            # 对每个配置项进行深度规范化
            local normalized_new normalized_current
            
            # 规范化新配置：对每个配置项进行标准化处理
            normalized_new=$(echo "$new_prom_array" | jq -c '
                map({
                    urls: (.urls // []) | sort,
                    interval: (.interval // ""),
                    tags: (.tags // {}) | to_entries | sort_by(.key) | from_entries
                }) | sort_by(.urls, .interval, .tags)
            ' 2>/dev/null || echo "$new_prom_array")
            
            # 规范化当前配置
            normalized_current=$(echo "$current_prom_array" | jq -c '
                map({
                    urls: (.urls // []) | sort,
                    interval: (.interval // ""),
                    tags: (.tags // {}) | to_entries | sort_by(.key) | from_entries
                }) | sort_by(.urls, .interval, .tags)
            ' 2>/dev/null || echo "$current_prom_array")
            
            log_info "规范化比较:"
            log_info "  新配置: $normalized_new"
            log_info "  当前配置: $normalized_current"
            
            # 检查是否有配置变更
            if [ "$normalized_new" != "$normalized_current" ]; then
                log_info "发现指标配置差异，开始基于关键字段对比"
                
                # 获取配置项数量
                local new_count current_count
                new_count=$(echo "$new_prom_array" | jq 'length' 2>/dev/null || echo "0")
                current_count=$(echo "$current_prom_array" | jq 'length' 2>/dev/null || echo "0")
                
                log_info "配置项数量对比: 当前=$current_count, 新增=$new_count"
                
                # 基于关键字段对比配置项（不依赖位置）
                local config_changes=0
                local added_configs=()
                local removed_configs=()
                local modified_configs=()
                
                # 构建新配置的标识映射（支持重复项计数）
                declare -A new_config_map
                declare -A new_config_count
                for i in $(seq 0 $((new_count - 1))); do
                    local new_item
                    new_item=$(echo "$new_prom_array" | jq -c ".[$i]" 2>/dev/null || echo "null")
                    
                    if [ "$new_item" = "null" ]; then
                        continue
                    fi
                    
                    # 提取关键字段用于匹配，使用规范化排序确保一致性
                    local new_tags new_urls
                    # 对tags进行规范化排序，确保字段顺序一致
                    new_tags=$(echo "$new_item" | jq -c '.tags // {} | to_entries | sort_by(.key) | from_entries' 2>/dev/null || echo "{}")
                    new_urls=$(echo "$new_item" | jq -c '.urls // [] | sort' 2>/dev/null || echo "[]")
                    
                    # 生成配置项标识，使用规范化后的字段
                    local key_identifier
                    if [ "$new_tags" = "{}" ] && [ "$new_urls" = "[]" ]; then
                        # 关键字段都为空，使用完整配置作为标识（规范化排序）
                        key_identifier=$(echo "$new_item" | jq -c 'del(.tags, .urls)' 2>/dev/null || echo "$new_item")
                        log_info "  警告: 新配置项关键字段为空，使用完整配置作为标识"
                    else
                        key_identifier="${new_tags}|${new_urls}"
                    fi
                    
                    # 记录配置项和计数
                    new_config_map["$key_identifier"]="$new_item"
                    new_config_count["$key_identifier"]=$((${new_config_count["$key_identifier"]:-0} + 1))
                    
                    # 检查重复配置项
                    if [ "${new_config_count[$key_identifier]}" -gt 1 ]; then
                        log_info "  警告: 发现重复的新配置项 (标识: $key_identifier, 数量: ${new_config_count[$key_identifier]})"
                    fi
                done
                
                # 构建当前配置的标识映射（支持重复项计数）
                declare -A current_config_map
                declare -A current_config_count
                for i in $(seq 0 $((current_count - 1))); do
                    local current_item
                    current_item=$(echo "$current_prom_array" | jq -c ".[$i]" 2>/dev/null || echo "null")
                    
                    if [ "$current_item" = "null" ]; then
                        continue
                    fi
                    
                    # 提取关键字段用于匹配，使用规范化排序确保一致性
                    local current_tags current_urls
                    # 对tags进行规范化排序，确保字段顺序一致
                    current_tags=$(echo "$current_item" | jq -c '.tags // {} | to_entries | sort_by(.key) | from_entries' 2>/dev/null || echo "{}")
                    current_urls=$(echo "$current_item" | jq -c '.urls // [] | sort' 2>/dev/null || echo "[]")
                    
                    # 生成配置项标识，使用规范化后的字段
                    local key_identifier
                    if [ "$current_tags" = "{}" ] && [ "$current_urls" = "[]" ]; then
                        # 关键字段都为空，使用完整配置作为标识（规范化排序）
                        key_identifier=$(echo "$current_item" | jq -c 'del(.tags, .urls)' 2>/dev/null || echo "$current_item")
                        log_info "  警告: 当前配置项关键字段为空，使用完整配置作为标识"
                    else
                        key_identifier="${current_tags}|${current_urls}"
                    fi
                    
                    # 记录配置项和计数
                    current_config_map["$key_identifier"]="$current_item"
                    current_config_count["$key_identifier"]=$((${current_config_count["$key_identifier"]:-0} + 1))
                    
                    # 检查重复配置项
                    if [ "${current_config_count[$key_identifier]}" -gt 1 ]; then
                        log_info "  警告: 发现重复的当前配置项 (标识: $key_identifier, 数量: ${current_config_count[$key_identifier]})"
                    fi
                done
                
                # 检查新增、修改和数量变化的配置项
                for key_identifier in "${!new_config_map[@]}"; do
                    local new_item="${new_config_map[$key_identifier]}"
                    local current_item="${current_config_map[$key_identifier]:-}"
                    local new_count="${new_config_count[$key_identifier]:-0}"
                    local current_count="${current_config_count[$key_identifier]:-0}"
                    
                    if [ -z "$current_item" ]; then
                        # 新增配置项
                        if [ "$new_count" -gt 1 ]; then
                            log_info "  新增配置项 (标识: $key_identifier, 数量: $new_count)"
                        else
                            log_info "  新增配置项 (标识: $key_identifier)"
                        fi
                        added_configs+=("$key_identifier")
                        config_changes=$((config_changes + 1))
                    elif [ "$new_item" != "$current_item" ]; then
                        # 修改配置项
                        log_info "  配置项修改 (标识: $key_identifier)"
                        log_info "    当前: $current_item"
                        log_info "    新值: $new_item"
                        modified_configs+=("$key_identifier")
                        config_changes=$((config_changes + 1))
                    elif [ "$new_count" != "$current_count" ]; then
                        # 数量变化
                        if [ "$new_count" -gt "$current_count" ]; then
                            log_info "  配置项数量增加 (标识: $key_identifier, 当前: $current_count -> 新值: $new_count)"
                        else
                            log_info "  配置项数量减少 (标识: $key_identifier, 当前: $current_count -> 新值: $new_count)"
                        fi
                        modified_configs+=("$key_identifier")
                        config_changes=$((config_changes + 1))
                    fi
                done
                
                # 检查删除的配置项
                for key_identifier in "${!current_config_map[@]}"; do
                    local current_item="${current_config_map[$key_identifier]}"
                    local new_item="${new_config_map[$key_identifier]:-}"
                    local current_count="${current_config_count[$key_identifier]:-0}"
                    
                    if [ -z "$new_item" ]; then
                        # 删除配置项
                        if [ "$current_count" -gt 1 ]; then
                            log_info "  删除配置项 (标识: $key_identifier, 数量: $current_count)"
                        else
                            log_info "  删除配置项 (标识: $key_identifier)"
                        fi
                        removed_configs+=("$key_identifier")
                        config_changes=$((config_changes + 1))
                    fi
                done
                
                # 输出变更统计
                if [ ${#added_configs[@]} -gt 0 ]; then
                    log_info "新增配置项数量: ${#added_configs[@]}"
                fi
                if [ ${#removed_configs[@]} -gt 0 ]; then
                    log_info "删除配置项数量: ${#removed_configs[@]}"
                fi
                if [ ${#modified_configs[@]} -gt 0 ]; then
                    log_info "修改配置项数量: ${#modified_configs[@]}"
                fi
                
                if [ "$config_changes" -gt 0 ]; then
                    log_info "检测到 $config_changes 个配置变更，更新配置"
                    log_info "变更详情:"
                    log_info "  新增配置项: ${#added_configs[@]}"
                    log_info "  修改配置项: ${#modified_configs[@]}"
                    log_info "  删除配置项: ${#removed_configs[@]}"
                    
                    # 直接替换整个prom数组
                    updated_config=$(echo "$updated_config" | jq --argjson prom_array "$new_prom_array" '.inputs.prom = $prom_array' 2>/dev/null)
                    if [ $? -eq 0 ] && [ -n "$updated_config" ]; then
                        has_changes=true
                        log_info "指标配置更新成功"
                    else
                        record_error "CONFIG_ERROR" "指标配置更新失败" "ERROR"
                    fi
                else
                    log_info "配置项内容无实际差异，跳过更新"
                    log_info "详细比较结果:"
                    log_info "  规范化新配置: $normalized_new"
                    log_info "  规范化当前配置: $normalized_current"
                fi
            else
                log_info "指标配置无差异，跳过更新"
            fi
            ;;
        "health")
            # 健康检查配置：逐项比较
            local compare_paths=(".inputs.host_healthcheck[0].http[0].url" ".inputs.host_healthcheck[0].interval" ".inputs.host_healthcheck[0].tags")
            for path in "${compare_paths[@]}"; do
                local new_value current_value
                new_value=$(get_json_path_value "$config_data" "$path" 2>/dev/null || echo "")
                current_value=$(get_json_path_value "$updated_config" "$path" 2>/dev/null || echo "")
                
                if [ "$new_value" != "$current_value" ] && [ -n "$new_value" ]; then
                    log_info "发现配置差异: $path"
                    log_info "  当前值: $current_value"
                    log_info "  新值: $new_value"
                    
                    # 更新配置
                    local temp_updated
                    if [[ "$new_value" =~ ^\{.*\}$ ]] || [[ "$new_value" =~ ^\[.*\]$ ]]; then
                        local temp_file=$(mktemp)
                        echo "$new_value" > "$temp_file"
                        temp_updated=$(echo "$updated_config" | jq --argjson val "$(cat "$temp_file")" "$path = \$val" 2>/dev/null)
                        mv "$temp_file" /tmp/datakit/
                    else
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
                        has_changes=true
                    else
                        record_error "CONFIG_ERROR" "配置更新失败: $path" "ERROR"
                    fi
                fi
            done
            ;;
    esac
    
    # 如果有变更，更新文件
    if [ "$has_changes" = true ]; then
        log_info "检测到配置变更，准备更新文件: $target_file"
        log_info "变更详情: 配置类型=$config_type, 服务名=$service_name"
        
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
        log_info "设置 CONFIG_CHANGED=true (原因: 配置更新成功)"
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
    
    if [ "$logging_count" -eq 0 ]; then
        log_info "服务 $service_name 没有日志配置，跳过处理"
        return 0
    fi
    
    log_info "发现 $logging_count 个日志配置项，开始按logType分组处理"
    
    # 收集所有有效的logging配置项，按logType分组
    # 使用关联数组存储配置项，key为logType，value为配置项数组
    declare -A logging_by_type
    local valid_count=0
    local invalid_count=0
    
    for i in $(seq 0 $((logging_count - 1))); do
        local logging
        logging=$(echo "$service" | jq -r ".\"$service_name\".logging[$i]" 2>/dev/null)
        
        if [ "$logging" = "null" ] || [ -z "$logging" ]; then
            log_info "跳过无效的日志配置项 $((i + 1))/$logging_count"
            invalid_count=$((invalid_count + 1))
            continue
        fi
        
        log_info "处理日志配置项 $((i + 1))/$logging_count"
        
        # 获取日志类型
        local log_type
        log_type=$(echo "$logging" | jq -r ".logType" 2>/dev/null || echo "default")
        
        # 确保tags.service存在
        if ! echo "$logging" | jq -r ".tags.service" 2>/dev/null; then
            logging=$(echo "$logging" | jq --arg service_name "$service_name" ".tags.service = \$service_name")
        fi
        
        # 验证JSON格式
        if ! echo "$logging" | jq empty 2>/dev/null; then
            log_info "跳过无效JSON格式的日志配置项 $((i + 1))/$logging_count"
            invalid_count=$((invalid_count + 1))
            continue
        fi
        
        # 将配置项添加到对应logType的数组中
        if [ -n "${logging_by_type[$log_type]:-}" ]; then
            logging_by_type["$log_type"]="${logging_by_type[$log_type]},$logging"
        else
            logging_by_type["$log_type"]="$logging"
        fi
        
        valid_count=$((valid_count + 1))
        log_info "日志配置项 $((i + 1)) 验证通过 (logType: $log_type)"
    done
    
    if [ "$valid_count" -eq 0 ]; then
        log_info "服务 $service_name 没有有效的日志配置，跳过处理"
        return 0
    fi
    
    # 输出统计信息
    log_info "日志配置统计: 有效配置项=$valid_count, 无效配置项=$invalid_count, logType数量=${#logging_by_type[@]}"
    
    # 处理每个logType的配置项
    for log_type in "${!logging_by_type[@]}"; do
        local logging_array="${logging_by_type[$log_type]}"
        
        # 构建包含多个logging配置项的JSON结构
        local logging_content
        logging_content=$(echo "{\"inputs\": {\"logging\": [$logging_array]}}" | jq -r ".")
        
        if ! echo "$logging_content" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "日志配置内容不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 构建目标文件路径
        local target_file="${APP_INIT_LOGGING_DIR}/${service_name}_${log_type}_auto.conf"
        
        # 处理配置项（支持多配置）
        log_info "开始处理日志配置: $service_name-$log_type (配置项数: $(echo "$logging_content" | jq '.inputs.logging | length')) -> $target_file"
        process_config_item "$service_name" "logging" "$logging_content" "$target_file"
        log_info "完成处理日志配置: $service_name-$log_type"
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
    
    if [ "$metrics_count" -eq 0 ]; then
        log_info "服务 $service_name 没有指标配置，跳过处理"
        return 0
    fi
    
    log_info "发现 $metrics_count 个指标配置项，开始合并处理"
    
    # 收集所有有效的metrics配置项（去重处理）
    local all_metrics=()
    local valid_count=0
    local duplicate_count=0
    
    # 用于去重的标识映射
    declare -A seen_configs
    
    for i in $(seq 0 $((metrics_count - 1))); do
        local metrics
        metrics=$(echo "$service" | jq -r ".\"$service_name\".metrics[$i]" 2>/dev/null)
        
        if [ "$metrics" = "null" ] || [ -z "$metrics" ]; then
            log_info "跳过无效的指标配置项 $((i + 1))/$metrics_count"
            continue
        fi
        
        log_info "处理指标配置项 $((i + 1))/$metrics_count"
        
        # 处理interval单位问题
        if ! echo "$metrics" | jq -r ".interval" 2>/dev/null | grep -q "s"; then
            local current_interval=$(echo "$metrics" | jq -r ".interval" 2>/dev/null)
            if [ -n "$current_interval" ] && [ "$current_interval" != "null" ]; then
                metrics=$(echo "$metrics" | jq --arg interval "${current_interval}s" ".interval = \$interval")
            fi
        fi
        
        # 验证JSON格式
        if ! echo "$metrics" | jq empty 2>/dev/null; then
            record_error "VALIDATION_ERROR" "指标配置项 $((i + 1)) 不是有效的JSON格式" "ERROR"
            continue
        fi
        
        # 检查URLs是否为空，如果为空则跳过此配置项
        local urls
        urls=$(echo "$metrics" | jq -c '.urls // []' 2>/dev/null || echo "[]")
        local urls_length
        urls_length=$(echo "$urls" | jq 'length' 2>/dev/null || echo "0")
        
        # 检查URLs数组是否为空或包含空字符串
        local has_valid_urls=false
        if [ "$urls_length" -gt 0 ]; then
            # 检查是否有非空URL
            for j in $(seq 0 $((urls_length - 1))); do
                local url
                url=$(echo "$urls" | jq -r ".[$j]" 2>/dev/null)
                if [ -n "$url" ] && [ "$url" != "null" ] && [ "$url" != "" ]; then
                    has_valid_urls=true
                    break
                fi
            done
        fi
        
        if [ "$has_valid_urls" = false ]; then
            log_info "跳过URLs为空的指标配置项 $((i + 1))/$metrics_count"
            log_info "  URLs内容: $urls"
            continue
        fi
        
        # 生成配置项标识用于去重
        local tags key_identifier
        tags=$(echo "$metrics" | jq -c '.tags // {}' 2>/dev/null || echo "{}")
        
        if [ "$tags" = "{}" ] && [ "$urls" = "[]" ]; then
            # 关键字段都为空，使用完整配置作为标识
            key_identifier=$(echo "$metrics" | jq -c 'del(.tags, .urls)' 2>/dev/null || echo "$metrics")
        else
            key_identifier="${tags}|${urls}"
        fi
        
        # 检查是否已存在相同配置项
        if [ -n "${seen_configs[$key_identifier]:-}" ]; then
            log_info "  警告: 发现重复的指标配置项 (标识: $key_identifier)"
            log_info "    已存在: ${seen_configs[$key_identifier]}"
            log_info "    重复项: $metrics"
            duplicate_count=$((duplicate_count + 1))
            continue
        fi
        
        # 记录已见过的配置项
        seen_configs["$key_identifier"]="$metrics"
        all_metrics+=("$metrics")
        valid_count=$((valid_count + 1))
        log_info "指标配置项 $((i + 1)) 验证通过"
    done
    
    if [ "$valid_count" -eq 0 ]; then
        log_info "服务 $service_name 没有有效的指标配置，跳过处理"
        return 0
    fi
    
    # 输出去重统计信息
    if [ "$duplicate_count" -gt 0 ]; then
        log_info "去重统计: 原始配置项=$metrics_count, 有效配置项=$valid_count, 重复项=$duplicate_count"
    else
        log_info "成功收集 $valid_count 个有效指标配置项，无重复项"
    fi
    
    log_info "开始合并 $valid_count 个指标配置项"
    
    # 合并所有metrics配置项到prom数组中
    local merged_metrics
    if [ "$valid_count" -eq 1 ]; then
        # 只有一个配置项，直接使用
        merged_metrics="[${all_metrics[0]}]"
    else
        # 多个配置项，使用jq合并
        merged_metrics=$(printf '%s\n' "${all_metrics[@]}" | jq -s '.')
    fi
    
    # 构建最终的配置内容
    local metrics_content
    metrics_content=$(echo "{\"inputs\": {\"prom\": $merged_metrics}}" | jq -r ".")
    
    log_info "合并后的指标配置内容: $metrics_content"
    
    # 验证最终配置的JSON格式
    if ! echo "$metrics_content" | jq empty 2>/dev/null; then
        record_error "VALIDATION_ERROR" "合并后的指标配置不是有效的JSON格式" "ERROR"
        return 1
    fi
    
    # 构建目标文件路径
    local target_file="${APP_INIT_METRICS_DIR}/${service_name}_metrics_auto.conf"
    
    log_info "开始处理合并后的指标配置，目标文件: $target_file"
    
    # 处理合并后的配置项
    process_config_item "$service_name" "metrics" "$metrics_content" "$target_file"
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
        

        log_info "health_content: $health_content"

        # 如果.inputs.host_healthcheck[0].interval" 值没有带单位，则添加单位
        if ! echo "$health_content" | jq -r ".inputs.host_healthcheck[0].interval" 2>/dev/null | grep -q "s"; then
            local current_interval=$(echo "$health_content" | jq -r ".inputs.host_healthcheck[0].interval" 2>/dev/null)
            health_content=$(echo "$health_content" | jq --arg interval "${current_interval}s" ".inputs.host_healthcheck[0].interval = \$interval")
        fi

        
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
                    log_info "设置 CONFIG_CHANGED=true (原因: 移除旧配置文件)"
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

    # 获取 service_name 列表
    local service_names=()
    local service_count=0
    for service in $services; do
        service_count=$((service_count + 1))
        local service_name
        service_name=$(echo "$service" | jq -r 'keys[0]' 2>/dev/null)
        service_names+=("$service_name")
        if [ -z "$service_name" ] || [ "$service_name" = "null" ]; then
            record_error "VALIDATION_ERROR" "跳过无效的服务配置" "WARNING"
            continue
        fi
        
        log_info "处理服务 $service_count: $service_name"
        
        # 处理各种配置类型
        log_info "开始处理服务 $service_name 的日志配置"
        process_logging "$service_name" "$service"
        log_info "完成处理服务 $service_name 的日志配置"
        
        log_info "开始处理服务 $service_name 的指标配置"
        process_metrics "$service_name" "$service"
        log_info "完成处理服务 $service_name 的指标配置"
        
        log_info "开始处理服务 $service_name 的健康检查配置"
        process_health "$service_name" "$service"
        log_info "完成处理服务 $service_name 的健康检查配置"
    done
    # 输出service_name 
    log_info "service_names: ${service_names[@]}"
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
        if [[ "${SKIP_OPS_TOKEN_CHECK:-false}" == "true" || "${SKIP_OPS_TOKEN_CHECK:-false}" == "1" ]]; then
            log_warning "无法获取OPS_TOKEN，已启用跳过开关，跳过业务配置同步，继续使用默认配置"
            return 0
        fi
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
    log_info "response: $(jq -c . "$tmp_json_file")"
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
