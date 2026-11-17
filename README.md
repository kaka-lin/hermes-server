<p align="center">
  <img src="docs/images/hermes-logo.png" alt="Hermes Agent Server logo" width="120">
</p>

# Hermes Agent Server

用 Docker Compose 跑 NousResearch 的 [Hermes Agent](https://hermes-agent.nousresearch.com/docs/)。

以上游 image `nousresearch/hermes-agent:<版本>` 為基底，建出自己的 image（名稱由 `compose.env` 的 `HERMES_IMAGE` 決定），多加了：

- DingTalk SDK（從上游 lockfile 的 `dingtalk` extra 安裝）
- `agent-browser` CLI，讓 skill 能指定要接哪個 host Chrome
- 自訂 skill 用的 Python 套件（[`requirements.txt`](requirements.txt)）
- [`patches/`](patches/README.md) 裡對上游原始碼的修補

## 架構

一個容器服務一個 home。home 是 host 上的 data dir（主 home 是 `~/.hermes`），掛到容器的 `/opt/data`。容器裡跑兩個服務：

| 服務 | 預設 port | 用途 |
| --- | --- | --- |
| Gateway | `8642` | 接訊息平台（Discord、DingTalk 等），並提供 OpenAI 相容 API |
| Dashboard | `9119` | Web 管理介面，需要帳密登入 |

要跑多個 agent 時有兩種隔離方式，可以疊著用：

- **一個 home 多個 profile**：用官方的 `hermes profile create` 建在 `profiles/<名稱>/`，由同一個容器的 gateway 一起帶起來。
- **多個 home**：每個 home 一個容器（`~/.hermes-<名稱>`，容器 `hermes-<名稱>`），用 `./hermes-run.sh new <名稱>` 建立。

怎麼選、怎麼設定見 [Agent、Home 與 Profile](docs/agents-and-profiles.md)。

## 支援的平台

| 平台 | 核心（gateway、dashboard、平台、cron） | 接 host 上的 Chrome |
| --- | --- | --- |
| macOS（Docker Desktop） | 可用 | 可用 |
| Windows（Docker Desktop + Git Bash） | 未實測 | 未實測 |
| Linux | 未實測 | 尚未支援，見[瀏覽器](docs/browser.md#linux) |

平台相關的值（Chrome 路徑等）會自動偵測，要改的話寫在 `platforms/<平台>.env`。

## 快速開始

需要 Docker 與 Compose v2、bash，和一組 LLM provider 的 API key。每一步的說明見[第一次部署](docs/setup.md)。

```bash
# 1. image 設定，然後建 image
cp -n compose.env.example compose.env
./hermes-build.sh

# 2. 準備 data dir，填入 API key 與 dashboard 帳密
mkdir -p ~/.hermes
cp -n .env.example ~/.hermes/.env
cp -n config.example.yaml ~/.hermes/config.yaml
# 編輯 ~/.hermes/.env

# 3. 啟動並檢查
./hermes-run.sh up
./hermes-run.sh cli doctor
```

`./hermes-run.sh up` 不會 build；image 不存在時直接報錯。之後所有 `hermes` 指令都透過 `./hermes-run.sh cli <args>` 在容器裡執行，見 [CLI 指令](docs/cli.md)。

## 文件

| 想做什麼 | 看這份 |
| --- | --- |
| 第一次跑起來 | [第一次部署](docs/setup.md) |
| 查 `hermes-run.sh` 與常用 `hermes` 指令 | [CLI 指令](docs/cli.md) |
| 跑多個 agent（profile 或另開 home） | [Agent、Home 與 Profile](docs/agents-and-profiles.md) |
| 讓 agent 操作 host 上已登入的 Chrome | [瀏覽器](docs/browser.md) |
| 了解 data dir 裡有什麼、怎麼備份 | [Data dir](docs/data-dir.md) |
| 換 model、設 fallback | [模型設定](docs/models.md) |
| 接 Discord、DingTalk | [Discord](docs/platforms/discord.md)、[DingTalk](docs/platforms/dingtalk.md) |
| 修改上游原始碼、跑測試、看本專案的 skill | [patches/](patches/README.md)、[tests/](tests/README.md)、[skills/](skills/README.md) |

### 疑難排解

- [VPN 切換後容器連不上外網](docs/troubleshooting/docker-dns-vpn.md)
- [cron 顯示 OK 卻沒有結果](docs/troubleshooting/cron-nohup-delay-orphan.md)
- [cron 的瀏覽器任務跑到一半停住](docs/troubleshooting/cron-chrome-occlusion-stall.md)

Hermes 本身的功能與設定以[官方文件](https://hermes-agent.nousresearch.com/docs/)為準。
