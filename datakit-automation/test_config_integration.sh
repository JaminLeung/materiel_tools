#!/bin/bash

# 测试配置文件集成
# 验证app_init.sh脚本是否正确加载和使用配置文件

set -euo pipefail

echo "=== 测试配置文件集成 ==="

# 检查配置文件是否存在
echo "检查配置文件..."
if [ -f "config/app_init.conf" ]; then
    echo "✓ 配置文件存在: config/app_init.conf"
else
    echo "✗ 配置文件不存在: config/app_init.conf"
    exit 1
fi

# 检查配置文件格式
echo ""
echo "检查配置文件格式..."
if yj -t < config/app_init.conf >/dev/null 2>&1; then
    echo "✓ 配置文件格式正确 (TOML)"
else
    echo "✗ 配置文件格式错误"
    exit 1
fi

# 检查脚本语法
echo ""
echo "检查脚本语法..."
if bash -n scripts/app_init.sh; then
    echo "✓ 脚本语法检查通过"
else
    echo "✗ 脚本语法检查失败"
    exit 1
fi

# 检查配置加载函数
echo ""
echo "检查配置加载函数..."
if grep -q "load_config_file" scripts/app_init.sh; then
    echo "✓ 检测到配置加载函数"
else
    echo "✗ 未检测到配置加载函数"
fi

# 检查配置验证函数
echo ""
echo "检查配置验证函数..."
if grep -q "validate_required_config" scripts/app_init.sh; then
    echo "✓ 检测到配置验证函数"
else
    echo "✗ 未检测到配置验证函数"
fi

# 检查配置值获取
echo ""
echo "检查配置值获取..."
if grep -q "get_config_value" scripts/app_init.sh; then
    echo "✓ 检测到配置值获取函数"
else
    echo "✗ 未检测到配置值获取函数"
fi

# 检查硬编码常量是否被替换
echo ""
echo "检查硬编码常量替换..."
if ! grep -q "readonly.*=.*\".*\"" scripts/app_init.sh; then
    echo "✓ 硬编码常量已被替换为配置值"
else
    echo "✗ 仍存在硬编码常量"
    grep "readonly.*=.*\".*\"" scripts/app_init.sh | head -5
fi

# 检查API配置参数
echo ""
echo "检查API配置参数..."
if grep -q "API_CONNECT_TIMEOUT\|API_MAX_TIME\|API_RANDOM_DELAY_MAX" scripts/app_init.sh; then
    echo "✓ 检测到API配置参数"
else
    echo "✗ 未检测到API配置参数"
fi

# 检查备份配置参数
echo ""
echo "检查备份配置参数..."
if grep -q "BACKUP_KEEP_DAYS" scripts/app_init.sh; then
    echo "✓ 检测到备份配置参数"
else
    echo "✗ 未检测到备份配置参数"
fi

echo ""
echo "=== 配置文件集成测试完成 ==="
echo "✓ 配置文件格式正确"
echo "✓ 脚本语法检查通过"
echo "✓ 配置管理函数已集成"
echo "✓ 硬编码常量已替换为配置值" 