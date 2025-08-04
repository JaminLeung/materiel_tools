#!/bin/bash

# 备用下载脚本 - 使用公共源
echo "=== 备用下载脚本 ==="

# 加载配置
source ./config/env/benjamin.sh

echo "使用公共源下载 Datakit..."

# 创建下载目录
mkdir -p "$DATAKIT_INSTALL_DIR"
cd "$DATAKIT_INSTALL_DIR"

# 下载Datakit
echo "下载 Datakit v$DATAKIT_VERSION..."
wget -O "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz" \
     "https://static.guance.com/datakit/datakit-$DATAKIT_VERSION-linux-amd64.tar.gz"

if [ $? -eq 0 ]; then
    echo "✅ Datakit 下载成功"
    
    # 验证文件
    if [ -f "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz" ]; then
        file_size=$(stat -c%s "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz")
        echo "文件大小: ${file_size} bytes"
        
        # 解压测试
        echo "测试解压..."
        tar -tzf "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz" | head -5
    fi
else
    echo "❌ Datakit 下载失败"
    exit 1
fi

echo "✅ 备用下载完成" 