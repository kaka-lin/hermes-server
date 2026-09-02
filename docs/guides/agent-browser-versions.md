# agent-browser 版本管理

本專案的衍生 image 覆寫了上游 pin 的 agent-browser 版本。這份文件記錄怎麼升級、為什麼需要覆寫、以及什麼時候可以拆掉這層。（事實查核日期：2026-09-01）

## 1. 怎麼升級

版本的單一真相來源是 [`versions.env`](../../versions.env)，改完 commit、重建即可，不用動任何 script 或 Dockerfile：

```ini
HERMES_VERSION=v2026.6.5
AGENT_BROWSER_VERSION=0.36.0
```

```bash
./hermes-build.sh && ./hermes-run.sh up

# 臨時換版本測試（不改檔案）
AGENT_BROWSER_VERSION=0.35.2 ./hermes-build.sh
```

- **重建後第一件事：實測 `browser_navigate`。** Hermes 的 browser tool 解析 agent-browser CLI 的輸出，而上游只在 0.26 上測過，新版有 CLI 漂移風險；不合就把版本往回降重建。
- 在跑起來的 container 裡 `npm update` 沒有意義——重建就還原成 image 內容。
- 回退：`git revert` 後重建即可，資料都在 `/opt/data`（volume），不受影響。

## 2. 為什麼需要覆寫

上游 image 內建 Node 22 並刻意 pin `agent-browser@^0.26.0`，而 npm registry 的 `engines` 宣告（`npm view agent-browser engines`）：

| 版本範圍 | engines 宣告 | Node 22 可用？ |
| --- | --- | --- |
| ≤ 0.27.0 | 無 | ✅ |
| 0.27.1 – 0.36.0（最新） | `node >=24.0.0`, `pnpm >=11.0.0` | ❌ |

所以要用新版就得在衍生 image 同一層換 Node 24 再覆寫（見 [Dockerfile](../../Dockerfile)）。npm 對 `engines` 不符預設只警告不擋，但官方已不支援 Node 22，不要硬裝賭運氣。

兩個常見誤解：

- **host 機器新舊無關**：container 是 Linux，內部 Node 與 host macOS / host Node 完全無關——舊 mac mini 跑 Node 24 的 image 沒問題，換新機也不會讓 container 裡的版本變新。
- **Setup 不用裝 CLI**：套件已內建在 image，setup 只需開 toolset、選 provider；缺的 Chrome 二進位首次使用時會自動補。見[瀏覽器自動化設定](browser-automation.md#41-local-模式預設)。

## 3. 什麼時候拆掉這層

這層是過渡方案。上游最新版（v2026.8.31 查證）已內建 **Node 26**，但 agent-browser 改為 `npx` lazy 安裝且**仍刻意 pin `^0.26.0`**（上游註解：安裝完整性考量）。所以：

- 升 `HERMES_VERSION` 到 v2026.7+ 之後：Dockerfile 的 Node 換裝段可刪；想繼續用新版 agent-browser，覆寫縮成一行 `npm install -g agent-browser@<版本>`。
- 每次升 `HERMES_VERSION` 都要重新確認這層是否還需要、是否還相容。

## 相關文件

- [瀏覽器自動化設定](browser-automation.md)
- [versions.env](../../versions.env)（版本旋鈕）／[Dockerfile](../../Dockerfile)（覆寫層實作）
