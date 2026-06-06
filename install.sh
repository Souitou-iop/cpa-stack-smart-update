#!/bin/sh
# CPA Stack Smart Update - Installer/Updater

SCRIPT_NAME="update-cpa-stack.sh"
SCRIPT_URL="https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh"

# ── Language ──

echo "Select language / 请选择语言:"
echo "  1) English"
echo "  2) 简体中文"
printf "> "
read -r _lang < /dev/tty
case "$_lang" in
  2|zh|ZH|中文) L=zh ;;
  *) L=en ;;
esac
echo ""

# ── Helper: bilingual messages ──

msg() {
  case "$1" in
    mode)       [ "$L" = "zh" ] && echo "安装模式:" || echo "Install mode:" ;;
    local_m)    [ "$L" = "zh" ] && echo "  1) 本地安装" || echo "  1) Local" ;;
    remote_m)   [ "$L" = "zh" ] && echo "  2) 远程 SSH 安装" || echo "  2) Remote via SSH" ;;
    host)       [ "$L" = "zh" ] && printf "远程地址 (例如 192.168.1.1): " || printf "Remote address (e.g. 192.168.1.1): " ;;
    dir)        [ "$L" = "zh" ] && printf "部署目录 [/root/cpa-deploy]: " || printf "Stack directory [/root/cpa-deploy]: " ;;
    conn_ok)    [ "$L" = "zh" ] && echo "✓ 连接成功" || echo "✓ Connected" ;;
    conn_fail)  [ "$L" = "zh" ] && echo "✗ 连接失败" || echo "✗ Connection failed" ;;
    installed)  [ "$L" = "zh" ] && echo "✓ 已安装脚本" || echo "✓ Script installed" ;;
    not_inst)   [ "$L" = "zh" ] && echo "未安装脚本" || echo "Script not installed" ;;
    chk_ok)     [ "$L" = "zh" ] && echo "✓ 已是最新版本" || echo "✓ Up-to-date" ;;
    chk_new)    [ "$L" = "zh" ] && echo "⬆ 有新版本！" || echo "⬆ Update available!" ;;
    ask_check)  [ "$L" = "zh" ] && printf "检查更新？(y/n): " || printf "Check for updates? (y/n): " ;;
    ask_install)[ "$L" = "zh" ] && printf "安装？(y/n): " || printf "Install? (y/n): " ;;
    ask_update) [ "$L" = "zh" ] && printf "更新？(y/n): " || printf "Update? (y/n): " ;;
    doing_inst) [ "$L" = "zh" ] && echo "正在安装 ..." || echo "Installing ..." ;;
    doing_upd)  [ "$L" = "zh" ] && echo "正在更新 ..." || echo "Updating ..." ;;
    ok)         [ "$L" = "zh" ] && echo "✓ 完成" || echo "✓ Done" ;;
    fail)       [ "$L" = "zh" ] && echo "✗ 失败" || echo "✗ Failed" ;;
    verify)     [ "$L" = "zh" ] && echo "验证服务 ..." || echo "Verifying services ..." ;;
    verify_ok)  [ "$L" = "zh" ] && echo "✓ 服务正常" || echo "✓ All services OK" ;;
    verify_fail)[ "$L" = "zh" ] && echo "✗ 服务异常" || echo "✗ Service check failed" ;;
    bye)        [ "$L" = "zh" ] && echo "操作完成。" || echo "Done." ;;
  esac
}

ask_yn() {
  msg "$1"
  read -r _a < /dev/tty
  case "$_a" in
    [yY]|[yY][eE][sS]|是) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Parse arguments ──

MODE="" ; REMOTE="" ; STACK_DIR=""

case "${1:-}" in
  --local)  MODE="local"; STACK_DIR="${2:-/root/cpa-deploy}" ;;
  --help|-h) echo "Usage: sh install.sh [--local|user@host] [stack_dir]"; exit 0 ;;
  "")       ;;
  *)        MODE="remote"; REMOTE="$1"; STACK_DIR="${2:-/root/cpa-deploy}" ;;
esac

# ── Ask missing values ──

if [ -z "$MODE" ]; then
  msg mode ; msg local_m ; msg remote_m
  printf "> "
  read -r _m < /dev/tty
  case "$_m" in 2) MODE="remote" ;; *) MODE="local" ;; esac
  echo ""
fi

if [ "$MODE" = "remote" ] && [ -z "$REMOTE" ]; then
  msg host
  read -r _h < /dev/tty
  case "$_h" in *@*) REMOTE="$_h" ;; *) REMOTE="root@$_h" ;; esac
  echo ""
fi

if [ -z "$STACK_DIR" ]; then
  msg dir
  read -r _d < /dev/tty
  STACK_DIR="${_d:-/root/cpa-deploy}"
  echo ""
fi

SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"

# ── Test connection ──

if [ "$MODE" = "remote" ]; then
  echo "Connecting to $REMOTE ..."
  if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "echo ok" >/dev/null 2>&1; then
    msg conn_ok
  else
    msg conn_fail
    exit 1
  fi
else
  if [ ! -d "$STACK_DIR" ]; then
    [ "$L" = "zh" ] && echo "✗ 目录不存在: $STACK_DIR" || echo "✗ Directory not found: $STACK_DIR"
    exit 1
  fi
fi

# ── Check if script exists ──

echo ""
_installed=0
if [ "$MODE" = "remote" ]; then
  if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "test -f '$SCRIPT_PATH'" 2>/dev/null; then
    _installed=1
  fi
else
  [ -f "$SCRIPT_PATH" ] && _installed=1 || true
fi

# ── Branch: installed or not ──

if [ "$_installed" -eq 1 ]; then
  msg installed
  if ask_yn ask_check; then
    echo ""
    [ "$L" = "zh" ] && printf "正在检查更新 ... " || printf "Checking updates ... "
    _gh=$(curl -fsSL --max-time 15 "$SCRIPT_URL" 2>/dev/null | md5 -q 2>/dev/null || echo "x")
    if [ "$MODE" = "remote" ]; then
      _lc=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "md5sum '$SCRIPT_PATH'" 2>/dev/null | cut -d' ' -f1 || echo "y")
    else
      _lc=$(md5 -q "$SCRIPT_PATH" 2>/dev/null || echo "y")
    fi
    if [ "$_gh" = "$_lc" ]; then
      msg chk_ok
    else
      msg chk_new
      if ask_yn ask_update; then
        msg doing_upd
        if [ "$MODE" = "remote" ]; then
          ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" 2>&1
        else
          curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" 2>&1 && chmod +x "$SCRIPT_PATH"
        fi
        if [ $? -eq 0 ]; then msg ok; else msg fail; fi
      fi
    fi
  fi
else
  msg not_inst
  if ask_yn ask_install; then
    msg doing_inst
    if [ "$MODE" = "remote" ]; then
      ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "mkdir -p '$STACK_DIR' && curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" 2>&1
    else
      mkdir -p "$STACK_DIR" && curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" 2>&1 && chmod +x "$SCRIPT_PATH"
    fi
    if [ $? -eq 0 ]; then msg ok; else msg fail; fi
  fi
fi

# ── Verify ──

echo ""
msg verify
if [ "$MODE" = "remote" ]; then
  _out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
else
  _out=$(sh "$SCRIPT_PATH" --check-only 2>&1) || true
fi
echo "$_out"
if echo "$_out" | grep -qE "up-to-date|skip"; then
  msg verify_ok
else
  msg verify_fail
fi

echo ""
msg bye
