#!/usr/bin/env python3
"""Remove the selected layer from the icon."""

# echo "[$0]"
# import os; print(sorted(os.environ.items()))

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.layer.remove.py ===")

icon_path = get_icon_path()
log(f"icon_path = '{icon_path}'")
if not icon_path:
    sys.exit(0)

layer_name = get_selected_layer()
if not layer_name or is_bg_selected() or is_group_selected():
    set_status("Cannot remove this item")
    sys.exit(0)

icon_data = load_icon_json(icon_path)
if not icon_data:
    sys.exit(1)

# Find layer to get group and layer indices (1-based for icedit)
result = find_layer(icon_data, layer_name)
if not result:
    set_status(f"Layer '{layer_name}' not found")
    sys.exit(1)

group_idx, layer_idx, layer = result
gi = group_idx + 1
li = layer_idx + 1

result = run_icedit("remove", icon_path, str(li), "--group", str(gi))
if result.returncode != 0:
    set_status(f"Remove failed: {result.stderr.strip()[:80]}")
    sys.exit(1)

# Refresh UI
pb_set(PB_SELECTED_LAYER, "")
icon_data = load_icon_json(icon_path)
populate_layer_list(icon_data)

# Hide settings panes (no layer selected)
show_view(ID_LAYER_PANE, False)
show_view(ID_GROUP_PANE, False)

# Re-render preview
render_preview(icon_path)
mark_dirty()
set_status(f"Removed layer '{layer_name}'")
