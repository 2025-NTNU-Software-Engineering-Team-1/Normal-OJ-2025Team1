# 專案目錄結構

此文檔提供專案的簡化目錄結構視圖，便於快速了解專案組織。

## Normal-OJ-2025Team1

```
Normal-OJ-2025Team1/
│
├── 📁 Back-End/                    # 後端服務 (Submodule)
│   ├── app.py                      # Flask 應用入口
│   ├── pyproject.toml              # Poetry 配置
│   ├── Dockerfile
│   ├── gunicorn.conf.py
│   ├── 📁 model/                   # 資料模型（21 個檔案）
│   ├── 📁 mongo/                   # MongoDB 操作（17 個檔案）
│   ├── 📁 migrations/              # 資料庫遷移
│   ├── 📁 tests/                   # 測試代碼（68 個檔案）
│   └── 📁 .config/                 # 配置文件
│
├── 📁 new-front-end/               # 前端介面 (Submodule)
│   ├── index.html                  # HTML 入口
│   ├── package.json                # npm 配置
│   ├── vite.config.ts              # Vite 配置
│   ├── tailwind.config.js
│   ├── tsconfig.json
│   ├── playwright.config.ts
│   ├── 📁 src/                     # 源代碼（103 個檔案）
│   │   ├── 📁 components/
│   │   ├── 📁 views/
│   │   ├── 📁 router/
│   │   ├── 📁 store/
│   │   └── 📁 assets/
│   ├── 📁 public/
│   └── 📁 tests/                   # Playwright 測試（9 個檔案）
│
├── 📁 Sandbox/                     # 沙箱服務 (Submodule)
│   ├── app.py                      # Flask 應用入口
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── Dockerfile.prod
│   ├── c_cpp_dockerfile            # C/C++ 環境
│   ├── python3_dockerfile          # Python 環境
│   ├── build.sh                    # 建構腳本
│   ├── Spec.md                     # API 規格
│   ├── TODO.md
│   ├── 📁 dispatcher/              # 任務分發（13 個檔案）
│   ├── 📁 problem/                 # 題目處理（22 個檔案）
│   ├── 📁 runner/                  # 執行器（2 個檔案）
│   ├── 📁 tests/                   # 測試（14 個檔案）
│   ├── 📁 .config/                 # 配置文件
│   └── 📁 submissions/             # 提交存儲
│
├── 📁 MongoDB/                     # MongoDB 資料目錄
├── 📁 redis-data/                  # Redis 資料目錄
├── 📁 submissions/                 # 提交資料
├── 📁 .secret/                     # 機密配置（.gitignore）
├── 📁 .secret.example/             # 配置範例
│
├── 📄 docker-compose.yml           # Docker 主配置
├── 📄 docker-compose.override.yml # 本地開發配置
├── 📄 docker-compose.prod.yml     # 生產環境配置
├── 📄 .drone.yml                   # CI/CD 配置
├── 📄 .gitmodules                  # Submodule 配置
├── 📄 deploy.sh                    # 部署腳本
├── 📄 backup.py                    # 備份腳本
├── 📄 README.md                    # 專案說明
└── 📄 ARCHITECTURE.md              # 架構文檔（本文檔）
```

## C-Sandbox-2025Team1

```
C-Sandbox-2025Team1/
│
├── 📄 sandbox.c                    # 主要實現（8450 bytes）
├── 📄 sandbox                      # 編譯後的執行檔（22576 bytes）
├── 📄 rule.h                       # 系統呼叫規則（4711 bytes）
├── 📄 lang.h                       # 語言定義（534 bytes）
├── 📄 makefile                     # 建構配置
├── 📄 dockerfile                   # Docker 映像
│
├── 📄 main.c                       # C 測試入口
├── 📄 main.py                      # Python 測試入口
│
├── 📁 test/                        # 測試目錄
│   └── 📁 e2e/                     # 端對端測試（8 個檔案）
│
└── 📄 README.md                    # 專案說明
```

---

## 檔案數量統計

### Normal-OJ-2025Team1

| 模組 | 檔案數 |
|------|--------|
| Back-End | 125+ 檔案 |
| new-front-end | 134+ 檔案 |
| Sandbox | 68+ 檔案 |
| 配置檔案 | 11 個 |
| **總計** | **338+ 檔案** |

### C-Sandbox-2025Team1

| 類型 | 數量 |
|------|------|
| 源碼檔案 | 10 個 |
| 測試檔案 | 8+ 個 |
| **總計** | **18+ 檔案** |

---

## 關鍵檔案說明

### 配置檔案

| 檔案 | 用途 |
|------|------|
| `.gitmodules` | Git Submodule 配置 |
| `docker-compose.yml` | Docker 服務定義 |
| `docker-compose.override.yml` | 本地開發配置（自動合併） |
| `docker-compose.prod.yml` | 生產環境配置 |
| `.drone.yml` | Drone CI 配置 |

### 腳本檔案

| 檔案 | 用途 |
|------|------|
| `deploy.sh` | 自動化部署 |
| `backup.py` | 資料備份 |
| `Sandbox/build.sh` | 建構 Docker 映像 |

### 文檔檔案

| 檔案 | 用途 |
|------|------|
| `README.md` | 專案說明與快速開始 |
| `ARCHITECTURE.md` | 詳細架構文檔 |
| `Sandbox/Spec.md` | Sandbox API 規格 |
| `Sandbox/TODO.md` | 開發待辦事項 |

---

## Git Submodules

本專案使用 Git Submodules 管理三個核心子模組：

```
[submodule "Back-End"]
    path = Back-End
    url = https://github.com/2025-NTNU-Software-Engineering-Team-1/Back-End-2025Team1.git

[submodule "Sandbox"]
    path = Sandbox
    url = https://github.com/2025-NTNU-Software-Engineering-Team-1/Sandbox-2025Team1.git

[submodule "new-front-end"]
    path = new-front-end
    url = https://github.com/2025-NTNU-Software-Engineering-Team-1/new-front-end-2025Team1.git
```

每個子模組都可以獨立開發和版本控制。

---

## 忽略檔案

主要被 `.gitignore` 忽略的目錄：

- `📁 MongoDB/` - 資料庫資料
- `📁 redis-data/` - Redis 快取資料
- `📁 submissions/` - 使用者提交
- `📁 .secret/` - 機密配置
- `📁 __pycache__/` - Python 快取
- `📁 node_modules/` - Node.js 依賴
- `📁 .pytest_cache/` - Pytest 快取
- 各種日誌檔案 (`.log`)

---

詳細架構說明請參考 [ARCHITECTURE.md](./ARCHITECTURE.md)
