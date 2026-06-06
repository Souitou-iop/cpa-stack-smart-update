#!/bin/sh
set -eu

# CPA Stack Smart Update - Interactive Installer/Updater
# Usage:
#   sh install.sh                    # Interactive: choose local or remote
#   sh install.sh --local            # Local install
#   sh install.sh user@host          # Remote install via SSH
#   sh install.sh user@host /path    # Remote install with custom stack dir

SCRIPT_NAME="update-cpa-stack.sh"
SCRIPT_URL="https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh"
SSH_TIMEOUT=10

LANG_EN=0
LANG_ZH=1
SELECTED_LANG=$LANG_EN
MODE=""  # "local" or "remote"
REMOTE=""
STACK_DIR=""

msg() {
  if [ "$SELECTED_LANG" -eq "$LANG_ZH" ]; then
    case "$1" in
      select_lang)     echo "请选择语言 / Select language:" ;;
      lang_en)         echo "1) English" ;;
      lang_zh)         echo "2) 简体中文" ;;
      select_mode)     echo "请选择安装模式 / Select install mode:" ;;
      mode_local)      echo "1) 本地安装 (Local install)" ;;
      mode_remote)     echo "2) 远程安装 (Remote install via SSH)" ;;
      enter_host)      echo "请输入远程地址 (例如 root@192.168.1.1): " ;;
      enter_dir)       echo "请输入部署目录 (默认 /root/cpa-deploy): " ;;
      checking)        echo "正在检查 ..." ;;
      installed)       echo "✓ 检测到已安装脚本。" ;;
      not_installed)   echo "✗ 未检测到脚本。" ;;
      check_update)    echo "是否检查更新？(y/n): " ;;
      install_confirm) echo "是否安装？(y/n): " ;;
      installing)      echo "正在安装脚本..." ;;
      install_ok)      echo "✓ 安装成功！" ;;
      install_fail)    echo "✗ 安装失败。" ;;
      checking_ver)    echo "正在检查更新..." ;;
      up_to_date)      echo "✓ 已是最新版本，无需更新。" ;;
      new_ver)         echo "⬆ 发现新版本！" ;;
      do_update)       echo "是否更新？(y/n): " ;;
      updating)        echo "正在更新..." ;;
      update_ok)       echo "✓ 更新成功！" ;;
      update_fail)     echo "✗ 更新失败。" ;;
      verifying)       echo "正在验证服务状态..." ;;
      verify_ok)       echo "✓ 验证通过！" ;;
      verify_fail)     echo "✗ 验证失败，请手动检查。" ;;
      ssh_fail)        echo "✗ 无法连接到 $REMOTE，请检查 SSH 配置。" ;;
      bye)             echo "操作完成。" ;;
    esac
  else
    case "$1" in
      select_lang)     echo "Select language / 请选择语言:" ;;
      lang_en)         echo "1) English" ;;
      lang_zh)         echo "2) 简体中文" ;;
      select_mode)     echo "Select install mode:" ;;
      mode_local)      echo "1) Local install" ;;
      mode_remote)     echo "2) Remote install via SSH" ;;
      enter_host)      echo "Enter remote address (e.g. root@192.168.1.1): " ;;
      enter_dir)       echo "Enter stack directory (default /root/cpa-deploy): " ;;
      checking)        echo "Checking ..." ;;
      installed)       echo "✓ Script is already installed." ;;
      not_installed)   echo "✗ Script is not installed." ;;
      check_update)    echo "Check for updates? (y/n): " ;;
      install_confirm) echo "Install now? (y/n): " ;;
      installing)      echo "Installing script..." ;;
      install_ok)      echo "✓ Installation complete!" ;;
      install_fail)    echo "✗ Installation failed." ;;
      checking_ver)    echo "Checking for updates..." ;;
      up_to_date)      echo "✓ Already up-to-date." ;;
      new_ver)         echo "⬆ New version available!" ;;
      do_update)       echo "Update now? (y/n): " ;;
      updating)        echo "Updating..." ;;
      update_ok)       echo "✓ Update complete!" ;;
      update_fail)     echo "✗ Update failed." ;;
      verifying)       echo "Verifying services..." ;;
      verify_ok)       echo "✓ Verification passed!" ;;
      verify_fail)     echo "✗ Verification failed, please check manually." ;;
      ssh_fail)        echo "✗ Cannot connect to $REMOTE, please check SSH config." ;;
      bye)             echo "Done." ;;
    esac
  fi
}

confirm() {
  printf "%s" "$(msg "$1")"
  read -r answer < /dev/tty
  case "$answer" in
    [yY]|[yY][eE][sS]|是) return 0 ;;
    *) return 1 ;;
  esac
}

select_language() {
  echo "$(msg select_lang)"
  echo "  $(msg lang_en)"
  echo "  $(msg lang_zh)"
  printf "> "
  read -r choice < /dev/tty
  case "$choice" in
    2|zh|ZH|中文) SELECTED_LANG=$LANG_ZH ;;
    *) SELECTED_LANG=$LANG_EN ;;
  esac
  echo ""
}

select_mode() {
  echo "$(msg select_mode)"
  echo "  $(msg mode_local)"
  echo "  $(msg mode_remote)"
  printf "> "
  read -r choice < /dev/tty
  case "$choice" in
    2) MODE="remote" ;;
    *) MODE="local" ;;
  esac
  echo ""
}

ask_remote_host() {
  printf "%s" "$(msg enter_host)"
  read -r REMOTE < /dev/tty
  echo ""
}

ask_stack_dir() {
  printf "%s" "$(msg enter_dir)"
  read -r input < /dev/tty
  STACK_DIR="${input:-/root/cpa-deploy}"
  echo ""
}

# ── Execution helpers ──

run_cmd() {
  if [ "$MODE" = "remote" ]; then
    ssh -o ConnectTimeout=$SSH_TIMEOUT "$REMOTE" "$@"
  else
    sh -c "$*"
  fi
}

check_ssh() {
  if ! ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "$REMOTE" "echo ok" >/dev/null 2>&1; then
    msg ssh_fail
    return 1
  fi
}

SCRIPT_PATH=""

set_script_path() {
  SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"
}

is_installed() {
  run_cmd "test -f '$SCRIPT_PATH' && echo yes || echo no" 2>/dev/null | grep -q "yes"
}

compute_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -d' ' -f1
  else
    md5 -q
  fi
}

has_update() {
  remote_hash=$(curl -fsSL --max-time 15 "$SCRIPT_URL" | compute_hash)
  local_hash=$(run_cmd "md5sum '$SCRIPT_PATH' 2>/dev/null | cut -d' ' -f1" || echo "none")
  [ "$remote_hash" != "$local_hash" ]
}

do_install() {
  msg installing
  if run_cmd "
    mkdir -p '$STACK_DIR'
    curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL'
    chmod +x '$SCRIPT_PATH'
  " 2>/dev/null; then
    msg install_ok
    return 0
  else
    msg install_fail
    return 1
  fi
}

do_update() {
  msg updating
  if run_cmd "
    curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL'
    chmod +x '$SCRIPT_PATH'
  " 2>/dev/null; then
    msg update_ok
    return 0
  else
    msg update_fail
    return 1
  fi
}

do_verify() {
  msg verifying
  result=$(run_cmd "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
  echo "$result"
  echo ""
  if echo "$result" | grep -qE "up-to-date|skip"; then
    msg verify_ok
  else
    msg verify_fail
  fi
}

# ── Parse arguments ──

case "${1:-}" in
  --local)
    MODE="local"
    STACK_DIR="${2:-/root/cpa-deploy}"
    ;;
  --help|-h)
    echo "Usage:"
    echo "  sh install.sh                    # Interactive mode"
    echo "  sh install.sh --local [dir]      # Local install"
    echo "  sh install.sh user@host [dir]    # Remote install via SSH"
    exit 0
    ;;
  "")
    # Interactive mode — ask everything
    ;;
  *)
    # First argument looks like user@host
    MODE="remote"
    REMOTE="$1"
    STACK_DIR="${2:-/root/cpa-deploy}"
    ;;
esac

# ── Main ──

select_language

# Fill in missing values interactively
if [ -z "$MODE" ]; then
  select_mode
fi
if [ "$MODE" = "remote" ] && [ -z "$REMOTE" ]; then
  ask_remote_host
fi
if [ -z "$STACK_DIR" ]; then
  ask_stack_dir
fi

set_script_path
msg checking

if [ "$MODE" = "remote" ]; then
  if ! check_ssh; then
    exit 1
  fi
fi

if is_installed; then
  msg installed
  if confirm check_update; then
    msg checking_ver
    if has_update; then
      echo ""
      msg new_ver
      if confirm do_update; then
        do_update && do_verify
      fi
    else
      msg up_to_date
    fi
  fi
else
  msg not_installed
  if confirm install_confirm; then
    do_install && do_verify
  fi
fi

echo ""
msg bye
