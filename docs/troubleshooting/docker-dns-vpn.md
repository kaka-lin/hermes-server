# VPN 切換後容器連不上外網

## 症狀

Mac 上的 VPN 開關切換後，host 網路正常，容器對外連線卻全部失效：Discord bot 離線、LLM API 一直逾時。重新打開 VPN 也不一定恢復。

## 原因

- **DNS 解析鏈斷掉**：容器預設經 Docker Desktop 轉給 Mac 當下的 DNS。VPN 關掉後 Mac 回到內網 DNS，可能解析不了外部網域，Docker Desktop 也不一定即時跟上。
- **連線卡在舊路徑**：連線建在 VPN 的虛擬網卡上，網卡消失後 socket 沒收到中斷，一直等到逾時。這一層只有重啟容器才解。

## 解法

[`docker-compose.yml`](../../docker-compose.yml) 已經處理第一層，並讓第二層看得見：

- `dns`：容器的 DNS 直接轉給公共 DNS（預設 `1.1.1.1`、`8.8.8.8`），不經 Mac。網路只能用內部 DNS 時，在 `compose.env` 改 `HERMES_DNS_PRIMARY`、`HERMES_DNS_SECONDARY`。
- `healthcheck`：每 30 秒從容器連 `HERMES_HEALTHCHECK_URL`（預設 `https://discord.com`），連續 3 次失敗標為 `unhealthy`。

`restart: unless-stopped` 不會因為 `unhealthy` 自動重啟。卡住時手動重啟：

```bash
./hermes-run.sh status    # STATUS 顯示 (unhealthy)
./hermes-run.sh restart
```

要自動重啟可以另外跑 [docker-autoheal](https://github.com/willfarrell/docker-autoheal) 之類的工具。

## 確認

```bash
docker inspect --format='{{.HostConfig.Dns}}' hermes            # 預設是 [1.1.1.1 8.8.8.8]，或你設的 HERMES_DNS_*
docker inspect --format='{{.State.Health.Status}}' hermes       # 應為 healthy
```

容器的 `/etc/resolv.conf` 仍是 `nameserver 127.0.0.11`（自訂 network 的內建 DNS），註解裡的 `ExtServers` 才是它轉送的對象，這是正常的。

其他 home 的容器名稱不是 `hermes`，用 `./hermes-run.sh ls` 查。
