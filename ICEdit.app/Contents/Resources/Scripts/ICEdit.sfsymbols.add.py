#!/usr/bin/env python3
"""Add the selected SF Symbol as a layer to the current icon."""

import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.sfsymbols.add.py ===")

SFSYMBOLS_UUID = WINDOW_UUID  # this dialog's own UUID

# Get selected symbol name
symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
if not symbol:
    subprocess.run(
        [DIALOG_TOOL, SFSYMBOLS_UUID, "3", "No symbol selected"],
        capture_output=True
    )
    sys.exit(0)

svg_path = f"/tmp/icedit_sfsymbol_{SFSYMBOLS_UUID}.svg"
if not os.path.isfile(svg_path):
    subprocess.run(
        [DIALOG_TOOL, SFSYMBOLS_UUID, "3", "No SVG rendered — select a symbol first"],
        capture_output=True
    )
    sys.exit(0)

# Get icon path from the parent ICEdit window
icon_path = pb_get(PB_ICON_PATH)
if not icon_path:
    subprocess.run(
        [DIALOG_TOOL, SFSYMBOLS_UUID, "3", "No icon open in ICEdit"],
        capture_output=True
    )
    sys.exit(0)

# Add the SVG as a layer using icedit
result = run_icedit("add_svg", icon_path, svg_path, symbol, "--auto-scale")
if result.returncode != 0:
    subprocess.run(
        [DIALOG_TOOL, SFSYMBOLS_UUID, "3", f"Failed: {result.stderr.strip()[:80]}"],
        capture_output=True
    )
    sys.exit(1)

# Refresh ICEdit main window — target parent document window
icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data, target=DOCUMENT_UUID)
    render_preview(icon_path, target_uuid=DOCUMENT_UUID)

mark_dirty()

subprocess.run(
    [DIALOG_TOOL, SFSYMBOLS_UUID, "3", f"Added '{symbol}' as layer"],
    capture_output=True
)

log("=== ICEdit.sfsymbols.add.py done ===")
