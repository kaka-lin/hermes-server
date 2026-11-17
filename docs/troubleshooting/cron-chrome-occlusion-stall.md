# cron 的瀏覽器任務跑到一半停住

## 症狀

cron 在背景觸發的瀏覽器任務半路停住，沒有明確錯誤；`agent.log` 裡工具呼叫一路逾時、重試，直到撞上 `agent.max_turns`。

## 原因

cron 觸發時，host 上的 Chrome 視窗常被遮住、縮到最小，或螢幕已鎖。macOS 會凍結看不見的視窗的 renderer 與 JS 計時器，經 CDP 下的操作因此逾時。

## 解法

用 [`start-browsers.sh`](../../start-browsers.sh) 開 Chrome，它已帶這四個旗標，讓 Chrome 看不見時也照常執行：

```text
--disable-background-timer-throttling
--disable-backgrounding-occluded-windows
--disable-renderer-backgrounding
--disable-features=CalculateNativeWinOcclusion
```

用別的方式開 Chrome 時也要加。已經開著的 Chrome 要 `./start-browsers.sh restart` 才會套用。

host Chrome 與 CDP 的整體設定見[瀏覽器](../browser.md)。

## 排查提示

run 半路停住、`agent.log` 滿是 CDP 逾時重試時，先確認 Chrome 是不是在背景被遮住，再懷疑腳本或網路。
