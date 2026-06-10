"""apply.py 的煙霧測試:純 stdlib,用臨時目錄當 HERMES_ROOT。

執行:python3 patches/test_apply.py(需要系統 patch binary)
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

APPLY = Path(__file__).resolve().parent / "apply.py"

# 一份最小的 unified diff:把 foo/bar.py 的 "old" 改成 "new",a/ b/ 前綴對應 -p1。
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

        # 1. 乾淨套用
        r = _run(root, patches)
        assert r.returncode == 0, f"clean apply failed: {r.stderr}"
        assert target.read_text() == "new\n", "content not patched"
        assert "applied" in r.stdout, r.stdout

        # 2. 冪等:再跑一次 → 略過、內容不變、退出 0
        r = _run(root, patches)
        assert r.returncode == 0, f"idempotent run failed: {r.stderr}"
        assert "already applied" in r.stdout, r.stdout
        assert target.read_text() == "new\n", "content changed on re-run"

        # 3. context 不符 → 非零退出、明確訊息
        target.write_text("something completely different\n")
        r = _run(root, patches)
        assert r.returncode != 0, "should fail on mismatched context"
        assert "does not apply cleanly" in r.stdout, r.stdout

        print("OK: all apply.py smoke tests passed")
        return 0


if __name__ == "__main__":
    sys.exit(main())
