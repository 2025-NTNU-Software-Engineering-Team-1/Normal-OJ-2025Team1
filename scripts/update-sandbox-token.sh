#!/bin/bash
# =============================================================================
# update-sandbox-token.sh - 更新 Sandbox Token
# =============================================================================
#
# 用法:
#   ./scripts/update-sandbox-token.sh [show|init|generate|set TOKEN|sync]
#
# 命令:
#   show      - 顯示目前的 Sandbox 設定
#   init      - 初始化 SubmissionConfig（如果不存在則建立）
#   generate  - 自動生成並設定新的安全 Token
#   set TOKEN - 設定指定的 Token
#   sync      - 從 .secret/sandbox.env 讀取 Token 並同步到 MongoDB
#
# 範例:
#   ./scripts/update-sandbox-token.sh show
#   ./scripts/update-sandbox-token.sh init
#   ./scripts/update-sandbox-token.sh sync
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

# 檢查 MongoDB 容器（修正：使用 Up 而非 running）
check_mongo() {
    if ! docker compose $COMPOSE_FILES ps mongo 2>/dev/null | grep -qE "(Up|running)"; then
        echo -e "${YELLOW}⚠️  MongoDB 容器未運行，正在啟動...${NC}"
        docker compose $COMPOSE_FILES up -d mongo
        sleep 3
    fi
}

# 偵測 mongo shell 指令（mongosh 或 mongo）
detect_mongo_shell() {
    if docker compose $COMPOSE_FILES exec -T mongo which mongosh > /dev/null 2>&1; then
        echo "mongosh"
    else
        echo "mongo"
    fi
}

# 顯示目前設定
show_config() {
    local MONGO_SHELL=$(detect_mongo_shell)
    echo -e "${BLUE}📋 目前的 Sandbox 設定:${NC}"
    echo "=================================================="

    docker compose $COMPOSE_FILES exec -T mongo $MONGO_SHELL normal-oj --quiet --eval '
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

# 初始化設定（建立 SubmissionConfig）
init_config() {
    local token="${1:-KoNoSandboxDa}"
    local MONGO_SHELL=$(detect_mongo_shell)

    echo -e "${BLUE}🔧 初始化 SubmissionConfig...${NC}"

    docker compose $COMPOSE_FILES exec -T mongo $MONGO_SHELL normal-oj --quiet --eval "
        var existing = db.config.findOne({_cls: 'SubmissionConfig'});
        if (existing) {
            print('SubmissionConfig 已存在，跳過初始化');
        } else {
            db.config.insertOne({
                _cls: 'SubmissionConfig',
                name: 'submission',
                rateLimit: 0,
                sandboxInstances: [{
                    name: 'Sandbox-0',
                    url: 'http://sandbox:1450',
                    token: '$token'
                }]
            });
            print('✅ SubmissionConfig 已建立');
        }
    "
}

# 更新 Token
update_token() {
    local new_token="$1"
    local MONGO_SHELL=$(detect_mongo_shell)

    echo -e "${BLUE}🔄 更新 Token...${NC}"

    # 先檢查是否存在，不存在則建立
    docker compose $COMPOSE_FILES exec -T mongo $MONGO_SHELL normal-oj --quiet --eval "
        var existing = db.config.findOne({_cls: 'SubmissionConfig'});
        if (existing) {
            db.config.updateOne(
                {_cls: 'SubmissionConfig'},
                {\$set: {'sandboxInstances.0.token': '$new_token'}}
            );
            print('✅ Token 已更新');
        } else {
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

    # 自動重啟 sandbox
    echo -e "${BLUE}🔄 重啟 sandbox 容器...${NC}"
    docker compose $COMPOSE_FILES restart sandbox
    echo -e "${GREEN}✅ sandbox 已重啟${NC}"
}

# 從 .secret/sandbox.env 同步 Token
sync_token() {
    local env_file=".secret/sandbox.env"

    if [ ! -f "$env_file" ]; then
        echo -e "${RED}❌ 找不到 $env_file${NC}"
        exit 1
    fi

    # 讀取 SANDBOX_TOKEN
    local token=$(grep -E "^SANDBOX_TOKEN=" "$env_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -z "$token" ]; then
        echo -e "${RED}❌ 在 $env_file 中找不到 SANDBOX_TOKEN${NC}"
        exit 1
    fi

    echo -e "${GREEN}🔑 從 $env_file 讀取到 Token: $token${NC}"
    update_token "$token"
}

# 生成隨機 Token
generate_token() {
    # 使用 openssl 生成 32 bytes 的 base64 編碼 token
    local new_token=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    echo -e "${GREEN}🔑 生成的 Token: $new_token${NC}"

    # 更新 .secret/sandbox.env
    local env_file=".secret/sandbox.env"
    if [ -f "$env_file" ]; then
        if grep -q "^SANDBOX_TOKEN=" "$env_file"; then
            sed -i "s/^SANDBOX_TOKEN=.*/SANDBOX_TOKEN=$new_token/" "$env_file"
        else
            echo "SANDBOX_TOKEN=$new_token" >> "$env_file"
        fi
        echo -e "${GREEN}✅ 已更新 $env_file${NC}"
    fi

    update_token "$new_token"
}

# 顯示使用說明
show_usage() {
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  show              顯示目前的 Sandbox 設定"
    echo "  init              初始化 SubmissionConfig（使用預設 Token）"
    echo "  sync              從 .secret/sandbox.env 同步 Token 到 MongoDB"
    echo "  generate          自動生成新 Token 並同步到所有地方"
    echo "  set <TOKEN>       設定指定的 Token"
    echo ""
    echo "範例:"
    echo "  $0 show"
    echo "  $0 sync           # 推薦：同步 .secret/sandbox.env 的 Token"
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
        init)
            init_config "${2:-KoNoSandboxDa}"
            show_config
            ;;
        sync)
            sync_token
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
