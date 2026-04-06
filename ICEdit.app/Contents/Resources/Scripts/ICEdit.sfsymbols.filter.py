#!/usr/bin/env python3
"""Filter SF Symbol names based on search text."""

import os
import subprocess
import sys

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")
APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
NAMES_FILE = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg/names.txt")

ID_LIST = 2
ID_STATUS = 3

search = os.environ.get("OMC_ACTIONUI_VIEW_1_VALUE", "").lower().strip()

with open(NAMES_FILE) as f:
    all_names = [line.strip() for line in f if line.strip()]

if search:
    # Split search into terms — all must match (AND logic)
    terms = search.split()
    filtered = [n for n in all_names if all(t in n for t in terms)]
else:
    filtered = all_names

# Update list
data = "\n".join(filtered)
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_LIST), "omc_list_set_items_from_stdin"],
    input=data.encode(), capture_output=True
)

# Update count
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_STATUS), f"{len(filtered)} symbols"],
    capture_output=True
)
