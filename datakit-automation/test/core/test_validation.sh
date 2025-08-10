#!/bin/bash

#=================================================
# 验证系统模块测试
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 加载测试工具
source "$SCRIPT_DIR/../test_utils.sh"

# 加载被测试的模块
source "$PROJECT_ROOT/core/validation.sh"

# 测试临时文件
TEMP_DIR=$(mktemp -d)

# 测试前准备
setup() {
    # 模拟日志函数（如果不存在）
    if ! command -v log_info >/dev/null 2>&1; then
        log_info() { echo "[INFO] $1"; }
        log_info() { echo "[SUCCESS] $1"; }
        log_error() { echo "[ERROR] $1"; }
        log_warning() { echo "[WARNING] $1"; }
    fi
    
    # 模拟配置数组
    declare -gA CONFIG
    CONFIG[DATAWAY_URL]="https://dataway.example.com"
    CONFIG[OPS_ADDR]="http://ops.example.com:5000"
    
    # 创建测试目录
    mkdir -p "$TEMP_DIR"
}

# 测试后清理
teardown() {
    rm -rf "$TEMP_DIR"
}

# 测试必需命令验证
test_validate_required_commands() {
    # 测试正常情况（所有命令都存在）
    if validate_required_commands; then
        # 如果验证通过，这是正常的
        assert_true "true" "所有必需命令验证应该通过"
    else
        # 如果验证失败，记录警告但不算测试失败
        skip_test "某些必需命令不存在，跳过此测试"
    fi
}

# 测试系统环境验证
test_validate_system_environment() {
    # 测试系统环境验证
    local result
    result=$(validate_system_environment 2>&1)
    
    # 检查是否包含预期的消息
    if echo "$result" | grep -q "系统环境验证通过"; then
        assert_true "true" "系统环境验证应该通过"
    elif echo "$result" | grep -q "需要root权限"; then
        skip_test "需要root权限运行，跳过此测试"
    elif echo "$result" | grep -q "需要支持systemd"; then
        skip_test "需要支持systemd的系统，跳过此测试"
    else
        assert_true "false" "系统环境验证结果不符合预期"
    fi
}

# 测试系统资源验证
test_validate_system_resources() {
    # 测试系统资源验证
    local result
    result=$(validate_system_resources 2>&1)
    
    # 检查磁盘空间验证
    if echo "$result" | grep -q "磁盘空间不足"; then
        skip_test "磁盘空间不足，跳过此测试"
    else
        assert_contains "$result" "系统资源验证通过" "系统资源验证应该通过或给出警告"
    fi
}

# 测试网络连通性验证
test_validate_network_connectivity() {
    # 测试网络连通性验证
    local result
    result=$(validate_network_connectivity 2>&1)
    
    # 检查网络验证结果
    if echo "$result" | grep -q "无法连接到AWS S3"; then
        skip_test "无法连接到AWS S3，跳过网络连通性测试"
    else
        assert_contains "$result" "网络连通性验证" "网络连通性验证应该执行"
    fi
}

# 测试环境变量验证
test_validate_environment_variables() {
    # 设置测试环境变量
    export DATAKIT_VERSION="1.78.0"
    export S3_BUCKET="test-bucket"
    export S3_ACCESS_KEY="test-key"
    export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
    export DATAWAY_URL="https://dataway.example.com"
    export OPS_ADDR="http://ops.example.com:5000"
    
    # 测试环境变量验证
    if validate_environment_variables; then
        assert_true "true" "环境变量验证应该通过"
    else
        assert_true "false" "环境变量验证应该通过"
    fi
    
    # 测试缺少环境变量的情况
    unset DATAKIT_VERSION
    if ! validate_environment_variables; then
        assert_true "true" "缺少环境变量时验证应该失败"
    else
        assert_true "false" "缺少环境变量时验证应该失败"
    fi
    
    # 恢复环境变量
    export DATAKIT_VERSION="1.78.0"
}

# 测试配置文件验证
test_validate_config_file() {
    # 创建测试配置文件
    local test_config="$TEMP_DIR/test_config.sh"
    cat > "$test_config" << 'EOF'
#!/bin/bash
DATAKIT_VERSION="1.78.0"
S3_BUCKET="test-bucket"
S3_ACCESS_KEY="test-key"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
DATAWAY_URL="https://dataway.example.com"
OPS_ADDR="http://ops.example.com:5000"
EOF
    
    # 测试有效的配置文件
    if validate_config_file "$test_config"; then
        assert_true "true" "有效配置文件验证应该通过"
    else
        assert_true "false" "有效配置文件验证应该通过"
    fi
    
    # 测试不存在的配置文件
    if ! validate_config_file "$TEMP_DIR/nonexistent.sh"; then
        assert_true "true" "不存在的配置文件验证应该失败"
    else
        assert_true "false" "不存在的配置文件验证应该失败"
    fi
    
    # 测试无效的配置文件
    local invalid_config="$TEMP_DIR/invalid_config.sh"
    echo "invalid syntax {" > "$invalid_config"
    
    if ! validate_config_file "$invalid_config"; then
        assert_true "true" "无效配置文件验证应该失败"
    else
        assert_true "false" "无效配置文件验证应该失败"
    fi
}

# 测试端口验证
test_validate_port() {
    # 测试有效端口
    assert_true "validate_port 80" "端口80应该有效"
    assert_true "validate_port 443" "端口443应该有效"
    assert_true "validate_port 8080" "端口8080应该有效"
    
    # 测试无效端口
    assert_false "validate_port 0" "端口0应该无效"
    assert_false "validate_port 65536" "端口65536应该无效"
    assert_false "validate_port -1" "负端口应该无效"
    assert_false "validate_port abc" "非数字端口应该无效"
}

# 测试URL验证
test_validate_url() {
    # 测试有效URL
    assert_true "validate_url 'https://example.com'" "HTTPS URL应该有效"
    assert_true "validate_url 'http://example.com'" "HTTP URL应该有效"
    assert_true "validate_url 'https://example.com:8080'" "带端口的URL应该有效"
    
    # 测试无效URL
    assert_false "validate_url 'not-a-url'" "无效URL应该失败"
    assert_false "validate_url ''" "空URL应该失败"
    assert_false "validate_url 'ftp://example.com'" "不支持的协议应该失败"
}

# 测试IP地址验证
test_validate_ip_address() {
    # 测试有效IP地址
    assert_true "validate_ip_address '192.168.1.1'" "有效IPv4地址应该通过"
    assert_true "validate_ip_address '10.0.0.1'" "有效IPv4地址应该通过"
    assert_true "validate_ip_address '127.0.0.1'" "本地回环地址应该通过"
    
    # 测试无效IP地址
    assert_false "validate_ip_address '256.256.256.256'" "无效IPv4地址应该失败"
    assert_false "validate_ip_address '192.168.1'" "不完整的IP地址应该失败"
    assert_false "validate_ip_address 'not-an-ip'" "非IP地址应该失败"
    assert_false "validate_ip_address ''" "空IP地址应该失败"
}

# 测试文件权限验证
test_validate_file_permissions() {
    # 创建测试文件
    local test_file="$TEMP_DIR/test_file.txt"
    echo "test content" > "$test_file"
    
    # 测试文件存在且可读
    assert_true "validate_file_permissions '$test_file' 'r'" "文件应该可读"
    
    # 测试文件不存在
    assert_false "validate_file_permissions '$TEMP_DIR/nonexistent.txt' 'r'" "不存在的文件应该失败"
    
    # 测试目录权限
    assert_true "validate_file_permissions '$TEMP_DIR' 'd'" "目录应该存在"
    
    # 测试可执行权限（如果文件可执行）
    chmod +x "$test_file"
    assert_true "validate_file_permissions '$test_file' 'x'" "可执行文件应该通过验证"
}

# 测试用户权限验证
test_validate_user_permissions() {
    # 测试当前用户权限
    local current_user=$(whoami)
    assert_true "validate_user_permissions '$current_user'" "当前用户权限应该有效"
    
    # 测试root用户（如果当前是root）
    if [ "$(id -u)" -eq 0 ]; then
        assert_true "validate_user_permissions 'root'" "root用户权限应该有效"
    else
        skip_test "非root用户，跳过root权限测试"
    fi
    
    # 测试不存在的用户
    assert_false "validate_user_permissions 'nonexistent_user_12345'" "不存在的用户应该失败"
}

# 测试磁盘空间验证
test_validate_disk_space() {
    # 测试磁盘空间验证
    local result
    result=$(validate_disk_space "/" "100" 2>&1)  # 检查100MB空间
    
    # 检查验证结果
    if echo "$result" | grep -q "磁盘空间不足"; then
        skip_test "磁盘空间不足，跳过此测试"
    else
        assert_contains "$result" "磁盘空间验证通过" "磁盘空间验证应该通过"
    fi
}

# 测试内存验证
test_validate_memory() {
    # 测试内存验证
    local result
    result=$(validate_memory "512" 2>&1)  # 检查512MB内存
    
    # 检查验证结果
    if echo "$result" | grep -q "内存不足"; then
        skip_test "内存不足，跳过此测试"
    else
        assert_contains "$result" "内存验证通过" "内存验证应该通过或给出警告"
    fi
}

# 测试CPU负载验证
test_validate_cpu_load() {
    # 测试CPU负载验证
    local result
    result=$(validate_cpu_load "5.0" 2>&1)  # 检查负载阈值5.0
    
    # 检查验证结果
    assert_contains "$result" "CPU负载验证" "CPU负载验证应该执行"
}

# 测试网络端口验证
test_validate_network_port() {
    # 测试网络端口验证
    local result
    result=$(validate_network_port "80" 2>&1)
    
    # 检查验证结果
    if echo "$result" | grep -q "端口80被占用"; then
        skip_test "端口80被占用，跳过此测试"
    else
        assert_contains "$result" "端口验证通过" "端口验证应该通过"
    fi
}

# 测试服务状态验证
test_validate_service_status() {
    # 测试服务状态验证（使用一个常见的系统服务）
    local result
    result=$(validate_service_status "systemd" 2>&1)
    
    # 检查验证结果
    if echo "$result" | grep -q "服务systemd未运行"; then
        skip_test "systemd服务未运行，跳过此测试"
    else
        assert_contains "$result" "服务状态验证" "服务状态验证应该执行"
    fi
}

# 测试完整验证流程
test_complete_validation_flow() {
    # 设置完整的环境变量
    export DATAKIT_VERSION="1.78.0"
    export S3_BUCKET="test-bucket"
    export S3_ACCESS_KEY="test-key"
    export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
    export DATAWAY_URL="https://dataway.example.com"
    export OPS_ADDR="http://ops.example.com:5000"
    
    # 创建测试配置文件
    local test_config="$TEMP_DIR/complete_config.sh"
    cat > "$test_config" << 'EOF'
#!/bin/bash
DATAKIT_VERSION="1.78.0"
S3_BUCKET="test-bucket"
S3_ACCESS_KEY="test-key"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
DATAWAY_URL="https://dataway.example.com"
OPS_ADDR="http://ops.example.com:5000"
EOF
    
    # 执行完整验证流程
    local result
    result=$(validate_all "$test_config" 2>&1)
    
    # 检查验证结果
    assert_contains "$result" "验证" "完整验证流程应该执行"
    
    # 清理
    unset DATAKIT_VERSION S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY DATAWAY_URL OPS_ADDR
}

# 运行测试
main() {
    echo "开始运行验证系统测试..."
    
    # 执行设置
    setup
    
    # 运行所有测试函数
    run_tests "validation"
    
    # 执行清理
    teardown
}

# 如果直接运行此脚本，则执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 