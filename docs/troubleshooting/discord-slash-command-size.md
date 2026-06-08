# Discord slash command sync 超過 8000 bytes

## 症狀

Gateway 啟動時 log 出現：

```text
WARNING gateway.platforms.discord: [Discord] Slash command sync failed:
Failed to upload commands to Discord (HTTP status 400, error code 50035)
In group 'skill' defined in module 'gateway.platforms.discord'
  Command exceeds maximum size (8000)
```

## 這代表什麼

Hermes 會把 installed skills 自動註冊成 Discord native slash commands。當 bundled / installed skills 太多，或 skill command metadata 太長時，Discord 會拒絕整包 slash command payload。

影響範圍：

- **Gateway 會因為未捕捉的 Python 例外而崩潰，並陷入 Crash Loop (不斷重啟)**。
- **Web UI (Dashboard) 會顯示 "Gateway not running"**，因為它無法連上不斷崩潰的 Gateway。
- 必須修復此問題，否則 Hermes 伺服器無法正常運作。

這不是 Docker Compose 設定錯誤，而是 Discord application command payload 限制。

## 解法：減少 Discord 要註冊的 skills

官方 FAQ 對 Telegram slash command payload 類似問題建議用 `skills.platform_disabled` 關閉特定平台的 skill。Discord 也可以採同樣方向：把不需要出現在 Discord slash command menu 的 skills 關掉。

編輯 `~/.hermes/config.yaml`：

```yaml
skills:
  platform_disabled:
    discord:
      # 為了符合 Discord 8000 byte 限制，隱藏大量 UI 按鈕 (AI 仍可自主呼叫)
      - architecture-diagram
      - ascii-art
      - ascii-video
      - excalidraw
      - manim-video
      - p5js
      - popular-web-designs
      - songwriting-and-ai-music
      - webhook-subscriptions
      - himalaya
      - minecraft-modpack-server
      - pokemon-player
      - codebase-inspection
      - github-auth
      - github-code-review
      - github-issues
      - github-pr-workflow
      - github-repo-management
      - mcporter
      - native-mcp
      - heartmula
      - songsee
      - youtube-content
      - audiocraft-audio-generation
      - axolotl
      - clip
      - dspy
      - evaluating-llms-harness
      - fine-tuning-with-trl
      - gguf-quantization
      - grpo-rl-training
      - guidance
      - huggingface-hub
      - llama-cpp
      - modal-serverless-gpu
      - obliteratus
      - outlines
      - peft-fine-tuning
      - pytorch-fsdp
      - segment-anything-model
      - serving-llms-vllm
      - stable-diffusion-image-generation
      - unsloth
      - weights-and-biases
      - whisper
      - obsidian
      - linear
      - nano-pdf
      - ocr-and-documents
      - powerpoint
      - arxiv
      - blogwatcher
      - llm-wiki
      - polymarket
      - openhue
      - xitter
      - systematic-debugging
      - test-driven-development
```

然後重啟：

```bash
docker compose restart hermes
```

如果你不確定有哪些 skill 名稱，可先列出：

```bash
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent skills list
```

## 仍可正常使用嗎？

可以。這個 warning 主要影響 Discord native slash command 同步，不代表 Hermes gateway 或 Discord 訊息處理一定失敗。

若 bot 不回應，優先檢查：

1. `~/.hermes/.env` 是否有 `DISCORD_BOT_TOKEN`
2. `DISCORD_ALLOWED_USERS` / `DISCORD_ALLOWED_ROLES` 是否正確
3. Discord Developer Portal 是否啟用 `MESSAGE CONTENT INTENT`
4. bot 是否在 server channel 被 `@mention`

## 相關參考

- [Discord 整合指南](../platforms/discord.md)
- [Hermes 官方 Discord 文件](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord)
- [Hermes 官方 FAQ](https://hermes-agent.nousresearch.com/docs/reference/faq)
