#!/bin/bash

#=================================================
# Core模块综合测试运行器
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 测试结果目录
RESULTS_DIR="$SCRIPT_DIR/results/test_reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
TEST_NAME="core_modules"

# 测试模块列表
TEST_MODULES=(
    "datakit_service"
    "error_handler"
    "logging"
)

# 创建结果目录
mkdir -p "$RESULTS_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 运行单个模块测试
run_module_test() {
    local module="$1"
    local test_script="$SCRIPT_DIR/test_${module}.sh"
    local run_script="$SCRIPT_DIR/run_${module}_tests.sh"
    
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}开始测试模块: $module${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    if [[ -f "$test_script" ]]; then
        if [[ -f "$run_script" ]]; then
            # 使用专门的运行器
            bash "$run_script"
            local exit_code=$?
        else
            # 直接运行测试脚本
            bash "$test_script"
            local exit_code=$?
        fi
        
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ 模块 $module 测试通过${NC}"
            return 0
        else
            echo -e "${RED}✗ 模块 $module 测试失败${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ 模块 $module 的测试脚本不存在: $test_script${NC}"
        return 2
    fi
}

# 显示测试结果
show_test_results() {
    local total_modules=${#TEST_MODULES[@]}
    local passed_modules=0
    local failed_modules=0
    local skipped_modules=0
    
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}测试结果统计${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo "总模块数: $total_modules"
    
    for module in "${TEST_MODULES[@]}"; do
        case "${MODULE_RESULTS[$module]}" in
            0)
                passed_modules=$((passed_modules + 1))
                ;;
            1)
                failed_modules=$((failed_modules + 1))
                ;;
            *)
                skipped_modules=$((skipped_modules + 1))
                ;;
        esac
    done
    
    echo "通过: $passed_modules"
    echo "失败: $failed_modules"
    echo "跳过: $skipped_modules"
    
    if [[ $total_modules -gt 0 ]]; then
        local pass_rate=$((passed_modules * 100 / total_modules))
        echo "通过率: ${pass_rate}%"
    fi
    
    echo ""
    echo "详细结果:"
    echo "------------------------------------------"
    for module in "${TEST_MODULES[@]}"; do
        case "${MODULE_RESULTS[$module]}" in
            0)
                echo -e "${GREEN}✓ PASS${NC} $module"
                ;;
            1)
                echo -e "${RED}✗ FAIL${NC} $module"
                ;;
            *)
                echo -e "${YELLOW}⚠ SKIP${NC} $module"
                ;;
        esac
    done
    
    echo ""
    if [[ $failed_modules -eq 0 ]]; then
        echo -e "${GREEN}🎉 所有模块测试通过！${NC}"
        return 0
    else
        echo -e "${RED}⚠️  有 $failed_modules 个模块测试失败${NC}"
        return 1
    fi
}

# 主函数
main() {
    echo "================================================="
    echo "开始运行 Core 模块综合测试"
    echo "================================================="
    echo "测试时间: $(date)"
    echo "结果目录: $RESULTS_DIR"
    echo "测试模块: ${TEST_MODULES[*]}"
    echo ""
    
    # 存储每个模块的测试结果
    declare -A MODULE_RESULTS
    
    # 运行所有模块测试
    local overall_success=true
    
    for module in "${TEST_MODULES[@]}"; do
        if run_module_test "$module"; then
            MODULE_RESULTS["$module"]=0
        else
            MODULE_RESULTS["$module"]=1
            overall_success=false
        fi
        echo ""
    done
    
    # 生成综合测试报告
    {
        echo "=== 综合测试开始: $TEST_NAME ==="
        echo "开始时间: $(date)"
        echo ""
        
        for module in "${TEST_MODULES[@]}"; do
            echo "模块: $module"
            case "${MODULE_RESULTS[$module]}" in
                0) echo "  状态: PASS" ;;
                1) echo "  状态: FAIL" ;;
                *) echo "  状态: SKIP" ;;
            esac
            echo ""
        done
        
        echo "=== 综合测试结束: $TEST_NAME ==="
        echo "结束时间: $(date)"
    } | tee "$RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.log"
    
    # 生成JSON格式的综合测试报告
    local passed_count=0
    local failed_count=0
    local skipped_count=0
    
    for module in "${TEST_MODULES[@]}"; do
        case "${MODULE_RESULTS[$module]}" in
            0) passed_count=$((passed_count + 1)) ;;
            1) failed_count=$((failed_count + 1)) ;;
            *) skipped_count=$((skipped_count + 1)) ;;
        esac
    done
    
    cat > "$RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.json" << EOF
{
    "test_name": "$TEST_NAME",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": 0,
    "summary": {
        "total": ${#TEST_MODULES[@]},
        "passed": $passed_count,
        "failed": $failed_count,
        "skipped": $skipped_count,
        "success_rate": $((passed_count * 100 / ${#TEST_MODULES[@]}))
    },
    "modules": {
$(for module in "${TEST_MODULES[@]}"; do
    local status
    case "${MODULE_RESULTS[$module]}" in
        0) status="PASS" ;;
        1) status="FAIL" ;;
        *) status="SKIP" ;;
    esac
    echo "        \"$module\": \"$status\""
done | sed '$s/,$//')
    }
}
EOF
    
    # 显示综合测试结果
    show_test_results
    
    # 返回测试结果
    if [[ "$overall_success" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

# 如果直接运行此脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 