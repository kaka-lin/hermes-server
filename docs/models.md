# 模型設定

模型設定在每個 profile 的 `config.yaml`，憑證分開放：

- `config.yaml`：用哪個 provider、哪個 model（`model:`、`fallback_providers:`、`auxiliary:`）
- `.env`：API key，例如 `openai-api` 讀 `OPENAI_API_KEY`
- `auth.json`：OAuth 登入（例如 `openai-codex`），只在 home 根目錄有一份，所有 profile 共用

檔案位置見 [Data dir](data-dir.md)。改完 `config.yaml` 執行 `./hermes-run.sh cli gateway restart` 套用。

## `model` 區塊

[`config.example.yaml`][config-example] 的設定：

```yaml
model:
  provider: openai-api
  base_url: https://api.openai.com/v1
  default: gpt-5.6-terra
  api_mode: codex_responses
```

- **`provider`**：provider ID。常用的有：
  - `openai-api`：OpenAI API key
  - `openai-codex`：ChatGPT 帳號登入
  - `anthropic`
  - `openrouter`
  - `gemini`
  - `custom`：接自架或其他相容端點

  怎麼查其他 provider 見[查可用的 provider 與 model](#查可用的-provider-與-model)。

- **`base_url`**：API 端點。

- **`default`**：預設 model ID。

- **`api_mode`**：送出請求用的格式。

  | 值 | 格式 |
  | --- | --- |
  | `chat_completions` | OpenAI 相容的 `/v1/chat/completions`，多數端點的預設 |
  | `codex_responses` | Responses API，OpenAI Codex 與 xAI 用這個 |
  | `anthropic_messages` | Anthropic Messages 格式，給 Anthropic 相容的 proxy |

  留空時 Hermes 依 `base_url` 判斷；`hermes model` 精靈會明確寫入。

## 查可用的 provider 與 model

- **`./hermes-run.sh cli model`**：互動精靈先列出所有 provider，選好再列出那個 provider 的 model。只想看清單時看完取消，設定不會變。要在終端機執行。
- **`./hermes-run.sh cli model --refresh`**：清掉精靈的 model 快取，重新向每個 provider 的 `/v1/models` 抓最新清單。新 model 沒出現在選單時用它。
- **聊天裡的 `/model`**：在 Discord 等平台對 bot 送 `/model`，列出目前的 model，以及已設好憑證的 provider 和各自的部分 model。`/model <model> --provider <provider>` 只換這個對話，加 `--global` 才寫進 `config.yaml`。

補充資料：

- 官方 [Providers][providers]：完整的 provider 清單與各自的設定方式
- 官方 [model catalog](https://hermes-agent.nousresearch.com/docs/api/model-catalog.json)：model ID 清單

## 換 model

```bash
./hermes-run.sh cli model                              # 互動精靈：選 provider、登入或填 key、選 model
./hermes-run.sh cli config set model.default <model>   # 只換 model ID
```

也可以直接編輯 `config.yaml` 的 `model:` 區塊。`cli model` 要在終端機執行，`hermes-run.sh` 偵測到終端機時才會加 `-it`。

## 登入 OpenAI Codex

用 ChatGPT 帳號（`openai-codex`）而不是 API key 時，要先登入：

```bash
./hermes-run.sh cli auth add openai-codex
```

預設走 device code：照畫面上的網址與代碼在任一台瀏覽器完成登入。憑證寫進 home 根目錄的 `auth.json`，同一個 home 的 profile 都讀這一份，不用每個 profile 各登入一次；換 home 要在那個 home 再登入一次。之後 refresh 失敗時，重跑同一個指令。

`./hermes-run.sh cli auth list` 列出已登入的憑證，`cli auth --help` 看其他子指令。

## Fallback

主 model 遇到下列情況時，Hermes 依序改用 `fallback_providers` 裡的 model：

- rate limit（429）
- 5xx
- 連線錯誤
- 401/403/404
- 連續空回應

依官方 [Fallback Providers][fallback]：fallback 以一個 turn 為單位，下一則訊息又會先用主 model；換 provider 會讓 prompt cache 失效。

[`config.example.yaml`][config-example] 用 ChatGPT 帳號登入的 Codex 當 fallback：

```yaml
fallback_providers:
  - provider: openai-codex
    model: gpt-5.6-terra
    base_url: https://chatgpt.com/backend-api/codex
```

用 CLI 管理：

```bash
./hermes-run.sh cli fallback          # 列出主 model 與 fallback 清單
./hermes-run.sh cli fallback add      # 用和 hermes model 相同的選單新增一筆
./hermes-run.sh cli fallback remove
./hermes-run.sh cli fallback clear
```

每個 fallback 的 provider 都要先備好 key 或登入，否則切過去也會失敗。

## Auxiliary

`auxiliary:` 設定副任務用的 model，每個任務一個 key，例如：

- `vision`：圖片分析
- `compression`：壓縮對話脈絡
- `title_generation`：session 標題
- `approval`：判斷指令要不要核准
- `web_extract`、`session_search`、`kanban_decomposer`、`curator` 等

預設 `provider: auto`，依序嘗試（前一個失敗才走下一個）：

1. 主 provider
2. 該任務的 `fallback_chain`
3. `fallback_providers`

`config.example.yaml` 把它們都設成較便宜的 `gpt-5.6-luna`：

```yaml
auxiliary:
  vision:
    provider: auto
    model: gpt-5.6-luna
```

## 每個 profile 各自設定

每個 profile 有自己的 `config.yaml` 與 `.env`，model 各設各的。對 profile 下指令加 `-p <名稱>`：

```bash
./hermes-run.sh cli -p <名稱> model
./hermes-run.sh cli -p <名稱> config set model.default <model>
./hermes-run.sh cli -p <名稱> fallback
```

`./hermes-run.sh cli profile list` 的 Model 欄列出每個 profile 目前用的 model。

[providers]: https://hermes-agent.nousresearch.com/docs/integrations/providers
[fallback]: https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers
[config-example]: ../config.example.yaml
