# Patch 管理與 Base Image Pinning 設計

設計把「對上游 Hermes image 的修改」整理成一套乾淨、可讀、可 PR、可分享的機制，並用
base image pinning 讓日常 build 穩定可重現。

> [!NOTE]
> 已實作完成。本節描述的 `scripts/patch_dingtalk_*.py` 字串替換腳本已由
> `patches/*.patch` + `patches/apply.py` 取代（見 [patches/README.md](../../../patches/README.md)）；
> 下列腳本路徑保留為當時現況的歷史紀錄，檔案本身已移除。

## 背景與問題

本 repo（`hermes-server`）的定位是 NousResearch `nousresearch/hermes-agent`
官方 image 的可部署設定，本身不含 Hermes 原始碼。為了修兩個上游缺陷，目前在
build 時對 image 內的上游檔做字串替換：

- `scripts/patch_dingtalk_send.py` — 改
  `tools/send_message_tool.py`（出站路由 + 官方 robot API）。
- `scripts/patch_dingtalk_handler.py` — 改
  `gateway/platforms/dingtalk.py`（lazy-install 後重建 Stream handler）。

現況有四個問題：

- **patch 不好讀、不能直接 PR** — anchored 整段字串替換冗長，且不是上游可接受的 PR 形式。
- **開發暫存檔散落** — 根目錄的 `dingtalk_new.py` / `dingtalk_ori.py` /
  `send_message_tool_new.py` 等以 untracked 形式堆在 repo root。
- **build-time patch 與 runtime 腳本混放** — `scripts/` 同時放 `cdp_proxy.py`（runtime）
  與 patch 腳本（build-time），職責不分。
- **base image 未 pin** — `Dockerfile` 用 `nousresearch/hermes-agent:latest`，而
  `latest`/`main` 會頻繁飄動，導致 build 不可重現、patch 可能在無 code 變更下突然套不上。

## 目標 / 非目標

目標：

- patch 以可讀、可 PR、可分享的形式維護，且**單一真相來源**、無重複同步。
- build-time 修補與 runtime 腳本目錄分家。
- base image 預設 pin 在穩定釋出 tag，並保留一鍵切到 `latest` 測上游的能力。
- 開發暫存檔不再以 untracked 散在 repo root。

非目標：

- 不支援非 Docker（node/pip 直裝）使用者作為一等公民；repo 定位仍是 Docker 部署（方向 A）。
  patch 以 `.patch` 形式存在，本身即可被非 Docker 使用者手動 `git apply`，屬附帶效益而非維護承諾。
- 不維護兩套 Dockerfile / 兩套部署。

## 設計總覽

兩塊互相加分的設計：

1. **`patches/` 目錄 + unified diff 真相來源 + 一支泛用 applier**。
2. **Base image pinning（`ARG HERMES_VERSION`，預設 pin 穩定 tag）**。

pin 之後，上游檔對該 pin 是凍結的，patch 每次 build 都確定套得上；飄動只在主動
bump pin 時發生，而那正是該重新驗證 patch 的時機，失敗會大聲報錯當作升級檢查點。

## patches/ 目錄結構

```text
patches/
  README.md                       # 作者 / 重算 / 套用 / PR 流程
  dingtalk-send-routing.patch     # 真相來源,可直接 PR / 分享
  dingtalk-stream-handler.patch
  apply.py                        # 泛用 applier(冪等 + 找不到明確報錯)
  .src/                           # gitignore:重算 diff 用的本地工作區(ori/new)
```

- 每個 `.patch` 用 `git diff` 產出，rooted 在 Hermes 安裝根 `/opt/hermes`，
  路徑形如 `a/tools/send_message_tool.py`、`a/gateway/platforms/dingtalk.py`。
- 檔頭以 `git diff` 原生 header 為主；額外的「為什麼」放在 [patches/README.md](../../../patches/README.md)
  與對應 SKILL，避免在 patch body 重複長篇 root-cause。

## Applier 設計

`patches/apply.py`：純 stdlib，shell 出去呼叫系統 `patch`（由 Dockerfile 安裝）。

- 依固定順序（檔名排序或 manifest）逐一處理 `patches/*.patch`。
- 每個 patch 的判定（以 `/opt/hermes` 為套用根）：
    1. `patch -p1 -R --dry-run -f -d /opt/hermes < p` 成功 → 已套用，skip（冪等）。
    2. 否則 `patch -p1 --dry-run -f -d /opt/hermes < p` 成功 → 正式套用。
    3. 兩者皆否 → 印明確錯誤（「context not found — 上游 layout 變了,patch 未套用」）並非零退出。
- 任一 patch 失敗即中止 build，不靜默略過。

選定機制 A（裝系統 `patch`、shell 呼叫）而非純 Python lib：最少依賴與魔法，`patch`
體積小（apt 一行），且 base 已 pin 後甚至不需 fuzz。`git apply` 為等價替代方案，
取決於 image 是否已含 `git`。

## Base image pinning

`Dockerfile` 開頭：

```dockerfile
ARG HERMES_VERSION=v2026.6.5
FROM nousresearch/hermes-agent:${HERMES_VERSION}
```

- 預設 build = pin 在穩定釋出 tag（正式部署）。
- 測上游最新 = `docker build --build-arg HERMES_VERSION=latest`（工程 / canary，
  專門驗證 patch 是否仍套得上）。
- 正式部署若要完全可重現,可在 pin tag 後再加 `@sha256:<digest>`。
- 版本升級走「改 `ARG` 預設值 → 重跑 applier 驗證 → commit」的明確流程,
  未來可接 Renovate/Dependabot 自動開 bump PR。

## Dockerfile 變更

把現有「兩組 COPY + RUN patch_*.py」收斂為：

```dockerfile
COPY patches/ /tmp/patches/
RUN apt-get update && apt-get install -y --no-install-recommends patch \
    && python3 /tmp/patches/apply.py \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
```

每個 patch 的「修什麼 + 版本 gate」一行註解保留在 Dockerfile；完整 root-cause 在 SKILL。

## 暫存檔處理

- 刪除 repo root 的 `dingtalk_new.py`、`dingtalk_ori.py`、`dingtalk_ori copy.py`、
  `send_message_tool_new.py`、`send_message_tool_ori.py`。
- 重算 diff 時改用 `patches/.src/`（gitignore），素材從 pinned base image 拉取，
  流程記於 [patches/README.md](../../../patches/README.md)。
- `.gitignore` 增加 `patches/.src/`。

## 作者 / 重算 / PR / 分享 工作流程（記於 patches/README.md）

- **權威 pristine 來源**：build 時真正被套 patch 的是 image 內 `/opt/hermes/...` 那份檔,
  故 pristine 一律從 pinned image 撈
  (`docker run --rm nousresearch/hermes-agent:v2026.6.5 cat /opt/hermes/<path>`)。
  GitHub 源僅在確認與 image 逐字一致時才採用。
- **重算 diff**：取 pristine 到 `patches/.src/<name>.orig`,複製為 `.new` 後修改,
  `git diff --no-index .src/x.orig .src/x.new` 產出 `.patch`（修正路徑前綴）。`.new`
  必須基於**同一 pinned 版本**改出,否則 diff 會混入無關的上游版本差異。
- **PR 回上游**：`.patch` 即 diff,可直接附在 PR 或用 `git format-patch` 形式送出。
- **分享朋友**：給 `.patch`,對方在其 Hermes 安裝根 `git apply` 或 `patch -p1`。

## SKILL.md 調整

[skills/patch-dingtalk/SKILL.md](../../../skills/patch-dingtalk/SKILL.md) 更新：

- Steps 改為「跑 `patches/apply.py`」而非逐支腳本。
- 兩節症狀說明保留;腳本檔名引用改為對應 `.patch`。
- 版本 gate 文字對齊 pinned tag（`v2026.6.5`）。

## 遷移步驟

1. 建 `patches/`,先用現有 `_ori`/`_new` 暫存檔產出兩個 `.patch`（快,無需重拉 image）。
2. 寫 `patches/apply.py` 與 `patches/README.md`。
3. 改 `Dockerfile`：加 `ARG HERMES_VERSION`、pin tag、改用 applier。
4. **驗證關卡**：對乾淨的 pinned image build,確認 applier 兩個 patch 皆乾淨套用、
   且結果與預期 `_new` 一致(抓出「pristine 來源非權威」或「`_new` 基底版本不符」兩個
   正確性風險)。未通過前**不得刪暫存檔**——`_new` 是修改目前唯一的全量留存。
5. 驗證通過後,才刪除 root 暫存檔、更新 `.gitignore`、移除 `scripts/patch_dingtalk_*.py`。
6. 更新 `skills/patch-dingtalk/SKILL.md`。

## 測試 / 驗證

- **乾淨套用**：對 pinned base build,applier 兩個 patch 皆 apply 成功。
- **冪等**：同一 build 重跑 applier → 兩個 patch 皆判定 already-applied、skip、退出 0。
- **飄動偵測**：`--build-arg HERMES_VERSION=latest` build,觀察 applier 是否乾淨套用或
  明確報「context not found」（後者代表上游變動，需重算 patch）。
- **行為驗證**：build 後容器內確認 `tools/send_message_tool.py` 含
  `"method": "official_robot_api"`、`gateway/platforms/dingtalk.py` 含
  `dingtalk_stream.ChatbotHandler.__init__(self)`。

## 取捨記錄

- **`.patch` vs anchored script**：選 `.patch` 為單一真相來源,因可讀、可 PR、可分享;
  applier 保住原腳本的冪等與明確報錯。anchored 整段替換對上游內容變動「一碰即 fail」,
  屬保守但難讀且不可 PR。
- **pin tag vs digest**：預設 pin tag(好讀);正式部署可加 digest 取得完全可重現。
- **單一 ARG vs 雙 Dockerfile**：選單一 `ARG HERMES_VERSION` 旋鈕,以最小維護成本達到
  「一穩一追新」雙軌效果。
