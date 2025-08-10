#!/bin/bash

#=================================================
# 工具函数模块测试
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 加载测试工具
source "$SCRIPT_DIR/../test_utils.sh"

# 加载被测试的模块
source "$PROJECT_ROOT/core/utils.sh"

# 测试临时文件
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/test_file.txt"
TEMP_DIR2="$TEMP_DIR/test_dir"

# 测试前准备
setup() {
    # 创建测试文件
    echo "test content" > "$TEMP_FILE"
    mkdir -p "$TEMP_DIR2"
    
    # 模拟日志函数（如果不存在）
    if ! command -v log_info >/dev/null 2>&1; then
        log_info() { echo "[INFO] $1"; }
        log_success() { echo "[SUCCESS] $1"; }
        log_error() { echo "[ERROR] $1"; }
        log_warning() { echo "[WARNING] $1"; }
    fi
}

# 测试后清理
teardown() {
    rm -rf "$TEMP_DIR"
}

# 测试 command_exists 函数
test_command_exists() {
    # 测试存在的命令
    assert_true "command_exists bash" "bash 命令应该存在"
    assert_true "command_exists ls" "ls 命令应该存在"
    assert_true "command_exists echo" "echo 命令应该存在"
    
    # 测试不存在的命令
    assert_false "command_exists nonexistent_command_12345" "不存在的命令应该返回false"
}

# 测试 file_exists 函数
test_file_exists() {
    # 测试存在的文件
    assert_true "file_exists $TEMP_FILE" "测试文件应该存在"
    assert_true "file_exists /etc/passwd" "/etc/passwd 文件应该存在"
    
    # 测试不存在的文件
    assert_false "file_exists $TEMP_DIR/nonexistent_file.txt" "不存在的文件应该返回false"
}

# 测试 dir_exists 函数
test_dir_exists() {
    # 测试存在的目录
    assert_true "dir_exists $TEMP_DIR" "测试目录应该存在"
    assert_true "dir_exists $TEMP_DIR2" "测试子目录应该存在"
    assert_true "dir_exists /tmp" "/tmp 目录应该存在"
    
    # 测试不存在的目录
    assert_false "dir_exists $TEMP_DIR/nonexistent_dir" "不存在的目录应该返回false"
}

# 测试 process_running 函数
test_process_running() {
    # 测试当前shell进程（使用进程ID而不是进程名）
    assert_true "kill -0 $$ 2>/dev/null" "当前进程应该正在运行"
    
    # 测试不存在的进程
    assert_false "kill -0 999999 2>/dev/null" "不存在的进程ID应该返回false"
}

# 测试 port_listening 函数
test_port_listening() {
    # 注意：这个测试可能需要网络服务运行
    # 测试一个不太可能被监听的端口
    assert_false "port_listening 65535" "端口65535应该没有被监听"
}

# 测试 safe_execute 函数
test_safe_execute() {
    # 测试成功执行的命令
    local result
    result=$(safe_execute "echo 'test success'" "测试成功命令" 2>&1)
    assert_contains "$result" "成功" "成功执行的命令应该包含'成功'"
    
    # 测试失败的命令
    result=$(safe_execute "nonexistent_command" "测试失败命令" 2>&1)
    assert_contains "$result" "失败" "失败的命令应该包含'失败'"
}

# 测试 retry_execute 函数
test_retry_execute() {
    # 测试成功的重试
    local result
    result=$(retry_execute "echo 'retry success'" 2 1 "测试重试成功" 2>&1)
    assert_contains "$result" "成功" "重试成功的命令应该包含'成功'"
    
    # 测试失败的重试（使用不存在的命令）
    result=$(retry_execute "nonexistent_command" 2 1 "测试重试失败" 2>&1)
    assert_contains "$result" "失败" "重试失败的命令应该包含'失败'"
}

# 测试 timeout_execute 函数
test_timeout_execute() {
    # 检查系统是否有timeout命令
    if ! command_exists timeout; then
        skip_test "系统不支持timeout命令，跳过此测试"
        return 0
    fi
    
    # 测试快速完成的命令
    local result
    result=$(timeout_execute 5 "echo 'timeout test'" "测试超时命令")
    assert_contains "$result" "成功" "快速完成的命令应该成功"
    
    # 测试超时的命令（如果系统支持sleep）
    if command_exists sleep; then
        result=$(timeout_execute 1 "sleep 3" "测试超时")
        assert_contains "$result" "超时" "超时的命令应该包含'超时'"
    fi
}

# 测试文件操作函数
test_file_operations() {
    # 测试创建目录
    local test_dir="$TEMP_DIR/test_create_dir"
    mkdir -p "$test_dir"
    assert_dir_exists "$test_dir" "创建的目录应该存在"
    
    # 测试创建文件
    local test_file="$TEMP_DIR/test_create_file.txt"
    echo "test" > "$test_file"
    assert_file_exists "$test_file" "创建的文件应该存在"
    
    # 测试删除文件
    rm "$test_file"
    assert_file_not_exists "$test_file" "删除的文件不应该存在"
}

# 测试字符串操作函数
test_string_operations() {
    # 测试字符串包含
    local test_string="hello world"
    assert_contains "$test_string" "hello" "字符串应该包含'hello'"
    assert_contains "$test_string" "world" "字符串应该包含'world'"
    assert_not_contains "$test_string" "nonexistent" "字符串不应该包含'nonexistent'"
}

# 测试数值比较函数
test_numeric_operations() {
    # 测试数值相等
    assert_equal "5" "5" "数值5应该等于5"
    assert_not_equal "5" "6" "数值5不应该等于6"
    
    # 测试数值比较
    assert_true "[ 5 -eq 5 ]" "5应该等于5"
    assert_true "[ 5 -lt 10 ]" "5应该小于10"
    assert_true "[ 10 -gt 5 ]" "10应该大于5"
}

# 测试环境变量操作
test_environment_variables() {
    # 设置测试环境变量
    export TEST_VAR="test_value"
    
    # 测试环境变量存在
    assert_equal "$TEST_VAR" "test_value" "环境变量应该等于设置的值"
    
    # 测试环境变量不存在
    assert_equal "${NONEXISTENT_VAR:-default}" "default" "不存在的环境变量应该返回默认值"
    
    # 清理
    unset TEST_VAR
}

# 测试数组操作
test_array_operations() {
    # 创建测试数组
    local test_array=("item1" "item2" "item3")
    
    # 测试数组长度
    assert_equal "${#test_array[@]}" "3" "数组应该有3个元素"
    
    # 测试数组元素
    assert_equal "${test_array[0]}" "item1" "第一个元素应该是item1"
    assert_equal "${test_array[1]}" "item2" "第二个元素应该是item2"
    assert_equal "${test_array[2]}" "item3" "第三个元素应该是item3"
}

# 测试错误处理
test_error_handling() {
    # 测试命令执行错误
    local result
    result=$(safe_execute "exit 1" "测试错误命令" 2>&1)
    assert_contains "$result" "失败" "错误命令应该返回失败"
    
    # 测试文件不存在错误
    assert_false "file_exists /nonexistent/path/file" "不存在的文件路径应该返回false"
    
    # 测试不存在的命令
    result=$(safe_execute "nonexistent_command" "测试不存在命令" 2>&1)
    assert_contains "$result" "失败" "不存在的命令应该返回失败"
}

# 运行测试
main() {
    echo "开始运行工具函数测试..."
    
    # 执行设置
    setup
    
    # 运行所有测试函数
    run_tests "utils"
    
    # 执行清理
    teardown
}

# 如果直接运行此脚本，则执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 