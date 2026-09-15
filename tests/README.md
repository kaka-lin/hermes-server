# 測試

這裡放 repo 的回歸測試；`patches/` 僅保留 build-time patch 與其 applier。

```bash
python3 tests/test_patch_apply.py
python3 tests/test_runtime_socket_paths.py
ruby tests/test_openai_api_routes.rb
```

`test_runtime_socket_paths.py` 預設驗證已建置的 custom image。要重現上游 image
缺少 runtime socket 修正的行為，可指定
`HERMES_SOCKET_TEST_IMAGE=nousresearch/hermes-agent:v2026.9.14`；該次執行預期失敗。
