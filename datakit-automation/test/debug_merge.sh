#!/bin/bash

# 调试合并逻辑

set -euo pipefail

echo "=== 调试合并逻辑 ==="
echo ""

# 模拟mock数据中的access配置项
TEST_DATA='{
  "cswap-account-0-0": {
    "logging": [
      {
        "logType": "access",
        "logfiles": ["/data/processLog/*process.log"],
        "source": "ec2-golang-logging",
        "service": "cswap-account-0-0"
      },
      {
        "logType": "access",
        "logfiles": ["/data/processLog/*process.log", "/data/processLog/access/*process.log"],
        "source": "ec2-golang-logging",
        "service": "cswap-account-0-0"
      },
      {
        "logType": "access",
        "logfiles": ["/data/processLog/*process.log"],
        "source": "ec2-golang-logging",
        "service": "cswap-account-0-0",
        "tags": {
          "sink_project": "cswap-account-0-0",
          "service": "cswap-account-0-0"
        }
      }
    ]
  }
}'

echo "测试数据："
echo "$TEST_DATA" | jq '.'
echo ""

# 模拟分组逻辑
echo "=== 模拟分组逻辑 ==="
echo ""

logging_count=$(echo "$TEST_DATA" | jq -r '.["cswap-account-0-0"].logging | length')
echo "日志配置项数量: $logging_count"

# 解析所有日志配置项
declare -a logging_items=()
for i in $(seq 0 $((logging_count - 1))); do
    logging=$(echo "$TEST_DATA" | jq -r ".[\"cswap-account-0-0\"].logging[$i]" 2>/dev/null)
    if [ "$logging" != "null" ] && [ -n "$logging" ]; then
        logging_items+=("$logging")
        echo "配置项 $((i + 1)): $(echo "$logging" | jq -r '.logType')"
        echo "  tags: $(echo "$logging" | jq -r '.tags // "null"')"
        echo "  logfiles: $(echo "$logging" | jq -r '.logfiles | join(", ")')"
    fi
done

echo "有效配置项数量: ${#logging_items[@]}"
echo ""

# 模拟分组
declare -A config_groups=()
declare -A group_configs=()
group_counter=0

for logging in "${logging_items[@]}"; do
    # 提取关键字段
    log_type=$(echo "$logging" | jq -r ".logType" 2>/dev/null || echo "default")
    source=$(echo "$logging" | jq -r ".source" 2>/dev/null || echo "")
    tags=$(echo "$logging" | jq -r ".tags" 2>/dev/null || echo "null")
    
    echo "处理配置项: logType=$log_type, source=$source"
    echo "  tags: $tags"
    
    # 生成分组键
    if [ "$tags" = "null" ] || [ -z "$tags" ]; then
        group_key="no_tags_${log_type}_${source}"
        echo "  无tags分组键: $group_key"
    else
        tags_hash=$(echo "$tags" | jq -c '.' | md5sum | cut -d' ' -f1)
        group_key="with_tags_${log_type}_${source}_${tags_hash}"
        echo "  有tags分组键: $group_key (hash: ${tags_hash:0:8}...)"
    fi
    
    # 检查是否已存在该分组
    if [ -z "${config_groups[$group_key]:-}" ]; then
        group_counter=$((group_counter + 1))
        config_groups["$group_key"]="$group_counter"
        group_configs["$group_counter"]="[$logging]"
        echo "  创建新分组 $group_counter"
    else
        existing_group_id="${config_groups[$group_key]}"
        existing_configs="${group_configs[$existing_group_id]}"
        group_configs["$existing_group_id"]=$(echo "$existing_configs" | jq ". += [$logging]")
        echo "  添加到现有分组 $existing_group_id"
    fi
    echo ""
done

echo "分组结果:"
for group_id in $(seq 1 $group_counter); do
    group_configs_json="${group_configs[$group_id]}"
    group_count=$(echo "$group_configs_json" | jq 'length')
    echo "分组 $group_id: $group_count 个配置项"
    
    if [ "$group_count" -gt 1 ]; then
        echo "  合并后的logfiles:"
        all_logfiles=$(echo "$group_configs_json" | jq -r '.[].logfiles[]' | sort -u | jq -R . | jq -s .)
        echo "$all_logfiles" | jq -r '.[]' | sed 's/^/    /'
    fi
    echo ""
done

echo "=== 预期结果 ==="
echo "应该生成2个分组："
echo "1. 分组1：2个无tags的access配置项合并"
echo "   logfiles: ['/data/processLog/*process.log', '/data/processLog/access/*process.log']"
echo "2. 分组2：1个有tags的access配置项"
echo "   logfiles: ['/data/processLog/*process.log']"
echo "" 