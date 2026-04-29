# Hermes CLI 使用手冊

Hermes Agent 提供豐富的 CLI 工具，用於管理 gateway、sessions、skills、cron job 等。本文件整理在 Docker 環境下的常用指令。

## 1. 核心概念

Hermes 同一個 image 提供兩種運作模式：

### hermes (gateway)

- **職責**：常駐執行的訊息平台閘道，監聽 `8642`，處理 Telegram/Discord/Slack 訊息。
- **啟動方式**：`docker compose up -d`（內部執行 `gateway run`）
- **狀態**：不可隨意中斷，否則服務中斷。

### hermes CLI

- **職責**：管理底層設定（authority、sessions、skills、cron）。
- **機制**：在已運行的 container 中透過 `docker exec` 執行，或啟動臨時容器。
- **狀態**：執行完即結束。

## 2. 在本專案執行 CLI

兩種方式：

### 方式 A：在運行中的 gateway 容器內執行（推薦）

```bash
docker exec -it hermes hermes <command>
```

### 方式 B：啟動臨時容器執行（gateway 未啟動時）

```bash
docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent <command>
```

## 3. 常見指令

### 🔑 Setup Wizard

```bash
# 初始化設定（首次使用）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup

# 重新設定特定模組
docker exec -it hermes hermes setup model
docker exec -it hermes hermes setup terminal
docker exec -it hermes hermes setup gateway

# 完整重置
docker exec -it hermes hermes setup --reset
```

### 📊 Dashboard

```bash
# Dashboard 是獨立 container（compose 中的 dashboard service）
# 因為宣告了 depends_on: hermes，未啟動時也會一起把 hermes 帶起來
docker compose up -d dashboard

# 查看 dashboard logs
docker compose logs -f dashboard
```

### 🔐 Pairing 配對管理

詳見 [Allowlist 設定指南](allowlist-config.md)。

```bash
# 列出已核准的配對
docker exec -it hermes hermes pairing list

# 核准配對 code（從 bot 訊息取得）
docker exec -it hermes hermes pairing approve telegram <code>

# 撤銷使用者
docker exec -it hermes hermes pairing revoke telegram <user-id>

# 清除等待中的配對請求
docker exec -it hermes hermes pairing clear-pending
```

### 💬 Session 管理

```bash
# 列出最近的 sessions
docker exec -it hermes hermes sessions list

# 互動瀏覽
docker exec -it hermes hermes sessions browse

# 匯出 session
docker exec -it hermes hermes sessions export ./session-backup.json --session-id <id>

# 刪除 session
docker exec -it hermes hermes sessions delete <id>

# 清理過期 session
docker exec -it hermes hermes sessions prune

# 查看統計資料
docker exec -it hermes hermes sessions stats
```

### ⏰ Cron Job 排程管理

```bash
# 列出所有排程
docker exec -it hermes hermes cron list

# 建立新 cron（互動式）
docker exec -it hermes hermes cron create

# 用 skill 建立
docker exec -it hermes hermes cron create --skill morning-summary

# 編輯
docker exec -it hermes hermes cron edit <job-id>

# 暫停 / 恢復
docker exec -it hermes hermes cron pause <job-id>
docker exec -it hermes hermes cron resume <job-id>

# 立即執行一次（不影響原排程）
docker exec -it hermes hermes cron run <job-id>

# 查看狀態
docker exec -it hermes hermes cron status

# 刪除
docker exec -it hermes hermes cron remove <job-id>
```

### 🧩 Skills 管理

```bash
# 瀏覽 / 搜尋 hub 上的 skills
docker exec -it hermes hermes skills browse
docker exec -it hermes hermes skills search <keyword>

# 安裝
docker exec -it hermes hermes skills install <skill-slug>

# 列出本地 skills
docker exec -it hermes hermes skills list

# 檢視 skill 細節
docker exec -it hermes hermes skills inspect <skill-slug>

# 安全性檢查
docker exec -it hermes hermes skills check <skill-slug>

# 更新所有 skill
docker exec -it hermes hermes skills update --all

# 發布自己的 skill
docker exec -it hermes hermes skills publish <skill-path>
```

### 🧠 Memory 管理

```bash
# 設定外部 memory provider（如 honcho、mem0）
docker exec -it hermes hermes memory setup

# 查看狀態
docker exec -it hermes hermes memory status

# 關閉
docker exec -it hermes hermes memory off
```

### 🔑 認證管理

```bash
# 列出設定的 provider
docker exec -it hermes hermes auth list

# 新增 API key
docker exec -it hermes hermes auth add openrouter --api-key sk-or-v1-xxx
docker exec -it hermes hermes auth add anthropic --api-key sk-ant-...

# 移除
docker exec -it hermes hermes auth remove openrouter
```

### 📋 Profile 管理

> ⚠️ 本專案目前還沒實際驗證過 Docker 環境下的多 profile 流程，下列指令僅列出 Hermes CLI 提供的 subcommand 供參考，實際行為（特別是 export / import 與容器隔離的相容性）請自行測試後再使用。

```bash
# 列出 profile
docker exec -it hermes hermes profile list

# 切換 profile
docker exec -it hermes hermes profile use work

# 建立新 profile（--clone 會複製 config / .env / SOUL.md）
docker exec -it hermes hermes profile create work --clone

# 匯出 / 匯入
docker exec -it hermes hermes profile export work ./work.tar.gz
docker exec -it hermes hermes profile import ./work.tar.gz
```

### 🔍 Insights 與 Logs

```bash
# 查看活動洞察（過去 N 天）
docker exec -it hermes hermes insights --days 7

# 查看特定來源
docker exec -it hermes hermes insights --source telegram

# Log 觀察
docker exec -it hermes hermes logs gateway -n 200
docker exec -it hermes hermes logs errors --since 1h
docker exec -it hermes hermes logs --session <id> -f
```

### 🪝 Webhook

```bash
# 訂閱 GitHub webhook 等
docker exec -it hermes hermes webhook subscribe <name> \
  --prompt "Summarize this PR" \
  --events issues,pull_request

# 列出
docker exec -it hermes hermes webhook list

# 移除
docker exec -it hermes hermes webhook remove <name>

# 測試
docker exec -it hermes hermes webhook test <name>
```

## 4. Tips

### 4.1 將 docker exec 包裝成 alias

在 host 的 shell 設定中加入：

```bash
# ~/.zshrc 或 ~/.bashrc
alias hcli='docker exec -it hermes hermes'
```

之後就可以：

```bash
hcli pairing list
hcli sessions list
hcli cron list
```

### 4.2 修改設定後別忘了重啟

修改 `~/.hermes/config.yaml` 或 `~/.hermes/.env` 後：

```bash
docker compose restart hermes
```

部分 skills 與 hooks 會 hot reload，但 platform token 與 allowlist 修改一律要重啟才會生效。

## 5. 相關參考

- [資料夾結構說明](data-volume.md)
- [Hermes CLI 官方文件](https://hermes-agent.nousresearch.com/docs/reference/cli-commands)
