#!/bin/bash
#==========================================================================
# test_runner.sh - 脚本自测套件
# 测试所有脚本的语法正确性和关键函数行为
# 用法：bash test_runner.sh
#==========================================================================

# 注意：测试脚本不用 set -e，grep 找不到匹配项时返回非零不会中断

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

PASS=0
FAIL=0
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

log_pass() { echo -e "  ${GREEN}✅ PASS${NC} $1"; ((PASS++)); }
log_fail() { echo -e "  ${RED}❌ FAIL${NC} $1"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}━━━ $1 ━━━${NC}"; }

#==========================================================================
# 测试 1：所有 Shell 脚本语法检查
#==========================================================================
test_shell_syntax() {
    log_info "Shell 语法检查"

    for f in "$REPO_DIR"/*.sh; do
        local name
        name=$(basename "$f")
        if bash -n "$f" 2>/dev/null; then
            log_pass "$name"
        else
            log_fail "$name"
        fi
    done
}

#==========================================================================
# 测试 2：Python 语法检查
#==========================================================================
test_python_syntax() {
    log_info "Python 语法检查"

    local py_cmd
    py_cmd=$(command -v python3 || command -v python || echo "")
    if [ -z "$py_cmd" ]; then
        log_fail "health_check.py (Python 未安装)"
        return
    fi

    if $py_cmd -m py_compile "$REPO_DIR/health_check.py" 2>/dev/null; then
        log_pass "health_check.py"
    else
        log_fail "health_check.py"
    fi
}

#==========================================================================
# 测试 3：shebang 检查（所有脚本必须有 #!/bin/bash 或 #!/usr/bin/env python3）
#==========================================================================
test_shebang() {
    log_info "Shebang 检查"

    for f in "$REPO_DIR"/*.sh; do
        local name first_line
        name=$(basename "$f")
        first_line=$(head -1 "$f")
        if echo "$first_line" | grep -qE '^#!/bin/(bash|sh)'; then
            log_pass "$name"
        else
            log_fail "$name (缺少 shebang)"
        fi
    done

    if head -1 "$REPO_DIR/health_check.py" | grep -q '^#!/usr/bin/env python3'; then
        log_pass "health_check.py"
    else
        log_fail "health_check.py (缺少 shebang)"
    fi
}

#==========================================================================
# 测试 4：关键函数存在性检查
#==========================================================================
test_functions() {
    log_info "关键函数检查"

    # init_server.sh 必须有 detect_os / main
    for func in detect_os install_base_packages disable_selinux configure_firewall create_ops_user main; do
        if grep -q "^${func}()" "$REPO_DIR/init_server.sh"; then
            log_pass "init_server.sh: $func"
        else
            log_fail "init_server.sh: $func (未找到)"
        fi
    done

    # backup.sh 必须有 full_backup / cleanup_old_backups / main
    for func in full_backup cleanup_old_backups main; do
        if grep -q "^${func}()" "$REPO_DIR/backup.sh"; then
            log_pass "backup.sh: $func"
        else
            log_fail "backup.sh: $func (未找到)"
        fi
    done

    # health_check.py 必须有 run_all_checks / main
    for func in check_http check_tcp check_process run_all_checks main; do
        if grep -q "def ${func}" "$REPO_DIR/health_check.py"; then
            log_pass "health_check.py: $func"
        else
            log_fail "health_check.py: $func (未找到)"
        fi
    done
}

#==========================================================================
# 测试 5：配置文件完整性检查
#==========================================================================
test_configs() {
    log_info "配置文件检查"

    local configs=(
        "nginx/nginx.conf"
        "nginx/conf.d/default.conf"
        "php/php.ini"
        "mysql/conf.d/my.cnf"
        "mysql/init/init.sql"
        "redis/redis.conf"
        "docker-compose.yml"
        ".env.example"
    )

    for cfg in "${configs[@]}"; do
        if [ -f "$REPO_DIR/$cfg" ]; then
            log_pass "$cfg"
        else
            log_fail "$cfg (文件缺失)"
        fi
    done
}

#==========================================================================
# 测试 6：set -e 检查（重要脚本应该有 set -e）
#==========================================================================
test_error_handling() {
    log_info "错误处理检查"

    local critical_scripts=("init_server.sh" "backup.sh" "deploy.sh" "log_analyzer.sh" "install.sh")
    for s in "${critical_scripts[@]}"; do
        if grep -q "^set -e" "$REPO_DIR/$s" || grep -q "^set -euo pipefail" "$REPO_DIR/$s"; then
            log_pass "$s: set -e"
        else
            log_fail "$s: 缺少 set -e（没有错误退出机制）"
        fi
    done
}

#==========================================================================
# 主流程
#==========================================================================
main() {
    echo "════════════════════════════════════════"
    echo "  server-deploy-toolkit - 自动化自测"
    echo "════════════════════════════════════════"
    echo ""

    test_shell_syntax
    test_python_syntax
    test_shebang
    test_functions
    test_configs
    test_error_handling

    echo ""
    echo "════════════════════════════════════════"
    echo "  结果：${PASS} 通过 / $((PASS + FAIL)) 总计"
    if [ "$FAIL" -gt 0 ]; then
        echo -e "  ${RED}${FAIL} 项未通过${NC}"
        exit 1
    else
        echo -e "  ${GREEN}全部通过 ✅${NC}"
    fi
    echo "════════════════════════════════════════"
}

main
