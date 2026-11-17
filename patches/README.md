# patches/

對上游 image 原始碼的修改，以 unified diff 維護，build 時由 [`apply.py`](apply.py) 套用到容器內的 `/opt/hermes`。`apply.py` 是冪等的，已套用的會跳過，context 不符時讓 build 失敗。

## 檔案

- `*.patch`：每個修改一個 diff，單一真相來源，可以直接附在 PR 或分享。
- `apply.py`：泛用 applier，讀 `*.patch`，冪等套用，context 不符時明確報錯。
- `.src/`：重算 diff 用的本機工作區（不進版控，用時再生）。

## 對應的版本

patch 對應 `compose.env` 的 `HERMES_VERSION`。換版本後套不上時，照[重算](#重算或新增-patch)的步驟對新版本重做。

## 現有 patch

### `dingtalk-send-routing.patch`

改 `plugins/platforms/dingtalk/adapter.py`，讓 `send_message` 能送到指定的 DingTalk 群組：

- 註冊上游的 `target_ref_syntax_fn=parse_nonempty`，`dingtalk:cidXXXX==` 才會被當成明確目標，不會回 `Could not resolve`。
- 純文字 `send_message` 走的 `_standalone_send` 先試官方機器人 API `groupMessages/send`，沒確認送達才退回單一群組的 `DINGTALK_WEBHOOK_URL`。
- live adapter 對 `cid` 群組沒有 session webhook 時也走機器人 API。

回歸測試：[`test_dingtalk_send_routing.py`](../tests/test_dingtalk_send_routing.py)。

### `control-socket-stale-inode.patch`

改 `gateway/control_socket.py`。容器沒有正常結束時，data dir 會留下 `gateway.sock`。在 Docker Desktop 的 bind mount 上，新容器 stat 不到也刪不掉它，bind 回 `EADDRINUSE`，gateway 每次啟動都失敗、被 s6 無限重啟。

上游遇到「不支援建 socket」的錯誤時，會改在容器內的暫存目錄 listen，並在 data dir 放指標檔讓 CLI 找到 gateway，但刻意排除 `EADDRINUSE`。這個 patch 讓「`EADDRINUSE` 且容器內 stat 不到那個路徑」也走同一個 fallback；真的有另一個 gateway 在跑時，它的 socket 看得到，照樣報錯。

回歸測試：[`test_control_socket_stale_inode.py`](../tests/test_control_socket_stale_inode.py)。

DingTalk SDK 不是 patch，而是 Dockerfile 在 build 時從上游 lockfile 的 `dingtalk` extra 安裝；原因與症狀見 [`skills/patch-dingtalk/SKILL.md`](../skills/patch-dingtalk/SKILL.md)。

## 重算或新增 patch

pristine 來源一律取自 pin 版本的 image，不從 GitHub 抓，否則 diff 會混入無關的版本差異：

```bash
TAG="$(sed -n 's/^HERMES_VERSION=//p' compose.env)"
P=plugins/platforms/dingtalk/adapter.py    # 相對 /opt/hermes 的路徑
mkdir -p "patches/.src/a/$(dirname "$P")" "patches/.src/b/$(dirname "$P")"
docker run --rm --entrypoint cat "nousresearch/hermes-agent:${TAG}" "/opt/hermes/$P" > "patches/.src/a/$P"
cp "patches/.src/a/$P" "patches/.src/b/$P"
# 編輯 patches/.src/b/$P
( cd patches/.src && diff -u "a/$P" "b/$P" ) > patches/my-fix.patch || true
```

`b/` 必須基於同一個 pin 的版本改出，否則 diff 會混入無關的上游版本差異。

## 套用與驗證

```bash
HERMES_ROOT=/path/to/hermes python3 patches/apply.py    # 在本機對某個原始碼樹套用
python3 tests/test_patch_apply.py                        # apply.py 的煙霧測試
```

build 時的套用見根目錄的 [Dockerfile](../Dockerfile)。改完 patch 用 `./hermes-build.sh` 重建，再跑對應的回歸測試。

## PR 回上游或分享

`.patch` 本身就是 diff：可以附在 PR，或用 `git format-patch` 的形式送出。分享給別人時，讓對方在 Hermes 安裝根目錄執行 `git apply <file>.patch` 或 `patch -p1 < <file>.patch`。
