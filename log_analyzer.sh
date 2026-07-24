#!/bin/bash
#==========================================================================
# log_analyzer.sh - 日志分析与异常检测
# 用法：
#   bash log_analyzer.sh --type=nginx  --hours=1       # 最近1小时 Nginx 日志
#   bash log_analyzer.sh --type=system --critical       # 系统关键错误
#   bash log_analyzer.sh --type=docker --service=mysql  # 指定容器日志
#==========================================================================

set -euo pipefail

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# 默认参数
LOG_TYPE="system"
HOURS=1
TOP_N=10
CRITICAL_ONLY=false
DOCKER_SERVICE=""

#==========================================================================
# 参数解析
#==========================================================================
parse_args() {
    for arg in "$@"; do
        case $arg in
            --type=*)     LOG_TYPE="${arg#*=}" ;;
            --hours=*)    HOURS="${arg#*=}" ;;
            --top=*)      TOP_N="${arg#*=}" ;;
            --critical)   CRITICAL_ONLY=true ;;
            --service=*)  DOCKER_SERVICE="${arg#*=}" ;;
            *)            echo "未知参数: $arg"; exit 1 ;;
        esac
    done
}

#==========================================================================
# 时间筛选
#==========================================================================
since_time() {
    if [ "$(uname)" = "Darwin" ]; then
        date -v-${HOURS}H "+%Y-%m-%d %H:%M"
    else
        date -d "${HOURS} hours ago" "+%Y-%m-%d %H:%M"
    fi
}

#==========================================================================
# Nginx 日志分析
#==========================================================================
analyze_nginx() {
    local log_file="/var/log/nginx/access.log"
    if [ ! -f "$log_file" ]; then
        log_file=$(docker inspect nginx 2>/dev/null | grep -o '"LogPath":"[^"]*"' | cut -d'"' -f4 | head -1)
    fi

    if [ ! -f "$log_file" ]; then
        echo "未找到 Nginx 日志文件"
        return 1
    fi

    echo "══════════ Nginx 状态码统计 ══════════"

    # 4xx/5xx 错误数
    awk -v since="$(since_time)" '
        $4 " " $5 >= since {
            status[$9]++
            total++
        }
        END {
            for (code in status)
                printf "  HTTP %s: %d (%.1f%%)\n", code, status[code], (status[code]/total)*100
        }' "$log_file" | sort -t: -k2 -rn

    echo ""
    echo "══════════ 高频访问 IP TOP ${TOP_N} ══════════"

    awk -v since="$(since_time)" '
        $4 " " $5 >= since { ip[$1]++ }
        END { for (i in ip) print ip[i], i }' "$log_file" \
        | sort -rn | head -n "$TOP_N" | awk '{printf "  %-20s %d 次\n", $2, $1}'

    echo ""
    echo "══════════ 慢请求（>2s） ══════════"

    awk -v since="$(since_time)" '
        $4 " " $5 >= since && $NF > 2 {
            count++
            printf "  [%s] %s %s (%s)\n", substr($4,2), $7, $NF, $1
        }
        END { if (!count) print "  ✅ 无慢请求" }' "$log_file" | head -n "$TOP_N"
}

#==========================================================================
# 系统日志分析
#==========================================================================
analyze_system() {
    echo "══════════ 系统关键错误 ══════════"

    # 搜索内核错误、OOM、磁盘错误
    if [ "$CRITICAL_ONLY" = true ]; then
        journalctl --since "$(since_time)" -p err..emerg --no-pager 2>/dev/null | tail -n "$TOP_N" | \
            while IFS= read -r line; do echo "  🔴 $line"; done
    else
        journalctl --since "$(since_time)" -p warning..emerg --no-pager 2>/dev/null | tail -n "$TOP_N" | \
            while IFS= read -r line; do echo "  ⚠️  $line"; done
    fi

    echo ""
    echo "══════════ 登录统计 ══════════"

    # 成功登录
    echo "  最近登录:"
    last -n 5 2>/dev/null | awk '{printf "  %-12s %s %s %s %s\n", $1, $4, $5, $6, $7}'

    echo ""
    echo "  失败登录 TOP ${TOP_N}:"
    if [ -f /var/log/auth.log ]; then
        grep "Failed password" /var/log/auth.log 2>/dev/null | \
            awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -n "$TOP_N" | \
            awk '{printf "  %-20s %d 次\n", $2, $1}'
    elif [ -f /var/log/secure ]; then
        grep "Failed password" /var/log/secure 2>/dev/null | \
            awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -n "$TOP_N" | \
            awk '{printf "  %-20s %d 次\n", $2, $1}'
    else
        echo "  未找到认证日志"
    fi
}

#==========================================================================
# Docker 容器日志分析
#==========================================================================
analyze_docker() {
    local svc="${DOCKER_SERVICE:-nginx}"

    echo "══════════ Docker: $svc 日志分析 ══════════"

    # 容器是否运行
    if docker ps --format '{{.Names}}' | grep -q "$svc"; then
        echo "  ✅ 容器 $svc 运行中"
    else
        echo "  🔴 容器 $svc 未运行"
        return
    fi

    echo ""
    echo "  最近 ${HOURS} 小时日志（最后 $TOP_N 条）:"

    docker logs --since "${HOURS}h" "$svc" 2>&1 | tail -n "$TOP_N" | \
        while IFS= read -r line; do
            if echo "$line" | grep -qiE "error|fatal|critical|panic"; then
                echo "  🔴 $line"
            elif echo "$line" | grep -qiE "warn|warning"; then
                echo "  ⚠️  $line"
            else
                echo "  ℹ️  $line"
            fi
        done
}

#==========================================================================
# MySQL 慢查询分析
#==========================================================================
analyze_mysql_slow() {
    echo "══════════ MySQL 慢查询分析 ══════════"

    local slow_log
    slow_log=$(docker exec mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD:-Root@2026}" \
        -N -e "SHOW VARIABLES LIKE 'slow_query_log_file';" 2>/dev/null | awk '{print $2}')

    if [ -z "$slow_log" ]; then
        echo "  ⚠️  无法读取 MySQL 慢查询日志（容器未运行或密码错误）"
        return
    fi

    docker exec mysql cat "$slow_log" 2>/dev/null | \
        grep -c "Query_time" || echo "  0" | \
        awk '{print "  最近慢查询数: " $1}'
}

#==========================================================================
# 主流程
#==========================================================================
main() {
    echo "════════════════════════════════════════"
    echo "  日志分析报告"
    echo "  时间范围: 最近 ${HOURS} 小时"
    echo "  类型: $LOG_TYPE"
    echo "════════════════════════════════════════"
    echo ""

    case "$LOG_TYPE" in
        nginx)  analyze_nginx ;;
        system) analyze_system ;;
        docker) analyze_docker ;;
        mysql)  analyze_mysql_slow ;;
        all)
            analyze_system
            echo ""; echo ""
            analyze_nginx
            echo ""; echo ""
            analyze_docker
            ;;
        *) echo "不支持的日志类型: $LOG_TYPE（支持: nginx/system/docker/mysql/all）" ;;
    esac

    echo ""
    echo "══════════ 报告结束 ═══════════"
}

parse_args "$@"
main
