#!/bin/sh
# CPA Stack Smart Update - Installer/Updater
# Usage:
#   sh install.sh                    # Interactive
#   sh install.sh --local            # Local install
#   sh install.sh user@host          # Remote via SSH
#   sh install.sh user@host /path    # Remote with custom dir

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

msg() {
  if [ "$L" = "zh" ]; then
    case "$1" in
      mode)       echo "安装模式:" ;;
      local_m)    echo "  1) 本地安装" ;;
      remote_m)   echo "  2) 远程 SSH 安装" ;;
      host)       printf "远程地址 (例如 192.168.1.1): " ;;
      dir)        printf "部署目录 [/root/cpa-deploy]: " ;;
      conn_ok)    echo "✓ 连接成功" ;;
      conn_fail)  echo "✗ 连接失败" ;;
      installed)  echo "✓ 已安装脚本" ;;
      not_inst)   echo "未安装脚本" ;;
      chk_ok)     echo "✓ 已是最新版本" ;;
      chk_new)    echo "⬆ 脚本有新版本" ;;
      ask_check)  printf "检查更新？(y/n): " ;;
      ask_install) printf "安装？(y/n): " ;;
      ask_update) printf "更新？(y/n): " ;;
      doing_inst) echo "正在安装 ..." ;;
      doing_upd)  echo "正在更新 ..." ;;
      ok)         echo "✓ 完成" ;;
      fail)       echo "✗ 失败" ;;
      verify)     echo "验证服务 ..." ;;
      verify_ok)  echo "✓ 服务正常" ;;
      verify_fail) echo "✗ 服务异常" ;;
      err_dir)    echo "✗ 目录不存在: $STACK_DIR" ;;
      bye)        echo "操作完成。" ;;
    esac
  else
    case "$1" in
      mode)       echo "Install mode:" ;;
      local_m)    echo "  1) Local" ;;
      remote_m)   echo "  2) Remote via SSH" ;;
      host)       printf "Remote address (e.g. 192.168.1.1): " ;;
      dir)        printf "Stack directory [/root/cpa-deploy]: " ;;
      conn_ok)    echo "✓ Connected" ;;
      conn_fail)  echo "✗ Connection failed" ;;
      installed)  echo "✓ Script installed" ;;
      not_inst)   echo "Script not installed" ;;
      chk_ok)     echo "✓ Up-to-date" ;;
      chk_new)    echo "⬆ Script update available" ;;
      ask_check)  printf "Check for updates? (y/n): " ;;
      ask_install) printf "Install? (y/n): " ;;
      ask_update) printf "Update? (y/n): " ;;
      doing_inst) echo "Installing ..." ;;
      doing_upd)  echo "Updating ..." ;;
      ok)         echo "✓ Done" ;;
      fail)       echo "✗ Failed" ;;
      verify)     echo "Verifying services ..." ;;
      verify_ok)  echo "✓ All services OK" ;;
      verify_fail) echo "✗ Service check failed" ;;
      err_dir)    echo "✗ Directory not found: $STACK_DIR" ;;
      bye)        echo "Done." ;;
    esac
  fi
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

# ── SSH helper ──

remote() {
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "$@" 2>&1
}

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
    msg err_dir
    exit 1
  fi
fi

# ── Check if installed ──

echo ""
_installed=0
if [ "$MODE" = "remote" ]; then
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "test -f '$SCRIPT_PATH'" >/dev/null 2>&1 && _installed=1 || true
else
  [ -f "$SCRIPT_PATH" ] && _installed=1 || true
fi

if [ "$_installed" -eq 1 ]; then
  msg installed
  if ask_yn ask_check; then
    echo ""
    [ "$L" = "zh" ] && printf "正在检查更新 ... " || printf "Checking updates ... "
    # Compute hash: macOS uses md5 -q, Linux uses md5sum
    _gh=$(curl -fsSL --max-time 15 "$SCRIPT_URL" 2>/dev/null | (md5 -q 2>/dev/null || md5sum 2>/dev/null | cut -d' ' -f1) || echo "x")
    if [ "$MODE" = "remote" ]; then
      _lc=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "md5sum '$SCRIPT_PATH'" 2>/dev/null | cut -d' ' -f1 || echo "y")
    else
      _lc=$(md5 -q "$SCRIPT_PATH" 2>/dev/null || md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 || echo "y")
    fi
    if [ "$_gh" = "$_lc" ]; then
      msg chk_ok
    else
      # 获取行数信息
      if [ "$MODE" = "remote" ]; then
        _local_lines=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" "wc -l < '$SCRIPT_PATH'" 2>/dev/null || echo "?")
      else
        _local_lines=$(wc -l < "$SCRIPT_PATH" 2>/dev/null || echo "?")
      fi
      _remote_lines=$(curl -fsSL --max-time 15 "$SCRIPT_URL" 2>/dev/null | wc -l | tr -d ' ')
      msg chk_new
      if [ "$L" = "zh" ]; then
        echo "  本地: ${_local_lines} 行 → 最新: ${_remote_lines} 行"
      else
        echo "  Local: ${_local_lines} lines → Latest: ${_remote_lines} lines"
      fi
      msg doing_upd
      if [ "$MODE" = "remote" ]; then
        remote "curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" && msg ok || msg fail
      else
        curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH" && msg ok || msg fail
      fi
    fi
  fi
else
  msg not_inst
  if ask_yn ask_install; then
    echo ""
    msg doing_inst
    if [ "$MODE" = "remote" ]; then
      remote "mkdir -p '$STACK_DIR' && curl -fsSLo '$SCRIPT_PATH' '$SCRIPT_URL' && chmod +x '$SCRIPT_PATH'" && msg ok || msg fail
    else
      mkdir -p "$STACK_DIR" && curl -fsSLo "$SCRIPT_PATH" "$SCRIPT_URL" && chmod +x "$SCRIPT_PATH" && msg ok || msg fail
    fi
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
