# 瀏覽器接線架構：Hermes 怎麼接到 Mac 上的 Chrome

本文解釋 Hermes 與 OpenClaw 兩套系統如何把「Docker 容器內的 Agent」接到「Mac 主機上已登入的 Chrome」，以及為什麼當你同時部署兩者時，OpenClaw Node 會自然地補上 Hermes 缺少的那一塊。

實際操作步驟（`cdp_proxy.py`、`/browser connect`、共用 OpenClaw profile 的指令範例）放在 [瀏覽器自動化設定](browser-automation.md)，本文聚焦在「為什麼這樣設計」與「兩者怎麼搭」。

## 1. 共同問題：Docker 碰不到 Host Chrome 的 CDP

不論 Hermes 還是 OpenClaw Gateway，只要部署在 Docker 容器內，都會遇到同一個跨網段問題——「已登入 Threads / IG / Instagram 的 Chrome」跑在 Mac 主機上，但容器看不到：

- Chrome 把 CDP 綁在 Mac host 的 `127.0.0.1:<port>`。
- Docker 容器的 `127.0.0.1` 指的是容器自己，**不是 Mac**。
- Chrome 還有 DNS rebinding 防護：HTTP `Host` header 不是 `127.0.0.1` 或 `localhost` 就直接拒絕。

兩套系統用完全相反的方向解這個問題。

## 2. 兩種架構：反向通道 vs 直接連線

### 2.1 OpenClaw：Mac 主動撥出（reverse tunnel）

```text
Mac Host                            Docker
┌──────────────────────┐            ┌──────────────────┐
│ Chrome :18800        │            │                  │
│       ↑              │            │                  │
│ OpenClaw Node ───────┼─── 撥出 ──→ | OpenClaw Gateway │
└──────────────────────┘            └──────────────────┘
        ↑                                   ↑
        └─ 在 Mac 本機直接打 localhost CDP    └─ 被動接受 Node 註冊
```

[`openclaw node run`](https://github.com/kaka-lin/openclaw-server/blob/main/docs/guides/browser-control.md) 是一個常駐在 Mac 上的程序：

- 從 Mac **主動撥電話到 Docker Gateway** 註冊自己（pairing + display name）。
- 收到 Gateway 指令後，本機 `127.0.0.1:18800` 直接打到 Chrome。
- Chrome 完全不需要對外暴露 CDP，連 `--remote-debugging-address=0.0.0.0` 都不用設。

這個設計買到的東西：

- 跨 NAT / 防火牆都能用（Gateway 跑雲端、Node 在你家裡也行）。
- 多台 host 可以掛同一個 Gateway，每台 Node 有名字。
- Node 同時負責 **Chrome lifecycle 管理**：依 profile 設定啟動多個 Chrome，各自綁不同 `--user-data-dir` 與 `--remote-debugging-port`。

代價：需要常駐程序、要走 pairing 流程、終端不能關。

### 2.2 Hermes：Docker 主動撥入（direct attach）

```text
Mac Host                            Docker
┌──────────────────────┐            ┌──────────────────────────────┐
│ Chrome :18800 ←──────┼── 撥入 ────┤ cdp_proxy.py                 │
│                      │            │   listens 127.0.0.1:18800    │
│                      │            │   → 192.168.65.254:18800     │
│                      │            │             ↑                │
│                      │            │       (容器內 loopback)       │
│                      │            │             │                │
│                      │            │  Hermes Gateway              │
│                      │            │   cdp_url:                   │
│                      │            │   http://127.0.0.1:18800     │
└──────────────────────┘            └──────────────────────────────┘
```

三個關鍵點：

- **資料路徑只有 cdp_proxy.py 一個中介**：流量是 Hermes Gateway → cdp_proxy.py → 192.168.65.254 → Chrome（直連）。注意 cdp_proxy.py 只是網路層代理，不是 CDP 協定層的 agent。
- `cdp_url` 寫的是 `http://127.0.0.1:18800`，**不是** `host.docker.internal:18800` —— 後者會被 Chrome DNS rebinding 拒絕。
- **安全模型靠網路隔離而非認證**：CDP 本身幾乎無認證，任何能進入 Hermes 容器或 Mac 本機的程序都能控制 Chrome。OpenClaw 的 `devices approve` pairing 在這條路徑沒有對應物。

Hermes 把問題外包給 Docker 網路層：

- 你給它一個 `cdp_url`，它就用標準 CDP（WebSocket）撥過去。
- Docker Desktop 預留 `192.168.65.254`（等同 `host.docker.internal`）讓容器反查 host。
- 為了繞過 Chrome 的 DNS rebinding 防護，Hermes 在容器內額外起一個 [`cdp_proxy.py`](../../scripts/cdp_proxy.py) —— 它是個**純 TCP byte forwarder**，在容器內 `127.0.0.1:<port>` 開 listener，把流量原封不動轉到 `192.168.65.254:<port>`。
- 這樣 CDP client 連到 `127.0.0.1:<port>` 時，送出的 HTTP `Host` header 自然就寫 `127.0.0.1:<port>`，Chrome 的 DNS rebinding 檢查直接放行——proxy 不用改寫任何封包內容。
- `cdp_proxy.py` 由 docker-compose 在容器啟動時一併拉起（`python3 .../cdp_proxy.py & exec hermes gateway run`），並讀取 `scripts/host/browsers.conf`——與 host 端 `start-browsers.sh` 共用同一份 port 清單，會為 conf 裡每個 port 各開一條轉發，無需手動逐一指定。

買到的東西：簡單，沒有 daemon、沒有 pairing。
代價：對網路拓樸有要求（基本上只適合本機或內網），CDP 本身幾乎沒做認證。

## 3. Hermes 沒有等價的 Node

這是本文的重點：**Hermes 完全沒有對應 OpenClaw Node 的元件**。它把 Chrome 的啟動與生命週期管理外包給使用者。

| Hermes 的東西 | 為什麼不是 Node |
| --- | --- |
| `agent-browser` CLI | 只能起一個全新乾淨的 Chromium（Chrome for Testing），不會繼承你的登入狀態，也不管多 profile。 |
| `cdp_proxy.py` | 只是繞過 DNS rebinding 的 TCP 轉發站，不啟動 Chrome、不管多實體。 |
| `/browser connect` | runtime 切換指令，不是常駐服務。 |
| `browser.cdp_url` 設定 | 單一字串，不支援多 endpoint 同時掛載。 |
| Camofox `managed_persistence` | 是 Firefox + 反偵測，不是 Chrome；走 Camofox 自己的 server，不是 CDP。 |

換句話說，當你想「在 Hermes 中操控已登入的 Mac Chrome」時，所有 Chrome 啟動參數（`--user-data-dir`、`--remote-debugging-port`、多 profile 隔離、process 重啟）都得自己準備。

## 4. 實用組合：用 OpenClaw Node 當 Hermes 的 Chrome lifecycle manager

如果你**同時部署了 [openclaw-server](https://github.com/kaka-lin/openclaw-server)**，最直接的做法是讓 OpenClaw Node 補上 Hermes 缺的這塊，Hermes 只負責當 CDP client。但這個組合也有 lazy-load 與 auto-fallback 兩個陷阱（後面 4.2 與 4.5 兩節會說明），決定要不要用之前先看完。

### 4.1 實際架構

```text
Mac Host
┌──────────────────────────────────────────────────────┐
│  OpenClaw Node (parent / supervisor)                 │
│      │ spawn (lazy)                                  │
│      ├─► Chrome [openclaw]     :18800                │
│      ├─► Chrome [helper]       :9223   ← Chrome      │
│      └─► Chrome [assistant]    :9224   ← 自己 bind    │
└──────────────────────────────────────────────────────┘
                   ▲
                   │ cdp_proxy.py (容器內) byte-forward
                   │ 127.0.0.1:<port> → 192.168.65.254:<port>
┌──────────────────┴───────────────────────────────────┐
│  Hermes Container                                    │
│    cdp_url: http://127.0.0.1:18800                   │
└──────────────────────────────────────────────────────┘
```

關鍵事實：

- **Chrome 自己 bind CDP port**：`lsof -iTCP:18800 -sTCP:LISTEN` 顯示 listener 是 `Google Chrome` 程序本身，不是 Node。Chrome 的啟動參數是 `--remote-debugging-port=18800 --user-data-dir=~/.openclaw/browser/<profile>/user-data`。
- **Node 是 Chrome 的父程序**：Chrome 的 PPID 指向 `openclaw-node`。Node 在背景當 supervisor，不參與 CDP 流量。
- **資料路徑不經過 Node**：Hermes 的 CDP 流量是 `Hermes Gateway → cdp_proxy.py → 192.168.65.254 → Chrome`，直接打到 Chrome，Node 不在路徑上。
- **但 Chrome 的存活綁定在 Node 上**：殺掉 Node（`Ctrl+C`）時，所有子 Chrome 也跟著終止；Hermes 此時會看到 `Read timed out`。所以對 Hermes 來說 Node **仍然是必要前提**。

OpenClaw 端的 profile 設定（[OpenClaw Browser Profiles 設定](https://github.com/kaka-lin/openclaw-server/blob/main/docs/guides/browser-profiles-config.md)）：

```json
"browser": {
  "defaultProfile": "openclaw",
  "profiles": {
    "openclaw":   { "cdpPort": 18800, "color": "#FF4500" },
    "helper":     { "cdpPort": 9223, "color": "#00AAFF" },
    "assistant":  { "cdpPort": 9224, "color": "#FF1493" }
  }
}
```

每個 profile 的 user-data-dir 預設在 `~/.openclaw/browser/<profile-name>/user-data/`，這是 Threads / IG 登入狀態實際存放的位置。

Hermes 端只要設定其中一個 port 當作預設：

```yaml
browser:
  cdp_url: http://127.0.0.1:18800
```

OpenClaw 在這個組合裡退化成「**多 profile 的 Chrome supervisor（lazy-load）**」：

- 被觸發時把 Chrome 帶上正確的 `--user-data-dir` 與 `--remote-debugging-port` 起來，並維持父子程序關係。

### 4.2 Lazy-load 行為

**OpenClaw 是完全的 lazy-load**：`openclaw node run` 啟動時不會起任何 Chrome，**連預設 profile 也不會**。log 只會顯示：

```text
🦞 OpenClaw 2026.4.15 — ...
[browser/service] Browser control service ready (profiles=4)
```

直到你透過 OpenClaw CLI / UI 對某個 profile 下指令，對應的 Chrome 才會被 spawn：

```text
[browser/chrome] openclaw browser started (chrome) profile "openclaw" on 127.0.0.1:18800 (pid 4697)
```

**這對 Hermes 是個陷阱**：Hermes 在 Docker 容器內，**無法主動 spawn Mac 上的 process**（容器隔離的根本限制）。如果你想叫 Hermes 用 `helper`，但這個 profile 還沒被 OpenClaw 喚醒，Hermes 撥到 9223 只會 `Connection refused`。

解法擇一：

1. 使用前**先在 OpenClaw 戳一下要用的 profile** 讓它點火。
2. 寫一個 eager launcher 取代 OpenClaw，所有 profile 一啟動就 ready（見 [什麼時候可以不用 OpenClaw Node](#5-什麼時候可以不用-openclaw-node)）。

### 4.3 多 profile 在 Hermes 的限制與切換

啟動 Hermes 你會看到 log 為每個 host port 各印一行 `Proxy listening on 127.0.0.1:<port> -> 192.168.65.254:<port>`——這只是 [`cdp_proxy.py`](../../scripts/cdp_proxy.py) 預先把網路通道架好。**`cdp_url` 仍是單一字串**，所以同一個 Hermes session 任何時刻只 attach 一個 profile。三種使用模式：

1. **Runtime 切換**（CLI 互動模式）：

    ```text
    /browser connect ws://127.0.0.1:9223     # 切到 helper
    /browser connect ws://127.0.0.1:9224     # 切到 assistant
    ```

    > 限制：`/browser connect` **不能**在 Discord / Telegram gateway 模式使用。

2. **讓 Agent 自己處理**（推薦，gateway 模式可用）：

    Agent 能讀取 `openclaw.json`，自動解析 profile 對應的 port 並切換。直接在 Discord / Telegram 對 Hermes 說：

    ```text
    請用 helper profile 開 https://threads.net
    ```

    詳見 [共用 OpenClaw Browser Profiles](browser-automation.md#6-共用-openclaw-browser-profiles)。

3. **真正並行**：開多個 Hermes 容器，每個 `cdp_url` 指不同 port，各自接不同 channel（Telegram bot A、Discord bot B、Slack bot C）。代價是 LLM 配額與記憶體 ×N。

### 4.4 Hermes 自動退回內部 headless 的陷阱

當 Hermes 連不到設定的 `cdp_url`（例如對應 profile 還沒被 OpenClaw 喚醒、或 OpenClaw Node 整個掛了），它**不會回報錯誤**，而是悄悄用 `agent-browser` CLI 在容器內起一個全新的 headless Chromium 來完成任務。後果：

- Mac 桌面**看不到任何視窗**（因為 Chrome 在 Docker 容器內 headless）。
- Agent 抓到的網頁是**未登入版本**，因為容器內 Chromium 跟你 Mac 上的 Chrome 是完全獨立的兩個實體，session / cookies 不會共享。
- 你問「你看到什麼？」時 agent 會給出畫面內容，但那不是你以為的那個瀏覽器。

辨識方式：

- Hermes log 看到類似 `Local Chromium browser session started` / `agent-browser` 字樣 → fallback 觸發了。
- Mac 上 `lsof -iTCP:<port> -sTCP:LISTEN` 沒輸出 → 對應 Chrome 沒在跑，Hermes 一定走 fallback。

避免方式：操作前確認對應 profile 的 Chrome 已被 OpenClaw 喚醒（看 OpenClaw log 是否有 `openclaw browser started` 對應那個 profile，或用 `lsof` 直接驗證）。

## 5. 什麼時候可以不用 OpenClaw Node

> [!IMPORTANT]
> **拿掉 Node = 拋棄 OpenClaw 自己的 browser 能力。** OpenClaw 的 `browser` 工具綁死走 Gateway → Node → Chrome 這條反向通道。一旦你殺掉 Node 改用 launcher script eager-spawn Chrome：
>
> - ✅ Hermes 仍能正常工作（直接撥 CDP，本來就沒用到 Node 的反向通道）。
> - ❌ OpenClaw 自己的 Control UI / 接的 Channel 操作 browser 會壞掉（Gateway 找不到 Node 就無法觸及 Chrome，即使 Chrome 還在跑）。
>
> 換句話說，這個方案適合「**只用 Hermes 操作 browser**」的人。若你還會透過 OpenClaw 的介面操作 browser，請保留 Node 走「先戳 OpenClaw 喚醒 profile」那條路。

如果你的需求滿足以下條件，可以考慮拿掉 OpenClaw：

- 只透過 Hermes 操作 browser，不用 OpenClaw 自己的 browser 工具。
- 希望所有 profile **一啟動就 ready**，不要 OpenClaw 的 lazy-load。
- 願意自己處理 Chrome 啟動參數與 supervisor 角色（process crash 不會自動拉起）。
- 不需要 OpenClaw 的 pairing、UI、跨網段功能。

OpenClaw 的「魔法」其實只是 `chrome --remote-debugging-port=N --user-data-dir=PATH`。實測你的 Chrome 啟動參數長這樣：

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=18800 \
  --user-data-dir=~/.openclaw/browser/openclaw/user-data \
  --no-first-run ...
```

本專案內建這支腳本：[`scripts/host/start-browsers.sh`](../../scripts/host/start-browsers.sh)。Profile 與 port 對應寫在同目錄的 `browsers.conf`（純文字，每行 `port:profile_name`）。

`browsers.conf` 是 host 端 `start-browsers.sh` 與容器內 [`cdp_proxy.py`](../../scripts/cdp_proxy.py) **共用的單一 port 來源**：start-browsers.sh 依它啟動 Chrome、cdp_proxy.py 依它架轉發，兩邊永遠對齊。慣例上**第一個 entry 當 main agent**（`config.yaml` 的 `cdp_url` 指向它），其餘留給 sub-agent 在 runtime 用 `/browser connect` 或讓 agent 自行切換：

```text
9222:main
9223:helper
9224:assistant
```

> [!NOTE]
> 註解（`#` 開頭）與空行會被忽略，但**不支援行內註解**——`port:name` 後面別接 `#`，否則 profile name 會把整段註解吃進去（`start-browsers.sh` 與 `cdp_proxy.py` 的解析方式相同）。

第一次使用先複製範本：

```bash
cp scripts/host/browsers.conf.example scripts/host/browsers.conf
# 編輯 browsers.conf 改成你自己的 port/profile
```

```bash
# 啟動所有 profile
./scripts/host/start-browsers.sh
./scripts/host/start-browsers.sh start    # 同上，顯式寫法

# 看誰 listen
./scripts/host/start-browsers.sh status

# 全部關掉（不用記 pkill 指令）
./scripts/host/start-browsers.sh stop

# 重啟
./scripts/host/start-browsers.sh restart
```

特性：

- **Idempotent**：已 listen 的 port 跳過，不會重複 spawn。
- **Polling**：`start` 會等到 Chrome 真的 bind port 才回報 `[ok]`，最多 15 s/port。
- **Stop 精準**：用 `pgrep -f "remote-debugging-port=<port>"` 只殺對應的 Chrome，不會誤殺其他 Chrome 實體。
- **Profile 可改**：編輯 `browsers.conf`，或設 `BROWSERS_CONFIG=/path/to/other.conf` 換不同 set。
- **資料目錄可改**：profile 的 user-data-dir 預設在 `~/.hermes/browser/<profile>/user-data`（Hermes 自己的 namespace，全新 profile 第一次需手動登入）。要沿用 OpenClaw 既有 profile 的登入狀態，把 script 開頭的 `DATA_DIR` 改成 `~/.openclaw/browser`。

腳本實際下的指令長這樣（每個 profile 各一個）：

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=18800 \
  --user-data-dir="$HOME/.hermes/browser/<profile>/user-data" \
  --no-first-run \
  --no-default-browser-check \
  --remote-allow-origins='*' &
```

關鍵 flag：

- `--remote-debugging-port=N` / `--user-data-dir=PATH`：對應 profile 的 CDP port 與資料目錄。預設根目錄是 `~/.hermes/browser`（Hermes 自己的 namespace，全新 profile 第一次需手動登入）；若想沿用 OpenClaw 既有 profile 保留登入狀態，把 script 開頭的 `DATA_DIR` 改成 `~/.openclaw/browser`。
- `--no-first-run`：跳過首次啟動精靈。實測 OpenClaw 也帶這個。
- `--no-default-browser-check`：跳過「要設為預設瀏覽器嗎」對話框。
- `--remote-allow-origins='*'`：Chrome 111+ WebSocket CDP 連線會驗 `Origin` header，不帶可能被擋。

Chrome 在腳本退出後會被 launchd 接管繼續活著，關終端機不會掛——只有登出 / reboot 或執行 `stop` 才會結束。

兩個模式下，**誰能用 browser**：

| | OpenClaw Node 模式 | 自寫 launcher script 模式 |
| --- | --- | --- |
| **OpenClaw**（Control UI / 接的 Channel） | ✓ | ✗（沒了 Node，Gateway 撥不到 Chrome） |
| **Hermes** | ✓ 但 profile 需先被 OpenClaw 喚醒；否則走 internal headless fallback | ✓ 所有 profile eager 起來就 ready |

其他運維差異（不影響 browser 能不能用，但影響怎麼維護）：

- **啟動策略**：Node = lazy（被觸發才 spawn）／launcher = eager（一執行就全開）。
- **Process supervisor**：Node 自帶（kill Node 連帶 cleanup 子 Chrome）／launcher 沒有，要自己用 launchd plist / pm2 補。
- **多 profile UI / pairing / 跨網段**：Node 提供／launcher 無。

只要你有兩個以上 profile **且**會頻繁切換，自寫 launcher 反而比 OpenClaw 順手；單一 profile 場景則用什麼都差不多。

## 6. 延伸閱讀

- [瀏覽器自動化設定](browser-automation.md)：本機 / 雲端 / CDP / Camofox 四種 backend 的實際設定步驟。
- [OpenClaw 瀏覽器控制完整指南](../../../openclaw-server/docs/guides/browser-control.md)：在 Mac 上啟動 Node、pairing、批准連線的完整流程。
- [OpenClaw Browser Profiles 設定](../../../openclaw-server/docs/guides/browser-profiles-config.md)：多 profile / 固定 Port 綁定。
- [Hermes Browser 官方文件](https://hermes-agent.nousresearch.com/docs/user-guide/features/browser)
