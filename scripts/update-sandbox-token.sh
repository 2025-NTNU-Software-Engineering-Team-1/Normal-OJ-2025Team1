#!/bin/bash
# =============================================================================
# update-sandbox-token.sh - 更新 Sandbox Token (Shell 包裝腳本)
# =============================================================================
#
# 用法:
#   ./scripts/update-sandbox-token.sh [show|generate|set TOKEN]
#
# 命令:
#   show      - 顯示目前的 Sandbox 設定
#   generate  - 自動生成並設定新的安全 Token
#   set TOKEN - 設定指定的 Token
#
# 範例:
#   ./scripts/update-sandbox-token.sh show
#   ./scripts/update-sandbox-token.sh generate
#   ./scripts/update-sandbox-token.sh set "MySecretToken123"
#
# =============================================================================

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

cd "$PROJECT_ROOT"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 檢查 Docker 是否運行
check_docker() {
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker 未運行${NC}"
        exit 1
    fi
}

# 檢查 MongoDB 容器
check_mongo() {
    if ! docker ps --format '{{.Names}}' | grep -q mongo; then
        echo -e "${RED}❌ MongoDB 容器未運行${NC}"
        echo -e "${YELLOW}   請先啟動服務: docker compose up -d mongo${NC}"
        exit 1
    fi
}

# 在 web 容器中執行 Python 腳本
run_in_container() {
    local args="$1"

    # 檢查 web 容器是否運行
    if docker ps --format '{{.Names}}' | grep -q web; then
        docker exec -it $(docker ps -qf "name=web") \
            python3 /app/scripts/update-sandbox-token.py $args
    else
        # 如果 web 容器沒運行，用臨時容器執行
        echo -e "${YELLOW}⚠️  web 容器未運行，使用臨時容器...${NC}"

        docker run --rm -it \
            --network $(docker network ls --filter name=normal-oj -q | head -1) \
            -v "$PROJECT_ROOT/scripts:/scripts:ro" \
            -v "$PROJECT_ROOT/Back-End:/app:ro" \
            -e MONGO_HOST=mongo \
            python:3.11-slim \
            bash -c "pip install -q pymongo && python3 /scripts/update-sandbox-token.py $args"
    fi
}

# 顯示使用說明
show_usage() {
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  show              顯示目前的 Sandbox 設定"
    echo "  generate          自動生成並設定新的安全 Token"
    echo "  set <TOKEN>       設定指定的 Token"
    echo ""
    echo "範例:"
    echo "  $0 show"
    echo "  $0 generate"
    echo "  $0 set \"MySecretToken123\""
}

# 主程式
main() {
    local cmd="${1:-show}"

    echo ""
    echo -e "${BLUE}🔧 Normal-OJ Sandbox Token 管理工具${NC}"
    echo "=================================================="

    check_docker
    check_mongo

    case "$cmd" in
        show)
            run_in_container "--show"
            ;;
        generate)
            run_in_container "--generate"
            echo ""
            echo -e "${YELLOW}⚠️  記得更新 .secret/sandbox.env 並重啟 sandbox:${NC}"
            echo "   nano .secret/sandbox.env"
            echo "   docker compose -f docker-compose.yml -f docker-compose.cloud.yml restart sandbox"
            ;;
        set)
            if [ -z "$2" ]; then
                echo -e "${RED}❌ 請提供 Token${NC}"
                echo "   用法: $0 set <TOKEN>"
                exit 1
            fi
            run_in_container "--token \"$2\""
            echo ""
            echo -e "${YELLOW}⚠️  記得更新 .secret/sandbox.env 並重啟 sandbox:${NC}"
            echo "   nano .secret/sandbox.env"
            echo "   docker compose -f docker-compose.yml -f docker-compose.cloud.yml restart sandbox"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}❌ 未知命令: $cmd${NC}"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
