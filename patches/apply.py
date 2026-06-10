#!/usr/bin/env python3
"""Apply unified-diff patches to the Hermes install at build time.

Idempotent: a patch already in place (reverse-applies cleanly) is skipped.
A patch whose context no longer matches aborts with a clear message, so an
upstream layout change is caught the moment the base image version is bumped.

Usage:
    python3 apply.py [patches_dir]   # default: this script's directory
    HERMES_ROOT overrides the patch target root (default /opt/hermes).
"""
import os
import subprocess
import sys
from pathlib import Path

HERMES_ROOT = os.environ.get("HERMES_ROOT", "/opt/hermes")


def _patch(patch_file: Path, extra: list[str]) -> subprocess.CompletedProcess:
    """Invoke GNU ``patch`` for ``patch_file`` against ``HERMES_ROOT`` with extra flags."""
    with patch_file.open("rb") as fh:
        return subprocess.run(
            ["patch", "-p1", "-d", HERMES_ROOT, *extra],
            stdin=fh, capture_output=True,
        )


def _already_applied(patch_file: Path) -> bool:
    """Return True if the patch is already present (a reverse dry-run applies cleanly)."""
    return _patch(patch_file, ["-R", "--dry-run", "-f", "-s"]).returncode == 0


def _applies_clean(patch_file: Path) -> bool:
    """Return True if the patch applies cleanly to a pristine tree (forward dry-run)."""
    return _patch(patch_file, ["--dry-run", "-f", "-s"]).returncode == 0


def main() -> int:
    """Apply every ``*.patch`` in the patches dir to ``HERMES_ROOT``; return a shell exit code."""
    patches_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
    patches = sorted(patches_dir.glob("*.patch"))
    if not patches:
        print(f"No .patch files found in {patches_dir}")
        return 1

    print(f"Applying {len(patches)} patch(es) to {HERMES_ROOT}...")
    for pf in patches:
        if _already_applied(pf):
            print(f"  - {pf.name}: already applied, skipping.")
            continue
        if not _applies_clean(pf):
            print(f"ERROR: {pf.name} does not apply cleanly to {HERMES_ROOT} "
                  "— upstream layout changed, patch NOT applied.")
            return 1
        result = _patch(pf, ["-f", "-s"])
        if result.returncode != 0:
            print(f"ERROR: {pf.name} failed to apply:\n{result.stderr.decode()}")
            return 1
        print(f"  - {pf.name}: applied.")

    print("All patches applied successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
