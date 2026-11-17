# DingTalk

Hermes 用 DingTalk 的 Stream 模式收訊息，由容器主動連出去，不需要公開 URL。這裡是在本專案接上 DingTalk 的步驟；需要更多細節時可參考[官方 DingTalk 文件][official]。

## 每個 profile 一個應用

一個容器的 gateway 會帶起該 home 底下所有 profile，每個 profile 讀自己的 `.env`。以 `~/.hermes` 為例：

- default profile：`~/.hermes/.env`
- 其他 profile：`~/.hermes/profiles/<名稱>/.env`

> 其他 home（例如 `~/.hermes-kaka`）路徑規則相同，把 `~/.hermes` 換成該 home 的 data dir。

每個 profile 要有**自己的** DingTalk 應用（Client ID / Client Secret）。同一組憑證不能給兩個 profile，也不能給兩個容器。profile 與 home 的關係見 [Agent、Home 與 Profile](../agents-and-profiles.md)。

## 建立應用

1. 用管理員帳號登入 [DingTalk 開發者後台](https://open-dev.dingtalk.com/)。
2. 進 **應用開發 → 企業內部開發** 建立應用（依後台版本是 H5 微應用或機器人）。
3. 在 **憑證與基礎資訊** 複製 `Client ID`（AppKey）與 `Client Secret`（AppSecret）。
4. 在 **新增能力** 加入 **機器人**，**訊息接收模式** 選 **Stream 模式**。
5. 在 **版本管理與發布** 建立新版本並發布，組織內的人才搜得到機器人、把它加進群組。
6. 取得要放進白名單的 user ID：在管理後台的通訊錄查，或先啟動 gateway、傳訊息給機器人，再到 log 找 `sender_id`。

## 填設定

### `.env`

編輯該 profile 的 `.env`：

```bash
DINGTALK_CLIENT_ID=<AppKey>
DINGTALK_CLIENT_SECRET=<AppSecret>
DINGTALK_ALLOWED_USERS=<user ID>   # 多個用逗號分隔
```

使用者白名單一定要放 `.env` 的 `DINGTALK_ALLOWED_USERS`：gateway 授權只看這個變數，`config.yaml` 的白名單要經橋接才寫進去，而非 default 的 profile 不做這個橋接。

其他變數：

| 變數 | 用途 |
| --- | --- |
| `DINGTALK_ALLOW_ALL_USERS` | 設 `true` 允許所有人，不用白名單 |
| `DINGTALK_REQUIRE_MENTION` | 群組裡是否要 `@機器人` 才回 |
| `DINGTALK_FREE_RESPONSE_CHATS` | 不用 `@` 就回的群組 ID（`cid...`） |
| `DINGTALK_MENTION_PATTERNS` | 視為叫機器人的文字 pattern，例如 `^小马` |
| `DINGTALK_HOME_CHANNEL` | cron 結果預設送到的群組 ID（`cid...`） |
| `DINGTALK_WEBHOOK_URL` | 自訂群機器人的 webhook，送到指定群組失敗時的後備 |

也可以用互動精靈寫入（`-p` 指定 profile，default profile 省略），它支援掃 QR code 授權或手動貼憑證：

```bash
./hermes-run.sh cli -p <profile> gateway setup
```

### `config.yaml`

平台設定放在 profile 的 `config.yaml`。[`config.example.yaml`][config-example] 用的是：

```yaml
gateway:
  platforms:
    dingtalk:
      extra:
        require_mention: true
```

`extra` 底下還可以放：

- `card_template_id`：AI 卡片範本 ID（後台 AI 卡片設定裡找），設了之後回覆改用卡片，見[AI 卡片](#ai-卡片)。
- `robot_code`：機器人代碼，預設等於 Client ID，不同時才要設。

群組裡不同使用者預設各自一個 session；要讓整個群組共用上下文，把頂層的 `group_sessions_per_user` 設為 `false`。

## 套用與確認

1. 重啟 gateway 讓新的 `.env` 生效。這會中斷該 home 所有 profile 正在跑的 cron 與對話：

    ```bash
    ./hermes-run.sh cli gateway restart
    ```

2. 私訊機器人，或在群組 `@` 它，確認有回覆。

3. 沒回覆時看 log（`./hermes-run.sh logs`，或 data dir 的 `logs/gateway.log`），對照[常見錯誤](#常見錯誤)。

其他 home 的容器在指令加 `-a <home>`，見 [CLI 指令](../cli.md)。

## 進階設定

### AI 卡片

回覆預設是 session webhook 送出的 Markdown。在 profile 的 `config.yaml` 設卡片範本 ID 後改用 AI 卡片：

```yaml
gateway:
  platforms:
    dingtalk:
      extra:
        card_template_id: <範本 ID>
```

- 範本要有名為 `content` 的變數，回覆內容寫進這個欄位。
- 卡片送不出去時自動退回 Markdown 回覆，log 會有 `AI Card send failed, falling back to webhook`。私訊的訊息沒帶 `sender_staff_id` 時也會退回，log 是 `AI Card skipped: missing sender_staff_id for DM`。
- 只設範本，卡片在回覆完成時一次送出；要邊產生邊更新，再照[顯示設定](#顯示設定)開串流。

### 表情回應

機器人收到訊息就在該訊息加上「思考中」表情，最終回覆送出後換成「完成」（英文語系是 `🤔Thinking`、`🥳Done`）。這個功能不需要 AI 卡片，也沒有開關。

表情在白名單與 `@` 規則檢查之前就加上：看到「思考中」卻沒有回覆，代表訊息已送到 gateway，是被擋在授權或群組規則，見[機器人不回覆](#機器人不回覆)。

### 顯示設定

DingTalk 的一般回覆送出後不能修改，Hermes 對它的預設是：

- `tool_progress: off`：不顯示工具進度
- `interim_assistant_messages: false`：不送中間的說明訊息
- `streaming: false`：不串流
- `long_running_notifications: false`：長時間執行不另外通知
- `show_reasoning: false`：不顯示推理過程

每個鍵依序取第一個有值的來源：

1. `display.platforms.dingtalk.<鍵>`
2. `display.<鍵>`
3. 上面的 DingTalk 預設

[`config.example.yaml`][config-example] 在 `display` 底下設了 `interim_assistant_messages: true`，所以 DingTalk 也會收到中間訊息。只想讓 DingTalk 保持安靜時：

```yaml
display:
  platforms:
    dingtalk:
      tool_progress: 'off'
      interim_assistant_messages: false
```

串流更新只在設了 `card_template_id` 時有效，而且三個條件都要成立：

- AI 卡片已設定
- 頂層 `streaming.enabled: true`，`config.example.yaml` 預設是 `false`
- `display.platforms.dingtalk.streaming: true`，因為 DingTalk 預設是 `false`

```yaml
streaming:
  enabled: true
display:
  platforms:
    dingtalk:
      streaming: true
```

`display.streaming` 只管 CLI，不影響 gateway。

### 主動通知

cron 結果預設送到 `.env` 的 `DINGTALK_HOME_CHANNEL`（群組 ID，`cid...`）。主動通知由容器呼叫 DingTalk API 送出，不需要公開 URL；手上沒有該群組的 session webhook 時改走機器人 API，見[送到指定群組](#送到指定群組)。

### 送到指定群組

一般回覆走訊息附帶的 session webhook，只能回剛收到的那則訊息。下列情況沒有這個 webhook，要靠 `send_message` 主動送出：

- cron
- 背景分身（例如 [`dispatch-agent`](../../skills/dispatch-agent/SKILL.md)）
- 跨群組發送

上游在這裡有兩個問題，`dingtalk-send-routing.patch` 修好它們：

- **目標解析**：上游對頻道目錄裡沒有的 `cid` 會回 `Could not resolve`。patch 讓 `dingtalk:cidXXXX==` 被當成明確目標。
- **發送方式**：上游的純文字 `send_message` 只會用 `DINGTALK_WEBHOOK_URL`，而一個自訂群機器人 webhook 只綁一個群組。patch 改成目標是 `cid...` 群組且有 Client ID / Secret 時，先用官方機器人 API（`robot/groupMessages/send`）送到該群組；API 沒確認送達才退回 `DINGTALK_WEBHOOK_URL`。gateway 內對 `cid` 群組沒有 session webhook 時，也走同一個 API。

確認 image 有套到 patch（需要已建好的 image）：

```bash
python3 tests/test_dingtalk_send_routing.py
```

## 限制

- 單則訊息上限 20,000 字元，超過的部分送出時會被截掉。
- 同一則訊息在 5 分鐘內重複送達，只處理一次。

## 常見錯誤

### 機器人不回覆

依序檢查：

1. 後台設定齊全：
    - 已加機器人能力
    - 訊息接收模式選 Stream
    - 應用已發布

2. log 有 `Connected via Stream Mode`。沒有的話看下面幾節。

3. 訊息上出現「思考中」表情卻沒有回覆：訊息已到 gateway，被擋在授權或群組規則。
    - 確認你的 user ID 在該 profile 的 `DINGTALK_ALLOWED_USERS`。
    - 群組裡要 `@` 機器人，或把群組 ID 加進 `DINGTALK_FREE_RESPONSE_CHATS`。

    這類訊息只在 debug 等級的 log 留紀錄，平常看不到錯誤。

### `dingtalk-stream not installed`

這個 image 在 build 時就裝好 SDK，正常不會出現。gateway 在建立 adapter 前會先檢查套件，所以缺套件時 log 通常先出現下面兩行之一：

- `Platform 'DingTalk' dependencies missing — attempting install...`
- `Platform 'DingTalk' requirements not met`

出現任何一種，代表容器跑的 image 不是用這個 repo 的 `Dockerfile` 建的。就算執行期自動補裝成功，Stream handler 也已綁錯基底類別，bot 一樣不回（見[這個 image 和上游的差異](#這個-image-和上游的差異)）。執行 `./hermes-build.sh` 重建，再用 `./hermes-run.sh up` 換上新 image。

### `DINGTALK_CLIENT_ID and DINGTALK_CLIENT_SECRET required`

這是 adapter 連線前的檢查，但 gateway 更早就會檢查憑證，所以缺憑證時通常看到的是：

- 完全沒填憑證：gateway 不啟用 DingTalk，log 沒有錯誤，機器人一直離線。
- 平台已在設定中啟用但缺憑證：log 是 `Platform 'DingTalk' config validation failed`。

把 `DINGTALK_CLIENT_ID`、`DINGTALK_CLIENT_SECRET` 填進**該 profile** 的 `.env`（路徑見[每個 profile 一個應用](#每個-profile-一個應用)），再重啟 gateway。

### Stream 斷線或一直重連

- Stream SDK 自己會重試。錯誤跑出 SDK 時由 Hermes 重連，log 有 `Stream client error:` 與 `Reconnecting in`，間隔依序是 2、5、10、30、60 秒，之後固定 60 秒。
- 同一種錯誤連續出現 5 次後熔斷，log 有 `circuit breaker tripped`，之後每 300 秒安靜重試一次，直到錯誤類型改變。
- log 有 `dingtalk-stream cannot open its websocket with the installed websockets package`：套件版本不相容，gateway 不會再重連。用這個 repo 的 `Dockerfile` 重建 image，不要在容器裡 `pip install`。
- 其他情況：確認憑證有效、主機能對外建立 WebSocket 連線。

### `No session_webhook available`

實際的 log 是 `No valid session_webhook for chat_id=`。一般回覆要用原訊息附帶的 session webhook，它只存在 gateway 的記憶體：

- gateway 重啟後就消失。
- 到期前 5 分鐘就不再使用。

這個 image 對 `cid` 開頭的目標會改用機器人 API 送出，不會出這個錯；只有目標不是 `cid...` 時才會。重新傳一則訊息給機器人即可。

## 這個 image 和上游的差異

上游的 DingTalk 有兩個問題，這個 image 在 build 時都修好了，不需要自己處理：

- **bot 不回訊息**：上游到執行期才裝 `dingtalk-stream`，Stream handler 會綁錯，每則訊息都報 `_IncomingHandler` 沒有 `raw_process`。[`Dockerfile`](../../Dockerfile) 改成 build 時就裝好。
- **送不到指定群組**：上游的 `send_message` 認不得 `dingtalk:cid...` 這種目標，也只會用 webhook 綁定的那個群組。[`dingtalk-send-routing.patch`](../../patches/dingtalk-send-routing.patch) 修好這兩點，見[送到指定群組](#送到指定群組)。

兩個修正的完整原因見 [`skills/patch-dingtalk/SKILL.md`](../../skills/patch-dingtalk/SKILL.md)。

[official]: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/dingtalk
[config-example]: ../../config.example.yaml
