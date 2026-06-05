#!/bin/busybox sh
set -eu

STACK_DIR="${STACK_DIR:-/root/cpa-deploy}"
CHECK_ONLY=0

if [ "${1:-}" = "--check-only" ]; then
  CHECK_ONLY=1
fi

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
require_cmd sort
require_cmd date

if [ ! -d "$STACK_DIR" ]; then
  echo "stack dir not found: $STACK_DIR" >&2
  exit 1
fi

latest_release_tag() {
  repo="$1"
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

normalize_version() {
  printf '%s' "$1" | sed 's/^v//'
}

version_gt() {
  a="$(normalize_version "$1")"
  b="$(normalize_version "$2")"
  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" = "$a" ] && [ "$a" != "$b" ]
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
  docker logs --tail 20 cli-proxy-api 2>&1 \
    | sed -n 's/.*CLIProxyAPI Version: \([^,]*\),.*/\1/p' \
    | tail -n 1
}

running_manager_version() {
  image_id="$(docker inspect -f '{{.Image}}' cpa-manager)"
  docker image inspect "$image_id" --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
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

update_service() {
  service="$1"
  image="$2"
  latest="$3"
  local_ver="$4"

  echo "[$service] local=$local_ver latest=$latest"

  if version_eq "$local_ver" "$latest"; then
    echo "[$service] up-to-date, skip"
    return 0
  fi

  if version_gt "$local_ver" "$latest"; then
    echo "[$service] local version is newer than upstream release, skip"
    return 0
  fi

  echo "[$service] update available"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    return 0
  fi

  ensure_image_tag "$service" "$image"
  docker pull "$image"
  (
    cd "$STACK_DIR"
    docker compose up -d "$service"
  )
}

CLI_IMAGE="${CLI_IMAGE:-eceasy/cli-proxy-api:latest}"
CLI_REPO="${CLI_REPO:-router-for-me/CLIProxyAPI}"
MGR_IMAGE="${MGR_IMAGE:-seakee/cpa-manager:latest}"
MGR_REPO="${MGR_REPO:-seakee/CPA-Manager}"

CLI_LOCAL="$(running_cli_version)"
MGR_LOCAL="$(running_manager_version)"
CLI_LATEST="$(latest_release_tag "$CLI_REPO")"
MGR_LATEST="$(latest_release_tag "$MGR_REPO")"

if [ -z "$CLI_LOCAL" ] || [ -z "$MGR_LOCAL" ] || [ -z "$CLI_LATEST" ] || [ -z "$MGR_LATEST" ]; then
  echo "failed to resolve one or more versions" >&2
  echo "cli_local=$CLI_LOCAL cli_latest=$CLI_LATEST mgr_local=$MGR_LOCAL mgr_latest=$MGR_LATEST" >&2
  exit 1
fi

update_service "cli-proxy-api" "$CLI_IMAGE" "$CLI_LATEST" "$CLI_LOCAL"
update_service "cpa-manager" "$MGR_IMAGE" "$MGR_LATEST" "$MGR_LOCAL"

if [ "$CHECK_ONLY" -eq 0 ]; then
  echo "post-check:"
  docker compose -f "$STACK_DIR/docker-compose.yml" ps
fi
