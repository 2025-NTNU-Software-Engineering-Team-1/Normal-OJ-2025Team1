# Normal-OJ 部署指南

本文檔說明如何在生產環境部署 Normal-OJ 系統，包括環境準備、配置設定、部署流程與維護策略。

## 📋 目錄

- [系統需求](#系統需求)
- [環境準備](#環境準備)
- [配置設定](#配置設定)
- [部署流程](#部署流程)
- [SSL/HTTPS 設定](#sslhttps-設定)
- [監控與日誌](#監控與日誌)
- [備份與復原](#備份與復原)
- [性能調優](#性能調優)
- [故障排除](#故障排除)

---

## 系統需求

### 硬體需求

**最低配置：**
- CPU: 4 核心
- RAM: 8 GB
- 儲存空間: 100 GB SSD

**建議配置（中型部署）：**
- CPU: 8 核心
- RAM: 16 GB
- 儲存空間: 500 GB SSD

**大型部署：**
- CPU: 16+ 核心
- RAM: 32+ GB
- 儲存空間: 1 TB+ SSD
- 分離式部署（Backend、Sandbox、Database 分開）

### 軟體需求

- **作業系統**: Ubuntu 20.04 LTS 或更新版本
- **Docker**: 20.10+ 或更新
- **Docker Compose**: 2.0+ 或更新
- **Git**: 2.25+ 或更新

### 網路需求

- **對外 Port**:
  - 80 (HTTP) - 可選，用於重定向到 HTTPS
  - 443 (HTTPS) - 主要服務
  - 9001 (MinIO Console) - 可選，用於管理

- **內部 Port**（Docker 網路）:
  - 5000 (Backend)
  - 5001 (Sandbox)
  - 27017 (MongoDB)
  - 6379 (Redis)
  - 9000 (MinIO API)

---

## 環境準備

### 1. 安裝 Docker 與 Docker Compose

```bash
# 更新套件列表
sudo apt update

# 安裝必要套件
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 新增 Docker 官方 GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 設定 Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安裝 Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 啟動 Docker 服務
sudo systemctl enable docker
sudo systemctl start docker

# 將當前使用者加入 docker 群組
sudo usermod -aG docker $USER
newgrp docker

# 驗證安裝
docker --version
docker compose version
```

### 2. Clone 專案

```bash
# Clone 主專案（包含所有子模組）
git clone --recurse-submodules \
  https://github.com/2025-NTNU-Software-Engineering-Team-1/Normal-OJ-2025Team1.git

cd Normal-OJ-2025Team1

# 確保所有子模組在 main 分支
git submodule foreach --recursive git checkout main
```

### 3. 建立必要目錄

```bash
# Backend MinIO 資料目錄
mkdir -p ./Back-End/minio/data

# MongoDB 資料目錄（自動建立）
# Redis 資料目錄（自動建立）
# Sandbox submissions 目錄
mkdir -p ./Sandbox/submissions
mkdir -p ./submissions
```

---

## 配置設定

### 1. 環境變數設定

建立 `.secret/.env` 檔案（從範例複製）：

```bash
cp -r .secret.example .secret
```

編輯 `.secret/.env`：

```bash
# JWT 設定
JWT_SECRET=<生成一個強隨機字串，至少 32 字元>
JWT_EXP=7
JWT_ISS=noj.tw

# Server 設定
SERVER_NAME=api.noj.tw
APPLICATION_ROOT=/

# MongoDB 設定
MONGO_HOST=mongodb
MONGO_PORT=27017

# Redis 設定
REDIS_HOST=redis
REDIS_PORT=6379

# MinIO 設定
MINIO_HOST=minio:9000
MINIO_ACCESS_KEY=<生成一個隨機字串>
MINIO_SECRET_KEY=<生成一個隨機字串>
MINIO_BUCKET=noj

# SMTP 設定（用於郵件發送）
SMTP_SERVER=smtp.gmail.com
SMTP_NOREPLY=noreply@noj.tw
SMTP_NOREPLY_PASSWORD=<SMTP 密碼>

# Sandbox Token（Backend 與 Sandbox 共享）
SANDBOX_TOKEN=<生成一個強隨機字串>
```

**生成隨機字串：**
```bash
# JWT_SECRET (32 bytes = 64 hex chars)
openssl rand -hex 32

# MINIO_ACCESS_KEY (16 bytes = 32 hex chars)
openssl rand -hex 16

# MINIO_SECRET_KEY (32 bytes = 64 hex chars)
openssl rand -hex 32

# SANDBOX_TOKEN (32 bytes = 64 hex chars)
openssl rand -hex 32
```

### 2. Sandbox 配置

編輯 `Sandbox/.config/submission.json`：

```json
{
  "working_dir": "/path/to/Normal-OJ-2025Team1/Sandbox/submissions"
}
```

**重要：** 將 `working_dir` 設為絕對路徑。

### 3. 建置 Sandbox Docker 映像

```bash
cd Sandbox
./build.sh
cd ..
```

這會建置三個映像：
- `noj-c-cpp` - C/C++ 執行環境
- `noj-py3` - Python 3 執行環境
- `noj-interactive` - Interactive 模式環境

**驗證映像：**
```bash
docker images | grep noj
```

---

## 部署流程

### 方法一：使用部署腳本（推薦）

```bash
# 賦予執行權限
chmod +x deploy.sh

# 執行部署
./deploy.sh
```

`deploy.sh` 會自動：
1. 拉取最新程式碼
2. 更新子模組
3. 使用 `docker-compose.prod.yml` 啟動服務

### 方法二：手動部署

```bash
# 停止現有服務（如果有）
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# 拉取最新映像
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

# 建置並啟動服務
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# 查看服務狀態
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

### 部署後檢查

```bash
# 檢查所有容器是否正常運行
docker ps

# 檢查日誌
docker compose logs -f backend
docker compose logs -f sandbox
docker compose logs -f mongodb

# 測試 Backend API
curl http://localhost:5000/health

# 測試 Sandbox
curl http://localhost:5001/status
```

### 初始化資料

**首次部署需要：**

1. **設定 MinIO**（若使用 MinIO 儲存）：
   - 開啟 http://localhost:9001
   - 使用 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD` 登入（見 docker-compose.yml）
   - 建立 Bucket（名稱須與 `MINIO_BUCKET` 一致）
   - 建立 Access Key（設為 `MINIO_ACCESS_KEY` 和 `MINIO_SECRET_KEY`）

2. **預設管理員帳號**：
   - Username: `first_admin`
   - Password: `firstpasswordforadmin`
   
   **重要：** 首次登入後立即修改密碼！

---

## SSL/HTTPS 設定

### 方法一：使用 Nginx Reverse Proxy + Let's Encrypt

**1. 安裝 Nginx 與 Certbot：**
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

**2. 建立 Nginx 配置：**
```nginx
# /etc/nginx/sites-available/noj
server {
    listen 80;
    server_name api.noj.tw;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**3. 啟用站台：**
```bash
sudo ln -s /etc/nginx/sites-available/noj /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**4. 取得 SSL 憑證：**
```bash
sudo certbot --nginx -d api.noj.tw
```

Certbot 會自動修改 Nginx 配置並設定 HTTPS。

**5. 自動續約：**
```bash
# 測試續約
sudo certbot renew --dry-run

# Certbot 會自動設定 cron job 進行續約
```

### 方法二：使用 Cloudflare

如果前端部署在 Cloudflare Pages，可使用 Cloudflare Tunnel：

1. 安裝 `cloudflared`
2. 建立 Tunnel 連接到 Backend (port 5000)
3. 在 Cloudflare Dashboard 設定 DNS 與 SSL

---

## 監控與日誌

### Docker 日誌

```bash
# 查看即時日誌
docker compose logs -f [service_name]

# 查看最近 100 行
docker compose logs --tail=100 backend

# 查看特定時間範圍
docker compose logs --since 2023-01-01T00:00:00 backend
```

### 日誌輪替

**Backend gunicorn 日誌：**

配置 `logrotate`：
```bash
# /etc/logrotate.d/noj-backend
/path/to/Normal-OJ/Back-End/gunicorn_error.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    missingok
    create 0644 nobody nobody
    postrotate
        docker compose exec backend kill -USR1 1
    endscript
}
```

**Sandbox 日誌：**

Sandbox 日誌位於 `Sandbox/logs/sandbox.log`，同樣可用 logrotate 管理。

### 效能監控

**使用 Docker Stats：**
```bash
docker stats
```

**使用 cAdvisor（推薦）：**
```yaml
# docker-compose.monitoring.yml
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
```

啟動：
```bash
docker compose -f docker-compose.monitoring.yml up -d
```

開啟 http://localhost:8080 查看監控資訊。

---

## 備份與復原

### 備份策略

**1. 使用內建備份腳本：**
```bash
python backup.py
```

這會備份：
- MongoDB 資料庫
- MinIO 儲存內容
- 配置檔案

**2. 手動備份：**

**MongoDB：**
```bash
# 備份
docker compose exec mongodb mongodump --out /backup/$(date +%Y%m%d)

# 複製到 Host
docker cp mongodb:/backup ./mongodb-backup
```

**MinIO：**
```bash
# 使用 mc (MinIO Client)
mc mirror minio/noj ./minio-backup
```

**配置檔案：**
```bash
tar -czf config-backup-$(date +%Y%m%d).tar.gz \
  .secret/ \
  Sandbox/.config/ \
  docker-compose.yml \
  docker-compose.prod.yml
```

### 復原流程

**1. 復原 MongoDB：**
```bash
# 複製備份到容器
docker cp ./mongodb-backup mongodb:/backup

# 復原
docker compose exec mongodb mongorestore /backup/20231225
```

**2. 復原 MinIO：**
```bash
mc mirror ./minio-backup minio/noj
```

**3. 復原配置：**
```bash
tar -xzf config-backup-20231225.tar.gz
```

### 自動化備份

**設定 Cron Job：**
```bash
# 編輯 crontab
crontab -e

# 每天凌晨 2 點執行備份
0 2 * * * cd /path/to/Normal-OJ && python backup.py
```

---

## 性能調優

### MongoDB 優化

**1. 建立索引：**
```javascript
// 連線到 MongoDB
docker compose exec mongodb mongosh

// 常用查詢的索引
db.submissions.createIndex({ "problemId": 1, "timestamp": -1 })
db.submissions.createIndex({ "userId": 1, "timestamp": -1 })
db.problems.createIndex({ "courses": 1 })
```

**2. 調整記憶體設定：**

編輯 `docker-compose.prod.yml`：
```yaml
services:
  mongodb:
    command: --wiredTigerCacheSizeGB 2
```

### Redis 優化

```yaml
services:
  redis:
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
```

### Sandbox 並發調整

編輯 `Sandbox/.config/dispatcher.json`：
```json
{
  "max_workers": 8,
  "queue_size": 100
}
```

根據硬體資源調整：
- **max_workers**: CPU 核心數
- **queue_size**: 2-3 倍的 max_workers

### Backend Gunicorn 調整

編輯 `Back-End/gunicorn.conf.py`：
```python
workers = 4          # 2-4 倍 CPU 核心數
worker_class = 'sync'
timeout = 120
keepalive = 5
max_requests = 1000
max_requests_jitter = 50
```

---

## 故障排除

### 常見問題

#### 1. 容器無法啟動

**檢查：**
```bash
# 查看詳細日誌
docker compose logs [service_name]

# 檢查 Port 佔用
sudo netstat -tulpn | grep LISTEN
```

**解決：**
- 確認 Port 未被佔用
- 檢查環境變數是否正確設定
- 確認 Docker Daemon 正常運行

#### 2. Backend 無法連線到 MongoDB

**檢查：**
```bash
# 測試 MongoDB 連線
docker compose exec mongodb mongosh --eval "db.runCommand({ ping: 1 })"
```

**解決：**
- 確認 `MONGO_HOST` 設為 `mongodb`（容器名稱）
- 檢查 Docker 網路設定

#### 3. Sandbox 評測失敗

**檢查：**
```bash
# 查看 Sandbox 日誌
docker compose logs sandbox

# 檢查 Docker 映像
docker images | grep noj
```

**解決：**
- 重新執行 `Sandbox/build.sh`
- 確認 `working_dir` 設定正確
- 檢查 Sandbox Token 是否一致

#### 4. MinIO 無法存取

**檢查：**
```bash
# 測試 MinIO API
curl http://localhost:9000/minio/health/live
```

**解決：**
- 確認 Bucket 已建立
- 檢查 Access Key 和 Secret Key
- 確認 MinIO 容器正常運行

### 效能問題

**症狀：** 評測速度慢

**排查：**
1. 檢查 CPU/記憶體使用率
2. 增加 Sandbox workers
3. 檢查是否有大量 pending 的 submissions
4. 考慮擴展為多個 Sandbox instances

**症狀：** 資料庫查詢慢

**排查：**
1. 檢查 MongoDB slow query log
2. 建立適當索引
3. 考慮增加 MongoDB 記憶體
4. 啟用 query profiling

---

## 更新與維護

### 更新流程

```bash
# 1. 備份資料
python backup.py

# 2. 拉取最新程式碼
git pull
git submodule update --remote --recursive

# 3. 重新建置 Sandbox 映像（如有變更）
cd Sandbox && ./build.sh && cd ..

# 4. 重啟服務
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# 5. 檢查服務狀態
docker compose ps
docker compose logs -f
```

### 資料庫遷移

若有 Schema 變更，執行遷移腳本：
```bash
docker compose exec backend python migrations/migrate.py
```

---

## 擴展部署

### 多 Sandbox Instances

**1. 建立多個 Sandbox 服務：**

`docker-compose.scale.yml`：
```yaml
services:
  sandbox-1:
    extends:
      file: docker-compose.yml
      service: sandbox
    container_name: sandbox-1
    ports:
      - "5001:5001"
  
  sandbox-2:
    extends:
      file: docker-compose.yml
      service: sandbox
    container_name: sandbox-2
    ports:
      - "5002:5001"
```

**2. Backend 設定多個 Sandbox：**

編輯 Backend 配置，加入多個 Sandbox URL。

### 分離式部署

**架構：**
```
Load Balancer (Nginx)
    ├── Backend (App Server)
    ├── Sandbox 1 (Eval Server)
    ├── Sandbox 2 (Eval Server)
    └── ...

Database Server
    ├── MongoDB
    ├── Redis
    └── MinIO
```

**優點：**
- 資源隔離
- 獨立擴展
- 更好的效能

---

## 相關文檔

- [ARCHITECTURE.md](ARCHITECTURE.md) - 系統架構
- [SECURITY_GUIDE.md](SECURITY_GUIDE.md) - 安全指南
- [API_REFERENCE.md](API_REFERENCE.md) - API 參考

---

**最後更新：** 2025-11-29  
**維護者：** 2025 NTNU Software Engineering Team 1
