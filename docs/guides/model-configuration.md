# 模型與備援設定指南 (Model & Fallback Configuration)

Hermes Agent 將「機密設定（如 API Keys）」與「一般設定（如選用的模型）」明確分開。無論你是直接在本地端 (Local) 跑 CLI，還是透過 Docker Compose 部署，底層依賴的設定檔位置與格式都是相同的。

本指南將說明如何設定預設模型 (Model) 以及備用模型 (Fallback Model)，並區分 Local 與 Docker 的操作差異。

## 1. 設定檔分工

Hermes 所有的運行時設定皆放置於 `~/.hermes/` 目錄下（Docker Compose 預設會將此目錄掛載到容器內）。

- **`~/.hermes/.env`**：專門用來存放機密資訊，例如 API Keys（`GEMINI_API_KEY`、`OPENROUTER_API_KEY` 等）。
  > **注意：** `.env` 內的 `LLM_MODEL` 變數已不再生效，僅供參考，請勿在此設定預設模型。
- **`~/.hermes/config.yaml`**：存放非機密的系統設定，包含你想設定的 `model` 和 `fallback_providers`。

## 2. 如何設定預設模型 (Default Model)

官方推薦透過 CLI 指令來設定，這會自動幫你寫入對應的檔案；當然你也可以選擇直接手動編輯 `config.yaml`。

### 方法 A：使用 CLI 設定（推薦）

- **原生 Local 環境**：

  透過互動選單設定：

  ```bash
  hermes model
  ```

  或透過單行指令快速設定：

  ```bash
  hermes config set model anthropic/claude-opus-4.6
  ```

- **Docker 環境**：

  由於 Hermes 的 Docker Image 封裝了執行環境，請透過啟動暫時性容器來進行設定（會自動掛載並寫入你本機的 `~/.hermes` 資料夾）：

  透過互動選單設定：

  ```bash
  docker run -it --rm \
    -v ~/.hermes:/opt/data \
    nousresearch/hermes-agent model
  ```

  或透過單行指令快速設定：

  ```bash
  docker run --rm \
    -v ~/.hermes:/opt/data \
    nousresearch/hermes-agent config set model anthropic/claude-opus-4.6
  ```

### 方法 B：手動修改設定檔

打開 Host 機器上的 `~/.hermes/config.yaml`，找到 `model` 區塊並修改 `default` 屬性：

```yaml
model:
  default: anthropic/claude-opus-4.6
  provider: auto
  base_url: https://openrouter.ai/api/v1
```

*(請確保在 `~/.hermes/.env` 中已填寫對應的 API Key)*

## 3. 如何設定備援機制 (Fallback Model)

當預設的模型連線失敗或超時（例如遇到 HTTP 503 超載），Hermes 會自動切換去嘗試你設定的備用模型。

目前 Fallback 設定沒有像 `hermes model` 這樣的互動式選單，你必須透過單行指令或手動修改 `config.yaml`。在較新版本的 Hermes 中，推薦使用明確指定 Provider 與 Model 的寫法：

### 方法 A：使用單行指令設定 (Docker 環境)

你可以直接使用 `config set` 指令來分別設定 fallback 的 provider 與 model：

```bash
docker run --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent config set fallback_model.provider openai

docker run --rm \
  -v ~/.hermes:/opt/data \
  nousresearch/hermes-agent config set fallback_model.model gpt-5.5
```

### 方法 B：手動修改設定檔 (Fallback)

1. 打開 `~/.hermes/config.yaml`。

2. 在最下方加入（或找到）`fallback_model` 區塊，並明確指定你要的備用服務商與模型名稱（以下使用 OpenAI 的 GPT-5.5 為例）：

    ```yaml
    fallback_model:
      provider: openai
      model: gpt-5.5
    ```

    > **注意：**
    > 你必須在 `~/.hermes/.env` 裡面事先準備好這個備用 Provider 的 API Key（以上方為例，就是 `OPENAI_API_KEY`），否則切換過去也會因為沒有權限而失敗。

## 4. 儲存與套用設定

存檔後，讓系統重新載入設定：

- **原生 Local 環境**：

  如果您有在跑 Gateway 服務，請重新啟動讓設定生效（若是純 CLI 對話則下一次執行即會生效）：

  ```bash
  hermes gateway
  ```

- **Docker 環境**：

  修改設定後，必須讓容器載入新設定。

  如果容器**尚未啟動**，請執行：

  ```bash
  docker compose up -d
  ```

  如果容器**已經在運行中**，只要重啟服務即可套用新設定：

  ```bash
  docker compose restart hermes
  ```

## 5. 附錄：查詢支援的模型清單

如果在手動設定 `config.yaml`（例如 Fallback Model）時，不確定你想要使用的模型精確名稱（Model ID）為何，你可以參考 Hermes 官方持續更新的「模型目錄」：

- **[Hermes Model Catalog (JSON)](https://hermes-agent.nousresearch.com/docs/api/model-catalog.json)**

> **小技巧：**
> 如果你是使用像 OpenAI 這類本身支援度極高的 Provider，其實可以直接在 [OpenAI 官方網站](https://platform.openai.com/docs/models) 查看最新的型號 ID（如 `gpt-4o`、`gpt-5.5`、`o1-mini`）。因為 Hermes 底層會直接把你輸入的字串送給 API 端點，所以只要官方有開，通常填上去就能直接通！
