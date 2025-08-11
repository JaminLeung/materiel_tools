# Datakit 自动化安装工具

## 📁 目录结构

```
datakit-automation/
├── README.md                    # 项目说明文档
├── installer.sh                 # 主入口脚本 (重命名)
├── config/                      # 配置管理
│   ├── base/                    # 基础配置
│   │   ├── base_config.sh       # 基础配置
│   │   └── state_config.sh      # 状态配置
│   ├── env/                     # 环境配置
│   │   ├── production.sh        # 生产环境配置
│   │   ├── development.sh       # 开发环境配置
│   │   └── example.sh           # 配置示例
│   ├── loader.sh                # 配置加载器
├── core/                        # 核心功能模块
│   ├── logging.sh               # 日志系统
│   ├── validation.sh            # 验证系统
│   ├── utils.sh                 # 工具函数
│   └── initialize.sh            # 初始化系统
├── install/                     # 安装相关模块
│   ├── download.sh              # 下载模块
│   ├── install.sh               # 安装模块
│   └── configure.sh             # 配置模块
├── scenarios/                   # 安装场景 (重命名)
│   ├── new_install.sh           # 新安装
│   ├── existing_install.sh      # 存量安装
│   ├── incremental_install.sh   # 增量安装
│   ├── version_upgrade.sh       # 版本升级
│   ├── config_update.sh         # 配置更新
│   └── reinstall.sh             # 重装
├── tools/                       # 工具脚本 (重命名)
│   ├── backup.sh                # 备份工具
│   ├── rollback.sh              # 回滚工具
│   └── cleanup.sh               # 清理工具
├── docs/                        # 文档
│   ├── installation.md          # 安装指南
│   ├── configuration.md         # 配置说明
└── logs/                        # 日志目录
```

## 🚀 快速开始

### 1. 环境准备

拷贝 config/env/example.sh，自定义当前配置



```bash
# 设置环境变量
export DATAKIT_VERSION=1.78.0
export S3_BUCKET=your-bucket
export S3_ACCESS_KEY=your-key
export S3_SECRET_KEY=your-secret
export DATAWAY_URL=https://dataway.example.com
export OPS_ADDR=http://ops.example.com:5000
```

### 2. 执行安装
```bash
# 存量安装
./installer.sh existing-install

# 增量安装
./installer.sh incremental-install

# 版本升级
./installer.sh version-upgrade

# 配置更新
./installer.sh config-update

# 重装
./installer.sh reinstall
```

### 3. 使用配置文件
```bash
# 使用生产配置
./installer.sh --config config/env/production.sh existing-install

# 使用开发配置
./installer.sh --config config/env/development.sh existing-install
```

## 📋 配置说明

### 环境变量优先级
1. **环境变量** (最高优先级)
2. **配置文件** (中等优先级)
3. **默认值** (最低优先级)

### 必需配置
- `DATAKIT_VERSION`: Datakit版本
- `S3_BUCKET`: S3存储桶
- `S3_ACCESS_KEY`: S3访问密钥
- `S3_SECRET_KEY`: S3秘密密钥
- `DATAWAY_URL`: Dataway地址
- `OPS_ADDR`: 运维平台地址

## 🔧 工具使用

### 配置测试
```bash
./config/tests/test_config.sh
```

### 备份管理
```bash
./tools/backup.sh create    # 创建备份
./tools/backup.sh list      # 列出备份
./tools/backup.sh restore   # 恢复备份
```

### 清理工具
```bash
./tools/cleanup.sh          # 清理临时文件
./tools/rollback.sh         # 回滚安装
```

## 📖 文档

- [安装指南](docs/installation.md)
- [配置说明](docs/configuration.md)
- [故障排除](docs/troubleshooting.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！ 





# TODO 
install 目录只包含安装相关的脚本，其他的脚本都放在 core 目录下