#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if ! grep -q -- "$pattern" "$file"; then
        fail "$message"
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if grep -q -- "$pattern" "$file"; then
        echo "---- $file ----" >&2
        cat "$file" >&2
        fail "$message"
    fi
}

log_info() { echo "[INFO] $*"; }
log_warning() { echo "[WARN] $*"; }
handle_error() {
    echo "[$1] $2" >&2
    return 1
}

create_fake_commands() {
    local bin_dir="$TEMP_DIR/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-u" ]; then
    shift 2
fi
exec "$@"
EOF

    cat > "$bin_dir/crontab" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
    -l)
        cat "$TEST_CRONTAB_STATE" 2>/dev/null || true
        ;;
    -r)
        : > "$TEST_CRONTAB_STATE"
        ;;
    *)
        cp "$1" "$TEST_CRONTAB_STATE"
        ;;
esac
EOF

    cat > "$bin_dir/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF

    chmod +x "$bin_dir/sudo" "$bin_dir/crontab" "$bin_dir/systemctl"
    export PATH="$bin_dir:$PATH"
}

test_skip_ops_token_check_removes_ops_cron_jobs() {
    create_fake_commands

    export TEST_CRONTAB_STATE="$TEMP_DIR/crontab_state"
    cat > "$TEST_CRONTAB_STATE" <<'EOF'
*/16 * * * * DATAKIT_ENV=ox bash -c "/opt/datakit/datakit_auto_installer.sh config-update"
*/6 * * * * DATAKIT_ENV=ox bash -c "/opt/datakit/datakit_auto_installer.sh health-check"
*/11 * * * * DATAKIT_ENV=ox bash -c "/opt/datakit/datakit_auto_installer.sh app-init"
5 * * * * echo keep-this-job
EOF

    export SCENARIO_PROJECT_ROOT="$TEMP_DIR/project"
    export DATAKIT_ENV="ox"
    export SKIP_OPS_TOKEN_CHECK="true"
    mkdir -p "$SCENARIO_PROJECT_ROOT"
    touch "$SCENARIO_PROJECT_ROOT/datakit_auto_installer.sh"

    source "$PROJECT_ROOT/install/setup_cron.sh"
    setup_cron_jobs

    assert_contains "$TEST_CRONTAB_STATE" "keep-this-job" "skip 模式应保留 datakit 用户已有的非 OPS 定时任务"
    assert_not_contains "$TEST_CRONTAB_STATE" "config-update" "skip 模式不应下发 config-update 定时任务"
    assert_not_contains "$TEST_CRONTAB_STATE" "health-check" "skip 模式不应下发 health-check 定时任务"
    assert_not_contains "$TEST_CRONTAB_STATE" "app-init" "skip 模式不应下发 app-init 定时任务"
}

test_normal_mode_installs_ops_cron_jobs() {
    create_fake_commands

    export TEST_CRONTAB_STATE="$TEMP_DIR/normal_crontab_state"
    cat > "$TEST_CRONTAB_STATE" <<'EOF'
5 * * * * echo keep-this-job
EOF

    export SCENARIO_PROJECT_ROOT="$TEMP_DIR/normal_project"
    export DATAKIT_ENV="ox"
    unset SKIP_OPS_TOKEN_CHECK
    mkdir -p "$SCENARIO_PROJECT_ROOT"
    touch "$SCENARIO_PROJECT_ROOT/datakit_auto_installer.sh"

    setup_cron_jobs

    assert_contains "$TEST_CRONTAB_STATE" "config-update" "正常模式应下发 config-update 定时任务"
    assert_contains "$TEST_CRONTAB_STATE" "health-check" "正常模式应下发 health-check 定时任务"
    assert_contains "$TEST_CRONTAB_STATE" "app-init" "正常模式应下发 app-init 定时任务"
    assert_contains "$TEST_CRONTAB_STATE" "keep-this-job" "正常模式应保留已有的非 OPS 定时任务"
}

test_verify_cron_jobs_skips_when_skip_ops_token_check_enabled() {
    create_fake_commands

    export TEST_CRONTAB_STATE="$TEMP_DIR/empty_crontab_state"
    : > "$TEST_CRONTAB_STATE"
    export SKIP_OPS_TOKEN_CHECK="1"

    source "$PROJECT_ROOT/core/validation.sh"

    if ! verify_cron_jobs; then
        fail "skip 模式下安装验证不应要求 datakit 用户存在 OPS 定时任务"
    fi
}

test_skip_ops_token_check_removes_ops_cron_jobs
test_normal_mode_installs_ops_cron_jobs
test_verify_cron_jobs_skips_when_skip_ops_token_check_enabled

echo "PASS: skip-ops-token-check disables datakit cron delivery"
