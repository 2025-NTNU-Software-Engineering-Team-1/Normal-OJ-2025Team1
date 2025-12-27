#!/bin/bash
# =============================================================================
# deploy-cloud.sh - GCE 雲端部署腳本
# =============================================================================
#
# 用法:
#   ./deploy-cloud.sh [模式]
#
# 模式:
#   restart  - 快速更新：git pull + 重啟容器 (預設)
#   rebuild  - 完整重建：git pull + 重建所有映像 + 重建 Sandbox sidecar
#
# 範例:
#   ./deploy-cloud.sh           # 使用預設 restart 模式
#   ./deploy-cloud.sh restart   # 快速更新
#   ./deploy-cloud.sh rebuild   # 完整重建
#
# 環境變數:
#   DOCKER_COMPOSE_BINARY - Docker Compose 指令 (預設: docker compose)
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 顏色定義 (用於終端輸出)
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# -----------------------------------------------------------------------------
# 變數設定
# -----------------------------------------------------------------------------
# 切換到腳本所在目錄
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# 部署模式 (預設: restart)
MODE=${1:-restart}

# Docker Compose 指令
COMPOSE_CMD=${DOCKER_COMPOSE_BINARY:-docker compose}

# Compose 檔案組合
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.cloud.yml"

# -----------------------------------------------------------------------------
# 輔助函數
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------------
# 前置檢查
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_info "檢查前置條件..."

    # 檢查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安裝"
        exit 1
    fi

    # 檢查 Docker Compose
    if ! $COMPOSE_CMD version &> /dev/null; then
        log_error "Docker Compose 未安裝或無法使用"
        exit 1
    fi

    # 檢查必要的環境變數檔案
    local required_env_files=(".secret/web.env" ".secret/minio.env" ".secret/caddy.env")
    for env_file in "${required_env_files[@]}"; do
        if [ ! -f "$env_file" ]; then
            log_error "缺少環境變數檔案: $env_file"
            exit 1
        fi
    done

    log_success "前置條件檢查通過"
}

# -----------------------------------------------------------------------------
# 確保必要目錄存在
# -----------------------------------------------------------------------------
ensure_directories() {
    log_info "確保必要目錄存在..."

    # 建立必要的目錄
    mkdir -p logs/web logs/caddy .caddy
    mkdir -p Sandbox/submissions Sandbox/logs

    # 確保 GCE 資料目錄存在 (需要 sudo)
    if [ ! -d "/opt/noj" ]; then
        log_warning "/opt/noj 不存在，嘗試建立..."
        sudo mkdir -p /opt/noj/minio /opt/noj/mongodb /opt/noj/redis
        sudo chown -R $USER:$USER /opt/noj
    fi

    log_success "目錄檢查完成"
}

# -----------------------------------------------------------------------------
# 更新程式碼
# -----------------------------------------------------------------------------
update_code() {
    log_info "更新程式碼..."

    # 拉取主專案最新程式碼
    git pull origin main

    # 更新 Git submodules (Back-End, Sandbox)
    git submodule update --init --recursive

    # 進入各 submodule 拉取最新程式碼
    log_info "更新 Back-End submodule..."
    git submodule foreach 'git checkout main && git pull origin main || true'

    log_success "程式碼更新完成"
}

# -----------------------------------------------------------------------------
# 快速重啟模式
# -----------------------------------------------------------------------------
deploy_restart() {
    log_info "執行快速重啟模式..."

    # 重啟所有容器
    $COMPOSE_CMD $COMPOSE_FILES restart

    log_success "容器已重啟"
}

# -----------------------------------------------------------------------------
# 完整重建模式
# -----------------------------------------------------------------------------
deploy_rebuild() {
    log_info "執行完整重建模式..."

    # 停止 sandbox 和 web 服務
    log_info "停止服務..."
    $COMPOSE_CMD $COMPOSE_FILES stop sandbox web

    # 清理 Sandbox Python 快取
    log_info "清理 Python 快取..."
    find ./Sandbox -name "*.pyc" -delete 2>/dev/null || true
    find ./Sandbox -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    # 移除舊的 sandbox 容器和映像
    log_info "移除舊的 sandbox 映像..."
    $COMPOSE_CMD $COMPOSE_FILES rm -f sandbox || true
    docker rmi normal-oj-2025team1-sandbox 2>/dev/null || true

    # 建置 Sidecar 映像 (noj-c-cpp, noj-py3, etc.)
    log_info "建置 Sandbox sidecar 映像..."
    if [ -f "./Sandbox/build.sh" ]; then
        cd Sandbox
        chmod +x build.sh
        ./build.sh
        cd ..
    else
        log_warning "Sandbox/build.sh 不存在，跳過 sidecar 映像建置"
    fi

    # 重建所有映像
    log_info "重建 Docker 映像..."
    $COMPOSE_CMD $COMPOSE_FILES build --no-cache

    # 啟動所有服務
    log_info "啟動服務..."
    $COMPOSE_CMD $COMPOSE_FILES up -d --remove-orphans

    log_success "完整重建完成"
}

# -----------------------------------------------------------------------------
# 健康檢查
# -----------------------------------------------------------------------------
health_check() {
    log_info "等待服務啟動..."
    sleep 15

    log_info "執行健康檢查..."

    # 檢查 Backend API
    if curl -sf http://localhost:8080/api/health > /dev/null 2>&1; then
        log_success "Backend API 健康"
    else
        log_warning "Backend API 健康檢查失敗 (可能仍在啟動中)"
    fi

    # 檢查 MinIO
    if curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        log_success "MinIO 健康"
    else
        log_warning "MinIO 健康檢查失敗"
    fi

    # 顯示容器狀態
    echo ""
    log_info "容器狀態:"
    $COMPOSE_CMD $COMPOSE_FILES ps
}

# -----------------------------------------------------------------------------
# 顯示使用說明
# -----------------------------------------------------------------------------
show_usage() {
    echo "用法: $0 [模式]"
    echo ""
    echo "模式:"
    echo "  restart  - 快速更新：git pull + 重啟容器 (預設)"
    echo "  rebuild  - 完整重建：git pull + 重建映像 + 重建 sidecar"
    echo ""
    echo "範例:"
    echo "  $0           # 使用 restart 模式"
    echo "  $0 restart   # 快速更新"
    echo "  $0 rebuild   # 完整重建"
}

# -----------------------------------------------------------------------------
# 主程式
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${YELLOW}=============================================${NC}"
    echo -e "${YELLOW}  Normal-OJ Cloud Deployment${NC}"
    echo -e "${YELLOW}=============================================${NC}"
    echo -e "模式: ${GREEN}$MODE${NC}"
    echo -e "時間: $(date)"
    echo ""

    # 前置檢查
    check_prerequisites

    # 確保目錄存在
    ensure_directories

    # 更新程式碼
    update_code

    # 根據模式執行部署
    case $MODE in
        restart)
            deploy_restart
            ;;
        rebuild)
            deploy_rebuild
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "未知的模式: $MODE"
            show_usage
            exit 1
            ;;
    esac

    # 健康檢查
    health_check

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  部署完成!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
}

# 執行主程式
main
