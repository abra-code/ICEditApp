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

# The alert's Cancel slot is wired to "Don't Save", so 1 is the only answer that
# means discard. Everything else is treated as Save: 0 is the user asking for
# it, and 3 (timed out) and 255 (failed to display) mean the question never
# reached them, which must not be read as permission to throw their work away.
DISCARD_RC = 1

# Set when this close has handed the saving off to ICEdit.save.as, which then
# owns the cleanup - omc_next_command queues the request, so that command runs
# after this handler returns rather than alongside it.
handed_off_to_save_as = False

# Set when the user asked to save and the save did not happen. The window is
# going away either way, but the working copy is not released, so the edit is
# still on disk to be recovered.
save_failed = False

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
    
    if r.returncode != DISCARD_RC:
        if original_path:
            # Existing document with unsaved changes
            dest = save_icon_to(original_path)
            if dest:
                log(f"Saved on close: {dest}")
            else:
                # The user asked to save and the save did not happen - a full
                # disk, a read-only volume, a working copy swept from $TMPDIR.
                # Releasing the window here would delete the only copy of work
                # they explicitly asked to keep, so the state is kept instead
                # and they are told where it is. A closing window has nowhere
                # to put a status line, so this has to be an alert.
                log("Save on close failed")
                save_failed = True
                subprocess.run([
                        ALERT_TOOL,
                        "--level", "critical",
                        "--title", "Could Not Save",
                        "--ok", "OK",
                        f"The changes to \u201c{doc_name}\u201d could not be saved, "
                        f"so they have been left in:\n\n{get_icon_path()}"
                ], capture_output=False)
        else:
            # New modified and unsaved document — chain to Save As, let it clean up after
            pb_set(PB_CLOSE_AFTER_SAVE, "1")
            r = subprocess.run([NEXT_CMD, CMD_GUID, "ICEdit.save.as"], capture_output=False)
            # Only if the request was actually queued. If it was not, nobody
            # else is going to clean up, and PB_CLOSE_AFTER_SAVE would stay set
            # for a document that is never saved.
            handed_off_to_save_as = (r.returncode == 0)
    else:
        log("Closing without saving")

# Every path that is not handing off releases the window's state here. It used
# to happen only on the save-an-existing-document branch, so the two commonest
# closes there are - a document with no unsaved changes, and a Don't Save - left
# the working copy directory, both preview PNGs and all the pasteboard keys
# behind until logout.
if not handed_off_to_save_as and not save_failed:
    cleanup_state()

log("=== ICEdit.window.close.py done ===")
