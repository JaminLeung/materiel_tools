#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

CONFIG_UPDATE_DATAKIT_CONF_DIR="$TEST_ROOT/conf.d"
CONFIG_UPDATE_DATAKIT_CONF="$CONFIG_UPDATE_DATAKIT_CONF_DIR/datakit.conf"
mkdir -p "$CONFIG_UPDATE_DATAKIT_CONF_DIR"

cat > "$CONFIG_UPDATE_DATAKIT_CONF" <<'TOML'
[dataway]
  urls = ["https://example.com?token=main-token"]

[global_host_tags]
  account_name = "test"
TOML

set_global_state() {
    eval "STATE_$1=\$2"
}

get_global_state() {
    eval "printf '%s' \"\${STATE_$1:-}\""
}

log_info() {
    :
}

handle_error() {
    printf '%s\n' "$*" >&2
    return 1
}

read_toml_config() {
    python3 - "$1" <<'PY'
import json
import sys

data = {}
section = None

def parse_value(raw):
    raw = raw.strip()
    if raw in ("true", "false"):
        return raw == "true"
    if raw.startswith("[") and raw.endswith("]"):
        items = raw[1:-1].strip()
        if not items:
            return []
        return [parse_value(item.strip()) for item in items.split(",")]
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    try:
        if "." in raw:
            return float(raw)
        return int(raw)
    except ValueError:
        return raw

with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            data.setdefault(section, {})
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        target = data.setdefault(section, {}) if section else data
        target[key.strip()] = parse_value(value)

print(json.dumps(data))
PY
}

update_toml_config() {
    python3 - "$1" "$2" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.loads(sys.argv[2])

def scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(scalar(item) for item in value) + "]"
    return json.dumps(str(value))

with open(path, "w", encoding="utf-8") as f:
    for key, value in data.items():
        if not isinstance(value, dict):
            f.write(f"{key} = {scalar(value)}\n")
            continue
        f.write(f"[{key}]\n")
        for child_key, child_value in value.items():
            f.write(f"  {child_key} = {scalar(child_value)}\n")
        f.write("\n")
PY
}

CONFIG_CHANGED=false
set_global_state "PROJECT_ROOT" "$PROJECT_ROOT"
set_global_state "TAIL_SAMPLING_ENABLE" "false"
set_global_state "TAIL_SAMPLING_ENDPOINT" ""
set_global_state "TAIL_SAMPLING_RATE" "0.05"
set_global_state "TAIL_SAMPLING_TTL" "1m"
set_global_state "TAIL_SAMPLING_GROUP_KEY" "trace_id"
set_global_state "TAIL_SAMPLING_PROFILE" "5pct"
set_global_state "TAIL_SAMPLING_MAX_RAW_BODY_SIZE" "1048576"
set_global_state "TAIL_SAMPLING_LOCAL_CONFIG_DIR" "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr"
set_global_state "TAIL_SAMPLING_METRIC_CONFIG_FILE" "aggr.toml"
set_global_state "TAIL_SAMPLING_CONFIG_FILE" "tail-sampling.toml"
set_global_state "WORKSPACE_TOKEN" "workspace-token"

source "$PROJECT_ROOT/core/tail_sampling.sh"

configure_datakit_tail_sampling
test ! -d "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr"

set_global_state "TAIL_SAMPLING_ENABLE" "true"
set_global_state "TAIL_SAMPLING_ENDPOINT" "http://tail-proxy.example.internal:9528"
set_global_state "TAIL_SAMPLING_RATE" "0.07"
set_global_state "TAIL_SAMPLING_TTL" "2m"

configure_datakit_tail_sampling

read_toml_config "$CONFIG_UPDATE_DATAKIT_CONF" | jq -e '
  .aggregator.endpoints == ["http://tail-proxy.example.internal:9528?token=workspace-token"] and
  .aggregator.use_local_config == true and
  .aggregator.local_config_dir == "'"$CONFIG_UPDATE_DATAKIT_CONF_DIR"'/aggr" and
  .aggregator.local_tail_sampling_config_file == "tail-sampling.toml"
' >/dev/null

test -f "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr/aggr.toml"
test -f "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr/tail-sampling.toml"
test -f "$CONFIG_UPDATE_DATAKIT_CONF_DIR/opentelemetry/opentelemetry.conf"
grep -q 'data_ttl = "2m"' "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr/tail-sampling.toml"
grep -q 'rate = 0.07' "$CONFIG_UPDATE_DATAKIT_CONF_DIR/aggr/tail-sampling.toml"
grep -q 'sampling_rate = 1.0' "$CONFIG_UPDATE_DATAKIT_CONF_DIR/opentelemetry/opentelemetry.conf"

echo "TAIL_SAMPLING_CONFIG_TEST_OK"
