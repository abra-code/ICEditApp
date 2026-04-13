#!/usr/bin/env python3
"""Handle image files dropped onto the layer table.

Reads OMC_ACTIONUI_TRIGGER_CONTEXT as {"items": [String], "location": {...}}
and adds each recognized image/SVG file as a new topmost layer.
icedit add_image / add_svg always inserts at position 0 (topmost), so no
reordering is needed after adding.
"""

import os
import sys
import json

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

# print_env()

icon_path = get_icon_path()
if not icon_path:
    set_status("No icon loaded")
    sys.exit(0)

context_json = os.environ.get("OMC_ACTIONUI_TRIGGER_CONTEXT", "")
if not context_json:
    sys.exit(0)

try:
    context = json.loads(context_json)
except (ValueError, TypeError):
    sys.exit(0)

items = context.get("items", [])
if not items:
    sys.exit(0)

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".tiff", ".tif",
              ".bmp", ".heic", ".webp", ".svg"}

image_files = [
    item for item in items
    if os.path.splitext(item)[1].lower() in IMAGE_EXTS and os.path.isfile(item)
]

if not image_files:
    sys.exit(0)

log(f"=== ICEdit.layer.drop.py ===")
log(f"Dropped files: {image_files}")

added = []
failed = []
for file_path in image_files:
    ext = os.path.splitext(file_path)[1].lower()
    cmd = "add_svg" if ext == ".svg" else "add_image"
    result = run_icedit(cmd, icon_path, file_path, "--auto-scale")
    if result.returncode != 0:
        failed.append(os.path.basename(file_path))
        log(f"Failed to add {file_path}: {result.stderr.strip()}")
        continue
    out = result.stdout.strip()
    layer_name = out.split("'")[1] if "'" in out else os.path.splitext(os.path.basename(file_path))[0]
    added.append(layer_name)

icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data)
    render_preview(icon_path)
    mark_dirty()

if added and not failed:
    set_status(f"Added {len(added)} layer{'s' if len(added) > 1 else ''}: {', '.join(added)}")
elif added:
    set_status(f"Added {len(added)}, failed {len(failed)}: {', '.join(failed)}")
else:
    set_status(f"Failed to add: {', '.join(failed)}")

log("=== ICEdit.layer.drop.py done ===")
