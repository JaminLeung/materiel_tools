# Datakit 配置加载机制改进说明

## 📋 问题描述

在使用 `./installer.sh --config xxxx` 方式时，发现多个脚本中存在硬编码的配置文件加载，导致无法正确使用命令指定的配置文件。

## 🔍 发现的问题

### 1. Scenarios 目录中的硬编码配置
- `scenarios/existing_installation.sh` - 硬编码 `benjamin.sh`
- `scenarios/incremental_installation.sh` - 硬编码 `production_config.sh`
- `scenarios/config_update.sh` - 硬编码 `production_config.sh`
- `scenarios/version_upgrade.sh` - 硬编码 `production_config.sh`
- `scenarios/reinstall.sh` - 硬编码 `production_config.sh`

### 2. Scripts 目录中的硬编码配置
- `scripts/config_update.sh` - 硬编码 `benjamin.sh`
- `scripts/datakit_health_check.sh` - 硬编码 `benjamin.sh`

### 3. Tools 目录中的硬编码配置
- `tools/backup.sh` - 硬编码 `production_config.sh`
- `tools/rollback.sh` - 硬编码 `production_config.sh`
- `tools/cleanup.sh` - 硬编码 `production_config.sh`

## 🛠️ 解决方案

### 1. 修改 installer.sh
在所有场景执行函数中添加配置传递：
```bash
# 传递配置信息给场景脚本
export DATAKIT_CONFIG_FILE="$env_config_file"
```

### 2. 统一配置加载逻辑
为所有脚本添加统一的配置加载检查机制：

```bash
# 检查是否通过installer.sh调用，如果是则配置已加载
# 否则尝试加载默认配置或从环境变量获取
if [[ -z "${DATAKIT_VERSION:-}" ]]; then
    # 尝试从环境变量获取配置文件路径
    local config_file="${DATAKIT_CONFIG_FILE:-}"
    
    if [[ -n "$config_file" ]]; then
        # 加载指定的配置文件
        if [[ -f "$config_file" ]]; then
            source "$config_file"
        elif [[ -f "$CONFIG_DIR/env/$config_file" ]]; then
            source "$CONFIG_DIR/env/$config_file"
        else
            echo "[ERROR] 指定的配置文件不存在: $config_file" >&2
            exit 1
        fi
    else
        # 尝试加载默认配置
        local default_configs=("benjamin.sh" "production.sh" "development.sh")
        local config_loaded=false
        
        for config in "${default_configs[@]}"; do
            if [[ -f "$CONFIG_DIR/env/$config" ]]; then
                echo "[INFO] 加载默认配置文件: $config"
                source "$CONFIG_DIR/env/$config"
                config_loaded=true
                break
            fi
        done
        
        if [[ "$config_loaded" == "false" ]]; then
            echo "[ERROR] 未找到可用的配置文件，请设置 DATAKIT_CONFIG_FILE 环境变量" >&2
            exit 1
        fi
    fi
fi
```

## 📝 修改的文件列表

### installer.sh
- ✅ 添加配置传递机制
- ✅ 在所有场景执行函数中传递 `DATAKIT_CONFIG_FILE` 环境变量

### Scenarios 目录
- ✅ `existing_installation.sh` - 移除硬编码，添加动态配置加载
- ✅ `incremental_installation.sh` - 移除硬编码，添加动态配置加载
- ✅ `config_update.sh` - 移除硬编码，添加动态配置加载
- ✅ `version_upgrade.sh` - 移除硬编码，添加动态配置加载
- ✅ `reinstall.sh` - 移除硬编码，添加动态配置加载

### Scripts 目录
- ✅ `config_update.sh` - 移除硬编码，添加动态配置加载
- ✅ `datakit_health_check.sh` - 移除硬编码，添加动态配置加载

### Tools 目录
- ✅ `backup.sh` - 移除硬编码，添加动态配置加载
- ✅ `rollback.sh` - 移除硬编码，添加动态配置加载
- ✅ `cleanup.sh` - 移除硬编码，添加动态配置加载

## 🎯 配置加载优先级

1. **通过 installer.sh 调用** - 配置已加载，直接使用
2. **环境变量 DATAKIT_CONFIG_FILE** - 加载指定的配置文件
3. **默认配置文件** - 按优先级加载：`benjamin.sh` → `production.sh` → `development.sh`
4. **错误处理** - 如果都找不到，显示错误信息并退出

## 🚀 使用方法

### 方法一：通过 installer.sh 调用（推荐）
```bash
# 使用相对路径
./installer.sh --config benjamin.sh existing-install

# 使用绝对路径
./installer.sh --config /path/to/custom_config.sh existing-install
```

### 方法二：直接调用脚本
```bash
# 设置环境变量
export DATAKIT_CONFIG_FILE=benjamin.sh

# 直接调用脚本
./scenarios/existing_installation.sh
```

### 方法三：使用环境变量
```bash
# 设置所有必要的环境变量
export DATAKIT_VERSION=1.78.0
export S3_BUCKET=my-bucket
export S3_ACCESS_KEY=your-key
export S3_SECRET_KEY=your-secret
export DATAWAY_URL=https://dataway.example.com

# 调用脚本
./scenarios/existing_installation.sh
```

## ✅ 改进效果

1. **配置灵活性** - 支持通过命令行参数指定配置文件
2. **向后兼容** - 保持原有的默认配置加载机制
3. **错误处理** - 提供清晰的错误信息和处理机制
4. **统一性** - 所有脚本使用相同的配置加载逻辑
5. **可维护性** - 减少硬编码，提高代码可维护性
6. **语法修复** - 修复了 `local` 关键字在非函数环境中的使用问题

## 🧪 测试结果

### ✅ 成功的测试用例
1. **相对路径配置** - `./installer.sh --config benjamin.sh existing-install` ✅
2. **绝对路径配置** - `./installer.sh --config /path/to/benjamin.sh --help` ✅
3. **配置加载流程** - 基础配置 → 环境配置 → 场景执行 ✅
4. **错误处理** - 不存在的配置文件会显示详细的错误信息 ✅

### 📊 测试输出示例
```bash
[INFO] 开始加载配置...
[INFO] 加载基础配置: /root/benjamin/datakit_host/materiel_tools/datakit-automation/config/base
[INFO] 加载基础配置文件: base_config.sh
[INFO] 加载基础配置文件: state_config.sh
[INFO] 加载环境配置文件: /root/benjamin/datakit_host/materiel_tools/datakit-automation/config/env/benjamin.sh
[INFO] 配置加载完成
```

### ❌ 错误处理示例
```bash
[ERROR] 指定的配置文件不存在: /path/to/nonexistent.sh
[INFO] 尝试查找的路径:
[INFO]   - /root/benjamin/datakit_host/materiel_tools/datakit-automation/config/env/nonexistent.sh
[INFO]   - /root/benjamin/datakit_host/materiel_tools/datakit-automation/config/nonexistent.sh
```

## 🔧 测试建议

1. **测试配置传递** - 验证 `--config` 参数是否正确传递
2. **测试默认配置** - 验证默认配置加载是否正常工作
3. **测试错误处理** - 验证配置文件不存在时的错误处理
4. **测试向后兼容** - 验证现有脚本调用方式是否仍然有效 