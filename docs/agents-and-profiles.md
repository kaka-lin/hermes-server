# Agent、Home 與 Profile

要跑多個各自獨立的 agent，有兩種隔離方式，可以疊著用：

- **一個 home 多個 profile**：在同一個容器裡用 `hermes profile create` 建，由同一個 gateway 一起帶起來。
- **多個 home**：每個 home 是一個 data dir 加一個容器，用 `./hermes-run.sh new` 建。

依官方 [Profiles][profiles]，profile 就是一個獨立的 Hermes home，有自己的 `config.yaml`、`.env`、`SOUL.md`、記憶、session、skills 與 cron；用它跑起來的助理就是一個 agent。本專案的 **home** 指掛到容器 `/opt/data` 的 data dir，根目錄是 `default` profile，`profiles/<名稱>/` 是其他 profile，見 [Data dir](data-dir.md)。

## 兩種做法比較

| | 一個 home 多個 profile | 多個 home（每個一容器） |
| --- | --- | --- |
| 設定、記憶、session、skills、cron | 各自分開 | 各自分開 |
| 容器與 gateway | 共用一個 | 各自一個 |
| OpenAI 相容 API | 共用 `8642`，路徑 `/p/<名稱>/v1`，key 是該 profile `.env` 的 `API_SERVER_KEY` | 每個 home 一個 port（`8642`，其他從 `8643` 往上） |
| Dashboard | 共用 `9119`，用 profile 切換器 | 每個 home 一個 port（`9119`，其他從 `9120` 往上） |
| 從 script 指定 | `hermes -p <名稱> …` | 容器內切不到別的 home，要從 host 用 `./hermes-run.sh cli -a <home>` 或打對方的 API |
| 共用的東西 | `scripts/`、`shared/`、`cdp_proxy.py`、OAuth 登入（`auth.json`）、Kanban 任務板 | 不共用 |
| image 版本、資源上限 | 全部一起 | 各自設（`agents/<名稱>.conf`） |
| 重啟 | `gateway restart` 中斷所有 profile | 互不影響 |

兩種做法都不能讓兩個 agent 共用同一組 bot token，同一個 bot 被連兩次會互搶連線。

## 該選哪一種

官方 [Docker 文件][docker]建議一個容器帶所有 profile，只有需要下列隔離時才分開容器：

- 每個工作負載各自的資源上限
- 各自釘 image 版本
- 網路區隔
- 憑證外洩時的影響範圍

照這個原則：

- **預設用 profile**：分身要不同的人設、model、bot 或 Chrome 帳號，但可以跑同一版、一起重啟。
- **要隔離才開新 home**：先拿新版本試跑、不想讓一個 agent 的重啟影響其他人、要限制記憶體或 CPU，或憑證要分開管。

每個容器都要有自己的 data dir。兩個 gateway 同時掛同一個 data dir 會損壞 session 與記憶。

## 建一個 profile

1. 建立，不加 `-a` 就建在主 home：

    ```bash
    ./hermes-run.sh cli [-a <home>] profile create <名稱> [--clone]
    ```

    v0.23.1 的選項（`hermes profile create --help`）：

    | 選項 | 效果 |
    | --- | --- |
    | 不帶 | 空白 profile |
    | `--clone` | 從目前的 profile 複製 `config.yaml`、`.env`、`SOUL.md`、skills；bot token 與 allowlist 不帶 |
    | `--clone-from <來源>` | 指定從哪個 profile 複製，隱含 `--clone` |
    | `--clone-all` | 複製全部狀態，不含對話紀錄與平台設定 |
    | `--clone-channels` | 連 bot token、allowlist、平台設定一起複製；來源正被 live gateway 服務時會被拒絕 |
    | `--no-skills` | 不帶內建 skills |

2. 編輯 `<data dir>/profiles/<名稱>/`：

    - `.env`：這個 profile 自己的 bot token、allowlist、`API_SERVER_KEY`
    - `SOUL.md`：身份與人設
    - `config.yaml`：model（見[模型設定](models.md)）、`browser.cdp_url`（見[瀏覽器](browser.md)）

3. 挑空檔套用：`./hermes-run.sh cli [-a <home>] gateway restart`。

4. 確認：`cli doctor` 的 Profiles 區段列出新 profile，再到平台上找它說句話。

### 讓 profile 使用主 home 部署的 skills

`hermes -p <名稱>` 只讀那個 profile 自己的 `skills/`，不讀主 home 的：

```text
<data dir>/
├── skills/<分類>/…                ← 部署只更新這裡；default profile 讀這裡
└── profiles/<名稱>/skills/…       ← hermes -p <名稱> 只讀這裡
```

所以用 `--clone` 建的 profile 拿到的是建立當下的副本，之後越來越舊；沒有副本的 profile 則找不到主 home 的 skill。要讓它們用同一份，兩步都要做：

1. 刪掉 profile 裡的副本，例如 `<data dir>/profiles/<名稱>/skills/<分類>/`。上游的同名 skill 優先順序是 `project > local > create_dir > external_dirs`，profile 自己的副本（local）會蓋過下一步掛進來的那份。
2. 把主 home 的 `skills/` 本身掛成外部目錄。不能只掛 `skills/<分類>/`，否則分類名稱會消失，`-s <分類>:<skill>` 找不到：

    ```bash
    ./hermes-run.sh cli [-a <home>] -p <名稱> config set skills.external_dirs '["/opt/data/skills"]'
    ```

確認：`cli -p <名稱> skills list` 裡那些 skill 的來源是 `external`。

## 建一個新 home

官方沒有「建立新 home」的指令：新 home 就是一個新資料夾加一個新容器。容器第一次啟動時，entrypoint 會補上缺少的 `.env`、`config.yaml`、`SOUL.md`，同步內建 skills，註冊 default profile；之後可以用 `setup` 精靈設定。`./hermes-run.sh new` 照這個流程，再多做兩件事：從主 home 複製設定，並自動挑 port。

```bash
./hermes-run.sh new kaka
```

它會：

- 建 `~/.hermes-kaka`，容器叫 `hermes-kaka`
- 從主 home 複製 `.env` 與 `config.yaml`（不複製 `SOUL.md`）；`--force` 重跑時，已存在的不覆蓋
- 同步 repo 的 `scripts/` 與 `browsers.conf`
- 從 `8643`、`9120` 往上挑沒被佔用、也不在 `browsers.conf` 裡的 port
- 寫 `agents/kaka.conf`（格式見 [`agent.conf.example`](../agents/agent.conf.example)），要跑不同 image 版本就在裡面設 `HERMES_VERSION`

名稱只能用小寫字母、數字和連字號，不能叫 `hermes`。啟動前：

1. `~/.hermes-kaka/.env` 換成這個 home 自己的 bot token 與 `API_SERVER_KEY`。
2. 寫 `~/.hermes-kaka/SOUL.md`，不寫就用官方預設。
3. 要用瀏覽器時，把 `config.yaml` 的 `browser.cdp_url` 改成這個 home 專屬的 Chrome port。
4. `./hermes-run.sh up -a kaka`。

## 讓 agent 協作

profile 之間不會自己溝通，協作要靠：

- **`delegate_task`**：主 agent 在對話中召喚匿名 subagent，用主 agent 的設定。
- **[Kanban][kanban]**：主 agent 開 task 指定給某個 profile，在背景派給它的 worker；任務板是 home 根目錄的 `kanban.db`。
- **`hermes -p <名稱> chat -q "<任務>"`**：用某個 profile 跑一次任務。[`dispatch-agent`](../skills/dispatch-agent/SKILL.md) skill 把它包成「叫分身做事、再由主 agent 代發報告」的流程。

[profiles]: https://hermes-agent.nousresearch.com/docs/user-guide/profiles
[docker]: https://hermes-agent.nousresearch.com/docs/user-guide/docker
[kanban]: https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban
