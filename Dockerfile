ARG HERMES_VERSION=v2026.9.14
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# Extra packages for our skills. Target the hermes venv explicitly: `--system` lands in Debian's
# /usr/local/lib/python3.13/dist-packages, which the venv does not see, so hermes never finds them.
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/requirements.txt

# Bake the DingTalk SDK into the venv. Upstream leaves it to a runtime lazy install, but the
# adapter module binds _IncomingHandler to `object` when the SDK is absent at import time and
# never rebinds it, so the bot crashes with no raw_process() on every inbound message.
# Export the `dingtalk` extra from upstream's own lockfile so cryptography stays at the pinned
# 50.x (the SDK's metadata alone would drag it back below 49). Not `uv sync`: it honours
# .python-version (3.11) and recreated the venv from scratch, dropping every messaging extra.
RUN cd /opt/hermes \
    && uv export --frozen --extra dingtalk --no-hashes --no-emit-project --no-annotate -o /tmp/dingtalk-req.txt \
    && uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/dingtalk-req.txt \
    && rm /tmp/dingtalk-req.txt

# Apply upstream patches at build time (unified diffs under patches/, applied by apply.py).
#   - dingtalk-send-routing:   explicit dingtalk:cidXXXX== targets parse as explicit and deliver
#                              to that group via the official robot API when no session webhook
#                              is known (cron output, cross-group sends).
#   - cli-session-source-override: preserve an explicit cron source tag on the session a context
#                                  compression spawns instead of replacing it with the CLI label
#                                  (upstream already honours it for the initial session).
COPY patches/ /tmp/patches/
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && python3 /tmp/patches/apply.py \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
