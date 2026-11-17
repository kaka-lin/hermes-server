# 其他 Home 的容器設定

主 home（`~/.hermes`）以外，每個 home 在這裡有一個 `<名稱>.conf`，寫這個 home 的容器怎麼起：

- data dir
- 容器名稱
- 對外 port
- image 版本

> Hermes 自己的設定不在這裡，在 data dir 的 `.env` 與 `config.yaml`。

## 誰寫、誰讀

- `./hermes-run.sh new <名稱>` 產生 `<名稱>.conf`，並自動挑好 port，一般不用手寫。
- `./hermes-run.sh up|down|restart|logs|cli -a <名稱>` 讀這個檔，再交給 Docker Compose。
- `--all` 和 `ls` 會掃過這裡全部的 `.conf`。

> `*.conf` 是機器專屬的設定，被 repo 的 [`.gitignore`](../../.gitignore) 忽略，只追蹤範本 [`agent.conf.example`](agent.conf.example)。

## Port

每個 home 對外開三個 port，對到容器內固定的 port：

| 用途 | 容器內 | 主 home | `new` 從哪裡往上挑 |
| --- | --- | --- | --- |
| Gateway | `8642` | `8642` | `8650` |
| Dashboard | `9119` | `9119` | `9120` |
| Webhook | `8644` | `8644` | `8650`，和 gateway 共用同一段 |

`new` 挑 port 時會跳過：

- 已被佔用的 port
- 已寫在其他 `.conf` 的 port
- 列在 `config/browsers.conf` 的 port

從 `8650` 開始，是為了避開官方平台預設的 `8642`–`8646`。

home 和 profile 怎麼選、怎麼設定，見 [Agent、Home 與 Profile](../../docs/agents-and-profiles.md)。
