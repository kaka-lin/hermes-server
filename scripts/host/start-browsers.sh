#!/bin/bash
#
# start-browsers.sh — 管理 host 端獨立 Chrome 實體（CDP-based agent control）
#
# 為每個 profile 啟動一個獨立的 Chrome，各自綁定 CDP debug port，
# user-data-dir 預設放在 Hermes 自己的 namespace（~/.hermes/browser），
# 每個 profile 第一次啟動是全新空白 Chrome，需手動登入一次。
# 若要沿用 OpenClaw 既有 profile（保留登入狀態），見下方 DATA_DIR 說明。
# 此腳本可獨立取代 OpenClaw Node 的 Chrome lifecycle 功能。
#
# Usage:
#   bash scripts/host/start-browsers.sh [start|stop|status|restart]
#   (無參數 = start)
#
# Profile 設定: scripts/host/browsers.conf
#   可用 BROWSERS_CONFIG=/path/to/other.conf 環境變數覆寫
#
# 參考: docs/guides/mac-chrome-cdp-guide.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${BROWSERS_CONFIG:-$SCRIPT_DIR/browsers.conf}"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Profile 的 user-data-dir 根目錄：$DATA_DIR/<profile>/user-data
# 預設用 Hermes 自己的 namespace（全新 profile，第一次啟動需手動登入）。
# 若要沿用 OpenClaw 既有 profile（保留 Threads/IG 登入狀態），改成：
#   DATA_DIR="$HOME/.openclaw/browser"
DATA_DIR="$HOME/.hermes/browser"

# ---- Helpers ----

load_profiles() {
  if [[ ! -f "$CONFIG" ]]; then
    echo "Error: config 找不到 ($CONFIG)" >&2
    if [[ -f "$CONFIG.example" ]]; then
      echo "" >&2
      echo "Hint: 從範本複製一份，再編輯成你的 profile：" >&2
      echo "  cp $CONFIG.example $CONFIG" >&2
    fi
    exit 1
  fi

  PROFILES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    PROFILES+=("$line")
  done < "$CONFIG"

  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo "Error: $CONFIG 沒有有效的 profile 條目" >&2
    exit 1
  fi
}

launch_chrome() {
  local port=$1
  local profile=$2
  local user_data="$DATA_DIR/$profile/user-data"

  if lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "skip:   $profile  (port $port 已在 listen)"
    return 0
  fi

  if [[ ! -d "$user_data" ]]; then
    echo "warn:   $profile  user-data-dir 不存在 ($user_data)，會建立全新空白 Chrome"
  fi

  "$CHROME" \
    --remote-debugging-port="$port" \
    --user-data-dir="$user_data" \
    --no-first-run \
    --no-default-browser-check \
    --remote-allow-origins='*' \
    >/dev/null 2>&1 &

  echo "launch: $profile  on port $port  (pid $!)"
}

wait_for_listen() {
  local port=$1
  local timeout=15
  for ((i=0; i<timeout; i++)); do
    if lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# ---- Commands ----

cmd_start() {
  if [[ ! -x "$CHROME" ]]; then
    echo "Error: Chrome 找不到 ($CHROME)" >&2
    exit 1
  fi

  for entry in "${PROFILES[@]}"; do
    IFS=':' read -r port name <<< "$entry"
    launch_chrome "$port" "$name"
  done

  echo ""
  echo "等待 Chrome listener 就緒（最多 15s/port）..."
  for entry in "${PROFILES[@]}"; do
    IFS=':' read -r port name <<< "$entry"
    if wait_for_listen "$port"; then
      printf "  [ok]   %-15s  http://127.0.0.1:%s\n" "$name" "$port"
    else
      printf "  [fail] %-15s  port %s 在 15s 內未 listen\n" "$name" "$port"
    fi
  done
}

cmd_stop() {
  echo "停止 Chrome 實例..."
  local stopped=0
  for entry in "${PROFILES[@]}"; do
    IFS=':' read -r port name <<< "$entry"
    local pids
    pids=$(pgrep -f "remote-debugging-port=$port" || true)
    if [[ -z "$pids" ]]; then
      printf "  [--]   %-15s  port %s 沒有對應 process\n" "$name" "$port"
      continue
    fi
    for pid in $pids; do
      if kill "$pid" 2>/dev/null; then
        stopped=$((stopped + 1))
      fi
    done
    printf "  [stop] %-15s  killed pid %s\n" "$name" "$(echo $pids | tr '\n' ' ')"
  done
  echo ""
  echo "已停止 $stopped 個 process"
}

cmd_status() {
  echo "Chrome listener 狀態："
  for entry in "${PROFILES[@]}"; do
    IFS=':' read -r port name <<< "$entry"
    local pid
    pid=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -n1 || true)
    if [[ -n "$pid" ]]; then
      printf "  [ok]   %-15s  http://127.0.0.1:%-6s  pid %s\n" "$name" "$port" "$pid"
    else
      printf "  [--]   %-15s  http://127.0.0.1:%-6s  (not listening)\n" "$name" "$port"
    fi
  done
}

cmd_restart() {
  cmd_stop
  sleep 2
  echo ""
  cmd_start
}

# ---- Main ----

load_profiles

case "${1:-start}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  restart) cmd_restart ;;
  -h|--help|help)
    echo "Usage: $0 [start|stop|status|restart]"
    echo "  (無參數 = start)"
    echo ""
    echo "Profile 設定: $CONFIG"
    exit 0
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Usage: $0 [start|stop|status|restart]" >&2
    exit 1
    ;;
esac
