#!/bin/sh
# CPA Stack Smart Update - Installer/Updater (Improved)
# Supports both key-based and password authentication

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
      user)       printf "SSH 用户名 [root]: " ;;
      auth)       echo "SSH 认证方式:" ;;
      auth_key)   echo "  1) 免密 SSH (密钥认证)" ;;
      auth_pass)  echo "  2) 密码认证" ;;
      pass)       printf "SSH 密码: " ;;
      dir)        printf "部署目录 [/root/cpa-deploy]: " ;;
      conn_ok)    echo "✓ 连接成功" ;;
      conn_fail)  echo "✗ 连接失败" ;;
      conn_retry) echo "请检查地址、用户名和密码是否正确" ;;
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
      sshpass_warn) echo "提示: 密码认证需要安装 sshpass" ;;
      sshpass_install) echo "正在安装 sshpass ..." ;;
    esac
  else
    case "$1" in
      mode)       echo "Install mode:" ;;
      local_m)    echo "  1) Local" ;;
      remote_m)   echo "  2) Remote via SSH" ;;
      host)       printf "Remote address (e.g. 192.168.1.1): " ;;
      user)       printf "SSH username [root]: " ;;
      auth)       echo "SSH authentication:" ;;
      auth_key)   echo "  1) Key-based (passwordless)" ;;
      auth_pass)  echo "  2) Password" ;;
      pass)       printf "SSH password: " ;;
      dir)        printf "Stack directory [/root/cpa-deploy]: " ;;
      conn_ok)    echo "✓ Connected" ;;
      conn_fail)  echo "✗ Connection failed" ;;
      conn_retry) echo "Please check address, username and password" ;;
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
      sshpass_warn) echo "Note: Password auth requires sshpass" ;;
      sshpass_install) echo "Installing sshpass ..." ;;
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

MODE="" ; REMOTE="" ; STACK_DIR="" ; SSH_USER="root" ; SSH_PASS="" ; AUTH_MODE=""

case "${1:-}" in
  --local)  MODE="local"; STACK_DIR="${2:-/root/cpa-deploy}" ;;
  --help|-h) echo "Usage: sh install.sh [--local|user@host] [stack_dir]"; exit 0 ;;
  "")       ;;
  *)        MODE="remote"; REMOTE="$1"; STACK_DIR="${2:-/root/cpa-deploy}" ;;
esac

# ── SSH helper functions ──

# Test key-based authentication
test_key_auth() {
  ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE" "echo ok" >/dev/null 2>&1
}

# Test password authentication
test_pass_auth() {
  if ! command -v sshpass >/dev/null 2>&1; then
    msg sshpass_warn
    msg sshpass_install
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v brew >/dev/null 2>&1; then
      brew install sshpass
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y sshpass
    else
      echo "无法自动安装 sshpass，请手动安装" >&2
      return 1
    fi
  fi
  sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE" "echo ok" >/dev/null 2>&1
}

# Execute remote command
remote() {
  if [ "$AUTH_MODE" = "key" ]; then
    ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE" "$@" 2>&1
  else
    sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE" "$@" 2>&1
  fi
}

# ── Interactive mode ──

if [ "$MODE" = "" ]; then
  msg mode
  echo "  $(msg local_m)"
  echo "  $(msg remote_m)"
  printf "> "
  read -r _mode < /dev/tty
  case "$_mode" in
    1|local) MODE="local" ;;
    2|remote) MODE="remote" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

if [ "$MODE" = "remote" ]; then
  if [ -z "$REMOTE" ]; then
    msg host
    read -r REMOTE < /dev/tty
  fi
  
  # Ask for username
  if [ "$SSH_USER" = "root" ]; then
    msg user
    read -r _user < /dev/tty
    if [ -n "$_user" ]; then
      SSH_USER="$_user"
    fi
  fi
  
  # Try key-based auth first
  echo ""
  echo "Testing SSH connection ..."
  if test_key_auth; then
    AUTH_MODE="key"
    msg conn_ok
  else
    echo "Key-based authentication failed."
    msg auth
    echo "  $(msg auth_key)"
    echo "  $(msg auth_pass)"
    printf "> "
    read -r _auth < /dev/tty
    case "$_auth" in
      1|key)
        AUTH_MODE="key"
        echo "Please set up SSH key authentication first."
        echo "Run: ssh-copy-id $SSH_USER@$REMOTE"
        exit 1
        ;;
      2|pass)
        AUTH_MODE="pass"
        msg pass
        read -r -s SSH_PASS < /dev/tty
        echo ""
        if test_pass_auth; then
          msg conn_ok
        else
          msg conn_fail
          msg conn_retry
          exit 1
        fi
        ;;
      *)
        echo "Invalid choice"
        exit 1
        ;;
    esac
  fi
else
  if [ ! -d "$STACK_DIR" ]; then
    msg err_dir
    exit 1
  fi
fi

if [ -z "$STACK_DIR" ]; then
  msg dir
  read -r STACK_DIR < /dev/tty
  [ -z "$STACK_DIR" ] && STACK_DIR="/root/cpa-deploy"
fi

SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"

# ── Check if installed ──

echo ""
_installed=0
if [ "$MODE" = "remote" ]; then
  remote "test -f '$SCRIPT_PATH'" >/dev/null 2>&1 && _installed=1 || true
else
  [ -f "$SCRIPT_PATH" ] && _installed=1 || true
fi

if [ "$_installed" -eq 1 ]; then
  msg installed
  [ "$L" = "zh" ] && printf "正在检查脚本更新 ... " || printf "Checking script update ... "
  _gh=$(curl -fsSL --max-time 15 "$SCRIPT_URL" 2>/dev/null | (md5 -q 2>/dev/null || md5sum 2>/dev/null | cut -d' ' -f1) || echo "x")
  if [ "$MODE" = "remote" ]; then
    _lc=$(remote "md5sum '$SCRIPT_PATH'" 2>/dev/null | cut -d' ' -f1 || echo "y")
  else
    _lc=$(md5 -q "$SCRIPT_PATH" 2>/dev/null || md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 || echo "y")
  fi
  if [ "$_gh" = "$_lc" ]; then
    msg chk_ok
  else
    if [ "$MODE" = "remote" ]; then
      _local_lines=$(remote "wc -l < '$SCRIPT_PATH'" 2>/dev/null || echo "?")
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
    if ask_yn ask_update; then
      echo ""
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
  _out=$(remote "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
else
  _out=$(sh "$SCRIPT_PATH" --check-only 2>&1) || true
fi
echo "$_out"
if echo "$_out" | grep -qE "up-to-date|skip|已是最新"; then
  msg verify_ok
else
  msg verify_fail
fi

echo ""
msg bye
