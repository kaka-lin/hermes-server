"""Regression test for the control-socket stale-inode patch in the built Hermes image."""
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
import tempfile
from pathlib import Path

from gateway import control_socket
from gateway.control_socket import GatewayControlServer, resolve_client_socket_path

original_bind = GatewayControlServer._bind_posix


async def bind_like_docker_desktop(self, bind_path, pointer_file):
    # A bind mount refuses the in-home path with EADDRINUSE, as it does for an inode a previous
    # container left behind; any other path (the private temp-dir fallback) binds normally.
    if bind_path == self._home / control_socket._SOCKET_FILENAME:
        raise OSError(errno.EADDRINUSE, "Address already in use")
    return await original_bind(self, bind_path, pointer_file)


GatewayControlServer._bind_posix = bind_like_docker_desktop


async def start(home):
    server = GatewayControlServer(home)
    try:
        return await server.start(), server._bind_path
    finally:
        await server.stop()


async def main():
    # Nothing stat-able at the path: a stale inode, so the gateway falls back and clients follow it.
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp).resolve()
        started, bound = await start(home)
        assert started, "stale inode must fall back to the private temp dir"
        assert bound.parent != home, bound
        server = GatewayControlServer(home)
        assert await server.start()
        assert resolve_client_socket_path(home) == server._bind_path
        await server.stop()

    # A visible file at the path stands for a live sibling: keep failing loudly.
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp).resolve()
        (home / control_socket._SOCKET_FILENAME).touch()
        started, _ = await start(home)
        assert not started, "EADDRINUSE with a visible socket must not fall back"


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
        "control socket stale-inode fallback regressed\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    print(f"OK: {IMAGE} falls back past a stale control socket and still refuses a live one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
