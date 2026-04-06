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

subprocess.run(["open", "-a", composer_app, original_path])
set_status(f"Opened in Icon Composer")

log("=== ICEdit.open.in.composer.py done ===")
