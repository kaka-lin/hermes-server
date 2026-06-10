---
name: patch-dingtalk
description: "Patches Hermes Agent's DingTalk integration with two build-time fixes: (1) routing — explicit dingtalk:cidXXXX== targets reach that specific group via the official robot API instead of the home channel or a single webhook; (2) Stream handler — rebuilds _IncomingHandler after the lazy SDK install so the bot actually replies instead of crashing with no raw_process()"
version: 1.0.0
---
# Patch DingTalk

Hermes Agent's DingTalk integration has two independent defects on the current
base image. Both are fixed by patch scripts applied at build time
([Dockerfile](../../Dockerfile)), in sequence, against a pristine base image.
Each script is idempotent, so a re-run is a no-op.

The two patches address **different symptoms** — read the one that matches what
you are seeing, or apply both after a rebuild.

## 1. Routing — messages reach the wrong group

Script: `patch_dingtalk_send.py`. Symptom: an explicit `dingtalk:cidXXXX==` target is
delivered to the home channel or to the webhook's single bound group instead of
the group it names.

Two halves of one fix:

- **Target parsing** — `_parse_target_ref` has no `dingtalk` branch, so
  `dingtalk:cidXXXX==` parses as `None` (not explicit). The directory-resolution
  path re-parses through the same branch-less function, gets `None` again, and
  `_handle_send` falls back to `DINGTALK_HOME_CHANNEL` — silently delivering to
  the wrong group. The patch adds the branch so the conversation id routes
  directly.

- **Send mechanism** — `_send_dingtalk` only knows the static custom-robot
  webhook (`DINGTALK_WEBHOOK_URL`), which is bound to **one** group, so even a
  correctly parsed `cid` is ignored at send time. The patch adds the official
  enterprise robot API (`groupMessages/send`): when `DINGTALK_CLIENT_ID` /
  `DINGTALK_CLIENT_SECRET` are set and `chat_id` is a group id (`cid...`), it
  fetches an `accessToken` and posts with `openConversationId`, delivering to
  that specific group; it falls back to the webhook on failure or for non-group
  targets. The official path verifies the response body (`processQueryKey`)
  before reporting success, so a `200`-with-error-body falls back rather than
  reporting a false success.

## 2. Stream handler — the bot never replies

Script: `patch_dingtalk_handler.py`. Symptom: every inbound message logs
`'_IncomingHandler' object has no attribute 'raw_process'` and the bot never
replies.

`dingtalk-stream` is not in the base image; it is lazy-installed at runtime by
`tools.lazy_deps.ensure("platform.dingtalk")`. When `dingtalk.py` is first
imported the package is still absent, so the top-level `import dingtalk_stream`
fails and the module-level `class _IncomingHandler(... if
DINGTALK_STREAM_AVAILABLE else object)` binds to `object`.
`check_dingtalk_requirements()` later installs the SDK and flips the flag, but
upstream never rebinds the class, so it stays an `object` subclass with no
`ChatbotHandler.raw_process()`.

Two halves of one fix:

- **Handler rebuild** — after the lazy install flips the flags, rebuild
  `_IncomingHandler` as a real `ChatbotHandler` subclass. `type()` is used
  rather than `__bases__ =` assignment, which Python 3.13 prohibits for an
  object-derived heap class.

- **Explicit base init** — the rebuilt class's copied `__init__` must NOT use
  zero-arg `super()`: a method copied via `type()` keeps its original implicit
  `__class__` cell (pointing at the discarded object-based class), so
  `super().__init__()` raises `TypeError` at instantiation. Naming the base
  class directly sidesteps the stale cell and works for both the normal and the
  rebuilt class.

## Trigger

When rebuilding or restarting the container, or when DingTalk misbehaves:

- Messages to an explicit `dingtalk:cidXXXX==` group land in the home channel or
  the webhook's single group → apply patch 1.
- The bot never replies and logs `no attribute 'raw_process'` → apply patch 2.

## Steps

1. Run `python /opt/data/scripts/patch_dingtalk_send.py`
2. Run `python /opt/data/scripts/patch_dingtalk_handler.py`
3. Restart Hermes Gateway or the CLI session.
