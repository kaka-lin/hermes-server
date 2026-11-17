# Discord

gateway 用 bot token 連上 Discord，不需要公開的 URL。這裡是在本專案接上 Discord 的步驟；完整選項見[官方 Discord 文件][official]。

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

行為設定也可以放在 profile 的 `config.yaml` 頂層 `discord:` 區塊，鍵名是去掉 `DISCORD_` 前綴的小寫；兩邊都設時以 `.env` 為準。[`config.example.yaml`](../../config.example.yaml) 用的是：

```yaml
discord:
  require_mention: true
  auto_thread: false
  thread_require_mention: false
  reactions: true
```

同一個頻道裡不同使用者預設各自一個 session；要讓整個頻道共用上下文，把頂層的 `group_sessions_per_user` 設為 `false`。

### Home channel

在想當 home 的頻道輸入 `/sethome`，或在 `.env` 設 `DISCORD_HOME_CHANNEL`。

## 套用與確認

1. 重啟 gateway 讓新的 `.env` 生效。這會中斷該 home 所有 profile 正在跑的 cron 與對話：

    ```bash
    ./hermes-run.sh cli gateway restart
    ```

2. 幾秒內 bot 應該在 Discord 顯示上線。私訊它，或在頻道 `@` 它，確認有回覆。
3. 輸入 `/whoami` 看自己的權限等級。
4. bot 沒上線時看 log（`./hermes-run.sh logs`，或 data dir 的 `logs/gateway.log`）。Discord 拒絕 privileged intents 時，log 會說明要開哪個 intent。

其他 home 的容器在指令加 `-a <home>`，見 [CLI 指令](../cli.md)。

[official]: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord
