# 第一次部署

從零把主 home（`~/.hermes`，容器 `hermes`）跑起來。以下指令都在 repo 根目錄執行。

需要：

- Docker 與 Compose v2（macOS、Windows 用 Docker Desktop）、bash、rsync
- 一組 LLM provider 的 API key。`config.example.yaml` 用 OpenAI API，所以要 `OPENAI_API_KEY`；換 provider 見[模型設定](models.md)

## 1. 建 image

```bash
cp -n compose.env.example compose.env
./hermes-build.sh
```

`compose.env`（不進版控）決定 image，改了要重建：

| 變數 | 用途 |
| --- | --- |
| `HERMES_IMAGE` | 建出來的 image 名稱，預設 `kakalin/hermes-agent` |
| `HERMES_VERSION` | 上游 base image 的 tag，也是建出來的 image tag |
| `AGENT_BROWSER_VERSION` | 裝進 image 的 `agent-browser` 版本 |

`./hermes-build.sh <tag>` 建指定版本，其他旗標（例如 `--no-cache`）原樣交給 `docker compose build`。

`patches/` 只對應 pin 的版本。換版本後 patch 套不上時，build 會在 `apply.py` 停下，見 [patches/README.md](../patches/README.md)。

## 2. 準備 data dir

```bash
mkdir -p ~/.hermes
cp -n .env.example ~/.hermes/.env
cp -n config.example.yaml ~/.hermes/config.yaml
```

`cp -n` 不會覆蓋已有的檔案。沒複製的也沒關係：容器第一次啟動時，會用上游預設補上缺少的 `.env`、`config.yaml`、`SOUL.md`。

設定分兩處：

- `~/.hermes/.env`：Hermes 讀的機密（API key、平台 token、dashboard 帳密），值會蓋過容器的環境變數。
- repo 的 `compose.env`：只給 Compose 用，見 [Compose 變數](#compose-變數)。

## 3. 填入 API key 與帳密

編輯 `~/.hermes/.env`：

```ini
OPENAI_API_KEY=sk-...
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=your-user
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=use-a-long-unique-password
```

- 不設 dashboard 帳密時，會用 `docker-compose.yml` 裡的不安全預設值。
- `API_SERVER_KEY` 是 OpenAI 相容 API 的金鑰。`.env` 裡沒有時，容器第一次啟動會自動產生一組寫進去；要從外部呼叫 API 時，到 `.env` 查這個值，或自己設一組至少 16 個字元的值。
- 接訊息平台見 [Discord](platforms/discord.md)、[DingTalk](platforms/dingtalk.md)。

## 4. 啟動與確認

```bash
./hermes-run.sh up
./hermes-run.sh status            # STATUS 出現 (healthy)
./hermes-run.sh cli doctor
./hermes-run.sh cli profile list  # Gateway 欄是 running
```

- `up` 會先把 repo 的 `scripts/` 和 `browsers.conf` 同步進 data dir，再以 `docker compose up -d --no-build --pull never` 啟動。沒有 `browsers.conf` 只會印警告，不影響 gateway；要讓 agent 用 host 上的 Chrome 再看[瀏覽器](browser.md)。image 不存在時直接報錯，不會自動 build。
- `doctor` 的 Configuration Files 段落要有 `API key or custom endpoint configured`。
- healthy 來自 healthcheck：每 30 秒從容器連一次 `HERMES_HEALTHCHECK_URL`（預設 `https://discord.com`）。
- 用瀏覽器開 <http://localhost:9119>，以剛才的帳密登入 dashboard。

有錯誤時看 `./hermes-run.sh logs`，或查[疑難排解](troubleshooting/)。

## 改設定後怎麼套用

| 改了什麼 | 怎麼套用 |
| --- | --- |
| data dir 的 `.env`、`config.yaml` | `./hermes-run.sh cli gateway restart` |
| `.env` 裡的 dashboard 帳密 | `./hermes-run.sh restart` |
| `compose.env` 的 image 設定 | `./hermes-build.sh`，再 `./hermes-run.sh up` |
| 其他 Compose 變數 | `./hermes-run.sh up` |

`cli gateway restart` 只重啟 gateway，新的 gateway 會重新讀 `.env`、`config.yaml`，見 [CLI 指令](cli.md#gateway)；dashboard 是另一個程式，要靠 `restart` 才會重新讀 `.env`。`restart` 是 `docker compose restart`：重啟容器裡的程式，但不重建容器，所以 Compose 變數改了要靠 `up` 重建。

## Compose 變數

`docker-compose.yml` 讀這些變數，括號內是預設值：

| 變數 | 用途 |
| --- | --- |
| `HERMES_IMAGE`（`kakalin/hermes-agent`） | image 名稱 |
| `HERMES_VERSION`（`v0.23.1`） | 要跑的 image tag |
| `AGENT_BROWSER_VERSION`（`0.26.0`） | build 時裝的 `agent-browser` 版本 |
| `HERMES_DATA_DIR`（`~/.hermes`） | 掛到 `/opt/data` 的 data dir |
| `HERMES_CONTAINER_NAME`（`hermes`） | 容器名稱 |
| `HERMES_GATEWAY_PORT`（`8642`） | host 上的 gateway port |
| `HERMES_DASHBOARD_PORT`（`9119`） | host 上的 dashboard port |
| `HERMES_DASHBOARD`（`1`） | 是否在容器裡跑 dashboard |
| `HERMES_MEMORY_LIMIT`（`6G`）、`HERMES_CPU_LIMIT`（`2.0`） | 容器資源上限 |
| `HERMES_SHM_SIZE`（`1g`） | Chromium 用的共享記憶體 |
| `TZ`（`Asia/Taipei`） | 容器時區 |
| `CDP_HOST`（`host.docker.internal`） | `cdp_proxy.py` 轉發 CDP 的目標，見[平台設定](#平台設定) |
| `HERMES_UID`、`HERMES_GID`（空） | 容器裡 `hermes` 使用者改用的 UID/GID，見[平台設定](#平台設定) |
| `HERMES_DNS_PRIMARY`（`1.1.1.1`）、`HERMES_DNS_SECONDARY`（`8.8.8.8`） | 容器用的 DNS，原因見 [VPN 切換後容器連不上外網](troubleshooting/docker-dns-vpn.md) |
| `HERMES_HEALTHCHECK_URL`（`https://discord.com`） | healthcheck 探測的網址，連不上就標為 unhealthy |
| `HERMES_API_CORS_ORIGINS`（`*`） | OpenAI 相容 API 允許的 CORS 來源 |

主 home 的值寫在 `compose.env`，或在指令前設環境變數；其他 home 寫在 `agents/<名稱>.conf`。

## 平台設定

跟平台有關的值放在 `platforms/<平台>.env`（不進版控，範本是同目錄的 `.example`）。[`platforms/detect.sh`](../platforms/detect.sh) 用 `uname -s` 判斷平台（`macos`、`linux`、`windows`），偵測錯時用 `HERMES_PLATFORM=<平台>` 指定。檔案不存在或沒填的值，自動用預設：

| 變數 | 誰用 | 預設 |
| --- | --- | --- |
| `CHROME` | `start-browsers.sh` | macOS 的 Chrome 安裝路徑；Linux 從 PATH 找 `google-chrome`、`chromium`；Windows 沒有預設，要填 |
| `BROWSER_DATA_DIR` | `start-browsers.sh` | `~/.hermes/browser` |
| `CDP_HOST` | 容器裡的 `cdp_proxy.py` | `host.docker.internal` |
| `HERMES_UID`、`HERMES_GID` | 容器啟動時 | 空，不改。Linux 上填 `id -u`、`id -g`，容器才寫得進 data dir |

`hermes-run.sh` 會把這個檔案和 `compose.env` 一起交給 Compose，同名的值以平台設定為準。macOS 上什麼都不用建。

## 下一步

- [CLI 指令](cli.md)
- [Agent、Home 與 Profile](agents-and-profiles.md)
- [瀏覽器](browser.md)
- [Data dir](data-dir.md)
