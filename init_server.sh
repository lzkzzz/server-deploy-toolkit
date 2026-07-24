#!/bin/bash
#==========================================================================
# init_server.sh - 服务器初始化脚本
# 支持：CentOS 7/8/9 | Ubuntu 20.04/22.04/24.04
# 用途：裸机到手 → 一条命令完成基础初始化
#==========================================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # 无色

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#==========================================================================
# Step 1：检测操作系统
#==========================================================================
detect_os() {
    if grep -qi "ubuntu" /etc/os-release; then
        OS="ubuntu"
    elif grep -qi "centos" /etc/os-release; then
        OS="centos"
    elif grep -qi "rocky" /etc/os-release; then
        OS="centos"  # Rocky Linux 和 CentOS 命令一样
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    log_info "检测到系统类型：$OS"
}

#==========================================================================
# Step 2：安装基础软件包
#==========================================================================
install_base_packages() {
    log_info "正在安装基础软件包..."

    if [ "$OS" = "centos" ]; then
        yum install -y epel-release
        yum install -y \
            vim wget curl git net-tools lrzsz \
            htop tree unzip zip bash-completion \
            gcc gcc-c++ make
    elif [ "$OS" = "ubuntu" ]; then
        apt update -y
        apt install -y \
            vim wget curl git net-tools lrzsz \
            htop tree unzip zip bash-completion \
            build-essential
    fi

    log_info "基础软件包安装完成"
}

#==========================================================================
# Step 3：关闭 SELinux（仅 CentOS）
#==========================================================================
disable_selinux() {
    if [ "$OS" = "centos" ]; then
        log_info "正在关闭 SELinux..."
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        log_info "SELinux 已关闭"
    fi
}

#==========================================================================
# Step 4：配置防火墙
#==========================================================================
configure_firewall() {
    log_info "正在配置防火墙..."

    if [ "$OS" = "centos" ]; then
        systemctl start firewalld
        systemctl enable firewalld
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
    elif [ "$OS" = "ubuntu" ]; then
        ufw --force enable
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi

    log_info "防火墙配置完成（已开放 22, 80, 443 端口）"
}

#==========================================================================
# Step 5：创建运维账号
#==========================================================================
create_ops_user() {
    local username="ops"

    if id "$username" &>/dev/null; then
        log_warn "用户 $username 已存在，跳过创建"
    else
        log_info "正在创建运维账号 $username ..."
        useradd -m "$username"
        echo "$username:ops@2026" | chpasswd
        # 免密切 sudo
        echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$username
        chmod 440 /etc/sudoers.d/$username
        log_info "运维账号 $username 创建完成（密码: ops@2026，请登录后立即修改）"
    fi
}

#==========================================================================
# Step 6：设置时区 & 时间同步
#==========================================================================
configure_time() {
    log_info "正在设置时区..."
    timedatectl set-timezone Asia/Shanghai

    if [ "$OS" = "centos" ]; then
        yum install -y chrony
        systemctl start chronyd
        systemctl enable chronyd
    elif [ "$OS" = "ubuntu" ]; then
        systemctl restart systemd-timesyncd
    fi

    log_info "时区已设置为 Asia/Shanghai"
}

#==========================================================================
# Step 7：系统参数优化
#==========================================================================
tune_system() {
    log_info "正在优化系统参数..."

    # 修改 ulimit（文件句柄数）
    cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc  65535
* hard nproc  65535
EOF

    log_info "系统参数优化完成"
}

#==========================================================================
# 主流程
#==========================================================================
main() {
    echo "============================================"
    echo "  server-deploy-toolkit - 服务器初始化脚本"
    echo "============================================"
    echo ""

    detect_os
    install_base_packages
    disable_selinux
    configure_firewall
    create_ops_user
    configure_time
    tune_system

    echo ""
    echo "============================================"
    log_info "初始化完成！"
    echo ""
    echo "  运维账号：ops"
    echo "  密码：ops@2026（首次登录请修改）"
    echo "  已开放端口：22（SSH）80（HTTP）443（HTTPS）"
    echo "============================================"
}

main "$@"
