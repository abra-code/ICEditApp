#!/usr/bin/env python3
"""Save As — invoked after OMC's Save As dialog provides the path."""

import os
import sys
import subprocess

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.save.as.py ===")

dest_path = os.environ.get("OMC_DLG_SAVE_AS_PATH", "")
log(f"OMC_DLG_SAVE_AS_PATH = '{dest_path}'")

closing = pb_get(PB_CLOSE_AFTER_SAVE) == "1"

if not dest_path:
    log("Save As cancelled")
    if closing:
        cleanup_state()
    else:
        set_status("Save cancelled")
    sys.exit(0)

dest = save_icon_to(dest_path)
if dest:
    if closing:
        cleanup_state()
    else:
        # Normal Save As — remember the original path and update UI
        pb_set(PB_ORIGINAL_ICON_PATH, dest)
        mark_clean()
        store_original_hash()
        subprocess.run([DIALOG_TOOL, WINDOW_UUID, "omc_window", "omc_invoke",
                        "setTitleWithRepresentedFilename:", dest],
                       capture_output=True)
        set_status(f"Saved {os.path.basename(dest)}")
else:
    if closing:
        cleanup_state()
    else:
        set_status("Save failed")

log("=== ICEdit.save.as.py done ===")
