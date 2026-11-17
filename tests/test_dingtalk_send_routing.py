"""Regression test for the DingTalk send-routing patch in the built Hermes image."""
import os
import subprocess
import sys


# Same image name the build produces; the env vars match config/compose.env.
IMAGE = os.environ.get("HERMES_DINGTALK_TEST_IMAGE") or (
    f"{os.environ.get('HERMES_IMAGE', 'kakalin/hermes-agent')}:{os.environ.get('HERMES_VERSION', 'v0.23.1')}"
)
PROBE = r'''
import asyncio
import json
from types import SimpleNamespace

import httpx

from hermes_cli.plugins import discover_plugins
from plugins.platforms.dingtalk import adapter
from tools.send_message_targets import resolve_send_target

discover_plugins()

# A cid group is an explicit target, so send_message never falls back to the home channel.
assert resolve_send_target("dingtalk", "cidAbC123==") == ("cidAbC123==", None, None)


def run_standalone(robot_reply):
    """Run _standalone_send against a fake DingTalk; return (result, requests seen)."""
    seen = []

    def handler(request):
        body = json.loads(request.content or b"{}")
        seen.append((request.url.path, body))
        if request.url.path == "/v1.0/oauth2/accessToken":
            return httpx.Response(200, json={"accessToken": "token"})
        if request.url.path == "/v1.0/robot/groupMessages/send":
            return httpx.Response(200, json=robot_reply)
        return httpx.Response(200, json={"errcode": 0})  # the static webhook

    real_client = httpx.AsyncClient
    adapter_httpx = httpx.AsyncClient
    httpx.AsyncClient = lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw)
    try:
        pconfig = SimpleNamespace(extra={"client_id": "app", "client_secret": "secret",
                                         "webhook_url": "https://oapi.dingtalk.com/robot/send?access_token=x"})
        result = asyncio.run(adapter._standalone_send(pconfig, "cidAbC123==", "**report**"))
    finally:
        httpx.AsyncClient = adapter_httpx
    return result, seen


# The robot API confirms delivery: no webhook call.
result, seen = run_standalone({"processQueryKey": "k"})
assert result.get("method") == "official_robot_api", result
robot_body = dict(seen)["/v1.0/robot/groupMessages/send"]
assert robot_body["openConversationId"] == "cidAbC123==", robot_body
assert robot_body["msgKey"] == "sampleMarkdown", robot_body
assert not any(path == "/robot/send" for path, _ in seen), seen

# The robot API answers without a processQueryKey: fall back to the webhook, as markdown.
result, seen = run_standalone({"code": "invalidParameter"})
assert result.get("method") == "custom_webhook", result
webhook_body = dict(seen)["/robot/send"]
assert webhook_body["msgtype"] == "markdown", webhook_body
'''


def main() -> int:
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "--entrypoint", "/opt/hermes/.venv/bin/python",
            "-w", "/opt/hermes",
            IMAGE, "-c", PROBE,
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "DingTalk send routing regressed\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    print(f"OK: {IMAGE} routes DingTalk cid targets through the robot API with webhook fallback")
    return 0


if __name__ == "__main__":
    sys.exit(main())
