---
name: dispatch-agent
description: 總指揮專用技能：根據使用者指示，在背景啟動指定的 Hermes Profile 分身去執行特定任務。
version: 1.0.0
---

# 啟動分身任務 (Dispatch Agent)

## 觸發情境

當使用者對「總指揮（你）」說：

- 「叫 helper 去巡邏」
- 「請 assistant 去檢查簡訊」
- 「讓 xxx agent 去執行...」

## 執行流程

1. **確認 Profile 與回報權限**

    先使用 `terminal` 執行 `/opt/hermes/.venv/bin/hermes profile list`，確認使用者提到的分身是否存在。

2. **確認回報平台與精確 ID (總指揮負責查地址)**

    如果使用者要求分身回報結果（例如發送訊息到釘釘的群組或某個 Discord 頻道），**你（總指揮）必須先使用 `send_message(action='list')` 查出該群組的「精確底層 ID」**（例如 `discord:1503642517088894996` 或 `dingtalk:cidLbiQUw...`）。絕對不能把中文名稱直接丟給分身。

    > **[極度重要：分身不自己發送，由總指揮代發]**
    >
    > `hermes -p <分身> chat -q` 在 gateway 行程內以分身的 profile 執行，讀的是分身自己的 `.env`。在 shell 裡 `export DISCORD_BOT_TOKEN` 對它沒有作用；而同一組 bot token 不能同時給兩個 profile 用，所以分身沒有可用的發送憑證。分身只把報告寫成檔案，再由 `hermes send`（不經過模型，用主帳號 `/opt/data/.env` 的憑證）把檔案送到目標。

3. **背景派發任務**

    使用 `terminal(background=true)` 執行下列指令串。先決定報告檔路徑 `REPORT=/opt/data/shared/reports/<profile名稱>-<YYYYmmdd-HHMMSS>.md`，把它和第 2 步查到的精確 ID 寫死在指令中。

    指令格式：

    ```bash
    mkdir -p /opt/data/shared/reports && \
    hermes -p <profile名稱> chat -q "你是 <profile名稱>。要用瀏覽器時，用你 profile 的 browser.cdp_url（hermes config get browser.cdp_url）。<任務內容>。請直接讀取技能位於主倉庫的絕對路徑（例如 /opt/data/skills/.../SKILL.md）並執行。任務完成後，把完整戰績報告用 write_file 寫入 <REPORT 路徑>；不要呼叫 send_message，也絕對不要使用 delegate_task！【極度重要：報告格式要求】1. 務必『完整呈現』步驟細節，就像對話般生動，禁止壓縮摘要！ 2. 絕對不可以使用連續的波浪號 (~) 來當作語氣詞或裝飾，以免觸發刪除線排版！請改用驚嘆號或表情符號。" && \
    test -s <REPORT 路徑> && \
    hermes send -t '<你剛剛查到的精確ID>' -f <REPORT 路徑> -s "【<profile名稱> 回報】"
    ```

    `test -s` 確保分身真的寫出報告才發送；任一步失敗，後面的發送就不會執行，報告檔留在 `/opt/data/shared/reports/` 可供查看。

4. **回報派發結果**

    向使用者回報「✅ 已成功派發任務給 [分身名稱]」，並附上你下的指令內容。告知使用者分身正在背景執行，不會干擾我們現在的對話。

## 停止或終止分身任務

1. **尋找 PID**：使用 `ps aux | grep <profile名稱>` 或 `ps aux | grep hermes`。
2. **尋找關聯程序**：分身可能連帶啟動 `agent-browser`，執行 `ps aux | grep agent-browser` 確認。`cdp_proxy.py` 是容器啟動時就在跑、所有 profile 共用的 CDP 轉發，不屬於分身。
3. **終止程序**：使用 `pkill -f "<profile名稱>"`，必要時再終止該分身的 `agent-browser` 程序。**不要**終止 `cdp_proxy.py`，否則所有 profile 的瀏覽器都會斷線，要重啟容器才會恢復。
4. **回報**：確認程序已消失，向使用者回報。

## 跨平台與背景執行陷阱

1. **目標一律用精確 ID**

    發送由指令串最後的 `hermes send` 負責，目標要寫死成第 2 步查到的精確 ID，不要用中文頻道名稱。

    - ❌ **錯誤作法**：要求分身自己呼叫 `send_message` 回報。分身沒有自己的 bot 憑證，發送會失敗。
    - ✅ **正確作法 (Discord)**：總指揮先查好「精確的數字 ID」（例如 `discord:1503642517088894996`），寫進 `hermes send -t`。
    - ✅ **正確作法 (DingTalk)**：總指揮先查好群組的精確 ID，目標寫成 `dingtalk:cidXXXX==` 並寫進 `hermes send -t`。本專案的 `dingtalk-send-routing.patch` 讓 `cid` 目標被當成明確目標，經官方機器人 API 送到**該群組**（需要 `DINGTALK_CLIENT_ID` / `DINGTALK_CLIENT_SECRET`）；API 沒確認送達時才退回 `DINGTALK_WEBHOOK_URL` 綁定的單一群組。只寫 `dingtalk` 不加 CID 時，只會送到 home channel 或 webhook 的那一個群。

2. **專案化技能與環境變數解耦**

    在派發需要呼叫共用資源的技能時，應確保環境變數已在主 `.env` 中設定，避免在指令中硬編碼絕對路徑。
