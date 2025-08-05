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

# 加载核心模块
source "$CORE_DIR/logging.sh" 2>/dev/null || echo "警告: 无法加载logging.sh" >&2
source "$CORE_DIR/utils.sh" 2>/dev/null || echo "警告: 无法加载utils.sh" >&2
source "$CORE_DIR/datakit_service.sh" 2>/dev/null || echo "警告: 无法加载datakit_service.sh" >&2
source "$CORE_DIR/config_file.sh" 2>/dev/null || echo "警告: 无法加载config_file.sh" >&2

# =============================================================================
# 配置管理
# =============================================================================
# 设置配置文件路径
readonly CONFIG_FILE="$SCRIPT_DIR/../config/app_init.conf"

# 加载配置文件
load_config_file "$CONFIG_FILE" || die "无法加载配置文件: $CONFIG_FILE"

# 验证必需配置项
validate_required_config "script_name" "script_version" "ops_config_py_file" "ops_api_url" || die "配置文件缺少必需项"

# 从配置文件获取配置值
SCRIPT_NAME=$(get_config_value "script_name")
SCRIPT_VERSION=$(get_config_value "script_version")
LOG_FILE=$(get_config_value "script_log_file")
CONFIG_PY_FILE=$(get_config_value "ops_config_py_file")
OPS_API_URL=$(get_config_value "ops_api_url")
DATAWAY_URL=$(get_config_value "ops_dataway_url")

# Datakit配置目录
LOGGING_DIR=$(get_config_value "datakit_logging_dir")
METRICS_DIR=$(get_config_value "datakit_metrics_dir")
HEALTH_DIR=$(get_config_value "datakit_health_dir")

# 备份配置
BACKUP_BASE_DIR=$(get_config_value "backup_base_dir")
BACKUP_KEEP_DAYS=$(get_config_value "backup_keep_days" "7")
BACKUP_DATE_DIR="${BACKUP_BASE_DIR}/$(date +%Y%m%d)"
BACKUP_APP_INIT_DIR="${BACKUP_DATE_DIR}/app_init"

# 临时存储目录
LOGGING_TMP_DIR="${BACKUP_APP_INIT_DIR}/log"
METRICS_TMP_DIR="${BACKUP_APP_INIT_DIR}/prom"
HEALTH_TMP_DIR="${BACKUP_APP_INIT_DIR}/host"

# 前一次存储目录
LOGGING_PREV_DIR="${BACKUP_APP_INIT_DIR}/log_prev"
METRICS_PREV_DIR="${BACKUP_APP_INIT_DIR}/prom_prev"
HEALTH_PREV_DIR="${BACKUP_APP_INIT_DIR}/host_prev"

# 模板文件路径
LOGGING_TEMPLATE=$(get_config_value "templates_logging_template")
METRICS_TEMPLATE=$(get_config_value "templates_metrics_template")
HEALTH_TEMPLATE=$(get_config_value "templates_health_template")

# API配置
API_CONNECT_TIMEOUT=$(get_config_value "api_connect_timeout" "10")
API_MAX_TIME=$(get_config_value "api_max_time" "30")
API_RANDOM_DELAY_MAX=$(get_config_value "api_random_delay_max" "60")

# =============================================================================
# 全局变量
# =============================================================================
HOST_IP=""
OPS_TOKEN=""
OPS_ADDR=""
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
die() {
    log_error "$1"
    exit 1
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录"
    
    # 创建备份基础目录
    local dirs=("$BACKUP_BASE_DIR" "$BACKUP_DATE_DIR" "$BACKUP_APP_INIT_DIR"
                "$LOGGING_TMP_DIR" "$METRICS_TMP_DIR" "$HEALTH_TMP_DIR" 
                "$LOGGING_PREV_DIR" "$METRICS_PREV_DIR" "$HEALTH_PREV_DIR"
                "$LOGGING_DIR" "$METRICS_DIR" "$HEALTH_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
        fi
    done
    
    log_success "目录创建完成"
}

# =============================================================================
# 运维平台API
# =============================================================================
get_ops_config() {
    log_info "获取运维平台配置"
    
    # 从配置文件获取OPS配置
    OPS_TOKEN=$(grep -v '^\s*#' "$CONFIG_PY_FILE" | grep -oP "ops_token = '\K[^']+" 2>/dev/null || echo "")
    OPS_ADDR=$(grep -v '^\s*#' "$CONFIG_PY_FILE" | grep -oP "ops_addr = '\K[^']+" 2>/dev/null || echo "")
    
    if [ -z "$OPS_TOKEN" ] || [ -z "$OPS_ADDR" ]; then
        die "无法从配置文件获取OPS配置"
    fi
    
    log_info "OPS_TOKEN: $OPS_TOKEN"
    log_info "OPS_ADDR: $OPS_ADDR"
    
    # 随机休眠避免并发请求
    local random_number=$((RANDOM % API_RANDOM_DELAY_MAX + 1))
    log_info "随机休眠 $random_number 秒"
    sleep $random_number
    
    # 调用运维平台API
    local http_code
    local tmp_json_file="${BACKUP_APP_INIT_DIR}/tmp.json"
    
    http_code=$(curl -s -o "$tmp_json_file" -w "%{http_code}" -X POST "$OPS_API_URL" \
        -H "Authorization: Token $OPS_TOKEN" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$HOST_IP\"}" \
        --connect-timeout "$API_CONNECT_TIMEOUT" \
        --max-time "$API_MAX_TIME")
    
    # 检查HTTP状态码
    if [ "$http_code" -eq 28 ]; then
        die "请求超时，当前连接超时设置为${API_CONNECT_TIMEOUT}s，最大请求时间为${API_MAX_TIME}s"
    elif [ "$http_code" -ne 200 ]; then
        case "$http_code" in
            400) die "错误请求，可能是请求参数有误" ;;
            401) die "未授权，检查Token是否有效" ;;
            403) die "禁止访问，您没有权限访问该资源" ;;
            404) die "未找到，检查URL是否正确" ;;
            500) die "服务器内部错误，请稍后重试" ;;
            502) die "错误网关，可能是上游服务器问题" ;;
            503) die "服务不可用，服务器当前无法处理请求" ;;
            504) die "网关超时，服务器未能及时响应" ;;
            *) die "其他错误，HTTP状态码: $http_code" ;;
        esac
    fi
    
    # 验证JSON格式
    if ! jq empty "$tmp_json_file" 2>/dev/null; then
        die "响应结果不是有效的JSON格式"
    fi
    
    log_success "配置获取成功"
}

# =============================================================================
# Datakit健康检查
# =============================================================================
verify_datakit_health() {
    log_info "验证Datakit健康状态"
    sleep 3
    
    check_datakit_status || die "Datakit进程未运行"
    
    local response
    response=$(curl -s -m 10 "http://localhost:9529/v1/ping" 2>/dev/null) || die "Datakit健康检查失败"
    
    [ -n "$response" ] && log_success "Datakit健康检查通过" || die "Datakit健康检查失败"
}

# =============================================================================
# 配置文件处理
# =============================================================================
read_toml_config() {
    local toml_file="$1"
    [ -f "$toml_file" ] || die "配置文件不存在: $toml_file"
    
    check_command yj
    yj -t < "$toml_file" 2>/dev/null || die "TOML文件读取失败: $toml_file"
}

update_toml_config() {
    local toml_file="$1"
    local json_data="$2"
    
    # 备份原文件到备份目录
    local filename=$(basename "$toml_file")
    local backup_file="${BACKUP_APP_INIT_DIR}/${filename}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$toml_file" "$backup_file"
    log_info "备份配置文件: $filename -> $(basename "$backup_file")"
    
    # 更新配置文件
    echo "$json_data" | yj -jt > "$toml_file" 2>/dev/null || {
        log_error "配置文件更新失败: $toml_file"
        return 1
    }
    
    log_success "配置文件更新成功: $toml_file"
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
            log_error "日志配置内容不是有效的JSON格式"
            continue
        fi
        
        # 转换为TOML格式
        local logging_content_toml
        logging_content_toml=$(echo "$logging_content" | yj -jt 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            log_error "日志配置TOML转换失败"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf"
        echo "$logging_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf" "logging"
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
            log_error "指标配置TOML转换失败"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${METRICS_TMP_DIR}/${service_name}_metrics.conf"
        echo "$metrics_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${METRICS_PREV_DIR}/${service_name}_metrics.conf" "metrics"
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
            log_error "健康检查配置TOML转换失败"
            continue
        fi
        
        # 生成临时配置文件
        local tmp_file="${HEALTH_TMP_DIR}/${service_name}_health.conf"
        echo "$health_content_toml" > "$tmp_file"
        
        # 检查差异并处理
        handle_config_diff "$tmp_file" "${HEALTH_PREV_DIR}/${service_name}_health.conf" "health"
    done
}

# =============================================================================
# 配置差异处理
# =============================================================================
handle_config_diff() {
    local tmp_file="$1"
    local prev_file="$2"
    local config_type="$3"
    
    # 如果前一次存储目录存在同名文件，检查差异
    if [ -f "$prev_file" ]; then
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
        log_info "首次处理配置: $tmp_file"
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
    
    log_success "配置文件合并完成"
}

merge_logging_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${LOGGING_DIR}/${file}"
    
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
                    log_success "日志配置合并成功"
                else
                    log_error "日志配置合并失败"
                fi
            else
                log_error "JSON解析失败"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_success "日志配置复制成功"
    fi
}

merge_metrics_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${METRICS_DIR}/${file}"
    
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
                    log_success "指标配置合并成功"
                else
                    log_error "指标配置合并失败"
                fi
            else
                log_error "JSON解析失败"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_success "指标配置复制成功"
    fi
}

merge_health_config() {
    local source="$1"
    local file=$(basename "$source")
    local datakit_file="${HEALTH_DIR}/${file}"
    
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
                    log_success "健康检查配置合并成功"
                else
                    log_error "健康检查配置合并失败"
                fi
            else
                log_error "JSON解析失败"
            fi
        fi
    else
        # 直接复制
        cp "$source" "$datakit_file"
        log_success "健康检查配置复制成功"
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
    local tmp_json_file="${BACKUP_APP_INIT_DIR}/tmp.json"
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
    cleanup_config_directory "$LOGGING_DIR" "logging" "${current_services[@]}"
    
    # 清理指标配置
    cleanup_config_directory "$METRICS_DIR" "metrics" "${current_services[@]}"
    
    # 清理健康检查配置
    cleanup_config_directory "$HEALTH_DIR" "health" "${current_services[@]}"
    
    log_success "配置文件清理和备份完成"
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
                # 格式: xxx.conf (任何以服务名开头的.conf文件)
                if [[ "$filename" =~ ^[^_]+_.*\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_.*\.conf$/\1/p')
                    should_backup=true
                else
                    log_info "跳过不符合日志格式的文件: $filename (应为 xxx_*.conf)"
                    continue
                fi
                ;;
            "metrics")
                # 格式: xxx_metrics.conf
                if [[ "$filename" =~ ^[^_]+_metrics\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_metrics\.conf$/\1/p')
                    should_backup=true
                else
                    log_info "跳过不符合指标格式的文件: $filename (应为 xxx_metrics.conf)"
                    continue
                fi
                ;;
            "health")
                # 格式: xxx_health.conf
                if [[ "$filename" =~ ^[^_]+_health\.conf$ ]]; then
                    service_name=$(echo "$filename" | sed -n 's/^\([^_]*\)_health\.conf$/\1/p')
                    should_backup=true
                else
                    log_info "跳过不符合健康检查格式的文件: $filename (应为 xxx_health.conf)"
                    continue
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
                local backup_file="${BACKUP_APP_INIT_DIR}/${filename}.backup_$(date +%Y%m%d_%H%M%S)"
                if mv "$config_file" "$backup_file"; then
                    log_info "备份旧配置文件: $filename -> $(basename "$backup_file")"
                else
                    log_error "备份配置文件失败: $filename"
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
    local tmp_json_file="${BACKUP_APP_INIT_DIR}/tmp.json"
    # 检查是否有data字段，如果没有则直接使用根对象
    if jq -e '.data' "$tmp_json_file" >/dev/null 2>&1; then
        services=$(jq -c '.data[]' "$tmp_json_file" 2>/dev/null) || die "JSON数据解析失败"
    else
        # 如果没有data字段，将整个JSON对象作为一个服务处理
        services=$(cat "$tmp_json_file" 2>/dev/null) || die "JSON数据解析失败"
    fi
    
    local service_count=0
    for service in $services; do
        service_count=$((service_count + 1))
        local service_name
        service_name=$(echo "$service" | jq -r 'keys[0]' 2>/dev/null)
        
        if [ -z "$service_name" ] || [ "$service_name" = "null" ]; then
            log_warning "跳过无效的服务配置"
            continue
        fi
        
        log_info "处理服务 $service_count: $service_name"
        
        # 处理各种配置类型
        process_logging "$service_name" "$service"
        process_metrics "$service_name" "$service"
        process_health "$service_name" "$service"
    done
    
    log_success "服务配置处理完成，共处理 $service_count 个服务"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    log_info "开始执行 $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # 检查依赖
    command_exists jq || die "命令 'jq' 不存在"
    command_exists yj || die "命令 'yj' 不存在"
    command_exists curl || die "命令 'curl' 不存在"
    
    # 创建必要的目录
    create_directories
    
    # 获取配置
    get_host_ip
    HOST_IP=$(get_global_state 'HOST_IP')
    get_ops_config
    
    # 验证JSON文件
    local tmp_json_file="${BACKUP_APP_INIT_DIR}/tmp.json"
    if [ ! -f "$tmp_json_file" ] || ! jq empty "$tmp_json_file" 2>/dev/null; then
        die "tmp.json文件不存在或不是有效的JSON格式"
    fi
    
    # 处理服务配置
    process_services
    
    # 合并配置文件
    merge_config_files
    
    # 清理和备份旧配置
    cleanup_old_configs
    
    # 清理旧备份目录
    cleanup_old_backup_dirs "$BACKUP_BASE_DIR" "$BACKUP_KEEP_DAYS"
    
    # 输出统计信息
    log_info "配置差异统计:"
    log_info "  总差异数: $diff_count"
    log_info "  日志差异数: $diff_count_logging"
    log_info "  指标差异数: $diff_count_metrics"
    log_info "  健康检查差异数: $diff_count_health"
    
    # 如果有配置变更，重启Datakit
    if [ "$CONFIG_CHANGED" = true ]; then
        log_info "检测到配置变更，重启Datakit"
        restart_datakit
        verify_datakit_health
        log_success "Datakit重启完成"
    else
        log_info "无配置变更，无需重启Datakit"
    fi
    
    log_success "业务配置同步完成"
}



# =============================================================================
# 脚本入口
# =============================================================================
main "$@"
