# 瀏覽器自動化設定指南

Hermes Agent 提供一套 browser tool 介面（`browser_navigate`、`browser_click` 等），讓 agent 能瀏覽網頁、截圖、填表、抓取結構化資料。但 Hermes **本身不內建瀏覽器引擎** — 實際的瀏覽器執行依賴外部後端：

- **Local 模式** — 透過 [`agent-browser`](https://agent-browser.dev) CLI（Vercel Labs 開源，Rust 原生）驅動本地 Chrome
- **雲端模式** — 透過 Browserbase / Browser Use / Firecrawl API
- **CDP 模式** — 連接 Host 上已開的 Chrome（`/browser connect`）
- **Camofox 模式** — 透過 Camofox server 驅動反偵測 Firefox

本文件說明 Docker 環境下的設定要點與操作流程。

- **[Hermes Browser 官方文件](https://hermes-agent.nousresearch.com/docs/user-guide/features/browser)**
- **[agent-browser 安裝指南](https://agent-browser.dev/installation)**

## 1. 架構差異：Hermes vs OpenClaw

| | Hermes | OpenClaw |
| --- | --- | --- |
| 瀏覽器引擎 | 外部（`agent-browser` CLI / 雲端 / CDP） | 外部（Mac Host Chrome） |
| 橋接方式 | `agent-browser` CLI 透過 CDP 驅動 Chrome | `openclaw node run` 透過自建 Node bridge 驅動 |
| 是否需要額外安裝 | ✅ 需安裝 `agent-browser` + `agent-browser install` | ✅ 需在 Mac 跑 `openclaw node run` |
| 登入狀態保持 | 每次 session 獨立（除非用 CDP 或 Camofox persistence） | 直接使用 Mac Chrome 的登入狀態 |
| 適合場景 | 爬蟲、填表、自動化 | 需保持登入的操作（如 Threads、IG 發文） |

> [!IMPORTANT]
> Local 模式的 Chrome 由 `agent-browser` 管理，是獨立的 Chrome for Testing 實例，**不會繼承** Host Chrome 的 cookies 或登入狀態。若需要操控已登入的網站，請使用 §5 的 CDP 連接模式或 §4.5 的 Camofox persistent session。

## 2. Docker 環境：系統需求與 `shm_size`

### 2.1 為什麼需要 `shm_size: 1g`

Playwright / Chromium 大量使用 `/dev/shm` 共享記憶體。Docker 預設只給 **64 MB**，會造成：

- 瀏覽器啟動失敗
- Page crash with `Target closed`
- 執行 navigation 時發生 segfault
- 記憶體不足相關的隨機崩潰

本專案 `docker-compose.yml` 預設啟用：

```yaml
services:
  hermes:
    shm_size: "${HERMES_SHM_SIZE:-1g}"
```

### 2.2 資源配置

| 項目 | 不啟用 browser | 啟用 browser |
| --- | --- | --- |
| Memory limit | 1 GB | **2 GB 起跳，4 GB 建議** |
| `/dev/shm` | 預設 64 MB 即可 | **1 GB** |
| Disk | 500 MB | 2 GB+（Chromium 二進位 + cache） |

`.env` 配置範例：

```ini
# 啟用 browser（預設）
HERMES_MEMORY_LIMIT=4G
HERMES_SHM_SIZE=1g

# 不需要 browser tools，節省資源
HERMES_MEMORY_LIMIT=1G
HERMES_SHM_SIZE=64m
```

## 3. 啟用 browser tools

啟用 browser 需要**兩個步驟**：將 `browser` 加入 `toolsets` 清單 + 設定 browser provider。

### 步驟 1：將 `browser` 加入 toolsets

預設的 `toolsets` 只有 `hermes-cli`，**不包含** `browser`。必須手動加入：

- **CLI 指令（推薦）：**

  ```bash
  docker run --rm \
    -v ~/.hermes:/opt/data \
    nousresearch/hermes-agent config set toolsets '["hermes-cli", "browser"]'
  ```

- **手動編輯** `~/.hermes/config.yaml`：

  ```yaml
  toolsets:
  - hermes-cli
  - browser
  ```

### 步驟 2：設定 browser provider

透過 `hermes tools` 互動選單選擇 browser 後端（local / Browserbase / Firecrawl 等）：

```bash
docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent tools
```

執行後會看到 `Browser Automation - Choose a provider` 選單，選擇後設定會寫入 `~/.hermes/config.yaml` 的 `browser:` 區塊。

> [!WARNING]
> `hermes tools` 只設定 browser **provider**，**不會**自動將 `browser` 加入 `toolsets` 清單。如果你只跑了 `hermes tools` 卻沒做步驟 1，browser tools 不會被載入。

修改後重啟：

```bash
docker compose restart hermes
```

## 4. Browser Provider 設定

以下設定皆位於 `~/.hermes/config.yaml` 的頂層 `browser:` 區塊（參考 [`config.example.yaml`](../../config.example.yaml)）：

```yaml
browser:
  inactivity_timeout: 120          # 閒置多久後自動清理 session（秒）
  command_timeout: 30              # 單一指令超時（秒）
  record_sessions: false           # 是否錄製 session 為 WebM
  allow_private_urls: false        # 是否允許存取私有 URL
  auto_local_for_private_urls: true  # 雲端模式下自動用本地 sidecar 處理私有 URL
  cdp_url: ''                      # 自訂 CDP endpoint
  dialog_policy: must_respond      # JS dialog 處理策略
  dialog_timeout_s: 300            # dialog 超時（秒）
  cloud_provider: local            # local / browserbase / browser-use / firecrawl
  camofox:
    managed_persistence: false     # Camofox 持久 session
```

### 4.1 Local 模式（預設）

不需要設定任何 API key。`cloud_provider: local` 為預設值，容器內透過 `agent-browser` CLI 驅動本地 Chromium。

**安裝 `agent-browser` CLI：**

Local 模式依賴 [`agent-browser`](https://agent-browser.dev) CLI（Rust 原生二進位）。根據 [Hermes 官方文件](https://hermes-agent.nousresearch.com/docs/user-guide/features/browser#install-agent-browser-cli)與 [agent-browser 安裝指南](https://agent-browser.dev/installation)，安裝方式為：

```bash
npm install -g agent-browser
agent-browser install              # 從 Chrome for Testing 下載 Chrome 二進位（首次必跑）
# Docker / Linux 環境需加上 --with-deps 安裝系統依賴：
# agent-browser install --with-deps
```

安裝後可用 `agent-browser doctor` 診斷環境是否正常。

官方文件也提到 `hermes setup tools → Browser Automation` 會自動安裝 `agent-browser`：

```bash
docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent setup tools
# → Browser Automation → 選擇 provider 後自動安裝
```

> [!NOTE]
> Docker 環境下，即使執行了 `hermes tools` 或 `hermes setup tools`，`agent-browser` 不一定會成功安裝到容器內。若首次使用 `browser_navigate` 失敗，agent 會自動嘗試在容器內安裝 `agent-browser` 並重試：
>
> ```text
> 💻 terminal: "agent-browser install"
> 💻 terminal: "python3 -m playwright install chromium"
> 🌐 browser_navigate: "https://..." ← 失敗
> 💻 terminal: (自動排障、安裝依賴)
> 🌐 browser_navigate: "https://..." ← 成功 ✅
> ```
>
> 安裝完成後，後續的 browser 操作會正常運作。

**設定確認清單：**

1. `toolsets` 包含 `browser`（§3 步驟 1）
2. `browser.cloud_provider` 為 `local`（預設即是）
3. Docker Compose 的 `shm_size` 為 `1g`（§2）
4. 重啟容器讓設定生效

```bash
docker compose restart hermes
```

**使用方式：**

在任何已連線的 Channel（Discord、Telegram、CLI 等）用自然語言指揮 agent 瀏覽網頁：

```text
幫我用 browser 打開 https://github.com/trending，告訴我現在最熱門的 repo 有哪些
```

```text
到 https://example.com/signup 幫我填寫註冊表單，email 用 test@example.com
```

> [!NOTE]
> 如果不明確說「用 browser」，agent 可能會優先使用 `web_search` 或 `execute_code` + `urllib` 來抓取資料（因為更快且更便宜）。明確指定「用 browser」可以強制使用 browser tools。

Agent 會自動呼叫 `browser_navigate` → `browser_snapshot` → `browser_click` / `browser_type` 等工具完成操作。頁面內容以 accessibility tree（文字快照）回傳，互動元素會帶有 ref ID（如 `@e1`、`@e2`）。

> [!NOTE]
> Local 模式的 Chromium 在容器內 headless 運行，你看不到瀏覽器畫面。如果需要即時觀看，請使用 §5 的 CDP 模式連接 Host Chrome，或使用 Camofox 的 VNC 功能（§4.5）。

### 4.2 Browserbase 雲端模式

在 `~/.hermes/.env` 加入：

```ini
BROWSERBASE_API_KEY=***
BROWSERBASE_PROJECT_ID=your-project-id-here
```

可選環境變數：

```ini
# Residential proxy（預設：true）
BROWSERBASE_PROXIES=true
# 進階隱匿模式 — 需要 Scale Plan（預設：false）
BROWSERBASE_ADVANCED_STEALTH=false
# Session 斷線重連 — 需要付費方案（預設：true）
BROWSERBASE_KEEP_ALIVE=true
# 自訂 session timeout（毫秒）
BROWSERBASE_SESSION_TIMEOUT=600000
# 閒置多久後自動清理（秒，預設：120）
BROWSER_INACTIVITY_TIMEOUT=120
```

至 [browserbase.com](https://browserbase.com) 取得憑證。

### 4.3 Browser Use 雲端模式

在 `~/.hermes/.env` 加入：

```ini
BROWSER_USE_API_KEY=***
```

至 [browser-use.com](https://browser-use.com) 取得 API key。若同時設定 Browserbase 和 Browser Use，**Browserbase 優先**。

### 4.4 Firecrawl 雲端模式

在 `~/.hermes/.env` 加入：

```ini
FIRECRAWL_API_KEY=fc-***
```

接著選擇 Firecrawl 為 browser provider：

```bash
docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent setup tools
# → Browser Automation → Firecrawl
```

可選設定：

```ini
# Self-hosted Firecrawl（預設：https://api.firecrawl.dev）
FIRECRAWL_API_URL=http://localhost:3002
# Session TTL 秒數（預設：300）
FIRECRAWL_BROWSER_TTL=600
```

### 4.5 Camofox 本地反偵測模式

[Camofox](https://github.com/jo-inc/camofox-browser) 是包裝 Camoufox（具 C++ 指紋欺騙的 Firefox fork）的 Node.js server：

```bash
# 透過 Docker 執行
docker run -d --network host -e CAMOFOX_PORT=9377 jo-inc/camofox-browser
```

在 `~/.hermes/.env` 設定：

```ini
CAMOFOX_URL=http://localhost:9377
```

當 `CAMOFOX_URL` 已設定，所有 browser tools 自動透過 Camofox 路由。

#### Persistent browser sessions

預設每次 session 使用隨機身分。要啟用持久 session（保留 cookies / 登入狀態）：

```yaml
# ~/.hermes/config.yaml
browser:
  camofox:
    managed_persistence: true
```

> [!WARNING]
> 必須放在 `browser.camofox.managed_persistence`，**不是**頂層的 `managed_persistence`。錯誤的路徑會導致 Hermes 靜默回退到隨機 userId。修改後必須**完全重啟** Hermes。

### 4.6 Hybrid Routing：雲端 + 本地自動切換

當雲端 provider 已設定時，Hermes 會自動為私有 / 本地位址（`localhost`、`127.0.0.1`、`192.168.x.x`、`10.x.x.x`、`*.local` 等）啟動本地 Chromium sidecar。公開 URL 繼續走雲端。

預設開啟。要關閉：

```yaml
browser:
  cloud_provider: browserbase
  auto_local_for_private_urls: false
```

> [!NOTE]
> Nous Portal 付費訂閱者可透過 [Tool Gateway](https://hermes-agent.nousresearch.com/docs/user-guide/features/tool-gateway) 使用 browser 功能，不需額外設定 API key。執行 `hermes model` 或 `hermes tools` 即可啟用。

## 5. 進階：透過 Chrome DevTools Protocol (CDP) 連接 Host Chrome

如果你需要讓 agent 控制 Host 上**已登入**的 Chrome（保留 cookies 等狀態），可使用 CDP 模式。

### 5.1 啟動 Host Chrome 的 CDP 服務

要讓 Agent 控制你的 Chrome，你需要開啟遠端除錯（CDP）端口：

1. 打開你日常使用的 Chrome 瀏覽器。
2. 在網址列輸入並前往 `chrome://inspect/#remote-debugging`。
3. 勾選 **「Allow remote debugging for this browser instance」**。
4. 勾選後，畫面下方會顯示 `Server running at: 127.0.0.1:18800`，代表 CDP 服務已成功啟動。

> [!TIP]
> 這樣 Agent 就能直接控制你目前正在使用的 Chrome，共用所有的登入狀態與 Cookies，是最方便的做法！

### 5.2 設定 Hermes 連接與繞過 Chrome 安全限制

Hermes 執行在 Docker 容器內，要連線到 Mac 上的 Chrome 必須透過 `host.docker.internal`。
但是，**Chrome 內建防止 DNS Rebinding 的安全機制**，當它看到連線請求的 Host 標頭不是 `127.0.0.1` 或是 `localhost` 時，會**直接拒絕連線**。

為了解決這個問題，我們必須在 Docker 內架設一個「TCP 轉發站 (Proxy)」，欺騙 Chrome 請求是來自本地端。最簡單的方式就是**直接請 Agent 代勞**！

#### 讓 Agent 自動處理

你不需要死記底層指令或了解轉發機制！直接在 Discord / Telegram 中對 Hermes 下達直覺的指令：

> 「請幫我連接本機的 Chrome (port 18800) 並打開網頁。」

聰明的 Agent 就會自動幫你在背景跑起轉發站（[`cdp_proxy.py`](../../scripts/cdp_proxy.py)），並透過 CDP 完成連線與網頁操作。

> [!TIP]
> **給想手動操作的進階使用者：**
> 在 Mac 執行 `docker exec -d hermes python3 /opt/data/scripts/cdp_proxy.py 18800` 後，修改 `config.yaml` 中的 `cdp_url: 'http://127.0.0.1:18800'` 並重啟容器即可。

#### 替代方法：互動式 CLI 臨時連接

若你是在終端機執行 `hermes chat`，可用 `/browser connect` 即時連接（同樣需先執行第一步啟動轉發站）：

```text
/browser connect ws://127.0.0.1:18800
/browser status
/browser disconnect
```

> [!WARNING]
> `/browser connect` 是互動式指令，**不會**在 gateway 模式（Discord 等）中運作。

## 6. 共用 OpenClaw Browser Profiles

如果你同時運行 OpenClaw and Hermes，可以讓 Hermes 直接連接 OpenClaw 已經開啟並管理好的 Chrome profiles，共用登入狀態。這其實就是 §5 「方法 A」的延伸應用。

### 6.1 前提與準備

1. **OpenClaw Profiles 已啟動**：在 `openclaw.json` 中設定好 CDP port 並確認瀏覽器已開啟（在 OpenClaw log 中看到 `openclaw browser started`）。

2. **準備 Mac Chrome 視窗**：
    - 確保 **目標 Profile 的 Chrome 視窗保持開啟**。
    - 每個 Profile 至少 **保留一個分頁**（防止瀏覽器進入休眠或自動關閉）。
    - 如果 macOS 跳出「允許遠端連線 / Attach」的系統提示，請務必點擊 **允許**。

**OpenClaw 範例設定：**

```json
"browser": {
    "defaultProfile": "openclaw",
    "profiles": {
        "default": { "cdpPort": 18800 },
        "worker1": { "cdpPort": 9223 },
    }
}
```

確認 profiles 已啟動（在 OpenClaw log 中看到 `openclaw browser started`）。

### 6.2 讓 Agent 自動處理（推薦）

因為 Agent 能夠自己讀取 `openclaw.json` 並執行指令，**最簡單的方式是直接叫 Agent 幫你處理**！你可以直接對它這樣說：

**Discord / Telegram 用法：**

```text
# 走預設 openclaw profile（Hermes 內建 browser tools）
幫我用 browser 打開 https://example.com

# 走特定的 profile (例如 worker1)
請用 worker1 profile 開 https://threads.net 幫我發文
```

> [!TIP]
> 當你這樣下令時，聰明的 Agent 會自己去解析 profile 對應的 port（例如 9223），並自動去背景啟動 TCP 轉發站來完成任務！完全不需要你手動去查 port 或是下 Bash 指令。

### 6.3 手動連線操作（進階）

如果你想手動設定，假設要用 `langlive-main` Profile (Port: 9223) 來開網頁：

1. **啟動本機轉發站 (Proxy)：**

    ```bash
    docker exec -d hermes python3 /opt/data/scripts/cdp_proxy.py 9223
    ```

2. **更新連線設定（如果需要改變預設）：**

    ```yaml
    # ~/.hermes/config.yaml
    browser:
      cdp_url: 'http://127.0.0.1:9223'
    ```

    *(修改後需執行 `docker compose restart hermes`)*

3. **呼叫工具：**

    之後 Agent 呼叫 `browser_navigate` 時，指令就會順著這條管線傳遞：

    > **Hermes 工具 → 轉發站 (127.0.0.1:9223) → Mac 上的 OpenClaw (langlive-main)**

| Profile | CDP Port | 從容器內的連線方式 | 使用工具 |
| --- | --- | --- | --- |
| `openclaw`（預設） | 18800 | `browser.cdp_url` 自動連接 | Hermes browser tools |
| `worker1` | 9223 | `agent-browser --cdp "http://127.0.0.1:9223"` | terminal tool |

> [!TIP]
> 非預設 profile 走的是 terminal tool → `agent-browser` CLI，不是 Hermes 內建的 browser tools。操作方式（snapshot、click 等）一樣，只是 agent 會用 `agent-browser snapshot` 而非 `browser_snapshot`。

## 7. 可用的 Browser Tools

| Tool | 說明 |
| --- | --- |
| `browser_navigate` | 導航至 URL（必須最先呼叫，初始化 session） |
| `browser_snapshot` | 取得頁面 accessibility tree 快照 |
| `browser_click` | 透過 ref ID 點擊元素（如 `@e5`） |
| `browser_type` | 在輸入欄位打字（先清除再輸入） |
| `browser_scroll` | 上下捲動頁面 |
| `browser_press` | 按下鍵盤按鍵（`Enter`、`Tab`、`Escape` 等） |
| `browser_back` | 返回上一頁 |
| `browser_get_images` | 列出頁面所有圖片（URL + alt text） |
| `browser_vision` | 截圖 + AI 視覺分析 |
| `browser_console` | 讀取瀏覽器 console 輸出 |
| `browser_cdp` | 原始 CDP 指令直通（需 CDP 連線） |
| `browser_dialog` | 回應原生 JS dialog（alert / confirm / prompt） |

> [!TIP]
> 單純抓取資訊時，優先使用 `web_search` 或 `web_extract` — 更快且更便宜。Browser tools 適用於需要互動的場景（點擊、填表、動態內容）。

## 8. 常見錯誤與限制

- **Target closed / 崩潰**：如果在跑 Browser 時突然失敗或出現 `Target closed`，通常是記憶體不足。請確認 `.env` 中的 `HERMES_MEMORY_LIMIT` 至少設為 `4G`，且 `docker-compose.yml` 中分配了 `shm_size: 1g`。
- **文字互動限制**：Agent 依賴網頁的 Accessibility Tree（無障礙樹狀結構）來理解頁面，對於某些缺乏語意標籤的重度單頁應用程式 (SPA) 可能較難精準操作。
- **防護驗證碼**：部分嚴格的網站（如 Cloudflare 防護）可能會阻擋無頭瀏覽器。遇到此情況時，請使用 **CDP 模式**（也就是前兩節教的 TCP 轉發站）來接管你的真實 Chrome，通常能順利繞過驗證。

## 9. 相關參考

- [Hermes Browser 官方文件](https://hermes-agent.nousresearch.com/docs/user-guide/features/browser)
- [agent-browser CLI 工具](https://agent-browser.dev)
