"""Debounce helper for the symbol-picker search filters.

Each keystroke in the search field fires a separate filter process. When the
user types fast these pile up faster than the list can be rebuilt. To collapse
a burst into a single rebuild, every invocation claims "latest" by atomically
writing a unique token to a per-window file, waits a short interval, then checks
whether it is still the latest claim. Only the last keystroke in a burst is —
the earlier (now superseded) ones return False and exit before doing any work,
which both defers the rebuild and cancels in-progress ones."""

import os
import time
import uuid
import tempfile

# How long to wait before committing to a rebuild. A burst of keystrokes closer
# together than this collapses into a single list rebuild.
DEBOUNCE_DELAY = 0.18


def should_rebuild(key, delay=DEBOUNCE_DELAY):
    """Return True if this invocation should rebuild the list, False if a newer
    keystroke has superseded it. `key` scopes the coordination file (use the
    window UUID so separate pickers/windows don't interfere)."""
    token = uuid.uuid4().hex
    safe_key = key or "default"
    path = os.path.join(tempfile.gettempdir(), f"icedit_filter_{safe_key}.tok")
    tmp = f"{path}.{token}"
    try:
        with open(tmp, "w") as f:
            f.write(token)
        os.replace(tmp, path)  # atomic publish — readers never see a partial token
    except OSError:
        return True  # can't coordinate — fail open and just rebuild
    time.sleep(delay)
    try:
        with open(path) as f:
            return f.read() == token
    except OSError:
        return True
