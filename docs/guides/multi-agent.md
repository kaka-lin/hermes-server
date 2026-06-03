# Hermes Multi-Agent

Hermes Agent 支援兩種截然不同的 Multi-Agent 協作模式，分別適用於不同的使用情境：**臨時任務委派 (Delegate Task)** 與 **實體多重程序 (Spawning Instances / Profiles)**。

本文將詳細介紹這兩種模式的差異，以及如何透過 Profiles 模式建立完全獨立的代理人（例如：負責不同社群帳號的瀏覽器自動化）。

## 1. Multi-Agent 機制總覽

Hermes 的多 agent 協作有兩條主要路徑，差別在「分身要不要 24/7 自己接訊息」：

| 方案 | 分身有自己長駐的 gateway？ | 需要改 docker-compose？ | 適用 |
| --- | --- | --- | --- |
| **方案 1：透過 main agent 代理** | 否 | 否 | 分身被臨時喚醒做任務、main 統一收訊息再派工 |
| **方案 2：獨立 container + 獨立 data dir** | 是 | 是 | 分身要全職守在某平台收訊息 |

方案 1 又分三種子機制，差別在阻塞、process 隔離、是否使用 profile 自己的設定檔：

| 子機制 | 觸發方式 | 子 agent 是獨立 process？ | 用 profile 自己的 `.env` / `config.yaml`？ | 行為 |
| --- | --- | --- | --- | --- |
| **1a. `delegate_task`** | main agent 在對話中呼叫 tool | 否（同 process 沙盒） | **否**（共用 main 的 config） | RPC call，main 阻塞等子 agent 回覆 |
| **1b. `hermes -p X chat -q "..."`** | main agent 透過 bash tool 或人手動下 | 是 | **是** | 短期 spawn 新 process，跑完即退 |
| **1c. Kanban orchestration** | main agent 用 `kanban_create()` 開 task | 是（dispatcher 背景 spawn） | **是** | Fire-and-forget，持久任務板 + retry |

詳細見下面四個子節（方案 1a–1c 與方案 2）。

### 1.1 方案 1a — Delegate Task

這是一種「平行運算」模式。當主 Agent 遇到龐大的任務時，可以臨時召喚多個子 Agent (Subagents) 平行處理。

- **運作方式**：在同一個 Hermes Process 內部產生獨立對話沙盒供子 Agent 運作，由母 Gateway 統一管理生命週期。
- **特點**：
  - 用完即丟，子 Agent 完成任務回報後即銷毀。
  - **共用**：所有子 Agent 繼承母體的 `config.yaml`、`.env`、`browser.cdp_url`、API key、session DB。
  - 子 agent 是匿名的（官方用詞 "Anonymous subagent"），不是某個 named profile。
  - 即使你用 `hermes profile create` 建了 profile，**`delegate_task` 不會使用它的設定檔**——profile 的 `.env` / `config.yaml` 在這個子機制下完全不生效。
  - **不需要**為子 Agent 額外執行 `gateway run` 或建立 docker service。
- **適用情境**：平行搜尋資料、大量文本分析等不需要獨立系統設定的雜事。

> [!WARNING]
> **瀏覽器自動化的限制**
> 如果你希望不同的子 Agent 控制不同的瀏覽器 Profile（不同的 CDP Port），**不能**使用 `delegate_task`。因為所有子 Agent 會共用同一個 `browser.cdp_url` 設定，導致它們互相搶奪同一個瀏覽器的控制權。要不同 CDP 請改走方案 1b（CLI 代理）或方案 1c（Kanban orchestration）。

### 1.2 方案 1b — CLI 代理 `hermes -p X chat -q "..."`

Main agent（或你本人）透過 bash tool 把任務丟給特定 profile 跑單次任務：

```bash
hermes -p helper chat -q "去檢查有沒有新的客訴簡訊並用設定好的人設語氣回覆"
```

- **運作方式**：spawn 一個帶 `-p` 的新 Hermes process，使用該 profile 的設定執行完一個 `chat` 後退出。
- **特點**：
  - **使用 profile 自己的 `.env` 和 `config.yaml`**——這是方案 1 中**唯一**會讓 `hermes profile create` 出來的設定真正生效的子模式（除了 1c Kanban）。
  - 適合分身要用**不同 model**、**不同 `browser.cdp_url`**、**不同 API key**、**不同 SOUL/system prompt** 來執行任務。
  - 用 `&` 放背景跑就不阻塞 main 對話。
  - 任務沒有持久狀態——跑完即退，跨呼叫沒有任務記憶接續（profile 自己的 sessions/memories 還是會累積，下次再呼叫看得到）。
- **適用情境**：main 想把單次任務丟給專業分身（「請 helper 用它的瀏覽器去 Threads 巡邏一次」），且每次任務獨立、不需要任務板協調。

> [!TIP]
> **本專案實作**：[`skills/dispatch-agent/SKILL.md`](../../skills/dispatch-agent/SKILL.md) 把這個流程包成可被 main agent 觸發的 skill — 當你在 Discord/DingTalk 對 main 說「叫 helper 去巡邏」「請 assistant 去檢查簡訊」這類話時，skill 會自動：
>
> 1. `hermes profile list` 確認分身存在
> 2. 用 `send_message(action='list')` 查回報頻道的精確底層 ID（背景 CLI 分身連不到主控台通訊錄，所以要由 main 先查好）
> 3. 從主帳號 `.env` 抽 platform token（`DISCORD_BOT_TOKEN` / `DINGTALK_WEBHOOK_URL`）export 給分身 process
> 4. `terminal(background=true)` 跑 `/opt/data/home/.local/bin/<profile> chat -q "..."`（profile 的 `~/.local/bin/<name>` 別名等同於 `hermes -p <name> chat -q`）
>
> 注意：skill 設計上**平台 token 來自 main 的 `.env`**（集中管理），其他 config（model、CDP、SOUL）才用 profile 自己的。如果你要讓分身用自己的 bot 帳號發訊息，要修 skill 把 token export 改成從 profile `.env` 抽。

### 1.3 方案 1c — Kanban Orchestration

[官方 Kanban 頁面](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban) 提供持久任務板：main agent 開 task，由 dispatcher 在背景 spawn worker process。

官方對 Kanban vs `delegate_task` 的對比（[Kanban — kanban-vs-delegate_task](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban#kanban-vs-delegate_task) 逐字節錄）：

| | `delegate_task` | Kanban |
| --- | --- | --- |
| Shape | RPC call (fork → join) | Durable message queue + state machine |
| Parent | Blocks until child returns | Fire-and-forget after create |
| Child identity | Anonymous subagent | Named profile with persistent memory |
| Resumability | None — failed = failed | Block → unblock → re-run; crash → reclaim |
| Human in the loop | Not supported | Comment / unblock at any point |
| Audit trail | Lost on context compression | Durable rows in SQLite forever |

官方一句話總結：

> `delegate_task` is a function call; Kanban is a work queue where every handoff is a row any profile (or human) can see and edit.

- **運作方式**：
    1. Main agent 用 `kanban_create()` 把任務寫進 `~/.hermes/kanban.db`，指定 assignee 為某個 profile 名稱。
    2. Hermes 內建 dispatcher（預設嵌在 main gateway 內，預設每 60 秒掃一次）看到 task 進入 `ready` 狀態時，spawn 該 profile 的 worker process。
    3. Worker 啟動時帶 `HERMES_KANBAN_TASK` 環境變數，自動讀取自己的 task context、跑完用 `kanban_complete()` 回報。
- **特點**：
  - **使用 profile 自己的 `.env` 和 `config.yaml`**（同 1b）。
  - Worker 是「full OS process with its own identity」（官方用詞）——有獨立 memory、可重啟、crash 可被 reclaim。
  - Fire-and-forget——main 不阻塞，task 進行中可繼續做別的事。
  - 持久任務板——task 落地在 SQLite (`~/.hermes/kanban.db`)，重啟 gateway 不會丟。
  - 支援人類 collaborator：可透過 dashboard / CLI 給 task 加 comment、unblock、reassign。
  - **不需要動 docker-compose**——dispatcher 跟 worker process 都跑在 main gateway 容器內。
- **適用情境**：跨領域長期任務派工（main → researcher → coder → reviewer 流水線）、需要重試 / 人在中間 review / audit trail 的場景。
- **Agent 工具集**（官方）：`kanban_show`、`kanban_list`、`kanban_complete`、`kanban_block`、`kanban_heartbeat`、`kanban_comment`、`kanban_create`、`kanban_link`、`kanban_unblock`。

### 1.4 方案 2 — 獨立 Gateway / 多容器

這是建立「完全獨立、互不干擾」的長駐機器人模式。Hermes 官方對 profile 的定義是「a separate Hermes home directory」——每個 profile 擁有自己的 `config.yaml`、`.env`、`SOUL.md`、`memories/`、`sessions/`、`skills/`、`cron/` 與 state database。

- **運作方式**：每個 Agent 都是獨立的 OS Process，跑各自的 `gateway run`。
  - **在 Host 上**（非 Docker）：直接 `coder gateway start` + `assistant gateway start`，官方 [profiles 頁](https://hermes-agent.nousresearch.com/docs/user-guide/profiles#running-gateways) 的標準做法。
  - **在 Docker 部署**：每個 agent 一個 container、各自 bind-mount 獨立 host 資料夾（例如 `~/.hermes-work`、`~/.hermes-helper`），詳見 [Docker Compose 多容器部署](#3-docker-compose-多容器部署)。
- **特點**：
  - 完整的設定隔離（model、平台 token、`browser.cdp_url`、API key）。
  - 記憶完全分開，不會互相洩漏。
  - 24/7 各自接訊息回訊息，platform webhook 直接打到該 agent 的 gateway。
- **適用情境**：分身要全職守在某平台（DingTalk、Line、Telegram 第二帳號…）、要連自己的瀏覽器 Profile、需要完全獨立的 API quota / OAuth 帳號。

> [!IMPORTANT]
> **Docker 部署絕對不要**用 `hermes -p <名稱> gateway run` + 共掛同一個 volume 來模擬方案 2——官方明文禁止（[Docker — Multi-profile support](https://hermes-agent.nousresearch.com/docs/user-guide/docker#multi-profile-support)），詳見 [Docker Compose 多容器部署](#3-docker-compose-多容器部署)。

## 2. 實戰：建立多平台社群巡邏 Agents

假設我們有多個不同的網頁 Profile（例如登入著不同社群帳號），並希望多個獨立的 Hermes Agent 分別控制它們，且在 Discord 的不同頻道中各自回覆。

### 2.1 建立獨立 Profile

透過 `--clone` 參數，可以複製主帳號的 `config.yaml`、`.env`、`SOUL.md` 來快速建立分身（`sessions/`、`memories/` 不會複製，新 profile 為全新狀態）：

```bash
hermes profile create manager1 --clone
hermes profile create manager2 --clone
```

> [!NOTE]
> `profile create` 只是建立資料夾與設定檔；分身真正「上線」要靠後續的 `gateway run`（見 [啟動與指揮總管](#24-啟動與指揮總管)）或在 Docker Compose 新增 service（見 [Docker Compose 多容器部署](#3-docker-compose-多容器部署)）。沒有跑 gateway 的分身只能被 subagent 模式或 `hermes -p ... chat` 臨時喚醒。

### 2.2 設定獨立的瀏覽器 CDP URL

分別修改它們各自的 `config.yaml`，讓它們對應到不同的 CDP Port。

#### Agent A (manager1)

修改 `~/.hermes/profiles/manager1/config.yaml`：

```yaml
browser:
  cdp_url: 'http://127.0.0.1:<Port1>'  # 對應 Google Profile 1
```

#### Agent B (manager2)

修改 `~/.hermes/profiles/manager2/config.yaml`：

```yaml
browser:
  cdp_url: 'http://127.0.0.1:<Port2>'  # 對應 Google Profile 2
```

### 2.3 設定 Discord 頻道分流

為了讓多個 Agent 在同一個 Discord 伺服器中擔任不同頻道的專職客服，我們不需要申請多個不同的 Bot Token。只要在 `config.yaml` 中限制它們的活動範圍即可。

**以 agent-main 為例：**

```yaml
discord:
  require_mention: true
  allowed_channels: '<Channel ID>' # 限制它只能在這個 Channel 讀取和說話
  free_response_channels:
    - '<Channel ID>' # 在這頻道不用 @ 就直接回話
```

### 2.4 啟動與指揮總管

當設定完成後，只要為每個 Profile 各跑一個 Gateway 行程：

```bash
hermes -p manager1 gateway run &
hermes -p manager2 gateway run &
```

> [!IMPORTANT]
> 上面這種「同一台機器、同一個 `~/.hermes`、多個 gateway 平行跑」的寫法是 Hermes 官方在 [profiles 頁](https://hermes-agent.nousresearch.com/docs/user-guide/profiles#running-gateways) 對「直接在 host 上跑」的範例。但**在 Docker 部署下，官方明確不推薦這個模式**（[Docker — Multi-profile support](https://hermes-agent.nousresearch.com/docs/user-guide/docker#multi-profile-support)：「not recommended」+「still applies to profiles within a single container」），請改用 [Docker Compose 多容器部署](#3-docker-compose-多容器部署) 介紹的「一個 container 一個獨立 host 資料夾」模式。

#### 透過總指揮統一發號施令

你也可以把目前的 Hermes 作為「總指揮」，透過終端機直接指派任務給這些分身，它們會在背景各自使用自己的設定檔平行運作：

```bash
# 叫 manager1 去做任務（-q 表示在背景跑完就結束）
hermes -p manager1 chat -q "去檢查信箱有沒有新的信件" &

# 叫 manager2 去做任務
hermes -p manager2 chat -q "去檢查IG有沒有新的限時動態" &
```

這保證了**設定隔離**與**非同步執行**，每個 Agent 都能精準連上自己的瀏覽器，不會發生控制權衝突。

## 3. Docker Compose 多容器部署

如果你希望某個 profile 在 Docker 環境下「24 小時長駐接訊息」（例如 `manager1` 全職接 DingTalk），就需要為它建立獨立的 Compose service。這一節遵循官方 [Hermes Docker 文件 — Multi-profile support](https://hermes-agent.nousresearch.com/docs/user-guide/docker#multi-profile-support) 的推薦做法。

### 3.1 官方明文：Docker 內**不要用** `-p` 共用 volume

官方逐字（來源同上）：

> **When running under Docker, using Hermes' built-in multi-profile feature is not recommended.** Instead, the recommended pattern is **one container per profile**, with each container bind-mounting its own host directory as `/opt/data`.
>
> **Avoids concurrent-write risk** — the warning above about never running two gateways against the same data directory **still applies to profiles within a single container**.

換句話說，官方已預先排除「以 `-p` 切換 profile 子目錄」當作併發寫入的解法。雖然 `state.db` 等檔案會被 lazy-create 到 `profiles/<名稱>/` 底下，但官方明確說頂層 `auth.json`、`kanban.db`、`response_store.db` 等共用檔案的 concurrent-write 風險**對 profile 子目錄一樣存在**。

### 3.2 何時需要多容器？

| 情境 | 建議模式 |
| --- | --- |
| 主帳號處理所有平台，分身只在背景被臨時喚醒做雜事 | **單容器** + `delegate_task` 或 Kanban orchestration |
| 分身需要全職守在某平台（DingTalk、Line、Telegram 第二帳號…） | **多容器 + 分離 data dir**（見下節推薦架構） |
| 分身需要長期連自己的瀏覽器 Profile，且與主帳號平行運作 | **多容器 + 分離 data dir**（見下節推薦架構） |
| 分身需要完全獨立的 API 配額 / OAuth 帳號 / 計費 | **多容器 + 分離 data dir**（見下節推薦架構） |

### 3.3 推薦架構：一個 container 一個 profile，各自 bind-mount 獨立 host 資料夾

按官方範例：

```yaml
services:
  hermes-work:
    image: kakalin/hermes-agent:latest
    container_name: hermes-work
    restart: unless-stopped
    command: gateway run            # 永遠不帶 -p
    volumes:
      - ${HOME}/.hermes-work:/opt/data
    ports:
      - "8642:8642"
    shm_size: "${HERMES_SHM_SIZE:-1g}"
    dns: [1.1.1.1, 8.8.8.8]
    networks: [hermes-net]

  hermes-personal:
    image: kakalin/hermes-agent:latest
    container_name: hermes-personal
    restart: unless-stopped
    command: gateway run
    volumes:
      - ${HOME}/.hermes-personal:/opt/data    # 不同 host 路徑
      - ${HOME}/.hermes-work/skills:/opt/data/skills:ro   # （選用）跨容器共讀 skills
    ports:
      - "8643:8642"
    shm_size: "${HERMES_SHM_SIZE:-1g}"
    dns: [1.1.1.1, 8.8.8.8]
    networks: [hermes-net]

networks:
  hermes-net:
    driver: bridge
```

**注意事項**：

- 每個 host 資料夾都是**頂層獨立的 Hermes 安裝**，不是 `~/.hermes/profiles/<名稱>/` 那種子目錄。每個都有自己的 `.env`、`config.yaml`、`SOUL.md`、`auth.json`、`state.db`。
- 每個 helper 第一次啟動時要重新 OAuth 登入、重新下載 LLM provider metadata、bundled skills 會被 image 帶進來。
- 想跨容器共用 skills 可用 read-only bind mount（上面範例第二個 service 示範）。這只共用「讀取」，避免 helper 寫到主帳號的 skills 目錄。

### 3.4 為什麼共用 volume + 多個 `-p` gateway 不行（即使檔案層級看起來隔離）

官方明文（3.1 節已引用）已直接駁回「`-p` 把寫入路徑切到 profile 子目錄就安全」這套說法。即使 `profiles/<name>/state.db` 是獨立檔案，下列頂層檔案在共掛 volume + 多 gateway 場景下仍會被多個 process 同時讀寫：

| 路徑 | 共寫風險 |
| --- | --- |
| `/opt/data/auth.json` + `auth.lock` | OAuth refresh 同時觸發時的競爭，依賴 `auth.lock` 但不保證所有 race window 都被覆蓋 |
| `/opt/data/kanban.db` | 多 gateway 同時 enqueue task |
| `/opt/data/response_store.db` | LLM response cache 寫入競爭 |
| `/opt/data/channel_directory.json` | Discord channel metadata |
| `/opt/data/gateway_state.json` / `processes.json` | Gateway 自我狀態 |
| `/opt/data/models_dev_cache.json` | LLM provider metadata 寫入 |

短時間實測（< 1 分鐘）通常看不到問題，但官方團隊「特別把這條警告寫進文件」就代表他們踩過或預期會踩到 race condition。**不要把短時實測沒撞鎖當成可以長駐的證據**。

### 3.5 新增第 N 個 agent 的 SOP

1. **準備獨立 host 資料夾**

    ```bash
    docker compose down       # 先停掉現有 service 再搬資料
    # 從現有 agent 的設定當基礎（可選）
    mkdir -p ~/.hermes-agent-line
    cp ~/.hermes/.env       ~/.hermes-agent-line/.env
    cp ~/.hermes/config.yaml ~/.hermes-agent-line/config.yaml
    cp ~/.hermes/SOUL.md    ~/.hermes-agent-line/SOUL.md 2>/dev/null || true
    # 編輯 ~/.hermes-agent-line/{.env,config.yaml}，換成新的 platform token、allowlist、CDP port
    ```

2. **在 `docker-compose.yml` 加一個 service**（複製 3.3 節推薦架構模板，改 `container_name`、`volumes` 的 host 路徑、`ports`）

3. **啟動**

    ```bash
    docker compose up -d
    ```

4. **驗證**

    ```bash
    docker compose logs -f hermes-agent-line
    # gateway 啟動後，host 上應該出現
    ls -la ~/.hermes-agent-line/ | grep -E 'state\.db|config\.yaml'
    ```

5. **第一次 OAuth 登入**（如果 agent 用 Anthropic Portal 或其他 OAuth provider）

    ```bash
    docker exec -it hermes-agent-line hermes setup
    ```

## 3.6 用 hermes-stack.sh 管理多容器

[`hermes-stack.sh`](../../hermes-stack.sh) 把上面 §3.3 的推薦架構與 §3.5 的新增 SOP 包成一支腳本，**不修改 `docker-compose.yml`**。它的做法是：同一份已被 env 參數化的 compose 檔，搭配 `docker compose -p <project>` 做命名空間隔離，每個 agent 一個獨立 stack。

- **主 agent**：`~/.hermes`，project = `hermes`，吃 compose 預設 port / 容器名，不需要設定檔。
- **分身 agent**：`~/.<name>`，project = `<name>`，編排設定讀 [`agents/<name>.conf`](../../agents/agent.conf.example)。`<name>` 原樣使用、不自動補前綴，所以要 `hermes-` 開頭請自己打全名（例如 `new hermes-katherine` → 容器 `hermes-katherine`）。

`agents/<name>.conf` 只放**編排設定**（port、容器名、data dir 路徑）；分身的 runtime 設定（`config.yaml`、含金鑰的 `.env`）一律留在它自己的 data dir，由 `new` 從主 agent clone 過去。`.conf` 與 runtime 的 `.env` 是不同層，用不同副檔名避免混淆。真檔 `agents/*.conf` 已被 gitignore，只 commit `agent.conf.example` 範本。

### 指令

```bash
./hermes-stack.sh up [<name>|all]       # 啟動（無參數 = 主 agent）
./hermes-stack.sh down [<name>|all]     # 停止
./hermes-stack.sh restart [<name>|all]  # 重啟 process（不重建容器）
./hermes-stack.sh logs [<name>]         # 跟著看 log（無參數 = 主 agent）
./hermes-stack.sh status [<name>]       # 無參數 = 所有 agent 狀態總覽
./hermes-stack.sh ls                    # 列出已設定的 agent 與其 port
./hermes-stack.sh new <name> [--force]  # scaffold 新分身（clone 主 agent 設定）
```

> [!NOTE]
> 主 agent 用 project `hermes`，與你直接 `docker compose up -d`（project = 目錄名 `hermes-server`）是不同 stack。第一次改用本腳本前，先 `docker compose down` 把舊 stack 收掉，避免兩邊都想建名為 `hermes` 的容器而撞名。

### `new <name>` 做的事（自動化 §3.5）

1. 驗證名稱（`[a-z0-9-]`、不可叫 `main` / `hermes`，後者保留給主 agent）、確認 `agents/<name>.conf` 與 `~/.<name>` 不存在（`--force` 才覆寫）。
2. 掃描主 agent 預設與現有 `agents/*.conf`，自動挑一組沒被佔用、且避開 CDP `9223-9225` 的 gateway / dashboard port。
3. 建 `~/.<name>/`，**clone** 主 agent 的 `.env` / `config.yaml` / `SOUL.md`。
4. 複製容器內 runtime 腳本到 data dir，保留 `cdp_proxy.py` 需要的巢狀結構：`scripts/cdp_proxy.py`（來源 repo `scripts/`）與 `scripts/host/browsers.conf`（來源 repo root 的 `browsers.conf`，是 [`cdp_proxy.py`](../../scripts/cdp_proxy.py) 讀 port 的來源，見 [瀏覽器接線架構](mac-chrome-cdp-guide.md)）。
5. 產生 `agents/<name>.conf`（絕對路徑 data dir、自動挑的 port、唯一容器名）。
6. 印出剩下的手動步驟：去分身的 `.env` 填它自己的 platform token / allowlist / API key，必要時改 `config.yaml` 的 `browser.cdp_url`，然後 `./hermes-stack.sh up <name>`。

`new` **不複製 skills**——分身用 image 內建 skills 起步，要哪個客製 skill 再自行安裝（避免與「skills 目錄需可寫、且 role-specific」打架）。

## 4. 相關參考

- [Hermes 官方 — Profiles](https://hermes-agent.nousresearch.com/docs/user-guide/profiles) — `-p` flag、`profile create --clone`、host 上跑多 gateway
- [Hermes 官方 — Docker](https://hermes-agent.nousresearch.com/docs/user-guide/docker) — Docker 部署的「one container per profile」推薦做法
- [Hermes 官方 — Kanban](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban) — Kanban orchestration、`kanban_*` 工具集、`kanban-vs-delegate_task` 對比
- [`~/.hermes` 資料夾結構說明 — 多 profile 切換](data-volume.md#4-多-profile-切換) — 多 agent 部署的注意事項
- [Setup Deep Dive](../deployment/setup-deep-dive.md) — Docker Compose 設計細節
- [瀏覽器自動化](browser-automation.md) — CDP Port 設定
