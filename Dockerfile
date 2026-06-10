ARG HERMES_VERSION=v2026.6.5
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# Copy and install dependencies
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --system --break-system-packages --no-cache-dir -r /tmp/requirements.txt

# Apply upstream patches at build time (unified diffs under patches/, applied by apply.py).
#   - dingtalk-send-routing:   explicit dingtalk:cidXXXX== targets deliver to that group
#                              via the official robot API.
#   - dingtalk-stream-handler: rebuild _IncomingHandler after the lazy SDK install so the
#                              bot replies instead of crashing with no raw_process().
COPY patches/ /tmp/patches/
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && python3 /tmp/patches/apply.py \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
