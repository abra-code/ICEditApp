#!/usr/bin/env python3
"""Initialize Material Symbols picker — load all symbol names into the list."""

import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_material import load_names, CODEPOINTS_FILE

DEBUG = False
LOG = os.environ.get("TMPDIR", "/tmp").rstrip("/") + "/icedit_debug.log"
def log(msg):
    if DEBUG:
        with open(LOG, "a") as f:
            f.write(msg + "\n")

log("=== ICEdit.materialsymbols.init.py ===")

SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

ID_LIST = 2
ID_STATUS = 3
ID_WEIGHT = 11

log(f"CODEPOINTS_FILE={CODEPOINTS_FILE} exists={os.path.isfile(CODEPOINTS_FILE)}")

names = load_names()

if not names:
    subprocess.run(
        [DIALOG_TOOL, WINDOW_UUID, str(ID_STATUS),
         "Material Symbols not installed — run download_material_symbols.sh"],
        capture_output=True
    )
    log("=== no names — data not installed ===")
    sys.exit(0)

# Populate the list
data = "\n".join(names)
r = subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_LIST), "omc_list_set_items_from_stdin"],
    input=data.encode(), capture_output=True
)
log(f"list_set_items: rc={r.returncode}")

# Count and show status
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_STATUS), f"{len(names)} symbols"],
    capture_output=True
)

# Default weight to Bold (heaviest available — renders well as icon layer)
subprocess.run(
    [DIALOG_TOOL, WINDOW_UUID, str(ID_WEIGHT), "bold"],
    capture_output=True
)

log("=== ICEdit.materialsymbols.init.py done ===")
