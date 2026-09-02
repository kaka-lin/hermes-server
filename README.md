<p align="center">
  <img src="docs/images/hermes-logo.png" alt="Hermes Agent Server logo" width="120">
</p>

# Hermes Agent Server

本專案提供由 NousResearch 開發的 [Hermes Agent](https://hermes-agent.nousresearch.com) 的 Docker Compose 部署配置，包含 API Gateway 與 Web Dashboard。

## 關於與架構 (Overview)

### 服務架構 (Services)

- **hermes** — 單一容器,內含：
  - 相容 OpenAI 格式的 API Gateway（對外 Port `8642`）
  - Web Dashboard（對外 Port `9119`,由 `HERMES_DASHBOARD=1` 啟用,在容器內以 s6 服務跟 Gateway 一起跑）

資料持久化在 Host 上的 `~/.hermes` 資料夾（透過 `HERMES_DATA_DIR` 可改）。

> 這是官方建議的部署方式:dashboard 跟 gateway 同容器,共用同一份 `/opt/data`。
> **切勿**另外開第二個容器去掛同一個資料夾——會造成 s6 log 撞鎖（`Resource busy`）並有並發寫壞
> session / memory 的風險。詳見 [官方 Docker 文件](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
> 與 [Setup Deep Dive](docs/deployment/setup-deep-dive.md)。

### 專案範圍 (Repository Scope)

只放 Hermes 的可部署設定、Docker Compose、平台接入步驟、日常操作與疑難排解。

通用架構、核心概念、設計取捨、CLI/Reference 筆記放在 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)。

## 快速開始 (Quick Start)

### 前置作業與資源需求 (Prerequisites)

- Docker Engine 24+ 與 Compose v2
- 至少一組支援的 LLM Provider API Key

| 資源 | 最低需求 | 建議規格 |
| --- | --- | --- |
| Memory | 1 GB | 2–4 GB（使用 Browser Automation 時） |
| CPU | 1 core | 2 cores |
| Disk | 500 MB | 2+ GB |

### 1. 初始化資料夾與 API Keys

執行 Setup Wizard 一次，會在 `~/.hermes/.env` 寫入 API 金鑰、平台 Token 與 Allowlist：

```bash
mkdir -p ~/.hermes

docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent setup
```

### 2. 設定 Hermes 執行變數與金鑰

你可以將本專案提供的備用範本 `.env.example` 和 `config.example.yaml` 複製到 `~/.hermes/` 下來使用：

```bash
cp .env.example ~/.hermes/.env
cp config.example.yaml ~/.hermes/config.yaml
```

**注意：** `.env.example` 是 Hermes 的**執行期**設定範本（API Key、平台 Token、Allowlist 等），複製到 `~/.hermes/.env` 給容器內 Hermes 讀取。Compose 編排選項（Port、資源上限、`HERMES_VERSION`）是另一回事，有內建預設，見「設定參考 → 環境變數」。

依你要接的平台（Telegram / Discord / Slack），各自需要設定對應的 `XXX_BOT_TOKEN` 與 `XXX_ALLOWED_USERS`，請參考 [docs/platforms/](docs/platforms/) 下的對應指南。

修改 `~/.hermes/.env` 後，重啟 Gateway 套用：

```bash
./hermes-run.sh restart
```

### 3. 首次建置與啟動

首次需先建置客製化 image（在官方 base image 上套用 `patches/` 的修補），再啟動主 agent：

```bash
./hermes-build.sh        # 建置 image（base image 版本見「操作 → 建置」）
./hermes-run.sh up       # 啟動主 agent
```

- Gateway: <http://localhost:8642>
- Dashboard: <http://localhost:9119>

## 操作 (Operations)

### 建置 (Build)

在官方 base image 上套用 `patches/` 的修補（見 [`patches/`](./patches/)）並覆寫 agent-browser 版本（見 [agent-browser 版本管理](docs/guides/agent-browser-versions.md)），產出客製化成品 image（`kakalin/hermes-agent:latest`）。版本旋鈕集中在 [`versions.env`](./versions.env)，預設 pin 在穩定 tag。

```bash
# 建置預設 pin 版本（穩定）
./hermes-build.sh

# 改建上游最新（浮動 tag，自動 --pull 刷新；非穩定發布版）
./hermes-build.sh latest

# 建指定 tag
./hermes-build.sh v2026.7.0
```

- **升級穩定版**：改 [`versions.env`](./versions.env) 的 `HERMES_VERSION` / `AGENT_BROWSER_VERSION` 並 commit；`docker-compose.yml` / `Dockerfile` 內同名預設是「直接 `docker compose build`」的備援，請一併同步。
- **快速測試**：也可不經腳本直接 `docker compose build`（吃上述備援預設）。

### 啟動與管理 (Run)

[`hermes-run.sh`](./hermes-run.sh) 是啟動與管理的統一入口：無參數操作主 agent（`~/.hermes`），帶名稱操作分身（見下方 [多 Agent 管理](#多-agent-管理-multi-agent)）。

```bash
./hermes-run.sh up                 # 啟動主 agent（~/.hermes）
./hermes-run.sh restart            # 重啟 process（不重建容器）
./hermes-run.sh logs               # 跟著看即時 log
./hermes-run.sh status             # 所有 agent 狀態總覽
./hermes-run.sh down               # 停止並移除容器
```

> 也可不經腳本、直接用 docker compose 操作主 agent（快速 / 單一）：`docker compose up -d`、`docker compose logs -f`、`docker compose down`；改了 `.env` / `docker-compose.yml` 要重建容器時用 `docker compose down && docker compose up -d`。

#### 多 Agent 管理 (Multi-Agent)

需要多個 agent 同時長駐（各自 24/7 接訊息、互不干擾）時，用 [`hermes-run.sh`](./hermes-run.sh)。它沿用同一份 `docker-compose.yml`，靠 `docker compose -p <name>` 把每個 agent 隔離成獨立 stack；分身的 port / 容器名 / data dir 寫在各自的 `agents/<name>.conf`。

```bash
./hermes-run.sh up              # 啟動主 agent (~/.hermes)
./hermes-run.sh new coder       # scaffold 新分身（clone 主 agent，自動挑 port）
./hermes-run.sh up coder        # 啟動分身
./hermes-run.sh up all          # 主 agent + 所有分身一次拉起
./hermes-run.sh down [coder|all] # 停止並移除容器（無參數 = 主 agent）
./hermes-run.sh restart [coder]  # 重啟 process（不重建容器）
./hermes-run.sh logs [coder]     # 跟著看 log（無參數 = 主 agent）
./hermes-run.sh status           # 所有 agent 狀態總覽
./hermes-run.sh ls               # 列出已設定的 agent 與其 port
```

> 機制、`new` 流程與注意事項見 [Multi-Agent — 用 hermes-run.sh 管理多容器](docs/guides/multi-agent.md#36-用-hermes-runsh-管理多容器)。

### 查版本 (Check Version)

base image 版本 pin 在 `HERMES_VERSION`（見 [`versions.env`](./versions.env)），所以從設定就看得出版本。若用 `./hermes-build.sh latest`（浮動 tag、非穩定發布版）建置，就看不出實際版本，需用下列指令向運行中的 image 查詢。注意 image 用 **s6-overlay** 啟動：`hermes` 不在 `docker exec` 的預設 PATH，且直接 `docker run <image> hermes …` 會把所有服務拉起再關掉（一堆 `s6-rc` log、有副作用）。`hermes` 本身是 Python 入口腳本（`/opt/hermes/hermes`），所以一律用 venv python 呼叫，與 cron 腳本一致。

```bash
# 服務正在跑時（最常用，輸出乾淨）；多 agent 時把 hermes 換成目標容器名（如 hermes-katherine）
docker exec hermes bash -c '/opt/hermes/.venv/bin/python /opt/hermes/hermes version'

# 服務沒在跑時：用建置好的 image，--entrypoint 繞過 s6 避免拉起服務
docker run --rm --entrypoint /opt/hermes/.venv/bin/python \
  kakalin/hermes-agent:latest /opt/hermes/hermes version
```

輸出範例：`Hermes Agent v0.16.0 (2026.6.5) · upstream f8adefde`。

## 設定參考 (Configuration)

### 環境變數 (Environment Variables)

下表是 Docker Compose 傳入容器的變數，多數是有安全預設的編排選項（在 `docker-compose.yml`；`HERMES_VERSION` / `AGENT_BROWSER_VERSION` 在 `versions.env`），可直接沿用或覆寫。要覆寫：單次用環境變數（如 `HERMES_GATEWAY_PORT=8643 ./hermes-run.sh up`），多 agent 則寫在各自的 `agents/<name>.conf`。**例外：`API_SERVER_KEY` 是驗證金鑰，預設不安全，務必更改。** Hermes 執行期設定（API Key、平台 Token 等）見 [`.env.example`](./.env.example)，複製到 `~/.hermes/.env` 使用。

| 變數 | 預設值 | 說明 |
| --- | --- | --- |
| `TZ` | `Asia/Taipei` | Container 時區 |
| `HERMES_VERSION` | `v2026.6.5` | 上游 base image 版本 tag（build 時）；設 `latest` 可測上游最新 |
| `AGENT_BROWSER_VERSION` | `0.36.0` | agent-browser 版本（build 時覆寫上游 pin，見 [agent-browser 版本管理](docs/guides/agent-browser-versions.md)） |
| `HERMES_CONTAINER_NAME` | `hermes` | Container Name |
| `HERMES_DATA_DIR` | `~/.hermes` | Host 上的資料目錄（多 Profile 時切換此路徑） |
| `HERMES_GATEWAY_PORT` | `8642` | Gateway 對外 Port |
| `HERMES_DASHBOARD_PORT` | `9119` | Dashboard 對外 Port |
| `HERMES_DASHBOARD` | `1` | 是否在容器內啟用 Web Dashboard（s6 服務） |
| `HERMES_DASHBOARD_INSECURE` | `true` | Dashboard 跳過 OAuth gate,允許無認證存取（等同舊版 `--insecure`） |
| `API_SERVER_KEY` | `hermes_default_secret` ⚠️ | API Server 驗證金鑰；**務必更改**（預設不安全、公開已知） |
| `HERMES_MEMORY_LIMIT` | `4G` | 容器記憶體限制（Gateway + Dashboard 同容器） |
| `HERMES_CPU_LIMIT` | `2.0` | 容器 CPU 限制 |
| `HERMES_SHM_SIZE` | `1g` | Browser Tools 共享記憶體 |

> **Note:** API Keys、平台 Token、Allowlist 由 Hermes 從 `~/.hermes/.env` 讀取。這跟官方 Docker 文件一致：Host 的 `~/.hermes` 會掛載到容器內 `/opt/data`。

### 資料持久化 (Data Volume)

掛載到 `~/.hermes`（或 `HERMES_DATA_DIR`）的內容：

- `.env` — API 金鑰（Setup Wizard 產生，或從本專案的 `.env.example` 複製）
- `config.yaml` — Agent 設定（如 Fallback Model、Smart Routing 等，可參考 [`config.example.yaml`](./config.example.yaml)）
- `sessions/` — 對話歷史
- `memories/` — 持久化記憶
- `skills/` — 已安裝的技能
- `logs/`、`hooks/`、`cron/` — 執行紀錄與排程

> ⚠️ 切勿同時跑兩個 Gateway 共用同一資料夾（包含 `hermes -p <名稱> gateway run` 共用 volume 的場景）。多 agent 隔離請每個 agent 各自一個 host 資料夾，官方逐字警告與部署 SOP 見 [Multi-Agent — Docker Compose 多容器部署](docs/guides/multi-agent.md#3-docker-compose-多容器部署)。

### 瀏覽器自動化 (Browser Automation)

> 詳見 [瀏覽器自動化指南](docs/guides/browser-automation.md)

使用 Playwright/Chromium 工具時需要 `shm_size: 1g`（已預設啟用）。
不使用 Browser Tools 時可在 Repo `.env` 設定 `HERMES_SHM_SIZE=64m` 節省資源。

Mac 上需要以多個 Chrome profile 透過 CDP 給 agent 使用時，有兩種做法：

- **OpenClaw Node**（需另外部署 [openclaw-server](https://github.com/kaka-lin/openclaw-server)）：由 Node 當 Chrome supervisor，採 lazy-load，profile 第一次被使用時才 spawn。
- **本專案的 [`start-browsers.sh`](start-browsers.sh)（推薦）**：在 host 端 eager 啟動／停止／檢查多組獨立 Chrome 實例，不依賴 OpenClaw，避免 lazy-load 與 fallback 陷阱。Profile 與 port 對應寫在同層的 `browsers.conf`。

  > 差異比較與選擇依據見： [瀏覽器接線架構（Docker → Mac Chrome）](docs/guides/mac-chrome-cdp-guide.md)。

## 完整文件 (Documentation)

完整文件請見 [`docs/`](docs/README.md)：

- [安裝指南](docs/deployment/setup.md)
- [瀏覽器自動化指南](docs/guides/browser-automation.md)
- [瀏覽器接線架構（Docker → Mac Chrome）](docs/guides/mac-chrome-cdp-guide.md)
- [Discord 整合](docs/platforms/discord.md)
- [常見問題排除](docs/README.md#疑難排解-troubleshooting)

如需深入了解 Hermes Agent 核心架構，請參閱 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)。
