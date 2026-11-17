# Discord

gateway 用 bot token 連上 Discord，不需要公開的 URL。這裡是在本專案接上 Discord 的步驟；需要更多細節時可參考[官方 Discord 文件][official]。

## 每個 profile 一個 bot

一個容器的 gateway 會帶起 home 底下所有 profile，每個 profile 讀自己的 `.env`：

- default profile：`<data dir>/.env`
- 其他 profile：`<data dir>/profiles/<名稱>/.env`

每個 profile 要有**自己的** Discord application 與 bot token。同一組 token 不能給兩個 profile，也不能給兩個容器；要再加一個 bot，就在 Developer Portal 再建一個 application。profile 與 home 的關係見 [Agent、Home 與 Profile](../agents-and-profiles.md)。

## 建立 bot

1. 到 [Discord Developer Portal](https://discord.com/developers/applications) 按 **New Application**。
2. 進 **Bot** 頁：
    - **Public Bot** 設為 ON（Discord 產生的邀請連結需要它），**Require OAuth2 Code Grant** 保持 OFF。
    - 按 **Reset Token** 複製 token，它只顯示一次。
3. 在同一頁的 **Privileged Gateway Intents** 打開：
    - **Message Content Intent**：必開，沒開的話 Discord 會拒絕連線。
    - **Server Members Intent**：用使用者名稱或角色做白名單時需要。
4. 進 **Installation** 頁產生邀請連結：
    - **Installation Contexts** 勾 `Guild Install`，**Install Link** 選 `Discord Provided Link`。
    - **Scopes** 選 `bot` 與 `applications.commands`。
    - **Permissions** 至少勾 `View Channels`、`Send Messages`、`Embed Links`、`Attach Files`、`Read Message History`；建議再加 `Create Public Threads`、`Send Messages in Threads`、`Add Reactions`。
5. 用邀請連結把 bot 加進伺服器，你要在該伺服器有 Manage Server 權限。
6. 在 Discord 用戶端的 **使用者設定 → 進階** 打開 **開發者模式**，對自己的名字按右鍵 **複製使用者 ID**；頻道 ID 也用同樣方式複製。

## 填設定

### `.env`

編輯該 profile 的 `.env`，至少填 token 和白名單：

```bash
DISCORD_BOT_TOKEN=<bot token>
DISCORD_ALLOWED_USERS=<你的 user ID>   # 多個用逗號分隔
```

常用的其他變數：

| 變數 | 用途 |
| --- | --- |
| `DISCORD_ALLOWED_ROLES` | 角色 ID 白名單，有其中任一角色的成員都能用 |
| `DISCORD_ALLOWED_CHANNELS` | 只在這些頻道回應 |
| `DISCORD_IGNORED_CHANNELS` | 這些頻道一律不回應 |
| `DISCORD_HOME_CHANNEL` | 主動訊息（例如 cron 結果）送到的頻道 ID |
| `DISCORD_REQUIRE_MENTION` | 伺服器頻道是否要 `@bot` 才回，預設 `true` |
| `DISCORD_FREE_RESPONSE_CHANNELS` | 不用 `@bot` 就回的頻道 ID |

沒設白名單、也沒設 `DISCORD_ALLOW_ALL_USERS=true` 時，bot 會上線但不回任何人。

也可以用互動精靈寫入（`-p` 指定 profile，default profile 省略）：

```bash
./hermes-run.sh cli -p <profile> gateway setup
```

### `config.yaml`

行為設定也可以放在 profile 的 `config.yaml` 頂層 `discord:` 區塊，鍵名大多是去掉 `DISCORD_` 前綴的小寫（使用者白名單例外，鍵名是 `allow_from`）；兩邊都設時以 `.env` 為準。[`config.example.yaml`](../../config.example.yaml) 用的是：

```yaml
discord:
  require_mention: true
  auto_thread: false
  thread_require_mention: false
  reactions: true
```

頻道、討論串和 session 的對應見[頻道行為與 session](#頻道行為與-session)。

### Home channel

在想當 home 的頻道輸入 `/sethome`，或在 `.env` 設 `DISCORD_HOME_CHANNEL`。

## 頻道行為與 session

### 什麼時候回應

私訊不受頻道規則限制，只看白名單。伺服器頻道依序套用下面的規則：

1. `allowed_channels` 有設時，只在這些頻道回應，其他頻道就算 `@bot` 也不回。
2. `ignored_channels` 裡的頻道一律不回應。
3. `require_mention` 預設 `true`，要 `@bot` 才回。下面兩種情況例外：
    - 頻道在 `free_response_channels` 裡，不用 `@` 就回。
    - bot 已參與的討論串，後續訊息不用 `@`。設 `thread_require_mention: true` 可取消這個例外，適合多個 bot 共用討論串、要避免互相觸發時。

這幾個頻道清單可以填頻道 ID、頻道名稱、`#頻道名稱`，或 `*` 代表全部。討論串也會比對它所屬的頻道。`.env` 用逗號分隔，`config.yaml` 可以寫 YAML list：

```yaml
discord:
  free_response_channels:
    - "<頻道 ID>"
    - "#bot-chat"
  ignored_channels:
    - "<頻道 ID>"
```

### 討論串

`auto_thread` 開啟時，在頻道 `@bot` 會從該訊息開一個討論串，回覆和後續對話都在討論串裡。原始碼預設開啟，本專案的 [`config.example.yaml`](../../config.example.yaml) 設成 `false`。

開啟時，下列訊息仍直接在頻道回覆：

- 在 `no_thread_channels` 裡的頻道
- `free_response_channels` 裡的頻道，除非設 `free_response_auto_thread: true`
- 用 Discord「回覆」功能送出的訊息

討論串建立失敗時，bot 會在頻道回一則警告並略過該訊息，不會改在頻道裡回覆。

### Session 怎麼分

| 對話位置 | Session |
| --- | --- |
| 私訊 | 每個私訊一個 |
| 伺服器頻道 | 每位使用者各一個（`group_sessions_per_user: true`，預設） |
| 討論串 | 整個討論串共用一個（`thread_sessions_per_user: false`，預設） |

這兩個都是 `config.yaml` 的頂層鍵。開了 `auto_thread` 時，每次在頻道 `@bot` 都會開新的討論串，也就是新的 session。

`require_mention` 開啟時，兩次 `@bot` 之間別人在頻道說的話不會進 session。`history_backfill`（預設 `true`）會在下次被 `@` 時，把 bot 上一則訊息之後的頻道內容當成上下文補進去，最多往回看 `history_backfill_limit` 則（預設 50）。

### 斜線指令

gateway 連上後會把 Hermes 指令同步成 Discord 斜線指令，skill 統一放在一個 `/skill` 指令底下，輸入名稱時有自動完成。

- 斜線指令和一般訊息套用同一套白名單與頻道規則。
- 設 `DISCORD_HIDE_SLASH_COMMANDS=true` 時，只有伺服器管理員看得到斜線指令。這只是隱藏，權限仍由白名單決定。
- `DISCORD_COMMAND_SYNC_POLICY` 控制同步方式：
  - `safe`（預設）：只更新有變的指令
  - `bulk`：整批覆蓋
  - `off`：不同步

## 套用與確認

1. 重啟 gateway 讓新的 `.env` 生效。這會中斷該 home 所有 profile 正在跑的 cron 與對話：

    ```bash
    ./hermes-run.sh cli gateway restart
    ```

2. 幾秒內 bot 應該在 Discord 顯示上線。私訊它，或在頻道 `@` 它，確認有回覆。
3. 輸入 `/whoami` 看自己的權限等級。
4. bot 沒上線或沒回覆時看 log（`./hermes-run.sh logs`，或 data dir 的 `logs/gateway.log`），對照[常見錯誤](#常見錯誤)。

其他 home 的容器在指令加 `-a <home>`，見 [CLI 指令](../cli.md)。

## 常見錯誤

### bot 沒上線：privileged intents 被拒

log 開頭是 `Discord rejected the connection because privileged Gateway Intents are not enabled for this bot in the Developer Portal.`，下面列出 Hermes 要求的 intent：

- Message Content Intent：一定會要求。
- Server Members Intent：白名單用使用者名稱或設了 `DISCORD_ALLOWED_ROLES` 時才要求。

到 Developer Portal 的 **Bot → Privileged Gateway Intents** 打開列出的 intent 並儲存，再重啟 gateway。這個錯誤不會自動重試。

### bot 沒上線：token 被拒

log 有 `Discord bot token rejected:`。token 錯了或已失效，到 **Bot** 頁按 **Reset Token**，更新該 profile `.env` 的 `DISCORD_BOT_TOKEN`，再重啟 gateway。

### bot 上線但完全不回

log 有 `Discord messages are being denied because no allowlist is configured.`：沒設任何白名單。設 `DISCORD_ALLOWED_USERS`、`DISCORD_ALLOWED_ROLES` 或 `DISCORD_ALLOWED_CHANNELS` 其中之一，或設 `DISCORD_ALLOW_ALL_USERS=true` 開放所有人。

### 私訊會回，頻道不回

頻道訊息被[什麼時候回應](#什麼時候回應)的規則擋下時只記 debug log，平常看不到錯誤。檢查：

- 有沒有 `@bot`，或頻道在 `free_response_channels` 裡。
- `allowed_channels` 有設時，頻道在不在清單裡。
- 頻道在不在 `ignored_channels` 裡。

### 討論串建立失敗

頻道收到 `⚠️ Hermes could not create a Discord thread for this message, so the request was not processed. Please retry.`，log 有 `Auto-thread creation failed after retry.`，後面附 Discord 回傳的錯誤。

- 錯誤和權限有關：確認 bot 在該頻道有 `Create Public Threads` 與 `Send Messages in Threads` 權限。
- 不需要討論串：把頻道加進 `no_thread_channels`，或把 `auto_thread` 設為 `false`。

### 斜線指令沒出現或不完整

- 完全沒有斜線指令：邀請連結少了 `applications.commands` scope。用 [建立 bot](#建立-bot) 的設定重新產生邀請連結，再邀請一次。
- `DISCORD_COMMAND_SYNC_POLICY` 是 `off` 時不會同步，log 有 `Skipping Discord slash command sync (policy=off)`。
- log 有 `Discord rate-limited slash command sync; retrying after` 或 `Slash command sync timed out`：被 Discord 限流，下次重連時會再同步。
- log 有 `Reached Discord's limit of 100 slash commands`：Discord 最多 100 個斜線指令，超出的低優先指令被略過。停用用不到的指令或外掛。

[official]: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord
