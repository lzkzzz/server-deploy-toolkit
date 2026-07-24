#!/bin/bash
#==========================================================================
# backup.sh - MySQL 数据库自动备份脚本
# 用法：
#   bash backup.sh                   # 全量备份
#   bash backup.sh --binlog          # 全量 + binlog 备份
#   定时任务：0 2 * * * bash /opt/server-deploy-toolkit/backup.sh
#==========================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 配置
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-Root@2026}"
DB_NAMES="${DB_NAMES:---all-databases}"    # 备份哪些库，默认全部
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"       # 保留天数

BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"

#==========================================================================
# 全量备份（mysqldump）
#==========================================================================
full_backup() {
    log_info "开始全量备份..."

    local dump_file="$BACKUP_DIR/${BACKUP_NAME}.sql"

    # 备份结构+数据
    if [ "$DB_NAMES" = "--all-databases" ]; then
        mysqldump \
            -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
            --all-databases \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --set-gtid-purged=OFF \
            > "$dump_file"
    else
        mysqldump \
            -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
            --databases $DB_NAMES \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --set-gtid-purged=OFF \
            > "$dump_file"
    fi

    # 压缩
    gzip -f "$dump_file"
    local size
    size=$(du -sh "$dump_file.gz" | cut -f1)
    log_info "全量备份完成: $dump_file.gz ($size)"
}

#==========================================================================
# Binlog 备份（增量）
#==========================================================================
binlog_backup() {
    log_info "开始 binlog 备份..."

    # 刷新 binlog，生成新的日志文件
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
        -e "FLUSH BINARY LOGS;" 2>/dev/null

    # 读取 binlog 目录
    local binlog_dir
    binlog_dir=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
        -N -e "SHOW VARIABLES LIKE 'log_bin_basename';" 2>/dev/null | awk '{print $2}')
    binlog_dir=$(dirname "$binlog_dir")

    if [ ! -d "$binlog_dir" ]; then
        log_warn "找不到 binlog 目录，跳过"
        return
    fi

    # 复制 binlog 文件
    local binlog_backup_dir="$BACKUP_DIR/binlog_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$binlog_backup_dir"
    cp "$binlog_dir"/mysql-bin.* "$binlog_backup_dir/" 2>/dev/null || true

    # 获取当前 binlog 位置（不复制正在写入的）
    local current_binlog
    current_binlog=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
        -N -e "SHOW MASTER STATUS;" 2>/dev/null | awk '{print $1}')
    rm -f "$binlog_backup_dir/$current_binlog"

    log_info "Binlog 备份完成: $binlog_backup_dir"
}

#==========================================================================
# 清理过期备份
#==========================================================================
cleanup_old_backups() {
    log_info "清理 ${RETENTION_DAYS} 天前的备份..."

    find "$BACKUP_DIR" -name "*.sql.gz" -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "binlog_*" -type d -mtime "+$RETENTION_DAYS" \
        -exec rm -rf {} \; 2>/dev/null || true

    log_info "清理完成"
}

#==========================================================================
# 备份完整性校验
#==========================================================================
verify_backup() {
    local latest
    latest=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)

    if [ -z "$latest" ]; then
        log_warn "未找到备份文件，跳过校验"
        return
    fi

    # 用 gunzip -t 测试压缩文件完整性
    if gunzip -t "$latest" 2>/dev/null; then
        log_info "备份校验通过: $latest"
    else
        log_error "备份文件损坏: $latest"
    fi
}

#==========================================================================
# 主流程
#==========================================================================
main() {
    echo "============================================"
    echo "  server-deploy-toolkit - 数据库备份脚本"
    echo "============================================"

    full_backup

    if [[ "${1:-}" == "--binlog" ]]; then
        binlog_backup
    fi

    verify_backup
    cleanup_old_backups

    echo ""
    log_info "备份任务完成"
    echo "  备份目录: $BACKUP_DIR"
    echo "  保留天数: $RETENTION_DAYS 天"
    echo ""
    echo "  定时任务示例:"
    echo "  crontab -e"
    echo "  0 2 * * * bash $(realpath "$0") >> /var/log/backup.log 2>&1"
}

main "$@"
