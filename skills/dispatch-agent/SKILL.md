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

    > **[極度重要：跨平台通行證與發送權限]**
    >
    > 在背景 CLI 模式下執行時，必須依據目標平台給予對應的身分！例如目標為 Discord 時，提取 `DISCORD_BOT_TOKEN` 並加上 `export HERMES_SESSION_PLATFORM=discord`；若目標為 DingTalk，則提取 `DINGTALK_WEBHOOK_URL` 並加上 `export HERMES_SESSION_PLATFORM=dingtalk`。

3. **背景派發任務**

    使用 `terminal(background=true)` 呼叫該分身的專屬捷徑，並加上 `-q` (安靜模式/單次查詢) 來執行任務。
    **【重要：總指揮翻譯法 Address Translation】**：因為背景分身無法連線到主系統通訊錄，很容易因為自行查驗名稱失敗而放棄發送。
    所以我們在喚醒指令中，必須直接把「精確的底層 API ID」寫死在 prompt 中，讓分身閉著眼睛盲發即可成功。

    指令格式：

    ```bash
    # 請依據目標平台動態替換變數 (以下以 discord 為例，若為 dingtalk 則替換對應的 token 與 PLATFORM)
    export DISCORD_BOT_TOKEN=$(grep DISCORD_BOT_TOKEN /opt/data/.env | cut -d "=" -f2) && export HERMES_SESSION_PLATFORM=discord && /opt/data/home/.local/bin/<profile名稱> chat -q "你是 <profile名稱>。請切換並確認你的 CDP proxy port 正確對應你的身分。<任務內容>。請直接讀取技能位於主倉庫的絕對路徑（例如 /opt/data/skills/.../SKILL.md）並執行。任務完成後，請呼叫 send_message 工具將戰績發送到精確目標 ID：『<你剛剛查到的精確ID>』；絕對不要使用 delegate_task!)。【極度重要：報告格式要求】1. 務必『完整呈現』步驟細節，就像對話般生動，禁止壓縮摘要！ 2. 絕對不可以使用連續的波浪號 (~) 來當作語氣詞或裝飾，以免觸發刪除線排版！請改用驚嘆號或表情符號。"
    ```

4. **回報派發結果**

    向使用者回報「✅ 已成功派發任務給 [分身名稱]」，並附上你下的指令內容。告知使用者分身正在背景執行，不會干擾我們現在的對話。

## 停止/終止分身任務 (Stopping Dispatch Agents)

1. **尋找 PID**：使用 `ps aux | grep <profile名稱>` 或 `ps aux | grep hermes`。
2. **尋找關聯程序**：分身通常會連帶啟動 `cdp_proxy.py` 或 `agent-browser`，執行 `ps aux | grep proxy` 確認。
3. **終止程序**：使用 `pkill -f "<profile名稱>" ; pkill -f "cdp_proxy.py"`。
4. **回報**：確認程序已消失，向使用者回報。

## ⚠️ 跨平台與背景執行陷阱 (Pitfalls)

1. **通訊錄隔離與名稱解析失敗 (Address Book Isolation)**

    背景分身 (CLI 模式) 並**沒有**連線到主控台 Gateway 的通訊錄快取，因此**完全無法解析中文頻道名稱**。

    - ❌ **錯誤作法**：要求分身發送至中文名稱頻道，或要求分身執行 `send_message(action='list')` 來查通訊錄（會回傳空清單，導致分身誤判無權限而放棄發送）。
    - ✅ **正確作法 (Discord)**：總指揮應先查好「精確的數字 ID」（例如 `discord:1503642517088894996`），並直接將這串 ID 寫死在派發給分身的 prompt 中。
    - ✅ **正確作法 (DingTalk Webhook)**：若是使用 Webhook 直發模式的釘釘，目標請**直接寫 `dingtalk`** 即可，絕對不要加上任何 CID，否則系統會因為找不到通訊錄而報錯。讓分身盲發。

2. **專案化技能與環境變數解耦**

    在派發需要呼叫共用資源的技能時，應確保環境變數已在主 `.env` 中設定，避免在指令中硬編碼絕對路徑。
