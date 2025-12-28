#!/usr/bin/env python3
# =============================================================================
# update-sandbox-token.py - 更新 Sandbox Token 腳本
# =============================================================================
#
# 用法:
#   python3 scripts/update-sandbox-token.py [OPTIONS]
#
# 選項:
#   --token TOKEN       設定新的 Sandbox Token
#   --url URL           設定 Sandbox URL (預設: http://sandbox:1450)
#   --name NAME         設定 Sandbox 名稱 (預設: Sandbox-0)
#   --show              顯示目前設定
#   --generate          自動生成安全的 Token
#
# 範例:
#   # 顯示目前設定
#   python3 scripts/update-sandbox-token.py --show
#
#   # 設定新 Token
#   python3 scripts/update-sandbox-token.py --token "MySecretToken123"
#
#   # 自動生成並設定 Token
#   python3 scripts/update-sandbox-token.py --generate
#
# 注意:
#   - 需要在 Back-End 目錄下執行，或設定 PYTHONPATH
#   - 需要 MongoDB 正在運行
#   - 更新後需要同時更新 sandbox.env 中的 SANDBOX_TOKEN
#
# =============================================================================

import os
import sys
import argparse
import secrets

# 加入 Back-End 路徑
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
BACKEND_PATH = os.path.join(PROJECT_ROOT, 'Back-End')
sys.path.insert(0, BACKEND_PATH)

# 設定環境變數 (如果沒有設定)
if 'MONGO_HOST' not in os.environ:
    os.environ['MONGO_HOST'] = 'mongo'


def get_mongo_client():
    """取得 MongoDB 連線"""
    from pymongo import MongoClient

    mongo_host = os.environ.get('MONGO_HOST', 'mongo')
    mongo_port = int(os.environ.get('MONGO_PORT', 27017))

    client = MongoClient(mongo_host, mongo_port)
    return client


def get_current_config(db):
    """取得目前的 SubmissionConfig"""
    config = db.config.find_one({'_cls': 'SubmissionConfig'})
    return config


def show_current_config():
    """顯示目前的 Sandbox 設定"""
    try:
        client = get_mongo_client()
        db = client['normal-oj']

        config = get_current_config(db)

        if not config:
            print("❌ 找不到 SubmissionConfig，可能是首次部署")
            print("   請先啟動服務讓系統自動建立預設設定")
            return

        print("\n📋 目前的 Sandbox 設定:")
        print("=" * 50)

        sandbox_instances = config.get('sandboxInstances', [])

        if not sandbox_instances:
            print("   (沒有設定任何 Sandbox)")
        else:
            for i, sb in enumerate(sandbox_instances):
                print(f"\n   Sandbox #{i}:")
                print(f"   ├── Name:  {sb.get('name', 'N/A')}")
                print(f"   ├── URL:   {sb.get('url', 'N/A')}")
                print(f"   └── Token: {sb.get('token', 'N/A')}")

        print("\n" + "=" * 50)

        client.close()

    except Exception as e:
        print(f"❌ 錯誤: {e}")
        print("   請確認 MongoDB 正在運行")


def update_sandbox_token(token, url=None, name=None):
    """更新 Sandbox Token"""
    try:
        client = get_mongo_client()
        db = client['normal-oj']

        config = get_current_config(db)

        if not config:
            # 建立新的設定
            print("⚠️  找不到現有設定，建立新設定...")

            new_config = {
                '_cls': 'SubmissionConfig',
                'name': 'submission',
                'rateLimit': 0,
                'sandboxInstances': [{
                    'name': name or 'Sandbox-0',
                    'url': url or 'http://sandbox:1450',
                    'token': token
                }]
            }

            db.config.insert_one(new_config)
            print("✅ 已建立新的 SubmissionConfig")

        else:
            # 更新現有設定
            sandbox_instances = config.get('sandboxInstances', [])

            if sandbox_instances:
                # 更新第一個 sandbox
                sandbox_instances[0]['token'] = token
                if url:
                    sandbox_instances[0]['url'] = url
                if name:
                    sandbox_instances[0]['name'] = name
            else:
                # 新增 sandbox
                sandbox_instances = [{
                    'name': name or 'Sandbox-0',
                    'url': url or 'http://sandbox:1450',
                    'token': token
                }]

            db.config.update_one(
                {'_cls': 'SubmissionConfig'},
                {'$set': {'sandboxInstances': sandbox_instances}}
            )
            print("✅ 已更新 Sandbox Token")

        client.close()

        # 顯示更新後的設定
        print("\n📋 更新後的設定:")
        print(f"   Name:  {name or 'Sandbox-0'}")
        print(f"   URL:   {url or 'http://sandbox:1450'}")
        print(f"   Token: {token}")

        print("\n⚠️  重要提醒:")
        print("   請同時更新 .secret/sandbox.env 中的 SANDBOX_TOKEN:")
        print(f"   SANDBOX_TOKEN={token}")
        print("\n   然後重啟 sandbox 容器:")
        print("   docker compose -f docker-compose.yml -f docker-compose.cloud.yml restart sandbox")

    except Exception as e:
        print(f"❌ 錯誤: {e}")
        print("   請確認 MongoDB 正在運行")


def generate_token():
    """生成安全的 Token"""
    return secrets.token_urlsafe(32)


def main():
    parser = argparse.ArgumentParser(
        description='更新 Normal-OJ Sandbox Token',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
範例:
  顯示目前設定:
    python3 %(prog)s --show

  設定新 Token:
    python3 %(prog)s --token "MySecretToken123"

  自動生成並設定 Token:
    python3 %(prog)s --generate

  完整設定:
    python3 %(prog)s --token "MyToken" --url "http://sandbox:1450" --name "Sandbox-0"
        """
    )

    parser.add_argument('--token', type=str, help='設定新的 Sandbox Token')
    parser.add_argument('--url', type=str, help='設定 Sandbox URL (預設: http://sandbox:1450)')
    parser.add_argument('--name', type=str, help='設定 Sandbox 名稱 (預設: Sandbox-0)')
    parser.add_argument('--show', action='store_true', help='顯示目前設定')
    parser.add_argument('--generate', action='store_true', help='自動生成安全的 Token')

    args = parser.parse_args()

    print("\n🔧 Normal-OJ Sandbox Token 管理工具")
    print("=" * 50)

    if args.show:
        show_current_config()
    elif args.generate:
        token = generate_token()
        print(f"🔑 生成的 Token: {token}")
        update_sandbox_token(token, args.url, args.name)
    elif args.token:
        update_sandbox_token(args.token, args.url, args.name)
    else:
        # 預設顯示目前設定
        show_current_config()
        print("\n使用 --help 查看更多選項")


if __name__ == '__main__':
    main()
