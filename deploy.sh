#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# Ensure required directories exist (idempotent)
mkdir -p MongoDB redis-data Sandbox/submissions Sandbox/logs .caddy
touch Back-End/gunicorn_error.log

# Load image definitions if provided via .env
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

IMAGES=()
[ -n "${WEB_IMAGE:-}" ] && IMAGES+=("$WEB_IMAGE")
[ -n "${SANDBOX_IMAGE:-}" ] && IMAGES+=("$SANDBOX_IMAGE")
[ -n "${CCPP_IMAGE:-}" ] && IMAGES+=("$CCPP_IMAGE")
[ -n "${PY3_IMAGE:-}" ] && IMAGES+=("$PY3_IMAGE")

if [ ${#IMAGES[@]} -gt 0 ]; then
  for image in "${IMAGES[@]}"; do
    echo "Pulling $image"
    docker pull "$image"
  done
fi

COMPOSE_CMD=${DOCKER_COMPOSE_BINARY:-docker compose}

$COMPOSE_CMD -f docker-compose.yml -f docker-compose.prod.yml pull
$COMPOSE_CMD -f docker-compose.yml -f docker-compose.prod.yml up -d --remove-orphans
