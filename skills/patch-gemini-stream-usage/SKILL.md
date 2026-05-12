---
name: patch-gemini-stream-usage
description: "Patches Gemini native adapter to properly parse usageMetadata in streaming mode"
version: 1.0.0
---
# Patch Gemini Stream Usage

Hermes Agent's `gemini_native_adapter.py` drops `usageMetadata` during streaming. 
This skill applies a Python patch script located at `/opt/data/scripts/patch_gemini.py` to fix it.

## Trigger

When restarting the container or when streaming token usage shows 0 for Gemini models.

## Steps

1. Run `python /opt/data/scripts/patch_gemini.py`
2. Restart Hermes Gateway or the CLI session.
