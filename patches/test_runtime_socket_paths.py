"""Runtime socket regression test against a built Hermes image.

Run with the upstream image first to prove the missing behavior:
    python3 patches/test_runtime_socket_paths.py

Then point it at the custom image after ``docker compose build``:
    HERMES_SOCKET_TEST_IMAGE=kakalin/hermes-agent:v2026.9.14 \
        python3 patches/test_runtime_socket_paths.py
"""
import os
import subprocess
import sys


IMAGE = os.environ.get("HERMES_SOCKET_TEST_IMAGE", "nousresearch/hermes-agent:v2026.9.14")
RUNTIME_DIR = "/run/hermes"
PROBE = """
from pathlib import Path
from gateway.control_socket import resolve_server_socket_path
from gateway.shutdown_watchdog import get_loop_tick_socket_path

control_socket, pointer_file = resolve_server_socket_path(Path('/opt/data'))
tick_socket = get_loop_tick_socket_path(Path('/opt/data'), pid=17)

assert control_socket == Path('/run/hermes/gateway.sock'), control_socket
assert pointer_file is None, pointer_file
assert tick_socket == Path('/run/hermes/gateway.loop-tick.17.sock'), tick_socket
"""


def main() -> int:
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "--entrypoint", "/opt/hermes/.venv/bin/python",
            "-e", f"HERMES_RUNTIME_DIR={RUNTIME_DIR}",
            IMAGE, "-c", PROBE,
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"runtime socket paths did not use {RUNTIME_DIR}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    print(f"OK: {IMAGE} uses {RUNTIME_DIR} for runtime sockets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
