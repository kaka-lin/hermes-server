# 背景 cron 啟動的 Chrome 被遮蔽，CDP 卡死直到撞 max_turns

## 症狀

- cron 在背景觸發的瀏覽器自動化任務跑到一半停滯，最後無聲無息結束，沒有完成、也沒有明確錯誤。
- `agent.log` 顯示工具呼叫一路逾時重試，最後撞到 `agent.max_turns: 90` 被切斷。

## 根因

cron 在背景觸發時，Chrome 視窗常被遮蔽、縮到最小，或螢幕已鎖。macOS 的 window occlusion 會凍結隱藏視窗的 renderer 與 JS 計時器，使自動化的 CDP 操作打滑甚至卡死。

agent 端看到的不是明確錯誤，而是一步步逾時、重試，把工具呼叫次數耗到上限 `agent.max_turns: 90`（`config.yaml`），整個 run 因此被切斷。表面像「跑到一半莫名死掉」，實際是瀏覽器被作業系統凍結。

## 修正

在 `start-browsers.sh` 的 `launch_chrome()` 啟動參數加上四個抗節流旗標，讓 Chrome 即使「看不見」也維持正常 renderer 與計時器（commit `9d56325`）：

```text
--disable-background-timer-throttling
--disable-backgrounding-occluded-windows
--disable-renderer-backgrounding
--disable-features=CalculateNativeWinOcclusion
```

## 排查提示

- run 半路死、`agent.log` 充滿 CDP 逾時重試並逼近 `max_turns` 時，先確認 Chrome 是否在背景被遮蔽，不要先當成腳本或網路問題。
