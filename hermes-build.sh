#!/bin/bash
#
# hermes-build.sh — 建置客製化的 Hermes image
#
# 在官方 base image 上套用 patches/ 的修補，產出 <HERMES_IMAGE>:<版本>。
# patches/ 只對應 compose.env 目前 pin 的版本，換版本要重算。
# 用法：./hermes-build.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
COMPOSE_ENV_FILE="$SCRIPT_DIR/compose.env"
[[ -f "$SCRIPT_DIR/versions.env" && ! -f "$COMPOSE_ENV_FILE" ]] &&
  echo "warn: versions.env 已改名為 compose.env，請執行 mv versions.env compose.env（目前用預設值）" >&2
COMPOSE=(docker compose)
[[ -f "$COMPOSE_ENV_FILE" ]] && COMPOSE+=(--env-file "$COMPOSE_ENV_FILE")
COMPOSE+=(--project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE")

# 沒有 compose.env 時的 fallback，要和 docker-compose.yml / Dockerfile 的 :- 預設一致。
HERMES_VERSION_DEFAULT="v0.23.1"
HERMES_IMAGE_DEFAULT="kakalin/hermes-agent"

usage() {
  cat <<EOF
hermes-build.sh — 建置客製化的 Hermes image

在官方 base image（nousresearch/hermes-agent:<版本>）上套用 patches/ 的修補，
產出 <HERMES_IMAGE>:<版本>（tag 跟 base 同名，多版本可並存），供 hermes-run.sh 啟動。
啟動時用同一個變數挑 image：HERMES_VERSION=<版本> ./hermes-run.sh up。

Usage:
  ./hermes-build.sh                建置 compose.env 的版本（fallback=${HERMES_VERSION_DEFAULT}）
  ./hermes-build.sh latest         改建上游最新（浮動 tag，自動 --pull 刷新）
  ./hermes-build.sh v0.23.2        建指定 tag
  ./hermes-build.sh --no-cache     其餘旗標原樣轉給 docker compose build

升級版本或換 image 名稱：改 compose.env 的 HERMES_VERSION、HERMES_IMAGE，不必 commit。
快速測試也可直接 \`docker compose build\`（吃 docker-compose.yml 的同名預設）。
EOF
}

# Ask Compose for its resolved environment instead of sourcing compose.env as
# shell code. That keeps Compose interpolation semantics authoritative.
# $1 = variable, $2 = fallback, rest = command prefix (e.g. env -u VAR).
resolved() {
  local key="$1" fallback="$2" v
  shift 2
  v="$({
    "$@" "${COMPOSE[@]}" config --environment \
      | awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
  } || true)"
  echo "${v:-$fallback}"
}
version="$(resolved HERMES_VERSION "$HERMES_VERSION_DEFAULT")"
image="$(resolved HERMES_IMAGE "$HERMES_IMAGE_DEFAULT")"
# 不加 HERMES_VERSION 執行 hermes-run.sh up 會用的版本；建的就是它時，啟動提示不必帶 HERMES_VERSION。
pinned="$(resolved HERMES_VERSION "$HERMES_VERSION_DEFAULT" env -u HERMES_VERSION)"
passthrough=()

for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      passthrough+=("$arg") # --no-cache / --progress=… 等旗標轉給 compose
      ;;
    *)
      version="$arg" # 第一個非旗標參數當 base image 版本 tag
      ;;
  esac
done

# 浮動 tag 自動 --pull，確保抓到當下最新內容（pin 的 tag 不需要）
cmd=("${COMPOSE[@]}" build)
case "$version" in
  latest | main) cmd+=(--pull) ;;
esac
if [[ ${#passthrough[@]} -gt 0 ]]; then
  cmd+=("${passthrough[@]}")
fi

echo "==> Building Hermes image (base: nousresearch/hermes-agent:${version})"
HERMES_VERSION="$version" "${cmd[@]}"
echo "==> Done: ${image}:${version}"
if [[ "$version" == "$pinned" ]]; then
  echo "    啟動：./hermes-run.sh up"
else
  echo "    啟動：HERMES_VERSION=${version} ./hermes-run.sh up"
fi
