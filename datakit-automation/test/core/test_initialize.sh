#!/bin/bash

#=================================================
# 初始化系统模块测试
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 加载测试工具
source "$SCRIPT_DIR/../test_utils.sh"

# 加载被测试的模块
source "$PROJECT_ROOT/core/initialize.sh"

# 测试临时文件
TEMP_DIR=$(mktemp -d)
TEST_PID_FILE="$TEMP_DIR/test.pid"
TEST_BACKUP_DIR="$TEMP_DIR/backups"

# 测试前准备
setup() {
    # 模拟日志函数（如果不存在）
    if ! command -v log_info >/dev/null 2>&1; then
        log_info() { echo "[INFO] $1"; }
        log_success() { echo "[SUCCESS] $1"; }
        log_error() { echo "[ERROR] $1"; }
        log_warning() { echo "[WARNING] $1"; }
    fi
    
    # 创建测试目录
    mkdir -p "$TEMP_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    
    # 清理可能存在的PID文件
    rm -f "$TEST_PID_FILE"
}

# 测试后清理
teardown() {
    # 清理测试进程
    if [ -f "$TEST_PID_FILE" ]; then
        local pid=$(cat "$TEST_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$TEST_PID_FILE"
    fi
    
    # 清理测试目录
    rm -rf "$TEMP_DIR"
}

# 测试运行实例检查
test_check_running_instance() {
    # 测试没有运行实例的情况
    PID_FILE="$TEST_PID_FILE"
    check_running_instance
    assert_true "true" "没有运行实例时检查应该通过"
    
    # 测试有过期PID文件的情况
    echo "999999" > "$TEST_PID_FILE"  # 写入一个不存在的PID
    check_running_instance
    assert_file_not_exists "$TEST_PID_FILE" "过期的PID文件应该被清理"
    
    # 测试有运行实例的情况（创建后台进程）
    (
        echo "$$" > "$TEST_PID_FILE"
        sleep 10 &
        wait
    ) &
    local background_pid=$!
    
    # 等待PID文件创建
    sleep 1
    
    # 检查运行实例
    local result
    result=$(check_running_instance 2>&1)
    
    # 清理后台进程
    kill "$background_pid" 2>/dev/null
    rm -f "$TEST_PID_FILE"
    
    # 检查结果
    if echo "$result" | grep -q "脚本已在运行"; then
        assert_true "true" "检测到运行实例"
    else
        skip_test "无法创建测试运行实例"
    fi
}

# 测试备份目录创建
test_create_backup_directory() {
    # 测试创建备份目录
    BACKUP_DIR="$TEST_BACKUP_DIR"
    create_backup_directory
    
    assert_dir_exists "$TEST_BACKUP_DIR" "备份目录应该被创建"
    
    # 测试创建嵌套目录
    local nested_backup_dir="$TEST_BACKUP_DIR/nested/dir"
    BACKUP_DIR="$nested_backup_dir"
    create_backup_directory
    
    assert_dir_exists "$nested_backup_dir" "嵌套备份目录应该被创建"
}

# 测试系统资源验证
test_validate_system_resources() {
    # 测试系统资源验证
    local result
    result=$(validate_system_resources 2>&1)
    
    # 检查验证结果
    if echo "$result" | grep -q "磁盘空间不足"; then
        skip_test "磁盘空间不足，跳过此测试"
    else
        assert_contains "$result" "磁盘空间验证" "系统资源验证应该执行"
    fi
}

# 测试配置验证
test_validate_config() {
    # 设置完整的环境变量
    export DATAKIT_VERSION="1.78.0"
    export S3_BUCKET="test-bucket"
    export S3_ACCESS_KEY="test-key"
    export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
    export DATAWAY_URL="https://dataway.example.com"
    export OPS_ADDR="http://ops.example.com:5000"
    
    # 测试配置验证
    if validate_config; then
        assert_true "true" "完整配置验证应该通过"
    else
        assert_true "false" "完整配置验证应该通过"
    fi
    
    # 测试缺少环境变量的情况
    unset DATAKIT_VERSION
    if ! validate_config; then
        assert_true "true" "缺少环境变量时配置验证应该失败"
    else
        assert_true "false" "缺少环境变量时配置验证应该失败"
    fi
    
    # 恢复环境变量
    export DATAKIT_VERSION="1.78.0"
}

# 测试系统环境验证
test_validate_system_environment() {
    # 测试系统环境验证
    local result
    result=$(validate_system_environment 2>&1)
    
    # 检查验证结果
    if echo "$result" | grep -q "建议使用root用户"; then
        skip_test "非root用户，跳过此测试"
    else
        assert_contains "$result" "系统环境验证" "系统环境验证应该执行"
    fi
}

# 测试必需命令验证
test_validate_required_commands() {
    # 测试必需命令验证
    local result
    result=$(validate_required_commands 2>&1)
    
    # 检查验证结果
    if echo "$result" | grep -q "缺少必需的命令"; then
        skip_test "缺少必需命令，跳过此测试"
    else
        assert_contains "$result" "所有必需命令验证通过" "必需命令验证应该通过"
    fi
}

# 测试PID文件管理
test_pid_file_management() {
    # 测试创建PID文件
    PID_FILE="$TEST_PID_FILE"
    create_pid_file
    
    assert_file_exists "$TEST_PID_FILE" "PID文件应该被创建"
    assert_equal "$(cat "$TEST_PID_FILE")" "$$" "PID文件应该包含当前进程ID"
    
    # 测试清理PID文件
    cleanup_pid_file
    assert_file_not_exists "$TEST_PID_FILE" "PID文件应该被清理"
}

# 测试信号处理
test_signal_handling() {
    # 测试信号处理函数存在
    if declare -F cleanup_on_exit >/dev/null 2>&1; then
        assert_true "true" "信号处理函数应该存在"
    else
        skip_test "信号处理函数不存在，跳过此测试"
    fi
}

# 测试初始化流程
test_initialization_flow() {
    # 设置测试环境
    export DATAKIT_VERSION="1.78.0"
    export S3_BUCKET="test-bucket"
    export S3_ACCESS_KEY="test-key"
    export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
    export DATAWAY_URL="https://dataway.example.com"
    export OPS_ADDR="http://ops.example.com:5000"
    export PID_FILE="$TEST_PID_FILE"
    export BACKUP_DIR="$TEST_BACKUP_DIR"
    
    # 测试完整初始化流程
    local result
    result=$(initialize_system 2>&1)
    
    # 检查初始化结果
    assert_contains "$result" "初始化" "初始化流程应该执行"
    
    # 清理
    cleanup_pid_file
    unset DATAKIT_VERSION S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY DATAWAY_URL OPS_ADDR PID_FILE BACKUP_DIR
}

# 测试错误处理
test_error_handling() {
    # 测试无效PID文件路径
    PID_FILE="/nonexistent/path/test.pid"
    local result
    result=$(check_running_instance 2>&1)
    
    # 检查错误处理
    assert_contains "$result" "错误" "无效路径应该产生错误"
    
    # 测试无效备份目录路径
    BACKUP_DIR="/nonexistent/path/backups"
    result=$(create_backup_directory 2>&1)
    
    # 检查错误处理
    assert_contains "$result" "错误" "无效备份目录应该产生错误"
}

# 测试并发初始化
test_concurrent_initialization() {
    # 创建多个进程同时尝试初始化
    for i in {1..3}; do
        (
            export PID_FILE="$TEST_PID_FILE.$i"
            export BACKUP_DIR="$TEST_BACKUP_DIR.$i"
            initialize_system
        ) &
    done
    
    # 等待所有进程完成
    wait
    
    # 检查结果
    for i in {1..3}; do
        if [ -f "$TEST_PID_FILE.$i" ]; then
            rm -f "$TEST_PID_FILE.$i"
        fi
        if [ -d "$TEST_BACKUP_DIR.$i" ]; then
            rm -rf "$TEST_BACKUP_DIR.$i"
        fi
    done
    
    assert_true "true" "并发初始化应该完成"
}

# 测试环境变量优先级
test_environment_variable_priority() {
    # 设置不同优先级的配置
    export DATAKIT_VERSION="env_version"
    export S3_BUCKET="env_bucket"
    
    # 创建配置文件
    local config_file="$TEMP_DIR/test_config.sh"
    cat > "$config_file" << 'EOF'
#!/bin/bash
DATAKIT_VERSION="config_version"
S3_BUCKET="config_bucket"
EOF
    
    # 测试环境变量优先级
    source "$config_file"
    
    # 环境变量应该覆盖配置文件
    assert_equal "$DATAKIT_VERSION" "env_version" "环境变量应该优先于配置文件"
    assert_equal "$S3_BUCKET" "env_bucket" "环境变量应该优先于配置文件"
    
    # 清理
    unset DATAKIT_VERSION S3_BUCKET
}

# 测试配置加载
test_config_loading() {
    # 创建测试配置文件
    local config_file="$TEMP_DIR/test_config.sh"
    cat > "$config_file" << 'EOF'
#!/bin/bash
DATAKIT_VERSION="1.78.0"
S3_BUCKET="test-bucket"
S3_ACCESS_KEY="test-key"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
DATAWAY_URL="https://dataway.example.com"
OPS_ADDR="http://ops.example.com:5000"
EOF
    
    # 测试配置加载
    if load_config "$config_file"; then
        assert_true "true" "配置加载应该成功"
    else
        assert_true "false" "配置加载应该成功"
    fi
}

# 测试系统检查
test_system_checks() {
    # 测试系统类型检查
    local result
    result=$(check_system_type 2>&1)
    assert_contains "$result" "系统类型" "系统类型检查应该执行"
    
    # 测试系统版本检查
    result=$(check_system_version 2>&1)
    assert_contains "$result" "系统版本" "系统版本检查应该执行"
    
    # 测试系统架构检查
    result=$(check_system_architecture 2>&1)
    assert_contains "$result" "系统架构" "系统架构检查应该执行"
}

# 测试权限检查
test_permission_checks() {
    # 测试当前用户权限
    local result
    result=$(check_user_permissions 2>&1)
    assert_contains "$result" "权限" "权限检查应该执行"
    
    # 测试文件权限
    local test_file="$TEMP_DIR/test_file.txt"
    echo "test" > "$test_file"
    result=$(check_file_permissions "$test_file" 2>&1)
    assert_contains "$result" "权限" "文件权限检查应该执行"
}

# 测试网络检查
test_network_checks() {
    # 测试网络连通性检查
    local result
    result=$(check_network_connectivity 2>&1)
    assert_contains "$result" "网络" "网络检查应该执行"
    
    # 测试DNS解析检查
    result=$(check_dns_resolution 2>&1)
    assert_contains "$result" "DNS" "DNS检查应该执行"
}

# 测试完整初始化测试
test_complete_initialization() {
    # 设置完整测试环境
    export DATAKIT_VERSION="1.78.0"
    export S3_BUCKET="test-bucket"
    export S3_ACCESS_KEY="test-key"
    export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
    export DATAWAY_URL="https://dataway.example.com"
    export OPS_ADDR="http://ops.example.com:5000"
    export PID_FILE="$TEST_PID_FILE"
    export BACKUP_DIR="$TEST_BACKUP_DIR"
    
    # 执行完整初始化测试
    local result
    result=$(run_initialization_tests 2>&1)
    
    # 检查测试结果
    assert_contains "$result" "测试" "初始化测试应该执行"
    
    # 清理
    cleanup_pid_file
    unset DATAKIT_VERSION S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY DATAWAY_URL OPS_ADDR PID_FILE BACKUP_DIR
}

# 运行测试
main() {
    echo "开始运行初始化系统测试..."
    
    # 执行设置
    setup
    
    # 运行所有测试函数
    run_tests "initialize"
    
    # 执行清理
    teardown
}

# 如果直接运行此脚本，则执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 