# cron 顯示 OK 卻沒有結果

## 症狀

- `hermes cron list` 顯示某次觸發成功，但訊息平台沒收到任何輸出。
- 把所有 cron job 暫停後，`ps aux` 仍看得到任務的進程在跑。

## 原因

腳本用 `nohup` 把工作丟到背景、先睡一段隨機時間再執行：

```bash
nohup bash -c 'sleep $((RANDOM % 7200)); …' >/dev/null 2>&1 &
```

觸發腳本立刻結束，gateway 把這次 job 記為完成。睡著的進程已脫離 gateway 管理：暫停 cron 停不了它、容器重啟它就消失、結果不會送出、失敗也沒人通知。

改成同步睡也不行：agent 用 terminal 跑腳本受 `terminal.timeout`（預設 180 秒）限制，睡太久會被砍。

## 解法：讓 gateway 排一個隨機時間的一次性 job

每個任務拆成兩支腳本，放在 data dir 的 `scripts/`：

1. 觸發端 `schedule_*.sh`：算隨機分鐘數，向 gateway 註冊一次性 job 後立刻結束。

    ```bash
    DELAY=$(( RANDOM % 30 + 1 ))
    hermes cron create "${DELAY}m" \
      --no-agent --script run_xxx.sh \
      --failure-deliver "<platform>:<chat_id>" \
      --name "xxx-oneshot-$DELAY" \
      --repeat 1 >/dev/null
    ```

2. 執行端 `run_*.sh`：同步跑真正的任務，不要 detach。`--no-agent` 模式下它的 stdout 會原樣送到 `--deliver` 的目標。

注意：

- 從 CLI 建的 job 預設不送到任何地方，要用 `--deliver` 或 `--failure-deliver` 指定。
- 等待期間容器重啟，只要在到點前回來就會照常執行；錯過到點時間的一次性 job 預設不補跑，見 `hermes cron create --help` 的 `--catch-up`。
- `--no-agent` 腳本受 `cron.script_timeout_seconds` 限制（預設 3600 秒，[`config.example.yaml`](../../config.example.yaml) 設 7200），瀏覽器任務跑很久時要確認夠長。

## 排查提示

遇到「cron 顯示 OK 但沒結果」，先查腳本有沒有把工作丟到背景，再懷疑網路、OOM 這類沒有 log 佐證的原因。`hermes cron runs` 可以看每次執行的紀錄。
