<p align="center">
  <img src="docs/images/hermes-logo.png" alt="Hermes Agent Server logo" width="120">
</p>

# Hermes Agent Server

本專案提供由 NousResearch 開發的 [Hermes Agent](https://hermes-agent.nousresearch.com) 的 Docker Compose 部署配置，包含 API Gateway 與 Web Dashboard。

## 服務架構 (Services)

- **hermes** — 單一容器,內含：
  - 相容 OpenAI 格式的 API Gateway（對外 Port `8642`）
  - Web Dashboard（對外 Port `9119`,由 `HERMES_DASHBOARD=1` 啟用,在容器內以 s6 服務跟 Gateway 一起跑）

資料持久化在 Host 上的 `~/.hermes` 資料夾（透過 `HERMES_DATA_DIR` 可改）。

> 這是官方建議的部署方式:dashboard 跟 gateway 同容器,共用同一份 `/opt/data`。
> **切勿**另外開第二個容器去掛同一個資料夾——會造成 s6 log 撞鎖（`Resource busy`）並有並發寫壞
> session / memory 的風險。詳見 [官方 Docker 文件](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
> 與 [Setup Deep Dive](docs/deployment/setup-deep-dive.md)。

## 專案範圍 (Repository Scope)

只放 Hermes 的可部署設定、Docker Compose、平台接入步驟、日常操作與疑難排解。

通用架構、核心概念、設計取捨、CLI/Reference 筆記放在 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)。

## 安裝前置作業 (Prerequisites)

- Docker Engine 24+ 與 Compose v2
- 至少 1 GB RAM（使用 Browser Automation 時建議 2–4 GB）
- 至少一組支援的 LLM Provider API Key

## 快速啟動 (Quick Start)

### 1. 初始化資料夾與 API Keys

執行 Setup Wizard 一次，會在 `~/.hermes/.env` 寫入 API 金鑰、平台 Token 與 Allowlist：

```bash
mkdir -p ~/.hermes

docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent setup
```

### 2. 設定 Hermes 運行變數與金鑰

你可以將本專案提供的備用範本 `.env.example` 和 `config.example.yaml` 複製到 `~/.hermes/` 下來使用：

```bash
cp .env.example ~/.hermes/.env
cp config.example.yaml ~/.hermes/config.yaml
```

**注意：** 本專案目錄下的 `.env` 主要是給 Docker Compose 解析編排選項用的（例如 Port、Image Tag），實際的 Hermes Runtime 設定（API Key、平台 Token、使用者授權）請放在 `~/.hermes/.env`。

依你要接的平台（Telegram / Discord / Slack），各自需要設定對應的 `XXX_BOT_TOKEN` 與 `XXX_ALLOWED_USERS`，請參考 [docs/platforms/](docs/platforms/) 下的對應指南。

修改 `~/.hermes/.env` 後，重啟 Gateway 套用：

```bash
docker compose restart hermes
```

### 3. 啟動服務

```bash
docker compose up -d
```

- Gateway: <http://localhost:8642>
- Dashboard: <http://localhost:9119>

## 環境變數與設定 (Configuration)

Compose 編排選項透過此目錄下的 `.env` 設定。完整變數清單請見 [`.env.example`](./.env.example) 與 [文件中心](docs/README.md)。

| 變數 | 預設值 | 說明 |
| --- | --- | --- |
| `TZ` | `Asia/Taipei` | Container 時區 |
| `HERMES_VERSION` | `v2026.6.5` | 上游 base image 版本 tag（build 時）；設 `latest` 可測上游最新 |
| `HERMES_CONTAINER_NAME` | `hermes` | Container Name |
| `HERMES_DATA_DIR` | `~/.hermes` | Host 上的資料目錄（多 Profile 時切換此路徑） |
| `HERMES_GATEWAY_PORT` | `8642` | Gateway 對外 Port |
| `HERMES_DASHBOARD_PORT` | `9119` | Dashboard 對外 Port |
| `HERMES_DASHBOARD` | `1` | 是否在容器內啟用 Web Dashboard（s6 服務） |
| `HERMES_DASHBOARD_INSECURE` | `true` | Dashboard 跳過 OAuth gate,允許無認證存取（等同舊版 `--insecure`） |
| `API_SERVER_KEY` | `hermes_default_secret` | API Server 驗證金鑰 |
| `HERMES_MEMORY_LIMIT` | `4G` | 容器記憶體限制（Gateway + Dashboard 同容器） |
| `HERMES_CPU_LIMIT` | `2.0` | 容器 CPU 限制 |
| `HERMES_SHM_SIZE` | `1g` | Browser Tools 共享記憶體 |

> **Note:** API Keys、平台 Token、Allowlist 由 Hermes 從 `~/.hermes/.env` 讀取。這跟官方 Docker 文件一致：Host 的 `~/.hermes` 會掛載到容器內 `/opt/data`。

## 資料持久化 (Data Volume)

掛載到 `~/.hermes`（或 `HERMES_DATA_DIR`）的內容：

- `.env` — API 金鑰（Setup Wizard 產生，或從本專案的 `.env.example` 複製）
- `config.yaml` — Agent 設定（如 Fallback Model、Smart Routing 等，可參考 [`config.example.yaml`](./config.example.yaml)）
- `sessions/` — 對話歷史
- `memories/` — 持久化記憶
- `skills/` — 已安裝的技能
- `logs/`、`hooks/`、`cron/` — 執行紀錄與排程

> ⚠️ 切勿同時跑兩個 Gateway 共用同一資料夾（包含 `hermes -p <名稱> gateway run` 共用 volume 的場景）。多 agent 隔離請每個 agent 各自一個 host 資料夾，官方逐字警告與部署 SOP 見 [Multi-Agent — Docker Compose 多容器部署](docs/guides/multi-agent.md#3-docker-compose-多容器部署)。

## 瀏覽器自動化 (Browser Automation)

> 詳見 [瀏覽器自動化指南](docs/guides/browser-automation.md)

使用 Playwright/Chromium 工具時需要 `shm_size: 1g`（已預設啟用）。
不使用 Browser Tools 時可在 Repo `.env` 設定 `HERMES_SHM_SIZE=64m` 節省資源。

Mac 上需要以多個 Chrome profile 透過 CDP 給 agent 使用時，有兩種做法：

- **OpenClaw Node**（需另外部署 [openclaw-server](https://github.com/kaka-lin/openclaw-server)）：由 Node 當 Chrome supervisor，採 lazy-load，profile 第一次被使用時才 spawn。
- **本專案的 [`start-browsers.sh`](start-browsers.sh)（推薦）**：在 host 端 eager 啟動／停止／檢查多組獨立 Chrome 實例，不依賴 OpenClaw，避免 lazy-load 與 fallback 陷阱。Profile 與 port 對應寫在同層的 `browsers.conf`。

  > 差異比較與選擇依據見： [瀏覽器接線架構（Docker → Mac Chrome）](docs/guides/mac-chrome-cdp-guide.md)。

## 資源需求 (Resource Requirements)

| 資源 | 最低需求 | 建議規格 |
| --- | --- | --- |
| Memory | 1 GB | 2–4 GB |
| CPU | 1 core | 2 cores |
| Disk | 500 MB | 2+ GB |

## 常用指令 (Common Commands)

```bash
# 背景啟動所有服務（首次啟動，或 Dockerfile 有異動時加上 --build）
docker compose up -d

# 重啟服務（不重建容器，僅重啟 process）
docker compose restart

# 套用 .env / docker-compose.yml 變更（重建容器但不更新 image）
docker compose down && docker compose up -d

# 查看即時 log
docker compose logs -f

# 查看最近 200 行 log
docker compose logs --tail 200 hermes

# 停止服務
docker compose down

# 重建客製化層並重啟（base image 已 pin 在 HERMES_VERSION，不會自動換版）
docker compose build && docker compose up -d

# 升級上游 Hermes：改 HERMES_VERSION 再重建
#   穩定版：在 .env 設 HERMES_VERSION=<新 tag>（預設 v2026.6.5），再 build
#   試最新：HERMES_VERSION=latest docker compose build --pull && docker compose up -d
```

## 查版本 (Check Version)

base image 已 pin 在 `HERMES_VERSION`（預設 `v2026.6.5`），所以版本直接看 Dockerfile / `docker-compose.yml` 即可。若改用 `HERMES_VERSION=latest`（浮動 tag、非穩定發布版）建置，就看不出實際版本，需用下列指令向運行中的 image 查詢。注意 image 用 **s6-overlay** 啟動：`hermes` 不在 `docker exec` 的預設 PATH，且直接 `docker run <image> hermes …` 會把所有服務拉起再關掉（一堆 `s6-rc` log、有副作用）。`hermes` 本身是 Python 入口腳本（`/opt/hermes/hermes`），所以一律用 venv python 呼叫，與 cron 腳本一致。

```bash
# 服務正在跑時（最常用，輸出乾淨）；多 agent 時把 hermes 換成目標容器名（如 hermes-katherine）
docker exec hermes bash -c '/opt/hermes/.venv/bin/python /opt/hermes/hermes version'

# 服務沒在跑時：用建置好的 image，--entrypoint 繞過 s6 避免拉起服務
docker run --rm --entrypoint /opt/hermes/.venv/bin/python \
  kakalin/hermes-agent:latest /opt/hermes/hermes version
```

輸出範例：`Hermes Agent v0.16.0 (2026.6.5) · upstream f8adefde`。

## 多 Agent 管理 (Multi-Agent)

需要多個 agent 同時長駐（各自 24/7 接訊息、互不干擾）時，用 [`hermes-stack.sh`](./hermes-stack.sh)。它沿用同一份 `docker-compose.yml`，靠 `docker compose -p <name>` 把每個 agent 隔離成獨立 stack；分身的 port / 容器名 / data dir 寫在各自的 `agents/<name>.conf`。

```bash
./hermes-stack.sh up              # 啟動主 agent (~/.hermes)
./hermes-stack.sh new coder       # scaffold 新分身（clone 主 agent，自動挑 port）
./hermes-stack.sh up coder        # 啟動分身
./hermes-stack.sh up all          # 主 agent + 所有分身一次拉起
./hermes-stack.sh down [coder|all] # 停止並移除容器（無參數 = 主 agent）
./hermes-stack.sh restart [coder]  # 重啟 process（不重建容器）
./hermes-stack.sh logs [coder]     # 跟著看 log（無參數 = 主 agent）
./hermes-stack.sh status           # 所有 agent 狀態總覽
./hermes-stack.sh ls               # 列出已設定的 agent 與其 port
```

> 機制、`new` 流程與注意事項見 [Multi-Agent — 用 hermes-stack.sh 管理多容器](docs/guides/multi-agent.md#36-用-hermes-stacksh-管理多容器)。

## 完整文件 (Documentation)

完整文件請見 [`docs/`](docs/README.md)：

- [安裝指南](docs/deployment/setup.md)
- [瀏覽器自動化指南](docs/guides/browser-automation.md)
- [瀏覽器接線架構（Docker → Mac Chrome）](docs/guides/mac-chrome-cdp-guide.md)
- [Discord 整合](docs/platforms/discord.md)
- [常見問題排除](docs/README.md#疑難排解-troubleshooting)

如需深入了解 Hermes Agent 核心架構，請參閱 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)。
