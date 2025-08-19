# 日志配置智能合并实现文档

## 概述

本文档描述了在 `app_init.sh` 脚本中实现的日志配置智能合并功能。该功能能够根据配置项的相似性自动合并日志配置，减少配置文件数量，提高管理效率。

## 功能特性

### 1. 智能分组
- 根据 `logType`、`source` 和 `tags` 字段自动分组
- 支持有tags和无tags两种场景
- 使用MD5哈希确保tags比较的准确性

### 2. 自动合并
- 相同特征的配置项自动合并
- logfiles自动去重
- 保持原有配置结构

### 3. 智能分离
- 不同特征的配置项保持分离
- 支持多配置项写入同一文件
- 保持配置的完整性

## 实现架构

### 核心函数

#### 1. `merge_logging_configs()`
- **功能**: 主合并函数，负责整体流程控制
- **输入**: `service_name`, `service` (JSON配置)
- **输出**: 生成合并后的配置文件

#### 2. `process_single_logging_config()`
- **功能**: 处理单个配置项
- **输入**: `service_name`, `logging` (单个配置)
- **输出**: 生成单个配置文件

#### 3. `process_merged_logging_configs()`
- **功能**: 处理需要合并的配置项
- **输入**: `service_name`, `group_configs_json` (配置组)
- **输出**: 根据情况合并或分离

#### 4. `merge_logfiles_without_tags()`
- **功能**: 处理无tags字段的合并
- **输入**: `service_name`, `group_configs_json`
- **输出**: 合并后的配置文件

#### 5. `merge_logfiles_with_tags()`
- **功能**: 处理有tags字段的合并
- **输入**: `service_name`, `group_configs_json`
- **输出**: 根据tags一致性决定合并或分离

### 分组逻辑

#### 无tags字段
```bash
group_key="no_tags_${log_type}_${source}"
```

#### 有tags字段
```bash
tags_hash=$(echo "$tags" | jq -c '.' | md5sum | cut -d' ' -f1)
group_key="with_tags_${log_type}_${source}_${tags_hash}"
```

## 处理场景

### 场景1：无tags字段，logType和source相同
- **条件**: `tags`字段不存在，`logType`和`source`相同
- **处理**: 合并所有`logfiles`，去重后作为一个配置项
- **结果**: 单个配置项写入文件

**示例**:
```json
[
  {
    "logType": "access",
    "logfiles": ["/data/processLog/*process.log"],
    "source": "ec2-golang-logging"
  },
  {
    "logType": "access", 
    "logfiles": ["/data/processLog/*process.log", "/data/processLog/access/*process.log"],
    "source": "ec2-golang-logging"
  }
]
```
**合并结果**:
```json
{
  "logType": "access",
  "logfiles": ["/data/processLog/*process.log", "/data/processLog/access/*process.log"],
  "source": "ec2-golang-logging"
}
```

### 场景2：有tags字段，tags一致
- **条件**: `tags`字段存在且所有配置项的tags一致
- **处理**: 合并`logfiles`，保持第一个配置项的`tags`
- **结果**: 单个配置项写入文件

### 场景3：有tags字段，tags不一致
- **条件**: `tags`字段存在但配置项的tags不一致
- **处理**: 保持分离，写入多个配置项到同一文件
- **结果**: 多个配置项写入同一文件

### 场景4：logType或source不同
- **条件**: `logType`或`source`不同
- **处理**: 保持分离，写入不同文件
- **结果**: 不同文件

## 文件命名规则

```
${service_name}_${log_type}_auto.conf
```

**示例**:
- `nginx_access_auto.conf`
- `mysql_error_auto.conf`
- `app_metric_auto.conf`

## 自动标签处理

### service标签自动添加
如果配置中没有 `service` 标签，会自动添加：
```bash
if ! echo "$logging_content" | jq -r ".inputs.logging[0].tags.service" 2>/dev/null; then
    logging_content=$(echo "$logging_content" | jq --arg service_name "$service_name" ".inputs.logging[0].tags.service = \$service_name")
fi
```

## 错误处理

### 1. 输入验证
- 检查配置数据是否为空
- 验证JSON格式
- 检查必需字段

### 2. 合并验证
- 验证合并后的logfiles不为空
- 检查合并后的配置格式
- 确保文件写入成功

### 3. 错误记录
- 使用 `record_error` 记录错误
- 详细的错误信息
- 错误分类和级别

## 调试功能

### 详细日志
- 分组过程日志
- 合并过程日志
- 文件生成日志

### 验证信息
- 配置项数量统计
- 分组结果统计
- 合并结果验证

## 兼容性

### 与现有系统兼容
- 保持原有的文件命名规则
- 兼容清理函数逻辑
- 保持配置项处理函数接口

### 向后兼容
- 单个配置项处理逻辑不变
- 配置比较逻辑不变
- 文件格式不变

## 测试验证

### 测试脚本
- `test_logging_merge.sh`: 完整测试场景
- `validate_merge_logic.sh`: 核心逻辑验证

### 测试场景
1. 无tags字段合并
2. 有tags字段一致合并
3. 有tags字段不一致分离
4. 不同logType分离

### 验证要点
- 合并逻辑正确性
- 去重功能有效性
- 文件生成正确性
- 错误处理完整性

## 使用示例

### 运行脚本
```bash
cd datakit-automation/scripts
./app_init.sh
```

### 检查结果
```bash
ls -la /usr/local/datakit/conf.d/logging/
cat /usr/local/datakit/conf.d/logging/*.conf
```

## 性能考虑

### 优化点
- 使用关联数组提高分组效率
- 批量处理减少文件I/O
- 智能缓存减少重复计算

### 内存使用
- 配置数据在内存中处理
- 及时释放临时变量
- 避免内存泄漏

## 维护说明

### 代码维护
- 函数职责清晰分离
- 详细的注释和文档
- 统一的错误处理

### 配置维护
- 保持配置格式一致性
- 定期验证合并结果
- 监控配置文件数量

## 总结

日志配置智能合并功能通过智能分组、自动合并和智能分离，有效减少了配置文件数量，提高了管理效率。该功能完全兼容现有系统，具有良好的扩展性和维护性。 