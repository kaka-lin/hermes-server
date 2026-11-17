"""Regression test for the watchdog tick-socket fallback patch in the built Hermes image."""
import os
import subprocess
import sys


# Same image name the build produces; the env vars match config/compose.env.
IMAGE = os.environ.get("HERMES_SOCKET_TEST_IMAGE") or (
    f"{os.environ.get('HERMES_IMAGE', 'kakalin/hermes-agent')}:{os.environ.get('HERMES_VERSION', 'v0.23.1')}"
)
PROBE = r'''
import asyncio
import errno
import json
import os
import tempfile
from pathlib import Path

from gateway import shutdown_watchdog


async def refuse_unix(*args, **kwargs):
    # Docker Desktop 4.41 bind mounts refuse AF_UNIX nodes with EPERM.
    raise PermissionError(errno.EPERM, os.strerror(errno.EPERM))


asyncio.start_unix_server = refuse_unix


async def main():
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp).resolve()
        await shutdown_watchdog.loop_heartbeat_forever(home=home, should_continue=lambda: False)
        payload = json.loads(shutdown_watchdog.get_loop_heartbeat_path(home).read_text())
        assert payload.get("loop_tick_socket") is True, payload
        assert int(payload.get("loop_tick_tcp_port") or 0) > 0, payload


asyncio.run(main())
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
        "watchdog tick socket fallback regressed\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    print(f"OK: {IMAGE} serves the loop tick witness on loopback TCP when AF_UNIX is refused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
