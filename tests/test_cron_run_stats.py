"""Regression test: cron_run_stats sums this run's sessions from the ids printed in the run log."""
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        db = tmp_path / "state.db"
        connection = sqlite3.connect(db)
        connection.execute(
            "CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT, parent_session_id TEXT, "
            "api_call_count INTEGER, input_tokens INTEGER, output_tokens INTEGER)"
        )
        connection.executemany(
            "INSERT INTO sessions VALUES (?, 'oneshot', ?, ?, ?, ?)",
            [
                ("local-run", None, 3, 100, 10),
                ("child-of-run", "local-run", 2, 50, 5),  # context compression continuation
                ("local-other", None, 7, 999, 99),  # another job's session
            ],
        )
        connection.commit()
        connection.close()

        log = tmp_path / "run.log"
        # The same id printed twice (two attempts resuming it) must not be counted twice.
        log.write_text("...\nSession:        local-run\n...\nSession: local-run\n", encoding="utf-8")

        def run(run_log: Path) -> str:
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "cron_run_stats.py"),
                 "--state-db", str(db), "--run-log", str(run_log),
                 "--attempts", "第1次", "--elapsed", "61", "--invocations", "1"],
                capture_output=True, text=True,
            )
            assert result.returncode == 0, result.stderr
            return result.stdout

        out = run(log)
        assert "session 段數=2｜API 呼叫=5" in out, out
        assert "輸入=150｜輸出=15" in out, out

        empty = tmp_path / "empty.log"
        empty.write_text("no session line\n", encoding="utf-8")
        assert "session 段數=n/a" in run(empty)

    print("OK: cron_run_stats counts the logged sessions and their compression children")
    return 0


if __name__ == "__main__":
    sys.exit(main())
