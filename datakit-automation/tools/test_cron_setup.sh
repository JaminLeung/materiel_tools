#!/bin/bash

#=================================================
# 定时任务设置测试脚本
#=================================================
# 功能: 测试新的定时任务设置逻辑
#=================================================

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载核心模块
source "$PROJECT_ROOT/core/logging.sh"
source "$PROJECT_ROOT/core/utils.sh"

# 测试函数：检查定时任务是否存在
test_check_cron_job_exists() {
    echo "=== 测试 check_cron_job_exists 函数 ==="
    
    # 测试不存在的任务
    if check_cron_job_exists "nonexistent_task"; then
        echo "❌ 错误：不存在的任务被检测为存在"
        return 1
    else
        echo "✅ 正确：不存在的任务被正确检测"
    fi
    
    # 添加一个测试任务
    echo "添加测试任务..."
    (crontab -l 2>/dev/null; echo "# 测试任务"; echo "*/1 * * * * echo 'test'") | crontab -
    
    # 测试存在的任务
    if check_cron_job_exists "echo 'test'"; then
        echo "✅ 正确：存在的任务被正确检测"
    else
        echo "❌ 错误：存在的任务未被检测到"
        return 1
    fi
    
    # 清理测试任务
    crontab -l 2>/dev/null | grep -v "echo 'test'" | crontab -
    echo "✅ 测试任务已清理"
}

# 测试函数：添加单个定时任务
test_add_cron_job() {
    echo "=== 测试 add_cron_job 函数 ==="
    
    local test_job_name="测试任务"
    local test_identifier="test_identifier"
    local test_cron="*/2 * * * *"
    local test_command="echo 'test_add_cron_job'"
    
    echo "第一次添加任务..."
    if add_cron_job "$test_job_name" "$test_identifier" "$test_cron" "$test_command"; then
        echo "✅ 第一次添加成功"
    else
        echo "❌ 第一次添加失败"
        return 1
    fi
    
    echo "第二次添加相同任务..."
    if add_cron_job "$test_job_name" "$test_identifier" "$test_cron" "$test_command"; then
        echo "✅ 第二次添加被正确跳过"
    else
        echo "❌ 第二次添加处理错误"
        return 1
    fi
    
    # 清理测试任务
    crontab -l 2>/dev/null | grep -v "$test_identifier" | crontab -
    echo "✅ 测试任务已清理"
}

# 测试函数：完整的setup_cron_jobs
test_setup_cron_jobs() {
    echo "=== 测试完整的 setup_cron_jobs 函数 ==="
    
    # 设置测试环境变量
    export SCENARIO_PROJECT_ROOT="$PROJECT_ROOT"
    
    # 创建测试脚本文件
    local test_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$test_scripts_dir"
    
    # 创建测试脚本
    cat > "$test_scripts_dir/config_update.sh" << 'EOF'
#!/bin/bash
echo "config_update.sh executed at $(date)"
EOF
    
    cat > "$test_scripts_dir/datakit_health_check.sh" << 'EOF'
#!/bin/bash
echo "datakit_health_check.sh executed at $(date)"
EOF
    
    cat > "$test_scripts_dir/app_init.sh" << 'EOF'
#!/bin/bash
echo "app_init.sh executed at $(date)"
EOF
    
    chmod +x "$test_scripts_dir"/*.sh
    
    echo "第一次运行 setup_cron_jobs..."
    if setup_cron_jobs; then
        echo "✅ 第一次运行成功"
    else
        echo "❌ 第一次运行失败"
        return 1
    fi
    
    echo "第二次运行 setup_cron_jobs..."
    if setup_cron_jobs; then
        echo "✅ 第二次运行成功（应该跳过已存在的任务）"
    else
        echo "❌ 第二次运行失败"
        return 1
    fi
    
    # 显示当前crontab
    echo "当前crontab内容："
    crontab -l 2>/dev/null || echo "无crontab"
    
    # 清理测试任务
    echo "清理测试任务..."
    crontab -l 2>/dev/null | grep -v "config_update.sh\|datakit_health_check.sh\|app_init.sh" | crontab -
    
    # 清理测试脚本
    rm -f "$test_scripts_dir"/{config_update,datakit_health_check,app_init}.sh
    echo "✅ 测试完成"
}

# 主测试函数
main() {
    echo "开始定时任务设置逻辑测试..."
    echo "项目根目录: $PROJECT_ROOT"
    echo ""
    
    # 备份当前crontab
    local backup_file="/tmp/crontab_backup_$(date +%Y%m%d%H%M%S)"
    crontab -l 2>/dev/null > "$backup_file" || true
    echo "当前crontab已备份到: $backup_file"
    echo ""
    
    # 运行测试
    local test_results=()
    
    if test_check_cron_job_exists; then
        test_results+=("check_cron_job_exists: ✅")
    else
        test_results+=("check_cron_job_exists: ❌")
    fi
    
    if test_add_cron_job; then
        test_results+=("add_cron_job: ✅")
    else
        test_results+=("add_cron_job: ❌")
    fi
    
    if test_setup_cron_jobs; then
        test_results+=("setup_cron_jobs: ✅")
    else
        test_results+=("setup_cron_jobs: ❌")
    fi
    
    # 恢复crontab
    echo ""
    echo "恢复原始crontab..."
    if [ -s "$backup_file" ]; then
        crontab "$backup_file"
        echo "✅ crontab已恢复"
    else
        crontab -r 2>/dev/null || true
        echo "✅ crontab已清空"
    fi
    rm -f "$backup_file"
    
    # 显示测试结果
    echo ""
    echo "=== 测试结果 ==="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    
    # 检查是否有失败的测试
    if [[ "${test_results[*]}" =~ ❌ ]]; then
        echo ""
        echo "❌ 部分测试失败"
        exit 1
    else
        echo ""
        echo "✅ 所有测试通过"
        exit 0
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 