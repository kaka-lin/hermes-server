import sys

TARGET = "/opt/hermes/tools/send_message_tool.py"

print("Patching send_message_tool.py (dingtalk target parsing)...")

with open(TARGET, "r") as f:
    content = f.read()

# Upstream's _parse_target_ref has no `dingtalk` branch (confirmed still
# missing as of base image > v0.13.0, which added ntfy/email but not dingtalk),
# so an explicit target like "dingtalk:cidXXXX==" falls through to
# `return None, None, False` (is_explicit=False). The directory-resolution path
# then re-parses the resolved id through the same branch-less function, gets
# None again, and _handle_send falls back to DINGTALK_HOME_CHANNEL — silently
# delivering to the wrong group. Adding an explicit dingtalk branch makes the
# conversation id route directly, exactly like the other platforms.
#
# Anchored on the function signature + docstring (very stable) rather than a
# mid-function neighbour, so newly added platform branches (ntfy, email, …)
# don't break the anchor. dingtalk is an exact, mutually-exclusive match, so
# inserting it first is behaviourally identical to inserting it lower down.
ANCHOR = '''def _parse_target_ref(platform_name: str, target_ref: str):
    """Parse a tool target into chat_id/thread_id and whether it is explicit."""'''

PATCHED = '''def _parse_target_ref(platform_name: str, target_ref: str):
    """Parse a tool target into chat_id/thread_id and whether it is explicit."""
    if platform_name == "dingtalk":
        return target_ref.strip(), None, True'''

if 'if platform_name == "dingtalk":' in content:
    print("Already patched, skipping.")
    sys.exit(0)

if ANCHOR not in content:
    print("ERROR: anchor not found — upstream layout changed, patch NOT applied.")
    sys.exit(1)

content = content.replace(ANCHOR, PATCHED)

with open(TARGET, "w") as f:
    f.write(content)

print("Patch applied successfully!")
