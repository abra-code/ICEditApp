#!/usr/bin/env python3
"""ICEdit.open - Open an icon file.

The OMC engine handles OPEN_OBJECT_DIALOG to get the file path and
NEXT_COMMAND_ID=top! to create a new window. This script loads
the selected .icon bundle into the new window."""

import os
import sys
import shutil
import subprocess

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.open.py ===")

icon_path = os.environ.get("OMC_OBJ_PATH", "")
log(f"OMC_OBJ_PATH = '{icon_path}'")
log(f"WINDOW_UUID = '{WINDOW_UUID}'")

if not (icon_path and icon_path.endswith(".icon")
        and os.path.isdir(icon_path)
        and os.path.isfile(os.path.join(icon_path, "icon.json"))):
    if WINDOW_UUID:
        set_status("Not a valid .icon bundle")
    sys.exit(0)

# If no window, we're the no-window path — NEXT_COMMAND_ID=top! will create one
if not WINDOW_UUID:
    log("No window — deferring to NEXT_COMMAND_ID=top!")
    sys.exit(0)

# We have a window — load the file into it
if is_dirty():
    r = subprocess.run([
        ALERT_TOOL,
        "--level", "caution",
        "--title", "Unsaved Changes",
        "--ok", "Discard and Open",
        "--cancel", "Cancel",
        "The current icon has unsaved changes that will be lost."
    ], capture_output=False)
    if r.returncode != 0:
        sys.exit(0)

# Clean up old working copy
old_work = get_icon_path()
if old_work and os.path.exists(old_work):
    shutil.rmtree(old_work, ignore_errors=True)

# Set up new document
pb_set(PB_ORIGINAL_ICON_PATH, icon_path)
work_icon = create_working_copy(icon_path)
pb_set(PB_ICON_PATH, work_icon)
mark_clean()
store_original_hash()

# Refresh UI
icon_data = load_icon_json(work_icon)
if icon_data:
    populate_layer_list(icon_data)

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

    # Hide layer/group panes (no selection)
    show_view(ID_LAYER_PANE, False)
    show_view(ID_GROUP_PANE, False)
    pb_set(PB_SELECTED_LAYER, "")

    render_preview(work_icon)

    basename = os.path.basename(icon_path)
    set_window_title(basename)
    set_status(f"Opened {basename}")
else:
    set_status("Failed to load icon.json")

log("=== ICEdit.open.py done ===")
