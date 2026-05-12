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

> **[極度重要：跨平台回報權限]** 若任務需要分身在結束時回報至 Discord 等平台，該分身在背景（CLI 模式）下**必須**具備 `messaging` 工具。請先檢查該分身的 `config.yaml`（例如 `/opt/data/profiles/<name>/config.yaml`），確保 `toolsets` 陣列中包含 `"messaging"`。若沒有，請先用 `sed` 幫它補上（例如將 `["hermes-cli", "browser"]` 替換為 `["hermes-cli", "browser", "messaging"]`），否則分身任務完成時將因找不到 `send_message` 工具而無法回報戰績！
>
> **[極度重要：Discord 通行證與發送權限]** 在背景 CLI 模式下執行時，除了提取 `.env` 中的 `DISCORD_BOT_TOKEN` 外，還必須加上 `export HERMES_SESSION_PLATFORM=discord` 讓它擁有正確的平台身分！如果不加，分身會以為自己沒有 `send_message` 權限而試圖透過 `delegate_task` 找代班發送，導致最終失敗。另外，在 prompt 中務必嚴格禁止它使用 `delegate_task`。

1. **背景派發任務**
   使用 `terminal(background=true)` 呼叫該分身的專屬捷徑，並加上 `-q` (安靜模式/單次查詢) 來執行任務。
   如果使用者希望分身回報結果（例如發送訊息到 Discord），請在傳遞給分身的 prompt 中，明確指示分身在任務最後呼叫 `send_message` 工具，將執行結果發送回這個指定的 Discord 頻道。

   >【重要】：請確保分身的 profile 名稱與使用者要求的完全一致（例如 `helper`, `main`, `assistant`），並提醒分身必須切換到對應的 OpenClaw Port（例如 main 是 18800，helper 是 9223）。

   指令格式：

   ```bash
   export DISCORD_BOT_TOKEN=$(grep DISCORD_BOT_TOKEN /opt/data/profiles/<profile名稱>/.env | cut -d '=' -f2) && export HERMES_SESSION_PLATFORM=discord && /opt/data/home/.local/bin/<profile名稱> chat -q "你是 <profile名稱>。請切換並確認你的 CDP proxy port 正確對應你的身分。<任務內容>。如果你被要求執行特定的技能，請直接讀取該技能位於主倉庫的絕對路徑（例如 /opt/data/skills/.../SKILL.md）並執行其腳本。任務完成後，請自己呼叫 send_message 工具將戰績發送到 discord:<頻道ID> (絕對不要使用 delegate_task!)。【極度重要：報告格式要求】1. 務必『完整呈現』步驟細節（包含每一則抓到的貼文內容、思考策略、回覆草稿），就像對話般生動，禁止壓縮摘要！ 2. 絕對不可以使用連續的波浪號 (~) 來當作語氣詞或裝飾，以免觸發 Discord 的刪除線排版！請改用驚嘆號或表情符號。"
   ```

   例如：

   ```bash
   /opt/data/home/.local/bin/helper chat -q "啟動社群掃描技能，抓取 Threads 上的熱門趨勢"
   ```

2. **回報派發結果**

   向使用者回報「✅ 已成功派發任務給 [分身名稱]」，並附上你下的指令內容。告知使用者分身正在背景執行，不會干擾我們現在的對話。

## 停止/終止分身任務 (Stopping Dispatch Agents)

當使用者要求「停止某個分身」或「取消所有活動」時：

1. **尋找背景任務 PID**

   使用 `terminal` 執行 `ps aux | grep <profile名稱>` 或 `ps aux | grep hermes` 來找到正在執行的分身程序。

2. **尋找關聯的代理與瀏覽器**

   分身通常會連帶啟動 `cdp_proxy.py` 或 `agent-browser`，也需要一併終止。執行 `ps aux | grep proxy` 確認。

3. **終止程序 (Kill)**
   使用 `pkill` 強制終止相關程序，例如：

   ```bash
   pkill -f "<profile名稱>" ; pkill -f "cdp_proxy.py" ; pkill -f "agent-browser"
   ```

   或者直接針對 PID 使用 `kill <PID>`。

4. **確認並回報**
   確認程序已消失，並向使用者回報活動已成功停止。
