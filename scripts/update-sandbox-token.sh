#!/bin/bash
# =============================================================================
# update-sandbox-token.sh - 更新 Sandbox Token
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

# Docker Compose 檔案
COMPOSE_FILES="-f docker-compose.yml"
if [ -f "docker-compose.cloud.yml" ]; then
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.cloud.yml"
elif [ -f "docker-compose.override.yml" ]; then
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.override.yml"
fi

# 檢查 Docker 是否運行
check_docker() {
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker 未運行${NC}"
        exit 1
    fi
}

# 檢查 MongoDB 容器
check_mongo() {
    if ! docker compose $COMPOSE_FILES ps mongo 2>/dev/null | grep -q "running"; then
        echo -e "${RED}❌ MongoDB 容器未運行${NC}"
        echo -e "${YELLOW}   請先啟動服務: docker compose $COMPOSE_FILES up -d mongo${NC}"
        exit 1
    fi
}

# 顯示目前設定
show_config() {
    echo -e "${BLUE}📋 目前的 Sandbox 設定:${NC}"
    echo "=================================================="

    docker compose $COMPOSE_FILES exec -T mongo mongosh normal-oj --quiet --eval '
        var config = db.config.findOne({_cls: "SubmissionConfig"});
        if (config && config.sandboxInstances) {
            config.sandboxInstances.forEach(function(sb, i) {
                print("Sandbox #" + i + ":");
                print("  Name:  " + sb.name);
                print("  URL:   " + sb.url);
                print("  Token: " + sb.token);
                print("");
            });
        } else {
            print("找不到 SubmissionConfig 或沒有設定 Sandbox");
        }
    '
}

# 更新 Token
update_token() {
    local new_token="$1"

    echo -e "${BLUE}🔄 更新 Token...${NC}"

    docker compose $COMPOSE_FILES exec -T mongo mongosh normal-oj --quiet --eval "
        var result = db.config.updateOne(
            {_cls: 'SubmissionConfig'},
            {\$set: {'sandboxInstances.0.token': '$new_token'}}
        );
        if (result.matchedCount > 0) {
            print('✅ Token 已更新');
        } else {
            // 如果沒有找到，建立新的設定
            db.config.insertOne({
                _cls: 'SubmissionConfig',
                name: 'submission',
                rateLimit: 0,
                sandboxInstances: [{
                    name: 'Sandbox-0',
                    url: 'http://sandbox:1450',
                    token: '$new_token'
                }]
            });
            print('✅ 已建立新的 SubmissionConfig');
        }
    "

    echo ""
    echo -e "${GREEN}📋 更新後的設定:${NC}"
    echo "  Token: $new_token"
    echo ""
    echo -e "${YELLOW}⚠️  重要提醒:${NC}"
    echo "  1. 請確認 .secret/sandbox.env 中的 SANDBOX_TOKEN 與此一致:"
    echo "     SANDBOX_TOKEN=$new_token"
    echo ""
    echo "  2. 重啟 sandbox 容器:"
    echo "     docker compose $COMPOSE_FILES restart sandbox"
}

# 生成隨機 Token
generate_token() {
    # 使用 openssl 生成 32 bytes 的 base64 編碼 token
    local new_token=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    echo -e "${GREEN}🔑 生成的 Token: $new_token${NC}"
    update_token "$new_token"
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
            show_config
            ;;
        generate)
            generate_token
            ;;
        set)
            if [ -z "$2" ]; then
                echo -e "${RED}❌ 請提供 Token${NC}"
                echo "   用法: $0 set <TOKEN>"
                exit 1
            fi
            update_token "$2"
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
