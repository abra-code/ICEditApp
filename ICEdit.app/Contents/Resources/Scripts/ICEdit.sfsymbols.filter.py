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
    # Split search into terms — a name matches if ANY term appears in it (OR
    # logic), and results are ranked by how many distinct terms match so the
    # best matches bubble to the top. Within the same rank the original
    # (alphabetical) order is preserved by the stable sort.
    terms = search.split()
    scored = []
    for n in all_names:
        rank = sum(1 for t in terms if t in n)
        if rank > 0:
            scored.append((rank, n))
    scored.sort(key=lambda x: -x[0])
    filtered = [n for _, n in scored]
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
