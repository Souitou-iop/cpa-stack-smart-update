#!/bin/sh
set -eu

# ── 核心配置 ──
if [ -z "${STACK_DIR:-}" ]; then
  if [ -d "/mnt/docker-data/cpa-deploy" ]; then
    STACK_DIR="/mnt/docker-data/cpa-deploy"
  elif [ -d "/root/cpa-deploy" ]; then
    STACK_DIR="/root/cpa-deploy"
  else
    STACK_DIR="/mnt/docker-data/cpa-deploy"
  fi
fi

COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
MAX_BACKUPS=10
HEALTH_TIMEOUT=90
HEALTH_INTERVAL=5
CLI_HEALTH_URL="${CLI_HEALTH_URL:-http://127.0.0.1:8317/}"

# ── 参数解析 ──
CHECK_ONLY=0
VERIFY_ONLY=0
AUTO_YES=0
CLEANUP_ONLY=0
BACKUP_ONLY=0
ROLLBACK=0

case "${1:-}" in
  --check-only) CHECK_ONLY=1 ;;
  --verify)     VERIFY_ONLY=1 ;;
  --yes|-y)     AUTO_YES=1 ;;
  --cleanup-only) CLEANUP_ONLY=1 ;;
  --backup-only) BACKUP_ONLY=1 ;;
  --rollback)   ROLLBACK=1 ;;
  --help|-h)
    echo "CLIProxyAPI 自动更新脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --check-only    仅检查版本，不更新"
    echo "  --verify        仅验证服务状态"
    echo "  --cleanup-only  仅清理旧镜像和旧备份"
    echo "  --backup-only   仅备份 compose 文件"
    echo "  --rollback      回滚到最近一次备份"
    echo "  --yes, -y       跳过确认提示，自动执行"
    echo "  --help, -h      显示此帮助信息"
    exit 0
    ;;
  "") ;;
  *)
    echo "未知参数: ${1:-}" >&2
    exit 1
    ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd docker
require_cmd curl
require_cmd sed
require_cmd grep
require_cmd awk
require_cmd date

compose_project() {
  (
    cd "$STACK_DIR"
    docker compose config 2>/dev/null \
      | sed -n 's/^name:[[:space:]]*//p' \
      | head -n 1
  )
}

verify_compose_container() {
  service="$1"
  project="$2"

  if ! docker inspect "$service" >/dev/null 2>&1; then
    return 0
  fi

  container_project="$(docker inspect "$service" --format '{{index .Config.Labels "com.docker.compose.project"}}')"
  container_service="$(docker inspect "$service" --format '{{index .Config.Labels "com.docker.compose.service"}}')"

  if [ "$container_project" != "$project" ] || [ "$container_service" != "$service" ]; then
    echo "container $service exists but is not managed by compose project $project" >&2
    exit 1
  fi
}

latest_release_tag() {
  repo="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --max-time 15 -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/$repo/releases/latest" \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
  else
    curl -fsSL --max-time 15 "https://api.github.com/repos/$repo/releases/latest" \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
  fi
}

normalize_version() {
  printf '%s' "$1" | sed 's/^v//'
}

version_gt() {
  a="$(normalize_version "$1")"
  b="$(normalize_version "$2")"

  OLD_IFS="$IFS"
  IFS='.'
  set -- $a
  a_major="${1:-0}"; a_minor="${2:-0}"; a_patch="${3:-0}"
  set -- $b
  b_major="${1:-0}"; b_minor="${2:-0}"; b_patch="${3:-0}"
  IFS="$OLD_IFS"

  a_major=$(printf '%s' "$a_major" | sed 's/[^0-9].*//'); a_major="${a_major:-0}"
  a_minor=$(printf '%s' "$a_minor" | sed 's/[^0-9].*//'); a_minor="${a_minor:-0}"
  a_patch=$(printf '%s' "$a_patch" | sed 's/[^0-9].*//'); a_patch="${a_patch:-0}"
  b_major=$(printf '%s' "$b_major" | sed 's/[^0-9].*//'); b_major="${b_major:-0}"
  b_minor=$(printf '%s' "$b_minor" | sed 's/[^0-9].*//'); b_minor="${b_minor:-0}"
  b_patch=$(printf '%s' "$b_patch" | sed 's/[^0-9].*//'); b_patch="${b_patch:-0}"

  if [ "$a_major" -gt "$b_major" ] 2>/dev/null; then return 0; fi
  if [ "$a_major" -lt "$b_major" ] 2>/dev/null; then return 1; fi
  if [ "$a_minor" -gt "$b_minor" ] 2>/dev/null; then return 0; fi
  if [ "$a_minor" -lt "$b_minor" ] 2>/dev/null; then return 1; fi
  if [ "$a_patch" -gt "$b_patch" ] 2>/dev/null; then return 0; fi
  return 1
}

version_eq() {
  [ "$(normalize_version "$1")" = "$(normalize_version "$2")" ]
}

backup_compose() {
  TS=$(date +%Y%m%d%H%M%S)
  backup_file="$STACK_DIR/docker-compose.yml.bak-$TS"
  cp "$COMPOSE_FILE" "$backup_file"
  echo "✓ compose 文件备份完成: $backup_file"
}

cleanup_old_backups() {
  (
    cd "$STACK_DIR" 2>/dev/null || exit 0
    ls -t docker-compose.yml.bak-* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read -r old; do
      rm -f "$old"
    done
  )
}

running_cli_version() {
  ver=$(docker logs --tail 20 cli-proxy-api 2>&1 \
    | sed -n 's/.*CLIProxyAPI Version: \([^,]*\),.*/\1/p' \
    | tail -n 1)
  if [ -z "$ver" ]; then
    ver=$(docker logs --tail 200 cli-proxy-api 2>&1 \
      | sed -n 's/.*CLIProxyAPI Version: \([^,]*\),.*/\1/p' \
      | tail -n 1)
  fi
  echo "$ver"
}

cleanup_dangling_images() {
  if docker images -q -f dangling=true | grep -q .; then
    docker image prune -f >/dev/null
  fi
}

check_endpoint() {
  url="$1"
  expect="$2"
  label="$3"

  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expect" ]; then
    echo "  ✓ $label → $code"
  else
    echo "  ✗ $label → $code (expected $expect)"
  fi
}

do_verify() {
  echo "Compose status:"
  docker compose -f "$COMPOSE_FILE" ps
  echo ""

  echo "CLIProxyAPI endpoints:"
  check_endpoint "http://127.0.0.1:8317/" "200" "/"
  check_endpoint "http://127.0.0.1:8317/v1/models" "401" "/v1/models"
  check_endpoint "http://127.0.0.1:8317/management.html" "200" "/management.html"
}

# ── STACK_DIR 检查 ──
if [ ! -d "$STACK_DIR" ]; then
  echo "stack dir not found: $STACK_DIR" >&2
  exit 1
fi

if [ "$VERIFY_ONLY" -eq 1 ]; then
  do_verify
  exit 0
fi

CLI_IMAGE="${CLI_IMAGE:-eceasy/cli-proxy-api:latest}"
CLI_REPO="${CLI_REPO:-router-for-me/CLIProxyAPI}"

COMPOSE_PROJECT="$(compose_project)"
if [ -z "$COMPOSE_PROJECT" ]; then
  echo "failed to resolve compose project in $STACK_DIR" >&2
  exit 1
fi
verify_compose_container "cli-proxy-api" "$COMPOSE_PROJECT"

CLI_LOCAL="$(running_cli_version)"
CLI_LATEST="$(latest_release_tag "$CLI_REPO")"

echo ""
echo "  ✓ cli-proxy-api: $CLI_LOCAL (最新: $CLI_LATEST)"

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 0
fi

if version_eq "$CLI_LOCAL" "$CLI_LATEST" || version_gt "$CLI_LOCAL" "$CLI_LATEST"; then
  echo "已是最新版本，无需更新。"
  do_verify
  exit 0
fi

backup_compose
cleanup_old_backups

echo "拉取最新镜像并更新..."
docker pull "$CLI_IMAGE"
( cd "$STACK_DIR" && docker compose up -d )

cleanup_dangling_images
echo "✓ 更新完成"
echo ""
do_verify
