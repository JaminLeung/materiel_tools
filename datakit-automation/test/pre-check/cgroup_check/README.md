# Cgroup支持检查脚本

## 功能说明

本脚本用于检查系统是否符合Cgroup资源限制的要求，确保Datakit能够正确使用资源限制功能。

## 主要功能

1. **Cgroup版本检测**：自动检测系统使用的是cgroup v1还是v2
2. **资源限制测试**：创建测试cgroup并验证CPU和内存限制是否生效
3. **兼容性验证**：支持不同操作系统的cgroup实现
4. **自动清理**：测试完成后自动清理测试资源

## 验证指标

- **CPU限制**：检查进程平均使用率是否 ≤200%（1核满负载）
- **内存限制**：检查实际使用是否 ≤512MB，或是否触发OOM日志

## 使用方法

```bash
# 赋予执行权限
chmod +x verify_cgroup.sh

# 以root权限运行（cgroup操作需要管理员权限）
sudo ./verify_cgroup.sh
```

## 环境变量

- `CLEANUP_AFTER_TEST`：是否在测试后清理资源（默认：true）

## 支持的Cgroup版本

### Cgroup v1
- 支持路径：`/sys/fs/cgroup/cpu`、`/sys/fs/cgroup/memory`
- 兼容路径：`/sys/fs/cgroup/cpu,cpuacct`

### Cgroup v2
- 支持路径：`/sys/fs/cgroup/unified`

## 测试流程

1. **权限检查**：验证是否具有root权限
2. **工具检查**：确保必要工具（bc、awk、grep等）已安装
3. **版本检测**：自动检测cgroup版本
4. **创建测试cgroup**：根据版本创建相应的cgroup配置
5. **CPU测试**：启动CPU密集型进程并监控使用率
6. **内存测试**：启动内存密集型进程并检查OOM事件
7. **结果验证**：验证限制是否生效
8. **资源清理**：清理测试过程中创建的资源

## 输出示例

```
[INFO] 开始cgroup支持检查...
[INFO] 检查必要工具...
[SUCCESS] 所有必要工具已安装
[INFO] 检测cgroup版本...
[SUCCESS] 检测到cgroup v2
[INFO] 创建测试cgroup: datakit_test_12345
[SUCCESS] 测试cgroup创建成功
[INFO] 启动CPU密集型测试进程...
[SUCCESS] 测试进程已启动 (PID: 12346)
[INFO] 监控CPU使用率 (10秒)...
[INFO] 启动内存密集型测试进程...
[SUCCESS] 内存测试进程已启动 (PID: 12347)
[INFO] 监控内存使用率...
[INFO] 检查OOM事件...
[INFO] 验证测试结果...
[SUCCESS] CPU限制测试通过: 150.25% <= 200%
[SUCCESS] 内存限制测试通过: 触发OOM事件 (1 次)

=== 测试结果汇总 ===
Cgroup版本: v2
CPU使用率: 150.25%
内存使用率: 512.00MB
OOM事件数: 1

[SUCCESS] 所有测试通过！系统支持cgroup资源限制
```

## 错误处理

脚本包含完善的错误处理机制：
- 关键步骤添加错误检查
- 工具缺失检测
- 权限不足检查
- 配置写入失败处理
- 自动资源清理

## 注意事项

1. **需要root权限**：cgroup操作需要管理员权限
2. **系统兼容性**：支持主流Linux发行版
3. **资源占用**：测试过程中会短暂占用系统资源
4. **自动清理**：默认测试后自动清理，可通过环境变量禁用 