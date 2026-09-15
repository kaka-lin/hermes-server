# patches/

對上游 `nousresearch/hermes-agent` image 的修改，以 unified diff 維護，build 時由
[apply.py](apply.py) 套用到容器內的 `/opt/hermes`。

## 檔案

- `*.patch` — 每個修改一個 diff，單一真相來源，可直接 PR / 分享。
- `apply.py` — 泛用 applier：讀 `*.patch`，冪等套用，context 不符則明確報錯。
- `test_apply.py` — apply.py 的 stdlib 煙霧測試（`python3 patches/test_apply.py`）。
- `.src/` — 重算 diff 用的本地工作區（gitignore，用時再生）。

## 現有 patch

目前對應 base `v2026.9.14`。

- `dingtalk-send-routing.patch` — `plugins/platforms/dingtalk/adapter.py`（v2026.9.x 起
  DingTalk 是 plugin，不在 `gateway/platforms/`）：註冊 `parse_target_ref_fn` 讓
  `dingtalk:cidXXXX==` 被視為 explicit 目標，不會退回 home channel；live adapter 沒有
  該群的 session webhook（cron、跨群發送）時改走官方 robot API
  `groupMessages/send`，cron 獨立程序的 `_standalone_send` 也先試官方 API 再退回
  單一 webhook。
- `cli-session-source-override.patch` — `agent/conversation_compression.py`：讓明確設定的
  `HERMES_SESSION_SOURCE` 優先於 CLI 硬編碼的 `platform="cli"`，供 cron 以唯一 tag
  精準彙總單次 token／API usage。上游 v2026.9.14 的 `run_agent.py` 已經這樣做，只剩
  上下文壓縮後另開的續段 session 還是舊順序，漏掉會讓壓縮過的 run 少算。這個變數
  只能在單次呼叫時設定，不要放進 `/opt/data/.env`，否則 gateway 上所有平台的 session
  都會被貼同一個 tag。

已移除：`dingtalk-stream-handler.patch`。根因（SDK 在 import 時不存在，
`_IncomingHandler` 綁到 `object` 後不再重綁）在 v2026.9.14 仍在，但 Dockerfile 現在改成
build 時從上游 lockfile 匯出 `dingtalk` extra 裝進 venv，import 時就有，不需要 patch。

完整 root-cause 與症狀見 [../skills/patch-dingtalk/SKILL.md](../skills/patch-dingtalk/SKILL.md)。

## 重算 / 新增一個 patch

權威 pristine 來源是 **pinned image 內的檔**（不是 GitHub，除非確認逐字一致）：

```bash
TAG=v2026.9.14
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
python3 patches/test_apply.py                            # 跑煙霧測試
```

build 時的套用見根目錄 [Dockerfile](../Dockerfile)。

## PR 回上游 / 分享

`.patch` 本身即 diff：附在 PR，或用 `git format-patch` 形式送出；給朋友就讓對方在其
Hermes 安裝根 `git apply <file>.patch` 或 `patch -p1 < <file>.patch`。
