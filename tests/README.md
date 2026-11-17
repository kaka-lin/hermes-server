# 測試

只測這個 repo 自己寫的邏輯：

```bash
python3 tests/test_patch_apply.py                 # patches/apply.py 套用 unified diff
python3 tests/test_cron_run_stats.py              # scripts/cron_run_stats.py 的 session 統計
python3 tests/test_dingtalk_send_routing.py       # dingtalk-send-routing.patch 在 image 裡有沒有生效
python3 tests/test_control_socket_stale_inode.py  # control-socket-stale-inode.patch 在 image 裡有沒有生效
```

後兩支需要已建好的 image，預設 `kakalin/hermes-agent:v0.23.1`，可用 `HERMES_DINGTALK_TEST_IMAGE`、`HERMES_SOCKET_TEST_IMAGE` 換。換成上游 image 會失敗，用來確認 patch 沒漏套。

`hermes-run.sh`、`hermes-build.sh` 這類包 docker 的腳本不寫測試，改完實際跑一次確認。
