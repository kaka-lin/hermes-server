"""Regression test for interim-only stream consumers in the built Hermes image."""
import os
import subprocess
import sys


IMAGE = os.environ.get("HERMES_STREAM_TEST_IMAGE", "kakalin/hermes-agent:v2026.9.14")
PROBE = r'''
import asyncio
import logging
from types import SimpleNamespace

from gateway.run_turn import GatewayTurnMixin


class InterimOnlyConsumer:
    # This consumer is created solely for interim assistant messages. It never
    # receives text deltas and has not delivered any final-response content.
    stream_deltas_enabled = False
    final_content_delivered = False
    final_response_sent = False


class Capture(logging.Handler):
    def __init__(self):
        super().__init__()
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


async def main():
    capture = Capture()
    # run_turn keeps log-record parity with gateway.run, so capture the logger
    # that emits the production warning rather than the module import path.
    logger = logging.getLogger("gateway.run")
    logger.addHandler(capture)
    try:
        turn_ctx = SimpleNamespace(
            stream_consumer_holder=[InterimOnlyConsumer()],
            source=object(),
            session_key="interim-only-regression",
        )
        response = {"final_response": "single normal reply"}
        runner = object.__new__(GatewayTurnMixin)
        await runner._run_agent_mark_streamed_delivery(response, turn_ctx)
    finally:
        logger.removeHandler(capture)

    warnings = [m for m in capture.messages if "possible duplicate send" in m]
    assert warnings == [], warnings
    assert response.get("already_sent") is None, response


asyncio.run(main())
'''


def main() -> int:
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "--entrypoint", "/opt/hermes/.venv/bin/python",
            IMAGE, "-c", PROBE,
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "an interim-only stream consumer emitted a false duplicate-send warning\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    print(f"OK: {IMAGE} suppresses the interim-only duplicate-send diagnostic")
    return 0


if __name__ == "__main__":
    sys.exit(main())
