#!/bin/sh
# CPA Stack Smart Update - Interactive Installer/Updater
# Usage:
#   sh install.sh                    # Interactive
#   sh install.sh --local            # Local install
#   sh install.sh user@host          # Remote install via SSH
#   sh install.sh user@host /path    # Remote with custom stack dir

SCRIPT_NAME="update-cpa-stack.sh"
SCRIPT_URL="https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh"
SSH_TIMEOUT=10

MODE=""
REMOTE=""
STACK_DIR=""

# ── Language ──

echo "Select language / 请选择语言:"
echo "  1) English"
echo "  2) 简体中文"
printf "> "
read -r _lang < /dev/tty
case "$_lang" in
  2|zh|ZH|中文) LANG=zh ;;
  *) LANG=en ;;
esac
echo ""

say() {
  if [ "$LANG" = "zh" ]; then
    case "$1" in
      mode)        echo "安装模式:" ;;
      local_m)     echo "  1) 本地安装" ;;
      remote_m)    echo "  2) 远程 SSH 安装" ;;
      host)        printf "远程地址 (例如 192.168.1.1): " ;;
      dir)         printf "部署目录 [/root/cpa-deploy]: " ;;
      conn)        printf "连接 %s ... " "$REMOTE" ;;
      ok)          echo "✓" ;;
      fail)        echo "✗" ;;
      installed)   echo "✓ 已安装脚本" ;;
      not_inst)    echo "未安装脚本" ;;
      chk_upd)     printf "检查更新 ... " ;;
      up2date)     echo "已是最新版本" ;;
      has_upd)     echo "⬆ 有新版本！" ;;
      ask_update)  printf "是否更新？(y/n): " ;;
      ask_install) printf "是否安装？(y/n): " ;;
      ask_check)   printf "是否检查更新？(y/n): " ;;
      installing)  printf "安装中 ... " ;;
      updating)    printf "更新中 ... " ;;
      done)        echo "✓ 完成" ;;
      fail_msg)    echo "✗ 失败" ;;
      verifying)   echo "验证服务 ..." ;;
      verify_ok)   echo "✓ 服务正常" ;;
      verify_fail) echo "✗ 服务异常" ;;
      err_dir)     echo "✗ 目录不存在: $STACK_DIR" ;;
      err_ssh)     echo "✗ 无法连接 $REMOTE" ;;
      bye)         echo "操作完成。" ;;
    esac
  else
    case "$1" in
      mode)        echo "Install mode:" ;;
      local_m)     echo "  1) Local" ;;
      remote_m)    echo "  2) Remote via SSH" ;;
      host)        printf "Remote address (e.g. 192.168.1.1): " ;;
      dir)         printf "Stack directory [/root/cpa-deploy]: " ;;
      conn)        printf "Connecting to %s ... " "$REMOTE" ;;
      ok)          echo "✓" ;;
      fail)        echo "✗" ;;
      installed)   echo "✓ Script installed" ;;
      not_inst)    echo "Script not installed" ;;
      chk_upd)     printf "Checking updates ... " ;;
      up2date)     echo "Up-to-date" ;;
      has_upd)     echo "Update available!" ;;
      ask_update)  printf "Update now? (y/n): " ;;
      ask_install) printf "Install now? (y/n): " ;;
      ask_check)   printf "Check for updates? (y/n): " ;;
      installing)  printf "Installing ... " ;;
      updating)    printf "Updating ... " ;;
      done)        echo "✓ Done" ;;
      fail_msg)    echo "✗ Failed" ;;
      verifying)   echo "Verifying services ..." ;;
      verify_ok)   echo "✓ All services OK" ;;
      verify_fail) echo "✗ Service check failed" ;;
      err_dir)     echo "✗ Directory not found: $STACK_DIR" ;;
      err_ssh)     echo "✗ Cannot connect to $REMOTE" ;;
      bye)         echo "Done." ;;
    esac
  fi
}

ask_yn() {
  say "$1"
  read -r _ans < /dev/tty
  case "$_ans" in
    [yY]|[yY][eE][sS]|是) return 0 ;;
    *) return 1 ;;
  esac
}

compute_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -d' ' -f1
  else
    md5 -q
  fi
}

ssh_run() {
  ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "$REMOTE" "$@" 2>/dev/null
}

# ── Parse arguments ──

case "${1:-}" in
  --local)
    MODE="local"
    STACK_DIR="${2:-/root/cpa-deploy}"
    ;;
  --help|-h)
    echo "Usage: sh install.sh [--local|user@host] [stack_dir]"
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
  say mode
  say local_m
  say remote_m
  printf "> "
  read -r _mode < /dev/tty
  case "$_mode" in
    2) MODE="remote" ;;
    *) MODE="local" ;;
  esac
  echo ""
fi

if [ "$MODE" = "remote" ] && [ -z "$REMOTE" ]; then
  say host
  read -r _host < /dev/tty
  case "$_host" in
    *@*) REMOTE="$_host" ;;
    *)   REMOTE="root@$_host" ;;
  esac
  echo ""
fi

if [ -z "$STACK_DIR" ]; then
  say dir
  read -r _dir < /dev/tty
  STACK_DIR="${_dir:-/root/cpa-deploy}"
  echo ""
fi

SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"

# ── Check connectivity ──

if [ "$MODE" = "remote" ]; then
  say conn
  if ssh_run "echo ok" >/dev/null 2>&1; then
    say ok
  else
    say fail
    exit 1
  fi
else
  if [ ! -d "$STACK_DIR" ]; then
    say err_dir
    exit 1
  fi
fi

# ── Check if installed ──

_installed=0
if [ "$MODE" = "remote" ]; then
  ssh_run "test -f '$SCRIPT_PATH'" && _installed=1 || true
else
  [ -f "$SCRIPT_PATH" ] && _installed=1 || true
fi

echo ""

if [ "$_installed" -eq 1 ]; then
  say installed

  if ask_yn ask_check; then
    say chk_upd
    _remote_hash=$(curl -fsSL --max-time 15 "$SCRIPT_URL" | compute_hash)
    if [ "$MODE" = "remote" ]; then
      _local_hash=$(ssh_run "md5sum '$SCRIPT_PATH'" | cut -d' ' -f1 || echo "none")
    else
      _local_hash=$(compute_hash < "$SCRIPT_PATH" || echo "none")
    fi

    if [ "$_remote_hash" = "$_local_hash" ]; then
      say up2date
    else
      say has_upd
      echo ""
      if ask_yn ask_update; then
        say updating
        _ok=0
        if [ "$MODE" = "remote" ]; then
          ssh_run "curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" && _ok=1 || true
        else
          curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH" && _ok=1 || true
        fi
        if [ "$_ok" -eq 1 ]; then say done; else say fail_msg; fi
      fi
    fi
  fi
else
  say not_inst

  if ask_yn ask_install; then
    say installing
    _ok=0
    if [ "$MODE" = "remote" ]; then
      ssh_run "mkdir -p '$STACK_DIR' && curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" && _ok=1 || true
    else
      mkdir -p "$STACK_DIR" && curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH" && _ok=1 || true
    fi
    if [ "$_ok" -eq 1 ]; then say done; else say fail_msg; fi
  fi
fi

# ── Verify after any change ──

echo ""
say verifying
if [ "$MODE" = "remote" ]; then
  _result=$(ssh_run "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
else
  _result=$(sh "$SCRIPT_PATH" --check-only 2>&1) || true
fi
echo "$_result"
if echo "$_result" | grep -qE "up-to-date|skip"; then
  say verify_ok
else
  say verify_fail
fi

echo ""
say bye
