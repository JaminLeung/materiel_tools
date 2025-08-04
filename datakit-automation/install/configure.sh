#!/bin/bash

#=================================================
# 配置模块
#=================================================
# 功能: Datakit配置、采集器配置、资源限制设置、全局标签配置
#=================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$SCRIPT_DIR")/core"

# Source外部脚本
source "$CORE_DIR/logging.sh" 2>/dev/null || echo "警告: 无法加载logging.sh" >&2
source "$CORE_DIR/utils.sh" 2>/dev/null || echo "警告: 无法加载utils.sh" >&2
source "$CORE_DIR/initialize.sh" 2>/dev/null || echo "警告: 无法加载initialize.sh" >&2
source "$CORE_DIR/validation.sh" 2>/dev/null || echo "警告: 无法加载validation.sh" >&2

# 配置Datakit
configure_datakit() {
    log_info "=== 步骤4: 配置Datakit ==="
    
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在: $datakit_conf"
        return 1
    fi
    
    # 设置日志分片
    if ! safe_execute "yq eval '.logging.rotate = \"32\"' \"$datakit_conf\" -i" "设置日志分片"; then
        return 1
    fi
    
    # 设置Cgroup配置
    local cpu_limit=$(get_global_state 'CGROUP_CPU_LIMIT')
    local memory_limit=$(get_global_state 'CGROUP_MEMORY_LIMIT')
    
    if [ -n "$cpu_limit" ]; then
        if ! safe_execute "yq eval \".resource_limit.cpu_cores = \\\"$cpu_limit\\\"\" \"$datakit_conf\" -i" "设置CPU限制"; then
            return 1
        fi
    fi
    
    if [ -n "$memory_limit" ]; then
        if ! safe_execute "yq eval \".resource_limit.mem_max_mb = \\\"$memory_limit\\\"\" \"$datakit_conf\" -i" "设置内存限制"; then
            return 1
        fi
    fi
    
    # 设置全局标签
    local env=$(get_global_state 'ENV')
    local workspace=$(get_global_state 'WORKSPACE')
    local global_tags=$(get_global_state 'GLOBAL_TAGS')
    
    if [ -n "$env" ]; then
        if ! safe_execute "yq eval \".global_host_tags.env = \\\"$env\\\"\" \"$datakit_conf\" -i" "设置环境标签"; then
            return 1
        fi
    fi
    
    if [ -n "$workspace" ]; then
        if ! safe_execute "yq eval \".global_host_tags.workspace = \\\"$workspace\\\"\" \"$datakit_conf\" -i" "设置工作空间标签"; then
            return 1
        fi
    fi
    
    if [ -n "$global_tags" ]; then
        if ! safe_execute "yq eval \".global_host_tags.global_source = \\\"$global_tags\\\"\" \"$datakit_conf\" -i" "设置全局标签"; then
            return 1
        fi
    fi
    
    # 修改Dataway地址
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    if [ -n "$dataway_url" ]; then
        if ! safe_execute "yq eval \".dataway.dataway_url = [\\\"$dataway_url\\\"]\" \"$datakit_conf\" -i" "设置Dataway地址"; then
            return 1
        fi
    fi
    
    log_success "Datakit配置完成"
    dataway_log "info" "Datakit配置完成"
    return 0
}

# 配置采集器
configure_inputs() {
    log_info "=== 步骤5: 配置采集器 ==="
    
    local conf_dir="/usr/local/datakit/conf.d"
    
    # 确保配置目录存在
    if ! dir_exists "$conf_dir"; then
        log_error "Datakit配置目录不存在: $conf_dir"
        return 1
    fi
    
    # Prometheus配置
    cat > "$conf_dir/prom_node_exporter.conf" << 'EOF'
# {"version": "1.63.1", "desc": "do NOT edit this line"}

[[inputs.prom]]
  ## Exporter URLs.
  urls = ["http://127.0.0.1:9100/metrics"]

  uds_path = ""

  ## Ignore URL request errors.
  ignore_req_err = false

  ## Collector alias.
  source = "prom"

  measurement_name = "node_exporter"

  keep_exist_metric_name = true

  election = true

  ## disable setting host tag for this input
  disable_host_tag = false

  ## disable setting instance tag for this input
  disable_instance_tag = false

  ## disable info tag for this input
  disable_info_tag = false

  [[inputs.prom.measurements]]
    prefix = "etcd_network_"
    name = "etcd_network"
    
  [[inputs.prom.measurements]]
    prefix = "etcd_server_"
    name = "etcd_server"

  ## Rename tag key in prom data.
  [inputs.prom.tags_rename]
    overwrite_exist_tags = false

  [inputs.prom.as_logging]
    enable = false
    service = "service_name"

  ## Customize tags.
  # [inputs.prom.tags]
    # some_tag = "some_value"
    # more_tag = "some_other_value"
  
  ## (Optional) Collect interval: (defaults to "30s").
  # interval = "30s"

  ## (Optional) Timeout: (defaults to "30s").
  # timeout = "30s"
EOF

    # OpenTelemetry配置
    cat > "$conf_dir/opentelemetry.conf" << 'EOF'
# {"version": "1.64.1", "desc": "do NOT edit this line"}
[[inputs.opentelemetry]]
  [inputs.opentelemetry.http]
   enable = true
   http_status_ok = 200
   trace_api = "/otel/v1/trace"
   metric_api = "/otel/v1/metric"
   logs_api = "/otel/v1/logs"

  [inputs.opentelemetry.grpc]
   trace_enable = true
   metric_enable = true
   addr = "0.0.0.0:4317"
EOF

    # 日志配置
    cat > "$conf_dir/logging.conf" << 'EOF'
[[inputs.logging]]
  logfiles = [
    "/var/log/syslog",
    "/var/log/messages",
    "/var/log/dmesg",
    "/var/log/aws-routed-eni/*",
    "/var/log/secure",
    "/var/log/audit/*",
    "/var/log/lastlog",
    "/opt/datakit/*.log",
    "/var/log/datakit/log"
  ]

  ignore = [""]

  source = ""

  service = ""

  pipeline = ""

  ignore_status = []

  character_encoding = ""

  auto_multiline_detection = true
  auto_multiline_extra_patterns = []

  remove_ansi_escape_codes = false

  ignore_dead_log = "12h"

  from_beginning = false

  [inputs.logging.tags]
EOF

    # Pushgateway配置
    cat > "$conf_dir/pushgateway.conf" << 'EOF'
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF

    log_success "采集器配置完成"
    dataway_log "info" "采集器配置完成"
}

# 设置资源限制
set_resource_limits() {
    log_info "设置资源限制..."
    
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在: $datakit_conf"
        return 1
    fi
    
    # 设置CPU限制
    local cpu_limit=$(get_global_state 'CGROUP_CPU_LIMIT')
    if [ -n "$cpu_limit" ]; then
        if ! safe_execute "yq eval \".resource_limit.cpu_cores = \\\"$cpu_limit\\\"\" \"$datakit_conf\" -i" "设置CPU限制"; then
            log_warning "设置CPU限制失败"
        fi
    fi
    
    # 设置内存限制
    local memory_limit=$(get_global_state 'CGROUP_MEMORY_LIMIT')
    if [ -n "$memory_limit" ]; then
        if ! safe_execute "yq eval \".resource_limit.mem_max_mb = \\\"$memory_limit\\\"\" \"$datakit_conf\" -i" "设置内存限制"; then
            log_warning "设置内存限制失败"
        fi
    fi
    
    log_success "资源限制设置完成"
}

# 设置全局标签
set_global_tags() {
    log_info "设置全局标签..."
    
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在: $datakit_conf"
        return 1
    fi
    
    # 设置环境标签
    local env=$(get_global_state 'ENV')
    if [ -n "$env" ]; then
        if ! safe_execute "yq eval \".global_host_tags.env = \\\"$env\\\"\" \"$datakit_conf\" -i" "设置环境标签"; then
            log_warning "设置环境标签失败"
        fi
    fi
    
    # 设置工作空间标签
    local workspace=$(get_global_state 'WORKSPACE')
    if [ -n "$workspace" ]; then
        if ! safe_execute "yq eval \".global_host_tags.workspace = \\\"$workspace\\\"\" \"$datakit_conf\" -i" "设置工作空间标签"; then
            log_warning "设置工作空间标签失败"
        fi
    fi
    
    # 设置全局标签
    local global_tags=$(get_global_state 'GLOBAL_TAGS')
    if [ -n "$global_tags" ]; then
        if ! safe_execute "yq eval \".global_host_tags.global_source = \\\"$global_tags\\\"\" \"$datakit_conf\" -i" "设置全局标签"; then
            log_warning "设置全局标签失败"
        fi
    fi
    
    log_success "全局标签设置完成"
}

# 通过yj读取TOML文件并转换为JSON格式
read_toml_as_json() {
    local toml_file="$1"
    local json_path="$2"
    
    log_info "读取TOML文件: $toml_file"
    
    # 检查文件是否存在
    if [ ! -f "$toml_file" ]; then
        log_error "TOML文件不存在: $toml_file"
        return 1
    fi
    
    # 检查yj工具是否可用
    if ! command -v yj >/dev/null 2>&1; then
        log_error "yj工具不可用，请先安装yj"
        return 1
    fi
    
    # 使用yj将TOML转换为JSON
    local json_output
    if json_output=$(yj -t < "$toml_file" 2>/dev/null); then
        # 如果指定了JSON路径，则提取该路径的值
        if [ -n "$json_path" ]; then
            if command -v jq >/dev/null 2>&1; then
                local extracted_value
                if extracted_value=$(echo "$json_output" | jq -r "$json_path" 2>/dev/null); then
                    if [ "$extracted_value" != "null" ]; then
                        echo "$extracted_value"
                        log_info "成功提取JSON路径 $json_path 的值"
                        return 0
                    else
                        log_warning "JSON路径 $json_path 的值为null"
                        return 1
                    fi
                else
                    log_error "jq解析JSON路径失败: $json_path"
                    return 1
                fi
            else
                log_error "jq工具不可用，无法提取JSON路径"
                return 1
            fi
        else
            # 没有指定路径，返回完整JSON
            echo "$json_output"
            log_info "成功转换TOML为JSON格式"
            return 0
        fi
    else
        log_error "yj转换TOML文件失败: $toml_file"
        return 1
    fi
} 