import sys

TARGET = "/opt/hermes/gateway/platforms/dingtalk.py"

# Fixes the DingTalk Stream-mode handler under a lazy-installed SDK.
#
# dingtalk-stream is not in the base image; it is installed at runtime by
# tools.lazy_deps.ensure("platform.dingtalk"). At the moment dingtalk.py is
# first imported the package is therefore absent, so the top-level
# `import dingtalk_stream` fails, DINGTALK_STREAM_AVAILABLE is False, and the
# module-level `class _IncomingHandler(... if DINGTALK_STREAM_AVAILABLE else
# object)` binds to `object`. check_dingtalk_requirements() later installs the
# SDK and flips the flag, but upstream never rebinds the class, so the handler
# stays an `object` subclass with no ChatbotHandler.raw_process() — the SDK then
# logs "'_IncomingHandler' object has no attribute 'raw_process'" on every
# inbound message and the bot never replies.
#
# Two anchored halves:
#   1. rebuild — after the lazy install flips the flags, rebuild
#      _IncomingHandler as a real ChatbotHandler subclass. type() is used
#      rather than `__bases__ =` assignment, which Python 3.13 prohibits for an
#      object-derived heap class (deallocator/layout mismatch).
#   2. explicit base init — the rebuilt class's copied __init__ must NOT use
#      zero-arg super(): a method copied via type() keeps its original implicit
#      __class__ cell (pointing at the discarded object-based class), so
#      super().__init__() raises "TypeError: super(type, obj): obj must be an
#      instance or subtype of type" at instantiation. Naming the base class
#      directly sidesteps the stale cell and works for both the normal and the
#      rebuilt class.
#
# Applied at build time against a pristine base image. A single idempotency
# guard skips a re-run; a missing anchor on either half aborts before writing.

REBUILD_ANCHOR = '''        DINGTALK_STREAM_AVAILABLE = True
        HTTPX_AVAILABLE = True
    if not os.getenv("DINGTALK_CLIENT_ID") or not os.getenv("DINGTALK_CLIENT_SECRET"):'''

REBUILD_PATCHED = '''        DINGTALK_STREAM_AVAILABLE = True
        HTTPX_AVAILABLE = True
        # The module-level _IncomingHandler was bound to `object` because the
        # SDK was absent at import time (lazy install). Rebuild it now as a
        # real ChatbotHandler subclass so it has raw_process(). type() is used
        # rather than `__bases__ =` assignment, which Python 3.13 prohibits for
        # an object-derived heap class.
        if "_IncomingHandler" in globals():
            handler_cls = globals()["_IncomingHandler"]
            if handler_cls.__bases__ == (object,):
                globals()["_IncomingHandler"] = type(
                    "_IncomingHandler",
                    (_ds.ChatbotHandler,),
                    {k: v for k, v in handler_cls.__dict__.items()
                     if k not in ("__dict__", "__weakref__")},
                )
    if not os.getenv("DINGTALK_CLIENT_ID") or not os.getenv("DINGTALK_CLIENT_SECRET"):'''

INIT_ANCHOR = '''    def __init__(self, adapter: DingTalkAdapter, loop: Optional[asyncio.AbstractEventLoop] = None):
        if DINGTALK_STREAM_AVAILABLE:
            super().__init__()
        self._adapter = adapter
        self._loop = loop'''

INIT_PATCHED = '''    def __init__(self, adapter: DingTalkAdapter, loop: Optional[asyncio.AbstractEventLoop] = None):
        # Explicit base init instead of zero-arg super(): after the type()
        # rebuild in check_dingtalk_requirements(), a copied method's implicit
        # __class__ cell still points at the original object-based class, so
        # super().__init__() would raise TypeError. Naming the base sidesteps it.
        if DINGTALK_STREAM_AVAILABLE and dingtalk_stream is not None:
            dingtalk_stream.ChatbotHandler.__init__(self)
        self._adapter = adapter
        self._loop = loop'''

# (label, anchor, replacement)
PATCHES = [
    ("lazy-install handler rebuild", REBUILD_ANCHOR, REBUILD_PATCHED),
    ("explicit base __init__", INIT_ANCHOR, INIT_PATCHED),
]


def main() -> int:
    print("Patching dingtalk.py (lazy-install _IncomingHandler rebuild + explicit base init)...")

    with open(TARGET, "r") as f:
        content = f.read()

    if "dingtalk_stream.ChatbotHandler.__init__(self)" in content:
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
