# Hermes Agent DingTalk 整合指南

這份文件說明如何將 Hermes Agent 設定為 DingTalk (釘釘) 聊天機器人。機器人透過 DingTalk 的 Stream Mode (Stream 模式) 連線，無需公開的 webhook URL 或伺服器，並使用 DingTalk 的 session webhook API 進行回覆，支援 Markdown 格式的訊息。

## 1. 預設行為與機制

- **DM 私訊**：每個私訊對話都會建立獨立的 session。
- **群組聊天**：預設情況下，群組內的使用者在與機器人對話時，每個人都會有各自獨立的 session，並不會共享整個群組的對話上下文。

這可以在 `config.yaml` 中透過以下設定來控制：

```yaml
group_sessions_per_user: true
```

如果希望整個群組共享同一個對話上下文，請將此值設為 `false`。

## 2. 系統需求與套件安裝

在開始之前，請確保已經安裝所需的 Python 套件：

```bash
pip install "hermes-agent[dingtalk]"
```

或者可以手動安裝個別依賴套件：

```bash
pip install dingtalk-stream httpx alibabacloud-dingtalk
```

- `dingtalk-stream`：DingTalk 官方 Stream 模式 SDK（基於 WebSocket 的即時通訊）。
- `httpx`：用於發送非同步 HTTP 請求的客戶端（透過 session webhooks 發送回覆）。
- `alibabacloud-dingtalk`：DingTalk OpenAPI SDK，用於支援 AI 卡片、表情符號回應和媒體下載功能。

## 3. 設定步驟

### 3.1 步驟一：建立 DingTalk 應用程式

1. 前往 [DingTalk 開發者後台](https://open-dev.dingtalk.com/)。
2. 使用你的 DingTalk 管理員帳號登入。
3. 點選 **Application Development** (應用開發) -> **Custom Apps** (企業內部開發) -> 透過 **H5 微應用** (H5 Micro-App) 或是 **機器人** (Robot) 來建立應用程式（視你的後台版本而定）。
4. 填寫應用程式資訊：

    - **App Name**：例如 `Hermes Agent`
    - **Description**：選填

5. 建立完成後，前往 **Credentials & Basic Info** (憑證與基礎資訊) 尋找你的 `Client ID` (AppKey) 和 `Client Secret` (AppSecret)。請將這兩個值複製下來。

    > [!WARNING]
    > `Client Secret` 僅在建立應用程式時顯示一次。如果遺失，必須重新產生。請勿將這些憑證公開或提交至 Git 儲存庫。

### 3.2 步驟二：啟用機器人能力

1. 在應用程式設定頁面中，前往 **Add Capability** (新增能力) -> **Robot** (機器人)。
2. 啟用機器人能力。
3. 在 **Message Reception Mode** (訊息接收模式) 中，選擇 **Stream Mode** (Stream 模式)。這也是官方推薦的方式，無需公開的 URL 即可運作。

### 3.3 步驟三：版本管理與發布

為了讓組織內的其他使用者能夠搜尋到該機器人並將其加入群組，必須將應用程式發布上線：

1. 在左側選單進入 **Version Management & Release** (版本管理與發布)。
2. 點選 **Create New Version** (建立新版本)，填寫版本號與更新說明。
3. 儲存後，點選 **Publish** (發布) 即可上線。

### 3.4 步驟四：取得 DingTalk 使用者 ID

Hermes Agent 會使用你的 DingTalk 使用者 ID 來限制誰可以與機器人互動。你可以透過以下兩種方式取得：

1. 詢問組織管理員：可以在管理後台的 **Contacts -> Members** 找到。
2. 透過日誌：啟動 Hermes gateway 並發送訊息給機器人，接著在終端機日誌中尋找 `sender_id`。

### 3.5 步驟五：設定 Hermes Agent

你可以選擇互動式設定或是手動設定。

#### 選項 A：互動式設定（推薦）

執行官方的設定腳本，按照終端機提示選擇 **DingTalk**，並完成授權。

- **原生 Local 環境**：
  直接在終端機輸入以下指令：

  ```bash
  hermes gateway setup
  ```

- **Docker 環境**：
  在 `docker-compose.yml` 所在目錄執行，透過 Compose 啟動一次性互動容器（會走 entrypoint 自動切換到 `hermes` 使用者並啟用 venv，設定會寫入掛載的資料卷）：

  ```bash
  docker compose run --rm hermes gateway setup
  ```

  > 💡 **提示**：設定完成後，請重新啟動主容器以套用變更：`docker compose restart hermes`。

設定精靈提供兩種授權方式：

- **QR-code 掃描**（推薦）：在終端機列印出 QR code，使用 DingTalk App 掃描授權。
- **手動輸入**：手動貼上 `Client ID`、`Client Secret` 和允許的使用者 ID。

#### 選項 B：手動設定

在 `~/.hermes/.env` (或專案的 `.env`) 中加入以下設定：

```env
# 必要設定
DINGTALK_CLIENT_ID=your-app-key
DINGTALK_CLIENT_SECRET=your-app-secret

# 安全性：限制可與機器人互動的使用者 ID（多個使用者可使用逗號分隔）
DINGTALK_ALLOWED_USERS=user-id-1,user-id-2

# 選擇性設定：群組聊天限制
# DINGTALK_REQUIRE_MENTION=true
# DINGTALK_FREE_RESPONSE_CHATS=cidABC==,cidDEF==
# DINGTALK_MENTION_PATTERNS=^小马
# DINGTALK_HOME_CHANNEL=cidXXXX==
# DINGTALK_ALLOW_ALL_USERS=true
```

在 `~/.hermes/config.yaml` (或專案的 `config.yaml`) 中的平台行為設定：

```yaml
gateway:
  platforms:
    dingtalk:
      extra:
        # 在群組中是否需要被 @ 提及才回覆
        require_mention: true
        # 平台專屬的允許名單 (與 .env 的 DINGTALK_ALLOWED_USERS 合併)
        allowed_users:
          - user-id-1
          - user-id-2
```

## 4. 啟動 Gateway

完成設定後，依照部署方式啟動或重啟 DingTalk gateway：

- **原生 Local 環境**：

  ```bash
  hermes gateway
  ```

- **Docker 環境**：

  ```bash
  docker compose restart hermes
  ```

機器人應會在幾秒內透過 Stream 模式連上 DingTalk。你可以透過私訊或群組發送訊息來測試連線。

## 5. 功能支援與進階設定

### 5.1 AI 卡片 (AI Cards)

Hermes 支援使用 DingTalk 的 AI 卡片來取代純 Markdown 回覆，提供更結構化的顯示方式，並且在生成時支援串流更新。

要啟用 AI 卡片，請在 `config.yaml` 中設定卡片範本 ID (可以在開發者後台的 AI 卡片設定中找到)：

```yaml
platforms:
  dingtalk:
    enabled: true
    extra:
      card_template_id: "your-card-template-id"
```

### 5.2 表情符號回應 (Emoji Reactions)

Hermes 會自動加上表情符號回應以顯示處理狀態：

- 🤔 Thinking (思考中)：機器人開始處理訊息時加入。
- 🥳 Done (完成)：回覆完成後加入（會取代思考中的符號）。

### 5.3 顯示設定 (Display Settings)

你可以針對 DingTalk 平台自訂顯示行為：

```yaml
display:
  platforms:
    dingtalk:
      show_reasoning: false # 顯示模型的推理思考過程
      streaming: true # 啟用串流回應 (與 AI 卡片一起使用)
      tool_progress: all # 顯示工具執行進度 (all/new/off)
      interim_assistant_messages: true # 顯示中間的註釋/過渡訊息
```

如果要隱藏工具進度和中間訊息以保持乾淨的體驗，可設定為：

```yaml
display:
  platforms:
    dingtalk:
      tool_progress: off
      interim_assistant_messages: false
```

### 5.4 主動通知與 Cron 任務 (Home Channel)

若要讓 Cron Jobs 執行完成後將結果主動傳送到 DingTalk，請在 `.env` 設定目標 ID：

```bash
DINGTALK_HOME_CHANNEL="cidXXXX==" # 預設通知對象的群組 ID (Conversation ID)
```

> 💡 **提示**：DingTalk 發送主動通知是透過官方的 OpenAPI 直接發起請求，因此**完全不需要**像 LINE 一樣架設公開的 Webhook 隧道 (不需使用 ngrok 或 cloudflared)。

### 5.5 Multi-Agent 背景分身與主動推播 (Webhook 模式)

當透過 `dispatch-agent` 等技能在背景喚醒一個分身（CLI 模式）去執行任務時，該分身由於獨立執行且沒有持續連線的 WebSocket，也沒有使用者訊息帶來的「臨時 session webhook」，因此**無法透過 Gateway 的機制來回覆**。

為了解決這個問題，背景分身在執行 `send_message` 工具時，會依賴你在 `.env` 中設定的自定義機器人 Webhook URL 來對指定群組進行**單向盲發**：

```bash
# 用於特定群組的「自定義機器人」單向廣播
# 我們扮演 Client 端主動呼叫釘釘 API，不需架設 Webhook 伺服器
DINGTALK_WEBHOOK_URL="https://oapi.dingtalk.com/robot/send?access_token=..."
```

> 💡 **提示**：這是釘釘官方的「自定義群組機器人」功能。你只需要在目標群組的設定中新增自定義機器人並獲取這串 URL 即可。這與 Gateway 的雙向回覆機制是獨立且並存的功能，**專門用於解決 Multi-Agent 架構下缺乏對話上下文的主動回報問題**。

## 6. 常見問題與除錯 (Troubleshooting)

### 機器人沒有回應訊息

- **原因**：尚未啟用機器人能力，或 `DINGTALK_ALLOWED_USERS` 未包含你的使用者 ID。
- **解決方案**：確保應用程式設定中啟用了機器人能力，並且使用 Stream 模式。檢查 `DINGTALK_ALLOWED_USERS` 是否設定正確，然後重啟 gateway。

### 出現 "dingtalk-stream not installed" 錯誤

- **原因**：缺少 `dingtalk-stream` 套件。
- **解決方案**：執行 `pip install dingtalk-stream httpx` 進行安裝。

### 出現 "DINGTALK_CLIENT_ID and DINGTALK_CLIENT_SECRET required"

- **原因**：`.env` 環境變數未正確設定。
- **解決方案**：確保 `DINGTALK_CLIENT_ID` (AppKey) 和 `DINGTALK_CLIENT_SECRET` (AppSecret) 已正確設定。

### Stream 斷線或不斷重連

- **原因**：網路不穩定、DingTalk 維護或憑證問題。
- **解決方案**：系統會自動以指數退避演算法 (2s -> 5s -> 10s...) 進行重連。請檢查憑證是否有效，並確認網路環境允許對外建立 WebSocket 連線。

### 出現 "No session_webhook available"

- **原因**：機器人試圖回覆，但缺乏 session webhook URL。這通常發生在 webhook 逾時，或是機器人在收到訊息後與回覆期間重新啟動。
- **解決方案**：重新發送一則新的訊息給機器人。

## 7. 其他注意事項

- **Stream 模式**：無須公開 URL，連線由你的機器主動發起。
- **支援 Markdown 與媒體檔案**：回覆使用 DingTalk Markdown 格式，並且支援視覺工具來解析傳入的圖片和檔案。
- **訊息長度限制**：每則回覆上限為 20,000 字元，超出的部分會被截斷。
- **自動去重**：Adapter 會在 5 分鐘的視窗內處理訊息去重，防止重複回應。
