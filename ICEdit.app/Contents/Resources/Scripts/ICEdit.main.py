#!/usr/bin/env python3
"""ICEdit main script - handles app launch and icon file opening."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.main.py ===")
log(f"OMC_OBJ_PATH = {os.environ.get('OMC_OBJ_PATH', '<not set>')}")
log(f"OMC_ACTIONUI_WINDOW_UUID = {os.environ.get('OMC_ACTIONUI_WINDOW_UUID', '<not set>')}")
log(f"WINDOW_UUID = {WINDOW_UUID}")

icon_path = os.environ.get("OMC_OBJ_PATH", "")
log(f"icon_path = '{icon_path}'")

# Check if a .icon bundle was dropped/opened
if (icon_path and icon_path.endswith(".icon")
        and os.path.isdir(icon_path)
        and os.path.isfile(os.path.join(icon_path, "icon.json"))):
    log("Valid .icon bundle detected — creating working copy")
    pb_set(PB_ORIGINAL_ICON_PATH, icon_path)
    work_icon = create_working_copy(icon_path)
    pb_set(PB_ICON_PATH, work_icon)
    mark_clean()
    store_original_hash()
    log(f"Working copy: {work_icon}")
else:
    log("No valid .icon — creating new icon")
    pb_set(PB_ORIGINAL_ICON_PATH, "")
    work_icon = create_new_icon()
    pb_set(PB_ICON_PATH, work_icon)
    log(f"New icon: {work_icon}")

icon_data = load_icon_json(work_icon)
if icon_data:
    log(f"icon.json loaded, keys: {list(icon_data.keys())}")
    layers = get_layers(icon_data)
    log(f"Layers: {layers}")
    populate_layer_list(icon_data)

    # Show background pane with initial values
#     show_bg_pane()
#     bg_type, bg_c1, bg_c2 = parse_fill(icon_data.get("fill"))
#     log(f"Background fill: type={bg_type}, c1={bg_c1}, c2={bg_c2}")
#     set_value(ID_BG_FILL, bg_type)
#     set_value(ID_BG_COLOR1_PICKER, color_to_hex(bg_c1))
#     if bg_c2:
#         set_value(ID_BG_COLOR2_PICKER, color_to_hex(bg_c2))
#     show_view(ID_BG_COLOR1, bg_type in ("solid", "auto-gradient", "gradient"))
#     show_view(ID_BG_COLOR2, bg_type == "gradient")
#     set_value(ID_BG_COLOR1_LABEL, "Start" if bg_type == "gradient" else "Color")
#     set_value(ID_BG_COLOR2_LABEL, "Stop")

    # Render preview
    log("Rendering preview...")
    result = render_preview(work_icon)
    log(f"Render result: {result}")

    original = get_original_icon_path()
    if original:
        basename = os.path.basename(original)
        set_window_title(basename)
        set_status(f"Loaded {basename}")
    else:
        set_window_title("Untitled")
        set_status("New icon")
else:
    log("Failed to load icon.json")
    set_status("Failed to load icon.json")

log("=== ICEdit.main.py done ===")
