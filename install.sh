#!/bin/sh
set -eu

# CPA Stack Smart Update - Interactive Installer/Updater
# Usage:
#   sh install.sh                    # Interactive
#   sh install.sh --local            # Local install
#   sh install.sh user@host          # Remote install via SSH
#   sh install.sh user@host /path    # Remote with custom stack dir

SCRIPT_NAME="update-cpa-stack.sh"
SCRIPT_URL="https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh"
SSH_TIMEOUT=10

LANG_EN=0
LANG_ZH=1
SELECTED_LANG=$LANG_EN
MODE=""
REMOTE=""
STACK_DIR=""

log() {
  if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
    case "$1" in
      checking_remote)  printf "正在连接 %s ... " "$REMOTE" ;;
      checking_local)   echo "正在检查本地环境 ..." ;;
      installed)        echo "✓ 已安装" ;;
      not_installed)    echo "✗ 未安装" ;;
      checking_ver)     printf "正在检查更新 ... " ;;
      up_to_date)       echo "已是最新版本" ;;
      new_ver)          echo "发现新版本" ;;
      installing)       printf "正在安装 ... " ;;
      install_ok)       echo "✓ 安装成功" ;;
      updating)         printf "正在更新 ... " ;;
      update_ok)        echo "✓ 更新成功" ;;
      verifying)        echo "正在验证服务 ..." ;;
      verify_ok)        echo "✓ 验证通过" ;;
      verify_fail)      echo "✗ 验证失败" ;;
      done)             echo "操作完成。" ;;
      err_connect)      echo "✗ 连接失败" ;;
      err_dir)          echo "✗ 目录不存在: $STACK_DIR" ;;
      err_script)       echo "✗ 安装/更新失败" ;;
    esac
  else
    case "$1" in
      checking_remote)  printf "Connecting to %s ... " "$REMOTE" ;;
      checking_local)   echo "Checking local environment ..." ;;
      installed)        echo "✓ Installed" ;;
      not_installed)    echo "✗ Not installed" ;;
      checking_ver)     printf "Checking for updates ... " ;;
      up_to_date)       echo "Up-to-date" ;;
      new_ver)          echo "Update available" ;;
      installing)       printf "Installing ... " ;;
      install_ok)       echo "✓ Done" ;;
      updating)         printf "Updating ... " ;;
      update_ok)        echo "✓ Done" ;;
      verifying)        echo "Verifying services ..." ;;
      verify_ok)        echo "✓ All good" ;;
      verify_fail)      echo "✗ Verification failed" ;;
      done)             echo "Done." ;;
      err_connect)      echo "✗ Connection failed" ;;
      err_dir)          echo "✗ Directory not found: $STACK_DIR" ;;
      err_script)       echo "✗ Install/update failed" ;;
    esac
  fi
}

confirm() {
  case "$1" in
    check_update)
      if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
        printf "是否检查更新？(y/n): "
      else
        printf "Check for updates? (y/n): "
      fi
      ;;
    install)
      if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
        printf "是否安装？(y/n): "
      else
        printf "Install now? (y/n): "
      fi
      ;;
    update)
      if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
        printf "是否更新？(y/n): "
      else
        printf "Update now? (y/n): "
      fi
      ;;
  esac
  read -r answer < /dev/tty
  case "$answer" in
    [yY]|[yY][eE][sS]|是) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Language / Mode selection ──

if [ "$SELECTED_LANG" -eq "$LANG_EN" ]; then
  echo "Select language:"
  echo "  1) English"
  echo "  2) 简体中文"
else
  echo "请选择语言:"
  echo "  1) English"
  echo "  2) 简体中文"
fi
printf "> "
read -r choice < /dev/tty
case "$choice" in
  2|zh|ZH|中文) SELECTED_LANG=$LANG_ZH ;;
  *) SELECTED_LANG=$LANG_EN ;;
esac
echo ""

# ── Parse arguments ──

case "${1:-}" in
  --local)
    MODE="local"
    STACK_DIR="${2:-/root/cpa-deploy}"
    ;;
  --help|-h)
    echo "Usage:"
    echo "  sh install.sh                    # Interactive"
    echo "  sh install.sh --local [dir]      # Local install"
    echo "  sh install.sh user@host [dir]    # Remote via SSH"
    exit 0
    ;;
  "")
    ;;
  *)
    MODE="remote"
    REMOTE="$1"
    STACK_DIR="${2:-/root/cpa-deploy}"
    ;;
esac

# ── Ask missing values ──

if [ -z "$MODE" ]; then
  if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
    echo "安装模式:"
    echo "  1) 本地安装"
    echo "  2) 远程 SSH 安装"
  else
    echo "Install mode:"
    echo "  1) Local"
    echo "  2) Remote via SSH"
  fi
  printf "> "
  read -r choice < /dev/tty
  case "$choice" in
    2) MODE="remote" ;;
    *) MODE="local" ;;
  esac
  echo ""
fi

if [ "$MODE" = "remote" ] && [ -z "$REMOTE" ]; then
  if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
    printf "远程地址 (例如 192.168.1.1 或 root@192.168.1.1): "
  else
    printf "Remote address (e.g. 192.168.1.1 or root@192.168.1.1): "
  fi
  read -r host_input < /dev/tty
  case "$host_input" in
    *@*) REMOTE="$host_input" ;;
    *)   REMOTE="root@$host_input" ;;
  esac
  echo ""
fi

if [ -z "$STACK_DIR" ]; then
  if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
    printf "部署目录 [/root/cpa-deploy]: "
  else
    printf "Stack directory [/root/cpa-deploy]: "
  fi
  read -r input < /dev/tty
  STACK_DIR="${input:-/root/cpa-deploy}"
  echo ""
fi

SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"

# ── Helpers ──

remote_exec() {
  ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "$REMOTE" "$@"
}

check_remote() {
  log checking_remote
  if remote_exec "test -d '$STACK_DIR'" 2>/dev/null; then
    echo "✓"
    return 0
  else
    log err_connect
    return 1
  fi
}

check_local() {
  log checking_local
  if [ -d "$STACK_DIR" ]; then
    return 0
  else
    log err_dir
    return 1
  fi
}

is_installed() {
  if [ "$MODE" = "remote" ]; then
    remote_exec "test -f '$SCRIPT_PATH'" 2>/dev/null
  else
    test -f "$SCRIPT_PATH"
  fi
}

compute_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -d' ' -f1
  else
    md5 -q
  fi
}

has_update() {
  log checking_ver
  remote_hash=$(curl -fsSL --max-time 15 "$SCRIPT_URL" | compute_hash)
  if [ "$MODE" = "remote" ]; then
    local_hash=$(remote_exec "md5sum '$SCRIPT_PATH' 2>/dev/null | cut -d' ' -f1" || echo "none")
  else
    local_hash=$(md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 || echo "none")
  fi
  if [ "$remote_hash" != "$local_hash" ]; then
    log new_ver
    return 0
  else
    log up_to_date
    return 1
  fi
}

do_install() {
  log installing
  if [ "$MODE" = "remote" ]; then
    remote_exec "mkdir -p '$STACK_DIR' && curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" 2>/dev/null
  else
    mkdir -p "$STACK_DIR" && curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH"
  fi && log install_ok || { log err_script; return 1; }
}

do_update() {
  log updating
  if [ "$MODE" = "remote" ]; then
    remote_exec "curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" 2>/dev/null
  else
    curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH"
  fi && log update_ok || { log err_script; return 1; }
}

do_verify() {
  log verifying
  if [ "$MODE" = "remote" ]; then
    result=$(remote_exec "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
  else
    result=$(sh "$SCRIPT_PATH" --check-only 2>&1) || true
  fi
  echo "$result"
  if echo "$result" | grep -qE "up-to-date|skip"; then
    log verify_ok
  else
    log verify_fail
  fi
}

# ── Main ──

# Check connectivity / directory
if [ "$MODE" = "remote" ]; then
  check_remote || exit 1
else
  check_local || exit 1
fi

if is_installed; then
  log installed
  if confirm check_update; then
    if has_update; then
      if confirm update; then
        do_update && do_verify
      fi
    fi
  fi
else
  log not_installed
  if confirm install; then
    do_install && do_verify
  fi
fi

echo ""
log done
