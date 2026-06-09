# DEPRECATED (2026-06-09): no longer wired into the Dockerfile.
#
# Upstream hermes-agent fixed this independently in v0.13.0 (tag v2026.5.7,
# released 2026-05-07, "The Tenacity Release") — commit 2026-05-04
# "fix(gemini): extract usageMetadata from streaming chunks for token tracking".
# translate_stream_event now parses `usageMetadata` (promptTokenCount /
# candidatesTokenCount) and attaches token counts to the finish chunk, so any
# base image >= v0.13.0 already reports streaming usage correctly.
#
# Kept for reference and as a rollback safety net. Note it uses plain
# str.replace() with no anchor check: against a newer base image whose code has
# changed, every replace() silently no-ops (it does NOT corrupt the file), so
# re-enabling it on an already-fixed base is harmless but pointless. Only re-add
# the Dockerfile COPY/RUN lines if Gemini streaming usage shows 0 again.

import re

print("Patching gemini_native_adapter.py...")

with open('/opt/hermes/agent/gemini_native_adapter.py', 'r') as f:
    content = f.read()

# 1. Update _make_stream_chunk signature
content = content.replace(
'''    finish_reason: Optional[str] = None,
    reasoning: str = "",
) -> _GeminiStreamChunk:''',
'''    finish_reason: Optional[str] = None,
    reasoning: str = "",
    usage: Optional[SimpleNamespace] = None,
) -> _GeminiStreamChunk:'''
)

# 2. Update _make_stream_chunk return
content = content.replace(
'''        model=model,
        choices=[choice],
        usage=None,
    )''',
'''        model=model,
        choices=[choice],
        usage=usage,
    )'''
)

# 3. Update translate_stream_event signature and parsing
old_trans = '''def translate_stream_event(event: Dict[str, Any], model: str, tool_call_indices: Dict[str, Dict[str, Any]]) -> List[_GeminiStreamChunk]:'''
new_trans = '''def translate_stream_event(event: Dict[str, Any], model: str, tool_call_indices: Dict[str, Dict[str, Any]]) -> List[_GeminiStreamChunk]:
    chunks: List[_GeminiStreamChunk] = []
    
    # Process usageMetadata if present in this event (usually the last chunk)
    usage_meta = event.get("usageMetadata")
    stream_usage = None
    if usage_meta and isinstance(usage_meta, dict):
        stream_usage = SimpleNamespace(
            prompt_tokens=int(usage_meta.get("promptTokenCount") or 0),
            completion_tokens=int(usage_meta.get("candidatesTokenCount") or 0),
            total_tokens=int(usage_meta.get("totalTokenCount") or 0),
            prompt_tokens_details=SimpleNamespace(
                cached_tokens=int(usage_meta.get("cachedContentTokenCount") or 0),
            ),
        )'''
content = content.replace(old_trans, new_trans)

# 4. We need to replace the assignment of chunks inside translate_stream_event.
content = content.replace(
'''    candidates = event.get("candidates") or []
    if not candidates:
        return []
    cand = candidates[0] if isinstance(candidates[0], dict) else {}
    parts = ((cand.get("content") or {}).get("parts") or []) if isinstance(cand, dict) else []
    chunks: List[_GeminiStreamChunk] = []''',
'''    candidates = event.get("candidates") or []
    if not candidates:
        if stream_usage:
            # Yield a chunk with just usage if no candidates but usage is present
            return [_make_stream_chunk(model=model, usage=stream_usage)]
        return []
    cand = candidates[0] if isinstance(candidates[0], dict) else {}
    parts = ((cand.get("content") or {}).get("parts") or []) if isinstance(cand, dict) else []'''
)

# 5. Make sure the finish reason chunk includes usage if present
content = content.replace(
'''    finish_reason_raw = str(cand.get("finishReason") or "")
    if finish_reason_raw:
        mapped = "tool_calls" if tool_call_indices else _map_gemini_finish_reason(finish_reason_raw)
        chunks.append(_make_stream_chunk(model=model, finish_reason=mapped))
    return chunks''',
'''    finish_reason_raw = str(cand.get("finishReason") or "")
    if finish_reason_raw:
        mapped = "tool_calls" if tool_call_indices else _map_gemini_finish_reason(finish_reason_raw)
        chunks.append(_make_stream_chunk(model=model, finish_reason=mapped, usage=stream_usage))
        stream_usage = None # Consumed

    # If we have usage but no finish reason (e.g. usage only chunk or weird chunking)
    if stream_usage:
        chunks.append(_make_stream_chunk(model=model, usage=stream_usage))
        
    return chunks'''
)

with open('/opt/hermes/agent/gemini_native_adapter.py', 'w') as f:
    f.write(content)

print("Patch applied successfully!")
