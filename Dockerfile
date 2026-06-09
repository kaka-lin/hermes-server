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

# Still required as of v0.16.0 (tag v2026.6.5): two halves of one dingtalk fix.
#   - _parse_target_ref has no dingtalk branch, so explicit dingtalk: targets
#     fall back to the home channel.
#   - _send_dingtalk only knows the static custom-robot webhook (one bound
#     group), so out-of-process sends ignore the requested chat_id.
# The patch adds the dingtalk branch and the official enterprise robot API
# (groupMessages/send) so an explicit dingtalk:cidXXXX== target delivers to
# that specific group, with a webhook fallback.
COPY scripts/patch_dingtalk.py /tmp/patch_dingtalk.py
RUN python3 /tmp/patch_dingtalk.py && rm /tmp/patch_dingtalk.py

# dingtalk-stream is lazy-installed at runtime, so it is absent when dingtalk.py
# is first imported: _IncomingHandler binds to `object` and never regains
# ChatbotHandler.raw_process(), so the bot logs "'_IncomingHandler' object has
# no attribute 'raw_process'" and never replies. This patch rebuilds the
# handler as a real ChatbotHandler subclass after the lazy install (via type(),
# since Python 3.13 forbids __bases__ assignment) and switches its __init__ to
# an explicit base call so the rebuilt class doesn't TypeError on a stale
# super() __class__ cell.
COPY scripts/patch_dingtalk_handler.py /tmp/patch_dingtalk_handler.py
RUN python3 /tmp/patch_dingtalk_handler.py && rm /tmp/patch_dingtalk_handler.py

