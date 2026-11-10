# patches/

對上游 `nousresearch/hermes-agent` image 的修改，以 unified diff 維護，build 時由
[apply.py](apply.py) 套用到容器內的 `/opt/hermes`。

## 檔案

- `*.patch` — 每個修改一個 diff，單一真相來源，可直接 PR / 分享。
- `apply.py` — 泛用 applier：讀 `*.patch`，冪等套用，context 不符則明確報錯。
- `.src/` — 重算 diff 用的本地工作區（gitignore，用時再生）。

## 現有 patch

目前對應 base `v2026.9.21`。

- `dingtalk-send-routing.patch` — `plugins/platforms/dingtalk/adapter.py`（v2026.9.x 起
  DingTalk 是 plugin，不在 `gateway/platforms/`）：註冊 `parse_target_ref_fn` 讓
  `dingtalk:cidXXXX==` 被視為 explicit 目標，不會退回 home channel；live adapter 沒有
  該群的 session webhook（cron、跨群發送）時改走官方 robot API
  `groupMessages/send`，cron 獨立程序的 `_standalone_send` 也先試官方 API 再退回
  單一 webhook。
- `runtime-sockets-on-tmpfs.patch` — `gateway/control_socket.py` 與
  `gateway/shutdown_watchdog.py`：當設定 `HERMES_RUNTIME_DIR` 時，將 control 與
  loop-watchdog Unix socket 建在 container-local runtime 目錄，而非掛載的 `/opt/data`。
  Compose 以 `/run/hermes` tmpfs 提供該目錄，避開 Docker Desktop host bind mount 建立
  socket 時的 `Operation not permitted`；未設定環境變數時完全維持上游路徑行為。

升到 v2026.9.21 時移除（上游已處理）：

- `cli-session-source-override.patch` — 壓縮後的續段 session 改為繼承父 session 的
  source，而父 session 已依 `HERMES_SESSION_SOURCE` 決定。
- `stream-consumer-interim-diagnostic.patch` — 上游以同名 `stream_deltas_enabled`
  實作同一修正。
- `registry-optional-check-false-debug.patch` — 上游把 probe 回傳 `False` 改記 INFO
  （原為 WARNING），例外仍為 WARNING；接受 INFO，不再降到 DEBUG。

更早移除：`dingtalk-stream-handler.patch`。根因（SDK 在 import 時不存在，
`_IncomingHandler` 綁到 `object` 後不再重綁）在 v2026.9.14 仍在，但 Dockerfile 現在改成
build 時從上游 lockfile 匯出 `dingtalk` extra 裝進 venv，import 時就有，不需要 patch。

完整 root-cause 與症狀見 [../skills/patch-dingtalk/SKILL.md](../skills/patch-dingtalk/SKILL.md)。

## 重算 / 新增一個 patch

權威 pristine 來源是 **pinned image 內的檔**（不是 GitHub，除非確認逐字一致）：

```bash
TAG=v2026.9.21
P=plugins/platforms/dingtalk/adapter.py    # 目標相對 /opt/hermes 的路徑
mkdir -p "patches/.src/a/$(dirname "$P")" "patches/.src/b/$(dirname "$P")"
docker run --rm "nousresearch/hermes-agent:${TAG}" cat "/opt/hermes/$P" \
  > "patches/.src/a/$P"
cp "patches/.src/a/$P" "patches/.src/b/$P"   # 在 b/ 上改成想要的樣子
# ...編輯 patches/.src/b/$P...
( cd patches/.src && diff -u "a/$P" "b/$P" ) > "patches/my-fix.patch" || true
```

`b/` 必須基於**同一 pinned 版本**改出，否則 diff 會混入無關的上游版本差異。

## 套用 / 驗證

```bash
HERMES_ROOT=/path/to/hermes python3 patches/apply.py    # 本地對某個樹套用
python3 tests/test_patch_apply.py                        # 跑 applier 煙霧測試
```

build 時的套用見根目錄 [Dockerfile](../Dockerfile)。

## PR 回上游 / 分享

`.patch` 本身即 diff：附在 PR，或用 `git format-patch` 形式送出；給朋友就讓對方在其
Hermes 安裝根 `git apply <file>.patch` 或 `patch -p1 < <file>.patch`。
