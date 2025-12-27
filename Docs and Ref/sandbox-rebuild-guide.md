```
# 完整重建 Sandbox 環境指南

## Sandbox 構建架構說明
Sandbox 環境包含以下組件：
1. **Sandbox Flask 應用** - 主要的評測服務 (`./Sandbox` 目錄)
2. **執行環境 Docker Images** - 用於執行學生程式碼或網路服務，我們叫
   - `noj-c-cpp` - C/C++ 執行環境
   - `noj-py3` - Python3 執行環境
   - `noj-interactive` - 互動式題目環境
   - `noj-custom-checker-scorer` - 自定義 Checker Scorer
   - `noj-router` - Network Mode 路由器
   - `system-router` - 內部 AI 功能路由器
3. **Sandbox 二進制檔** - C-Sandbox 執行器
   - `sandbox` - 標準執行器
   - `sandbox_interactive` - 互動式執行器

## 完整重建步驟

### 步驟 1: 停止所有相關服務
```bash
docker compose stop sandbox
```

### 步驟 2: 清除 Python Cache
```bash
find ./Sandbox -name "*.pyc" -delete
find ./Sandbox -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
```

### 步驟 3: 刪除舊的 Sandbox Container 和 Image
```bash
docker compose rm -f sandbox
docker rmi normal-oj-2025team1-sandbox 2>/dev/null || true
```

### 步驟 4: 執行 build.sh (重建執行環境)
```bash
cd Sandbox
chmod +x build.sh
./build.sh
cd ..
```

這會：
- 下載最新的 `sandbox` 和 `sandbox_interactive` 二進制檔
- 重建所有執行環境 Docker images (`--no-cache`)

### 步驟 5: 重建並啟動 Sandbox Container
```bash
docker compose build --no-cache sandbox
docker compose up -d sandbox
```

### 步驟 6: 驗證服務正常
```bash
# 檢查 container 狀態
docker compose ps sandbox

# 檢查日誌確認無錯誤
docker logs normal-oj-2025team1-sandbox-1 --tail 20
```

## 一鍵完整重建腳本

將以下內容合併為一個完整的重建流程：

```bash
# 完整重建 Sandbox 環境
docker compose stop sandbox && \
find ./Sandbox -name "*.pyc" -delete && \
find ./Sandbox -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null; \
docker compose rm -f sandbox && \
docker rmi normal-oj-2025team1-sandbox 2>/dev/null; \
cd Sandbox && chmod +x build.sh && ./build.sh && cd .. && \
docker compose build --no-cache sandbox && \
docker compose up -d sandbox && \
echo "等待服務啟動..." && sleep 5 && \
docker logs normal-oj-2025team1-sandbox-1 --tail 10
```