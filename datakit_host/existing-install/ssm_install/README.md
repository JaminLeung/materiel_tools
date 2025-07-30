# Datakit SSM安装脚本

## 概述

`main_install.sh` 是一个自动化安装Datakit的Bash脚本，通过AWS SSM Agent向目标主机发送安装任务。该脚本支持自动安装AWS CLI、下载Datakit物料、安装Node Exporter和Datakit，并配置各种采集器。

## 主要功能

### 1. 使用curl下载S3物料
- 直接使用curl从S3下载物料文件
- 支持私有S3 bucket（AWS签名v4认证）
- 无需安装AWS CLI，减少依赖
- 自动验证下载文件完整性

### 2. 智能物料下载
- 优先下载已打包的bundle文件 (`datakit_bundle-*.tar.gz`)
- 验证MD5文件完整性
- 自动解压并重命名文件
- 下载必要的工具文件 (jq, yj, aws-cli)

### 3. 资源限制策略
- 根据机器规格动态设置Cgroup资源限制
- 支持CPU和内存限制配置
- 自动适配不同规格的机器

### 4. 完整的安装流程
- 安装Node Exporter (端口9100)
- 安装Datakit (端口9529)
- 配置各种采集器
- 设置定时任务

## 安装流程

### 关键步骤

1. **获取业务主机信息**
   - 获取本机IP地址
   - 从运维平台获取配置信息
   - 构建Dataway URL

2. **检查安装状态**
   - 检查Datakit进程
   - 检查端口占用情况
   - 检查配置文件

3. **配置AWS凭证**
   - 配置AWS凭证（如果AWS CLI可用）
   - 支持预签名URL生成

4. **物料准备**
   - 下载bundle文件
   - 验证MD5完整性
   - 解压并准备安装文件

5. **执行安装流程**
   - 安装Node Exporter
   - 安装Datakit
   - 配置采集器
   - 重启服务

6. **设置定时任务**
   - 日志清理任务
   - 健康检查任务

## 配置的采集器

### 1. Prometheus采集器
- 采集Node Exporter指标
- 支持etcd相关指标
- 自动选举功能

### 2. OpenTelemetry采集器
- HTTP和gRPC支持
- 支持Trace、Metric、Logs
- 默认端口4317

### 3. 日志采集器
- 系统日志采集
- 支持多文件监控
- 自动多行检测

### 4. Pushgateway采集器
- 支持Prometheus Pushgateway
- 自定义路由前缀

## 使用方法

### 通过SSM执行

```bash
# 使用AWS CLI通过SSM执行
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s https://your-script-url/main_install.sh | bash"]'

# 或直接上传脚本到目标主机
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["bash /path/to/main_install.sh"]'
```

### 直接使用curl下载

```bash
# 直接执行安装脚本（使用curl下载S3物料）
curl -s https://your-script-url/main_install.sh | bash

# 或直接运行
./main_install.sh
```

## 配置要求

### 系统要求
- Linux x86_64系统
- curl, unzip, tar, netstat等基础工具
- 足够的磁盘空间和内存

### S3配置要求
- 支持私有S3 bucket（需要AWS凭证）
- 配置正确的AWS Access Key和Secret Key
- S3 bucket需要适当的读取权限
- SSM执行权限 (ssm:SendCommand)

### 网络要求
- 访问AWS S3的权限
- 访问Dataway的权限
- 访问运维平台API的权限

## 日志和监控

### 本地日志
- 日志文件: `/var/log/datakit_install.log`
- 包含详细的安装过程记录
- 支持彩色输出

### Dataway上报
- 自动上报安装状态到Dataway
- 包含主机信息和环境标签
- 支持错误和成功状态上报

### 定时任务
- 日志清理: 每天00:00清理7天前的日志
- 健康检查: 每5分钟检查Datakit状态

## 错误处理

### 常见错误
1. **S3下载失败**
   - 检查AWS凭证是否正确配置
   - 验证S3 bucket权限
   - 检查网络连接
   - 检查文件路径是否正确

2. **Bundle下载失败**
   - 检查S3权限
   - 验证bundle文件存在
   - 检查网络连接

3. **MD5验证失败**
   - 重新下载文件
   - 检查网络稳定性
   - 验证文件完整性

### 故障排除
- 查看详细日志: `tail -f /var/log/datakit_install.log`
- 检查服务状态: `systemctl status datakit`
- 验证端口监听: `netstat -tlnp | grep -E ':(9529|9100)'`

## 依赖文件

### 必需文件
- `main_install.sh` - 主安装脚本

### 配置文件
- `/usr/lib/zabbix/externalscripts/config.py` - 运维平台配置

### 临时文件
- `/tmp/datakit_install_*` - 安装临时目录

## 注意事项

1. **权限要求**: 脚本需要root权限执行
2. **网络依赖**: 需要访问AWS S3和Dataway
3. **资源限制**: 根据机器规格自动设置资源限制
4. **服务冲突**: 检查端口9529和9100是否被占用
5. **配置文件**: 确保运维平台配置文件存在且有效

## 更新日志

### v1.0.0
- 初始版本发布
- 支持基本的Datakit安装功能

### v1.1.0
- 改用curl直接下载S3物料
- 支持私有S3 bucket（AWS签名v4认证）
- 移除AWS CLI依赖
- 优化bundle文件下载逻辑
- 增强错误处理和日志记录

### v1.1.1
- 修复AWS签名v4中缺少x-amz-content-sha256头部的问题
- 完善S3请求签名算法
- 增强错误检测和响应处理

### v1.1.2
- 修复AWS签名v4中credential_scope使用错误时间戳的问题
- 修正签名密钥生成逻辑
- 添加详细调试脚本用于问题排查 