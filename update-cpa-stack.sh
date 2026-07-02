#!/bin/sh
set -eu

STACK_DIR="${STACK_DIR:-/root/cpa-deploy}"
CHECK_ONLY=0
VERIFY_ONLY=0
AUTO_YES=0
CLEANUP_ONLY=0

case "${1:-}" in
  --check-only) CHECK_ONLY=1 ;;
  --verify)     VERIFY_ONLY=1 ;;
  --yes|-y)     AUTO_YES=1 ;;
  --cleanup-only) CLEANUP_ONLY=1 ;;
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

if [ ! -d "$STACK_DIR" ]; then
  echo "stack dir not found: $STACK_DIR" >&2
  exit 1
fi

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
  # 使用 GitHub token 认证（如果设置），避免 rate limit
  # 设置方式：export GITHUB_TOKEN=your_token
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

# Compare two version strings without relying on sort -V
# Returns 0 if $1 > $2, 1 otherwise
version_gt() {
  a="$(normalize_version "$1")"
  b="$(normalize_version "$2")"

  # Split into components and compare
  OLD_IFS="$IFS"
  IFS='.'
  set -- $a
  a_major="${1:-0}"; a_minor="${2:-0}"; a_patch="${3:-0}"
  set -- $b
  b_major="${1:-0}"; b_minor="${2:-0}"; b_patch="${3:-0}"
  IFS="$OLD_IFS"

  # Strip non-numeric suffixes (e.g., "1rc1" -> "1")
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

backup_compose_once() {
  if [ ! -f "$STACK_DIR/.update-compose-backed-up" ]; then
    cp "$STACK_DIR/docker-compose.yml" "$STACK_DIR/docker-compose.yml.bak-smart-update-$(date +%Y%m%d%H%M%S)"
    : > "$STACK_DIR/.update-compose-backed-up"
  fi
}

running_cli_version() {
  # 先尝试从最近 20 行获取，如果没有则从最近 200 行获取
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
  image_id="$(docker inspect -f '{{.Image}}' cpa-manager)"
  docker image inspect "$image_id" --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
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
  compose_file="$STACK_DIR/docker-compose.yml"
  if ! sed -n "/^[[:space:]]*$service:[[:space:]]*$/,/^[[:space:]]*[A-Za-z0-9_.-][A-Za-z0-9_.-]*:[[:space:]]*$/p" "$compose_file" | grep -q "image: $image"; then
    backup_compose_once
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
  docker compose -f "$STACK_DIR/docker-compose.yml" ps
  echo ""

  echo "CLIProxyAPI endpoints:"
  check_endpoint "http://127.0.0.1:8317/" "200" "/"
  check_endpoint "http://127.0.0.1:8317/v1/models" "401" "/v1/models"
  check_endpoint "http://127.0.0.1:8317/management.html" "200" "/management.html"
  echo ""

  echo "CPA Manager Plus endpoints:"
  check_endpoint "http://127.0.0.1:18317/health" "200" "/health"
  check_endpoint "http://127.0.0.1:18317/management.html" "200" "/management.html"
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
  do_verify
  exit 0
fi

if [ "$CLEANUP_ONLY" -eq 1 ]; then
  cleanup_dangling_images
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
verify_compose_container "cpa-manager" "$COMPOSE_PROJECT"

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
  echo "  ✓ cpa-manager-plus: $MGR_LOCAL (已是最新)"
elif version_gt "$MGR_LOCAL" "$MGR_LATEST"; then
  echo "  ✓ cpa-manager-plus: $MGR_LOCAL (本地更新)"
else
  echo "  ⬆ cpa-manager-plus: $MGR_LOCAL → $MGR_LATEST"
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

echo ""
if [ "$_need_update_cli" -eq 1 ]; then
  echo "正在更新 cli-proxy-api ..."
  _old_cli_image_id="$(container_image_id "cli-proxy-api")"
  ensure_image_tag "cli-proxy-api" "$CLI_IMAGE"
  docker pull "$CLI_IMAGE"
  (
    cd "$STACK_DIR"
    docker compose up -d "cli-proxy-api"
  )
  cleanup_old_image "cli-proxy-api" "$_old_cli_image_id"
  cleanup_dangling_images
  echo "✓ cli-proxy-api 更新完成"
fi

if [ "$_need_update_mgr" -eq 1 ]; then
  echo "正在更新 cpa-manager-plus ..."
  _old_mgr_image_id="$(container_image_id "cpa-manager")"
  ensure_image_tag "cpa-manager" "$MGR_IMAGE"
  docker pull "$MGR_IMAGE"
  (
    cd "$STACK_DIR"
    docker compose up -d "cpa-manager"
  )
  cleanup_old_image "cpa-manager" "$_old_mgr_image_id"
  cleanup_dangling_images
  echo "✓ cpa-manager-plus 更新完成"
fi

# ── 验证 ──

echo ""
do_verify
