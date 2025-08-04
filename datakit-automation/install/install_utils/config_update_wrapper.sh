#!/bin/bash

# config_update.sh 包装脚本 - 带锁检查功能
# 每15分钟执行一次，检查上一个任务是否执行完

SCRIPT_PATH="$1"
LOCK_FILE="/var/run/config_update.lock"
LOG_FILE="/var/log/datakit/config_update.log"

# 清空日志文件，只保留最新内容
> "$LOG_FILE"

# 记录执行开始
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始执行config_update.sh" > "$LOG_FILE"

# 检查锁文件
if [ -f "$LOCK_FILE" ]; then
    # 读取锁文件中的PID
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    
    # 检查进程是否还在运行
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 上一个任务(PID: $pid)还在运行，跳过本次执行" >> "$LOG_FILE"
        exit 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 发现僵尸锁文件，清理并继续执行" >> "$LOG_FILE"
        rm -f "$LOCK_FILE"
    fi
fi

# 创建锁文件
echo $$ > "$LOCK_FILE"

# 执行实际脚本
if [ -f "$SCRIPT_PATH" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 执行脚本: $SCRIPT_PATH" >> "$LOG_FILE"
    if "$SCRIPT_PATH" >> "$LOG_FILE" 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 脚本执行成功" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 脚本执行失败" >> "$LOG_FILE"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 脚本文件不存在: $SCRIPT_PATH" >> "$LOG_FILE"
fi

# 清理锁文件
rm -f "$LOCK_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 执行完成" >> "$LOG_FILE" 