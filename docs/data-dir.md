# Data Dir

一個 home 的所有狀態都在 host 上的一個資料夾，掛到容器的 `/opt/data`。主 home 是 `~/.hermes`，`./hermes-run.sh new <名稱>` 建的是 `~/.hermes-<名稱>`（見 [Agent、Home 與 Profile](agents-and-profiles.md)）。

一個 data dir 只能給一個容器掛。官方 [Docker 文件](https://hermes-agent.nousresearch.com/docs/user-guide/docker)警告兩個 gateway 容器同時用同一個 data dir 會損壞 session 與記憶。

## 結構

只列需要知道的項目，lock 檔、快取等 Hermes 自己管的省略。

```text
<data dir>/                  → 容器的 /opt/data
├── .env                     # default profile 的 API key、bot token、API_SERVER_KEY
├── config.yaml              # default profile 的設定
├── SOUL.md                  # default profile 的身份與人設
├── auth.json                # OAuth 登入（例如 openai-codex），所有 profile 共用
├── state.db                 # session 與訊息（SQLite）
├── sessions/
├── memories/                # MEMORY.md、USER.md，agent 第一次寫記憶時才建立
├── platforms/pairing/       # 私訊配對的 code 與已核准的使用者
├── skills/                  # 內建 skills（每次啟動同步）與自己裝、agent 自建的
├── cron/                    # jobs.json 與每次執行的 output/
├── logs/                    # gateway.log、agent.log、errors.log…
├── home/                    # 工具子程序（git、ssh、gh）用的 HOME
├── kanban.db                # Kanban 任務板，所有 profile 共用
├── scripts/                 # hermes-run.sh 同步進來的腳本，也放 agent 自己寫的
│   ├── cdp_proxy.py
│   ├── cron_run_stats.py
│   └── host/browsers.conf
├── shared/                  # 自己的 script 用的共用目錄，不是 Hermes 內建
└── profiles/<名稱>/         # 其他 profile
```

### 設定檔

- **`.env`**：機密值放這裡，權限維持 `600`。`config.yaml` 不放 key。
- **`config.yaml`**：一般設定。可以直接編輯，或用 `./hermes-run.sh cli config set <key> <value>`；改完執行 `./hermes-run.sh cli gateway restart` 套用。model 的寫法見[模型設定](models.md)。
- **`SOUL.md`**：身份與人設。缺少時容器啟動會放官方預設。

容器第一次啟動時，entrypoint 會補上缺少的 `.env`、`config.yaml`、`SOUL.md`。

### 狀態

- **`state.db`**：對話紀錄存在這個 SQLite 資料庫，不要直接改，用 `./hermes-run.sh cli sessions …` 操作（`list`、`browse`、`prune`…）。
- **`memories/`**：`MEMORY.md` 是 agent 自己的筆記，`USER.md` 是它記下的使用者資訊，開新 session 時載入 system prompt。字數上限是 `config.yaml` 的 `memory.memory_char_limit`（預設 `2200`）與 `memory.user_char_limit`（預設 `1375`）。可以手動編輯，但條目之間要用單獨一行的 `§` 分隔；格式不符時 agent 下次寫入會拒絕，並先存一份快照。
- **`platforms/pairing/`**：沒設 allowlist 時，陌生人私訊 bot 拿到的 pairing code 與已核准的使用者，存成權限 `600` 的 JSON。用 `./hermes-run.sh cli pairing …` 管理，不要手改。舊的 `pairing/` 裡有資料時，Hermes 沿用舊目錄。
- **`skills/`**：同名 skill 以這裡的版本為準。
- **`cron/`**：排程由 gateway 執行，用 `./hermes-run.sh cli cron …` 管理。

### `scripts/`

`./hermes-run.sh up` 與 `new` 每次都用 `rsync` 把 repo 的 `scripts/` 同步進來（排除 `__pycache__`，不刪除多出來的檔案），並把 repo 的 `config/browsers.conf` 放到 `scripts/host/browsers.conf`：

- `cdp_proxy.py`：容器啟動時跑起來，把 CDP 連線轉到 host 上的 Chrome，見[瀏覽器](browser.md)。
- `cron_run_stats.py`：依 cron 執行的 log 和 `state.db`，產生單次執行的遙測通知。

agent 自己寫的腳本會留著，但和 repo 同名的檔案會被覆蓋，要改這些請改 repo 裡的。

### `shared/`

同一個 home 的 profile 交換檔案用，目錄由使用的 script 自己建立：

- `shared/reports/`：[`dispatch-agent`](../skills/dispatch-agent/SKILL.md) 讓分身把報告寫在這裡，再由主 agent 代發。
- `shared/locks/`：cron script 用 `flock` 鎖住同一個 Chrome，避免兩個任務同時操作。

## Profile 目錄

`profiles/<名稱>/` 是一份獨立的 home，有自己的：

- `.env`、`config.yaml`、`SOUL.md`
- `state.db`、`sessions/`、`memories/`
- `skills/`、`cron/`、`logs/`、`home/`

profile 目錄裡沒有 `auth.json` 與 `kanban.db`：OAuth 登入與 Kanban 任務板用 home 根目錄那一份。`scripts/` 與 `shared/` 也只有根目錄一份，所有 profile 共用。

## 備份

先停容器再打包，避免打包到寫到一半的 SQLite：

```bash
./hermes-run.sh down
tar czf hermes-backup-$(date +%Y%m%d).tar.gz -C ~ .hermes
./hermes-run.sh up
```

其他 home 加 `-a <名稱>`，打包 `.hermes-<名稱>`。備份檔含 `.env` 與 `auth.json`，要當機密保管。

## 安全建議

Data dir 裡含機密的檔案：

- `.env`、`profiles/<名稱>/.env`：API key、bot token
- `auth.json`：OAuth 登入憑證
- `state.db`：所有對話內容
- 備份檔：含上面全部

`stage2-hook.sh` 每次容器啟動都會把根目錄的 `.env` 設成 `600`。其他的自己收緊：

```bash
chmod 700 ~/.hermes
chmod 600 ~/.hermes/auth.json
chmod 600 ~/.hermes/profiles/<名稱>/.env   # 每個 profile 各一次
```

Linux 上先照 [容器內 Permission denied](#容器內-permission-denied) 設好 `HERMES_UID`，否則 `700` 會讓容器讀不到。不要把 data dir 或備份檔放進 git 或共用雲端資料夾。

## 容器內 Permission denied

容器裡的程式以 `hermes` 使用者執行，image 裡它的 UID/GID 是 `10000`。Linux 上 data dir 通常屬於自己（例如 `1000`），兩者不同時容器寫不進 data dir。macOS 的 Docker Desktop 會隱藏擁有者的差異，一般不用處理。

### 診斷

```bash
ls -lnd ~/.hermes            # data dir 擁有者的 UID/GID
docker exec hermes id hermes # 容器裡 hermes 的 UID/GID
```

其他 home 的容器名稱看 `./hermes-run.sh ls` 的 `CONTAINER` 欄。兩組數字不同就是這個原因。

### 修正

1. 複製平台設定範本：

    ```bash
    cp config/platforms/linux.env.example config/platforms/linux.env
    ```

2. 把 `HERMES_UID`、`HERMES_GID` 改成 `id -u`、`id -g` 的結果。

3. 重新啟動容器。Compose 變數只有 `up` 會套用：

    ```bash
    ./hermes-run.sh up
    ```

`docker-compose.yml` 把這兩個值傳進容器。容器啟動時，image 的 `/opt/hermes/docker/stage2-hook.sh` 會：

- 用 `usermod`、`groupmod` 把 `hermes` 改成這組 UID/GID
- data dir 根目錄的擁有者不是 `hermes` 時，只 chown 根目錄本身，再把 Hermes 自己的子目錄（`sessions/`、`logs/`、`skills/`、`cron/`、`profiles/` 等）chown 給 `hermes`；其他檔案不動

不要用 `docker run --user` 指定 UID：這個 image 會拒絕啟動，要用 `HERMES_UID`、`HERMES_GID`。

設好之後還有寫不進去的檔案，通常是在 host 上用 `sudo` 建的。找出來再改回自己：

```bash
find ~/.hermes ! -user "$(id -u)"
sudo chown -R "$(id -u):$(id -g)" ~/.hermes
```

這一步只在 `HERMES_UID` 等於 `id -u` 時才對。不要 `chmod -R 755`，會讓 `.env` 這類機密檔變成其他人可讀。

## 磁碟用量過大

先看哪個目錄大：

```bash
du -sh ~/.hermes/* | sort -h
./hermes-run.sh cli sessions stats
./hermes-run.sh cli checkpoints status
```

### 對話紀錄

`state.db` 會隨對話一直長大，用 `sessions prune` 刪舊的。先 `--dry-run` 看會刪哪些，要留的先匯出：

```bash
./hermes-run.sh cli sessions prune --older-than 90 --dry-run
./hermes-run.sh cli sessions export /opt/data/sessions-old.jsonl --older-than 90
./hermes-run.sh cli sessions prune --older-than 90
```

`--older-than` 可以寫天數或 `5h`、`2d`、`1w`。釘選（`sessions pin`）與封存的 session 預設不刪。

### Checkpoints

Hermes 在改檔案前會把工作目錄快照到 `checkpoints/`，給 `/rollback` 用：

```bash
./hermes-run.sh cli checkpoints prune    # 刪掉孤兒與過期的快照
./hermes-run.sh cli checkpoints clear    # 全部刪掉，之後無法 /rollback
```

### 會自動控制大小的

- **`logs/`**：自動輪替。`agent.log` 預設每個 5 MB、留 3 份，由 `config.yaml` 的 `logging.max_size_mb`、`logging.backup_count` 調整；`errors.log`、`gateway.log` 也有固定上限。不用手動刪。
- **`cron/output/`**：每個 job 只留最近 50 次的輸出，由 `config.yaml` 的 `cron.output_retention` 調整。

`hermes backup` 產生的 `hermes-backup-*.zip` 不會自動清，搬走或刪掉。
