# 測試

這裡放 repo 的回歸測試；`patches/` 僅保留 build-time patch 與其 applier。

```bash
python3 tests/test_patch_apply.py
python3 tests/test_runtime_socket_paths.py
python3 tests/test_stream_consumer_interim_diagnostic.py
python3 tests/test_login_shell_hermes_path.py
python3 tests/test_build_script_compose_version.py
python3 tests/test_compose_agent_browser_version.py
ruby tests/test_openai_api_routes.rb
```

`test_runtime_socket_paths.py` 預設驗證已建置的 custom image。要重現上游 image
缺少 runtime socket 修正的行為，可指定
`HERMES_SOCKET_TEST_IMAGE=nousresearch/hermes-agent:v2026.9.14`；該次執行預期失敗。
