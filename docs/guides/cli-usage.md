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
- **機制**：以 `docker run` 啟動臨時容器執行，掛載 `~/.hermes` 共用資料夾。
- **狀態**：執行完即結束。

## 2. 在本專案執行 CLI

CLI 以臨時容器執行，掛載 `~/.hermes` 資料夾即可操作與 gateway 共用的設定與資料。執行完即結束，不影響運行中的 gateway：

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
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup model
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup terminal
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup gateway

# 完整重置
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup --reset
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
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent pairing list

# 核准配對 code（從 bot 訊息取得）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent pairing approve telegram <code>

# 撤銷使用者
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent pairing revoke telegram <user-id>

# 清除等待中的配對請求
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent pairing clear-pending
```

### 💬 Session 管理

```bash
# 列出最近的 sessions
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions list

# 互動瀏覽
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions browse

# 匯出 session
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions export ./session-backup.json --session-id <id>

# 刪除 session
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions delete <id>

# 清理過期 session
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions prune

# 查看統計資料
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent sessions stats
```

### ⏰ Cron Job 排程管理

```bash
# 列出所有排程
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron list

# 建立新 cron（互動式）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron create

# 用 skill 建立
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron create --skill morning-summary

# 編輯
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron edit <job-id>

# 暫停 / 恢復
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron pause <job-id>
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron resume <job-id>

# 立即執行一次（不影響原排程）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron run <job-id>

# 查看狀態
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron status

# 刪除
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent cron remove <job-id>
```

### 🧩 Skills 管理

```bash
# 瀏覽 / 搜尋 hub 上的 skills
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills browse
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills search <keyword>

# 安裝
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills install <skill-slug>

# 列出本地 skills
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills list

# 檢視 skill 細節
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills inspect <skill-slug>

# 安全性檢查
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills check <skill-slug>

# 更新所有 skill
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills update --all

# 發布自己的 skill
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills publish <skill-path>
```

### 🧠 Memory 管理

```bash
# 設定外部 memory provider（如 honcho、mem0）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent memory setup

# 查看狀態
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent memory status

# 關閉
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent memory off
```

### 🔑 認證管理

```bash
# 列出設定的 provider
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent auth list

# 新增 API key
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent auth add openrouter --api-key sk-or-v1-xxx
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent auth add anthropic --api-key sk-ant-...

# 移除
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent auth remove openrouter
```

### 📋 Profile 管理

> [!IMPORTANT]
> Hermes profile CLI 可在容器內正常使用（list / use / create / export / import 都 OK）。但**官方明文不建議在 Docker 內用 `hermes -p <名稱> gateway run` 跑多個長駐 gateway**（[Hermes Docker — Multi-profile support](https://hermes-agent.nousresearch.com/docs/user-guide/docker#multi-profile-support)：「using Hermes' built-in multi-profile feature is not recommended」）。要 24/7 多 agent 並行，請改用[一個 container 一個獨立 host 資料夾](multi-agent.md#33-推薦架構一個-container-一個-profile各自-bind-mount-獨立-host-資料夾)的模式。
>
> 在 Docker 內 `hermes -p ... chat -q "..."` 這類**短暫**呼叫（subagent 用法）仍然可用，因為 gateway 全程只有主帳號這一個。

```bash
# 列出 profile
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile list

# 切換 profile（影響後續 plain `hermes` 指令的預設 profile）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile use work

# 建立新 profile（--clone 會複製 config / .env / SOUL.md）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile create work --clone

# 匯出 / 匯入
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile export work ./work.tar.gz
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile import ./work.tar.gz

# 對特定 profile 下單次任務（subagent 模式，不啟動長駐 gateway）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent -p work chat -q "幫我跑 X 任務"
```

### 🔍 Insights 與 Logs

```bash
# 查看活動洞察（過去 N 天）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent insights --days 7

# 查看特定來源
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent insights --source telegram

# Log 觀察
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent logs gateway -n 200
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent logs errors --since 1h
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent logs --session <id> -f
```

### 🪝 Webhook

```bash
# 訂閱 GitHub webhook 等
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent webhook subscribe <name> \
  --prompt "Summarize this PR" \
  --events issues,pull_request

# 列出
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent webhook list

# 移除
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent webhook remove <name>

# 測試
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent webhook test <name>
```

## 4. Tips

### 4.1 將 CLI 指令包裝成 alias

在 host 的 shell 設定中加入：

```bash
# ~/.zshrc 或 ~/.bashrc
alias hcli='docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent'
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
