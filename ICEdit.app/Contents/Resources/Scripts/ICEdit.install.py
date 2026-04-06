#!/usr/bin/env python3
"""Install the current icon into a chosen .app bundle.
Compiles the .icon to Assets.car and .icns with actool, copies them into
the app's Resources, and updates CFBundleIconFile / CFBundleIconName in Info.plist."""

import os
import sys
import subprocess
import shutil
import tempfile

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.install.py ===")

app_path = os.environ.get("OMC_DLG_CHOOSE_OBJECT_PATH", "").strip()
log(f"OMC_DLG_CHOOSE_OBJECT_PATH = '{app_path}'")

if not app_path:
    set_status("Install cancelled")
    sys.exit(0)

if not app_path.endswith(".app") or not os.path.isdir(app_path):
    app_name = os.path.basename(app_path) or app_path
    subprocess.run([
        ALERT_TOOL,
        "--level", "critical",
        "--title", "Not an App Bundle",
        "--ok", "OK",
        f"\u201c{app_name}\u201d is not a .app bundle. Installation cannot be performed."
    ], capture_output=False)
    set_status("Install failed: not a .app bundle")
    sys.exit(1)

icon_path = get_icon_path()
if not icon_path:
    set_status("No icon to install")
    sys.exit(1)

if not ACTOOL:
    subprocess.run([
        ALERT_TOOL,
        "--level", "critical",
        "--title", "Xcode Not Found",
        "--ok", "OK",
        "actool is required to compile icons but was not found. Please install Xcode from the App Store."
    ], capture_output=False)
    set_status("Install failed: Xcode (actool) not installed")
    sys.exit(1)

resources_dir = os.path.join(app_path, "Contents", "Resources")
info_plist = os.path.join(app_path, "Contents", "Info.plist")

if not os.path.isdir(resources_dir):
    set_status(f"No Contents/Resources in {os.path.basename(app_path)}")
    sys.exit(1)

if not os.path.isfile(info_plist):
    set_status(f"No Info.plist in {os.path.basename(app_path)}")
    sys.exit(1)

icon_base = os.path.splitext(os.path.basename(icon_path))[0]
app_name = os.path.splitext(os.path.basename(app_path))[0]

# Read the app's current icon name from Info.plist so we can check for its .icns
old_icon_name = ""
try:
    r = subprocess.run(
        ["plutil", "-extract", "CFBundleIconFile", "raw", "-o", "-", info_plist],
        capture_output=True, text=True
    )
    if r.returncode == 0:
        old_icon_name = r.stdout.strip()
except OSError:
    pass

# Check which files already exist in the app and warn before overwriting
existing = []
if os.path.isfile(os.path.join(resources_dir, "Assets.car")):
    existing.append("Assets.car")
if old_icon_name and os.path.isfile(os.path.join(resources_dir, f"{old_icon_name}.icns")):
    existing.append(f"{old_icon_name}.icns")

if existing:
    files_list = " and ".join(f"\u201c{f}\u201d" for f in existing)
    r = subprocess.run([
        ALERT_TOOL,
        "--level", "caution",
        "--title", "Replace Existing Files?",
        "--ok", "Replace",
        "--cancel", "Cancel",
        f"{files_list} will replace the existing resources in {app_name}."
    ], capture_output=False)
    if r.returncode != 0:
        set_status("Install cancelled")
        sys.exit(0)

log(f"Installing icon '{icon_base}' into '{app_name}'")

temp_dir = tempfile.mkdtemp(prefix="icedit_install_")
try:
    partial_plist = os.path.join(temp_dir, "partial.plist")

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

    installed = []

    car_src = os.path.join(temp_dir, "Assets.car")
    if os.path.isfile(car_src):
        shutil.copy2(car_src, os.path.join(resources_dir, "Assets.car"))
        installed.append("Assets.car")

    icns_src = os.path.join(temp_dir, f"{icon_base}.icns")
    if os.path.isfile(icns_src):
        shutil.copy2(icns_src, os.path.join(resources_dir, f"{icon_base}.icns"))
        installed.append(f"{icon_base}.icns")

        # Remove old .icns if it differs from the new one
        if old_icon_name and old_icon_name != icon_base:
            old_icns = os.path.join(resources_dir, f"{old_icon_name}.icns")
            if os.path.isfile(old_icns):
                os.remove(old_icns)
                log(f"Removed old icon: {old_icns}")

    if not installed:
        set_status("actool produced no output files")
        sys.exit(1)

    # Update Info.plist
    subprocess.run(
        ["plutil", "-replace", "CFBundleIconFile", "-string", icon_base, info_plist],
        capture_output=True
    )
    subprocess.run(
        ["plutil", "-replace", "CFBundleIconName", "-string", icon_base, info_plist],
        capture_output=True
    )
    log(f"Updated CFBundleIconFile and CFBundleIconName to '{icon_base}'")

    # Touch the app bundle to invalidate the icon cache
    subprocess.run(["touch", app_path], capture_output=True)

    set_status(f"Installed into {app_name}: {', '.join(installed)}")

finally:
    shutil.rmtree(temp_dir, ignore_errors=True)

log("=== ICEdit.install.py done ===")
