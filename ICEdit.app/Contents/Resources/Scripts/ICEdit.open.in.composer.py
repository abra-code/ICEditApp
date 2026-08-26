#!/usr/bin/env python3
"""Open the current icon in Icon Composer.app.
If the working copy has unsaved changes, offer to save first."""

import os
import sys
import subprocess

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.open.in.composer.py ===")

original_path = get_original_icon_path()
if not original_path:
    set_status("Save the icon first before opening in Icon Composer")
    sys.exit(0)

if not ICTOOL:
    set_status("Icon Composer not found")
    sys.exit(0)

# Icon Composer.app path is derived from ictool path
# e.g., /Applications/Icon Composer.app/Contents/Executables/ictool
composer_app = os.path.dirname(os.path.dirname(os.path.dirname(ICTOOL)))
# The derivation assumes ictool sits three levels inside a .app, which every
# path find_icon_composer searches does - but $ICEDIT_ICTOOL can name one
# anywhere, and /usr/local/bin/ictool would derive "/usr". Checked rather than
# handed to open(1), which would fail while the status line below still claimed
# success.
if not composer_app.endswith(".app") or not os.path.isdir(composer_app):
    set_status("Cannot locate Icon Composer.app from %s" % ICTOOL)
    sys.exit(0)

if is_dirty():
    # Ask user to save before opening
    r = subprocess.run([
        ALERT_TOOL,
        "--level", "caution",
        "--title", "Unsaved Changes",
        "--ok", "Save and Open",
        "--cancel", "Open Without Saving",
        "--other", "Cancel",
        "You have unsaved changes. Save before opening in Icon Composer?"
    ], capture_output=False)
    choice = r.returncode

    if choice == 2:
        # Cancel
        sys.exit(0)
    elif choice == 0:
        # Save and Open
        dest = save_icon_to(original_path)
        if dest:
            mark_clean()
            store_original_hash()
            set_status(f"Saved {os.path.basename(dest)}")
        else:
            set_status("Save failed")
            sys.exit(1)
    # choice == 1: Open Without Saving — proceed with stale file on disk

# Checked: open(1) reports a bundle it could not launch, and reporting success
# regardless leaves the user waiting for a window that is not coming.
r = subprocess.run(["open", "-a", composer_app, original_path],
                   capture_output=True, text=True)
if r.returncode != 0:
    err = (r.stderr.strip() or r.stdout.strip() or "open failed")
    log(f"open -a failed: {err}")
    set_status(f"Could not open Icon Composer: {err}")
    sys.exit(1)
set_status(f"Opened in Icon Composer")

log("=== ICEdit.open.in.composer.py done ===")
