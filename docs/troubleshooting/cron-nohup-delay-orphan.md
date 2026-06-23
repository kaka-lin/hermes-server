# cron 隨機延遲用 nohup 變孤兒

> [!IMPORTANT]
> 查這類「cron 顯示 OK 但沒結果」的問題時，先別接受「系統升級／cgroup／網路瞬斷／OOM」這種沒有日誌佐證的說法，本案這些臆測全部被現場證據推翻。

## 症狀

- cron 清單顯示某次觸發 `last status = OK`，但實際上沒有任何輸出送達設定的訊息平台。
- 把所有 cron job 都 **暫停（paused）後，背景卻仍有任務進程在跑**，暫停沒讓它停下來。

## 背景：這些排程怎麼跑

排程是 **Hermes gateway 內建的 cron**（非 host crontab），到點的 job 在隔離 session 執行，指向 `~/.hermes/scripts/` 下的腳本。舊版常用「金蟬脫殼」把工作丟到背景：

```bash
nohup bash -c 'sleep $((RANDOM % 7200)); …' >/dev/null 2>&1 &
```

## 根因

`nohup … sleep … &` 一旦把工作丟進背景，觸發腳本就秒退、gateway 視該 job 為「已完成」。那個睡 0–2 小時的進程不在 gateway 的 cron 記錄裡：

- **暫停 cron 殺不掉它**：觸發後即使把所有 cron 暫停，`ps aux` 仍會抓到背景有進程在跑，因為孤兒早已脫離 gateway 監管。
- **container 重啟即消失**：醒來執行這件事沒有任何持久化保證，能不能活到醒來純靠運氣。

也不能只把 `&` 拿掉改成同步睡：agent 用 terminal 跑腳本受 `terminal.timeout`（預設 180 秒）管控，同步睡 2 小時會在 180 秒被砍，這正是當初被迫 detach、進而產生孤兒的死結。

## 修正：把「隨機」從 sleep 改成「排程偏移量」

gateway 會持久化、監管「排程的 job」，但不會監管「一個在睡覺的孤兒進程」。所以別讓進程去睡，讓 gateway 在隨機的未來時間點幫你開一個 job。每支拆成兩段：

1. 觸發端 `schedule_*.sh`：秒退，算一個隨機分鐘數，向 gateway 註冊一個一次性子 job：

    ```bash
    DELAY=$(( RANDOM % 120 + 1 ))
    /opt/hermes/.venv/bin/python /opt/hermes/hermes cron create "${DELAY}m" \
      --no-agent --script run_*.sh --name "...-oneshot-$DELAY" --repeat 1 >/dev/null
    ```

2. 執行端 `run_*.sh`：被子 job 在隨機時間點呼叫，**同步**跑真正任務，不 detach。

這樣隨機時間就變成 `"${DELAY}m"` 這個排程偏移量，由 gateway 持久化在 `~/.hermes/cron/`，即使 container 在等待期間重啟也照樣會 fire。一次性子 job 預設 `--repeat 1`，跑完自動結束、不殘留。

> no-agent 子 job 受 `cron.script_timeout_seconds` 管控（預設僅 120 秒），而瀏覽器任務實測可達 7～11 分鐘，須在 `~/.hermes/config.yaml` 放寬（例如 `1800`）。注意 agent 無法自行修改 `config.yaml`（security-sensitive），需人手動改。
