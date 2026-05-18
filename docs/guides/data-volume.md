# `~/.hermes` 資料夾結構說明

Hermes 將所有狀態存在 host 上的 `~/.hermes/` 並掛載到容器內 `/opt/data`。本文件說明各檔案職責、備份策略與多 profile 切換時的注意事項。

## 1. 整體結構

```text
~/.hermes/                    → /opt/data （容器內）
├── .env                      # API keys 與平台 token（setup wizard 寫入）
├── config.yaml               # Agent 主要設定
├── auth.json                 # OAuth 憑證（Nous Portal、Anthropic 等）
├── SOUL.md                   # Agent 主要身份（system prompt slot #1）
├── state.db                  # SQLite 主資料庫（sessions、messages、FTS5）
├── memories/
│   ├── MEMORY.md             # Agent 記憶（≤ 2,200 字元）
│   └── USER.md               # 使用者 profile（≤ 1,375 字元）
├── skills/                   # 依類別組織（research/、productivity/ ...）
├── cron/
│   ├── jobs.json             # Cron job 定義
│   └── output/               # 各 job 執行輸出（{job_id}/{timestamp}.md）
├── pairing/                  # 配對核准與待處理資料（per-platform JSON）
├── hooks/                    # 事件 hook 腳本
└── logs/
    ├── gateway.log
    ├── agent.log
    └── errors.log
```

## 2. 重要檔案詳解

### 2.1 `.env`

API keys 的主要來源。由 `hermes setup` wizard 寫入，內容範例：

```ini
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_ALLOWED_USERS=123456789
```

> **權限**：應為 `chmod 600 ~/.hermes/.env`，避免他人讀取。

### 2.2 `config.yaml`

Agent 的主要設定（可參考本專案的 [`config.example.yaml`](../../config.example.yaml)），包含：

- 模型路由規則（如 Fallback Model 備用模型、Smart Model Routing 智慧路由）
- 平台設定（Telegram require_mention、Discord auto-thread 等）
- 工具啟用 / 停用（例如 Bedrock、MCP 等）
- 系統 prompt 與 personality

修改後需重啟 gateway：

```bash
docker compose restart hermes
```

### 2.3 `state.db`

SQLite 資料庫（位於 `~/.hermes/` 頂層，預設啟用 WAL mode），包含：

- `sessions` table — session metadata、token / billing 等
- `messages` table — 完整對話歷史
- `messages_fts` virtual table — FTS5 全文索引（讓 agent 可搜尋過往對話）
- `schema_version` table — migration 狀態

Gateway、CLI session、worktree agent 共用同一個 DB，由 SessionDB 處理寫入競爭（短 timeout + 隨機 retry + WAL checkpoint）。

**不要直接編輯**，使用 CLI 操作：

```bash
hermes sessions list
hermes sessions browse
```

### 2.4 `SOUL.md`

Agent 主要身份，會被注入 system prompt 第一個 slot。`hermes profile create --clone` 會連同 `config.yaml` 與 `.env` 一起複製這個檔案。

### 2.5 `memories/MEMORY.md`

Agent 的「個人筆記」，每次 session 啟動時會被 frozen 注入 system prompt（保留 prefix cache）。

- **由 agent 自己維護**（透過 memory tool）
- **大小限制**：2,200 字元
- 內容範例：環境細節、專案慣例、過去的解法

### 2.6 `memories/USER.md`

使用者 profile：

- 偏好的溝通風格
- 時區
- 技術專長
- **大小限制**：1,375 字元

### 2.7 `skills/`

容器啟動時會把 image 內 bundled 的 skills 同步到 `~/.hermes/skills/`，依類別（如 `research/`、`productivity/`）組織。Hub 安裝、agent 自建的 skills 也會落到同一個目錄；外部目錄則是僅供探索。

> 同名 skill 以 `~/.hermes/skills/` 內的版本優先。

### 2.8 `pairing/`

存放各平台的配對狀態，採 per-platform JSON 檔（如 `telegram-pending.json`）。**不要手動編輯**，請透過 CLI 管理：

```bash
hermes pairing list
hermes pairing approve telegram <code>
hermes pairing revoke telegram <user-id>
```

## 3. 備份策略

### 3.1 完整備份

```bash
# 停 service 後 tar 整個資料夾
docker compose down
tar czf hermes-backup-$(date +%Y%m%d).tar.gz -C ~ .hermes
docker compose up -d
```

### 3.2 最小備份（僅關鍵檔案）

如果你只想保留必要的設定與記憶：

```bash
tar czf hermes-config-$(date +%Y%m%d).tar.gz \
  -C ~/.hermes \
  .env config.yaml auth.json SOUL.md memories/ pairing/ cron/ skills/
```

### 3.3 自動備份 cron

可在 host 上設定排程：

```cron
# 每天 03:00 備份
0 3 * * * tar czf ~/backups/hermes-$(date +\%Y\%m\%d).tar.gz -C ~ .hermes
```

## 4. 多 profile 切換

要在本專案部署多個長駐 agent，**每個 agent 都應該有自己獨立的 host 資料夾**（例如 `~/.hermes-work`、`~/.hermes-personal`），不要共掛同一個 `${HERMES_DATA_DIR}`。本專案 `docker-compose.yml` 預留的 `HERMES_DATA_DIR`、`HERMES_CONTAINER_NAME`、`HERMES_GATEWAY_PORT`、`HERMES_DASHBOARD_PORT` 都可以透過 env 覆寫，方便每個 service 各自指向不同 host 路徑。

要點：

- 不同 agent 用不同的 `HERMES_DATA_DIR`
- 不同 agent 用不同的 `HERMES_GATEWAY_PORT` / `HERMES_DASHBOARD_PORT`
- container_name 不能撞名

為什麼官方禁止「共用 volume + 多 gateway」、為什麼推薦「一個 container 一個 host dir」，以及完整 SOP，集中於 [Multi-Agent — Docker Compose 多容器部署](multi-agent.md#3-docker-compose-多容器部署)。

## 5. 安全建議

```bash
# 整個資料夾只允許 owner 讀寫
chmod 700 ~/.hermes
chmod 600 ~/.hermes/.env
chmod 600 ~/.hermes/auth.json 2>/dev/null || true

# 確認 pairing 檔案權限
ls -la ~/.hermes/pairing/
```

## 6. 常見問題

### 6.1 容器內 Permission denied

如果容器內寫入失敗，通常是 host 上的目錄擁有者與容器內 user 不一致：

```bash
# 查看容器內 user
docker exec hermes id

# 修正 host 權限
chmod -R 755 ~/.hermes
chown -R $USER:$USER ~/.hermes
```

### 6.2 資料夾被鎖

切勿同時跑兩個 gateway 共用同一資料夾，SQLite 會 lock，session 寫入失敗。`hermes -p <名稱> gateway run` 切換 profile 子目錄**也不能繞過**這條規則。

多 agent 並行的正確做法（每個 agent 各自一個 host 資料夾）見 [本檔多 profile 切換](#4-多-profile-切換) 與 [Multi-Agent — Docker Compose 多容器部署](multi-agent.md#3-docker-compose-多容器部署)。

### 6.3 磁碟用量過大

```bash
# 查看各子目錄大小
du -sh ~/.hermes/*

# 清理舊 sessions
hermes sessions prune

# 清理舊 log
find ~/.hermes/logs -name "*.log" -mtime +30 -delete
```

## 7. 相關參考

- [Setup Deep Dive](../deployment/setup-deep-dive.md)
- [CLI 使用手冊](cli-usage.md)
