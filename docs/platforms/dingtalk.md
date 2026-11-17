# DingTalk

Hermes 用 DingTalk 的 Stream 模式收訊息，由容器主動連出去，不需要公開 URL。這裡是在本專案接上 DingTalk 的步驟，以及這個 image 和上游的差異；完整選項見[官方 DingTalk 文件][official]。

## 這個 image 和上游的差異

- **SDK 在 build 時裝好**：上游 image 沒有 `dingtalk-stream`，要到執行期才 lazy-install。那時 adapter 模組已經 import 完，Stream handler 綁錯基底類別，每則訊息都會丟出 `_IncomingHandler` 沒有 `raw_process` 的錯誤，bot 永遠不回。[`Dockerfile`](../../Dockerfile) 在 build 時從上游 lockfile 安裝 `dingtalk` extra，不需要手動裝套件。
- **[`dingtalk-send-routing.patch`](../../patches/dingtalk-send-routing.patch)**：讓 `send_message` 能送到指定群組，見[送到指定群組](#送到指定群組)。

原因與細節見 [`skills/patch-dingtalk/SKILL.md`](../../skills/patch-dingtalk/SKILL.md) 與 [`patches/README.md`](../../patches/README.md)。

## 每個 profile 一個應用

一個容器的 gateway 會帶起 home 底下所有 profile，每個 profile 讀自己的 `.env`：

- default profile：`<data dir>/.env`
- 其他 profile：`<data dir>/profiles/<名稱>/.env`

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

平台設定放在 profile 的 `config.yaml`。[`config.example.yaml`](../../config.example.yaml) 用的是：

```yaml
gateway:
  platforms:
    dingtalk:
      extra:
        require_mention: true
```

`extra` 底下還可以放：

- `card_template_id`：AI 卡片範本 ID（後台 AI 卡片設定裡找），設了之後回覆改用卡片並串流更新。
- `robot_code`：機器人代碼，預設等於 Client ID，不同時才要設。

群組裡不同使用者預設各自一個 session；要讓整個群組共用上下文，把頂層的 `group_sessions_per_user` 設為 `false`。

## 送到指定群組

一般回覆走訊息附帶的 session webhook，只能回剛收到的那則訊息。cron、背景分身（例如 [`dispatch-agent`](../../skills/dispatch-agent/SKILL.md)）或跨群組發送沒有這個 webhook，要靠 `send_message` 主動送出。上游在這裡有兩個問題，`dingtalk-send-routing.patch` 修好它們：

- **目標解析**：上游對頻道目錄裡沒有的 `cid` 會回 `Could not resolve`。patch 讓 `dingtalk:cidXXXX==` 被當成明確目標。
- **發送方式**：上游的純文字 `send_message` 只會用 `DINGTALK_WEBHOOK_URL`，而一個自訂群機器人 webhook 只綁一個群組。patch 改成目標是 `cid...` 群組且有 Client ID / Secret 時，先用官方機器人 API（`robot/groupMessages/send`）送到該群組；API 沒確認送達才退回 `DINGTALK_WEBHOOK_URL`。gateway 內對 `cid` 群組沒有 session webhook 時，也走同一個 API。

確認 image 有套到 patch（需要已建好的 image）：

```bash
python3 tests/test_dingtalk_send_routing.py
```

## 套用與確認

1. 重啟 gateway 讓新的 `.env` 生效。這會中斷該 home 所有 profile 正在跑的 cron 與對話：

    ```bash
    ./hermes-run.sh cli gateway restart
    ```

2. 私訊機器人，或在群組 `@` 它，確認有回覆。
3. 沒回覆時看 log（`./hermes-run.sh logs`，或 data dir 的 `logs/gateway.log`）：

    - `DINGTALK_CLIENT_ID and DINGTALK_CLIENT_SECRET required`：該 profile 的 `.env` 沒有憑證。
    - `dingtalk-stream not installed`：image 不是用這個 repo 的 `Dockerfile` 建的，執行 `./hermes-build.sh`。
    - `No valid session_webhook available`：回覆時找不到原訊息的 webhook（例如中間 gateway 重啟過），重新傳一則訊息即可。
    - 機器人沒反應也沒錯誤：確認後台已開機器人能力並選 Stream 模式、應用已發布、你的 user ID 在白名單裡。

其他 home 的容器在指令加 `-a <home>`，見 [CLI 指令](../cli.md)。

[official]: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/dingtalk
