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

| 脚本 | 行数 | 功能 | 面试可以这样说 |
|------|------|------|---------|
| `init_server.sh` | 160 | 服务器初始化（装包/关SELinux/配防火墙/建账号/调优） | "能自动识别 CentOS/Ubuntu，装完包、关掉 SELinux、配好防火墙、建好运维账号" |
| `deploy.sh` | 170 | 应用自动部署+健康检查+自动回滚 | "部署前自动备份旧版→部署新版→等健康检查通过→失败了自动回滚，不需要人工盯着" |
| `health_check.py` | 180 | 多线程健康监控（HTTP/TCP/进程）+钉钉/企微告警 | "Python 多线程并发检测 6 项服务，Nginx 挂了 5 秒内能收到钉钉告警" |
| `backup.sh` | 130 | MySQL 全量+ binlog 增量备份+自动清理 | "mysqldump 全量 + binlog 增量备份，保留 7 天自动删除，备份完自动校验文件有没有坏" |
| `log_analyzer.sh` | 150 | 日志分析（Nginx 状态码/IP/慢请求、系统错误、Docker） | "能分析 Nginx 的 4xx/5xx 错误比例、哪些 IP 在刷接口、系统有没有 OOM、SSH 有没有爆破" |
| `install.sh` | 100 | 一条命令安装本工具到任意服务器 | "curl 管道 sudo bash，自动装依赖→克隆代码→建配置→配别名" |
| `test_runner.sh` | 120 | 脚本自测（语法/函数/配置完整性） | "提交前自动跑：语法检查、关键函数是否存在、配置文件有没有丢、有没有 set -e 错误处理" |
| `docker-compose.yml` | — | LNMP 容器编排+健康检查+资源限制 | "一个 yml 文件拉起 Nginx + MySQL + Redis + PHP-FPM，每个容器都配了健康检查和自动重启" |
| `.env.example` | — | 集中配置管理 | "密码、路径、告警链接全放在 .env 里，不硬编码进脚本" |

## 快速开始

### 一键安装

```bash
curl -sSL https://raw.githubusercontent.com/lzkzzz/server-deploy-toolkit/main/install.sh | sudo bash
```

### 手动使用

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
├── install.sh                # 一键安装（100行）
├── test_runner.sh            # 自动化自测（120行）
├── .env.example              # 配置模板
├── .github/workflows/ci.yml  # CI 自动检查
├── nginx/ mysql/ php/ redis/ # 中间件配置
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
