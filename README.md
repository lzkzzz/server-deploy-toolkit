# server-deploy-toolkit

服务器自动化部署与运维工具箱——把实施工程师的手工活写成脚本，一行命令搞定。

## 工作流程

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────┐
│  裸机服务器    │───▶│  init_server.sh   │───▶│  基础环境就绪  │
│  (CentOS/Ubuntu)│    │  装包·关SELinux·防火墙·建账号│    │  已装Docker   │
└──────────────┘    └──────────────────┘    └──────┬───────┘
                                                   │
                                          docker compose up -d
                                                   │
┌──────────────┐    ┌──────────────────┐    ┌──────▼───────┐
│  应用上线     │◀───│   deploy.sh       │◀───│  LNMP 环境    │
│  + 自动回滚   │    │  备份→部署→健康检查→回滚│    │ Nginx+MySQL+Redis+PHP
└──────────────┘    └──────────────────┘    └──────┬───────┘
                                                   │
                                    ┌──────────────┼──────────────┐
                                    │              │              │
                              ┌─────▼─────┐ ┌──────▼──────┐ ┌────▼─────┐
                              │backup.sh   │ │health_check │ │log_      │
                              │ 数据库备份  │ │ 健康监控+告警│ │analyzer  │
                              │ +binlog    │ │ HTTP/TCP/进程│ │ 日志分析  │
                              └────────────┘ └─────────────┘ └──────────┘
```

## 功能列表

| 脚本 | 行数 | 功能 | 面试亮点 |
|------|------|------|---------|
| `init_server.sh` | 160 | 服务器初始化（装包/关SELinux/配防火墙/建账号/调优） | 双系统兼容、生产级 Shell |
| `deploy.sh` | 170 | 应用自动部署+健康检查+自动回滚 | 蓝绿部署模式 |
| `health_check.py` | 180 | 多线程健康监控（HTTP/TCP/进程）+钉钉/企微告警 | Python 多线程+Webhook |
| `backup.sh` | 130 | MySQL 全量+ binlog 增量备份+自动清理 | 数据安全意识 |
| `log_analyzer.sh` | 150 | 日志分析（Nginx 状态码/IP/慢请求、系统错误、Docker） | 生产排障能力 |
| `docker-compose.yml` | — | LNMP 容器编排+健康检查+资源限制 | Docker 实战 |

## 快速开始

```bash
# 1. 初始化服务器（裸 CentOS/Ubuntu）
sudo bash init_server.sh

# 2. 部署 LNMP 环境
docker compose up -d

# 3. 部署应用
bash deploy.sh --app=myapp --version=1.0.0

# 4. 定时任务（日常运维）
0 2 * * * bash /opt/server-deploy-toolkit/backup.sh
*/5 * * * * python /opt/server-deploy-toolkit/health_check.py --json --alert
0 8 * * * bash /opt/server-deploy-toolkit/log_analyzer.sh --type=all
```

## 项目结构

```
server-deploy-toolkit/
├── init_server.sh            # 服务器初始化（160行）
├── docker-compose.yml        # LNMP 容器编排
├── deploy.sh                 # 应用自动部署+回滚（170行）
├── health_check.py           # 健康监控+告警（180行）
├── backup.sh                 # MySQL 备份+清理（130行）
├── log_analyzer.sh           # 日志分析（150行）
├── .github/workflows/ci.yml  # CI 自动检查脚本语法
├── nginx/                    # Nginx 配置
├── php/                      # PHP 配置
├── mysql/                    # MySQL 配置+初始化
├── redis/                    # Redis 配置
├── docs/
│   ├── 部署手册.md             # 实施部署 SOP
│   └── 运维手册.md             # 日常运维 SOP
└── README.md
```

## 技术栈

- **Shell** — 部署/备份/日志分析（脚本总计 600+ 行）
- **Python** — 多线程健康监控 + Webhook 告警
- **Docker / Docker Compose** — LNMP 容器化部署 + 健康检查
- **MySQL** — mysqldump 全量 + binlog 增量备份
- **CI/CD** — GitHub Actions 自动语法检查
- **Nginx / Redis / PHP-FPM** — 标准 Web 技术栈

## 支持的平台

| 系统 | 版本 |
|------|------|
| CentOS | 7 / 8 / 9 |
| Rocky Linux | 8 / 9 |
| Ubuntu | 20.04 / 22.04 / 24.04 |

## 文档

- [部署手册](docs/部署手册.md) — 环境要求 → 安装步骤 → 验证清单 → 常见故障排查
- [运维手册](docs/运维手册.md) — 日常巡检 → 备份恢复 → 故障处理预案 → 安全加固

## CI 状态

![CI](https://github.com/lzkzzz/server-deploy-toolkit/actions/workflows/ci.yml/badge.svg)

## License

MIT
