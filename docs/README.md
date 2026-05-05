# Hermes Agent Server 文件中心

歡迎來到本專案的文件庫。這裡收錄了基於 Docker Compose 部署 Hermes Agent 的安裝、設定、平台整合與疑難排解指南。

本文件庫只放與 `hermes-server` 部署實作直接相關的內容。Hermes 的通用架構、概念、reference 與最佳實踐放在 [LLM-notes/Hermes](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)，分工與 `openclaw-server` / `LLM-notes/OpenClaw` 相同。

## 1. 快速入門 (Getting Started)

- [安裝指南](deployment/setup.md)
- [CLI 使用手冊](guides/cli-usage.md)

## 2. 常用 Docker 指令

```bash
# 啟動服務（背景執行）
docker compose up -d

# 重啟 Gateway（修改 ~/.hermes/config.yaml 後執行）
docker compose restart hermes

# 查看即時 log
docker compose logs -f hermes

# 查看最近 200 行 log
docker compose logs --tail 200 hermes

# 進入 Gateway 容器
docker exec -it hermes bash

# 執行 Hermes CLI 指令
docker exec -it hermes hermes <command>

# 例：列出 cron job
docker exec -it hermes hermes cron list

# 例：列出已配對的使用者
docker exec -it hermes hermes pairing list

# 例：查看 sessions
docker exec -it hermes hermes sessions list
```

## 3. 功能配置指南 (Guides)

### 基礎配置

- [Hermes CLI 使用手冊](guides/cli-usage.md)：`gateway`、`dashboard`、`pairing`、`sessions`、`skills`、`cron` 等指令。
- [資料夾結構說明](guides/data-volume.md)：`~/.hermes` 內各檔案職責與備份策略。
- [模型與備援設定](guides/model-configuration.md)：預設模型、Fallback Model 與 Local／Docker 設定差異。

### 進階使用

- [Multi-Agent & Profiles)](guides/multi-agent.md)：臨時任務委派 (Delegate Task) 與實體多重程序 (Profiles) 之差異與應用。
- [瀏覽器自動化設定](guides/browser-automation.md)：`shm_size`、Playwright、記憶體需求。

## 4. 平台整合 (Platform Integrations)

- [Discord 全功能安裝與配置指南](platforms/discord.md)

## 5. 進階部署 (Advanced Deployment)

- [Docker Compose 設計細節 (Setup Deep Dive)](deployment/setup-deep-dive.md)：volume 結構、環境變數分工、安全考量。

## 6. 疑難排解 (Troubleshooting)

- [Discord slash command sync 超過 8000 bytes](troubleshooting/discord-slash-command-size.md)：Discord 原生 slash command payload 過大。
- [VPN 關閉後 Telegram polling / LLM API 斷線](troubleshooting/docker-dns-vpn.md)：強制使用公共 DNS 修復內網 DNS 解析鏈斷裂。

## 7. 架構原理與深入研究

對於想要深入了解 Hermes Agent 核心設計的使用者，請參閱個人筆記庫：

- [Hermes Agent 核心原理與架構筆記 (LLM-notes)](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)

涵蓋主題：

- Gateway / Agent Loop / Reasoning Layer 架構
- Memory 系統（`MEMORY.md` / `USER.md` / Session search）
- Skills 系統（`SKILL.md` / Skills Hub / Progressive disclosure）
- Session 管理（SQLite + FTS5、lineage tracking）
- Cron 與 Hooks 機制
- MCP 整合

## 相關資源

- [回到專案首頁](../README.md)
- [Hermes Agent 官方文件](https://hermes-agent.nousresearch.com)
- [Hermes Agent GitHub](https://github.com/NousResearch/hermes-agent)
- [個人技術筆記 (LLM-notes)](https://github.com/kaka-lin/LLM-notes/tree/main/Hermes)
