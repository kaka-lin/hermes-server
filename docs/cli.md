# CLI 指令

日常操作都透過 `./hermes-run.sh`：前半管容器，`cli` 子指令在容器裡執行 `hermes`。完整的 `hermes` 指令與參數以[官方 CLI Reference][cli-ref] 為準，這裡列常用的。

## hermes-run.sh

| 指令 | 作用 |
| --- | --- |
| `up [-a <名稱> \| --all]` | 同步 `scripts/`、`config/browsers.conf` 到 data dir，再啟動容器 |
| `down [-a <名稱> \| --all]` | 停止並移除容器，data dir 不受影響 |
| `restart [-a <名稱> \| --all]` | 重啟容器裡的程式，不重建容器 |
| `logs [-a <名稱>]` | 跟著看容器 log（最後 100 行起） |
| `status [-a <名稱>]` | 容器狀態（`docker compose ps`），也可以寫成 `ps` |
| `cli [-a <名稱>] <args…>` | 在容器裡以 `hermes` 使用者執行 `hermes <args…>` |
| `new <名稱> [--force]` | 建立新 home，見[建一個新 home](agents-and-profiles.md#建一個新-home) |
| `ls` | 列出所有 home |

不加選項時操作主 home。`-a <名稱>`（或 `--agent <名稱>`）操作 `config/agents/<名稱>.conf` 的 home，要緊接在子指令後面，例如 `./hermes-run.sh cli -a work doctor`；`--all` 是主 home 加所有其他 home，只能用在 `up`、`down`、`restart`。

### up

以 `--no-build --pull never` 啟動，image 不存在時直接報錯，先用 `./hermes-build.sh` 建好。啟動前把 repo 的 `scripts/` 同步進 data dir（不刪除 data dir 裡多出來的檔案），並把 `config/browsers.conf` 放到 `scripts/host/browsers.conf`。

Compose 變數（port、data dir、image 版本）只有 `up` 會套用，`restart` 不會。

### ls

每個 home 一行，欄位依序是：

- `HOME`：home 名稱，主 home 顯示 `hermes`
- `CONTAINER`：容器名稱
- `STATUS`：`docker ps` 的狀態，沒有容器時是 `(none)`
- `GATEWAY`、`DASH`、`WEBHOOK`：host 上的 port
- `PROFILES`：data dir 的 `profiles/` 底下有哪些 profile

### cli

```bash
./hermes-run.sh cli [-a <home>] [-p <profile>] <子指令>
```

- 以 `hermes` 使用者執行，寫進 data dir 的檔案才不會變成 root 擁有。
- 在終端機執行時自動加 `-it`，`setup`、`model`、OAuth 登入這類互動指令才能用。
- `cli profile create <名稱>` 成功後會印出下一步。
- 容器裡的工作目錄是 `/opt/hermes`。檔案路徑一律寫 `/opt/data/...`（對應 host 的 data dir），寫相對路徑會落在容器內部，容器重建就不見。

常用的話可以設 alias：

```bash
# ~/.zshrc
alias hcli='/path/to/hermes-server/hermes-run.sh cli'
```

### 查版本

```bash
# 容器在跑時；其他 home 加 -a <名稱>
./hermes-run.sh cli --version

# 容器沒跑時：直接用 image，--entrypoint 跳過啟動流程
docker run --rm --entrypoint hermes kakalin/hermes-agent:v0.23.1 --version
```

第一行是 Hermes 版本與上游 commit，例如 `Hermes Agent v0.23.1 (2026.9.24) · upstream 3b421578`。image 名稱與 tag 依 `config/compose.env` 的 `HERMES_IMAGE`、`HERMES_VERSION`。

## 常用 hermes 指令

以下都省略前面的 `./hermes-run.sh cli`，例如 `doctor` 代表 `./hermes-run.sh cli doctor`。

### 指定 profile

全域選項 `-p <profile>` 放在子指令前面，只影響這一次執行：

```bash
./hermes-run.sh cli -p work cron list
```

不加 `-p` 時操作預設 profile。沒用 `profile use` 改過的話就是 `default`，也就是 data dir 本身。

### doctor 與 status

```bash
doctor            # 檢查設定、套件、服務、API 連線、工具
status            # 各元件狀態摘要
status --full     # 列出所有段落（金鑰會遮蔽）
--version         # Hermes 版本
```

### logs

`hermes logs` 讀 data dir 裡 Hermes 自己的 log 檔，和看容器輸出的 `./hermes-run.sh logs` 不同：

```bash
logs                     # agent.log 最後 50 行
logs gateway -n 200
logs errors --since 1h
logs -f --level WARNING
logs list                # 列出有哪些 log 檔
```

### gateway

```bash
gateway restart
gateway restart -y     # 有進行中的對話或 cron 時，不詢問直接中斷
```

一個 home 的所有 profile 由同一個 gateway 帶起，重啟會中斷它們進行中的對話與 cron。有進行中的工作時會列出來並問 y/N；沒有終端機（例如從腳本呼叫）時要加 `-y`。

新增 profile，或改了任何 profile 的 `.env`、`config.yaml`，都用它套用。dashboard 是另一個程式，不會跟著重啟，改了 `.env` 裡的 dashboard 帳密要用 `./hermes-run.sh restart`。不要自己再執行 `gateway run`：同一份 data dir 只能有一個 gateway。

### profile

```bash
profile list                       # 列出 profile、模型、gateway 狀態
profile create <名稱>              # 建立新的 profile
profile create <名稱> --clone      # 從目前 profile 複製設定與 skills（不含 bot token 與 allowlist）
profile show <名稱>
profile delete <名稱>
profile export <名稱>
profile import <封存檔路徑>
```

完整流程見 [Agent、Home 與 Profile](agents-and-profiles.md)。

### auth

管理 provider 的憑證池：

```bash
auth list
auth add openai-codex --browser        # OpenAI Codex 用瀏覽器登入
auth add openrouter --api-key <key>
auth remove <provider> <編號、id 或 label>
auth status <provider>
```

模型與 provider 的設定見[模型設定](models.md)。

### pairing

```bash
pairing list                         # 等待中與已核准的使用者
pairing approve <platform> <code>    # code 是 bot 私訊給使用者的配對碼
pairing revoke <platform> <user-id>
pairing clear-pending
```

### sessions

對話紀錄存在 data dir 的 `state.db`，用這組指令操作，不要直接改資料庫：

```bash
sessions list                                    # 最近的 session
sessions list --source discord --limit 20
sessions browse                                  # 互動式瀏覽、搜尋並接續 session
sessions stats                                   # session store 統計
sessions rename <session-id> <標題>
sessions export /opt/data/sessions.jsonl         # 匯出全部，預設 JSONL
sessions export /opt/data/exports/ --format md --session-id <session-id>
sessions delete <session-id>
sessions prune --older-than 30 --dry-run         # 先看會刪哪些
sessions prune --older-than 30
```

- `export` 的路徑要寫 `/opt/data/...`，檔案才會落在 host 的 data dir。加 `--redact` 遮蔽內容裡的 API key 與 token。
- `prune` 不加條件時刪 90 天前的 session；釘選（`sessions pin`）與封存的預設不刪。清理磁碟見 [磁碟用量過大](data-dir.md#磁碟用量過大)。

### memory

內建記憶（`memories/` 的 `MEMORY.md`、`USER.md`）一直開著。這組指令管外部 memory provider，同時只能開一個：

```bash
memory status                        # 目前的 provider 設定
memory setup                         # 互動式選 provider 並設定
memory off                           # 關掉外部 provider，只用內建記憶
memory reset --target memory         # 清空 MEMORY.md；user 清 USER.md，不加是兩個都清
```

image 內建 `retaindb`、`byterover`；`honcho`、`mem0` 等其他 provider 先用 `plugins install <名稱>` 安裝。

### skills

```bash
skills list                          # 已安裝的 skill
skills list --source hub             # 只列從 hub 裝的；另有 builtin、local
skills browse                        # 分頁瀏覽 registry
skills search <關鍵字>
skills inspect <identifier>          # 安裝前預覽
skills install <identifier>          # 例如 openai/skills/skill-creator，或 SKILL.md 的網址
skills check                         # 檢查 hub skill 有沒有新版
skills update                        # 更新過期的 hub skill，自己改過的會跳過
skills audit                         # 重新掃描已安裝的 hub skill
skills uninstall <名稱>
skills config                        # 互動式啟用、停用個別 skill
```

skill 裝在 profile 的 `skills/`，對其他 profile 加 `-p <名稱>`。`skills list --enabled-only -p <名稱>` 列出那個 profile 實際會載入的 skill。

### cron

```bash
cron list
cron create "0 9 * * *" "整理今天的待辦" --name daily-todo
cron create "every 2h" --skill <skill 名稱> --name <名稱>
cron edit <job-id> --schedule "0 10 * * *"
cron pause <job-id>
cron resume <job-id>
cron run <job-id>              # 在下一個 scheduler tick 執行一次
cron runs [<job-id>]           # 執行紀錄
cron remove <job-id>
cron status                    # scheduler 有沒有在跑
cron doctor                    # 檢查排程的常見問題
```

排程可以寫：

- `30m`
- `every 2h`
- cron 語法

`--deliver` 指定結果送去哪裡（例如 `discord`、`platform:chat_id`），其餘選項看 `cron create --help`。

### send

不經過 LLM，直接用已設定好的平台憑證送訊息，適合腳本與通知：

```bash
send --list                                 # 列出可用的目標
send --to discord "deploy finished"         # 送到該平台的 home channel
send --to discord:#ops --file /opt/data/report.md
```

`--to` 的格式有：

- `platform`
- `platform:chat_id`
- `platform:#channel-name`

### webhook

讓外部服務（例如 GitHub）用 HTTP POST 觸發 agent。要先在 `.env` 加 `WEBHOOK_ENABLED=true` 並執行 `gateway restart`，沒開時指令只會印設定說明。

```bash
webhook subscribe github-pr \
  --events pull_request \
  --prompt "整理這個 PR：{pull_request.title}" \
  --deliver discord
webhook list
webhook test github-pr               # 送一個測試 POST
webhook remove github-pr
```

- 每個 subscription 的網址是 `/webhooks/<名稱>`，`--prompt` 用 `{欄位.子欄位}` 取 payload 的值。
- 沒給 `--secret` 時自動產生 HMAC secret，填到外部服務的 webhook 設定。
- `--deliver-only` 不經過 LLM，直接把套好 payload 的 prompt 當訊息送出，`--deliver` 要指定實際的平台。
- webhook 聽容器的 `8644`，對外開在 host 的 `HERMES_WEBHOOK_PORT`（主 home 預設 `8644`，其他 home 由 `new` 自動挑）。外部服務還要能連到這台 host，例如透過 tunnel 或公開網址。
- 一個 home 只對外開一個 webhook port，給 default profile 用。其他 profile 預設也聽 `8644`，會和 default profile 衝突，要在該 profile 的 `.env` 設 `WEBHOOK_PORT` 換 port，而且那個 port 不會對外開。

### insights

依對話紀錄統計 token 用量、費用、工具使用與活動趨勢：

```bash
insights                             # 過去 30 天
insights --days 7
insights --source discord            # 只看某個平台
```

### 其他

| 指令 | 用途 |
| --- | --- |
| `setup`、`setup model` | 互動式設定精靈，或只跑某一段 |
| `config show`、`config get <key>`、`config set <key> <value>` | 檢視與修改 `config.yaml` |
| `backup` | 把整個 home 備份成 zip，預設寫到 `/opt/data/hermes-backup-<timestamp>.zip` |

[cli-ref]: https://hermes-agent.nousresearch.com/docs/reference/cli-commands
