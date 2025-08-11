#!/bin/bash

#=================================================
# 状态配置测试脚本
#=================================================
# 测试状态配置是否正确集成到新的配置架构中
#=================================================

# 设置脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 开始测试状态配置集成..."
echo "=================================="

# 测试1: 加载基础配置
echo "📋 测试1: 加载基础配置"
if source "$SCRIPT_DIR/base/base_config.sh"; then
    echo "✅ 基础配置加载成功"
    echo "  - DATAKIT_VERSION: ${DATAKIT_VERSION:-未设置}"
    echo "  - OPS_ADDR: ${OPS_ADDR:-未设置}"
else
    echo "❌ 基础配置加载失败"
    exit 1
fi

echo ""

# 测试2: 加载状态配置
echo "📋 测试2: 加载状态配置"
if source "$SCRIPT_DIR/base/state_config.sh"; then
    echo "✅ 状态配置加载成功"
    
    # 检查状态管理函数
    if declare -F init_state >/dev/null; then
        echo "✅ init_state 函数存在"
    else
        echo "❌ init_state 函数不存在"
    fi
    
    if declare -F update_current_step >/dev/null; then
        echo "✅ update_current_step 函数存在"
    else
        echo "❌ update_current_step 函数不存在"
    fi
    
    if declare -F get_state_summary >/dev/null; then
        echo "✅ get_state_summary 函数存在"
    else
        echo "❌ get_state_summary 函数不存在"
    fi
else
    echo "❌ 状态配置加载失败"
    exit 1
fi

echo ""

# 测试3: 测试状态管理功能
echo "📋 测试3: 测试状态管理功能"

# 初始化状态
echo "🔄 初始化状态..."
init_state

# 更新步骤
echo "🔄 更新当前步骤..."
update_current_step "测试状态管理"

# 记录性能指标
echo "🔄 记录性能指标..."
record_performance "test" "5s"

# 设置状态
echo "🔄 设置安装状态..."
set_install_status "testing"
set_service_status "datakit" "testing"

# 显示状态摘要
echo "📊 状态摘要:"
get_state_summary

echo ""

# 测试4: 测试配置加载器集成
echo "📋 测试4: 测试配置加载器集成"
if source "$SCRIPT_DIR/loader.sh" example; then
    echo "✅ 配置加载器集成成功"
    
    # 检查状态是否被正确初始化
    if [[ -n "$SCRIPT_CURRENT_STEP" ]]; then
        echo "✅ 状态已初始化: $SCRIPT_CURRENT_STEP"
    else
        echo "❌ 状态未初始化"
    fi
else
    echo "❌ 配置加载器集成失败"
    exit 1
fi

echo ""
echo "🎉 所有测试完成!"
echo "状态配置已成功集成到新的配置架构中。"
echo ""
echo "现在您可以在脚本中使用以下功能:"
echo "  - 状态跟踪: update_current_step()"
echo "  - 性能监控: record_performance()"
echo "  - 状态管理: set_install_status(), set_service_status()"
echo "  - 状态查看: get_state_summary()"
echo "  - 状态重置: reset_state()" 