# VPN 切換造成 hermes 容器卡死

> [!IMPORTANT]
> 這個問題不是「沒有 VPN 就沒網路」——host 本身有對外連線能力。真正的觸發點是 **VPN 開→關（或不穩定切換）的瞬間**，會把 Python 容器推進兩種卡死狀態：
>
> - **DNS 解析鏈斷裂**：container 透過 host DNS chain 解析時，內網 DNS 無法解析外部域名
> - **Python socket 黏死**：底層 socket 綁在已消失的 VPN 虛擬網卡（`utun`），DNS resolver 快取也死咬舊路徑
>
> 同樣情境下，OpenClaw（Node.js）光靠 `dns:` 設定就能撐過去，因為它的 DNS / retry 機制比 Python 積極。但 Hermes（Python）需要**雙層防禦**：
>
> - `dns:` 強制 container 用公共 DNS，跳過 host DNS chain（解決第一層）
> - `healthcheck` 持續探測外網連通，在 socket 卡死時把容器標為 `unhealthy`，作為手動或自動重啟的觸發訊號（解決第二層）
>
> 這份文件記錄的就是這兩層設定。

## 症狀

VPN 開→關（或不穩定切換）後，`hermes` container 對外服務全部失聯：

- **Discord bot 立即顯示下線**：gateway WebSocket 斷開且無法重連
- **Telegram polling 卡死**：`getUpdates` 持續 stall 直到 timeout
- **LLM API 全面 timeout**：Anthropic / OpenAI 請求都打不出去

即使 VPN 重新打開、host 端 DNS 也已正常（`dig gateway.discord.gg` 有結果），container 內部仍可能持續卡死——Python socket 與 DNS resolver 已經黏死在已消失的舊網卡上，只有把整個容器重啟才能重新初始化網路堆疊。

## 根本原因

### 第一層：Docker DNS 解析鏈斷裂

Docker container 預設的 DNS 解析路徑：

```text
Container
  → 127.0.0.11 (Docker 內建 DNS)
    → 192.168.65.7 (Docker Desktop 的 host gateway)
      → Mac 主機目前使用的 DNS
```

當 VPN **開著**時，Mac 使用 VPN 提供的 DNS，能正常解析 `api.telegram.org`、`api.anthropic.com` 等外部域名。

當 VPN **關閉**後，Mac 的 DNS 回到公司 / 內網 DNS server。內網 DNS 通常：

- 無法解析公司網域以外的外部域名，或
- 解析速度不穩定，導致 long polling 的 TCP 連線在等待過程中被視為死連線而切斷。

Discord gateway 的 WebSocket 長連線、Telegram long polling (`getUpdates`)、Anthropic / OpenAI 的 streaming 都是會掛著等很久的長連線，特別容易受到 DNS 不穩或 NAT/防火牆的 idle TCP timeout 影響。

### 第二層：Python 與 Node.js 的重連韌性差異

**這層是 Hermes 跟 OpenClaw 在同環境下行為差異的關鍵，也是這份文件最重要的觀察。**

最初我們參考 OpenClaw 的[同類修復](https://github.com/kaka-lin/openclaw-server/blob/main/docs/troubleshooting/docker-dns-vpn.md)，假設只要加 `dns:` 就能解決——對 Node.js 服務確實如此。但同樣設定套到 Hermes，VPN 切換後仍然卡死。差異來自底層語言處理網路中斷的方式：

| 行為 | Node.js（OpenClaw） | Python（Hermes） |
| --- | --- | --- |
| DNS 快取 | 每次請求重新解析 | `asyncio` resolver 會快取並黏死舊結果 |
| Socket 綁定 | 連線失敗後快速釋放 | Socket 綁定在 VPN 虛擬網卡（`utun`），網卡消失後卡在 timeout |
| 重連行為 | 內建 retry 機制迅速發起新連線 | 連線池未重新初始化，持續嘗試已失效的路徑 |
| VPN 切換後 | 網路一恢復即自動重連 | 拋出 `[Errno -2] Name or service not known` 或無限 stall |

**具體流程**：

1. Hermes 在 VPN 開啟時啟動，底層 Socket 綁定到 VPN 的虛擬網卡
2. 關閉 VPN → 該網卡消失
3. Python 的 Socket 沒有立刻收到 TCP RST，陷入 timeout 等待
4. 即使最終偵測到斷線並嘗試重連，DNS resolver 因未重新初始化而繼續死咬舊路徑
5. 結果：polling stall、LLM timeout，必須把整個容器重啟才能恢復

## 解決方案

### 1. 指定公共 DNS（防禦 DNS 解析鏈斷裂）

在 `docker-compose.yml` 的 `hermes` service 加上 `dns`，強制 container 跳過 host DNS chain，直接使用公共 DNS：

```yaml
services:
  hermes:
    # ... 其他設定 ...

    # 內網 DNS 無法穩定解析外部域名，強制使用公共 DNS
    # 跳過 Docker Desktop ↔ host DNS chain
    dns:
      - 1.1.1.1
      - 8.8.8.8
```

> [!NOTE]
> 這層只解決 DNS。對 Hermes 而言**並不足夠**——VPN 切換造成的 Python socket 卡死還在。實際上我們套用這層後 Hermes 仍會卡死，所以接著加上 healthcheck 才真正解決。如果你的服務是 Node.js（例如 OpenClaw），通常到這裡就夠了。

### 2. Healthcheck 持續探測外網連通（防禦 Socket 卡死）

既然 Python 在 VPN 切換後會陷入 socket 卡死狀態，讓 Docker 定期從容器內部探測外網——一旦探測失敗，把容器標為 `unhealthy`，作為「該重啟了」的明確訊號：

```yaml
services:
  hermes:
    # ... 其他設定 ...
    restart: unless-stopped

    healthcheck:
      test: ["CMD", "python3", "-c",
        "import urllib.request; urllib.request.urlopen('https://discord.com', timeout=5)"]
      interval: 30s        # 每 30 秒檢查一次
      timeout: 10s         # 10 秒沒回應就算失敗
      retries: 3           # 連續 3 次失敗才判定不健康
      start_period: 15s    # 剛啟動時給 15 秒準備
```

設定後重啟 container 套用設定：

```bash
docker compose down && docker compose up -d
```

> [!IMPORTANT]
> Docker 原生的 `restart: unless-stopped` **不會**在 healthcheck 失敗時自動重啟。容器進入 `unhealthy` 狀態後，需要外部機制觸發重啟（例如 [autoheal](https://github.com/willfarrell/docker-autoheal)）或手動執行 `docker compose restart hermes`。Healthcheck 本身的價值在於**快速暴露問題**——讓你在 Discord 還沒被使用者抱怨之前就察覺，而不是等到下次打開 app 才發現 bot 已經下線好幾個小時。

### 3. 手動急救

容器卡死時，**不要靠重開 VPN 救它**。即使 VPN 重新打開、host 端 DNS 恢復正常，容器內部的 Python socket 與 DNS resolver 仍黏死在原本那條已消失的 utun 介面，不會跟著重新初始化。

直接重啟容器：

```bash
# 確認 healthcheck 狀態
docker inspect --format='{{.State.Health.Status}}' hermes

# 重啟容器，讓 Python 重新初始化網路堆疊
docker compose restart hermes
```

## 驗證

確認 container 內的 `/etc/resolv.conf` 已改為公共 DNS：

```bash
docker exec hermes cat /etc/resolv.conf
```

預期輸出：

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
```

確認 healthcheck 狀態：

```bash
docker inspect --format='{{.State.Health.Status}}' hermes
```

預期輸出為 `healthy`。如果顯示 `unhealthy`，表示容器已偵測到外網不通，需要重啟。

## 為什麼預設沒這個設定

這是環境特有的問題。多數人的網路環境（家用路由器或標準公司網路）的 DNS 都能穩定解析外部域名，且不會頻繁切換 VPN，因此：

- `dns:` 不需要——host DNS 本來就能用
- `healthcheck` 不需要——容器不會陷入 socket 黏死狀態

只有同時符合「host DNS 是內網 DNS（無法解析外部域名）」+「會頻繁開關 VPN」這兩個條件的環境，才需要這份文件描述的雙層防禦。

## 常見疑問：Mac 網路介面已設定 8.8.8.8，Docker 不是也會吃到嗎？

理論上是這樣，但實際上不可靠，原因有三：

1. **Docker Desktop 不即時同步 DNS 變更**：VPN 斷線時 Mac 的 DNS 切回 Ethernet 的設定，但 Docker Desktop VM 可能仍快取 VPN 的 DNS，有一段空窗期。
2. **傳遞路徑多且脆弱**：`container → 127.0.0.11 → 192.168.65.7 → Mac system resolver → 8.8.8.8`，中間任何一層異常都會失效。
3. **macOS 多介面 DNS 優先序複雜**：VPN 與 Ethernet 同時存在時，`scutil --dns` 的 resolver 順序並非單純依介面排序，VPN 斷線後其 DNS 條目有時不會立即清除。

`dns:` 寫進 docker-compose.yml 後，container 的 `/etc/resolv.conf` **直接就是** `nameserver 1.1.1.1`，完全跳過 Docker Desktop 的 DNS 同步機制，行為確定且不受 Mac 當下網路狀態影響。因此即使 Mac Ethernet 已設公共 DNS，保留這個設定仍然值得。

## 是否需要同時對 dashboard 設定？

通常不用。Dashboard 只連 gateway（`hermes:8642`），不直接打外網。但若 dashboard 也有 outbound HTTP 行為（例如 health check 外部資源），同樣可加 `dns:`。

## 相關參考

- [docker-autoheal](https://github.com/willfarrell/docker-autoheal) — 自動重啟 unhealthy 容器的第三方工具
