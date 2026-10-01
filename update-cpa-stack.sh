#!/bin/sh
set -eu

# ── 核心配置 ──
if [ -z "${STACK_DIR:-}" ]; then
  if [ -d "/mnt/docker-data/cli-proxy-api" ]; then
    STACK_DIR="/mnt/docker-data/cli-proxy-api"
  elif [ -d "/mnt/docker-data/cpa-deploy" ]; then
    STACK_DIR="/mnt/docker-data/cpa-deploy"
  else
    STACK_DIR="/mnt/docker-data/cli-proxy-api"
  fi
fi

COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
CONFIG_FILE="$STACK_DIR/config.yaml"
MAX_BACKUPS=1

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
    echo "CLIProxyAPI 智能更新脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --check-only    仅检查版本，不更新"
    echo "  --verify        仅验证服务状态"
    echo "  --cleanup-only  仅清理旧镜像和旧备份"
    echo "  --backup-only   仅备份配置文件（保留最近 $MAX_BACKUPS 份）"
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

latest_release_tag() {
  repo="$1"
  curl -fsSL --max-time 15 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' \
    | head -n 1 \
    | sed 's/.*"tag_name": *"//;s/"//g'
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

backup_configs() {
  TS=$(date +%Y%m%d%H%M%S)
  if [ -f "$COMPOSE_FILE" ]; then
    cp "$COMPOSE_FILE" "$STACK_DIR/docker-compose.yml.bak-$TS"
    echo "✓ compose 文件备份完成: docker-compose.yml.bak-$TS"
  fi
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$STACK_DIR/config.yaml.bak-$TS"
    echo "✓ config 文件备份完成: config.yaml.bak-$TS"
  fi
}

cleanup_old_backups() {
  echo "清理旧备份（仅保留最近 $MAX_BACKUPS 份）..."
  (
    cd "$STACK_DIR" 2>/dev/null || exit 0
    ls -t docker-compose.yml.bak-* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read -r old; do
      rm -f "$old"
      echo "  已删除旧 compose 备份: $old"
    done
    ls -t config.yaml.bak-* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read -r old; do
      rm -f "$old"
      echo "  已删除旧 config 备份: $old"
    done
  )
}

running_cli_version() {
  docker logs cli-proxy-api 2>&1 | grep -oE 'Version: v[0-9.]+' | tail -n 1 | awk '{print $2}'
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
    return 1
  fi
}

check_v8_config() {
  if grep -Eq '^config-version:[[:space:]]*8[[:space:]]*$' "$CONFIG_FILE" \
    && grep -Eq '^server:' "$CONFIG_FILE" \
    && grep -Eq '^management:' "$CONFIG_FILE" \
    && grep -Eq '^access:' "$CONFIG_FILE" \
    && grep -Eq '^routing:' "$CONFIG_FILE" \
    && grep -Eq '^oauth:' "$CONFIG_FILE"; then
    echo "  ✓ CPA 配置已是 v8 布局"
  else
    echo "  ✗ CPA 配置不是完整的 v8 布局"
    return 1
  fi
}

check_api_models() {
  _api_key=$(awk '
    /^access:/ { in_access=1; next }
    in_access && /^[^[:space:]]/ { in_access=0 }
    in_access && /^[[:space:]]+api-keys:/ { in_keys=1; next }
    in_keys && /^[^[:space:]]/ { in_keys=0 }
    in_keys && /^[[:space:]]+- / {
      value=$0
      sub(/^[[:space:]]*- /, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "$CONFIG_FILE")
  if [ -z "$_api_key" ]; then
    echo "  ✗ 无法读取 access.api-keys"
    return 1
  fi
  _code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Authorization: Bearer $_api_key" \
    http://127.0.0.1:8317/v1/models 2>/dev/null || echo "000")
  if [ "$_code" = "200" ]; then
    echo "  ✓ CPA 业务 API (/v1/models) → $_code"
  else
    echo "  ✗ CPA 业务 API (/v1/models) → $_code (expected 200)"
    return 1
  fi
}

do_verify() {
  echo "Compose 状态:"
  ( cd "$STACK_DIR" && docker compose ps )
  echo ""

  echo "服务健康检查:"
  check_v8_config
  check_endpoint "http://127.0.0.1:8317/" "200" "CLIProxyAPI 根路径 (/)"
  check_endpoint "http://127.0.0.1:8317/management.html" "200" "CPA 管理中心 (/management.html)"
  check_endpoint "http://127.0.0.1:8318/keeper/" "200" "CPA Usage Keeper 独立面板 (:8318)"
  check_api_models
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

if [ "$BACKUP_ONLY" -eq 1 ]; then
  echo "── 仅备份模式 ──"
  backup_configs
  cleanup_old_backups
  echo "✓ 备份已完成"
  exit 0
fi

if [ "$ROLLBACK" -eq 1 ]; then
  echo "── 回滚模式 ──"
  _rollback_ts=$(for _cfg in "$STACK_DIR"/config.yaml.bak-*; do
    [ -f "$_cfg" ] || continue
    _ts=${_cfg##*/config.yaml.bak-}
    [ -f "$STACK_DIR/docker-compose.yml.bak-$_ts" ] && printf '%s\n' "$_ts"
  done | sort -r | head -n 1)
  if [ -z "$_rollback_ts" ]; then
    echo "✗ 找不到同一时间戳的 compose/config 成对备份，拒绝回滚" >&2
    exit 1
  fi
  _latest_compose="$STACK_DIR/docker-compose.yml.bak-$_rollback_ts"
  _latest_config="$STACK_DIR/config.yaml.bak-$_rollback_ts"
  cp "$_latest_compose" "$COMPOSE_FILE"
  cp "$_latest_config" "$CONFIG_FILE"
  echo "✓ 已恢复成对备份: $_rollback_ts"
  ( cd "$STACK_DIR" && docker compose up -d cli-proxy-api )
  echo "✓ 回滚完成"
  do_verify
  exit 0
fi

if [ "$CLEANUP_ONLY" -eq 1 ]; then
  echo "── 清理模式 ──"
  cleanup_old_backups
  cleanup_dangling_images
  echo "✓ 清理完成"
  exit 0
fi

CLI_IMAGE="${CLI_IMAGE:-eceasy/cli-proxy-api:latest}"
CLI_REPO="${CLI_REPO:-router-for-me/CLIProxyAPI}"

CLI_LOCAL="$(running_cli_version)"
CLI_LATEST="$(latest_release_tag "$CLI_REPO")"

echo ""
echo "  ✓ cli-proxy-api: $CLI_LOCAL (GitHub 最新发布: $CLI_LATEST)"

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 0
fi

if [ -n "$CLI_LOCAL" ] && [ -n "$CLI_LATEST" ]; then
  if version_eq "$CLI_LOCAL" "$CLI_LATEST" || version_gt "$CLI_LOCAL" "$CLI_LATEST"; then
    echo "已是最新版本，无需更新。"
    echo ""
    do_verify
    exit 0
  fi
fi

backup_configs
cleanup_old_backups

echo "拉取最新镜像并更新 cli-proxy-api..."
docker pull "$CLI_IMAGE"
( cd "$STACK_DIR" && docker compose up -d cli-proxy-api )

cleanup_dangling_images
echo "✓ 更新完成"
echo ""
do_verify
