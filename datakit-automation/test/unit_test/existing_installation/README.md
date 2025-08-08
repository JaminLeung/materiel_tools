# existing_installation.sh 单元测试

## 概述

这是一个简单实用的单元测试脚本，用于对 `install` 目录下的各个模块进行独立测试。

## 设计理念

- **真实配置**: 使用真实的配置文件，通过 `source` 方式读取
- **临时文件**: 创建临时文件进行测试，不影响主流程安装
- **模块化测试**: 支持单独验证每个模块
- **自动清理**: 测试完成后自动删除临时文件
- **调试友好**: 便于在开发调试中对每个模块进行单独验证

## 支持的模块

| 模块名 | 文件名 | 功能描述 |
|--------|--------|----------|
| `status_check` | `status_check.sh` | 检查Datakit安装状态 |
| `download` | `download.sh` | 下载安装包 |
| `install` | `install.sh` | 安装组件 |
| `configure` | `configure.sh` | 配置和验证 |
| `setup_cron` | `setup_cron.sh` | 设置定时任务 |
| `verify` | `verify.sh` | 验证安装结果 |
| `host_info` | `host_info.sh` | 获取主机信息 |

## 使用方法

### 1. 运行所有模块测试

```bash
./unit_test.sh --all
```

### 2. 运行单个模块测试

```bash
# 测试状态检查模块
./unit_test.sh --module status_check

# 测试下载模块
./unit_test.sh --module download

# 测试安装模块
./unit_test.sh --module install

# 测试配置模块
./unit_test.sh --module configure

# 测试定时任务模块
./unit_test.sh --module setup_cron

# 测试验证模块
./unit_test.sh --module verify

# 测试主机信息模块
./unit_test.sh --module host_info
```

### 3. 详细输出模式

```bash
./unit_test.sh --all --verbose
```

### 4. 查看帮助

```bash
./unit_test.sh --help
```

## 测试环境

### 临时目录结构

测试脚本会创建以下临时目录结构：

```
/tmp/datakit_unit_test.XXXXXX/
├── install/                          # 安装目录（从/opt/datakit_install复制）
│   ├── datakit_bundle-*.tar.gz      # 真实的bundle文件
│   ├── installer-*                  # 真实的安装器
│   ├── datakit-*.tar.gz            # 真实的Datakit包
│   ├── dk_upgrader-*.tar.gz        # 真实的升级器
│   ├── data.tar.gz                 # 真实的数据包
│   └── node_exporter-*.tar.gz      # 真实的Node Exporter
├── usr/local/datakit/conf.d/        # 模拟Datakit配置目录
│   ├── datakit.conf                # 主配置文件
│   ├── opentelemetry/              # OpenTelemetry配置
│   ├── log/                        # 日志配置
│   ├── pushgateway/                # Pushgateway配置
│   └── prom/                       # Prometheus配置
├── var/log/datakit/                # 模拟日志目录
├── etc/systemd/system/             # 模拟systemd目录
└── scripts/                        # 模拟脚本目录
    ├── config_update.sh
    ├── datakit_health_check.sh
    └── app_init.sh
```

### 配置加载

测试脚本会按以下优先级加载真实配置：

1. **基础配置**: `config/base/base_config.sh`
2. **环境配置**: 按优先级加载 `config/env/benjamin.sh`、`production.sh`、`development.sh`
3. **核心模块**: 自动加载所有 `core/` 目录下的模块：
   - `core/logging.sh` - 日志功能
   - `core/utils.sh` - 工具函数
   - `core/validation.sh` - 配置验证
   - `core/initialize.sh` - 初始化功能
   - `core/health_check.sh` - 健康检查
   - `core/datakit_service.sh` - 服务管理
   - `core/config_file.sh` - 配置文件管理

## 测试内容

### 状态检查模块测试

- 检查Datakit进程状态
- 检查Datakit端口占用情况
- 检查Datakit配置文件存在性
- 完整安装状态检查

### 下载模块测试

- 准备安装目录
- 验证目录创建
- 检查bundle文件存在性

### 安装模块测试

- Bundle文件解压
- 解压后文件验证
- Node Exporter安装（模拟）
- Datakit安装（模拟）

### 配置模块测试

- Datakit主配置文件配置
- 配置文件修改验证
- 采集器配置
- 采集器配置文件验证

### 定时任务模块测试

- 定时任务设置
- 脚本文件权限设置
- 配置验证

### 验证模块测试

- 配置文件存在性验证
- 资源限制配置验证
- 定时任务配置验证

### 主机信息模块测试

- 主机信息获取
- 全局状态设置验证

## 测试结果

### 输出格式

```
✅ PASS: test_name - message
❌ FAIL: test_name - message (期望: 'expected', 实际: 'actual')
```

### 统计信息

```
==========================================
测试结果统计
==========================================
总测试数: 25
通过: 23
失败: 2
通过率: 92%

详细结果:
------------------------------------------
PASS: check_datakit_process_not_running - Datakit进程检查正确
PASS: check_datakit_port_not_listening - Datakit端口检查正确
...
```

## 注意事项

1. **权限要求**: 需要执行权限来创建临时目录和文件
2. **系统命令**: 依赖 `bash`, `mktemp`, `chmod`, `rm` 等系统命令
3. **目录结构**: 需要正确的项目目录结构
4. **清理机制**: 测试完成后会自动清理临时文件
5. **错误处理**: 使用 `set -e` 确保错误时及时退出

## 调试技巧

### 1. 查看详细输出

```bash
./unit_test.sh --module status_check --verbose
```

### 2. 手动检查临时文件

在测试运行期间，可以查看临时目录：

```bash
# 查看临时目录（测试运行时会显示路径）
ls -la /tmp/datakit_unit_test.*/
```

## 故障排除

### 常见问题

1. **权限错误**: 确保脚本有执行权限
   ```bash
   chmod +x unit_test.sh
   ```

2. **目录不存在**: 确保项目结构正确
   ```bash
   ls -la ../../../install/
   ```

3. **命令不存在**: 确保系统有必需命令
   ```bash
   which bash mktemp chmod rm
   ```

4. **临时文件清理失败**: 手动清理
   ```bash
   rm -rf /tmp/datakit_unit_test.*/
   ```

## 版本历史

- **v1.0.0**: 初始版本，支持所有install模块的单元测试

## 贡献

欢迎提交问题和改进建议！ 