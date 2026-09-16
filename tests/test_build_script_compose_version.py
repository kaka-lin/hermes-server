"""Regression test for Hermes version resolved from the Compose environment."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        project = tmp_path / "project"
        project.mkdir()
        shutil.copy2(ROOT / "hermes-build.sh", project / "hermes-build.sh")
        shutil.copy2(ROOT / "docker-compose.yml", project / "docker-compose.yml")
        versions_file = project / "versions.env"
        versions_file.write_text("HERMES_VERSION=v2026.8.31\n")
        captured_version = tmp_path / "build-version"
        captured_args = tmp_path / "docker-args"
        call_count = tmp_path / "docker-call-count"
        fake_docker = tmp_path / "docker"
        fake_docker.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$*\" >> \"$CAPTURED_ARGS\"\n"
            "if [ ! -e \"$CALL_COUNT\" ]; then\n"
            "  : > \"$CALL_COUNT\"\n"
            "  echo 'HERMES_VERSION=v2026.8.31'\n"
            "else\n"
            "  printf '%s' \"$HERMES_VERSION\" > \"$CAPTURED_VERSION\"\n"
            "fi\n"
        )
        fake_docker.chmod(0o755)
        env = {
            **os.environ,
            "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
            "CAPTURED_VERSION": str(captured_version),
            "CAPTURED_ARGS": str(captured_args),
            "CALL_COUNT": str(call_count),
        }
        result = subprocess.run(
            ["bash", "./hermes-build.sh"],
            cwd=project,
            env=env,
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, result.stderr
        assert captured_version.is_file(), captured_args.read_text()
        assert captured_version.read_text() == "v2026.8.31", captured_args.read_text()
        assert captured_args.read_text().splitlines()[0].startswith(
            f"compose --env-file {versions_file.resolve()} "
        )

    print("OK: hermes-build.sh uses the HERMES_VERSION resolved by Compose")
    return 0


if __name__ == "__main__":
    sys.exit(main())
