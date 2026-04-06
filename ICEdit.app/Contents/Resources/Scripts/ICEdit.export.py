#!/usr/bin/env python3
"""Export the current icon to Assets.car, .icns, and partial Info.plist
in a '{name}-Exported' subdirectory of the user-chosen folder."""

import os
import sys
import subprocess
import shutil
import tempfile

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.export.py ===")

dest_dir = os.environ.get("OMC_DLG_CHOOSE_FOLDER_PATH", "").strip()
log(f"OMC_DLG_CHOOSE_FOLDER_PATH = '{dest_dir}'")

if not dest_dir:
    set_status("Export cancelled")
    sys.exit(0)

icon_path = get_icon_path()
if not icon_path:
    set_status("No icon to export")
    sys.exit(1)

if not ACTOOL:
    subprocess.run([
        ALERT_TOOL,
        "--level", "critical",
        "--title", "Xcode Not Found",
        "--ok", "OK",
        "actool is required for export but was not found. Please install Xcode from the App Store."
    ], capture_output=False)
    set_status("Export failed: Xcode (actool) not installed")
    sys.exit(1)

icon_base = os.path.splitext(os.path.basename(icon_path))[0] or "Untitled"
export_dir = os.path.join(dest_dir, f"{icon_base}-Exported")
os.makedirs(export_dir, exist_ok=True)
log(f"Exporting '{icon_base}' to '{export_dir}'")

partial_plist = os.path.join(export_dir, "partial-Info.plist")

temp_dir = tempfile.mkdtemp(prefix="icedit_export_")
try:
    result = subprocess.run([
        ACTOOL, icon_path,
        "--compile", temp_dir,
        "--app-icon", icon_base,
        "--platform", "macosx",
        "--target-device", "mac",
        "--output-format", "human-readable-text",
        "--minimum-deployment-target", "14.6",
        "--output-partial-info-plist", partial_plist,
    ], capture_output=True, text=True)

    log(f"actool stdout: {result.stdout.strip()}")
    log(f"actool stderr: {result.stderr.strip()}")

    if result.returncode != 0:
        set_status(f"actool failed: {result.stderr.strip()[:80]}")
        sys.exit(1)

    exported = []

    car_src = os.path.join(temp_dir, "Assets.car")
    if os.path.isfile(car_src):
        shutil.copy2(car_src, os.path.join(export_dir, "Assets.car"))
        exported.append("Assets.car")

    icns_src = os.path.join(temp_dir, f"{icon_base}.icns")
    if os.path.isfile(icns_src):
        shutil.copy2(icns_src, os.path.join(export_dir, f"{icon_base}.icns"))
        exported.append(f"{icon_base}.icns")

    if os.path.isfile(partial_plist):
        exported.append("partial-Info.plist")

    if exported:
        set_status(f"Exported to {icon_base}-Exported: {', '.join(exported)}")
    else:
        set_status("actool produced no output files")
        sys.exit(1)

finally:
    shutil.rmtree(temp_dir, ignore_errors=True)

log("=== ICEdit.export.py done ===")
