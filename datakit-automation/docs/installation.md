# Datakit 安装指南

## 📋 安装前准备

### 1. 系统要求
- Linux 系统 (CentOS 7+, Ubuntu 18+, Debian 9+)
- 至少 100MB 可用磁盘空间
- 至少 512MB 可用内存
- 网络连接 (用于下载和配置)

### 2. 必需软件
- `curl` - 用于下载文件
- `jq` - 用于解析JSON
- `systemctl` - 用于服务管理
- `bash` 4.0+ - 脚本执行环境

### 3. 权限要求
- 建议使用 `root` 用户运行
- 需要写入 `/usr/local/bin` 和 `/var/log` 目录的权限

## 🚀 快速安装

### 方式1: 环境变量配置 (推荐)

```bash
# 1. 设置环境变量
export DATAKIT_VERSION=2.8.0
export S3_BUCKET=your-bucket-name
export S3_ACCESS_KEY=your-access-key
export S3_SECRET_KEY=your-secret-key
export DATAWAY_URL=https://dataway.example.com
export OPS_ADDR=http://ops.example.com:5000

# 2. 执行安装
./installer.sh existing-install
```

### 方式2: 配置文件

```bash
# 1. 复制配置示例
cp config/env/example.sh config/env/my-config.sh

# 2. 编辑配置文件
vim config/env/my-config.sh

# 3. 执行安装
./installer.sh --config config/env/my-config.sh existing-install
```

## 📦 安装场景

### 1. 存量安装 (existing-install)
适用于已运行但未安装Datakit的主机

```bash
./installer.sh existing-install
```

**执行步骤:**
- 检查系统环境
- 下载Datakit包
- 安装Datakit
- 配置Datakit
- 启动服务
- 健康检查

### 2. 增量安装 (incremental-install)
适用于初始化创建镜像的主机

```bash
./installer.sh incremental-install
```

**执行步骤:**
- 系统初始化
- 安装基础依赖
- 下载并安装Datakit
- 配置系统服务
- 验证安装

### 3. 版本升级 (version-upgrade)
升级Datakit到新版本

```bash
./installer.sh version-upgrade
```

**执行步骤:**
- 备份当前版本
- 下载新版本
- 停止旧服务
- 安装新版本
- 启动新服务
- 验证升级

### 4. 配置更新 (config-update)
仅更新配置文件

```bash
./installer.sh config-update
```

**执行步骤:**
- 备份当前配置
- 更新配置文件
- 重启服务
- 验证配置

### 5. 重装 (reinstall)
完全重新安装Datakit

```bash
./installer.sh reinstall
```

**执行步骤:**
- 停止服务
- 卸载旧版本
- 清理文件
- 重新安装
- 配置服务
- 启动验证

## 🔧 配置说明

### 环境变量

| 变量名 | 必需 | 说明 | 示例 |
|--------|------|------|------|
| `DATAKIT_VERSION` | ✅ | Datakit版本 | `2.8.0` |
| `S3_BUCKET` | ✅ | S3存储桶名称 | `my-bucket` |
| `S3_ACCESS_KEY` | ✅ | S3访问密钥 | `AKIA...` |
| `S3_SECRET_KEY` | ✅ | S3秘密密钥 | `secret...` |
| `DATAWAY_URL` | ✅ | Dataway地址 | `https://dataway.example.com` |
| `OPS_ADDR` | ✅ | 运维平台地址 | `http://ops.example.com:5000` |
| `OPS_TOKEN` | ❌ | 运维平台令牌 | `token...` |
| `LOG_LEVEL` | ❌ | 日志级别 | `1` |

### 配置文件

配置文件支持以下环境:
- `config/env/production.sh` - 生产环境
- `config/env/development.sh` - 开发环境
- `config/env/example.sh` - 配置示例

## 🛠️ 故障排除

### 常见问题

1. **权限不足**
   ```bash
   sudo ./installer.sh existing-install
   ```

2. **网络连接失败**
   ```bash
   # 检查网络连接
   curl -I https://s3.ap-southeast-1.amazonaws.com
   ```

3. **配置验证失败**
   ```bash
   # 测试配置
   ./config/tests/test_config.sh
   ```

4. **服务启动失败**
   ```bash
   # 检查服务状态
   systemctl status datakit
   
   # 查看日志
   journalctl -u datakit -f
   ```

### 日志文件

- 安装日志: `/var/log/datakit_install.log`
- Datakit日志: `/var/log/datakit/datakit.log`
- 系统日志: `journalctl -u datakit`

## 📞 技术支持

如遇到问题，请提供以下信息:
1. 操作系统版本
2. 错误日志
3. 配置文件内容
4. 执行命令 
