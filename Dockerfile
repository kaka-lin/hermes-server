ARG HERMES_VERSION=v0.23.1
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# agent-browser CLI lets skills pick a host Chrome profile per command (--cdp <port>),
# which browser_exec cannot. Since v0.23 Hermes no longer uses it and /opt/hermes
# refuses npm, so it gets its own prefix plus a wrapper that finds Hermes's Chromium.
ARG AGENT_BROWSER_VERSION=0.26.0
RUN npm install --prefix /opt/agent-browser --no-save --no-audit \
    "agent-browser@${AGENT_BROWSER_VERSION}"
COPY --chmod=0755 docker/bin/agent-browser /usr/local/bin/agent-browser
RUN agent-browser --version

# Install custom-skill dependencies into the Hermes virtual environment.
COPY requirements.txt /tmp/requirements.txt
# Since v0.23 uv is no longer on PATH; it lives in the arch-specific tool store.
RUN UV="$(ls /opt/hermes/tools/uv-*/uv)" \
    && "$UV" pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/requirements.txt

# Install DingTalk from the upstream lockfile so its SDK is available at import time.
RUN UV="$(ls /opt/hermes/tools/uv-*/uv)" && cd /opt/hermes \
    && "$UV" export --frozen --extra dingtalk --no-hashes --no-emit-project --no-annotate -o /tmp/dingtalk-req.txt \
    && "$UV" pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/dingtalk-req.txt \
    && rm /tmp/dingtalk-req.txt

# Apply all build-time patches from patches/ (see patches/README.md).
COPY patches/ /tmp/patches/
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && python3 /tmp/patches/apply.py \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
