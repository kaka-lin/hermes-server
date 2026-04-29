# Docker Compose 設計細節 (Setup Deep Dive)

本文件詳細解析本專案 `docker-compose.yml` 的設計選擇與運作原理。

## 1. 整體架構

```text
┌──────────────────────────────────────────────────┐
│                 Docker Compose                    │
│                                                   │
│  ┌─────────────┐         ┌──────────────────┐   │
│  │   hermes    │◄────────┤ hermes-dashboard │   │
│  │  (gateway)  │  健康   │  (web UI 9119)    │   │
│  │             │  檢查   └──────────────────┘   │
│  │  port 8642  │                                  │
│  └──────┬──────┘                                  │
│         │                                         │
│         ▼                                         │
│  ┌─────────────────┐                             │
│  │  ~/.hermes/     │ ← 兩個容器共用              │
│  │  (host volume)  │                              │
│  └─────────────────┘                              │
└──────────────────────────────────────────────────┘
```

兩個服務都來自同一個 image (`nousresearch/hermes-agent`)，但執行不同的 subcommand：

- **hermes**：`gateway run`（持續運行的訊息處理服務）
- **hermes-dashboard**：`dashboard --host 0.0.0.0 --insecure`（Web UI）

## 2. 共用設定（YAML Anchor）

```yaml
volumes:
  &hermes-volumes
  - ${HERMES_DATA_DIR:-${HOME}/.hermes}:/opt/data
```

使用 YAML anchor (`&hermes-volumes`) 避免兩個 service 重複定義 volume。修改一處即可同步兩端。

> ⚠️ **重要**：兩個容器共用同一個資料夾。Hermes 的 session 與 memory store **不支援並行寫入**，因此切勿同時跑兩個 gateway 共用同一資料夾。
>
> 多 instance 部署可參考 [`~/.hermes` 資料夾結構說明 §4](../guides/data-volume.md#4-多-profile-切換)（注意：尚未實際驗證）。

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

```text
~/.hermes/                    → /opt/data （容器內）
├── .env                      # API keys（setup wizard 寫入）
├── config.yaml               # Agent 設定
├── sessions/                 # SQLite + FTS5 session DB
├── memories/
│   ├── MEMORY.md             # Agent 記憶
│   └── USER.md               # 使用者 profile
├── skills/                   # 已安裝的 skills（含 bundled）
├── logs/                     # 執行紀錄
├── hooks/                    # 事件 hook 腳本
├── cron/                     # Cron job 定義（JSON）
└── pairing/                  # 配對核准資料（chmod 0600）
```

詳細說明請參閱 [資料夾結構說明](../guides/data-volume.md)。

## 6. 資源限制設計

```yaml
deploy:
  resources:
    limits:
      memory: ${HERMES_MEMORY_LIMIT:-4G}
      cpus: "${HERMES_CPU_LIMIT:-2.0}"
```

預設值適合大部分場景：

- **Gateway 4G / 2 CPU**：足以執行 browser automation 與多平台訊息處理。
- **Dashboard 512M / 0.5 CPU**：純 Web UI，輕量。

不使用 browser tools 時可調降至 `1G`：

```ini
# .env
HERMES_MEMORY_LIMIT=1G
HERMES_SHM_SIZE=64m
```

## 7. `shm_size: 1g` 為何是必要的

```yaml
shm_size: "${HERMES_SHM_SIZE:-1g}"
```

Playwright/Chromium 需要 `/dev/shm` 提供共享記憶體。Docker 預設只給 64 MB，不足會造成：

- 瀏覽器啟動失敗
- Page crash with `Target closed`
- 記憶體相關 segfault

預設設為 `1g` 確保 browser tools 可用；不需要瀏覽器自動化時可降為 `64m`。

## 8. 健康檢查機制

```yaml
dashboard:
  environment:
    GATEWAY_HEALTH_URL: ${GATEWAY_HEALTH_URL:-http://hermes:8642}
    GATEWAY_HEALTH_TIMEOUT: ${GATEWAY_HEALTH_TIMEOUT:-3}
  depends_on:
    - hermes
```

Dashboard 透過 `hermes-net` bridge network 用容器名稱解析 gateway。

- **同機部署**：用預設 `http://hermes:8642`（Docker DNS 自動解析）。
- **跨主機部署**：改為 `http://<gateway-host>:<gateway-port>`。

`depends_on` 確保啟動順序，但不等待 gateway 完全 ready；dashboard 自己會輪詢健康檢查 URL。

## 9. Network 隔離

```yaml
networks:
  hermes-net:
    driver: bridge
```

獨立的 bridge network 讓兩個容器互通，但與其他 Docker compose 專案隔離。對外只透過 `ports:` 顯式 publish 必要的 port。

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

## 11. 為何拿掉 `--insecure`

早期版本 dashboard 可能有 `--insecure` flag 用於跳過 TLS 驗證。當前官方版本 dashboard 預設行為已穩定，不需要此 flag。本專案 `docker-compose.yml` 已移除。

如果你需要對外提供 HTTPS dashboard，建議在 reverse proxy 層處理 TLS，而不是讓 Hermes 自簽。

## 12. 相關文件

- [Docker Compose 快速部署](../../README.md)
- [安裝指南](setup.md)
- [Allowlist 設定指南](../guides/allowlist-config.md)
- [資料夾結構說明](../guides/data-volume.md)
