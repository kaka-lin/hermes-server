# Docker Compose 設計細節 (Setup Deep Dive)

本文件詳細解析本專案 `docker-compose.yml` 的設計選擇與運作原理。

## 1. 整體架構

```text
┌──────────────────────────────────────────────────┐
│                 Docker Compose                    │
│                                                   │
│  ┌──────────────────────────────────────────┐   │
│  │              hermes (單一容器)             │   │
│  │   /init (s6-overlay) 監督樹:               │   │
│  │     • gateway run      → port 8642         │   │
│  │     • dashboard (s6)   → port 9119         │   │
│  └──────────────────┬───────────────────────┘   │
│                     │                             │
│                     ▼                             │
│  ┌─────────────────┐                             │
│  │  ~/.hermes/     │ ← 單一 owner              │
│  │  (host volume)  │                              │
│  └─────────────────┘                              │
└──────────────────────────────────────────────────┘
```

只有一個容器,來自 image (`nousresearch/hermes-agent`)。容器的 `ENTRYPOINT` 是 `/init`（s6-overlay）,它會起一棵監督樹:

- **gateway**:`gateway run`（持續運行的訊息處理服務,容器的主程式 / CMD）。
- **dashboard**:由 `HERMES_DASHBOARD=1` 啟用,以 s6 服務的形式跟 gateway 跑在**同一個容器**裡（不是另一個容器）。

這是官方建議的部署形態——dashboard 跟 gateway 同容器、共用同一份 `/opt/data`,只有一個寫入者。

## 2. 為什麼是「單一容器」而不是兩個

早期版本曾把 dashboard 拆成第二個容器(`command: dashboard ...`)、跟 gateway 共掛同一份 `~/.hermes`。這違反官方設計,會出兩個問題:

1. **s6 log 撞鎖**:兩個容器都走 `/init`,各自的 s6 監督樹會對 `/opt/data/logs/gateways/<profile>/lock` 搶 flock,後啟動的那個一直噴 `s6-log: ... Resource busy`。
2. **並發寫入**:session 檔與 memory store 不支援多進程同時寫。

官方逐字警告:

> never run two Hermes **gateway** containers against the same data directory simultaneously — session files and memory stores are not designed for concurrent write access.

正解就是本專案現在的做法:**一個容器,用 `HERMES_DASHBOARD=1` 內建 dashboard**。`hermes -p <名稱> gateway run` 切換 profile 子目錄也一樣不能繞過「同一份 data 只能一個 gateway」的規則;真要跑多個獨立 agent,請每個 agent 各自一份 host 資料夾,見 [Multi-Agent — Docker Compose 多容器部署](../guides/multi-agent.md#3-docker-compose-多容器部署)。

## 3. 環境變數與 runtime 設定

本專案刻意把兩種設定分開：

- **Repo `versions.env`**：給 wrapper scripts 傳入 Docker Compose，只放 `HERMES_VERSION`、`AGENT_BROWSER_VERSION` 等 image build 設定。可由 [`versions.env.example`](../../versions.env.example) 建立。
- **`~/.hermes/.env`**：由官方 image 從容器內 `/opt/data/.env` 讀取，放 API keys、平台 token、allowlist。

這跟官方 Docker 文件一致：container 本身是 stateless，所有 Hermes 狀態都在 `/opt/data`，host 預設對應 `~/.hermes`。

## 4. 為何不使用 `env_file`

官方 Docker 路徑已經會讀 `/opt/data/.env`。如果同時把 repo 的版本檔或 runtime `.env` 用 `env_file:` 注入容器，會產生兩份 runtime 設定來源，排錯時很容易不知道哪一份生效。

因此本 compose 不使用 `env_file:`。要改 Hermes runtime 行為時，請改 `~/.hermes/.env` 後重啟 gateway：

```bash
docker compose restart hermes
```

## 5. Volume 結構

`~/.hermes/` 掛載到容器內 `/opt/data`，存放所有 Hermes 狀態（`.env`、`config.yaml`、`state.db`、`memories/`、`skills/`、`cron/`、`pairing/`、`logs/` 等）。完整目錄結構與各檔案職責見 [資料夾結構說明 — 整體結構](../guides/data-volume.md#1-整體結構)。

### 5.1 Runtime socket 與正常關機

`/opt/data` 是 Docker Desktop 的 host bind mount，不能可靠承載 Unix socket。因此 compose 以
`/run/hermes` tmpfs 搭配 `HERMES_RUNTIME_DIR` 存放 gateway control / watchdog socket；它是
container-local 暫存資料，**不是** `~/.hermes` 的替代品，也不需要備份。

Compose 同時設定 `stop_grace_period: 30s`。image 的 `cont-finish.d/10-stop-gateways` 會先要求
s6 管理的 gateway 停止，讓 session 與資料庫有時間收尾，避免下次啟動留下 unclean shutdown 記錄。

## 6. 資源限制設計

```yaml
deploy:
  resources:
    limits:
      memory: ${HERMES_MEMORY_LIMIT:-4G}
      cpus: "${HERMES_CPU_LIMIT:-2.0}"
```

預設值適合大部分場景：

- **4G / 2 CPU**：gateway 與 dashboard 同容器,足以執行 browser automation、多平台訊息處理外加輕量的 Web UI。

不使用 browser tools 時可調降至 `1G`：

```ini
# .env
HERMES_MEMORY_LIMIT=1G
HERMES_SHM_SIZE=64m
```

## 7. `shm_size` 設計選擇

```yaml
shm_size: "${HERMES_SHM_SIZE:-1g}"
```

預設 `1g` 是讓 Playwright/Chromium 能正常啟動（Docker 預設 `/dev/shm` 只給 64 MB，會造成 browser crash）。不需要 browser tools 時可在 `.env` 設 `HERMES_SHM_SIZE=64m` 節省資源。背後成因與詳細症狀見 [瀏覽器自動化 — 為什麼需要 shm_size 1g](../guides/browser-automation.md#21-為什麼需要-shm_size-1g)。

## 8. 健康檢查機制

```yaml
healthcheck:
  test: [ "CMD", "python3", "-c", "import urllib.request as u; u.urlopen(u.Request('https://discord.com', headers={'User-Agent': 'hermes-healthcheck'}), timeout=5)" ]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 15s
```

因為 dashboard 跟 gateway 已經在**同一個容器**裡（s6 監督、crash 自動重啟）,不再需要跨容器的
`GATEWAY_HEALTH_URL` / `depends_on` 來做容器間健康探測——那是舊的雙容器架構才需要的。

現在 compose 的 `healthcheck` 改成探測「容器對外網的連通性」(打 `https://discord.com`),
用來快速暴露 VPN 切換後 Python socket / DNS 快取卡死的情形。背後成因見
[Docker DNS / VPN 疑難排解](../troubleshooting/docker-dns-vpn.md)。

## 9. Network 隔離

```yaml
networks:
  hermes-net:
    driver: bridge
```

獨立的 bridge network 與其他 Docker compose 專案隔離,對外只透過 `ports:` 顯式 publish 必要的 port（`8642` gateway、`9119` dashboard）。多 agent 部署時,各 stack 也能靠這個獨立 network 互不干擾。

## 10. 安全考量

### 10.1 對外開放 port 的風險

預設將 `8642`（gateway）與 `9119`（dashboard）綁定到 host 所有介面。如果機器有公網 IP：

- Gateway 提供 OpenAI 相容 API，**未授權者可能濫用你的 API quota**。
- Dashboard 要求 Basic Auth，但 compose 的首次啟動預設帳密不安全。

**建議**：

```yaml
ports:
  - "127.0.0.1:8642:8642"  # 只綁 localhost
  - "127.0.0.1:9119:9119"
```

或透過 reverse proxy（Caddy、nginx）加上認證。

### 10.2 Allowlist 失誤

預設 allowlist 為空時，gateway 會 fail-closed 拒絕所有請求。若強行設定 `GATEWAY_ALLOW_ALL_USERS=true`：

- 任何取得 bot token 的人都能使用你的 LLM 額度。
- 任何發訊息給 bot 的人都能使用其工具（執行命令、瀏覽網頁等）。

**生產環境絕對禁用** `GATEWAY_ALLOW_ALL_USERS=true`，請改用各平台的 allowlist；欄位清單見本專案 [`.env.example`](../../.env.example)。

### 10.3 Pairing 檔案權限

`~/.hermes/pairing/` 由 Hermes 內部維護，預設為 `chmod 0600`。確保 host 上 `~/.hermes/` 整個目錄不被其他 user 讀取：

```bash
chmod 700 ~/.hermes
```

## 11. Dashboard 的認證：Basic Auth

當 dashboard 綁非 loopback 介面（本專案 publish 為 `0.0.0.0`）時，未提供認證就不會啟動。

本 compose 以內建 Basic Auth 啟動 dashboard，帳密可由 `~/.hermes/.env` 覆蓋：

```ini
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=your-user
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=use-a-long-unique-password
```

> [!WARNING]
> Compose 內的預設帳密只為避免首次啟動失敗，不能視為安全設定。若 dashboard 可被外網存取，
> 仍應在 reverse proxy 層加 TLS 與網路存取限制。

## 12. 相關文件

- [Docker Compose 快速部署](../../README.md)
- [安裝指南](setup.md)
- [資料夾結構說明](../guides/data-volume.md)
