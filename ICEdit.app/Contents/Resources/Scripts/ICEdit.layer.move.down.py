#!/usr/bin/env python3
"""Move the selected layer down (toward bottom of stack)."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

icon_path = get_icon_path()
if not icon_path:
    sys.exit(0)

layer_name = get_selected_layer()
if not layer_name or is_bg_selected() or is_group_selected():
    sys.exit(0)

icon_data = load_icon_json(icon_path)
if not icon_data:
    sys.exit(1)

found = find_layer(icon_data, layer_name)
if not found:
    sys.exit(1)

group_idx, layer_idx, layer = found
gi = group_idx + 1
group = get_group(icon_data, gi)
layer_count = len(group.get("layers", []))

# Already at bottom of group (1-based)
li = layer_idx + 1
if li >= layer_count:
    sys.exit(0)

result = run_icedit("reorder", icon_path, str(li), str(li + 1), "--group", str(gi))
if result.returncode != 0:
    set_status(f"Move failed: {result.stderr.strip()}")
    sys.exit(1)

icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data)
    render_preview(icon_path)
    mark_dirty()
