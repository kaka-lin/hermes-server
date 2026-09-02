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

# agent-browser >=0.27.1 needs Node >=24 but upstream ships 22, so one layer
# swaps in Node 24 and overrides the upstream pin (^0.26.0). The symlinks make
# the new Node win even when upstream's sits in /usr/local/bin (which shadows
# /usr/bin on PATH). Details: docs/guides/agent-browser-versions.md
ARG AGENT_BROWSER_VERSION=0.36.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && ln -sf /usr/bin/node /usr/local/bin/node \
    && ln -sf /usr/bin/npm /usr/local/bin/npm \
    && ln -sf /usr/bin/npx /usr/local/bin/npx \
    && node -v | grep -q '^v24\.' \
    && npm install --prefix /opt/hermes --no-audit "agent-browser@${AGENT_BROWSER_VERSION}" \
    && node -p "'agent-browser ' + require('/opt/hermes/node_modules/agent-browser/package.json').version" \
    && rm -rf /var/lib/apt/lists/*
