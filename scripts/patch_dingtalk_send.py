import sys

TARGET = "/opt/hermes/tools/send_message_tool.py"

# Two halves of the same fix: making an explicit "dingtalk:cidXXXX==" target
# actually deliver to that specific group.
#
#   1. _parse_target_ref — upstream has no `dingtalk` branch (confirmed still
#      missing as of v0.16.0, tag v2026.6.5, which added ntfy/email but not
#      dingtalk), so "dingtalk:cidXXXX==" falls through to
#      `return None, None, False` (is_explicit=False). The directory-resolution
#      path re-parses through the same branch-less function, gets None again,
#      and _handle_send falls back to DINGTALK_HOME_CHANNEL — silently
#      delivering to the wrong group. Adding the branch makes the conversation
#      id route directly, exactly like the other platforms.
#
#   2. _send_dingtalk — upstream only knows the static custom-robot webhook
#      (DINGTALK_WEBHOOK_URL), which is bound to ONE group, so even a correctly
#      parsed cid is ignored at send time and every out-of-process send lands
#      in that single group. This adds the official enterprise robot API
#      (groupMessages/send): when client_id/client_secret are configured and
#      chat_id is a group id (cid...), it fetches an accessToken and posts with
#      openConversationId, delivering to that specific group, with a webhook
#      fallback. The official path verifies the response body (processQueryKey)
#      before reporting success so a 200-with-error-body falls back rather than
#      reporting a false success.
#
# Applied at build time against a pristine base image, so both anchors are
# always present together. A single idempotency guard skips a re-run; a missing
# anchor on either half aborts before writing anything.

PARSE_ANCHOR = '''def _parse_target_ref(platform_name: str, target_ref: str):
    """Parse a tool target into chat_id/thread_id and whether it is explicit."""'''

PARSE_PATCHED = '''def _parse_target_ref(platform_name: str, target_ref: str):
    """Parse a tool target into chat_id/thread_id and whether it is explicit."""
    if platform_name == "dingtalk":
        return target_ref.strip(), None, True'''

SEND_ANCHOR = '''async def _send_dingtalk(extra, chat_id, message):
    """Send via DingTalk robot webhook.

    Note: The gateway's DingTalk adapter uses per-session webhook URLs from
    incoming messages (dingtalk-stream SDK).  For cross-platform send_message
    delivery we use a static robot webhook URL instead, which must be
    configured via ``DINGTALK_WEBHOOK_URL`` env var or ``webhook_url`` in the
    platform's extra config.
    """
    try:
        import httpx
    except ImportError:
        return {"error": "httpx not installed"}
    try:
        webhook_url = extra.get("webhook_url") or os.getenv("DINGTALK_WEBHOOK_URL", "")
        if not webhook_url:
            return {"error": "DingTalk not configured. Set DINGTALK_WEBHOOK_URL env var or webhook_url in dingtalk platform extra config."}
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                webhook_url,
                json={"msgtype": "text", "text": {"content": message}},
            )
            resp.raise_for_status()
            data = resp.json()
            if data.get("errcode", 0) != 0:
                return _error(f"DingTalk API error: {data.get('errmsg', 'unknown')}")
        return {"success": True, "platform": "dingtalk", "chat_id": chat_id}
    except Exception as e:
        return _error(f"DingTalk send failed: {e}")'''

SEND_PATCHED = '''async def _send_dingtalk(extra, chat_id, message):
    """Send via DingTalk platform.

    Tries the official enterprise robot API (groupMessages/send) when
    ``client_id``/``client_secret`` are configured and ``chat_id`` is a group
    conversation id (``cid...``); this delivers to the specific group via
    ``openConversationId`` instead of a single static webhook target. Falls
    back to the custom robot webhook (``DINGTALK_WEBHOOK_URL`` /
    ``webhook_url``) on any failure or for non-group targets.
    """
    try:
        import httpx
    except ImportError:
        return {"error": "httpx not installed"}

    extra = extra or {}

    # 1. Official enterprise robot API — routes to a specific group by
    #    openConversationId, so multiple cid groups can each be addressed.
    client_id = extra.get("client_id") or os.getenv("DINGTALK_CLIENT_ID", "")
    client_secret = extra.get("client_secret") or os.getenv("DINGTALK_CLIENT_SECRET", "")
    is_group_chat = bool(chat_id) and chat_id.startswith("cid")

    if client_id and client_secret and is_group_chat:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                token_resp = await client.post(
                    "https://api.dingtalk.com/v1.0/oauth2/accessToken",
                    json={"appKey": client_id, "appSecret": client_secret},
                )
                token_resp.raise_for_status()
                access_token = token_resp.json().get("accessToken")

                if access_token:
                    # DingTalk markdown msgParam supports up to 20000 chars.
                    msg_param = json.dumps({"title": "Hermes", "text": message})
                    send_resp = await client.post(
                        "https://api.dingtalk.com/v1.0/robot/groupMessages/send",
                        headers={
                            "x-acs-dingtalk-access-token": access_token,
                            "Content-Type": "application/json",
                        },
                        json={
                            "robotCode": client_id,
                            "openConversationId": chat_id,
                            "msgKey": "sampleMarkdown",
                            "msgParam": msg_param,
                        },
                    )
                    send_resp.raise_for_status()
                    res_data = send_resp.json()
                    # A successful send returns a processQueryKey. Anything else
                    # (e.g. a 200 with a logical error body) is treated as a
                    # failure so we fall back to the webhook instead of
                    # reporting a false success.
                    if res_data.get("processQueryKey"):
                        logger.info(
                            "send_message DingTalk: delivered via official Robot API to %s",
                            chat_id,
                        )
                        return {
                            "success": True,
                            "platform": "dingtalk",
                            "chat_id": chat_id,
                            "method": "official_robot_api",
                        }
                    logger.warning(
                        "DingTalk official API returned no processQueryKey (%s), falling back to webhook",
                        res_data,
                    )
        except Exception as api_exc:
            logger.warning("DingTalk official API send failed, falling back to webhook: %s", api_exc)

    # 2. Fallback: custom robot webhook (one-way broadcast to its bound group).
    try:
        webhook_url = extra.get("webhook_url") or os.getenv("DINGTALK_WEBHOOK_URL", "")
        if not webhook_url:
            return {"error": "DingTalk not configured. Set DINGTALK_WEBHOOK_URL env var or webhook_url in dingtalk platform extra config."}
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                webhook_url,
                json={"msgtype": "markdown", "markdown": {"title": "Hermes", "text": message}},
            )
            resp.raise_for_status()
            data = resp.json()
            if data.get("errcode", 0) != 0:
                return _error(f"DingTalk webhook API error: {data.get('errmsg', 'unknown')}")
        return {"success": True, "platform": "dingtalk", "chat_id": chat_id, "method": "custom_webhook"}
    except Exception as e:
        return _error(f"DingTalk send failed: {e}")'''

# (label, anchor, replacement)
PATCHES = [
    ("target parsing", PARSE_ANCHOR, PARSE_PATCHED),
    ("official robot API send", SEND_ANCHOR, SEND_PATCHED),
]


def main() -> int:
    print("Patching send_message_tool.py (dingtalk routing: target parsing + official robot API send)...")

    with open(TARGET, "r") as f:
        content = f.read()

    if '"method": "official_robot_api"' in content:
        print("Already patched, skipping.")
        return 0

    for label, anchor, patched in PATCHES:
        if anchor not in content:
            print(f"ERROR: {label} anchor not found — upstream layout changed, patch NOT applied.")
            return 1
        content = content.replace(anchor, patched)
        print(f"  - {label}: applied.")

    with open(TARGET, "w") as f:
        f.write(content)

    print("Patch applied successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
