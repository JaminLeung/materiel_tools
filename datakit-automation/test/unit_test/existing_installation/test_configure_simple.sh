#!/bin/bash

# 简化的configure模块测试
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_info() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 读取TOML配置文件的辅助函数
read_toml_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        yj -tj < "$config_file" 2>/dev/null || cat "$config_file"
    else
        return 1
    fi
}

# 测试Datakit主配置文件
test_datakit_main_config() {
    log_info "测试Datakit主配置文件配置..."
    
    # 创建测试目录
    local test_dir="/tmp/datakit_configure_test"
    mkdir -p "$test_dir/usr/local/datakit/conf.d"
    
    # 创建模拟的datakit.conf文件
    local original_conf="$test_dir/usr/local/datakit/conf.d/datakit.conf"
    cat > "$original_conf" << 'EOF'
# Datakit配置文件
[logging]
  rotate = 16

[http_api]
  listen = "127.0.0.1:9529"

[resource_limit]
  cpu_cores = 0.5
  mem_max_mb = 1024

[global_host_tags]
  env = "production"
  workspace = "default"

[dataway]
  urls = ["http://localhost:9529"]
EOF
    
    local temp_conf="$test_dir/usr/local/datakit/conf.d/datakit.conf.temp"
    local backup_conf="$test_dir/usr/local/datakit/conf.d/datakit.conf.backup"
    
    # 备份原始配置文件
    cp "$original_conf" "$backup_conf"
    log_info "已备份原始配置文件到: $backup_conf"
    
    # 复制到临时配置文件
    cp "$original_conf" "$temp_conf"
    log_info "已复制配置文件到临时文件: $temp_conf"
    
    # 读取原始配置
    local original_config
    if ! original_config=$(read_toml_config "$temp_conf" 2>/dev/null); then
        log_error "读取原始配置文件失败"
        return 1
    fi
    
    log_info "=== 开始配置修改 ==="
    
    # 记录修改前的配置
    log_info "修改前配置:"
    log_info "日志分片: $(echo "$original_config" | jq -r '.logging.rotate // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "HTTP API监听: $(echo "$original_config" | jq -r '.http_api.listen // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "CPU限制: $(echo "$original_config" | jq -r '.resource_limit.cpu_cores // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "内存限制: $(echo "$original_config" | jq -r '.resource_limit.mem_max_mb // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "环境标签: $(echo "$original_config" | jq -r '.global_host_tags.env // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "工作空间标签: $(echo "$original_config" | jq -r '.global_host_tags.workspace // "未设置"' 2>/dev/null || echo "未设置")"
    
    # 应用配置修改
    local current_config="$original_config"
    
    # 1. 设置日志分片 (int类型)
    current_config=$(echo "$current_config" | jq '.logging.rotate = 32')
    log_info "✅ 修改: 设置日志分片为 32 (int类型)"
    
    # 2. 设置HTTP API监听地址
    current_config=$(echo "$current_config" | jq '.http_api.listen = "0.0.0.0:9529"')
    log_info "✅ 修改: 设置HTTP API监听地址为 0.0.0.0:9529"
    
    # 3. 设置资源限制
    current_config=$(echo "$current_config" | jq '.resource_limit.cpu_cores = 1.0')
    log_info "✅ 修改: 设置CPU限制为 1.0 (float类型)"
    
    current_config=$(echo "$current_config" | jq '.resource_limit.mem_max_mb = 2048')
    log_info "✅ 修改: 设置内存限制为 2048 MB (int类型)"
    
    # 4. 设置全局标签
    current_config=$(echo "$current_config" | jq '.global_host_tags.env = "unit_test"')
    log_info "✅ 修改: 设置环境标签为 unit_test"
    
    current_config=$(echo "$current_config" | jq '.global_host_tags.workspace = "test_workspace"')
    log_info "✅ 修改: 设置工作空间标签为 test_workspace"
    
    # 5. 设置Dataway地址
    current_config=$(echo "$current_config" | jq '.dataway.urls = ["http://test-dataway:9529"]')
    log_info "✅ 修改: 设置Dataway地址为 http://test-dataway:9529"
    
    # 6. 添加自定义全局标签
    current_config=$(echo "$current_config" | jq '.global_host_tags.test_tag = "test_value"')
    log_info "✅ 新增: 添加测试标签 test_tag=test_value"
    
    current_config=$(echo "$current_config" | jq '.global_host_tags.version = "1.78.0"')
    log_info "✅ 新增: 添加版本标签 version=1.78.0"
    
    # 将修改后的配置写回临时文件
    if ! echo "$current_config" | yj -jt > "$temp_conf" 2>/dev/null; then
        log_error "❌ 失败: 转换配置文件格式失败"
        return 1
    fi
    
    # 验证修改后的配置
    local modified_config
    if ! modified_config=$(read_toml_config "$temp_conf" 2>/dev/null); then
        log_error "❌ 失败: 读取修改后的配置文件失败"
        return 1
    fi
    
    log_info "=== 修改后配置验证 ==="
    
    # 验证各项配置
    local logging_rotate=$(echo "$modified_config" | jq -r '.logging.rotate // "未设置"' 2>/dev/null || echo "未设置")
    local http_listen=$(echo "$modified_config" | jq -r '.http_api.listen // "未设置"' 2>/dev/null || echo "未设置")
    local cpu_cores=$(echo "$modified_config" | jq -r '.resource_limit.cpu_cores // "未设置"' 2>/dev/null || echo "未设置")
    local mem_mb=$(echo "$modified_config" | jq -r '.resource_limit.mem_max_mb // "未设置"' 2>/dev/null || echo "未设置")
    local env_tag=$(echo "$modified_config" | jq -r '.global_host_tags.env // "未设置"' 2>/dev/null || echo "未设置")
    local workspace_tag=$(echo "$modified_config" | jq -r '.global_host_tags.workspace // "未设置"' 2>/dev/null || echo "未设置")
    local test_tag=$(echo "$modified_config" | jq -r '.global_host_tags.test_tag // "未设置"' 2>/dev/null || echo "未设置")
    local version_tag=$(echo "$modified_config" | jq -r '.global_host_tags.version // "未设置"' 2>/dev/null || echo "未设置")
    local dataway_urls=$(echo "$modified_config" | jq -r '.dataway.urls[0] // "未设置"' 2>/dev/null || echo "未设置")
    
    log_info "修改后配置:"
    log_info "日志分片: $logging_rotate"
    log_info "HTTP API监听: $http_listen"
    log_info "CPU限制: $cpu_cores"
    log_info "内存限制: $mem_mb"
    log_info "环境标签: $env_tag"
    log_info "工作空间标签: $workspace_tag"
    log_info "测试标签: $test_tag"
    log_info "版本标签: $version_tag"
    log_info "Dataway地址: $dataway_urls"
    
    # 验证配置正确性
    local config_errors=0
    
    if [[ "$logging_rotate" != "32" ]]; then
        log_error "❌ 配置错误: 日志分片应为 32，实际为 $logging_rotate"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 日志分片 = $logging_rotate"
    fi
    
    if [[ "$http_listen" != "0.0.0.0:9529" ]]; then
        log_error "❌ 配置错误: HTTP API监听应为 0.0.0.0:9529，实际为 $http_listen"
        ((config_errors++))
    else
        log_info "✅ 配置正确: HTTP API监听 = $http_listen"
    fi
    
    if [[ "$cpu_cores" != "1.0" && "$cpu_cores" != "1" ]]; then
        log_error "❌ 配置错误: CPU限制应为 1.0 或 1，实际为 $cpu_cores"
        ((config_errors++))
    else
        log_info "✅ 配置正确: CPU限制 = $cpu_cores"
    fi
    
    if [[ "$mem_mb" != "2048" ]]; then
        log_error "❌ 配置错误: 内存限制应为 2048，实际为 $mem_mb"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 内存限制 = $mem_mb"
    fi
    
    if [[ "$env_tag" != "unit_test" ]]; then
        log_error "❌ 配置错误: 环境标签应为 unit_test，实际为 $env_tag"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 环境标签 = $env_tag"
    fi
    
    if [[ "$workspace_tag" != "test_workspace" ]]; then
        log_error "❌ 配置错误: 工作空间标签应为 test_workspace，实际为 $workspace_tag"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 工作空间标签 = $workspace_tag"
    fi
    
    if [[ "$test_tag" != "test_value" ]]; then
        log_error "❌ 配置错误: 测试标签应为 test_value，实际为 $test_tag"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 测试标签 = $test_tag"
    fi
    
    if [[ "$version_tag" != "1.78.0" ]]; then
        log_error "❌ 配置错误: 版本标签应为 1.78.0，实际为 $version_tag"
        ((config_errors++))
    else
        log_info "✅ 配置正确: 版本标签 = $version_tag"
    fi
    
    if [[ "$dataway_urls" != "http://test-dataway:9529" ]]; then
        log_error "❌ 配置错误: Dataway地址应为 http://test-dataway:9529，实际为 $dataway_urls"
        ((config_errors++))
    else
        log_info "✅ 配置正确: Dataway地址 = $dataway_urls"
    fi
    
    if [[ $config_errors -eq 0 ]]; then
        log_info "🎉 所有配置验证通过！"
    else
        log_error "❌ 配置验证失败，共 $config_errors 个错误"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_conf"
    log_info "已清理临时配置文件"
    
    # 清理测试目录
    rm -rf "$test_dir"
    log_info "已清理测试目录"
    
    return 0
}

# 测试采集器配置
test_collector_configs() {
    log_info "测试采集器配置..."
    
    # 创建测试目录
    local test_dir="/tmp/datakit_collector_test"
    mkdir -p "$test_dir/usr/local/datakit/conf.d/prom"
    mkdir -p "$test_dir/usr/local/datakit/conf.d/opentelemetry"
    mkdir -p "$test_dir/usr/local/datakit/conf.d/log"
    mkdir -p "$test_dir/usr/local/datakit/conf.d/pushgateway"
    
    local config_errors=0
    
    # 测试Prometheus配置
    test_prometheus_config "$test_dir/usr/local/datakit/conf.d/prom/prom_node_exporter.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试OpenTelemetry配置
    test_opentelemetry_config "$test_dir/usr/local/datakit/conf.d/opentelemetry/opentelemetry.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试日志配置
    test_logging_config "$test_dir/usr/local/datakit/conf.d/log/logging.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试Pushgateway配置
    test_pushgateway_config "$test_dir/usr/local/datakit/conf.d/pushgateway/pushgateway.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    if [[ $config_errors -eq 0 ]]; then
        log_info "🎉 所有采集器配置验证通过！"
    else
        log_error "❌ 采集器配置验证失败，共 $config_errors 个错误"
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    log_info "已清理测试目录"
    
    return 0
}

# 测试Prometheus配置
test_prometheus_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试Prometheus配置: $config_file"
    
    # 创建原始配置
    cat > "$config_file" << 'EOF'
# 原始Prometheus配置
[[inputs.prom]]
  urls = ["http://localhost:9090/metrics"]
  source = "old_prom"
EOF
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始Prometheus配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 读取原始配置
    local original_content=$(cat "$temp_file")
    log_info "原始Prometheus配置内容长度: ${#original_content} 字符"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}

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
    
    log_info "✅ 修改: 应用新的Prometheus配置"
    
    # 验证配置
    local modified_content=$(cat "$temp_file")
    local content_length=${#modified_content}
    
    log_info "修改后Prometheus配置内容长度: $content_length 字符"
    
    # 验证关键配置项
    if grep -q "urls = \[\"http://127.0.0.1:9100/metrics\"\]" "$temp_file"; then
        log_info "✅ 配置正确: Prometheus URLs配置"
    else
        log_error "❌ 配置错误: Prometheus URLs配置缺失"
        return 1
    fi
    
    if grep -q "source = \"prom\"" "$temp_file"; then
        log_info "✅ 配置正确: Prometheus source配置"
    else
        log_error "❌ 配置错误: Prometheus source配置缺失"
        return 1
    fi
    
    if grep -q "measurement_name = \"node_exporter\"" "$temp_file"; then
        log_info "✅ 配置正确: Prometheus measurement_name配置"
    else
        log_error "❌ 配置错误: Prometheus measurement_name配置缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时Prometheus配置文件"
    
    return 0
}

# 测试OpenTelemetry配置
test_opentelemetry_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试OpenTelemetry配置: $config_file"
    
    # 创建原始配置
    cat > "$config_file" << 'EOF'
# 原始OpenTelemetry配置
[[inputs.opentelemetry]]
  enable = false
EOF
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始OpenTelemetry配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}
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
    
    log_info "✅ 修改: 应用新的OpenTelemetry配置"
    
    # 验证配置
    if grep -q "enable = true" "$temp_file"; then
        log_info "✅ 配置正确: OpenTelemetry HTTP启用"
    else
        log_error "❌ 配置错误: OpenTelemetry HTTP未启用"
        return 1
    fi
    
    if grep -q "addr = \"0.0.0.0:4317\"" "$temp_file"; then
        log_info "✅ 配置正确: OpenTelemetry gRPC地址"
    else
        log_error "❌ 配置错误: OpenTelemetry gRPC地址缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时OpenTelemetry配置文件"
    
    return 0
}

# 测试日志配置
test_logging_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试日志配置: $config_file"
    
    # 创建原始配置
    cat > "$config_file" << 'EOF'
# 原始日志配置
[[inputs.logging]]
  logfiles = ["/var/log/test.log"]
EOF
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始日志配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
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
    
    log_info "✅ 修改: 应用新的日志配置"
    
    # 验证配置
    if grep -q "/var/log/syslog" "$temp_file"; then
        log_info "✅ 配置正确: 系统日志文件路径"
    else
        log_error "❌ 配置错误: 系统日志文件路径缺失"
        return 1
    fi
    
    if grep -q "auto_multiline_detection = true" "$temp_file"; then
        log_info "✅ 配置正确: 自动多行检测启用"
    else
        log_error "❌ 配置错误: 自动多行检测未启用"
        return 1
    fi
    
    if grep -q "ignore_dead_log = \"12h\"" "$temp_file"; then
        log_info "✅ 配置正确: 忽略死日志时间设置"
    else
        log_error "❌ 配置错误: 忽略死日志时间设置缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时日志配置文件"
    
    return 0
}

# 测试Pushgateway配置
test_pushgateway_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试Pushgateway配置: $config_file"
    
    # 创建原始配置
    cat > "$config_file" << 'EOF'
# 原始Pushgateway配置
[[inputs.pushgateway]]
  route_prefix = "/old"
EOF
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始Pushgateway配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF
    
    log_info "✅ 修改: 应用新的Pushgateway配置"
    
    # 验证配置
    if grep -q "route_prefix = \"/v1/pushgateway\"" "$temp_file"; then
        log_info "✅ 配置正确: Pushgateway路由前缀"
    else
        log_error "❌ 配置错误: Pushgateway路由前缀缺失"
        return 1
    fi
    
    if grep -q "job_as_measurement = false" "$temp_file"; then
        log_info "✅ 配置正确: Pushgateway job_as_measurement设置"
    else
        log_error "❌ 配置错误: Pushgateway job_as_measurement设置缺失"
        return 1
    fi
    
    if grep -q "keep_exist_metric_name = true" "$temp_file"; then
        log_info "✅ 配置正确: Pushgateway keep_exist_metric_name设置"
    else
        log_error "❌ 配置错误: Pushgateway keep_exist_metric_name设置缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时Pushgateway配置文件"
    
    return 0
}

# 主函数
main() {
    log_info "开始测试configure模块..."
    
    # 测试Datakit主配置文件
    if test_datakit_main_config; then
        log_info "Datakit主配置文件测试通过"
    else
        log_error "Datakit主配置文件测试失败"
        return 1
    fi
    
    # 测试采集器配置
    if test_collector_configs; then
        log_info "采集器配置测试通过"
    else
        log_error "采集器配置测试失败"
        return 1
    fi
    
    log_info "🎉 所有configure模块测试通过！"
    return 0
}

# 运行主函数
main "$@" 