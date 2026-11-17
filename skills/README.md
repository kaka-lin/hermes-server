# 本專案的 Skill

綁定這套 Hermes 部署的 skill。這裡的 skill 通常有這些特徵：

- **基礎設施操作**：用到本專案的路徑（例如 `/opt/hermes/`、`/opt/data/`）、CLI 指令或環境變數。
- **修補與維護**：說明仍由本專案維護的修補。
- **生命週期管理**：和部署架構連動，架構重構或升級時可能要跟著更新或移除。

目前包含：

- [`dispatch-agent`](dispatch-agent/SKILL.md)：主 agent 在背景派 profile 分身執行任務，再代發報告。
- [`patch-dingtalk`](patch-dingtalk/SKILL.md)：DingTalk 在這個 image 裡的兩個修正（送到指定群組、build 時裝 SDK）的原因與症狀對照。

跨專案通用的 skill 不放這裡，放 [agent-library](../../agent-library/)。
