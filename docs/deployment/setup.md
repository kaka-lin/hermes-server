# Hermes Agent 安裝指南 (Installation Guide)

本文件介紹了 Hermes Agent 的多種安裝方式。

## 1. 本專案快速部署 (docker-compose)

這是針對本專案結構優化過的部署方式，會引導您完成 API key 寫入、平台 token 設定與資料夾權限。

> [!NOTE]
> 關於 `docker-compose.yml` 的設計細節與運作原理，請參閱：[Docker Compose 設計細節 (Setup Deep Dive)](setup-deep-dive.md)

### 部署步驟

請參考 [專案首頁 README](../../README.md) 中的 Quick Start 流程，只要透過幾個簡單指令即可完成部署：

```bash
# 1. 執行 setup wizard
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup

# 2. 複製設定並啟動
cp .env.example ~/.hermes/.env
docker compose up -d
```

## 2. 官方安裝方式 (Official Methods)

如果您偏好使用 Hermes 官方標準提供的安裝途徑，請參考以下分類：

### 2.1 NPM / pip 安裝 (本機部署)

適用於不想用 Docker，直接在 host 上執行的環境：

```bash
# 透過 pip（需要 Python 3.11+）
pip install hermes-agent

# 初始化
hermes setup
hermes gateway run
```

### 2.2 Docker 部署 (Official Docker Methods)

如果您偏好使用官方標準 Docker 路徑，只想拉取現成映像檔並手動管理單一容器：

```bash
# 1. 執行 setup wizard
docker run -it --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent setup

# 2. 啟動 gateway
docker run -d \
  --name hermes \
  --restart unless-stopped \
  -p 8642:8642 \
  -v ~/.hermes:/opt/data \
  --shm-size=1g \
  nousresearch/hermes-agent gateway run

# 3. （可選）啟動 dashboard
# 將 $HOST_IP 換成 gateway 所在主機 IP，例如 192.168.1.100。
docker run -d \
  --name hermes-dashboard \
  --restart unless-stopped \
  -p 9119:9119 \
  -v ~/.hermes:/opt/data \
  -e GATEWAY_HEALTH_URL=http://$HOST_IP:8642 \
  nousresearch/hermes-agent dashboard --host 0.0.0.0 --insecure
```

### 2.3 從原始碼建構 (From Source)

如果您是開發者，需要手動修改原始碼並本地建構映像檔：

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
docker build -t hermes:local -f Dockerfile .
```

## 3. 後續設定 (Next Steps)

完成基礎部署後，請根據您的需求參閱以下進階配置：

- [Allowlist 與授權設定](../guides/allowlist-config.md)
- [瀏覽器自動化指南](../guides/browser-automation.md)
- [Telegram 整合與 Bot 設定指南](../platforms/telegram.md)
- [Discord 全功能安裝與配置指南](../platforms/discord.md)
- [Slack App 設定（Socket Mode）](../platforms/slack.md)
