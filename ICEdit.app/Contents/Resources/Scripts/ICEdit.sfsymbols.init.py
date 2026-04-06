#!/usr/bin/env python3
"""Initialize SF Symbols picker — load all symbol names into the list."""

import os
import subprocess
import sys

DEBUG = False
LOG = "/tmp/icedit_debug.log"
def log(msg):
    if DEBUG:
        with open(LOG, "a") as f:
            f.write(msg + "\n")

log("=== ICEdit.sfsymbols.init.py ===")

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")
APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
NAMES_FILE = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg/names.txt")

log(f"WINDOW_UUID={WINDOW_UUID}")
log(f"NAMES_FILE={NAMES_FILE}")
log(f"exists={os.path.isfile(NAMES_FILE)}")
log(f"DIALOG_TOOL={DIALOG_TOOL}")
log(f"exists={os.path.isfile(DIALOG_TOOL)}")

ID_LIST = 2
ID_STATUS = 3

# Load names from file and populate the list
r = subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_LIST), "omc_list_set_items_from_file", NAMES_FILE],
    capture_output=True, text=True
)
log(f"list_set_items: rc={r.returncode} out={r.stdout.strip()} err={r.stderr.strip()}")

# Count and show status
with open(NAMES_FILE) as f:
    count = sum(1 for _ in f)
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_STATUS), f"{count} symbols"],
    capture_output=True
)

# Set default weight to Heavy (renders well as icon layer)
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, "11", "heavy"],
    capture_output=True
)

log("=== ICEdit.sfsymbols.init.py done ===")
