#!/bin/bash
#
# hermes-build.sh — 建置客製化的 Hermes image
#
# 在官方 base image（nousresearch/hermes-agent:<版本>）上套用 patches/ 下的
# unified diff（見 patches/apply.py），產出 docker-compose.yml 指定的成品 image
# kakalin/hermes-agent:<版本>（tag 跟 base 同名，多版本可並存），供 hermes-run.sh 啟動。
#
# base image 版本由 repo `versions.env` 的 HERMES_VERSION 決定；沒有設定時使用穩定預設，
# 也可在指令列覆寫。
# 啟動時用同一個變數挑 image：HERMES_VERSION=v2026.9.14 ./hermes-run.sh up
# （或寫進 agents/<name>.conf）。patches/ 只對應目前 pin 的版本，換版本要重算。
#
# Usage:
#   ./hermes-build.sh                # 建置 Compose .env 或預設 pin 版本
#   ./hermes-build.sh latest         # 改建上游最新（浮動 tag，自動加 --pull 刷新）
#   ./hermes-build.sh v2026.7.0      # 建指定 tag
#   ./hermes-build.sh --no-cache     # 其餘旗標原樣轉給 docker compose build
#
# 升級版本：改 repo `versions.env`，不必 commit。
# 快速測試也可直接 `docker compose build`（吃 docker-compose.yml 的同名預設）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
VERSIONS_FILE="$SCRIPT_DIR/versions.env"
COMPOSE=(docker compose)
[[ -f "$VERSIONS_FILE" ]] && COMPOSE+=(--env-file "$VERSIONS_FILE")
COMPOSE+=(--project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE")

# 上游 base image 的無設定 fallback。docker-compose.yml / Dockerfile 內的同名
# 預設僅為「直接 docker compose build」的備援，請與此值保持一致。
HERMES_VERSION_DEFAULT="v2026.9.14"

usage() {
  cat <<EOF
hermes-build.sh — 建置客製化的 Hermes image

在官方 base image（nousresearch/hermes-agent:<版本>）上套用 patches/ 的修補，
產出 kakalin/hermes-agent:<版本>（tag 跟 base 同名，多版本可並存），供 hermes-run.sh 啟動。
啟動時用同一個變數挑 image：HERMES_VERSION=<版本> ./hermes-run.sh up（或寫進 agents/<name>.conf）。

Usage:
  ./hermes-build.sh                建置 repo versions.env 或預設版本（fallback=${HERMES_VERSION_DEFAULT}）
  ./hermes-build.sh latest         改建上游最新（浮動 tag，自動 --pull 刷新）
  ./hermes-build.sh v2026.7.0      建指定 tag
  ./hermes-build.sh --no-cache     其餘旗標原樣轉給 docker compose build

升級版本：改 repo versions.env 的 HERMES_VERSION，不必 commit。
快速測試也可直接 \`docker compose build\`（吃 docker-compose.yml 的同名預設）。
EOF
}

# Ask Compose for its resolved environment instead of sourcing versions.env as
# shell code. That keeps Compose interpolation semantics authoritative.
version="$({
  "${COMPOSE[@]}" config --environment \
    | awk -F= '$1 == "HERMES_VERSION" {sub(/^HERMES_VERSION=/, ""); print; exit}'
} || true)"
version="${version:-$HERMES_VERSION_DEFAULT}"
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
echo "==> Done: kakalin/hermes-agent:${version}"
if [[ "$version" == "$HERMES_VERSION_DEFAULT" ]]; then
  echo "    啟動：./hermes-run.sh up"
else
  echo "    啟動：HERMES_VERSION=${version} ./hermes-run.sh up（或寫進 agents/<name>.conf）"
fi
