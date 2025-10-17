#!/bin/bash

# 脚本名称：datakit_install.sh
# 作用：下载并执行安装脚本，同时传递环境变量

# 接收传入参数
code="$1"
env="$2"
ops_env="$3"
system="$4"

# 打印日志
echo "========= 参数接收开始 ========="
echo "Code: $code"
echo "Environment: $env"
echo "Ops Environment: $ops_env"
echo "System: $system"
echo "========= 参数接收结束 ========="


# 设置环境变量
export ACCOUNT_NAME="$code"
export GLOBAL_ENV="$env"
export GLOBAL_OPS_ENV="$ops_env"
export GLOBAL_SYSTEM="$system"

echo "已设置以下环境变量："
echo "ACCOUNT_NAME=$ACCOUNT_NAME"
echo "GLOBAL_ENV=$GLOBAL_ENV"
echo "GLOBAL_OPS_ENV=$GLOBAL_OPS_ENV"
echo "GLOBAL_SYSTEM=$GLOBAL_SYSTEM"

# 定义安装脚本 URL
INSTALL_SCRIPT_URL="https://static-api.pre-guance.houtai.io/guance/datakit/install.sh"

# 删除旧的安装脚本文件
if [[ -f install.sh ]]; then
  echo "检测到旧的 install.sh，正在删除..."
  rm -f install.sh
fi

# 下载安装脚本
echo "正在下载安装脚本：$INSTALL_SCRIPT_URL..."
wget -q "$INSTALL_SCRIPT_URL" -O install.sh

# 检查下载是否成功
if [[ $? -ne 0 ]]; then
  echo "错误: 无法下载安装脚本，请检查网络连接或 URL 是否正确。"
  exit 2
fi

echo "安装脚本下载完成。"

# 修改脚本权限
chmod +x install.sh

# 执行安装脚本
echo "正在执行安装脚本..."
./install.sh

# 检查 install.sh 是否执行成功
if [[ $? -eq 0 ]]; then
  echo "安装成功！"
else
  echo "安装失败，请检查日志了解详情。"
  exit 3
fi
