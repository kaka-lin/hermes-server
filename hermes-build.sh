#!/bin/bash
#
# hermes-build.sh — 建置客製化的 Hermes image
#
# 在官方 base image（nousresearch/hermes-agent:<版本>）上套用 patches/ 下的
# unified diff（見 patches/apply.py）並覆寫 agent-browser 版本，產出
# docker-compose.yml 指定的成品 image（kakalin/hermes-agent:latest），
# 供 hermes-run.sh 啟動的所有 agent 共用。
#
# 版本旋鈕（base image 與 agent-browser）集中在 versions.env（純資料、git 追蹤），
# 可在指令列 / 環境變數臨時覆寫。
#
# Usage:
#   ./hermes-build.sh                # 建置 versions.env pin 的版本
#   ./hermes-build.sh latest         # 改建上游最新（浮動 tag，自動加 --pull 刷新）
#   ./hermes-build.sh v2026.7.0      # 建指定 tag
#   ./hermes-build.sh --no-cache     # 其餘旗標原樣轉給 docker compose build
#
# 升級：改 versions.env 並 commit。
# 快速測試也可直接 `docker compose build`（吃 docker-compose.yml 的同名預設）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# 版本從 versions.env 載入。環境變數覆寫（AGENT_BROWSER_VERSION=x.y.z ./hermes-build.sh）
# 要先於 source 收起來，否則會被檔案內容蓋掉。
agent_browser_override="${AGENT_BROWSER_VERSION:-}"
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"

usage() {
  cat <<EOF
hermes-build.sh — 建置客製化的 Hermes image

在官方 base image（nousresearch/hermes-agent:<版本>）上套用 patches/ 的修補
並覆寫 agent-browser 版本，產出 docker-compose.yml 指定的成品 image，
供 hermes-run.sh 啟動的所有 agent 共用。

Usage:
  ./hermes-build.sh                建置 versions.env pin 的版本（目前 ${HERMES_VERSION} / agent-browser ${AGENT_BROWSER_VERSION}）
  ./hermes-build.sh latest         改建上游最新（浮動 tag，自動 --pull 刷新）
  ./hermes-build.sh v2026.7.0      建指定 tag
  ./hermes-build.sh --no-cache     其餘旗標原樣轉給 docker compose build

升級：改 versions.env 並 commit。
臨時測試 agent-browser 其他版本：AGENT_BROWSER_VERSION=x.y.z ./hermes-build.sh
快速測試也可直接 \`docker compose build\`（吃 docker-compose.yml 的同名預設）。
EOF
}

version="$HERMES_VERSION"
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
cmd=(docker compose --project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE" build)
case "$version" in
  latest | main) cmd+=(--pull) ;;
esac
if [[ ${#passthrough[@]} -gt 0 ]]; then
  cmd+=("${passthrough[@]}")
fi

agent_browser_version="${agent_browser_override:-$AGENT_BROWSER_VERSION}"

echo "==> Building Hermes image (base: nousresearch/hermes-agent:${version}, agent-browser: ${agent_browser_version})"
HERMES_VERSION="$version" AGENT_BROWSER_VERSION="$agent_browser_version" "${cmd[@]}"
echo "==> Done. 啟動：./hermes-run.sh up"
