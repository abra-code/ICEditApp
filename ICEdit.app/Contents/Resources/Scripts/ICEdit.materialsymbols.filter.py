#!/usr/bin/env python3
"""Filter Material Symbol names by search text (matches name, tags, categories)."""

import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_material import load_names, load_search_index, filter_names

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

ID_LIST = 2
ID_STATUS = 3

search = os.environ.get("OMC_ACTIONUI_VIEW_1_VALUE", "")

names = load_names()
search_index = load_search_index()
filtered = filter_names(names, search_index, search)

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
