#!/usr/bin/env python3
"""Clean up temp files and state when an ICEdit window closes.
If the document has unsaved changes, offer to save first."""

import os
import sys
import subprocess

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.window.close.py ===")

if is_dirty():
    original_path = get_original_icon_path()
    if original_path:
       doc_name = os.path.basename(original_path)
    else:
       doc_name = "Untitled"
    
    r = subprocess.run([
            ALERT_TOOL,
            "--level", "caution",
            "--title", "Unsaved Changes",
            "--ok", "Save",
            "--cancel", "Don\u2019t Save",
            f"Do you want to save changes to \u201c{doc_name}\u201d?"
    ], capture_output=False)
    
    if r.returncode == 0:
        if original_path:
            # Existing document with unsaved changes
            dest = save_icon_to(original_path)
            if dest:
                log(f"Saved on close: {dest}")
            else:
                log("Save on close failed")
            cleanup_state()
        else:
            # New modified and unsaved document — chain to Save As, let it clean up after
            pb_set(PB_CLOSE_AFTER_SAVE, "1")
            r = subprocess.run([NEXT_CMD, CMD_GUID, "ICEdit.save.as"], capture_output=False)

log("=== ICEdit.window.close.py done ===")
