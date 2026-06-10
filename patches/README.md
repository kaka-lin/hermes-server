# patches/

對上游 `nousresearch/hermes-agent` image 的修改，以 unified diff 維護，build 時由
[apply.py](apply.py) 套用到容器內的 `/opt/hermes`。

## 檔案

- `*.patch` — 每個修改一個 diff，單一真相來源，可直接 PR / 分享。
- `apply.py` — 泛用 applier：讀 `*.patch`，冪等套用，context 不符則明確報錯。
- `test_apply.py` — apply.py 的 stdlib 煙霧測試（`python3 patches/test_apply.py`）。
- `.src/` — 重算 diff 用的本地工作區（gitignore，用時再生）。

## 現有 patch

- `dingtalk-send-routing.patch` — `tools/send_message_tool.py`：explicit
  `dingtalk:cidXXXX==` 目標經官方 robot API 送到該群。
- `dingtalk-stream-handler.patch` — `gateway/platforms/dingtalk.py`：lazy SDK 安裝後
  重建 `_IncomingHandler`，讓 bot 會回訊。

完整 root-cause 與症狀見 [../skills/patch-dingtalk/SKILL.md](../skills/patch-dingtalk/SKILL.md)。

## 重算 / 新增一個 patch

權威 pristine 來源是 **pinned image 內的檔**（不是 GitHub，除非確認逐字一致）：

```bash
TAG=v2026.6.5
P=gateway/platforms/dingtalk.py            # 目標相對 /opt/hermes 的路徑
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
