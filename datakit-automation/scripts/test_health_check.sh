#!/bin/bash

# Datakit健康检查测试脚本

set -euo pipefail

echo "=== Datakit健康检查测试 ==="
echo ""

# 1. 测试脚本基本功能
echo "1. 测试脚本基本功能..."
./datakit_health_check.sh >/dev/null 2>&1 && echo "✅ 基本功能正常" || echo "❌ 基本功能异常"

# 2. 测试单次健康检查
echo ""
echo "2. 测试单次健康检查..."
./datakit_health_check.sh check >/dev/null 2>&1 && echo "✅ 单次检查正常" || echo "❌ 单次检查异常"

# 3. 测试状态检查
echo ""
echo "3. 测试状态检查..."
./datakit_health_check.sh status >/dev/null 2>&1 && echo "✅ 状态检查正常" || echo "❌ 状态检查异常"

# 4. 检查定时任务
echo ""
echo "4. 检查定时任务..."
if crontab -l 2>/dev/null | grep -q "datakit_health_check.sh"; then
    echo "✅ 定时任务已安装"
    crontab -l | grep "datakit_health_check.sh"
else
    echo "❌ 定时任务未安装"
fi

# 5. 检查日志文件
echo ""
echo "5. 检查日志文件..."
if [ -f "/var/log/datakit_health_check.log" ]; then
    echo "✅ 日志文件存在"
    echo "日志文件大小: $(du -h /var/log/datakit_health_check.log | cut -f1)"
else
    echo "❌ 日志文件不存在"
fi

# 6. 检查Datakit服务状态
echo ""
echo "6. 检查Datakit服务状态..."
if pgrep -x "datakit" >/dev/null; then
    echo "✅ Datakit进程正在运行"
else
    echo "❌ Datakit进程未运行"
fi

# 7. 检查Datakit端口
echo ""
echo "7. 检查Datakit端口..."
if netstat -tlnp 2>/dev/null | grep -q ":9529 " || ss -tlnp 2>/dev/null | grep -q ":9529 "; then
    echo "✅ Datakit端口9529正在监听"
else
    echo "❌ Datakit端口9529未监听"
fi

# 8. 测试Datakit ping接口
echo ""
echo "8. 测试Datakit ping接口..."
if curl -s -m 5 "http://localhost:9529/v1/ping" >/dev/null 2>&1; then
    echo "✅ Datakit ping接口正常"
else
    echo "❌ Datakit ping接口异常"
fi

echo ""
echo "=== 测试完成 ===" 