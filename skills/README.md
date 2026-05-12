# 🤖 Hermes Agent 專用 Skills

這個目錄 (`hermes-server/skills/`) 專門存放**高度綁定 Hermes 基礎設施**的專用操作流程與補丁 (Patches)。

## 📁 這裡放什麼？

本目錄存放的 Skill 通常具有以下特徵：

- **基礎設施操作 (Infrastructure Operations)**：包含專案特定的絕對路徑（如 `/opt/hermes/`）、特定的 CLI 指令或環境變數配置。
- **補丁與維護 (Patches & Maintenance)**：針對特定 Bug 的修復指令（例如 `patch-gemini-stream-usage`）。
- **生命週期管理**：與 Hermes Server 架構連動的操作，當系統重構或升級時，這些 Skill 可能需要同步更新或移除。

### 目前包含的 Skills

- **`dispatch-agent`**: 總指揮專用的背景任務派發腳本。
- **`patch-gemini-stream-usage`**: 修復 streaming 模式下 usageMetadata 遺失的補丁腳本。

## 💡 通用 Skills 請至 Agent Library

如果你要尋找或新增的是**跨平台可復用**的領域知識（例如：「如何寫好 Git Commit」、「如何分析 FastAPI 專案架構」等），請**不要**放在這裡。

👉 **請前往：[Agent Library](../../../agent-library/)**

`agent-library` 是一個獨立的資源庫，專門收集跨平台通用的 Agent Skills、Workflows 和 Rules。將通用知識與專案基礎設施分離，能讓你的 Agent 更聰明且易於維護！
