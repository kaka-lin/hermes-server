FROM nousresearch/hermes-agent:latest

# Copy and install dependencies
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --system --break-system-packages --no-cache-dir -r /tmp/requirements.txt

# Copy and run the patch scripts.

# patch_gemini DISABLED 2026-06-09: fixed upstream in hermes-agent v0.13.0
# (tag v2026.5.7). Re-enable only on an older base where Gemini streaming
# token usage shows 0.
# COPY scripts/patch_gemini.py /tmp/patch_gemini.py
# RUN python3 /tmp/patch_gemini.py && rm /tmp/patch_gemini.py

# Outbound routing: explicit dingtalk:cidXXXX== targets deliver to that group
# via the official robot API. Still required as of v0.16.0 (tag v2026.6.5).
COPY scripts/patch_dingtalk_send.py /tmp/patch_dingtalk_send.py
RUN python3 /tmp/patch_dingtalk_send.py && rm /tmp/patch_dingtalk_send.py

# Inbound handler: rebuild _IncomingHandler after the lazy SDK install so the
# bot replies instead of crashing with no raw_process(). Still required v0.16.0.
COPY scripts/patch_dingtalk_handler.py /tmp/patch_dingtalk_handler.py
RUN python3 /tmp/patch_dingtalk_handler.py && rm /tmp/patch_dingtalk_handler.py

