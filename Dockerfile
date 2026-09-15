ARG HERMES_VERSION=v2026.9.14
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# Install custom-skill dependencies into the Hermes virtual environment.
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/requirements.txt

# Install DingTalk from the upstream lockfile so its SDK is available at import time.
RUN cd /opt/hermes \
    && uv export --frozen --extra dingtalk --no-hashes --no-emit-project --no-annotate -o /tmp/dingtalk-req.txt \
    && uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r /tmp/dingtalk-req.txt \
    && rm /tmp/dingtalk-req.txt

# Drain dynamic s6 gateways before the final shutdown sweep.
COPY --chmod=0755 docker/cont-finish.d/ /etc/cont-finish.d/

# Debian's /etc/profile resets PATH for every login shell. Restore the Hermes
# CLI paths so terminal tool commands can invoke `hermes` as documented.
COPY --chmod=0644 docker/profile.d/ /etc/profile.d/

# Apply all build-time patches from patches/:
# dingtalk routing, cron session source, runtime sockets, and optional-check logging.
COPY patches/ /tmp/patches/
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && python3 /tmp/patches/apply.py \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
