# Datakit 自动化安装工具使用指南

## 概述

Datakit自动化安装工具，支持一键安装、配置同步、健康监控和物料管理。

**主要功能：**
- 自动化安装和配置
- 配置同步和热更新
- 健康检查和故障自愈
- Mock测试环境
- 物料包下载工具

## 快速导航

- [快速开始](#快速开始---existing-installation-流程)
- [环境准备](#1-环境准备)
- [物料下载](#83-下载物料包推荐)
- [Mock服务器](#82-启动-mock-服务器测试环境)
- [故障排查](#mock模块故障排查)

## 快速开始 - Existing Installation 流程

### 1. 环境准备

```bash
# 克隆项目
git clone <repository_url>
cd datakit-automation

# 确保脚本可执行
chmod +x installer.sh
chmod +x scripts/*.sh
chmod +x install/install_steps/*.sh

# 安装Python依赖（用于Mock模块）
cd test/mocks
pip install -r requirements.txt
```
```
```
### 2. Mock模块和业务配置同步

#### 2.1 Python依赖安装
```bash
# 进入mock模块目录
cd test/mocks

# 安装Python依赖
pip install -r requirements.txt

# 验证依赖安装
python3 -c "import flask, boto3, requests; print('依赖安装成功')"
```

#### 2.2 启动 Mock 服务器（测试环境）
```bash
# 启动 Mock OPS 服务器
cd test/mocks
python3 mock_ops_server.py &

# 验证服务器启动
curl http://localhost:5000/health
```

#### 2.3 下载物料包

```bash
# 基本下载
python3 test/mocks/download_materials.py
--s3-access-key "your_access_key"
--s3-secret-key "your_secret_key"

# 指定目录
python3 test/mocks/download_materials.py 
--s3-access-key "your_access_key"
--s3-secret-key "your_secret_key"
--download-dir /opt/datakit_install


# 查看帮助
python3 test/mocks/download_materials.py --help
```



### 3. 配置文件设置

#### 3.1 复制并修改配置文件
```bash
# 复制示例配置
cp config/env/example.sh config/env/my_env.sh

# 编辑配置文件
vim config/env/my_env.sh
```

#### 3.2 关键配置项
```bash
# 基础配置
readonly ENV_NAME="my_env"
readonly ENV_TYPE="production"

# S3 配置
readonly S3_ACCESS_KEY="your_access_key"
readonly S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
readonly S3_REGION="ap-southeast-1"
readonly S3_BUCKET="your-bucket-name"

# Datakit 配置
readonly DATAKIT_VERSION="1.5.0"
readonly DATAKIT_TOKEN="your_datakit_token"
readonly DATAWAY_URL="https://openway.guance.com?token=your_token"
```

### 4. 执行安装

#### 4.1 使用配置文件运行
```bash
# 方式1：指定配置文件
./installer.sh --config my_env.sh existing-install

# 方式2：指定完整路径
./installer.sh --config config/env/my_env.sh  existing-install
```

#### 4.2 安装流程
安装过程会自动执行以下步骤：
1. 环境检查
2. 下载 Datakit 安装包
3. 安装 Datakit 组件
4. 配置 Datakit
5. 设置定时任务
6. 启动服务

### 5. 验证安装

#### 5.1 检查服务状态
```bash
# 检查 Datakit 进程
ps aux | grep datakit

# 检查服务状态
systemctl status datakit

# 检查端口监听
netstat -tlnp | grep 9529
```

#### 5.2 检查配置文件
```bash
# 主配置文件
cat /usr/local/datakit/conf.d/datakit.conf

# 检查配置目录
ls -la /usr/local/datakit/conf.d/
```

### 6. 查看日志

#### 6.1 安装日志
```bash
# 安装过程日志
tail -f /opt/datakit/install.log

# 查看完整日志
cat /opt/datakit/install.log
```

#### 6.2 Datakit 运行日志
```bash
# Datakit 日志
tail -f /var/log/datakit/datakit.log

#### 6.2 定时任务备份配置文件
cd /opt/datakit/backup

# 系统日志
journalctl -u datakit -f
```

### 7. 定时任务管理

#### 7.1 查看定时任务
```bash
# 查看当前用户的定时任务
crontab -l

# 查看系统定时任务
sudo crontab -l
```

#### 7.2 定时任务说明
- **配置更新任务**: 每15分钟执行一次配置同步
- **健康检查任务**: 每5分钟执行一次健康检查
- **业务配置同步任务**: 每10分钟执行一次业务配置同步

#### 6.3 手动执行定时任务
```bash
# 手动执行配置更新
/opt/datakit/scripts/config_update.sh

# 手动执行健康检查
/opt/datakit/scripts/datakit_health_check.sh

# 手动执行业务配置同步
/opt/datakit/scripts/app_init.sh
```

### 8. 故障排查

#### 8.1 常见问题
```bash
# 检查 Datakit 是否正常运行
curl http://localhost:9529/v1/ping

# 检查配置文件语法
datakit --check-config

# 查看错误日志
tail -f /var/log/datakit/datakit.log | grep ERROR
```

#### 8.2 重启服务
```bash
# 重启 Datakit
sudo /usr/bin/systemctl restart datakit.service

# 重新加载配置
datakit service -R
```


```

### 9. 卸载（如需要）

```bash
# 停止服务
sudo /usr/bin/systemctl stop datakit.service

# 删除定时任务
crontab -r

# 删除安装文件
rm -rf /usr/local/datakit
rm -rf /opt/datakit
```

## 注意事项

1. **权限要求**: 安装过程需要 root 权限
2. **网络要求**: 确保能访问 S3 存储和 Dataway
3. **依赖检查**: 确保系统已安装 `jq`, `yj`, `curl` 等工具
4. **Python依赖**: Mock模块需要Python 3.7+和相应的第三方库
5. **配置文件**: 修改配置文件后需要重新运行安装命令
6. **日志监控**: 建议定期检查日志文件大小和内容
7. **物料包**: 确保S3存储桶中有对应的Datakit物料包文件
8. **📦 物料下载**: 建议使用download_materials.py工具进行物料包管理

## 支持

如遇到问题，请检查：
1. 配置文件是否正确
2. 网络连接是否正常
3. 系统依赖是否完整
4. 日志文件中的错误信息
5. Python依赖是否正确安装
6. Mock服务器是否正常运行
7. S3存储桶和物料包是否存在

### Mock模块故障排查

#### Python依赖问题
```bash
# 检查Python版本
python3 --version

# 检查依赖安装
pip list | grep -E "(flask|boto3|requests)"

# 重新安装依赖
pip install -r test/mocks/requirements.txt --force-reinstall
```

#### Mock服务器问题
```bash
# 检查服务器状态
curl http://localhost:5000/health

# 查看服务器日志
ps aux | grep mock_ops_server

# 重启服务器
pkill -f mock_ops_server
cd test/mocks && python3 mock_ops_server.py &
```

#### 物料下载问题
```bash
# 检查S3连接
python3 test/mocks/download_materials.py --list-only

# 使用AKSK检查S3连接
python3 test/mocks/download_materials.py --aksk "your_access_key:your_secret_key" --list-only

# 查看下载日志
python3 test/mocks/download_materials.py --verbose

# 使用AKSK查看详细日志
python3 test/mocks/download_materials.py --aksk "your_access_key:your_secret_key" --verbose
```

## Mock模块详细说明

### 功能概述

Mock模块提供：
1. **Mock API服务器**: 模拟运维平台接口
2. **物料包下载工具**: 从S3下载Datakit安装包
3. **测试环境支持**: 开发和测试支持

### 文件结构

```
test/mocks/
├── download_materials.py      # 物料包下载工具
├── mock_ops_server.py         # Mock API服务器
├── requirements.txt           # Python依赖列表
└── mock_config.sh            # Mock配置脚本
```

### 使用场景

1. **🚀 离线部署**: 预先下载物料包，支持离线环境安装
2. **📦 物料管理**: 智能下载和管理Datakit安装包
3. **🧪 开发测试**: 在没有真实运维平台的环境中进行开发
4. **🔧 集成测试**: 测试配置同步和更新功能
5. **📊 演示环境**: 快速搭建演示环境
6. **🔄 批量部署**: 支持多台服务器的批量物料准备

### 配置说明

#### Mock服务器配置
- **端口**: 默认5000
- **接口**: `/api/v2/cmdb/observation-agent`, `/api/v2/cmdb/observation-metadata`
- **数据**: 模拟的服务器配置和元数据

#### 物料下载配置
- **S3存储桶**: benjamin--test
- **区域**: ap-southeast-1
- **文件**: datakit_bundle-linux-amd64-{version}.tar.gz
- **验证**: MD5校验确保文件完整性 