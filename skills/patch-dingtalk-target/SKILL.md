---
name: patch-dingtalk-target
description: "Patches send_message_tool to parse explicit dingtalk: targets instead of falling back to the home channel"
version: 1.0.0
---
# Patch DingTalk Target Parsing

Hermes Agent's `tools/send_message_tool.py` has no `dingtalk` branch in
`_parse_target_ref`, so an explicit target like `dingtalk:cidXXXX==` is parsed
as `None` (not explicit). The directory-resolution path re-parses the resolved
id through the same branch-less function, gets `None` again, and `_handle_send`
falls back to `DINGTALK_HOME_CHANNEL` — silently delivering to the wrong group.

This skill applies a Python patch script located at
`/opt/data/scripts/patch_dingtalk_target.py` that adds the missing branch so
the conversation id routes directly.

## Trigger

When restarting the container, or when a background/cron agent told to send to
a specific `dingtalk:cidXXXX==` group keeps delivering to the home channel.

## Steps

1. Run `python /opt/data/scripts/patch_dingtalk_target.py`
2. Restart Hermes Gateway or the CLI session.
