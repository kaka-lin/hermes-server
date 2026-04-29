# Hermes Agent Server

本專案提供由 NousResearch 開發的 [Hermes Agent](https://hermes-agent.nousresearch.com) 的 Docker Compose 部署配置，包含 API Gateway 與 Web Dashboard。

## 服務架構 (Services)

- **hermes** — 相容 OpenAI 格式的 API Gateway（對外 Port `8642`）
- **hermes-dashboard** — Web Dashboard（對外 Port `9119`）

兩個服務共用 Host 上的 `~/.hermes` 資料夾（透過 `HERMES_DATA_DIR` 可改）。

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
| `HERMES_IMAGE` | `nousresearch/hermes-agent:latest` | Docker Image Tag |
| `HERMES_CONTAINER_NAME` | `hermes` | Gateway Container Name |
| `HERMES_DASHBOARD_CONTAINER_NAME` | `hermes-dashboard` | Dashboard Container Name |
| `HERMES_DATA_DIR` | `~/.hermes` | Host 上的資料目錄（多 Profile 時切換此路徑） |
| `HERMES_GATEWAY_PORT` | `8642` | Gateway 對外 Port |
| `HERMES_DASHBOARD_PORT` | `9119` | Dashboard 對外 Port |
| `API_SERVER_KEY` | `hermes_default_secret` | API Server 驗證金鑰 |
| `HERMES_MEMORY_LIMIT` | `4G` | Gateway 容器記憶體限制 |
| `HERMES_CPU_LIMIT` | `2.0` | Gateway 容器 CPU 限制 |
| `HERMES_DASHBOARD_MEMORY_LIMIT` | `512M` | Dashboard 容器記憶體限制 |
| `HERMES_DASHBOARD_CPU_LIMIT` | `0.5` | Dashboard 容器 CPU 限制 |
| `HERMES_SHM_SIZE` | `1g` | Browser Tools 共享記憶體 |
| `GATEWAY_HEALTH_URL` | `http://hermes:8642` | Dashboard 健康檢查目標 |
| `GATEWAY_HEALTH_TIMEOUT` | `3` | 健康檢查 Timeout（秒） |

> **Note:** API Keys、平台 Token、Allowlist 由 Hermes 從 `~/.hermes/.env` 讀取。這跟官方 Docker 文件一致：Host 的 `~/.hermes` 會掛載到容器內 `/opt/data`。

## 資料持久化 (Data Volume)

掛載到 `~/.hermes`（或 `HERMES_DATA_DIR`）的內容：

- `.env` — API 金鑰（Setup Wizard 產生，或從本專案的 `.env.example` 複製）
- `config.yaml` — Agent 設定（如 Fallback Model、Smart Routing 等，可參考 [`config.example.yaml`](./config.example.yaml)）
- `sessions/` — 對話歷史
- `memories/` — 持久化記憶
- `skills/` — 已安裝的技能
- `logs/`、`hooks/`、`cron/` — 執行紀錄與排程

> ⚠️ 切勿同時跑兩個 Gateway 共用同一資料夾，Session 與 Memory Store 不支援並行寫入。需要多環境隔離時，請參考 [`~/.hermes` 資料夾結構說明 §4](docs/guides/data-volume.md#4-多-profile-切換)（注意：尚未實際驗證）。

## 瀏覽器自動化 (Browser Automation)

使用 Playwright/Chromium 工具時需要 `shm_size: 1g`（已預設啟用）。
不使用 Browser Tools 時可在 Repo `.env` 設定 `HERMES_SHM_SIZE=64m` 節省資源。

> 詳見 [瀏覽器自動化指南](docs/guides/browser-automation.md)

## 資源需求 (Resource Requirements)

| 資源 | 最低需求 | 建議規格 |
| --- | --- | --- |
| Memory | 1 GB | 2–4 GB |
| CPU | 1 core | 2 cores |
| Disk | 500 MB | 2+ GB |

## 常用指令 (Common Commands)

```bash
# 背景啟動所有服務
docker compose up -d

# 查看即時 log
docker compose logs -f

# 查看最近 200 行 log
docker compose logs --tail 200 hermes

# 停止服務
docker compose down

# 更新 image
docker compose pull && docker compose up -d
```

## 完整文件 (Documentation)

完整文件請見 [`docs/`](docs/README.md)：

- [安裝指南](docs/deployment/setup.md)
- [瀏覽器自動化指南](docs/guides/browser-automation.md)
- [Discord 整合](docs/platforms/discord.md)
- [常見問題排除](docs/README.md#疑難排解-troubleshooting)

如需深入了解 Hermes Agent 核心架構，請參閱 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)。
