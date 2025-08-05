#!/bin/bash

#=================================================
# Datakit 状态配置文件
#=================================================
# 管理脚本运行时的状态变量
#=================================================

# 基础配置已由installer.sh加载，此处不再重复加载

# 全局状态变量
HOST_IP=""
ENV=""
WORKSPACE=""
GLOBAL_TAGS=""
WORKSPACE_TOKEN=""
DATAWAY_FULL_URL=""
CGROUP_CPU_LIMIT=""
CGROUP_MEMORY_LIMIT=""

# 脚本状态变量
SCRIPT_START_TIME=""
SCRIPT_END_TIME=""
SCRIPT_EXIT_CODE=""
SCRIPT_ERROR_MESSAGE=""
SCRIPT_CURRENT_STEP=""
SCRIPT_BACKUP_CREATED="false"
SCRIPT_LOCK_ACQUIRED="false"

# 性能监控变量
PERFORMANCE_DOWNLOAD_TIME=""
PERFORMANCE_INSTALL_TIME=""
PERFORMANCE_CONFIG_TIME=""
PERFORMANCE_TOTAL_TIME=""

# 安装状态变量
INSTALL_STATUS=""
INSTALL_ERROR=""
DATAKIT_STATUS=""
NODE_EXPORTER_STATUS=""

# 初始化状态
init_state() {
    SCRIPT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SCRIPT_CURRENT_STEP="初始化"
    SCRIPT_EXIT_CODE=""
    SCRIPT_ERROR_MESSAGE=""
    SCRIPT_BACKUP_CREATED="false"
    SCRIPT_LOCK_ACQUIRED="false"
}

# 更新当前步骤
update_current_step() {
    SCRIPT_CURRENT_STEP="$1"
}

# 记录性能指标
record_performance() {
    local metric="$1"
    local value="$2"
    
    case "$metric" in
        "download") PERFORMANCE_DOWNLOAD_TIME="$value" ;;
        "install") PERFORMANCE_INSTALL_TIME="$value" ;;
        "config") PERFORMANCE_CONFIG_TIME="$value" ;;
        "total") PERFORMANCE_TOTAL_TIME="$value" ;;
    esac
}

# 设置安装状态
set_install_status() {
    INSTALL_STATUS="$1"
    if [ -n "$2" ]; then
        INSTALL_ERROR="$2"
    fi
}

# 设置服务状态
set_service_status() {
    local service="$1"
    local status="$2"
    
    case "$service" in
        "datakit") DATAKIT_STATUS="$status" ;;
        "node_exporter") NODE_EXPORTER_STATUS="$status" ;;
    esac
}

# 完成脚本执行
finish_script() {
    SCRIPT_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SCRIPT_EXIT_CODE="${1:-0}"
    if [ -n "$2" ]; then
        SCRIPT_ERROR_MESSAGE="$2"
    fi
} 