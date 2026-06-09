---
name: patch-dingtalk
description: "Patches send_message_tool so explicit dingtalk:cidXXXX== targets route to and deliver to that specific group (target parsing + official robot API send) instead of falling back to the home channel or a single webhook"
version: 1.0.0
---
# Patch DingTalk Routing

Hermes Agent's `tools/send_message_tool.py` mis-routes out-of-process DingTalk
sends in two ways, so an explicit `dingtalk:cidXXXX==` target never reaches the
group it names. This skill applies one patch script that fixes both halves:

1. **Target parsing** — `_parse_target_ref` has no `dingtalk` branch, so
   `dingtalk:cidXXXX==` is parsed as `None` (not explicit). The
   directory-resolution path re-parses through the same branch-less function,
   gets `None` again, and `_handle_send` falls back to `DINGTALK_HOME_CHANNEL`
   — silently delivering to the wrong group. The patch adds the branch so the
   conversation id routes directly.

2. **Send mechanism** — `_send_dingtalk` only knows the static custom-robot
   webhook (`DINGTALK_WEBHOOK_URL`), which is bound to **one** group, so even a
   correctly parsed `cid` is ignored at send time. The patch adds the official
   enterprise robot API (`groupMessages/send`): when `DINGTALK_CLIENT_ID` /
   `DINGTALK_CLIENT_SECRET` are set and `chat_id` is a group id (`cid...`), it
   fetches an `accessToken` and posts with `openConversationId`, delivering to
   that specific group; it falls back to the webhook on failure or for
   non-group targets. The official path verifies the response body
   (`processQueryKey`) before reporting success, so a `200`-with-error-body
   falls back rather than reporting a false success.

The patch script at `/opt/data/scripts/patch_dingtalk.py` is applied at build
time against a pristine base image (both halves together) and is idempotent, so
a re-run is a no-op.

## Trigger

When restarting the container, or when a background/cron agent told to send to
a specific `dingtalk:cidXXXX==` group keeps delivering to the home channel or
to the webhook's single bound group.

## Steps

1. Run `python /opt/data/scripts/patch_dingtalk.py`
2. Restart Hermes Gateway or the CLI session.
