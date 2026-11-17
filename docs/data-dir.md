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
├── memories/                # agent 第一次寫記憶時才建立
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
- **`skills/`**：同名 skill 以這裡的版本為準。
- **`cron/`**：排程由 gateway 執行，用 `./hermes-run.sh cli cron …` 管理。

### `scripts/`

`./hermes-run.sh up` 與 `new` 每次都用 `rsync` 把 repo 的 `scripts/` 同步進來（排除 `__pycache__`，不刪除多出來的檔案），並把 repo 根目錄的 `browsers.conf` 放到 `scripts/host/browsers.conf`：

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
