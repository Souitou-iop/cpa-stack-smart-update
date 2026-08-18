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
# CLIProxyAPI 健康检查端点（返回 200 表示服务就绪）
CLI_HEALTH_URL="${CLI_HEALTH_URL:-http://127.0.0.1:8317/}"
# CPA Manager Plus 健康检查端点（返回 200 表示服务就绪）
MGR_HEALTH_URL="${MGR_HEALTH_URL:-http://127.0.0.1:18317/health}"
# 公网健康检查端点（可选，设置后在 --verify 时同时检查公网）
PUBLIC_HEALTH_URL="${PUBLIC_HEALTH_URL:-}"

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
    echo "CPA Stack (CLIProxyAPI + CPA Manager Plus) 自动更新脚本"
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
    echo ""
    echo "示例:"
    echo "  $0                    # 检查并交互式更新"
    echo "  $0 --check-only       # 仅检查版本"
    echo "  $0 --verify           # 验证服务状态"
    echo "  $0 --backup-only      # 仅备份 compose 文件"
    echo "  $0 --rollback         # 回滚到最近一次备份"
    echo "  $0 --yes              # 跳过确认直接更新"
    echo "  $0 --cleanup-only     # 清理旧镜像和旧备份"
    echo ""
    echo "环境变量:"
    echo "  STACK_DIR           部署目录（默认: /mnt/docker-data/cpa-deploy 或 /root/cpa-deploy）"
    echo "  PUBLIC_HEALTH_URL   公网健康检查端点（可选）"
    echo "  GITHUB_TOKEN        GitHub API token（可选，避免 rate limit）"
    echo "  CLI_IMAGE           CLIProxyAPI 镜像（默认: eceasy/cli-proxy-api:latest）"
    echo "  MGR_IMAGE           CPA Manager 镜像（默认: seakee/cpa-manager-plus:latest）"
    echo "  CLI_HEALTH_URL      CLIProxyAPI 健康检查端点"
    echo "  MGR_HEALTH_URL      CPA Manager 健康检查端点"
    exit 0
    ;;
  "") ;;
  *)
    echo "未知参数: ${1:-}" >&2
    echo "使用 --help 查看用法" >&2
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

resolve_manager_service() {
  if docker inspect cpa-manager-plus >/dev/null 2>&1; then
    echo "cpa-manager-plus"
  elif docker inspect cpa-manager >/dev/null 2>&1; then
    echo "cpa-manager"
  else
    echo "cpa-manager-plus"
  fi
}

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
    echo "fix once: cd $STACK_DIR && docker stop $service && docker rm $service && docker compose up -d $service" >&2
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
  echo "清理旧 compose 备份（保留最近 $MAX_BACKUPS 份）..."
  (
    cd "$STACK_DIR" 2>/dev/null || exit 0
    ls -t docker-compose.yml.bak-* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read -r old; do
      rm -f "$old"
      echo "  已删除旧 compose 备份: $old"
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

running_manager_version() {
  mgr_svc="$(resolve_manager_service)"
  image_id="$(docker inspect -f '{{.Image}}' "$mgr_svc" 2>/dev/null || true)"
  if [ -n "$image_id" ]; then
    docker image inspect "$image_id" --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null || true
  fi
}

container_image_id() {
  service="$1"
  docker inspect -f '{{.Image}}' "$service" 2>/dev/null || true
}

cleanup_old_image() {
  service="$1"
  old_image_id="$2"
  current_image_id="$(container_image_id "$service")"

  if [ -z "$old_image_id" ] || [ "$old_image_id" = "$current_image_id" ]; then
    return 0
  fi

  echo "正在清理 $service 旧镜像 ..."
  if docker image rm "$old_image_id" >/dev/null 2>&1; then
    echo "✓ 已删除 $service 旧镜像 $old_image_id"
  else
    echo "  ! 跳过 $service 旧镜像 $old_image_id（可能仍被其他容器使用）"
  fi
}

cleanup_dangling_images() {
  if docker images -q -f dangling=true | grep -q .; then
    echo "正在清理未使用的悬空镜像 ..."
    docker image prune -f >/dev/null
    echo "✓ 悬空镜像清理完成"
  fi
}

ensure_image_tag() {
  service="$1"
  image="$2"
  compose_file="$COMPOSE_FILE"
  if ! sed -n "/^[[:space:]]*$service:[[:space:]]*$/,/^[[:space:]]*[A-Za-z0-9_.-][A-Za-z0-9_.-]*:[[:space:]]*$/p" "$compose_file" | grep -q "image: $image"; then
    backup_compose
    tmp_file="$compose_file.tmp.$$"
    awk -v service="$service" -v image_line="    image: $image" '
      /^[[:space:]]*[A-Za-z0-9_.-][A-Za-z0-9_.-]*:[[:space:]]*$/ {
        in_service = ($1 == service ":")
      }
      in_service && /^[[:space:]]*image:[[:space:]]*/ {
        print image_line
        changed = 1
        next
      }
      { print }
      END { if (!changed) exit 2 }
    ' "$compose_file" > "$tmp_file" || {
      rm -f "$tmp_file"
      echo "failed to update image for service: $service" >&2
      exit 1
    }
    mv "$tmp_file" "$compose_file"
  fi
}

wait_for_health() {
  url="$1"
  timeout="$2"
  interval="$3"
  label="${4:-服务}"

  elapsed=0
  printf "等待 %s 健康检查通过 ...\n" "$label"
  while [ "$elapsed" -lt "$timeout" ]; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
      printf "✓ %s 健康检查通过 (%ds)\n" "$label" "$elapsed"
      return 0
    fi
    printf "  ... 等待中 (%ds/%ds, HTTP %s)\n" "$elapsed" "$timeout" "$code"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  printf "✗ %s 健康检查超时（%ds）\n" "$label" "$timeout" >&2
  return 1
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
  
  cpa_html_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:8317/management.html" 2>/dev/null || echo "000")
  if [ "$cpa_html_code" = "200" ]; then
    echo "  ✓ /management.html → 200 (control panel enabled)"
  elif [ "$cpa_html_code" = "404" ]; then
    echo "  ✓ /management.html → 404 (control panel disabled as configured)"
  else
    echo "  ✗ /management.html → $cpa_html_code"
  fi
  echo ""

  echo "CPA Manager Plus endpoints:"
  check_endpoint "http://127.0.0.1:18317/health" "200" "/health"
  check_endpoint "http://127.0.0.1:18317/management.html" "200" "/management.html"

  if [ -n "$PUBLIC_HEALTH_URL" ]; then
    echo ""
    echo "Public health endpoint:"
    check_endpoint "$PUBLIC_HEALTH_URL" "200" "public"
  fi
}

show_rollback_hint() {
  mgr_svc="$(resolve_manager_service)"
  echo ""
  echo "✗ 更新失败，可执行手动回滚:"
  echo "  cd $STACK_DIR"
  echo "  cp docker-compose.yml.bak-<timestamp> docker-compose.yml"
  echo "  docker compose up -d cli-proxy-api $mgr_svc"
  echo ""
  echo "或使用脚本回滚:"
  echo "  $0 --rollback"
  echo ""
  _latest_bak=$(ls -t "$STACK_DIR"/docker-compose.yml.bak-* 2>/dev/null | head -n 1 || true)
  if [ -n "$_latest_bak" ]; then
    echo "最近备份: $_latest_bak"
    echo "  cp \"$_latest_bak\" \"$COMPOSE_FILE\""
    echo "  docker compose up -d cli-proxy-api $mgr_svc"
  fi
}

# ── STACK_DIR 检查 ──

if [ ! -d "$STACK_DIR" ]; then
  echo "stack dir not found: $STACK_DIR" >&2
  exit 1
fi

MGR_SERVICE="$(resolve_manager_service)"

# ── 回滚模式 ──

if [ "$ROLLBACK" -eq 1 ]; then
  echo "── 回滚模式 ──"
  echo ""
  _latest_bak=$(ls -t "$STACK_DIR"/docker-compose.yml.bak-* 2>/dev/null | head -n 1 || true)
  if [ -z "$_latest_bak" ]; then
    echo "✗ 未找到 docker-compose.yml 备份" >&2
    exit 1
  fi
  echo "正在恢复最近备份: $_latest_bak"
  cp "$_latest_bak" "$COMPOSE_FILE"
  echo "✓ 已恢复 compose 文件"
  (
    cd "$STACK_DIR"
    docker compose up -d
  )
  echo ""
  wait_for_health "$CLI_HEALTH_URL" "$HEALTH_TIMEOUT" "$HEALTH_INTERVAL" "CLIProxyAPI" || true
  wait_for_health "$MGR_HEALTH_URL" "$HEALTH_TIMEOUT" "$HEALTH_INTERVAL" "CPA Manager" || true
  echo ""
  do_verify
  exit 0
fi

if [ "$VERIFY_ONLY" -eq 1 ]; then
  do_verify
  exit 0
fi

# ── 仅备份模式 ──

if [ "$BACKUP_ONLY" -eq 1 ]; then
  echo "── 仅备份模式 ──"
  echo ""
  backup_compose
  cleanup_old_backups
  echo ""
  echo "✓ 备份完成"
  exit 0
fi

if [ "$CLEANUP_ONLY" -eq 1 ]; then
  cleanup_dangling_images
  cleanup_old_backups
  exit 0
fi

CLI_IMAGE="${CLI_IMAGE:-eceasy/cli-proxy-api:latest}"
CLI_REPO="${CLI_REPO:-router-for-me/CLIProxyAPI}"
MGR_IMAGE="${MGR_IMAGE:-seakee/cpa-manager-plus:latest}"
MGR_REPO="${MGR_REPO:-seakee/CPA-Manager-Plus}"

COMPOSE_PROJECT="$(compose_project)"
if [ -z "$COMPOSE_PROJECT" ]; then
  echo "failed to resolve compose project in $STACK_DIR" >&2
  exit 1
fi
verify_compose_container "cli-proxy-api" "$COMPOSE_PROJECT"
verify_compose_container "$MGR_SERVICE" "$COMPOSE_PROJECT"

CLI_LOCAL="$(running_cli_version)"
MGR_LOCAL="$(running_manager_version)"
CLI_LATEST="$(latest_release_tag "$CLI_REPO")"
MGR_LATEST="$(latest_release_tag "$MGR_REPO")"

if [ -z "$CLI_LOCAL" ] || [ -z "$MGR_LOCAL" ] || [ -z "$CLI_LATEST" ] || [ -z "$MGR_LATEST" ]; then
  echo "failed to resolve one or more versions" >&2
  echo "cli_local=$CLI_LOCAL cli_latest=$CLI_LATEST mgr_local=$MGR_LOCAL mgr_latest=$MGR_LATEST" >&2
  exit 1
fi

# ── 显示版本状态 ──

echo ""
if version_eq "$CLI_LOCAL" "$CLI_LATEST"; then
  echo "  ✓ cli-proxy-api: $CLI_LOCAL (已是最新)"
elif version_gt "$CLI_LOCAL" "$CLI_LATEST"; then
  echo "  ✓ cli-proxy-api: $CLI_LOCAL (本地更新)"
else
  echo "  ⬆ cli-proxy-api: $CLI_LOCAL → $CLI_LATEST"
fi

if version_eq "$MGR_LOCAL" "$MGR_LATEST"; then
  echo "  ✓ $MGR_SERVICE: $MGR_LOCAL (已是最新)"
elif version_gt "$MGR_LOCAL" "$MGR_LATEST"; then
  echo "  ✓ $MGR_SERVICE: $MGR_LOCAL (本地更新)"
else
  echo "  ⬆ $MGR_SERVICE: $MGR_LOCAL → $MGR_LATEST"
fi

# ── 检查是否有需要更新的服务 ──

_need_update_cli=0
_need_update_mgr=0

if ! version_eq "$CLI_LOCAL" "$CLI_LATEST" && ! version_gt "$CLI_LOCAL" "$CLI_LATEST"; then
  _need_update_cli=1
fi

if ! version_eq "$MGR_LOCAL" "$MGR_LATEST" && ! version_gt "$MGR_LOCAL" "$MGR_LATEST"; then
  _need_update_mgr=1
fi

# ── 如果是 check-only 模式，到此为止 ──

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 0
fi

# ── 如果没有需要更新的服务，直接进入验证 ──

if [ "$_need_update_cli" -eq 0 ] && [ "$_need_update_mgr" -eq 0 ]; then
  echo ""
  echo "所有服务已是最新版本。"
  do_verify
  exit 0
fi

# ── 询问用户是否更新 ──

echo ""
if [ "$AUTO_YES" -eq 0 ]; then
  printf "是否更新以上服务？(y/n): "
  read -r _ans
  case "$_ans" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "已跳过更新。"
      do_verify
      exit 0
      ;;
  esac
fi

# ── 执行更新 ──

backup_compose
cleanup_old_backups

echo ""
if [ "$_need_update_cli" -eq 1 ]; then
  echo "正在更新 cli-proxy-api ..."
  _old_cli_image_id="$(container_image_id "cli-proxy-api")"
  ensure_image_tag "cli-proxy-api" "$CLI_IMAGE"
  if ! docker pull "$CLI_IMAGE"; then
    echo "✗ docker pull $CLI_IMAGE 失败" >&2
    echo "最近日志:" >&2
    docker logs --tail 30 cli-proxy-api 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  if ! ( cd "$STACK_DIR" && docker compose up -d "cli-proxy-api" ); then
    echo "✗ docker compose up -d cli-proxy-api 失败" >&2
    echo "最近日志:" >&2
    docker logs --tail 30 cli-proxy-api 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  if ! wait_for_health "$CLI_HEALTH_URL" "$HEALTH_TIMEOUT" "$HEALTH_INTERVAL" "CLIProxyAPI"; then
    echo "最近日志:" >&2
    docker logs --tail 30 cli-proxy-api 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  cleanup_old_image "cli-proxy-api" "$_old_cli_image_id"
  cleanup_dangling_images
  echo "✓ cli-proxy-api 更新完成"
fi

if [ "$_need_update_mgr" -eq 1 ]; then
  echo "正在更新 $MGR_SERVICE ..."
  _old_mgr_image_id="$(container_image_id "$MGR_SERVICE")"
  ensure_image_tag "$MGR_SERVICE" "$MGR_IMAGE"
  if ! docker pull "$MGR_IMAGE"; then
    echo "✗ docker pull $MGR_IMAGE 失败" >&2
    echo "最近日志:" >&2
    docker logs --tail 30 "$MGR_SERVICE" 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  if ! ( cd "$STACK_DIR" && docker compose up -d "$MGR_SERVICE" ); then
    echo "✗ docker compose up -d $MGR_SERVICE 失败" >&2
    echo "最近日志:" >&2
    docker logs --tail 30 "$MGR_SERVICE" 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  if ! wait_for_health "$MGR_HEALTH_URL" "$HEALTH_TIMEOUT" "$HEALTH_INTERVAL" "CPA Manager"; then
    echo "最近日志:" >&2
    docker logs --tail 30 "$MGR_SERVICE" 2>&1 || true
    show_rollback_hint
    exit 1
  fi
  cleanup_old_image "$MGR_SERVICE" "$_old_mgr_image_id"
  cleanup_dangling_images
  echo "✓ $MGR_SERVICE 更新完成"
fi

# ── 验证 ──

echo ""
do_verify
