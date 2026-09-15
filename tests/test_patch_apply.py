"""Smoke test for the build-time unified-diff applier."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path


APPLY = Path(__file__).resolve().parents[1] / "patches" / "apply.py"

PATCH = """\
--- a/foo/bar.py
+++ b/foo/bar.py
@@ -1,1 +1,1 @@
-old
+new
"""


def _run(hermes_root: Path, patches_dir: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "HERMES_ROOT": str(hermes_root)}
    return subprocess.run(
        [sys.executable, str(APPLY), str(patches_dir)],
        env=env, capture_output=True, text=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "hermes"
        (root / "foo").mkdir(parents=True)
        target = root / "foo" / "bar.py"
        target.write_text("old\n")

        patches = Path(tmp) / "patches"
        patches.mkdir()
        (patches / "demo.patch").write_text(PATCH)

        result = _run(root, patches)
        assert result.returncode == 0, f"clean apply failed: {result.stderr}"
        assert target.read_text() == "new\n", "content not patched"
        assert "applied" in result.stdout, result.stdout

        result = _run(root, patches)
        assert result.returncode == 0, f"idempotent run failed: {result.stderr}"
        assert "already applied" in result.stdout, result.stdout
        assert target.read_text() == "new\n", "content changed on re-run"

        target.write_text("something completely different\n")
        result = _run(root, patches)
        assert result.returncode != 0, "should fail on mismatched context"
        assert "does not apply cleanly" in result.stdout, result.stdout

    print("OK: all apply.py smoke tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
