#!/usr/bin/env python3
"""產生簡潔的單次 Hermes cron 遙測通知。"""

from __future__ import annotations

import argparse
import re
import sqlite3
from pathlib import Path


ITERATION_RE = re.compile(
    r"(?:Iteration budget (?:reached|exhausted)|max_iterations_reached)"
    r"\s*\((?P<used>\d+)/(?P<limit>\d+)\)",
    re.IGNORECASE,
)
COMPRESSION_RE = re.compile(r"compacting context", re.IGNORECASE)
COMPRESSION_DONE_RE = re.compile(
    r"agent\.conversation_compression: context compression done:", re.IGNORECASE
)
AUX_TIMEOUT_RE = re.compile(
    r"Compression summary failed: .* exceeded \d+(?:\.\d+)?s total timeout", re.IGNORECASE
)
GATEWAY_IDLE_RE = re.compile(
    r"Job '.+?' idle for \d+s \(inactivity limit \d+s\)", re.IGNORECASE
)
SCRIPT_TIMEOUT_RE = re.compile(r"^Script timed out after \d+(?:\.\d+)?s:", re.IGNORECASE | re.MULTILINE)


def hms(seconds: int) -> str:
    return f"{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def usage_summary(state_db: Path, run_tag: str) -> dict[str, int] | None:
    try:
        connection = sqlite3.connect(f"file:{state_db}?mode=ro", uri=True)
        row = connection.execute(
            """
            SELECT COUNT(*), COALESCE(SUM(api_call_count), 0),
                   COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0)
            FROM sessions WHERE source = ?
            """,
            (run_tag,),
        ).fetchone()
        connection.close()
    except (sqlite3.Error, OSError):
        return None
    return {
        "segments": int(row[0]),
        "api_calls": int(row[1]),
        "input_tokens": int(row[2]),
        "output_tokens": int(row[3]),
    }


def render(args: argparse.Namespace) -> str:
    try:
        log = Path(args.run_log).read_text(encoding="utf-8", errors="replace")
    except OSError:
        log = ""

    iterations = list(ITERATION_RE.finditer(log))
    iteration = (
        f"HIT({iterations[-1]['used']}/{iterations[-1]['limit']})"
        if iterations
        else "未觸頂"
    )
    compression = max(
        len(COMPRESSION_RE.findall(log)),
        len(COMPRESSION_DONE_RE.findall(log)),
    )
    flags = {
        "aux_timeout": bool(AUX_TIMEOUT_RE.search(log)),
        "gateway_idle": bool(GATEWAY_IDLE_RE.search(log)),
        "script_timeout": bool(SCRIPT_TIMEOUT_RE.search(log)),
    }
    usage = usage_summary(Path(args.state_db), args.run_tag)

    lines = [
        f"⏱ 執行：{args.attempts}／總時 {hms(args.elapsed)}",
        "⚠️ 狀態："
        f"迭代額度={'觸頂' + iteration[3:] if iteration.startswith('HIT') else iteration}｜"
        f"上下文壓縮={compression}｜"
        f"壓縮摘要逾時={'是' if flags['aux_timeout'] else '否'}｜"
        f"Gateway 閒置逾時={'是' if flags['gateway_idle'] else '否'}｜"
        f"Cron 腳本逾時={'是' if flags['script_timeout'] else '否'}",
    ]
    if usage is None:
        lines.extend(
            [
                f"🤖 Agent：呼叫={args.invocations}｜session 段數=n/a｜API 呼叫=n/a",
                "🪙 Token：輸入／輸出 n/a",
            ]
        )
    else:
        lines.extend(
            [
                f"🤖 Agent：呼叫={args.invocations}｜session 段數={usage['segments']}｜"
                f"API 呼叫={usage['api_calls']}",
                f"🪙 Token：輸入={usage['input_tokens']:,}｜輸出={usage['output_tokens']:,}",
            ]
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-db", required=True)
    parser.add_argument("--run-tag", required=True)
    parser.add_argument("--run-log", required=True)
    parser.add_argument("--attempts", required=True)
    parser.add_argument("--elapsed", required=True, type=int)
    parser.add_argument("--invocations", required=True, type=int)
    print(render(parser.parse_args()))


if __name__ == "__main__":
    main()
