#!/bin/bash

# Datakit业务配置同步脚本 - 生产版本
# 功能：从运维平台获取业务可观测配置，同步到Datakit采集器
# 版本：2.0.0
# 作者：Datakit运维团队

set -euo pipefail

# =============================================================================
# 配置常量
# =============================================================================
readonly SCRIPT_NAME="datakit_app_init"
readonly SCRIPT_VERSION="2.0.0"
readonly LOG_FILE="/opt/datakit/app_init.log"
readonly CONFIG_PY_FILE="/usr/lib/zabbix/externalscripts/config.py"
readonly OPS_API_URL="http://localhost:5000/api/v2/cmdb/observation-metadata"
readonly DATAWAY_URL="https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82"

# 存储目录
readonly LOGGING_DIR="/usr/local/datakit/conf.d/logging"
readonly METRICS_DIR="/usr/local/datakit/conf.d/prom"
readonly HEALTH_DIR="/usr/local/datakit/conf.d/host"

# 临时存储目录
readonly LOGGING_TMP_DIR="/opt/datakit/log"
readonly METRICS_TMP_DIR="/opt/datakit/prom"
readonly HEALTH_TMP_DIR="/opt/datakit/host"

# 前一次存储目录
readonly LOGGING_PREV_DIR="/opt/datakit/log_prev"
readonly METRICS_PREV_DIR="/opt/datakit/prom_prev"
readonly HEALTH_PREV_DIR="/opt/datakit/host_prev"

# 模板文件路径
readonly LOGGING_TEMPLATE="logging_template.conf"
readonly METRICS_TEMPLATE="metrics_template.conf"
readonly HEALTH_TEMPLATE="health_template.conf"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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
# 日志函数
# =============================================================================
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case "$level" in
        "INFO") color="$BLUE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
    esac
    
    echo -e "${color}[$timestamp] [$level] $message${NC}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# 工具函数
# =============================================================================
die() {
    log_error "$1"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || die "命令 '$1' 不存在"
}

get_host_ip() {
    log_info "获取本机IP地址"
    
    HOST_IP=$(ip -4 addr show 2>/dev/null | grep -v '127.0.0.1' | awk '/inet/ {print $2}' | cut -d'/' -f1 | head -n1)
    
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    fi
    
    [ -n "$HOST_IP" ] || die "无法获取本机IP地址"
    log_success "本机IP: $HOST_IP"
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录"
    
    local dirs=("$LOGGING_TMP_DIR" "$METRICS_TMP_DIR" "$HEALTH_TMP_DIR" 
                "$LOGGING_PREV_DIR" "$METRICS_PREV_DIR" "$HEALTH_PREV_DIR")
    
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
    local random_number=$((RANDOM % 60 + 1))
    log_info "随机休眠 $random_number 秒"
    sleep $random_number
    
    # 调用运维平台API
    local http_code
    
    http_code=$(curl -s -o /opt/datakit/tmp.json -w "%{http_code}" -X POST "$OPS_API_URL" \
        -H "Authorization: Token $OPS_TOKEN" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$HOST_IP\"}" \
        --connect-timeout 10 \
        --max-time 30)
    
    # 检查HTTP状态码
    if [ "$http_code" -eq 28 ]; then
        die "请求超时，当前连接超时设置为10s，最大请求时间为30s"
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
    if ! jq empty /opt/datakit/tmp.json 2>/dev/null; then
        die "响应结果不是有效的JSON格式"
    fi
    
    log_success "配置获取成功"
}

# =============================================================================
# Datakit服务控制
# =============================================================================
check_datakit_status() {
    pgrep -x "datakit" >/dev/null || netstat -tlnp 2>/dev/null | grep -q ":9529 " || {
        command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet datakit 2>/dev/null
    }
}

restart_datakit() {
    log_info "重启Datakit"
    
    if command -v systemctl >/dev/null 2>&1 && systemctl restart datakit 2>/dev/null; then
        log_success "Datakit重启成功"
        return 0
    fi
    
    if command -v datakit >/dev/null 2>&1 && datakit service -R >/dev/null 2>&1; then
        log_success "Datakit重启成功"
        return 0
    fi
    
    die "Datakit重启失败"
}

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
    
    # 备份原文件
    cp "$toml_file" "${toml_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
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
# 主处理函数
# =============================================================================
process_services() {
    log_info "开始处理服务配置"
    
    # 读取JSON数据并解析
    local services
    services=$(jq -c '.data[]' /opt/datakit/tmp.json 2>/dev/null) || die "JSON数据解析失败"
    
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
    check_command jq
    check_command yj
    check_command curl
    
    # 创建必要的目录
    create_directories
    
    # 获取配置
    get_host_ip
    get_ops_config
    
    # 验证JSON文件
    if [ ! -f "/opt/datakit/tmp.json" ] || ! jq empty "/opt/datakit/tmp.json" 2>/dev/null; then
        die "tmp.json文件不存在或不是有效的JSON格式"
    fi
    
    # 处理服务配置
    process_services
    
    # 合并配置文件
    merge_config_files
    
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
