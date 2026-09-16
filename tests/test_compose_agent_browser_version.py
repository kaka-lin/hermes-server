"""Regression test for the configurable agent-browser build version."""
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        env_file = Path(tmp) / "compose.env"
        env_file.write_text(
            "HERMES_VERSION=v2026.9.14\n"
            "AGENT_BROWSER_VERSION=0.26.0\n"
        )
        result = subprocess.run(
            ["docker", "compose", "--env-file", str(env_file), "config"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    assert result.returncode == 0, result.stderr
    assert "AGENT_BROWSER_VERSION: 0.26.0" in result.stdout, result.stdout
    print("OK: Compose forwards AGENT_BROWSER_VERSION to the Hermes build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
