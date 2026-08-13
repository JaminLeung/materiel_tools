#!/bin/bash

#=================================================
# Tail sampling configuration helpers
#=================================================

tail_sampling_is_enabled() {
    local enable
    enable="$(get_global_state 'TAIL_SAMPLING_ENABLE')"
    [[ "$enable" == "true" || "$enable" == "1" || "$enable" == "yes" ]]
}

tail_sampling_template_dir() {
    local project_root
    project_root="$(get_global_state 'PROJECT_ROOT')"
    if [ -z "$project_root" ]; then
        project_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    fi
    printf '%s/config/tail_sampling' "$project_root"
}

tail_sampling_append_token() {
    local endpoint
    local token
    endpoint="$1"
    token="$(get_global_state 'WORKSPACE_TOKEN')"

    [ -n "$endpoint" ] || return 1

    if [[ "$endpoint" == *"?token="* || "$endpoint" == *"&token="* || -z "$token" ]]; then
        printf '%s' "$endpoint"
    elif [[ "$endpoint" == *"?"* ]]; then
        printf '%s&token=%s' "$endpoint" "$token"
    else
        printf '%s?token=%s' "$endpoint" "$token"
    fi
}

tail_sampling_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

tail_sampling_lines_to_json() {
    jq -Rsc 'split("\n") | map(select(length > 0)) | if length > 0 then . else error("empty endpoint list") end'
}

tail_sampling_build_endpoints_json() {
    local endpoints
    endpoints="$(get_global_state 'TAIL_SAMPLING_ENDPOINT')"

    [ -n "$endpoints" ] || return 1

    if [[ "$endpoints" =~ ^[[:space:]]*\[ ]]; then
        printf '%s' "$endpoints" |
            jq -r 'if type == "array" then .[] | tostring else error("TAIL_SAMPLING_ENDPOINT JSON value must be a list") end' |
            while IFS= read -r endpoint; do
                endpoint="$(tail_sampling_trim "$endpoint")"
                [ -n "$endpoint" ] || continue
                tail_sampling_append_token "$endpoint"
                printf '\n'
            done | tail_sampling_lines_to_json
        return $?
    fi

    local endpoint
    local IFS=','
    for endpoint in $endpoints; do
        endpoint="$(tail_sampling_trim "$endpoint")"
        [ -n "$endpoint" ] || continue
        tail_sampling_append_token "$endpoint"
        printf '\n'
    done | tail_sampling_lines_to_json
}

tail_sampling_write_file_if_changed() {
    local target="$1"
    local content="$2"

    mkdir -p "$(dirname "$target")"
    if [ -f "$target" ] && cmp -s "$target" "$content"; then
        log_info "尾采样配置相同，跳过更新: $target"
        return 1
    fi

    cp "$content" "$target"
    chown datakit:datakit "$target" 2>/dev/null || true
    chmod 644 "$target"
    log_info "尾采样配置已更新: $target"
    return 0
}

tail_sampling_render_rules() {
    local template_file="$1"
    local target_file="$2"
    local ttl="$3"
    local group_key="$4"
    local rate="$5"

    awk -v ttl="$ttl" -v group_key="$group_key" -v rate="$rate" '
        /^data_ttl = / { print "data_ttl = \"" ttl "\""; next }
        /^group_key = / { print "group_key = \"" group_key "\""; next }
        /^rate = / { print "rate = " rate; next }
        { print }
    ' "$template_file" > "$target_file"
}

configure_datakit_tail_sampling() {
    log_info "配置 DataKit 尾部采样..."

    local datakit_conf="${CONFIG_UPDATE_DATAKIT_CONF:-/usr/local/datakit/conf.d/datakit.conf}"
    local conf_dir="${CONFIG_UPDATE_DATAKIT_CONF_DIR:-/usr/local/datakit/conf.d}"
    local local_config_dir
    local metric_config_file
    local tail_config_file
    local profile
    local template_dir
    local aggr_template
    local tail_template
    local otel_template
    local endpoint
    local endpoints_json
    local ttl
    local group_key
    local rate
    local max_raw_body_size
    local changed=false

    local_config_dir="$(get_global_state 'TAIL_SAMPLING_LOCAL_CONFIG_DIR')"
    metric_config_file="$(get_global_state 'TAIL_SAMPLING_METRIC_CONFIG_FILE')"
    tail_config_file="$(get_global_state 'TAIL_SAMPLING_CONFIG_FILE')"
    profile="$(get_global_state 'TAIL_SAMPLING_PROFILE')"
    ttl="$(get_global_state 'TAIL_SAMPLING_TTL')"
    group_key="$(get_global_state 'TAIL_SAMPLING_GROUP_KEY')"
    rate="$(get_global_state 'TAIL_SAMPLING_RATE')"
    max_raw_body_size="$(get_global_state 'TAIL_SAMPLING_MAX_RAW_BODY_SIZE')"

    local_config_dir="${local_config_dir:-/usr/local/datakit/conf.d/aggr}"
    metric_config_file="${metric_config_file:-aggr.toml}"
    tail_config_file="${tail_config_file:-tail-sampling.toml}"
    profile="${profile:-5pct}"
    ttl="${ttl:-1m}"
    group_key="${group_key:-trace_id}"
    rate="${rate:-0.05}"
    max_raw_body_size="${max_raw_body_size:-1048576}"

    if ! tail_sampling_is_enabled; then
        log_info "尾部采样未启用，跳过配置"
        return 0
    fi

    endpoint="$(get_global_state 'TAIL_SAMPLING_ENDPOINT')"
    if [ -z "$endpoint" ]; then
        handle_error "CONFIG_ERROR" "尾部采样已启用但未配置 TAIL_SAMPLING_ENDPOINT" "ERROR" "false"
        return 1
    fi

    endpoints_json="$(tail_sampling_build_endpoints_json)" || {
        handle_error "CONFIG_ERROR" "尾部采样 endpoints 生成失败" "ERROR" "false"
        return 1
    }

    template_dir="$(tail_sampling_template_dir)"
    aggr_template="$template_dir/aggr.toml"
    tail_template="$template_dir/tail-sampling-${profile}.toml"
    otel_template="$template_dir/opentelemetry-tail-sampling.conf"

    [ -f "$aggr_template" ] || {
        handle_error "FILE_ERROR" "尾部采样 aggr 模板不存在: $aggr_template" "ERROR" "false"
        return 1
    }
    [ -f "$tail_template" ] || {
        handle_error "FILE_ERROR" "尾部采样规则模板不存在: $tail_template" "ERROR" "false"
        return 1
    }
    [ -f "$otel_template" ] || {
        handle_error "FILE_ERROR" "尾部采样 OpenTelemetry 模板不存在: $otel_template" "ERROR" "false"
        return 1
    }

    [ -f "$datakit_conf" ] || {
        handle_error "FILE_ERROR" "Datakit 配置文件不存在: $datakit_conf" "ERROR" "false"
        return 1
    }

    local current_config
    current_config="$(read_toml_config "$datakit_conf")" || {
        handle_error "FILE_ERROR" "读取 Datakit 配置文件失败: $datakit_conf" "ERROR" "false"
        return 1
    }

    local updated_config
    updated_config="$current_config"
    updated_config="$(echo "$updated_config" | jq --argjson endpoints "$endpoints_json" '.aggregator.endpoints = $endpoints')"
    updated_config="$(echo "$updated_config" | jq '.aggregator.timeout = "0s"')"
    updated_config="$(echo "$updated_config" | jq --argjson max_raw_body_size "$max_raw_body_size" '.aggregator.max_raw_body_size = $max_raw_body_size')"
    updated_config="$(echo "$updated_config" | jq '.aggregator.use_local_config = true')"
    updated_config="$(echo "$updated_config" | jq --arg local_config_dir "$local_config_dir" '.aggregator.local_config_dir = $local_config_dir')"
    updated_config="$(echo "$updated_config" | jq --arg metric_config_file "$metric_config_file" '.aggregator.local_metric_config_file = $metric_config_file')"
    updated_config="$(echo "$updated_config" | jq --arg tail_config_file "$tail_config_file" '.aggregator.local_tail_sampling_config_file = $tail_config_file')"

    if [ "$updated_config" != "$current_config" ]; then
        update_toml_config "$datakit_conf" "$updated_config" || {
            handle_error "CONFIG_ERROR" "更新 Datakit 尾部采样主配置失败" "ERROR" "false"
            return 1
        }
        changed=true
    else
        log_info "Datakit 尾部采样主配置无需更新"
    fi

    mkdir -p "$local_config_dir" "$conf_dir/opentelemetry"

    if tail_sampling_write_file_if_changed "$local_config_dir/$metric_config_file" "$aggr_template"; then
        changed=true
    fi

    local rendered_tail_config
    rendered_tail_config="$(mktemp /tmp/datakit-tail-sampling.XXXXXX)"
    tail_sampling_render_rules "$tail_template" "$rendered_tail_config" "$ttl" "$group_key" "$rate"
    if tail_sampling_write_file_if_changed "$local_config_dir/$tail_config_file" "$rendered_tail_config"; then
        changed=true
    fi
    rm -f "$rendered_tail_config"

    if tail_sampling_write_file_if_changed "$conf_dir/opentelemetry/opentelemetry.conf" "$otel_template"; then
        changed=true
    fi

    chown -R datakit:datakit "$local_config_dir" "$conf_dir/opentelemetry" 2>/dev/null || true
    chmod 755 "$local_config_dir" "$conf_dir/opentelemetry"

    if [ "$changed" = "true" ]; then
        CONFIG_CHANGED=true
        set_global_state "CONFIG_CHANGED" "true"
        log_info "DataKit 尾部采样配置完成，检测到配置变更"
    else
        log_info "DataKit 尾部采样配置完成，无配置变更"
    fi

    return 0
}
