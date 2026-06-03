"""CDP TCP proxy: forward container loopback ports to the Docker Desktop host.

Hermes Gateway runs inside Docker, but the Chrome it controls runs on the Mac
host. This forwarder listens on ``127.0.0.1:<port>`` inside the container and
relays raw bytes to ``192.168.65.254:<port>`` (Docker Desktop's host address).
Connecting through ``127.0.0.1`` makes Chrome's DNS-rebinding check pass,
because the HTTP ``Host`` header becomes ``127.0.0.1`` — the proxy never parses
or rewrites payloads.

Ports come from ``scripts/host/browsers.conf`` inside the data dir (relative to
this script). ``hermes-stack.sh new`` copies it there from the repo-root
``browsers.conf`` that start-browsers.sh reads, so the host launcher and the
in-container forwarder share one port list. Optional CLI arguments override the
config file for ad-hoc one-off forwards.

Usage:
    python3 cdp_proxy.py                 # forward every port in browsers.conf
    python3 cdp_proxy.py 9223 9224       # forward explicit ports (ignore config)
"""

import os
import socket
import sys
import threading
import time
from pathlib import Path

# Docker Desktop reserves this address for reaching the Mac host from inside a
# container (equivalent to host.docker.internal).
HOST_IP = "192.168.65.254"

# Same env var start-browsers.sh honors, so both sides can be repointed together.
DEFAULT_CONFIG = Path(__file__).resolve().parent / "host" / "browsers.conf"

BUFFER_SIZE = 4096


def forward(src: socket.socket, dst: socket.socket) -> None:
    """Pump bytes from ``src`` to ``dst`` until either side closes."""
    try:
        while True:
            data = src.recv(BUFFER_SIZE)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        # Either socket may drop mid-stream; tearing both down is the only
        # sensible response for a dumb byte forwarder.
        pass
    finally:
        src.close()
        dst.close()


def start_proxy(local_port: int, target_ip: str, target_port: int) -> None:
    """Listen on the container loopback and forward each connection to the host.

    Runs forever; intended to be launched in a daemon thread per port.

    Args:
        local_port: Port to bind on the container's 127.0.0.1.
        target_ip: Host address to forward to (Docker Desktop magic IP).
        target_port: Port on the host to connect to.
    """
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(("127.0.0.1", local_port))
        server.listen(5)
    except OSError as exc:
        print(f"Failed to bind {local_port}: {exc}", file=sys.stderr)
        return

    print(f"Proxy listening on 127.0.0.1:{local_port} -> {target_ip}:{target_port}")

    while True:
        client: socket.socket | None = None
        try:
            client, _ = server.accept()
            remote = socket.create_connection((target_ip, target_port))
            threading.Thread(target=forward, args=(client, remote), daemon=True).start()
            threading.Thread(target=forward, args=(remote, client), daemon=True).start()
        except OSError as exc:
            print(f"Error on {local_port}: {exc}", file=sys.stderr)
            if client is not None:
                client.close()


def load_ports_from_config(path: Path) -> list[int]:
    """Read CDP ports from a browsers.conf file.

    The file uses ``port:profile_name`` lines (see browsers.conf);
    only the port is needed here. Comment lines (starting with ``#``) and blank
    lines are ignored.

    Args:
        path: Path to the browsers.conf file.

    Returns:
        The ports listed in the file, in order, with duplicates removed.

    Raises:
        FileNotFoundError: If the config file does not exist.
    """
    ports: list[int] = []
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            port_field = line.split(":", 1)[0].strip()
            try:
                port = int(port_field)
            except ValueError:
                print(
                    f"Skipping malformed line in {path}: {raw_line!r}", file=sys.stderr
                )
                continue
            if port not in ports:
                ports.append(port)
    return ports


def resolve_ports(argv: list[str]) -> list[int]:
    """Resolve the port list: CLI args take precedence over the config file.

    Args:
        argv: Command-line arguments after the script name.

    Returns:
        The ports to forward (empty if the config file is missing and no args
        were given).
    """
    if argv:
        return [int(arg) for arg in argv]

    config_path = Path(os.environ.get("BROWSERS_CONFIG", DEFAULT_CONFIG))
    try:
        return load_ports_from_config(config_path)
    except FileNotFoundError:
        print(f"Config not found: {config_path}", file=sys.stderr)
        print(
            "Hint: pass ports explicitly (e.g. cdp_proxy.py 9223 9224) "
            "or set BROWSERS_CONFIG to a valid browsers.conf.",
            file=sys.stderr,
        )
        return []


def main() -> int:
    """Start one forwarding thread per resolved port, then idle forever."""
    ports = resolve_ports(sys.argv[1:])
    if not ports:
        print("No ports to forward; nothing to do.", file=sys.stderr)
        return 1

    for port in ports:
        threading.Thread(
            target=start_proxy, args=(port, HOST_IP, port), daemon=True
        ).start()

    while True:
        time.sleep(60)


if __name__ == "__main__":
    sys.exit(main())
