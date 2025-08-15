#!/bin/bash

#=================================================
# 错误处理模块测试运行器
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 测试结果目录
RESULTS_DIR="$SCRIPT_DIR/results/test_reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
TEST_NAME="error_handler"

# 创建结果目录
mkdir -p "$RESULTS_DIR"

# 运行测试并捕获输出
echo "开始运行 错误处理模块测试..."
echo "测试时间: $(date)"
echo "结果目录: $RESULTS_DIR"
echo ""

# 运行测试并记录输出
{
    echo "=== 测试开始: $TEST_NAME ==="
    echo "开始时间: $(date)"
    echo ""
    
    # 运行测试脚本
    bash "$SCRIPT_DIR/test_error_handler.sh" 2>&1
    
    echo ""
    echo "=== 测试结束: $TEST_NAME ==="
    echo "结束时间: $(date)"
} | tee "$RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.log"

# 获取测试退出码
TEST_EXIT_CODE=${PIPESTATUS[1]}

# 生成JSON格式的测试报告
cat > "$RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.json" << EOF
{
    "test_name": "$TEST_NAME",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": 0,
    "summary": {
        "total": 0,
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "success_rate": 0
    }
}
EOF

# 显示测试结果
echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
echo "测试名称: $TEST_NAME"
echo "测试时间: $TIMESTAMP"
echo "日志文件: $RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.log"
echo "报告文件: $RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.json"

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "\033[0;32m🎉 所有测试通过！\033[0m"
else
    echo -e "\033[0;31m⚠️  有测试失败，请查看日志文件\033[0m"
fi

echo ""
echo "查看详细结果:"
echo "cat $RESULTS_DIR/${TEST_NAME}_${TIMESTAMP}.log"

exit $TEST_EXIT_CODE 