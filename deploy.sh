#!/bin/bash
#==========================================================================
# deploy.sh - 应用自动部署脚本
# 用法：bash deploy.sh --app=myapp --version=1.0.0
#==========================================================================

set -euo pipefail

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 默认参数
APP_NAME=""
VERSION="latest"
DEPLOY_DIR="/var/www"
BACKUP_DIR="/var/backups/deploy"
HEALTH_URL=""
RETRIES=5

#==========================================================================
# 参数解析
#==========================================================================
parse_args() {
    for arg in "$@"; do
        case $arg in
            --app=*)    APP_NAME="${arg#*=}" ;;
            --version=*) VERSION="${arg#*=}" ;;
            --dir=*)    DEPLOY_DIR="${arg#*=}" ;;
            --health=*) HEALTH_URL="${arg#*=}" ;;
            *)          log_error "未知参数: $arg"; exit 1 ;;
        esac
    done

    if [ -z "$APP_NAME" ]; then
        log_error "缺少 --app 参数，用法：bash deploy.sh --app=myapp"
        exit 1
    fi
}

#==========================================================================
# Step 1：部署前检查
#==========================================================================
pre_check() {
    log_info "开始部署前检查..."

    # 检查 Docker 是否运行
    if ! docker info &>/dev/null; then
        log_error "Docker 未运行"
        exit 1
    fi

    # 检查目标目录
    if [ ! -d "$DEPLOY_DIR" ]; then
        log_info "创建部署目录: $DEPLOY_DIR"
        mkdir -p "$DEPLOY_DIR"
    fi

    # 检查磁盘空间（至少 1GB）
    local available
    available=$(df "$DEPLOY_DIR" --output=avail | tail -1)
    if [ "$available" -lt 1048576 ]; then
        log_error "磁盘空间不足（<1GB），无法部署"
        exit 1
    fi

    log_info "部署前检查通过"
}

#==========================================================================
# Step 2：备份当前版本
#==========================================================================
backup_current() {
    if [ -d "$DEPLOY_DIR/$APP_NAME" ]; then
        log_info "正在备份当前版本..."
        mkdir -p "$BACKUP_DIR"
        local backup_name="${APP_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$BACKUP_DIR/$backup_name" -C "$DEPLOY_DIR" "$APP_NAME" 2>/dev/null || true
        log_info "备份完成: $BACKUP_DIR/$backup_name"
    else
        log_warn "未发现旧版本，跳过备份"
    fi
}

#==========================================================================
# Step 3：部署新版本
#==========================================================================
deploy_app() {
    log_info "正在部署 $APP_NAME 版本 $VERSION..."

    local app_dir="$DEPLOY_DIR/$APP_NAME"

    # 如果应用目录存在，先停服务
    if [ -f "$app_dir/docker-compose.yml" ]; then
        log_info "停止旧版服务..."
        docker compose -f "$app_dir/docker-compose.yml" down 2>/dev/null || true
    fi

    # 创建部署目录
    mkdir -p "$app_dir"

    # 处理部署包（tar.gz 或 docker-compose.yml）
    if [ -f "${APP_NAME}_${VERSION}.tar.gz" ]; then
        log_info "解压部署包..."
        tar -xzf "${APP_NAME}_${VERSION}.tar.gz" -C "$app_dir"
    fi

    # 启动 Docker Compose
    if [ -f "$app_dir/docker-compose.yml" ]; then
        log_info "启动 Docker Compose 服务..."
        docker compose -f "$app_dir/docker-compose.yml" up -d --wait 2>/dev/null || \
        docker compose -f "$app_dir/docker-compose.yml" up -d
    else
        log_info "无 docker-compose.yml，使用 docker run 启动..."
        docker run -d \
            --name "$APP_NAME" \
            --restart unless-stopped \
            "$APP_NAME:$VERSION"
    fi
}

#==========================================================================
# Step 4：健康检查
#==========================================================================
health_check() {
    if [ -z "$HEALTH_URL" ]; then
        log_info "未配置健康检查 URL，跳过"
        return 0
    fi

    log_info "开始健康检查: $HEALTH_URL"

    for i in $(seq 1 "$RETRIES"); do
        if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
            log_info "健康检查通过（第 $i 次尝试）"
            return 0
        fi
        log_warn "第 $i 次健康检查失败，等待 5 秒..."
        sleep 5
    done

    log_error "健康检查失败（共 $RETRIES 次尝试），开始回滚..."
    return 1
}

#==========================================================================
# Step 5：回滚（健康检查失败时触发）
#==========================================================================
rollback() {
    log_warn "正在回滚到上一个版本..."

    local latest_backup
    latest_backup=$(ls -t "$BACKUP_DIR"/${APP_NAME}_*.tar.gz 2>/dev/null | head -1)

    if [ -z "$latest_backup" ]; then
        log_error "未找到备份文件，无法自动回滚"
        exit 1
    fi

    log_info "从备份恢复: $latest_backup"
    rm -rf "$DEPLOY_DIR/$APP_NAME"
    tar -xzf "$latest_backup" -C "$DEPLOY_DIR"

    docker compose -f "$DEPLOY_DIR/$APP_NAME/docker-compose.yml" up -d 2>/dev/null || \
        log_warn "Docker Compose 启动失败，请手动检查"

    log_info "回滚完成"
}

#==========================================================================
# Step 6：清理
#==========================================================================
cleanup() {
    log_info "正在清理..."

    # 保留最近 5 个备份
    local backups
    backups=$(ls -t "$BACKUP_DIR"/${APP_NAME}_*.tar.gz 2>/dev/null | tail -n +6)
    if [ -n "$backups" ]; then
        echo "$backups" | xargs rm -f
        log_info "已清理过期备份"
    fi

    # 清理未使用的 Docker 镜像
    docker image prune -f 2>/dev/null || true

    log_info "清理完成"
}

#==========================================================================
# 主流程
#==========================================================================
main() {
    echo "============================================"
    echo "  server-deploy-toolkit - 应用部署脚本"
    echo "============================================"

    parse_args "$@"
    pre_check
    backup_current
    deploy_app

    if ! health_check; then
        rollback
        exit 1
    fi

    cleanup

    echo ""
    log_info "部署成功！$APP_NAME:$VERSION 已上线"
    echo "  部署路径: $DEPLOY_DIR/$APP_NAME"
    echo "  备份目录: $BACKUP_DIR"
}

main "$@"
