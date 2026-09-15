---
name: patch-dingtalk
description: "Fixes Hermes Agent's DingTalk integration at image build time: (1) routing patch — explicit dingtalk:cidXXXX== targets reach that specific group via the official robot API instead of the home channel or a single webhook; (2) Stream handler — the SDK is baked into the image so _IncomingHandler binds to ChatbotHandler at import and the bot replies instead of crashing with no raw_process()"
version: 1.0.0
---
# Patch DingTalk

Hermes Agent's DingTalk integration has two independent defects upstream. Both
are fixed at image build time ([Dockerfile](../../Dockerfile)) against the
pinned base image (`nousresearch/hermes-agent:v2026.9.14`): one by a patch, one
by baking the SDK into the venv. Patches are idempotent, so a re-run is a no-op.

Since v2026.9.x DingTalk lives in `plugins/platforms/dingtalk/adapter.py`, not
`gateway/platforms/dingtalk.py`.

The two fixes address **different symptoms** — read the one that matches what
you are seeing.

## 1. Routing — messages reach the wrong group

Patch: `patches/dingtalk-send-routing.patch`. Symptom: an explicit `dingtalk:cidXXXX==` target is
delivered to the home channel or to the webhook's single bound group instead of
the group it names.

Two halves of one fix:

- **Target parsing** — the plugin registers no `parse_target_ref_fn`, so
  `dingtalk:cidXXXX==` is not recognised as explicit and the send falls back to
  `DINGTALK_HOME_CHANNEL` — silently delivering to the wrong group. The patch
  registers a parser that treats any `cid...` id as an explicit target.

- **Send mechanism** — the live adapter's `send()` only knows per-session
  webhooks, which exist after an inbound message and expire; the cron-process
  `_standalone_send` only knows the static custom-robot webhook
  (`DINGTALK_WEBHOOK_URL`), bound to **one** group. The patch adds the official
  enterprise robot API (`groupMessages/send`) to both: when `chat_id` is a group
  id (`cid...`) and no session webhook is known, it posts with
  `openConversationId`, delivering to that specific group, and falls back to the
  webhook otherwise. The official path verifies the response body
  (`processQueryKey`) before reporting success, so a `200`-with-error-body falls
  back rather than reporting a false success.

## 2. Stream handler — the bot never replies

Fix: the Dockerfile exports the `dingtalk` extra from upstream's lockfile
(`uv export --frozen --extra dingtalk`) and installs it into the venv, so the
SDK is present at import time. Symptom
without it: every inbound message logs `'_IncomingHandler' object has no
attribute 'raw_process'` and the bot never replies.

`dingtalk-stream` is not in the base image; upstream lazy-installs it at runtime
into `HERMES_LAZY_INSTALL_TARGET` (the venv itself is sealed). When the adapter
module is first imported the package is still absent, so the top-level
`import dingtalk_stream` fails and the module-level `class _IncomingHandler(...
if DINGTALK_STREAM_AVAILABLE else object)` binds to `object`.
`ensure_dingtalk_deps()` later installs the SDK and rebinds the module globals,
but never the class, so it stays an `object` subclass with no
`ChatbotHandler.raw_process()`.

Installing the extra at build time removes the lazy path entirely. The earlier
`dingtalk-stream-handler.patch` (rebuild the class via `type()` after the lazy
install) is gone. Installing from upstream's lockfile keeps `cryptography` at the
pinned 50.x, which a plain `pip install alibabacloud-dingtalk` would drag back
below 49. Do not use `uv sync` for this: it honours `.python-version` (3.11)
and recreates the venv from scratch, dropping every messaging extra.

## Trigger

When rebuilding or restarting the container, or when DingTalk misbehaves:

- Messages to an explicit `dingtalk:cidXXXX==` group land in the home channel or
  the webhook's single group → apply patch 1.
- The bot never replies and logs `no attribute 'raw_process'` → the image was
  built without the `dingtalk` extra; rebuild with the current Dockerfile.

## Steps

Patches are applied at image build time by `patches/apply.py` (see
[Dockerfile](../../Dockerfile)). To (re)apply:

1. Rebuild the image: `./hermes-build.sh` (see the repo README for version tags).
2. Recreate the container: `./hermes-run.sh up`.

The applier is idempotent — patches already present are skipped — and aborts
the build with a clear error if an upstream change makes a patch no longer
apply (a signal to refresh the diff via `patches/README.md`).
