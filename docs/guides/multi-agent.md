# Hermes Multi-Agent

Hermes Agent 支援兩種截然不同的 Multi-Agent 協作模式，分別適用於不同的使用情境：**臨時任務委派 (Delegate Task)** 與 **實體多重程序 (Spawning Instances / Profiles)**。

本文將詳細介紹這兩種模式的差異，以及如何透過 Profiles 模式建立完全獨立的代理人（例如：負責不同社群帳號的瀏覽器自動化）。

## 1. 兩種 Multi-Agent 模式比較

### 1.1 任務委派模式 (Delegate Task)

這是一種「平行運算」模式。當主 Agent 遇到龐大的任務時，可以臨時召喚多個子 Agent (Subagents) 平行處理。

- **運作方式**：在同一個 Hermes Process 內部，切割出獨立的沙盒記憶體供子 Agent 運作。
- **特點**：
  - 用完即丟，子 Agent 完成任務回報後即銷毀。
  - **限制**：所有子 Agent 繼承並共用母體的 `config.yaml`。
- **適用情境**：平行搜尋資料、大量文本分析等不需要獨立系統設定的雜事。

> [!WARNING]
> **瀏覽器自動化的限制**
> 如果你希望不同的子 Agent 控制不同的瀏覽器 Profile（不同的 CDP Port），**不能**使用 `delegate_task`。因為所有子 Agent 會共用同一個 `browser.cdp_url` 設定，導致它們互相搶奪同一個瀏覽器的控制權。

### 1.2 實體多重程序模式 (Spawning Instances / Profiles)

這是建立「完全獨立、互不干擾」的長駐機器人模式。透過 Hermes 內建的 Profile 功能，每個分身都會在 `~/.hermes/profiles/<名稱>/`（若是 Docker 部署則通常在 `/opt/data/profiles/<名稱>/`）底下擁有專屬的資料夾。

- **運作方式**：每個 Agent 都是獨立的 Process，載入各自的設定檔。
- **特點**：
  - 擁有獨立的 `config.yaml`（可設定不同的模型、CDP Port）。
  - 擁有獨立的 `sessions/` 與 `memory/`。
  - 擁有獨立的 `.env`（可設定不同的 API Key）。
- **適用情境**：專職代理人（例如：專職前端工程師、專職社群小編），或需要同時控制多個不同帳號的瀏覽器。

## 2. 實戰：建立多平台社群巡邏 Agents

假設我們有多個不同的網頁 Profile（例如登入著不同社群帳號），並希望多個獨立的 Hermes Agent 分別控制它們，且在 Discord 的不同頻道中各自回覆。

### 2.1 建立獨立 Profile

透過 `--clone` 參數，可以複製目前主帳號的基本設定來快速建立分身：

```bash
# 建立多個分身
hermes profile create agent-main --clone
hermes profile create agent-sms --clone
```

### 2.2 設定獨立的瀏覽器 CDP URL

分別修改它們各自的 `config.yaml`，讓它們對應到不同的 CDP Port。

**Agent A (agent-main)**

修改 `~/.hermes/profiles/agent-main/config.yaml`：

```yaml
browser:
  cdp_url: 'http://127.0.0.1:<Port1>'  # 對應 Google Profile 1
```

**Agent B (agent-sms)**

修改 `~/.hermes/profiles/agent-sms/config.yaml`：

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
# 開三個背景程序，讓三個 Agent 上線
hermes -p agent-main gateway run &
hermes -p agent-sms gateway run &
```

#### 透過總指揮統一發號施令

你也可以把目前的 Hermes 作為「總指揮」，透過終端機直接指派任務給這三個分身，它們會在背景各自使用自己的設定檔平行運作：

```bash
# 叫 agent-main 去做任務（-q 表示在背景跑完就結束）
hermes -p agent-main chat -q "載入 langlive-social-patrol 技能，去 Threads 巡邏並回報" &

# 叫 agent-sms 去做任務
hermes -p agent-sms chat -q "去檢查有沒有新的客訴簡訊並用小浪語氣回覆" &
```

這保證了**設定隔離**與**非同步執行**，每個 Agent 都能精準連上自己的瀏覽器，不會發生控制權衝突。
