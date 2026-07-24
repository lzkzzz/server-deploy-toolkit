-- 数据库初始化脚本（Docker 首次启动时自动执行）
CREATE TABLE IF NOT EXISTS deploy_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    app_name VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL,
    action VARCHAR(20) NOT NULL COMMENT 'deploy/rollback',
    status VARCHAR(10) NOT NULL DEFAULT 'ok',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_app_time (app_name, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
