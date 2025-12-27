#!/bin/bash
# =============================================================================
# rebuild-sandbox.sh - 完整重建 Sandbox 環境
# =============================================================================
#
# 用法:
#   ./rebuild-sandbox.sh
#
# 此腳本會：
#   1. 停止 sandbox 服務
#   2. 清理 Python 快取
#   3. 移除舊容器和映像
#   4. 建置 Sidecar 映像 (noj-c-cpp, noj-py3, etc.)
#   5. 重建 sandbox 映像
#   6. 啟動服務
#
# 何時使用此腳本：
#   - Sandbox 程式碼有重大變更
#   - Sidecar 映像需要更新 (例如編譯器版本更新)
#   - Sandbox 容器無法正常運作
#   - 首次部署
#
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# 顏色定義
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# 變數設定
# -----------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

COMPOSE_CMD=${DOCKER_COMPOSE_BINARY:-docker compose}

# 判斷使用哪個 compose 檔案組合
if [ -f "docker-compose.cloud.yml" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.cloud.yml"
    echo -e "${BLUE}[INFO]${NC} 使用雲端部署配置"
else
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.override.yml"
    echo -e "${BLUE}[INFO]${NC} 使用本地開發配置"
fi

# -----------------------------------------------------------------------------
# 輔助函數
# -----------------------------------------------------------------------------
log_step() {
    echo ""
    echo -e "${YELLOW}===================================================${NC}"
    echo -e "${YELLOW} Step: $1${NC}"
    echo -e "${YELLOW}===================================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------------
# 主程式
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}  Sandbox 完整重建${NC}"
echo -e "${YELLOW}=============================================${NC}"
echo -e "時間: $(date)"
echo ""

# Step 1: 停止 sandbox 服務
log_step "1/6 停止 Sandbox 服務"
$COMPOSE_CMD $COMPOSE_FILES stop sandbox || true
log_success "Sandbox 服務已停止"

# Step 2: 清理 Python 快取
log_step "2/6 清理 Python 快取"
find ./Sandbox -name "*.pyc" -delete 2>/dev/null || true
find ./Sandbox -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
log_success "Python 快取已清理"

# Step 3: 移除舊容器和映像
log_step "3/6 移除舊容器和映像"
$COMPOSE_CMD $COMPOSE_FILES rm -f sandbox || true

# 嘗試移除 sandbox 映像
docker rmi normal-oj-2025team1-sandbox 2>/dev/null || true
docker rmi $(docker images -q --filter "dangling=true") 2>/dev/null || true
log_success "舊容器和映像已移除"

# Step 4: 建置 Sidecar 映像
log_step "4/6 建置 Sidecar 映像"
if [ -f "./Sandbox/build.sh" ]; then
    log_info "執行 Sandbox/build.sh..."
    cd Sandbox
    chmod +x build.sh
    ./build.sh
    cd ..
    log_success "Sidecar 映像建置完成"
else
    log_error "Sandbox/build.sh 不存在!"
    exit 1
fi

# Step 5: 重建 sandbox 映像
log_step "5/6 重建 Sandbox 映像"
$COMPOSE_CMD $COMPOSE_FILES build --no-cache sandbox
log_success "Sandbox 映像建置完成"

# Step 6: 啟動服務
log_step "6/6 啟動 Sandbox 服務"
$COMPOSE_CMD $COMPOSE_FILES up -d sandbox
log_success "Sandbox 服務已啟動"

# 等待並檢查
echo ""
log_info "等待服務啟動..."
sleep 10

# 顯示日誌
log_info "最近的 Sandbox 日誌:"
echo "---"
docker logs normal-oj-2025team1-sandbox-1 --tail 15 2>/dev/null || \
docker logs $(docker ps -qf "name=sandbox") --tail 15 2>/dev/null || \
echo "無法取得日誌"
echo "---"

# 完成
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Sandbox 重建完成!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# 顯示可用的 sidecar 映像
log_info "可用的 Sidecar 映像:"
docker images | grep -E "noj-c-cpp|noj-py3|noj-interactive" || echo "無"
echo ""
