#!/bin/sh
set -eu

# CPA Stack Smart Update - Interactive Installer/Updater

REMOTE="${1:-root@192.168.31.81}"
STACK_DIR="${2:-/root/cpa-deploy}"
SCRIPT_NAME="update-cpa-stack.sh"
SCRIPT_PATH="$STACK_DIR/$SCRIPT_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/Souitou-iop/cpa-stack-smart-update/main/update-cpa-stack.sh"

LANG_EN=0
LANG_ZH=1
SELECTED_LANG=$LANG_EN

msg() {
  case "$1" in
    select_lang)    [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "请选择语言 / Select language:" || echo "Select language / 请选择语言:" ;;
    lang_en)        echo "1) English" ;;
    lang_zh)        echo "2) 简体中文" ;;
    checking)       [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "正在检查远程服务器: $REMOTE ..." || echo "Checking remote server: $REMOTE ..." ;;
    installed)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✓ 检测到已安装脚本。" || echo "✓ Script is already installed." ;;
    not_installed)  [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✗ 未检测到脚本。" || echo "✗ Script is not installed." ;;
    check_update)   [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "是否检查更新？(y/n): " || echo "Check for updates? (y/n): " ;;
    install_confirm) [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "是否安装？(y/n): " || echo "Install now? (y/n): " ;;
    installing)     [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "正在安装脚本..." || echo "Installing script..." ;;
    install_ok)     [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✓ 安装成功！" || echo "✓ Installation complete!" ;;
    install_fail)   [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✗ 安装失败。" || echo "✗ Installation failed." ;;
    checking_ver)   [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "正在检查更新..." || echo "Checking for updates..." ;;
    up_to_date)     [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✓ 已是最新版本，无需更新。" || echo "✓ Already up-to-date." ;;
    new_ver)        [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "⬆ 发现新版本！" || echo "⬆ New version available!" ;;
    do_update)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "是否更新？(y/n): " || echo "Update now? (y/n): " ;;
    updating)       [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "正在更新..." || echo "Updating..." ;;
    update_ok)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✓ 更新成功！" || echo "✓ Update complete!" ;;
    update_fail)    [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✗ 更新失败。" || echo "✗ Update failed." ;;
    verifying)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "正在验证服务状态..." || echo "Verifying services..." ;;
    verify_ok)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✓ 验证通过！" || echo "✓ Verification passed!" ;;
    verify_fail)    [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "✗ 验证失败，请手动检查。" || echo "✗ Verification failed, please check manually." ;;
    no_update)      [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "没有可用更新。" || echo "No updates available." ;;
    bye)            [ "$SELECTED_LANG" -eq "$LANG_ZH" ] && echo "操作完成。" || echo "Done." ;;
  esac
}

confirm() {
  printf "%s" "$(msg "$1")"
  read -r answer
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
  read -r choice
  case "$choice" in
    2|zh|ZH|中文) SELECTED_LANG=$LANG_ZH ;;
    *) SELECTED_LANG=$LANG_EN ;;
  esac
  echo ""
}

remote_exec() {
  ssh "$REMOTE" "$@"
}

is_installed() {
  remote_exec "test -f '$SCRIPT_PATH' && echo yes || echo no" 2>/dev/null | grep -q "yes"
}

has_update() {
  remote_hash=$(curl -fsSL "$SCRIPT_URL" | md5sum | cut -d' ' -f1)
  local_hash=$(remote_exec "md5sum '$SCRIPT_PATH' 2>/dev/null | cut -d' ' -f1" || echo "none")
  [ "$remote_hash" != "$local_hash" ]
}

do_install() {
  msg installing
  if remote_exec "
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
  if remote_exec "
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
  result=$(remote_exec "sh '$SCRIPT_PATH' --check-only" 2>&1) || true
  echo "$result"
  echo ""
  if echo "$result" | grep -qE "up-to-date|skip"; then
    msg verify_ok
  else
    msg verify_fail
  fi
}

# ── Main ──

select_language
msg checking

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
