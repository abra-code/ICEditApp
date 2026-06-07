#!/usr/bin/env python3
"""Render selected Material Symbol to SVG and display preview."""

import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_material import GLYPHSVG, MATERIAL_DIR, MATERIAL_STYLE_ARG

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

ID_PREVIEW = 10
ID_STATUS = 3

# Get selected symbol name from the list
symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
if not symbol:
    sys.exit(0)

# Get weight and fill
weight = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "regular") or "regular"
fill = os.environ.get("OMC_ACTIONUI_VIEW_12_VALUE", "").strip().lower() in ("1", "true", "yes", "on")

# Render SVG via glyphsvg in Material mode
svg_path = f"/tmp/icedit_matsymbol_{WINDOW_UUID}.svg"
cmd = [GLYPHSVG, f"--material={MATERIAL_STYLE_ARG}", symbol, weight, "768"]
if fill:
    cmd.append("--fill")
cmd.append(f"--output={svg_path}")

env = dict(os.environ, GLYPHSVG_MATERIAL_DIR=MATERIAL_DIR)
result = subprocess.run(cmd, capture_output=True, text=True, env=env)

if result.returncode != 0:
    err = result.stderr.strip() or result.stdout.strip()
    subprocess.run(
        [DIALOG_TOOL, WINDOW_UUID, str(ID_STATUS), f"Error: {err}"],
        capture_output=True
    )
    sys.exit(0)

# Update preview image
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_PREVIEW), svg_path],
    capture_output=True
)
