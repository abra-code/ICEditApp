#!/usr/bin/env python3
"""Handle window activation — detect external changes to the original icon."""

import os
import sys
import subprocess
import shutil

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.window.activated.py ===")

original_path = get_original_icon_path()
if not original_path:
    # New unsaved icon — nothing to check
    sys.exit(0)

original_json = os.path.join(original_path, "icon.json")
if not os.path.isfile(original_json):
    sys.exit(0)

stored_hash = pb_get(PB_ORIGINAL_HASH)
if not stored_hash:
    sys.exit(0)

current_hash = file_hash(original_json)
if stored_hash == current_hash:
    # No external change
    sys.exit(0)

log(f"External change detected: stored={stored_hash[:16]}... current={current_hash[:16]}...")

icon_path = get_icon_path()

if is_dirty():
    # Conflict: local unsaved changes AND external changes
    r = subprocess.run([
        ALERT_TOOL,
        "--level", "caution",
        "--title", "Document Changed Externally",
        "--ok", "Keep My Changes",
        "--cancel", "Reload from Disk",
        "--other", "Cancel",
        "The icon file was modified externally and you have unsaved changes.\n\n"
        "Keep My Changes: your edits are preserved, external changes will be lost on next save.\n"
        "Reload from Disk: discard your edits and load the version from disk."
    ], capture_output=False)
    choice = r.returncode

    if choice == 2:
        # Cancel — do nothing, leave everything as is
        log("User chose Cancel")
        sys.exit(0)
    elif choice == 0:
        # Keep My Changes — just update the stored hash so we don't ask again
        log("User chose Keep My Changes")
        pb_set(PB_ORIGINAL_HASH, current_hash)
        set_status("Keeping local changes (external changes will be overwritten on save)")
        sys.exit(0)
    else:
        # Reload from Disk — replace working copy with the version on disk
        log("User chose Reload from Disk")
        # Fall through to reload below
else:
    log("No local changes — silently reloading")

# Reload: replace working copy from disk
work_dir = os.path.dirname(icon_path)
work_icon_name = os.path.basename(icon_path)
new_work = os.path.join(work_dir, work_icon_name)
if os.path.exists(new_work):
    shutil.rmtree(new_work)
shutil.copytree(original_path, new_work)

mark_clean()
pb_set(PB_ORIGINAL_HASH, current_hash)

# Refresh UI
icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data)

    # Reload background settings
    show_bg_pane()
    bg_type, bg_c1, bg_c2 = parse_fill(icon_data.get("fill"))
    set_value(ID_BG_FILL, bg_type)
    set_value(ID_BG_COLOR1_PICKER, color_to_hex(bg_c1))
    if bg_c2:
        set_value(ID_BG_COLOR2_PICKER, color_to_hex(bg_c2))
    show_view(ID_BG_COLOR1, bg_type in ("solid", "auto-gradient", "gradient"))
    show_view(ID_BG_COLOR2, bg_type == "gradient")
    set_value(ID_BG_COLOR1_LABEL, "Start" if bg_type == "gradient" else "Color")
    set_value(ID_BG_COLOR2_LABEL, "Stop")

    # Hide layer/group panes (selection is lost)
    show_view(ID_LAYER_PANE, False)
    show_view(ID_GROUP_PANE, False)
    pb_set(PB_SELECTED_LAYER, "")

    render_preview(icon_path)
    set_status("Reloaded (changed externally)")

log("=== ICEdit.window.activated.py done ===")
