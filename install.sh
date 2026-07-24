#!/bin/bash
#==========================================================================
# install.sh - 一键安装本工具箱到任意服务器
# 用法：curl -sSL https://raw.githubusercontent.com/lzkzzz/server-deploy-toolkit/main/install.sh | bash
#==========================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

INSTALL_DIR="${INSTALL_DIR:-/opt/server-deploy-toolkit}"
REPO_URL="https://github.com/lzkzzz/server-deploy-toolkit.git"

echo "============================================"
echo "  server-deploy-toolkit - 安装程序"
echo "============================================"
echo ""

# 检测 root
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 或 sudo 运行此脚本"
    exit 1
fi

# 检测 OS
if grep -qi "ubuntu" /etc/os-release; then
    PKG_MANAGER="apt"
elif grep -qiE "centos|rocky" /etc/os-release; then
    PKG_MANAGER="yum"
else
    log_error "不支持的操作系统"
    exit 1
fi

# 安装依赖
log_info "安装依赖..."
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update -y && apt install -y git curl wget docker.io docker-compose-v2 mysql-client python3
else
    yum install -y epel-release
    yum install -y git curl wget docker docker-compose-plugin mysql python3
    systemctl start docker && systemctl enable docker
fi

# 克隆仓库
if [ -d "$INSTALL_DIR" ]; then
    log_info "目录已存在，执行更新：$INSTALL_DIR"
    cd "$INSTALL_DIR" && git pull origin main
else
    log_info "克隆仓库到：$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 初始化配置
if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    log_info "已创建 .env 配置文件，请按需修改：$INSTALL_DIR/.env"
fi

# 验证配置
cd "$INSTALL_DIR"

log_info "验证脚本语法..."
SYNTAX_OK=true
for f in *.sh; do
    if bash -n "$f" 2>/dev/null; then
        echo "  ✅ $f"
    else
        echo "  ❌ $f"
        SYNTAX_OK=false
    fi
done

# 创建备份目录
mkdir -p /var/backups/mysql /var/backups/deploy /var/log

# 添加别名（可选）
if ! grep -q "server-deploy-toolkit" /etc/profile 2>/dev/null; then
    cat >> /etc/profile <<'ALIAS'
# server-deploy-toolkit 别名
alias deploy='bash /opt/server-deploy-toolkit/deploy.sh'
alias health='python /opt/server-deploy-toolkit/health_check.py'
alias backup='bash /opt/server-deploy-toolkit/backup.sh'
alias logcheck='bash /opt/server-deploy-toolkit/log_analyzer.sh'
ALIAS
    log_info "已添加命令别名: deploy / health / backup / logcheck"
    log_info "重新登录后生效，或执行: source /etc/profile"
fi

echo ""
echo "============================================"
log_info "安装完成！"
echo ""
echo "  安装路径：$INSTALL_DIR"
echo "  配置文件：$INSTALL_DIR/.env"
echo ""
echo "  下一步："
echo "  1. 修改配置：vim $INSTALL_DIR/.env"
echo "  2. 初始化服务器：bash $INSTALL_DIR/init_server.sh"
echo "  3. 部署环境：cd $INSTALL_DIR && docker compose up -d"
echo "============================================"
