#!/bin/bash
#
# hermes-run.sh — 管理多個 Hermes agent 的 Docker Compose stack
#
# 每個 agent 是一個獨立的 compose stack（單一容器，gateway 與 dashboard
# 由 s6 一起跑在裡面），靠
#   docker compose -p <project> ...
# 做命名空間隔離，N 個 agent 互不干擾，全部共用同一份已被 env 參數化的
# docker-compose.yml（腳本不修改 compose 檔）。
#
#   - 主 agent  : ~/.hermes  project=hermes  吃 compose 預設 port/容器名
#   - 分身 agent: ~/.<name>   project=<name>  讀 agents/<name>.conf（name 原樣，不自動補前綴）
#
# Usage:
#   ./hermes-run.sh up [<name>|all]       # 啟動（無參數 = 主 agent）
#   ./hermes-run.sh down [<name>|all]     # 停止
#   ./hermes-run.sh restart [<name>|all]  # 重啟 process（不重建容器）
#   ./hermes-run.sh logs [<name>]         # 跟著看 log（無參數 = 主 agent）
#   ./hermes-run.sh status [<name>]       # 無參數 = 所有 agent 狀態總覽
#   ./hermes-run.sh ls                    # 列出已設定的 agent 與其 port
#   ./hermes-run.sh new <name> [--force]  # scaffold 新分身（clone 主 agent 設定）
#
# 分身設定: agents/<name>.conf（port + 容器名 + data dir，由 `new` 自動產生）
# 詳見 docs/guides/multi-agent.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# 主 agent 的 compose 預設（須與 docker-compose.yml 的 :- 預設一致）
MAIN_GATEWAY_PORT=8642
MAIN_DASHBOARD_PORT=9119

# 分身自動挑 port 的起點。避開瀏覽器 CDP 慣用的 9223-9225（見 browsers.conf）。
GATEWAY_PORT_BASE=8643
DASHBOARD_PORT_BASE=9120
CDP_RANGE_LO=9223
CDP_RANGE_HI=9225

# ---- Helpers ----

die() {
  echo "Error: $*" >&2
  exit 1
}

# 列出所有已設定的分身名稱（不含 main）。agents/ 不存在或為空時輸出空。
sub_agents() {
  local f
  for f in "$AGENTS_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    basename "$f" .conf
  done
}

# host 上某 port 是否已有 process 在 listen
port_busy() {
  lsof -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1
}

in_cdp_range() {
  (( $1 >= CDP_RANGE_LO && $1 <= CDP_RANGE_HI ))
}

# 收集已被佔用的 port：主 agent 預設 + 所有分身 conf 裡的 gateway/dashboard port
collect_used_ports() {
  echo "$MAIN_GATEWAY_PORT"
  echo "$MAIN_DASHBOARD_PORT"
  local f
  for f in "$AGENTS_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    awk -F= '/^(HERMES_GATEWAY_PORT|HERMES_DASHBOARD_PORT)=/ { gsub(/[[:space:]]/, "", $2); print $2 }' "$f"
  done
}

# 從 $1 起往上找一個「沒被列為已用、不在 CDP 範圍、host 上沒在 listen」的 port。
#   $1 = 起始 port  $2 = 已用 port 清單（每行一個）
pick_free_port() {
  local p="$1" used="$2"
  while :; do
    if ! grep -qx "$p" <<<"$used" && ! in_cdp_range "$p" && ! port_busy "$p"; then
      echo "$p"
      return 0
    fi
    p=$((p + 1))
  done
}

# 在 subshell 內把某 agent 的 conf 載好，再執行一個 docker compose 子命令。
# 用 () 作函式主體 → 自動在 subshell 執行，source 進來的變數不會外洩到下一個 agent。
#   $1 = agent 名稱（main 或分身名）；其餘參數原樣傳給 docker compose
compose_one() (
  local agent="$1"
  shift
  local project
  if [[ "$agent" == "main" ]]; then
    project="hermes"
  else
    local envfile="$AGENTS_DIR/$agent.conf"
    [[ -f "$envfile" ]] || die "找不到 agent 設定：${envfile}（先執行 '$0 new $agent'）"
    set -a
    # shellcheck disable=SC1090
    . "$envfile"
    set +a
    project="$agent"
  fi
  docker compose --project-directory "$SCRIPT_DIR" -p "$project" -f "$COMPOSE_FILE" "$@"
)

# 把一個 compose 動作套用到目標（單一 agent 或 all）
#   $1 = 目標（""|main|<name>|all）；其餘 = 傳給 docker compose 的參數
for_target() {
  local target="$1"
  shift
  case "$target" in
    "" | main)
      compose_one main "$@"
      ;;
    all)
      echo "==> main"
      compose_one main "$@"
      local a
      for a in $(sub_agents); do
        echo ""
        echo "==> $a"
        compose_one "$a" "$@"
      done
      ;;
    *)
      compose_one "$target" "$@"
      ;;
  esac
}

# 回報單一容器狀態字串
container_state() {
  local name="$1" st
  st="$(docker ps -a --filter "name=^${name}$" --format '{{.Status}}' 2>/dev/null | head -n1)"
  if [[ -z "$st" ]]; then
    echo "[--]   (不存在)"
  elif [[ "$st" == Up* ]]; then
    echo "[ok]   $st"
  else
    echo "[down] $st"
  fi
}

# 印出單一 agent 的 gateway / dashboard 狀態（在 subshell 內 source env）
# gateway 與 dashboard 跑在同一個容器，所以兩行共用同一個容器狀態。
status_line() (
  local agent="$1"
  local ctr gwport dashport state
  if [[ "$agent" == "main" ]]; then
    ctr="hermes"
    gwport="$MAIN_GATEWAY_PORT"
    dashport="$MAIN_DASHBOARD_PORT"
  else
    set -a
    # shellcheck disable=SC1090
    . "$AGENTS_DIR/$agent.conf"
    set +a
    ctr="${HERMES_CONTAINER_NAME:-$agent}"
    gwport="${HERMES_GATEWAY_PORT:-?}"
    dashport="${HERMES_DASHBOARD_PORT:-?}"
  fi
  state="$(container_state "$ctr")"
  printf "  %-14s gateway  %-26s %s\n" "$agent" "http://localhost:$gwport" "$state"
  printf "  %-14s dash     %-26s %s\n" "" "http://localhost:$dashport" "$state"
)

# ---- Commands ----

cmd_up() { for_target "${1:-}" up -d; }
cmd_down() { for_target "${1:-}" down; }
cmd_restart() { for_target "${1:-}" restart; }

cmd_logs() {
  local target="${1:-main}"
  [[ "$target" == "all" ]] && die "logs 一次只能跟一個 agent（指定名稱，或留空看主 agent）"
  compose_one "$target" logs -f --tail=100
}

cmd_status() {
  local target="${1:-}"
  if [[ -z "$target" || "$target" == "all" ]]; then
    echo "Hermes agent 狀態："
    status_line main
    local a
    for a in $(sub_agents); do
      status_line "$a"
    done
  else
    compose_one "$target" ps
  fi
}

cmd_ls() {
  printf "  %-14s %-30s %s\n" "AGENT" "GATEWAY" "DASHBOARD"
  printf "  %-14s %-30s %s\n" "main" "http://localhost:$MAIN_GATEWAY_PORT" "http://localhost:$MAIN_DASHBOARD_PORT"
  local a
  for a in $(sub_agents); do
    ls_line "$a"
  done
}

ls_line() (
  local a="$1"
  set -a
  # shellcheck disable=SC1090
  . "$AGENTS_DIR/$a.conf"
  set +a
  printf "  %-14s %-30s %s\n" "$a" \
    "http://localhost:${HERMES_GATEWAY_PORT:-?}" \
    "http://localhost:${HERMES_DASHBOARD_PORT:-?}"
)

cmd_new() {
  local name="${1:-}" force="${2:-}"
  [[ -n "$name" ]] || die "用法：$0 new <name> [--force]"
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || die "名稱只能用小寫字母 / 數字 / 連字號：$name"
  [[ "$name" == "main" || "$name" == "hermes" ]] && die "名稱不能叫 main / hermes（保留給主 agent）"

  local envfile="$AGENTS_DIR/$name.conf"
  local data_dir="$HOME/.$name"
  local main_data="${HERMES_DATA_DIR:-$HOME/.hermes}"

  if [[ "$force" != "--force" ]]; then
    [[ -e "$envfile" ]] && die "已存在：${envfile}（加 --force 覆寫）"
    [[ -e "$data_dir" ]] && die "已存在：${data_dir}（加 --force 覆寫）"
  fi

  # 1. 挑兩個沒被佔用的 port
  local used gwport dashport
  used="$(collect_used_ports)"
  gwport="$(pick_free_port "$GATEWAY_PORT_BASE" "$used")"
  used="$(printf '%s\n%s' "$used" "$gwport")"
  dashport="$(pick_free_port "$DASHBOARD_PORT_BASE" "$used")"

  echo "==> 建立分身 '$name'"
  echo "    data dir : $data_dir"
  echo "    gateway  : $gwport"
  echo "    dashboard: $dashport"

  # 2. 建資料夾 + clone 主 agent 的 runtime 設定。
  #    刻意不複製 SOUL.md：那是 agent 身份（system prompt slot #1），新分身應自己定義，
  #    靜默繼承主 agent 人格是地雷（見手動步驟）。.env/config.yaml 是基礎設施，給個 baseline 再改。
  [[ -d "$main_data" ]] || die "主 agent data dir 不存在：${main_data}（無法 clone）"
  mkdir -p "$data_dir"
  local f
  for f in .env config.yaml; do
    if [[ -f "$main_data/$f" ]]; then
      cp "$main_data/$f" "$data_dir/$f"
      echo "    clone    : $f"
    fi
  done

  # 3. 放容器內 runtime 腳本，保留 cdp_proxy 需要的巢狀結構：
  #    /opt/data/scripts/cdp_proxy.py + /opt/data/scripts/host/browsers.conf
  mkdir -p "$data_dir/scripts/host"
  cp "$SCRIPT_DIR/scripts/cdp_proxy.py" "$data_dir/scripts/cdp_proxy.py"
  echo "    runtime  : scripts/cdp_proxy.py"
  if [[ -f "$SCRIPT_DIR/browsers.conf" ]]; then
    cp "$SCRIPT_DIR/browsers.conf" "$data_dir/scripts/host/browsers.conf"
    echo "    runtime  : scripts/host/browsers.conf （來源 root/browsers.conf）"
  else
    echo "    warn     : 找不到 root/browsers.conf，cdp_proxy 啟動時無 port 可轉發（不影響 gateway 啟動）"
  fi

  # 4. 寫 orchestration env（HERMES_DATA_DIR 用 ${HOME}，腳本 source .conf 時才展開）
  mkdir -p "$AGENTS_DIR"
  cat >"$envfile" <<EOF
# Hermes agent '$name' — compose 編排設定（由 hermes-run.sh new 產生）
# dashboard 跟 gateway 跑在同一容器（compose 已內建 HERMES_DASHBOARD=1），
# 不需要獨立的 dashboard 容器名。
HERMES_DATA_DIR=\${HOME}/.$name
HERMES_CONTAINER_NAME=$name
HERMES_GATEWAY_PORT=$gwport
HERMES_DASHBOARD_PORT=$dashport
EOF
  echo "    寫入     : agents/$name.conf"

  cat <<EOF

完成。接下來的手動步驟：
  1. 撰寫 $data_dir/SOUL.md
     這個分身的身份 / system prompt（new 不從主 agent 複製，新 agent 自己定義）。
  2. 編輯 $data_dir/.env
     填這個分身自己的 platform token / allowlist / API key。
  3.（用瀏覽器才需要）編輯 $data_dir/config.yaml
     把 browser.cdp_url 改成這個分身專屬的 CDP port。
  4. 啟動：
     $0 up $name
EOF
}

usage() {
  cat <<EOF
hermes-run.sh — 管理多個 Hermes agent 的 Docker Compose stack

Usage:
  $0 up [<name>|all]       啟動（無參數 = 主 agent ~/.hermes）
  $0 down [<name>|all]     停止
  $0 restart [<name>|all]  重啟 process（不重建容器）
  $0 logs [<name>]         跟著看 log（無參數 = 主 agent）
  $0 status [<name>]       無參數 = 所有 agent 狀態總覽
  $0 ls                    列出已設定的 agent 與其 port
  $0 new <name> [--force]  scaffold 新分身（clone 主 agent 設定）

分身設定: $AGENTS_DIR/<name>.conf
詳見:     docs/guides/multi-agent.md
EOF
}

# ---- Main ----

case "${1:-}" in
  up)
    shift
    cmd_up "${1:-}"
    ;;
  down)
    shift
    cmd_down "${1:-}"
    ;;
  restart)
    shift
    cmd_restart "${1:-}"
    ;;
  logs)
    shift
    cmd_logs "${1:-}"
    ;;
  status | ps)
    shift
    cmd_status "${1:-}"
    ;;
  ls | list)
    cmd_ls
    ;;
  new)
    shift
    cmd_new "$@"
    ;;
  -h | --help | help | "")
    usage
    ;;
  *)
    die "未知指令：$1（執行 '$0 --help' 看用法）"
    ;;
esac
