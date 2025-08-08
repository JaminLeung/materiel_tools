# existing_installation.sh 单元测试方案总结

## 方案概述

我已经为您重新设计了一个**简单实用的单元测试方案**，完全符合您的需求：

- ✅ **使用真实配置**: 通过 `source` 方式读取真实的配置文件
- ✅ **创建临时文件**: 在测试过程中创建临时文件，不影响主流程
- ✅ **模块化测试**: 支持单独验证每个 install 模块
- ✅ **自动清理**: 测试完成后自动删除临时文件
- ✅ **调试友好**: 便于在开发调试中对每个模块进行单独验证

## 文件结构

```
test/unit_test/existing_installation/
├── unit_test.sh              # 主测试脚本 (30KB)
├── test_material.sh          # 物料包复制测试脚本 (6KB)
├── test_core_modules.sh      # Core模块加载测试脚本 (7KB)
├── test_version.sh           # 版本号获取测试脚本 (7KB)
├── test_configure_simple.sh  # configure模块测试脚本 (15KB)
├── cleanup.sh                # 临时文件清理脚本 (12KB)
├── README.md                 # 详细使用文档 (6KB)
└── SUMMARY.md               # 本总结文档 (7KB)
```

## 支持的模块

| 模块名 | 文件名 | 功能描述 | 测试内容 |
|--------|--------|----------|----------|
| `status_check` | `status_check.sh` | 检查Datakit安装状态 | 进程检查、端口检查、配置检查 |
| `download` | `download.sh` | 下载安装包 | 目录准备、文件验证 |
| `install` | `install.sh` | 安装组件 | Bundle解压、组件安装 |
| `configure` | `configure.sh` | 配置和验证 | 主配置、采集器配置 |
| `setup_cron` | `setup_cron.sh` | 设置定时任务 | 定时任务配置 |
| `verify` | `verify.sh` | 验证安装结果 | 配置验证、状态验证 |
| `host_info` | `host_info.sh` | 获取主机信息 | 主机信息获取 |

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

### 3. 查看帮助
```bash
./unit_test.sh --help
```

### 4. 基础功能测试
```bash
./test_basic.sh
```

### 5. 物料包复制测试
```bash
./test_material.sh
```

### 6. Core模块加载测试
```bash
./test_core_modules.sh
```

### 7. 版本号获取测试
```bash
./test_version.sh
```

### 8. configure模块测试
```bash
./test_configure_simple.sh
```

### 9. 临时文件清理
```bash
# 使用主脚本清理
./unit_test.sh --cleanup all         # 清理所有临时文件
./unit_test.sh --cleanup logs        # 清理日志文件
./unit_test.sh --cleanup orphaned    # 清理孤立的临时文件
./unit_test.sh --stats               # 显示临时文件统计信息

# 使用独立清理脚本
./cleanup.sh                         # 清理所有临时文件
./cleanup.sh --orphaned 2            # 清理超过2小时的孤立文件
./cleanup.sh --force                 # 强制清理所有临时文件
./cleanup.sh --stats                 # 显示临时文件统计信息
```

## 核心特性

### 1. 真实配置加载
- 按优先级加载环境配置：`benjamin.sh` → `production.sh` → `development.sh`
- 自动处理 readonly 变量冲突
- 支持环境变量覆盖

### 2. 临时文件管理
- 创建隔离的测试环境：`/tmp/datakit_unit_test.XXXXXX/`
- 模拟完整的文件结构
- 自动清理临时文件

### 3. 模块化测试
- 每个模块独立测试
- 详细的测试结果报告
- 支持断言框架

### 4. configure模块测试
- **配置文件复制**: 将原始配置文件复制到临时文件进行操作
- **详细日志记录**: 记录所有增、删、改操作的详细信息
- **修改前后对比**: 显示修改前后的配置值
- **配置验证**: 验证修改后的配置是否正确
- **自动清理**: 测试完成后自动清理临时文件
- **支持多种配置类型**:
  - Datakit主配置文件 (datakit.conf)
  - Prometheus采集器配置
  - OpenTelemetry采集器配置
  - 日志采集器配置
  - Pushgateway采集器配置

### 5. 测试结果统计
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
✅ PASS: check_datakit_process_not_running - Datakit进程检查正确
✅ PASS: check_datakit_port_not_listening - Datakit端口检查正确
...
```

## 测试环境结构

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

## 断言函数

框架提供以下断言函数：

- `assert_true(condition, test_name, message)` - 断言条件为真
- `assert_false(condition, test_name, message)` - 断言条件为假
- `assert_equal(actual, expected, test_name, message)` - 断言相等
- `assert_file_exists(file_path, test_name, message)` - 断言文件存在
- `assert_dir_exists(dir_path, test_name, message)` - 断言目录存在

## 调试技巧

### 1. 查看详细输出
```bash
./unit_test.sh --module status_check --verbose
```

### 2. 手动检查临时文件
```bash
# 查看临时目录（测试运行时会显示路径）
ls -la /tmp/datakit_unit_test.*/
```

### 3. 基础功能验证
```bash
./test_basic.sh
```

## 故障排除

### 常见问题

1. **权限错误**: 确保脚本有执行权限
   ```bash
   chmod +x unit_test.sh test_basic.sh
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

## 优势特点

### 1. 简单实用
- 单个脚本文件，易于理解和维护
- 清晰的命令行接口
- 详细的帮助文档

### 2. 真实环境
- 使用真实的配置文件
- 从 `/opt/datakit_install` 复制真实的物料包
- 自动加载所有 `core/` 模块的函数
- 模拟真实的文件结构
- 支持真实的环境变量

### 3. 安全隔离
- 完全隔离的测试环境
- 不影响主流程安装
- 自动清理临时文件

### 4. 调试友好
- 支持单独模块测试
- 详细的测试结果报告
- 支持详细输出模式

### 5. 智能清理
- 测试完成后自动清理临时文件
- 多种清理模式：全部、日志、孤立文件、强制清理
- 独立的清理脚本，支持灵活的参数配置
- 临时文件统计和监控功能

## 使用场景

### 1. 开发调试
- 单独测试某个模块的功能
- 验证配置文件的正确性
- 调试模块间的依赖关系

### 2. 功能验证
- 验证安装流程的完整性
- 检查配置文件的生成
- 测试错误处理机制

### 3. 回归测试
- 运行完整的测试套件
- 验证修改后的功能
- 确保向后兼容性

## 总结

这个单元测试方案完全满足您的需求：

1. **使用真实配置**: 通过 `source` 方式读取真实的配置文件
2. **创建临时文件**: 在测试过程中创建临时文件，不影响主流程
3. **模块化测试**: 支持单独验证每个 install 模块
4. **自动清理**: 测试完成后自动删除临时文件
5. **调试友好**: 便于在开发调试中对每个模块进行单独验证

方案简单实用，易于使用和维护，是您进行模块调试和功能验证的理想工具。 