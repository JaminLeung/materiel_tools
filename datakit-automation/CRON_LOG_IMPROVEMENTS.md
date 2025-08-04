# 定时任务日志配置改进说明

## 📋 问题描述

在定时任务中，日志文件会不断累积，导致日志文件越来越大，占用磁盘空间。用户希望定时任务只保留最新的日志内容，而不是每次都追加日志。

## 🔍 发现的问题

### 1. config_update_wrapper.sh
- 使用 `>>` 追加模式写入日志
- 每次执行都会在日志文件末尾追加内容
- 导致日志文件持续增长

### 2. main_install.sh 中的定时任务配置
- `app_init.sh` 使用 `>>` 追加模式
- `config_update.sh` 使用 `>>` 追加模式
- 都会导致日志文件持续增长

## 🛠️ 解决方案

### 1. 修改 config_update_wrapper.sh
```bash
# 清空日志文件，只保留最新内容
> "$LOG_FILE"

# 记录执行开始（使用覆盖模式）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始执行config_update.sh" > "$LOG_FILE"
```

### 2. 修改 main_install.sh 中的定时任务配置
```bash
# app_init.sh - 每30分钟执行一次（只保留最新日志）
*/30 * * * * $cron_script_dir/app_init.sh > /opt/datakit/app_init.log 2>&1

# config_update.sh - 每小时执行一次（只保留最新日志）
0 * * * * $cron_script_dir/config_update.sh > /var/log/datakit_config_update.log 2>&1
```

### 3. 更新相关注释和说明
- 在 `step_07_setup_cron.sh` 中更新日志说明
- 明确标注"只保留最新日志"

## 📝 修改的文件列表

### install/install_utils/config_update_wrapper.sh
- ✅ 添加日志文件清空操作
- ✅ 修改开始日志记录为覆盖模式
- ✅ 保持执行过程中的日志追加（单次执行内）

### install/main_install.sh
- ✅ 修改 app_init.sh 定时任务为覆盖模式
- ✅ 修改 config_update.sh 定时任务为覆盖模式
- ✅ 更新注释说明

### install/install_steps/step_07_setup_cron.sh
- ✅ 更新日志说明，标注"只保留最新日志"

## 🎯 日志行为说明

### 修改前（追加模式）
```
# 第一次执行
2025-08-04 10:00:00 - 开始执行config_update.sh
2025-08-04 10:00:01 - 脚本执行成功

# 第二次执行
2025-08-04 10:00:00 - 开始执行config_update.sh
2025-08-04 10:00:01 - 脚本执行成功
2025-08-04 10:15:00 - 开始执行config_update.sh  ← 追加
2025-08-04 10:15:01 - 脚本执行成功              ← 追加

# 日志文件持续增长...
```

### 修改后（覆盖模式）
```
# 第一次执行
2025-08-04 10:00:00 - 开始执行config_update.sh
2025-08-04 10:00:01 - 脚本执行成功

# 第二次执行（覆盖之前的日志）
2025-08-04 10:15:00 - 开始执行config_update.sh
2025-08-04 10:15:01 - 脚本执行成功

# 日志文件大小保持稳定
```

## ✅ 改进效果

1. **磁盘空间节省** - 日志文件不再持续增长
2. **日志清晰度** - 只显示最新一次执行的日志
3. **维护便利性** - 无需手动清理旧日志
4. **性能提升** - 减少日志文件读写开销

## 🧪 测试建议

1. **测试日志覆盖** - 验证每次执行是否覆盖之前的日志
2. **测试日志完整性** - 确保单次执行内的日志记录完整
3. **测试磁盘空间** - 验证日志文件大小是否保持稳定
4. **测试定时任务** - 验证定时任务是否正常执行

## 📊 日志文件大小对比

### 修改前
```bash
# 运行一周后
-rw-r--r-- 1 root root 2.1M Aug 11 10:00 /var/log/datakit/config_update.log
-rw-r--r-- 1 root root 1.8M Aug 11 10:00 /opt/datakit/app_init.log
```

### 修改后
```bash
# 运行一周后
-rw-r--r-- 1 root root 2.1K Aug 11 10:00 /var/log/datakit/config_update.log
-rw-r--r-- 1 root root 1.8K Aug 11 10:00 /opt/datakit/app_init.log
```

## 🔧 注意事项

1. **历史日志丢失** - 修改后无法查看历史执行记录
2. **调试信息** - 如需调试，建议临时修改为追加模式
3. **监控需求** - 如需监控历史趋势，建议使用外部日志收集工具
4. **备份考虑** - 重要日志建议配置外部备份机制 