# Datakit 自动化安装工具

## 📁 目录结构

```
datakit-automation/
├── README.md                      # 项目说明
├── datakit_auto_installer.sh      # 主入口脚本
├── core/                          # 核心模块
│   ├── logging.sh                 # 日志
│   ├── error_handler.sh           # 错误处理
│   ├── validation.sh              # 校验
│   ├── utils.sh                   # 工具函数
│   ├── initialize.sh              # 初始化&运行时目录
│   ├── datakit_service.sh         # 服务控制
│   └── health_check.sh            # 健康检查共享逻辑
├── config/                        # 配置体系（分层加载）
│   ├── base/
│   │   ├── base_config.sh         # 基础配置与默认值
│   │   └── state_config.sh        # 运行时状态配置
│   ├── env/                       # 环境配置
│   │   ├── example.sh
│   │   ├── dev.sh
│   │   ├── test.sh
│   │   ├── benjamin.sh
│   │   └── ox.sh
│   ├── scripts/                   # 脚本级配置（按脚本名）
│   │   ├── config_update.sh
│   │   ├── app_init.sh
│   │   └── health_check.sh
│   ├── tools/
│   ├── loader.sh                  # 配置加载器
│   ├── README.md
│   └── SECURITY.md
├── install/                       # 安装与定时任务
│   ├── install.sh
│   ├── configure.sh
│   └── setup_cron.sh
├── scenarios/                     # 安装场景（按场景组织）
│   ├── existing_installation.sh
│   ├── incremental_installation.sh
│   ├── version_upgrade.sh
│   └── reinstall.sh
├── scripts/                       # 业务脚本
│   ├── app_init.sh                # 从运维平台同步业务配置
│   ├── config_update.sh           # 配置同步/合并/写回
│   ├── datakit_health_check.sh    # 健康检查
│   └── ssm.yaml
├── tools/                         # 第三方工具（内置）
│   ├── jq
│   └── yj
├── backup/                        # 备份归档（按日期）
│   └── 20250813/
├── docs/                          # 文档
│   ├── installation.md
│   ├── configuration.md
│   ├── README_existing_installation.md
│   ├── README_health_check.md
│   ├── error_handling.md
│   ├── logging.md
│   ├── logging_merge_implementation.md
│   └── reinstall_design.md
├── test/                          # 测试与验证
│   ├── README.md
│   ├── validate_merge_logic.sh
│   ├── test_final_merge.sh
│   ├── test_logging_merge.sh
│   ├── test_modified_merge.sh
│   ├── core/
│   ├── pre-check/
│   ├── unit_test/
│   └── mocks/
└── changelog.md
```

## 🧭 功能分布

- **核心模块（core）**: 日志、错误处理、校验、服务控制、健康检查、初始化运行时目录。
- **配置体系（config）**: 分层加载，覆盖顺序详见“配置加载与优先级”。
- **安装与场景（install + scenarios）**: 安装动作封装与具体场景编排（存量、增量、升级、重装）。
- **业务脚本（scripts）**: 应用初始化、配置同步、健康检查。
- **工具（tools）**: 内置 `jq`/`yj` 供 JSON/TOML 处理（不使用 `yq`）。
- **备份（backup）**: 归档备份目录；运行期备份由脚本管理，必要时同步至此。
- **测试（test）**: 合并逻辑等单元/集成测试脚本与样例。

## 🚀 快速开始

### 1) 环境准备

```bash
# 选择环境（对应 config/env/<ENV>.sh）
export DATAKIT_ENV=dev

# 常用核心变量（按需）
export DATAKIT_VERSION=1.83.0
export DATAWAY_URL=https://dataway.example.com
export OPS_ADDR=http://ops.example.com:5000
```

可复制示例并自定义：`cp config/env/example.sh config/env/myenv.sh` 后设置 `DATAKIT_ENV=myenv`。

### 2) 执行场景

```bash
# 存量安装（已运行但未安装的主机）
./datakit_auto_installer.sh existing-install

# 增量安装（初始化创建镜像的主机）
./datakit_auto_installer.sh incremental-install


# 配置同步（Datakit 服务控制 + 全局/采集器配置管理）
./datakit_auto_installer.sh config-update

# 应用初始化（从运维平台同步业务配置）
./datakit_auto_installer.sh app-init

# 设置定时任务
./datakit_auto_installer.sh setup-cron

# 健康检查
./datakit_auto_installer.sh health-check

# 重装（支持新旧两种路径）
./datakit_auto_installer.sh reinstall

# 清理安装环境
./datakit_auto_installer.sh clean-install
```

提示：入口脚本支持 `-v/--verbose`, `-d/--debug`, `-h/--help`, `--version` 等选项。

### 3) 配置加载与优先级

配置加载由 `config/loader.sh` 统一完成，实际覆盖顺序：

1. 环境变量（最高）
2. 脚本特定配置（`config/scripts/<script>.sh`）
3. 环境配置（`config/env/<ENV>.sh`）
4. 状态配置（`config/base/state_config.sh`）
5. 基础配置（`config/base/base_config.sh`，最低）

说明：`--config` 参数目前保留但默认以 `DATAKIT_ENV` 选择环境配置为主。

## 🧰 工具约定

- 本项目默认使用 `jq` 与 `yj` 处理 JSON/TOML，不依赖 `yq`。
- 内置可执行在 `tools/` 下，脚本会自动调用。

## 💾 备份与重启策略

- 配置同步脚本会在处理全部配置后统一评估是否需要重启，仅在需要时重启一次，以避免多次扰动服务。
- 运行期会创建必要的备份与响应快照（例如写入到 `release/backup/config_update.json`），并在必要时执行备份目录初始化与回收。
- 归档与人工介入场景可将备份/恢复文件统一放置于仓库 `backup/` 目录下进行管理。

## 📖 文档

- 安装指南: `docs/installation.md`
- 配置说明: `docs/configuration.md`
- 场景说明: `docs/README_existing_installation.md`, `docs/README_health_check.md`
- 错误处理: `docs/error_handling.md`

## 🤝 贡献

欢迎提交 Issue 与 Pull Request！
