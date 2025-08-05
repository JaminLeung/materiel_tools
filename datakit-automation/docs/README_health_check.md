# Datakit健康检查脚本使用说明

## 概述

`datakit_health_check.sh` 是一个简化的Datakit健康检查脚本，参考了 `config_update.sh` 的风格和结构，通过调用Datakit的 `/v1/ping` 接口来监控服务状态。

## 功能特性

- ✅ 通过 `/v1/ping` 接口检查Datakit状态
- ✅ 连续失败3次后自动重启Datakit
- ✅ 支持5分钟定时任务
- ✅ 集成观测云日志上报
- ✅ 使用core模块，代码结构简洁
- ✅ 参考config_update.sh的风格和结构
- ✅ 支持锁机制，防止重复执行

## 使用方法

### 1. 执行单次健康检查
```bash
./datakit_health_check.sh
```

### 2. 查看健康检查状态
```bash
./datakit_health_check.sh status
```

### 3. 安装5分钟定时任务
```bash
./datakit_health_check.sh install-cron
```

### 4. 卸载定时任务
```bash
./datakit_health_check.sh uninstall-cron
```

## 配置说明

脚本中的主要配置常量（在脚本开头定义）：

```bash
# 健康检查配置
readonly HEALTH_CHECK_MAX_FAILURE_COUNT=3        # 最大失败次数
readonly HEALTH_CHECK_PING_TIMEOUT=10           # ping接口超时时间
readonly HEALTH_CHECK_PING_URL="http://localhost:9529/v1/ping"
```

## 文件说明

- **脚本文件**: `scripts/datakit_health_check.sh`
- **日志文件**: `/var/log/datakit_health_check.log`
- **锁文件**: `/var/run/datakit_health_check.lock`
- **失败计数文件**: `/var/run/datakit_health_check_failure_count`

## 定时任务

安装定时任务后，系统会每5分钟自动执行一次健康检查：

```bash
*/5 * * * * /path/to/datakit_health_check.sh >/dev/null 2>&1
```

## 锁机制

脚本使用锁机制确保同一时间只有一个健康检查任务在运行：

1. 执行前检查锁文件是否存在
2. 如果锁文件存在且进程还在运行，跳过本次执行
3. 如果发现僵尸锁文件，自动清理并继续执行
4. 执行完成后自动清理锁文件

## 失败计数机制

1. 每次健康检查失败时，失败计数加1
2. 达到最大失败次数（3次）时，自动重启Datakit
3. 重启成功后，失败计数重置为0
4. 健康检查成功后，失败计数重置为0

## 依赖要求

- `curl` - 用于调用Datakit API
- `crontab` - 用于管理定时任务
- core模块 - 提供日志和Datakit服务管理功能
- 环境配置文件 - `config/env/benjamin.sh`

## 代码结构

脚本遵循与 `config_update.sh` 相同的结构：

1. **环境配置加载** - 加载 `benjamin.sh` 环境配置
2. **核心模块加载** - 加载core模块中的功能
3. **工具函数定义** - 定义锁机制和失败计数管理
4. **主逻辑函数** - 实现健康检查核心逻辑
5. **主函数** - 处理命令行参数和流程控制

## 故障排除

1. **脚本无法启动**
   - 检查core模块是否存在
   - 确认环境配置文件路径正确
   - 确认脚本有执行权限

2. **健康检查失败**
   - 确认Datakit服务正在运行
   - 检查9529端口是否被监听
   - 查看日志文件获取详细错误信息

3. **定时任务不工作**
   - 检查crontab服务是否运行
   - 确认定时任务已正确安装
   - 查看系统日志：`journalctl -u cron`

4. **运维平台配置失败**
   - 脚本会使用默认配置继续运行
   - 检查网络连接和API地址配置

## 注意事项

- 脚本需要root权限才能管理Datakit服务
- 确保观测云配置正确，以便日志上报功能正常工作
- 建议在生产环境中使用定时任务模式
- 脚本会自动处理僵尸锁文件，无需手动清理 