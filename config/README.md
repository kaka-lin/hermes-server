# Host 設定檔

host 上要改的設定都在這裡。repo 的腳本每次執行都會讀，改了下次 `./hermes-run.sh up` 就生效。

真檔是機器專屬的設定，不進版控；這裡只追蹤 `.example` 範本和說明。第一次用時把範本複製成去掉 `.example` 的檔名。

| 檔案 | 誰讀 | 管什麼 |
| --- | --- | --- |
| `compose.env` | `hermes-run.sh`、`hermes-build.sh` 交給 Compose | 主 home 的 image 版本、port、資源上限等，見 [Compose 變數](../docs/setup.md#compose-變數) |
| `platforms/<平台>.env` | `hermes-run.sh`、`start-browsers.sh` | 跟平台有關的值（Chrome 路徑、UID/GID 等），可不建，見[平台設定](../docs/setup.md#平台設定) |
| `browsers.conf` | `start-browsers.sh`；`hermes-run.sh` 同步進容器給 `cdp_proxy.py` | host 上的 Chrome profile 與 CDP port，見[瀏覽器](../docs/browser.md) |
| `agents/<名稱>.conf` | `hermes-run.sh -a <名稱>`、`--all`、`ls` | 主 home 以外的 home，由 `new` 產生，見 [agents/README.md](agents/README.md) |

## 和根目錄範本的差別

根目錄的 [`.env.example`](../.env.example)、[`config.example.yaml`](../config.example.yaml) 是 Hermes 本身的設定範本。它們只在建 home 時複製進 data dir（`~/.hermes`）一次，之後要改的是 data dir 裡那份，改 repo 裡的範本不會生效。API key、bot token 只填在 `~/.hermes/.env`。
