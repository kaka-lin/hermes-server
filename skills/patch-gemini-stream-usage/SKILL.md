---
name: patch-gemini-stream-usage
description: "[DEPRECATED — fixed upstream] Patches Gemini native adapter to parse usageMetadata in streaming mode"
version: 1.1.0
---
# Patch Gemini Stream Usage

> [!WARNING]
> **Deprecated as of 2026-06-09 — fixed upstream in v0.13.0.** The fix landed in
> hermes-agent **v0.13.0** (tag `v2026.5.7`, released 2026-05-07, "The Tenacity
> Release"), via commit 2026-05-04 `fix(gemini): extract usageMetadata from
> streaming chunks for token tracking`. `translate_stream_event` now parses
> `usageMetadata` and attaches token counts to the finish chunk, so any base
> image **>= v0.13.0** already reports streaming usage correctly. The patch is no
> longer wired into the Dockerfile; this page is retained for history and
> rollback only.
>
> To actually pick up the upstream fix, rebuild with a fresh base
> (`docker compose build --pull`) — a plain `build` reuses the cached base layer
> and may still be an old, pre-v0.13.0 image.

Hermes Agent's `gemini_native_adapter.py` dropped `usageMetadata` during streaming.
This skill applied a Python patch script located at `/opt/data/scripts/patch_gemini.py` to fix it.

## Trigger

When restarting the container or when streaming token usage shows 0 for Gemini models.

## Steps

1. Run `python /opt/data/scripts/patch_gemini.py`
2. Restart Hermes Gateway or the CLI session.
