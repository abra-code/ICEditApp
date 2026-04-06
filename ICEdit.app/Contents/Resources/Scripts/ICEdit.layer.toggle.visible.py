#!/usr/bin/env python3
"""Toggle visibility of a layer or group from the eye button in the table."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.layer.toggle.visible.py ===")

icon_path = get_icon_path()
if not icon_path:
    sys.exit(0)

# Read from pasteboard — survives table selection changes
layer_name = get_selected_layer()
log(f"toggle.visible: layer_name='{layer_name}'")

if not layer_name or is_bg_selected():
    sys.exit(0)

icon_data = load_icon_json(icon_path)
if not icon_data:
    sys.exit(1)

if is_group_selected():
    gi = group_index_from_list(icon_data, layer_name)
    group = get_group(icon_data, gi)
    if not group:
        sys.exit(1)
    hidden = False
    for spec in group.get("hidden-specializations", []):
        if spec.get("idiom") == "square":
            hidden = spec.get("value", False)
            break
    new_hidden = not hidden
    result = run_icedit("hide_group", icon_path, str(gi),
                        "true" if new_hidden else "false")
else:
    found = find_layer(icon_data, layer_name)
    if not found:
        sys.exit(1)
    group_idx, layer_idx, layer = found
    gi = group_idx + 1
    li = layer_idx + 1
    hidden = layer.get("hidden", False)
    new_hidden = not hidden
    result = run_icedit("hide", icon_path, str(li), "--group", str(gi),
                        "true" if new_hidden else "false")

if result.returncode != 0:
    set_status(f"ictool: {result.stderr.strip()}")
    sys.exit(1)

# Refresh table and preview
icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data)
    render_preview(icon_path)
    mark_dirty()
