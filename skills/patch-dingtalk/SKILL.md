---
name: patch-dingtalk
description: "Fixes Hermes Agent's DingTalk integration at image build time: (1) routing patch — explicit dingtalk:cidXXXX== targets resolve and reach that specific group via the official robot API instead of failing with 'Could not resolve' or landing in the webhook's single group; (2) Stream handler — the SDK is baked into the image so _IncomingHandler binds to ChatbotHandler at import and the bot replies instead of crashing with no raw_process()"
version: 1.1.0
---
# Patch DingTalk

Hermes Agent's DingTalk integration has two independent defects upstream. Both
are fixed at image build time ([Dockerfile](../../Dockerfile)) against the
pinned base image (`nousresearch/hermes-agent:v0.23.1`): one by a patch, one
by baking the SDK into the venv. Patches are idempotent, so a re-run is a no-op.

DingTalk lives in `plugins/platforms/dingtalk/adapter.py`.

The two fixes address **different symptoms** — read the one that matches what
you are seeing.

## 1. Routing — messages to a named group fail or reach the wrong group

Patch: `patches/dingtalk-send-routing.patch`. Symptoms: `send_message` to an
explicit `dingtalk:cidXXXX==` target fails with `Could not resolve`, or the
message is delivered to the webhook's single bound group instead of the group
it names.

Two halves of one fix:

- **Target parsing** — upstream's `send_message` resolves targets strictly, and
  a `cid...` id that is not in the channel directory is rejected with
  `Could not resolve`. The patch registers upstream's
  `target_ref_syntax_fn=parse_nonempty`, so `dingtalk:cidXXXX==` is accepted as
  an explicit target.

- **Send mechanism** — in v0.23.1 a plain-text DingTalk `send_message` always
  goes to the standalone sender `_standalone_send`
  (`StandaloneSendPolicy(text_direct=True)`), which upstream only knows as the
  static custom-robot webhook (`DINGTALK_WEBHOOK_URL`), bound to **one** group.
  The patch makes `_standalone_send` try the official robot API
  (`robot/groupMessages/send`, `openConversationId=<cid>`, `msgKey`
  `sampleMarkdown`) first when `chat_id` is a `cid...` group id and
  `DINGTALK_CLIENT_ID` / `DINGTALK_CLIENT_SECRET` are set. The robot code
  defaults to the client id; set `robot_code` in the platform `extra` to
  override it. If the API does not confirm delivery, it falls back to the
  webhook, now sent as markdown. The live adapter's `send()` also uses the
  robot API when it has no session webhook for a `cid...` chat.

The official path verifies the response body (`processQueryKey`) before
reporting success, so a `200`-with-error-body falls back rather than reporting
a false success.

Regression test: `tests/test_dingtalk_send_routing.py`. It passes on the
patched image and fails on upstream at `cid` target resolution.

## 2. Stream handler — the bot never replies

Fix: the Dockerfile exports the `dingtalk` extra from upstream's lockfile
(`uv export --frozen --extra dingtalk`) and installs it into the venv, so the
SDK is present at import time. `uv` is not on `PATH` in the base image; the
Dockerfile calls `/opt/hermes/tools/uv-*/uv`. Symptom without it: every
inbound message logs `'_IncomingHandler' object has no attribute
'raw_process'` and the bot never replies.

`dingtalk-stream` is not in the base image; upstream lazy-installs it at runtime
into `HERMES_LAZY_INSTALL_TARGET` (the venv itself is sealed). When the adapter
module is first imported the package is still absent, so the top-level
`import dingtalk_stream` fails and the module-level `class _IncomingHandler(...
if DINGTALK_STREAM_AVAILABLE else object)` binds to `object`.
`ensure_dingtalk_deps()` later installs the SDK and rebinds the module globals,
but never the class, so it stays an `object` subclass with no
`ChatbotHandler.raw_process()`. This import-time bug is still present in
v0.23.1.

Installing the extra at build time removes the lazy path entirely. Installing
from upstream's lockfile keeps `cryptography` at the
pinned 50.x, which a plain `pip install alibabacloud-dingtalk` would drag back
below 49. Do not use `uv sync` for this: it honours `.python-version` (3.14)
and recreates the venv from scratch, dropping every messaging extra.

## Trigger

When rebuilding or restarting the container, or when DingTalk misbehaves:

- `send_message` to an explicit `dingtalk:cidXXXX==` group fails with
  `Could not resolve`, or lands in the webhook's single group → apply patch 1.
- The bot never replies and logs `no attribute 'raw_process'` → the image was
  built without the `dingtalk` extra; rebuild with the current Dockerfile.

## Steps

Patches are applied at image build time by `patches/apply.py` (see
[Dockerfile](../../Dockerfile)). To (re)apply:

1. Rebuild the image: `./hermes-build.sh` (see [docs/setup.md](../../docs/setup.md) for version tags).
2. Recreate the container: `./hermes-run.sh up`.

The applier is idempotent — patches already present are skipped — and aborts
the build with a clear error if an upstream change makes a patch no longer
apply (a signal to refresh the diff via `patches/README.md`).

Each Hermes profile needs its own DingTalk app credentials: one bot token
cannot be polled by two profiles at once.
