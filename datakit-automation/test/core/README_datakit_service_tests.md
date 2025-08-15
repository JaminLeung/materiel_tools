# Datakit服务模块测试说明

本文档描述了 `datakit_service.sh` 模块的单元测试。

## 📁 测试文件

- `test_datakit_service.sh` - 主要的测试脚本
- `run_datakit_service_tests.sh` - 测试运行器
- `README_datakit_service_tests.md` - 本文档

## 🚀 快速开始

### 运行所有测试
```bash
cd datakit-automation/test/core
bash run_datakit_service_tests.sh
```

### 直接运行测试脚本
```bash
cd datakit-automation/test/core
bash test_datakit_service.sh
```

## 🧪 测试覆盖范围

### 1. 函数存在性测试
- `check_datakit_status` - 检查Datakit服务状态
- `check_installation_status` - 检查安装状态
- `check_datakit_process` - 检查Datakit进程
- `check_datakit_port` - 检查Datakit端口
- `check_datakit_config` - 检查Datakit配置文件
- `check_node_exporter_status` - 检查Node Exporter状态
- `start_datakit` - 启动Datakit服务
- `stop_datakit` - 停止Datakit服务
- `restart_datakit` - 重启Datakit服务

### 2. 功能测试

#### 状态检查测试
- 测试进程不存在的情况
- 测试进程存在的情况
- 测试端口未被占用的情况
- 测试端口被占用的情况
- 测试配置文件不存在的情况
- 测试配置文件存在的情况

#### 服务控制测试
- 测试systemctl启动成功
- 测试datakit命令启动成功
- 测试启动失败的情况
- 测试systemctl停止成功
- 测试datakit命令停止成功
- 测试强制停止成功
- 测试systemctl重启成功
- 测试datakit命令重启成功

## 🔧 测试环境

### 模拟函数
测试使用模拟函数来避免对实际系统的影响：

- `mock_pgrep()` - 模拟进程检查
- `mock_netstat()` - 模拟网络状态检查
- `mock_ss()` - 模拟socket状态检查
- `mock_systemctl()` - 模拟systemctl命令
- `mock_datakit()` - 模拟datakit命令

### 环境变量
测试通过环境变量控制模拟行为：

- `MOCK_DATAKIT_PROCESS` - 控制进程模拟状态
- `MOCK_DATAKIT_PORT` - 控制端口模拟状态
- `MOCK_SYSTEMCTL_*` - 控制systemctl模拟状态
- `MOCK_DATAKIT_*` - 控制datakit命令模拟状态

## 📊 测试结果

### 输出格式
测试结果包含：
- 测试名称和描述
- 通过/失败/跳过状态
- 详细的错误信息
- 测试统计摘要

### 结果文件
测试完成后会生成：
- `.log` 文件 - 详细的测试日志
- `.json` 文件 - 结构化的测试报告

## 🐛 故障排除

### 常见问题

1. **权限问题**
   ```bash
   chmod +x test_datakit_service.sh
   chmod +x run_datakit_service_tests.sh
   ```

2. **路径问题**
   确保在正确的目录下运行测试，或者使用绝对路径。

3. **依赖问题**
   测试脚本依赖bash shell，确保系统支持bash。

### 调试模式
如果需要调试测试，可以在测试脚本中添加：
```bash
set -x  # 启用调试模式
```

## 📝 添加新测试

### 添加新的测试函数
1. 创建新的测试函数，命名格式：`test_<function_name>()`
2. 在 `main()` 函数中调用新测试
3. 使用断言函数验证结果

### 添加新的断言
1. 在断言函数部分添加新的断言函数
2. 确保断言函数记录测试结果
3. 在测试中使用新的断言

## 🔗 相关文档

- [Datakit服务模块](../core/datakit_service.sh)
- [测试框架说明](../README.md)
- [核心模块测试](../unit_test/existing_installation/)

## 📞 支持

如果遇到问题，请：
1. 检查测试日志文件
2. 确认测试环境设置正确
3. 查看相关模块的源代码
4. 联系开发团队 