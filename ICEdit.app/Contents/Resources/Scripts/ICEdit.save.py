#!/usr/bin/env python3
"""Save the current icon. For existing icons, overwrites the original.
For new icons, chains to ICEdit.save.as which shows a Save As dialog."""

import os
import sys
import subprocess

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.save.py ===")

work_icon = get_icon_path()
if not work_icon:
    set_status("No icon to save")
    sys.exit(0)

original_path = get_original_icon_path()
log(f"work_icon = {work_icon}")
log(f"original_path = '{original_path}'")

if original_path:
    # Existing icon — overwrite the original
    dest = save_icon_to(original_path)
    if dest:
        mark_clean()
        store_original_hash()
        set_status(f"Saved {os.path.basename(dest)}")
    else:
        set_status("Save failed")
else:
    # New icon — chain to ICEdit.save.as for Save As dialog
    log(f"New icon — chaining to ICEdit.save.as guid={CMD_GUID}")
    r = subprocess.run([NEXT_CMD, CMD_GUID, "ICEdit.save.as"], capture_output=True, text=True)
    log(f"omc_next_command result: rc={r.returncode} out={r.stdout.strip()} err={r.stderr.strip()}")

log("=== ICEdit.save.py done ===")
