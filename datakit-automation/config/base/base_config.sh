#!/bin/bash

#=================================================
# Datakit 基础配置文件
#=================================================
# 包含脚本元信息和基础路径配置
#=================================================

# 脚本元信息
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="0.1.1"

# 基础路径配置
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly MODULES_DIR="$PROJECT_ROOT/modules"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly SCENARIO_DIR="$PROJECT_ROOT/scenario"

# 日志配置
readonly LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-1}"

# 安装路径配置
readonly DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"
readonly DATAKIT_BIN_DIR="/usr/local/bin"
readonly DATAKIT_CONFIG_DIR="/usr/local/datakit/conf.d"
readonly DATAKIT_DATA_DIR="/usr/local/datakit/data"
readonly DATAKIT_LOG_DIR="/var/log/datakit"

# 外部脚本配置
readonly CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}" 