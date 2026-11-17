#!/bin/bash
#
# hermes-run.sh — 管理 Hermes 的 Docker Compose stack
#
# 兩層隔離可以疊著用（詳見 docs/agents-and-profiles.md）：
#   - home：一個 data dir 一個容器。主 home 是 ~/.hermes（容器 hermes）；
#           其他 home 由 `new <名稱>` 建立，設定在 agents/<名稱>.conf。
#   - profile：同一個 home 裡用官方 CLI 建（`cli profile create <名稱>`），
#              由那個容器的 gateway 一起帶起來。
#
# 用法：./hermes-run.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
COMPOSE_ENV_FILE="$SCRIPT_DIR/compose.env"
[[ -f "$SCRIPT_DIR/versions.env" && ! -f "$COMPOSE_ENV_FILE" ]] &&
  echo "warn: versions.env 已改名為 compose.env，請執行 mv versions.env compose.env（目前用預設值）" >&2
# shellcheck source=platforms/detect.sh
. "$SCRIPT_DIR/platforms/detect.sh"
COMPOSE=(docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yml")
# 後面的 env-file 蓋過前面的；shell 的環境變數（含 agents/<名稱>.conf）又蓋過兩者。
[[ -f "$COMPOSE_ENV_FILE" ]] && COMPOSE+=(--env-file "$COMPOSE_ENV_FILE")
[[ -f "$PLATFORM_ENV" ]] && COMPOSE+=(--env-file "$PLATFORM_ENV")
# new 自動挑 port 的起點；主 home 用 compose 預設的 8642 / 9119。
GATEWAY_PORT_BASE=8643
DASHBOARD_PORT_BASE=9120

die() {
  echo "Error: $*" >&2
  exit 1
}

# 已建立的其他 home 名稱（不含主 home）
agent_names() {
  local f
  for f in "$AGENTS_DIR"/*.conf; do
    [[ -e "$f" ]] && basename "$f" .conf
  done
}

# 把 agents/<名稱>.conf 的變數 export 進目前的 shell；shell env 蓋過 compose.env，
# 所以 conf 裡的值就是 Compose 會用的值。只在 subshell 裡呼叫，變數才不會漏到下一個 home。
load_agent() {
  local conf="$AGENTS_DIR/$1.conf"
  [[ -f "$conf" ]] || die "找不到 ${conf}（先執行 '$0 new $1'）"
  set -a
  # shellcheck disable=SC1090
  . "$conf"
  set +a
}

# Compose project 名稱：主 home 是 hermes，其他 home 是 hermes-<名稱>，各自是獨立的 stack。
project_of() {
  if [[ -z "$1" ]]; then echo hermes; else echo "hermes-$1"; fi
}

# The value Compose resolves for $1 (shell env, then the env files), so the script syncs into the
# same data dir and execs into the same container Compose actually uses. Empty when unset.
compose_env() {
  { "${COMPOSE[@]}" config --environment 2>/dev/null || true; } |
    awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
}

data_dir() {
  local dir
  dir="$(compose_env HERMES_DATA_DIR)"
  dir="${dir:-$HOME/.hermes}"
  # Compose prints the value as written but mounts it with ~ expanded and relative paths
  # resolved against the project dir; sync into that same directory.
  case "$dir" in
    "~" | "~/"*) dir="$HOME${dir#\~}" ;;
    /*) ;;
    *) dir="$SCRIPT_DIR/$dir" ;;
  esac
  echo "$dir"
}

container_name() {
  local name
  name="$(compose_env HERMES_CONTAINER_NAME)"
  echo "${name:-hermes}"
}

# 預設值要和 docker-compose.yml 的 :- 預設一致。
gateway_port() {
  local port
  port="$(compose_env HERMES_GATEWAY_PORT)"
  echo "${port:-8642}"
}

dashboard_port() {
  local port
  port="$(compose_env HERMES_DASHBOARD_PORT)"
  echo "${port:-9119}"
}

# 把 repo 的容器內 runtime 腳本同步進 data dir（掛載成容器的 /opt/data）。
# cdp_proxy.py 讀 scripts/host/browsers.conf 決定要轉發的 port。
# 不加 --delete：data dir 的 scripts/ 也放 agent 自己生成的腳本，不能清掉。
# 排除 __pycache__：repo 本機跑測試留下的 .pyc 不該帶進容器。
sync_runtime() {
  local dir="$1"
  mkdir -p "$dir/scripts/host"
  rsync -a --exclude=__pycache__ "$SCRIPT_DIR/scripts/" "$dir/scripts/"
  echo "    runtime  : scripts/ → $dir/scripts/"
  if [[ -f "$SCRIPT_DIR/browsers.conf" ]]; then
    cp "$SCRIPT_DIR/browsers.conf" "$dir/scripts/host/browsers.conf"
    echo "    runtime  : browsers.conf → $dir/scripts/host/browsers.conf"
  else
    echo "    warn     : 找不到 browsers.conf，cdp_proxy 沒有 port 可轉發（不影響 gateway 啟動）"
  fi
}

# 在 subshell 裡載入某個 home（"" = 主 home），對它執行 docker compose。
compose_one() (
  local agent="$1"
  shift
  [[ -z "$agent" ]] || load_agent "$agent"
  # --no-build --pull never：image 不存在時直接報錯，而不是默默重建 base image。
  if [[ "${1:-}" == up ]]; then
    sync_runtime "$(data_dir)"
    set -- up -d --no-build --pull never
  fi
  "${COMPOSE[@]}" -p "$(project_of "$agent")" "$@"
)

# 對目標 home 執行 compose 動作。$1 = 名稱、"" 或 --all。
for_target() {
  local target="$1" a
  shift
  if [[ "$target" == --all ]]; then
    # 一個 home 失敗不擋其他 home（例如 down --all 不該留一半容器在跑），最後才回報失敗。
    local failed=""
    echo "==> hermes（主 home）"
    compose_one "" "$@" || failed="$failed hermes"
    for a in $(agent_names); do
      printf '\n==> %s\n' "$a"
      compose_one "$a" "$@" || failed="$failed $a"
    done
    [[ -z "$failed" ]] || die "這些 home 失敗：$failed"
  else
    compose_one "$target" "$@"
  fi
}

# 在容器內以 hermes 身分執行 hermes CLI。少了 -u hermes，寫進 data dir 的檔案會變成 root 擁有；
# 在終端機執行時加 -it，登入、setup 這類互動指令才能用。
cmd_cli() (
  local agent="$1" container status=0
  shift
  [[ -z "$agent" ]] || load_agent "$agent"
  container="$(container_name)"
  local tty=()
  [[ -t 0 && -t 1 ]] && tty=(-it)
  # ${tty[@]+...}：macOS 的 bash 3.2 在 set -u 下展開空陣列會報錯。
  docker exec ${tty[@]+"${tty[@]}"} -u hermes "$container" hermes "$@" || status=$?
  if (( status == 0 )) && [[ "${1:-}" == profile && "${2:-}" == create && -n "${3:-}" && "${3:0:1}" != - ]]; then
    local again="$0 cli${agent:+ -a $agent}"
    cat <<EOF

下一步（gateway 不會自動重啟，避免 profile 在沒有憑證時就被帶起來）：
  1. 編輯 $(data_dir)/profiles/$3/
     - .env：這個 profile 自己的 bot token、API_SERVER_KEY（同一組 bot token 不能給兩個 profile 用）
     - SOUL.md：身份與人設
     - config.yaml：model、browser.cdp_url 等
  2. 套用：$again gateway restart（會中斷這個 home 所有 profile 正在跑的 cron 與對話）
  3. 確認：$again doctor（Host gateway 那一行會列出 $3）
EOF
  fi
  return "$status"
)

# host 上某 port 是否已有 process 在 listen
port_busy() {
  lsof -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1
}

# 已被佔用或保留的 port：主 home 的兩個、每個 home conf 裡的兩個、browsers.conf 的 CDP port。
used_ports() {
  local f
  gateway_port
  dashboard_port
  for f in "$AGENTS_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    sed -nE 's/^HERMES_(GATEWAY|DASHBOARD)_PORT=[[:space:]]*([0-9]+).*/\2/p' "$f"
  done
  [[ -f "$SCRIPT_DIR/browsers.conf" ]] && sed -n 's/^[[:space:]]*\([0-9][0-9]*\):.*/\1/p' "$SCRIPT_DIR/browsers.conf"
  return 0
}

# 從 $1 往上找第一個不在 $2（每行一個 port）裡、host 上也沒在 listen 的 port。
pick_free_port() {
  local p="$1"
  while grep -qx "$p" <<<"$2" || port_busy "$p"; do
    p=$((p + 1))
  done
  echo "$p"
}

cmd_new() {
  local name="${1:-}" force="${2:-}"
  [[ -n "$name" ]] || die "用法：$0 new <名稱> [--force]"
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || die "名稱只能用小寫字母、數字、連字號：$name"
  [[ "$name" == hermes ]] && die "名稱不能叫 hermes（保留給主 home）"

  local conf="$AGENTS_DIR/$name.conf" dir="$HOME/.hermes-$name" main_dir
  main_dir="$(data_dir)"
  if [[ "$force" != --force ]]; then
    [[ -e "$conf" ]] && die "已存在：${conf}（加 --force 覆寫）"
    [[ -e "$dir" ]] && die "已存在：${dir}（加 --force 覆寫）"
  fi
  [[ -d "$main_dir" ]] || die "主 home 不存在：${main_dir}（無法 clone）"
  [[ "hermes-$name" == "$(container_name)" ]] && die "容器名稱 hermes-$name 已經是主 home 在用的，換個名稱"

  local used gwport dashport
  used="$(used_ports)"
  gwport="$(pick_free_port "$GATEWAY_PORT_BASE" "$used")"
  dashport="$(pick_free_port "$DASHBOARD_PORT_BASE" "$(printf '%s\n%s' "$used" "$gwport")")"

  echo "==> 建立 home '$name'"
  echo "    data dir : $dir"
  echo "    容器     : hermes-$name"
  echo "    gateway  : $gwport"
  echo "    dashboard: $dashport"

  # 只 clone 基礎設定；SOUL.md 不複製，新 home 的身份要自己寫，其餘第一次啟動時由 entrypoint 補齊。
  # 已存在的不覆蓋：--force 重跑時，那個 home 自己填好的 token 不能被主 home 的蓋掉。
  mkdir -p "$dir"
  local f
  for f in .env config.yaml; do
    if [[ -f "$dir/$f" ]]; then
      echo "    保留     : ${f}（已存在，不覆蓋）"
    elif [[ -f "$main_dir/$f" ]]; then
      cp "$main_dir/$f" "$dir/$f"
      echo "    clone    : $f"
    fi
  done
  sync_runtime "$dir"

  mkdir -p "$AGENTS_DIR"
  cat >"$conf" <<EOF
# Hermes home '$name'（由 hermes-run.sh new 產生）
HERMES_DATA_DIR=\${HOME}/.hermes-$name
HERMES_CONTAINER_NAME=hermes-$name
HERMES_GATEWAY_PORT=$gwport
HERMES_DASHBOARD_PORT=$dashport
# 這個 home 要跑的 image 版本；不寫就用 compose.env 的 HERMES_VERSION。要先 ./hermes-build.sh <版本>。
# HERMES_VERSION=v0.23.1
EOF
  echo "    寫入     : agents/$name.conf"

  cat <<EOF

完成。接下來：
  1. 編輯 $dir/.env
     .env 是從主 home 整份複製的。換成這個 home 自己的 bot token、API_SERVER_KEY：
     同一組 bot token 不能給兩個容器用，不換的話兩邊會搶連線。
  2. 撰寫 $dir/SOUL.md（這個 home 的身份；不寫的話第一次啟動會放官方預設）
  3. 用瀏覽器才需要：$dir/config.yaml 的 browser.cdp_url 改成這個 home 專屬的 CDP port
  4. 啟動：$0 up -a $name
EOF
}

# 一行一個 home：名稱、容器狀態、gateway / dashboard port、profile
ls_line() (
  local agent="$1" ctr st profiles
  [[ -z "$agent" ]] || load_agent "$agent"
  ctr="$(container_name)"
  st="$(docker ps -a --filter "name=^${ctr}$" --format '{{.Status}}' 2>/dev/null | head -n1)"
  # 還沒建過 profile 的 home 沒有 profiles/；pipefail 下 ls 失敗會讓這行中斷。
  profiles="$(ls "$(data_dir)/profiles" 2>/dev/null | tr '\n' ' ' || true)"
  printf '  %-14s %-16s %-24s %-7s %-7s %s\n' "${agent:-hermes}" "$ctr" "${st:-(none)}" \
    "$(gateway_port)" "$(dashboard_port)" "${profiles:--}"
)

cmd_ls() {
  local a
  printf '  %-14s %-16s %-24s %-7s %-7s %s\n' HOME CONTAINER STATUS GATEWAY DASH PROFILES
  ls_line ""
  for a in $(agent_names); do
    ls_line "$a"
  done
}

usage() {
  cat <<EOF
hermes-run.sh — 管理 Hermes 的 Docker Compose stack

Usage:
  $0 up      [-a <名稱> | --all]  啟動（不指定 = 主 home \${HERMES_DATA_DIR:-~/.hermes}）
  $0 down    [-a <名稱> | --all]  停止並移除容器
  $0 restart [-a <名稱> | --all]  重啟 process（不重建容器）
  $0 logs    [-a <名稱>]          跟著看 log
  $0 status  [-a <名稱>]          容器狀態
  $0 cli     [-a <名稱>] <args…>  在容器內以 hermes 身分執行 hermes CLI，例如：
                                  $0 cli profile create <名稱> --clone
                                  $0 cli -a kaka gateway restart
                                  $0 cli doctor
  $0 new <名稱> [--force]         建立新 home：~/.hermes-<名稱>、容器 hermes-<名稱>、agents/<名稱>.conf
  $0 ls                           列出所有 home、port、狀態與 profile

  -a, --agent <名稱>  操作 agents/<名稱>.conf 的 home
  --all               up / down / restart 套用到所有 home

詳見: docs/agents-and-profiles.md
EOF
}

# ---- Main ----

cmd="${1:-}"
[[ $# -gt 0 ]] && shift
target=""
# 選項只認指令後面緊接的那幾個；cli 之後的其餘參數原樣交給 hermes。
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a | --agent)
      [[ -n "${2:-}" ]] || die "$1 後面要接 home 名稱"
      target="$2"
      shift 2
      ;;
    --all)
      target="--all"
      shift
      ;;
    *) break ;;
  esac
done
[[ "$target" == --all && ! "$cmd" =~ ^(up|down|restart)$ ]] && die "--all 只能用在 up / down / restart"
# 舊寫法 `down <名稱>` 會被當成主 home，所以多出來的參數直接報錯。
[[ $# -gt 0 && ! "$cmd" =~ ^(cli|new)$ ]] && die "多餘的參數：$*（指定 home 要用 -a <名稱>）"

case "$cmd" in
  up | down | restart) for_target "$target" "$cmd" ;;
  logs) compose_one "$target" logs -f --tail=100 ;;
  status | ps) compose_one "$target" ps ;;
  cli) cmd_cli "$target" "$@" ;;
  new) cmd_new "$@" ;;
  ls) cmd_ls ;;
  -h | --help | help | "") usage ;;
  *) die "未知指令：${cmd}（執行 '$0 --help' 看用法）" ;;
esac
