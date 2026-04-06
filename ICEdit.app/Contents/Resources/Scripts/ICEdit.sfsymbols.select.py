#!/usr/bin/env python3
"""Render selected SF Symbol to SVG and display preview."""

import os
import subprocess
import sys
import time

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")
APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
GLYPHSVG = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg/glyphsvg")

ID_PREVIEW = 10
ID_STATUS = 3

# Get selected symbol name from the list
symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
if not symbol:
    sys.exit(0)

# Get weight
weight = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "regular") or "regular"

# Render SVG
svg_path = f"/tmp/icedit_sfsymbol_{WINDOW_UUID}.svg"
result = subprocess.run(
    [GLYPHSVG, symbol, weight, "768", f"--output={svg_path}"],
    capture_output=True, text=True
)

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
