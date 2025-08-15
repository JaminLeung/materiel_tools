# Core模块测试说明

本目录包含 Datakit 自动化安装工具核心模块的单元测试。

## 📁 测试文件结构

```
core/
├── README.md                           # 本文档
├── run_all_core_tests.sh              # 综合测试运行器
├── test_datakit_service.sh            # Datakit服务模块测试
├── run_datakit_service_tests.sh       # Datakit服务测试运行器
├── README_datakit_service_tests.md    # Datakit服务测试说明
├── test_error_handler.sh              # 错误处理模块测试
├── run_error_handler_tests.sh         # 错误处理测试运行器
├── README_error_handler_tests.md      # 错误处理测试说明
├── test_logging.sh                    # 日志系统模块测试（已存在）
└── results/                           # 测试结果目录
    └── test_reports/                  # 测试报告文件
```

## 🚀 快速开始

### 运行所有Core模块测试
```bash
cd datakit-automation/test/core
bash run_all_core_tests.sh
```

### 运行特定模块测试

#### Datakit服务模块
```bash
cd datakit-automation/test/core
bash run_datakit_service_tests.sh
# 或者直接运行
bash test_datakit_service.sh
```

#### 错误处理模块
```bash
cd datakit-automation/test/core
bash run_error_handler_tests.sh
# 或者直接运行
bash test_error_handler.sh
```

#### 日志系统模块
```bash
cd datakit-automation/test/core
bash test_logging.sh
```

## 🧪 测试覆盖范围

### 1. Datakit服务模块 (`datakit_service.sh`)
- **状态检查函数**: 检查进程、端口、配置文件等
- **服务控制函数**: 启动、停止、重启Datakit服务
- **安装状态检查**: 验证是否已安装Datakit
- **Node Exporter状态检查**: 检查Node Exporter运行状态

**测试特点**:
- 使用模拟函数避免影响实际系统
- 测试各种成功和失败场景
- 验证systemctl和datakit命令的兼容性

### 2. 错误处理模块 (`error_handler.sh`)
- **错误代码管理**: 预定义错误代码和严重程度
- **错误记录**: 不同级别的错误日志记录
- **错误处理**: 标准化的错误处理流程
- **信号处理**: 处理中断和终止信号
- **清理功能**: 临时文件和日志文件清理

**测试特点**:
- 测试所有预定义的错误代码
- 验证错误严重程度的处理逻辑
- 模拟信号处理和清理操作

### 3. 日志系统模块 (`logging.sh`)
- **日志级别**: DEBUG、INFO、WARNING、ERROR、SUCCESS
- **日志格式**: JSON格式的日志输出
- **日志文件管理**: 日志文件创建和轮转
- **并发安全**: 多进程并发写入日志

**测试特点**:
- 测试各种日志级别的输出
- 验证JSON日志格式的正确性
- 测试并发写入的安全性

## 🔧 测试环境

### 模拟函数
所有测试都使用模拟函数来避免对实际系统的影响：

- **进程和端口模拟**: 模拟`pgrep`、`netstat`、`ss`等命令
- **系统服务模拟**: 模拟`systemctl`命令的各种操作
- **日志函数模拟**: 模拟日志输出到测试文件
- **文件操作模拟**: 模拟文件查找和删除操作

### 测试文件
测试会创建临时的测试文件：
- 临时测试文件（用于测试清理功能）
- 测试日志文件（用于验证输出）
- 模拟目录结构（用于测试文件操作）

## 📊 测试结果

### 输出格式
每个测试都会输出：
- 测试名称和描述
- 通过/失败/跳过状态
- 详细的错误信息（如果有）
- 测试统计摘要

### 结果文件
测试完成后会生成：
- `.log` 文件 - 详细的测试日志
- `.json` 文件 - 结构化的测试报告

### 综合报告
使用 `run_all_core_tests.sh` 会生成：
- 每个模块的单独测试报告
- 综合的测试摘要报告
- 模块级别的通过/失败统计

## 🐛 故障排除

### 常见问题

1. **权限问题**
   ```bash
   chmod +x *.sh
   ```

2. **路径问题**
   确保在正确的目录下运行测试，或者使用绝对路径。

3. **依赖问题**
   测试脚本依赖bash shell，确保系统支持bash。

4. **模拟函数问题**
   如果测试失败，检查模拟函数是否正确实现。

### 调试模式
如果需要调试测试，可以在测试脚本中添加：
```bash
set -x  # 启用调试模式
```

## 📝 添加新测试

### 为新模块添加测试
1. 创建测试脚本：`test_<module_name>.sh`
2. 创建测试运行器：`run_<module_name>_tests.sh`
3. 创建说明文档：`README_<module_name>_tests.md`
4. 在 `run_all_core_tests.sh` 中添加新模块

### 测试脚本结构
每个测试脚本应该包含：
- 测试环境设置 (`setup`)
- 测试环境清理 (`teardown`)
- 测试函数 (`test_<function_name>`)
- 主测试函数 (`main`)
- 结果统计和显示

### 断言函数
使用提供的断言函数：
- `assert_true()` - 断言条件为真
- `assert_false()` - 断言条件为假
- `assert_equal()` - 断言值相等
- `assert_function_exists()` - 断言函数存在

## 🔗 相关文档

- [项目根目录](../../README.md)
- [Core模块](../core/)
- [测试框架说明](../README.md)
- [单元测试](../unit_test/)

## 📞 支持

如果遇到问题，请：
1. 检查测试日志文件
2. 确认测试环境设置正确
3. 查看相关模块的源代码
4. 联系开发团队

## 🎯 测试最佳实践

### 1. 隔离性
- 每个测试应该独立运行
- 使用模拟函数避免外部依赖
- 测试后清理所有创建的文件

### 2. 可读性
- 测试名称应该清晰描述测试内容
- 使用有意义的变量名和函数名
- 添加适当的注释说明测试逻辑

### 3. 维护性
- 将公共函数提取到测试工具中
- 使用一致的命名约定
- 定期更新测试以适应代码变化

### 4. 覆盖率
- 测试所有公共函数
- 测试各种边界情况
- 测试错误处理路径 