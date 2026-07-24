#!/usr/bin/env python3
"""
health_check.py - 服务健康监控

检测 HTTP/TCP/进程存活状态，输出 JSON 结果。
异常时支持钉钉/企业微信 Webhook 告警。

用法：
    python health_check.py                          # 交互式输出
    python health_check.py --json                   # JSON 输出（适合定时任务）
    python health_check.py --alert                  # 异常时发送告警
"""

import json
import socket
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

# ========================= 配置 =========================
CHECKS = [
    {"name": "Nginx",         "type": "http",  "host": "localhost", "port": 80,  "path": "/"},
    {"name": "PHP-FPM",       "type": "tcp",   "host": "localhost", "port": 9000},
    {"name": "MySQL",         "type": "tcp",   "host": "localhost", "port": 3306},
    {"name": "Redis",         "type": "tcp",   "host": "localhost", "port": 6379},
    {"name": "Docker Daemon", "type": "process", "process_name": "dockerd"},
    {"name": "SSH Daemon",    "type": "process", "process_name": "sshd"},
]

# 告警 Webhook（留空则不发送）
DINGTALK_WEBHOOK = ""  # 钉钉机器人 Webhook URL
WECOM_WEBHOOK = ""     # 企业微信机器人 Webhook URL

TIMEOUT = 5  # 连接超时（秒）

# ========================= 数据模型 =========================
@dataclass
class CheckResult:
    """单次检查结果"""
    name: str
    type: str
    status: str        # "ok" | "error" | "unknown"
    latency_ms: float = 0.0
    message: str = ""
    checked_at: str = ""

# ========================= 检查函数 =========================
def check_http(name: str, host: str, port: int, path: str = "/") -> CheckResult:
    """HTTP 健康检查"""
    import urllib.request
    url = f"http://{host}:{port}{path}"
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            latency = (time.perf_counter() - start) * 1000
            if 200 <= resp.status < 400:
                return CheckResult(name, "http", "ok", round(latency, 2))
            return CheckResult(name, "http", "error", round(latency, 2),
                               f"HTTP {resp.status}")
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return CheckResult(name, "http", "error", round(latency, 2), str(e))

def check_tcp(name: str, host: str, port: int) -> CheckResult:
    """TCP 端口连通性检查"""
    start = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=TIMEOUT):
            latency = (time.perf_counter() - start) * 1000
            return CheckResult(name, "tcp", "ok", round(latency, 2))
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return CheckResult(name, "tcp", "error", round(latency, 2), str(e))

def check_process(name: str, process_name: str) -> CheckResult:
    """进程存活检查"""
    start = time.perf_counter()
    try:
        result = subprocess.run(
            ["pgrep", "-f", process_name],
            capture_output=True, text=True, timeout=TIMEOUT
        )
        latency = (time.perf_counter() - start) * 1000
        if result.returncode == 0:
            return CheckResult(name, "process", "ok", round(latency, 2))
        return CheckResult(name, "process", "error", round(latency, 2),
                           f"进程 {process_name} 未运行")
    except Exception as e:
        latency = (time.perf_counter() - start) * 1000
        return CheckResult(name, "process", "error", round(latency, 2), str(e))

# ========================= 主逻辑 =========================
def run_all_checks() -> list[CheckResult]:
    """多线程并发检查所有服务"""
    results: list[CheckResult] = []
    checked_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    with ThreadPoolExecutor(max_workers=len(CHECKS)) as executor:
        future_map = {}
        for check in CHECKS:
            ctype = check["type"]
            if ctype == "http":
                future = executor.submit(check_http, check["name"], check["host"],
                                         check["port"], check.get("path", "/"))
            elif ctype == "tcp":
                future = executor.submit(check_tcp, check["name"], check["host"],
                                         check["port"])
            elif ctype == "process":
                future = executor.submit(check_process, check["name"],
                                         check["process_name"])
            else:
                future = None
                results.append(CheckResult(check["name"], ctype, "unknown",
                                           message="不支持的检查类型"))

            if future:
                future_map[future] = check

        for future in as_completed(future_map):
            result = future.result()
            result.checked_at = checked_at
            results.append(result)

    return sorted(results, key=lambda r: r.name)

# ========================= 告警 =========================
def send_alert(results: list[CheckResult]) -> None:
    """异常时发送 Webhook 告警"""
    errors = [r for r in results if r.status != "ok"]
    if not errors:
        return

    error_list = "\n".join(f"- {r.name}: {r.message}" for r in errors)
    alert_msg = f"⚠️ **服务异常告警**\n时间：{datetime.now()}\n\n{error_list}"

    # 钉钉
    if DINGTALK_WEBHOOK:
        import urllib.request
        payload = json.dumps({
            "msgtype": "text",
            "text": {"content": alert_msg}
        }).encode()
        try:
            req = urllib.request.Request(DINGTALK_WEBHOOK, data=payload,
                                         headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=5)
        except Exception:
            pass

    # 企业微信
    if WECOM_WEBHOOK:
        import urllib.request
        payload = json.dumps({
            "msgtype": "text",
            "text": {"content": alert_msg}
        }).encode()
        try:
            req = urllib.request.Request(WECOM_WEBHOOK, data=payload,
                                         headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=5)
        except Exception:
            pass

# ========================= 入口 =========================
def main() -> None:
    results = run_all_checks()

    # 输出
    if "--json" in sys.argv:
        output = {
            "checked_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "total": len(results),
            "ok": sum(1 for r in results if r.status == "ok"),
            "error": sum(1 for r in results if r.status == "error"),
            "checks": [
                {
                    "name": r.name,
                    "status": r.status,
                    "latency_ms": r.latency_ms,
                    "message": r.message,
                }
                for r in results
            ]
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        print("=" * 50)
        print("  服务健康检查报告")
        print(f"  时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 50)
        for r in results:
            icon = "✅" if r.status == "ok" else "❌"
            detail = f"({r.latency_ms}ms)" if r.latency_ms else ""
            msg = f" -- {r.message}" if r.message else ""
            print(f"  {icon} {r.name:<15} {detail:<12} {msg}")

        ok_count = sum(1 for r in results if r.status == "ok")
        err_count = sum(1 for r in results if r.status == "error")
        print("-" * 50)
        print(f"  总计: {len(results)} | 正常: {ok_count} | 异常: {err_count}")

    # 告警
    if "--alert" in sys.argv:
        send_alert(results)

    # 有异常时返回非零退出码
    if any(r.status == "error" for r in results):
        sys.exit(1)

if __name__ == "__main__":
    main()
