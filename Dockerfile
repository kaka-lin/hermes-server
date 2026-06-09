FROM nousresearch/hermes-agent:latest

# Copy and install dependencies
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --system --break-system-packages --no-cache-dir -r /tmp/requirements.txt

# Copy and run the patch scripts

# DISABLED 2026-06-09: fixed upstream in hermes-agent v0.13.0 (tag v2026.5.7,
# 2026-05-07, "The Tenacity Release") — commit 2026-05-04 "fix(gemini): extract
# usageMetadata from streaming chunks for token tracking" makes
# translate_stream_event parse usageMetadata and attach token counts to the
# finish chunk. So patch_gemini.py is redundant on any base image >= v0.13.0.
# Kept (commented) for reference / base-image rollback. Re-enable both lines
# only if running an older base where Gemini streaming token usage shows 0.
# COPY scripts/patch_gemini.py /tmp/patch_gemini.py
# RUN python3 /tmp/patch_gemini.py && rm /tmp/patch_gemini.py

