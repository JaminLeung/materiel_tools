#!/bin/bash

# 通用定时任务包装脚本
# 功能：确保定时任务不会重复执行，支持多种任务类型
# 用法：./cron_wrapper.sh <task_type> <script_path>

TASK_TYPE="$1"
SCRIPT_PATH="$2"

# 根据任务类型设置配置
case "$TASK_TYPE" in
    "config_update")
        LOCK_FILE="/var/run/config_update.lock"
        LOG_FILE="/var/log/datakit/config_update.log"
        TASK_NAME="config_update.sh"
        ;;
    "health_check")
        LOCK_FILE="/var/run/datakit_health_check.lock"
        LOG_FILE="/var/log/datakit/health_check.log"
        TASK_NAME="datakit_health_check.sh"
        ;;
    "app_init")
        LOCK_FILE="/var/run/app_init.lock"
        LOG_FILE="/var/log/datakit/app_init.log"
        TASK_NAME="app_init.sh"
        ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 错误：未知的任务类型: $TASK_TYPE" >&2
        echo "支持的任务类型: config_update, health_check, app_init" >&2
        exit 1
        ;;
esac

# 检查脚本路径参数
if [ -z "$SCRIPT_PATH" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 错误：缺少脚本路径参数" >&2
    exit 1
fi

# 清空日志文件，只保留最新内容
> "$LOG_FILE"

# 记录执行开始
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始执行$TASK_NAME" > "$LOG_FILE"

# 检查锁文件
if [ -f "$LOCK_FILE" ]; then
    # 读取锁文件中的PID
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    
    # 检查进程是否还在运行
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 上一个$TASK_NAME任务(PID: $pid)还在运行，跳过本次执行" >> "$LOG_FILE"
        exit 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 发现僵尸锁文件，清理并继续执行" >> "$LOG_FILE"
        rm -f "$LOCK_FILE"
    fi
fi

# 执行实际脚本（脚本内部会处理锁机制）
if [ -f "$SCRIPT_PATH" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 执行脚本: $SCRIPT_PATH" >> "$LOG_FILE"
    if bash "$SCRIPT_PATH" >> "$LOG_FILE" 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $TASK_NAME执行成功" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $TASK_NAME执行失败" >> "$LOG_FILE"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 脚本文件不存在: $SCRIPT_PATH" >> "$LOG_FILE"
    exit 1
fi

# 记录执行结束
echo "$(date '+%Y-%m-%d %H:%M:%S') - $TASK_NAME执行完成" >> "$LOG_FILE" 