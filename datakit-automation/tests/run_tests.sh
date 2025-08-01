#!/bin/bash

#=================================================
# 测试运行器
#=================================================
# 功能: 自动发现测试文件、并行执行、生成报告
#=================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试目录
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# 测试统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 测试开始时间
START_TIME=$(date +%s)

# 显示帮助信息
show_help() {
    cat << EOF
测试运行器 - Datakit 自动化安装工具

用法: $0 [选项] [测试路径]

选项:
    -h, --help          显示此帮助信息
    -v, --verbose       详细输出
    -p, --parallel      并行执行测试
    -c, --coverage      生成覆盖率报告
    -r, --report        生成详细报告
    -f, --filter PATTERN 过滤测试文件

测试路径:
    core                运行所有核心模块测试
    core/utils          运行工具函数测试
    core/logging        运行日志系统测试
    core/validation     运行验证系统测试
    core/initialize     运行初始化系统测试
    all                 运行所有测试

示例:
    $0                    # 运行所有测试
    $0 core              # 运行核心模块测试
    $0 core/utils        # 运行工具函数测试
    $0 -v -p             # 详细输出并并行执行
    $0 -f "test_utils"   # 只运行包含 "test_utils" 的测试

EOF
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查必需的命令
    for cmd in "bash" "find" "grep" "awk" "bc"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}错误: 缺少必需的依赖: ${missing_deps[*]}${NC}" >&2
        exit 1
    fi
}

# 发现测试文件
discover_test_files() {
    local search_path="$1"
    local pattern="${2:-test_*.sh}"
    
    if [ -z "$search_path" ]; then
        search_path="$TEST_DIR"
    fi
    
    # 检查是否是单个文件
    if [ -f "$search_path" ]; then
        echo "$search_path"
        return 0
    fi
    
    # 查找测试文件
    find "$search_path" -name "$pattern" -type f | sort
}

# 运行单个测试文件
run_test_file() {
    local test_file="$1"
    local verbose="$2"
    
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}错误: 测试文件不存在: $test_file${NC}" >&2
        return 1
    fi
    
    if [ ! -x "$test_file" ]; then
        chmod +x "$test_file"
    fi
    
    local test_name=$(basename "$test_file" .sh)
    local test_dir=$(dirname "$test_file")
    
    echo -e "${BLUE}运行测试: $test_name${NC}"
    
    # 切换到测试目录
    cd "$test_dir" || return 1
    
    # 运行测试
    if [ "$verbose" = "true" ]; then
        bash "$test_file"
    else
        # 显示测试用例执行情况
        bash "$test_file"
    fi
    
    local exit_code=$?
    
    # 返回项目根目录
    cd "$PROJECT_ROOT" || return 1
    
    return $exit_code
}

# 并行运行测试
run_tests_parallel() {
    local test_files=("$@")
    local max_jobs=4  # 最大并行数
    local jobs=()
    local results=()
    
    echo -e "${BLUE}并行运行 ${#test_files[@]} 个测试文件 (最大并行数: $max_jobs)${NC}"
    
    for test_file in "${test_files[@]}"; do
        # 等待有空闲的进程槽
        while [ ${#jobs[@]} -ge $max_jobs ]; do
            for i in "${!jobs[@]}"; do
                if ! kill -0 "${jobs[$i]}" 2>/dev/null; then
                    wait "${jobs[$i]}"
                    results[$i]=$?
                    unset jobs[$i]
                    unset results[$i]
                fi
            done
            jobs=("${jobs[@]}")  # 重新索引数组
            results=("${results[@]}")
            sleep 0.1
        done
        
        # 启动新测试
        run_test_file "$test_file" "$VERBOSE" &
        jobs+=($!)
    done
    
    # 等待所有测试完成
    for job in "${jobs[@]}"; do
        wait "$job"
        results+=($?)
    done
    
    # 统计结果
    for result in "${results[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        if [ $result -eq 0 ]; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    done
}

# 串行运行测试
run_tests_serial() {
    local test_files=("$@")
    
    echo -e "${BLUE}串行运行 ${#test_files[@]} 个测试文件${NC}"
    
    for test_file in "${test_files[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        if run_test_file "$test_file" "$VERBOSE"; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    done
}

# 生成覆盖率报告
generate_coverage_report() {
    local coverage_dir="$TEST_DIR/results/coverage"
    mkdir -p "$coverage_dir"
    
    echo -e "${BLUE}生成覆盖率报告...${NC}"
    
    # 这里可以添加实际的覆盖率计算逻辑
    # 目前只是一个占位符
    cat > "$coverage_dir/coverage_report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "total_lines": 0,
    "covered_lines": 0,
    "coverage_percentage": 0,
    "files": []
}
EOF
    
    echo -e "${GREEN}覆盖率报告已生成: $coverage_dir/coverage_report.json${NC}"
}

# 生成汇总报告
generate_summary_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    # 计算成功率
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
    fi
    
    # 生成汇总报告
    local summary_file="$TEST_DIR/results/test_reports/summary_$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "$(dirname "$summary_file")"
    
    cat > "$summary_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $duration,
    "summary": {
        "total_tests": $TOTAL_TESTS,
        "passed_tests": $PASSED_TESTS,
        "failed_tests": $FAILED_TESTS,
        "skipped_tests": $SKIPPED_TESTS,
        "success_rate": $success_rate
    },
    "options": {
        "verbose": $VERBOSE,
        "parallel": $PARALLEL,
        "coverage": $COVERAGE
    }
}
EOF
    
    # 输出汇总信息
    echo ""
    echo -e "${BLUE}=== 测试汇总 ===${NC}"
    echo -e "总测试文件数: ${TOTAL_TESTS}"
    echo -e "通过: ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "失败: ${RED}${FAILED_TESTS}${NC}"
    echo -e "跳过: ${YELLOW}${SKIPPED_TESTS}${NC}"
    echo -e "成功率: ${success_rate}%"
    echo -e "执行时间: ${duration}秒"
    echo -e "汇总报告: $summary_file"
    
    # 返回退出码
    if [ $FAILED_TESTS -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 主函数
main() {
    # 解析命令行参数
    VERBOSE=false
    PARALLEL=false
    COVERAGE=false
    REPORT=false
    FILTER=""
    TEST_PATH=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -c|--coverage)
                COVERAGE=true
                shift
                ;;
            -r|--report)
                REPORT=true
                shift
                ;;
            -f|--filter)
                FILTER="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}错误: 未知选项 $1${NC}" >&2
                show_help
                exit 1
                ;;
            *)
                TEST_PATH="$1"
                shift
                ;;
        esac
    done
    
    # 检查依赖
    check_dependencies
    
    # 确定测试路径
    if [ -z "$TEST_PATH" ]; then
        TEST_PATH="all"
    fi
    
    # 根据测试路径确定搜索范围
    case "$TEST_PATH" in
        "all")
            SEARCH_PATH="$TEST_DIR"
            ;;
        "core")
            SEARCH_PATH="$TEST_DIR/core"
            ;;
        core/*)
            # 处理 core/模块名 的情况，查找对应的测试文件
            local module_name=$(basename "$TEST_PATH")
            local test_file="$TEST_DIR/core/test_${module_name}.sh"
            if [ -f "$test_file" ]; then
                SEARCH_PATH="$test_file"
            else
                SEARCH_PATH="$TEST_DIR/$TEST_PATH"
            fi
            ;;
        *)
            SEARCH_PATH="$TEST_PATH"
            ;;
    esac
    
    # 发现测试文件
    echo -e "${BLUE}在 $SEARCH_PATH 中查找测试文件...${NC}"
    test_files=($(discover_test_files "$SEARCH_PATH"))
    
    if [ ${#test_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}警告: 在 $SEARCH_PATH 中未找到测试文件${NC}"
        exit 0
    fi
    
    # 应用过滤器
    if [ -n "$FILTER" ]; then
        filtered_files=()
        for file in "${test_files[@]}"; do
            if [[ "$file" == *"$FILTER"* ]]; then
                filtered_files+=("$file")
            fi
        done
        test_files=("${filtered_files[@]}")
        
        if [ ${#test_files[@]} -eq 0 ]; then
            echo -e "${YELLOW}警告: 没有测试文件匹配过滤器 '$FILTER'${NC}"
            exit 0
        fi
    fi
    
    echo -e "${GREEN}找到 ${#test_files[@]} 个测试文件${NC}"
    
    # 运行测试
    if [ "$PARALLEL" = "true" ]; then
        run_tests_parallel "${test_files[@]}"
    else
        run_tests_serial "${test_files[@]}"
    fi
    
    # 生成覆盖率报告
    if [ "$COVERAGE" = "true" ]; then
        generate_coverage_report
    fi
    
    # 生成汇总报告
    generate_summary_report
}

# 运行主函数
main "$@" 