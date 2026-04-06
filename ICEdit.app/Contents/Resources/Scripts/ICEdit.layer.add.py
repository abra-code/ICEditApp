#!/usr/bin/env python3
"""Add a new layer from the chosen file (SVG or image)."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

icon_path = get_icon_path()
if not icon_path:
    set_status("No icon loaded")
    sys.exit(0)

file_path = os.environ.get("OMC_DLG_CHOOSE_FILE_PATH", "")
if not file_path or not os.path.isfile(file_path):
    sys.exit(0)

log(f"=== ICEdit.layer.add.py ===")
log(f"Adding layer from: {file_path}")

ext = os.path.splitext(file_path)[1].lower()
cmd = "add_svg" if ext == ".svg" else "add_image"

result = run_icedit(cmd, icon_path, file_path, "--auto-scale")
if result.returncode != 0:
    set_status(f"Add layer failed: {result.stderr.strip()[:80]}")
    sys.exit(1)

# Extract layer name from output (e.g. "Added SVG layer 'name' to ...")
layer_name = ""
out = result.stdout.strip()
if "'" in out:
    layer_name = out.split("'")[1]

# Refresh UI
icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data)
    render_preview(icon_path)
    mark_dirty()
    set_status(f"Added layer '{layer_name}'")

log("=== ICEdit.layer.add.py done ===")
