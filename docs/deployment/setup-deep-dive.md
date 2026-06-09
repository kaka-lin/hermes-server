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

- **Repo `.env`**：給 Docker Compose 解析 `${...}`，只放 port、image tag、resource limit、`HERMES_DATA_DIR` 等編排設定。
- **`~/.hermes/.env`**：由官方 image 從容器內 `/opt/data/.env` 讀取，放 API keys、平台 token、allowlist。

這跟官方 Docker 文件一致：container 本身是 stateless，所有 Hermes 狀態都在 `/opt/data`，host 預設對應 `~/.hermes`。

## 4. 為何不使用 `env_file`

官方 Docker 路徑已經會讀 `/opt/data/.env`。如果同時把 repo `.env` 用 `env_file:` 注入容器，會產生兩份 runtime 設定來源，排錯時很容易不知道哪一份生效。

因此本 compose 不使用 `env_file:`。要改 Hermes runtime 行為時，請改 `~/.hermes/.env` 後重啟 gateway：

```bash
docker compose restart hermes
```

## 5. Volume 結構

`~/.hermes/` 掛載到容器內 `/opt/data`，存放所有 Hermes 狀態（`.env`、`config.yaml`、`state.db`、`memories/`、`skills/`、`cron/`、`pairing/`、`logs/` 等）。完整目錄結構與各檔案職責見 [資料夾結構說明 — 整體結構](../guides/data-volume.md#1-整體結構)。

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
  test: [ "CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('https://discord.com', timeout=5)" ]
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
- Dashboard 預設沒有密碼保護。

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

**生產環境絕對禁用** `GATEWAY_ALLOW_ALL_USERS=true`，請改用平台 allowlist。詳見 [Allowlist 設定指南](../guides/allowlist-config.md)。

### 10.3 Pairing 檔案權限

`~/.hermes/pairing/` 由 Hermes 內部維護，預設為 `chmod 0600`。確保 host 上 `~/.hermes/` 整個目錄不被其他 user 讀取：

```bash
chmod 700 ~/.hermes
```

## 11. Dashboard 的認證:`HERMES_DASHBOARD_INSECURE`

當 dashboard 綁非 loopback 介面（本專案綁 `0.0.0.0`)時,官方的行為是:

- 若有註冊 OAuth provider(例如設了 `HERMES_DASHBOARD_OAUTH_CLIENT_ID`),OAuth gate 會自動生效。
- 若沒有任何認證 provider,`start_server` 會**直接 fail-closed**,拒絕啟動並回報明確錯誤。

也就是說,要在信任的 LAN 上跑「無 OAuth、無密碼」的 dashboard,必須**明確 opt-in**:

```yaml
environment:
  HERMES_DASHBOARD: "${HERMES_DASHBOARD:-1}"
  HERMES_DASHBOARD_INSECURE: "${HERMES_DASHBOARD_INSECURE:-true}"
```

本專案預設 `HERMES_DASHBOARD_INSECURE=true`,維持過去 `dashboard --insecure` 的行為（內網直接開,不擋認證）。

> [!WARNING]
> `HERMES_DASHBOARD_INSECURE=true` 等於把 dashboard 對 publish 出去的網段完全開放。
> 對外提供時,請設為 `false` 並改走 OAuth,或在 reverse proxy（Caddy / nginx）層加認證與 TLS,
> 不要讓 Hermes 自己裸奔在公網。

## 12. 相關文件

- [Docker Compose 快速部署](../../README.md)
- [安裝指南](setup.md)
- [Allowlist 設定指南](../guides/allowlist-config.md)
- [資料夾結構說明](../guides/data-volume.md)
