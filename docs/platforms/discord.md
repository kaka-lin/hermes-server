# 🦅 Hermes Agent Discord 全功能安裝與配置指南

本指南說明如何將 Hermes Agent 透過內建的 Messaging Gateway 連接至 Discord 平台。

> **文件版本資訊**：本指南依據 [Hermes Agent 官方 Gateway 文件](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord) 整理。

## 1. 第一階段：Discord 開發者後台 (準備工作)

1. **建立 App**：前往 [Discord Developer Portal](https://discord.com/developers/applications) -> New Application，輸入名稱並建立。
2. **獲取 Bot Token**：

    - 在左側選單進入「Bot」頁面。
    - 在「Authorization Flow」區塊，將 **Public Bot** 設為 **ON** (強烈建議，為了後續產生邀請連結)，**Require OAuth2 Code Grant** 保持 **OFF**。
    - 點擊 `Reset Token`，取得機器人的金鑰，**請妥善保存，後續無法再次查看**。
3. **開啟特權 (Intents)**：在同一個「Bot」頁面向下捲動找到「Privileged Gateway Intents」區塊，請務必開啟以下特權：

    - **Message Content Intent (必開)**：讓 Agent 能夠讀取頻道內的訊息內容，若未開啟，機器人會收到空訊息而完全無法回覆。
    - **Server Members Intent (必開)**：讓 Agent 能夠讀取伺服器內的成員資訊，用來驗證白名單 (`DISCORD_ALLOWED_USERS`) 中的使用者。

4. **產生邀請連結並將機器人加入伺服器**：
    點擊左側選單的 `Installation`。

    - 在「Installation Contexts」啟用 `Guild Install`。
    - 在「Install Link」選擇 `Discord Provided Link`。
    - 設定「Default Install Settings for Guild Install」：
      - **Scopes**：選擇 `bot` 與 `applications.commands` (讓 Hermes 的 Skills 支援斜線指令)。
      - **Permissions**：至少需勾選 `View Channels`, `Send Messages`, `Embed Links`, `Attach Files`, `Read Message History`。建議可額外勾選 `Send Messages in Threads`, `Add Reactions`。
    - 複製上方產生的網址，在瀏覽器中打開並將機器人加入你的伺服器。

5. **獲取 Discord User ID**：
    Hermes 預設透過 User ID 來控制誰可以使用機器人。

    - 在 Discord 應用程式中，前往「使用者設定 (齒輪圖示)」 -> 「進階 (Advanced)」 -> 開啟「開發者模式 (Developer Mode)」。
    - 對著自己的名字點擊右鍵 -> 「複製使用者 ID (Copy User ID)」。

## 2. 第二階段：設定 Hermes Gateway 並啟動

Hermes 主要透過 `~/.hermes/.env` 來進行 Gateway 設定 (在 Docker 中則對應至掛載的目錄設定)。

### 方法 A：互動式設定 (官方推薦)

執行官方的設定腳本，按照終端機提示選擇 Discord，並貼上 Token 與 User ID。

- **原生 Local 環境**：
  直接在終端機輸入以下指令：

  ```bash
  hermes gateway setup
  ```

- **Docker 環境**：
  直接進入已經在運行的 Hermes 容器內執行：

  ```bash
  docker exec -it hermes hermes gateway setup
  ```

  > 💡 **提示**：設定完成後，請重新啟動容器以套用變更：`docker compose restart hermes`。

### 方法 B：手動配置 (.env 與 config.yaml)

Hermes 支援兩種手動設定檔，皆存放於主機的掛載目錄中 (預設為 `~/.hermes/`)。您可以依據屬性分開設定：

1. **修改 `.env` 檔案 (推薦存放 Token 機密)**：
    直接編輯 `.env`，加入以下基本權限設定：

    ```bash
    # 必填項目
    DISCORD_BOT_TOKEN="你的_BOT_TOKEN"
    DISCORD_ALLOWED_USERS="你的_USER_ID"
    # 若允許多人使用，可用逗號分隔：DISCORD_ALLOWED_USERS="ID1,ID2"
    ```

2. **修改 `config.yaml` (推薦存放結構化行為設定)**：
    您可以將專案內的 `config.example` 複製一份為 `config.yaml`，官方文件指出 `config.yaml` 內的 `discord` 區塊參數完全對應 `.env` 變數 (例如 `free_response_channels` 就是 `DISCORD_FREE_RESPONSE_CHANNELS`)，非常適合用來管理行為邏輯。

    ```yaml
    discord:
      require_mention: true
      
      # 支援原生 YAML List 格式，方便管理多個頻道
      free_response_channels: 
        - "1498601986994733066"  # 頻道A
        - "1498601986994733067"  # 頻道B
      
      ignored_channels:
        - "987654321098765432"   # 忽略頻道
    ```

    > 💡 **權重規則**：如果同一個設定同時存在於 `.env` 跟 `config.yaml` 中，系統永遠會以 `.env` 的設定為主！

3. **啟動或重啟 Hermes 服務**：
    存檔後，讓系統重新載入設定。

    - **原生 Local 環境**：

      ```bash
      hermes gateway
      ```

    - **Docker 環境**：

      ```bash
      docker compose restart hermes
      ```

## 3. 第三階段：進階 - 頻道行為與 Session 模型

Hermes 在 Discord 中的運作並非簡單的 Webhook，而是完整的 Gateway，因此有其特殊的對話邏輯：

1. **觸發回覆邏輯 (Mention vs Free Response)**：

    - **預設狀態**：機器人只會在被 `@標註` 時才會回覆 (`DISCORD_REQUIRE_MENTION=true`)。
    - **免標註頻道**：若希望機器人在特定頻道能直接回覆任何人，可在 `.env` (或 `config.yaml`) 中設定 `DISCORD_FREE_RESPONSE_CHANNELS="頻道ID"`。
      > 💡 **多頻道設定**：若在 `.env`，請用逗號分隔如 `"ID1,ID2"`。若在 `config.yaml` 中設定，支援原生的 YAML List 格式 (例如 `- "ID1"` 換行 `- "ID2"`)。

2. **對話隔離 (Session Model)**：
    這是 Hermes 的一大特色。預設情況下 (`group_sessions_per_user: true`)：

    - 每一個私訊 (DM) 都是獨立的 Session。
    - **在同一個公開頻道內，不同使用者的對話是各自獨立的**。Alice 跟 Bob 即使在同一個 `#research` 頻道跟機器人講話，機器人也會將他們視為兩個不相干的對話。
    - 若希望整個頻道「共用」同一個上下文，需要在 `config.yaml` 中將 `group_sessions_per_user` 設為 `false`。

3. **斜線指令 (Skills 自動對接)**：
    Hermes 會將內部安裝的 Skills 自動註冊為 Discord 的斜線指令 (`/`)。在頻道中輸入 `/`，Discord 的自動選單就會列出 Hermes 目前支援的工具與指令。

4. **設定 Home Channel (主頻道)**：
    Home Channel 是 Hermes 用來發送背景任務結果 (例如 Cron Jobs 執行結果) 或跨平台通知的預設地點。若未設定，啟動時會在終端機或日誌看到警告 (`No home channel is set for Discord...`)。

    - **方法一 (使用斜線指令)**：直接在你想指定的伺服器頻道或私訊中，輸入斜線指令 `/sethome`。
      > 💡 **運作機制**：透過指令設定的結果，Hermes 系統底層會自動將變數存入 `config.yaml` 中，不須重啟即刻生效。
    - **方法二 (手動配置)**：直接編輯主機上的 `.env` 檔案，加入以下設定：

      ```bash
      DISCORD_HOME_CHANNEL="你的頻道ID"
      DISCORD_HOME_CHANNEL_NAME="#bot-updates" # 選填
      ```

      > 💡 **權重規則**：根據官方文件，`.env` 的變數優先級**大於** `config.yaml`。如果您同時在 `.env` 寫死了 ID，那麼不論你在 Discord 內如何使用 `/sethome`，系統都會強制以 `.env` 為主。

## 4. 底層運作邏輯

與一般的 Discord Bot 或 OpenClaw 相比，Hermes 的 Gateway 會經過完整的授權管道：

1. 驗證權限 (`DISCORD_ALLOWED_USERS`)。
2. 檢查觸發條件 (是否被標註、是否在免標註頻道)。
3. 查找對應的 Session。
4. 執行 Hermes Agent 核心功能 (Tools, Memory 等)。
5. 將結果送回 Discord。

這樣確保了 Agent 不論在哪個通訊平台，都保有一致的安全性與記憶管理機制。
