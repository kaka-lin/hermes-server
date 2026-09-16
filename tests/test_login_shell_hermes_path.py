"""Regression test for Hermes CLI availability from a login terminal shell."""
import os
import subprocess
import sys


IMAGE = os.environ.get("HERMES_LOGIN_SHELL_TEST_IMAGE", "kakalin/hermes-agent:v2026.9.14")


def main() -> int:
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "--entrypoint", "/bin/bash",
            IMAGE, "-lc", "command -v hermes && hermes --version",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "the terminal login shell cannot find the Hermes CLI\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert result.stdout.splitlines()[0].endswith("/hermes"), result.stdout
    assert "Hermes Agent v" in result.stdout, result.stdout
    print(f"OK: {IMAGE} exposes Hermes to login-shell terminal commands")
    return 0


if __name__ == "__main__":
    sys.exit(main())
