"""Shared helpers for ICEdit OMC scripts."""

import os
import sys
import json
import subprocess

# OMC environment
SUPPORT_PATH = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")
PARENT_UUID = os.environ.get("OMC_PARENT_DIALOG_GUID", "")
CMD_GUID = os.environ.get("OMC_CURRENT_COMMAND_GUID", "")

# The document window UUID — parent if running in a child dialog, else self
DOCUMENT_UUID = PARENT_UUID or WINDOW_UUID

DIALOG_TOOL = os.path.join(SUPPORT_PATH, "omc_dialog_control")
NEXT_CMD = os.path.join(SUPPORT_PATH, "omc_next_command")
PASTEBOARD_TOOL = os.path.join(SUPPORT_PATH, "pasteboard")
PYTHON3 = os.path.join(APP_BUNDLE, "Contents/Library/Python/bin/python3")

def find_icon_composer():
    """Find Icon Composer.app in common locations."""
    search_paths = [
        "/Applications/Icon Composer.app",
        "/Applications/Xcode.app/Contents/Applications/Icon Composer.app",
    ]
    # Try xcode-select to find the active Xcode installation
    try:
        r = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
        if r.returncode == 0:
            dev_path = r.stdout.strip()
            # Strip trailing /Developer to get Xcode.app/Contents
            if dev_path.endswith("/Developer"):
                xcode_contents = dev_path[:-len("/Developer")]
                search_paths.append(
                    os.path.join(xcode_contents, "Applications/Icon Composer.app"))
    except (OSError, FileNotFoundError):
        pass
    for path in search_paths:
        ictool = os.path.join(path, "Contents/Executables/ictool")
        if os.path.isfile(ictool):
            return ictool
    return None


ICTOOL = find_icon_composer()


def find_actool():
    """Return the path to actool via xcrun, or None if Xcode is not installed."""
    try:
        r = subprocess.run(["xcrun", "-find", "actool"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            path = r.stdout.strip()
            if path and os.path.isfile(path):
                return path
    except (OSError, FileNotFoundError):
        pass
    return None


ACTOOL = find_actool()
HELPERS_DIR = os.path.join(APP_BUNDLE, "Contents/Helpers")
ICEDIT_TOOL = os.path.join(HELPERS_DIR, "icedit", "icedit")

# Pasteboard keys (keyed by document window UUID so child dialogs share state)
PB_ICON_PATH = f"icedit_icon_path_{DOCUMENT_UUID}"           # working copy (temp)
PB_ORIGINAL_ICON_PATH = f"icedit_original_path_{DOCUMENT_UUID}"  # original on disk (empty for new)
PB_SELECTED_LAYER = f"icedit_selected_layer_{DOCUMENT_UUID}"
PB_SELECTED_TYPE = f"icedit_selected_type_{DOCUMENT_UUID}"    # TYPE_LAYER, TYPE_GROUP, or TYPE_BG
PB_DIRTY = f"icedit_dirty_{DOCUMENT_UUID}"                    # "1" if working copy has unsaved changes
PB_ORIGINAL_HASH = f"icedit_original_hash_{DOCUMENT_UUID}"    # SHA-256 of original file's icon.json at load/save time
PB_CLOSE_AFTER_SAVE = f"icedit_close_after_save_{DOCUMENT_UUID}"  # "1" if save.as was triggered from window close

# View IDs
ID_LAYER_LIST = 100
ID_BTN_ADD = 101
ID_BTN_REMOVE = 102
ID_PREVIEW = 200
ID_STATUS = 399
ID_BG_FILL = 301
ID_BG_COLOR1 = 302          # HStack wrapper (show/hide)
ID_BG_COLOR1_PICKER = 3020  # actual ColorPicker (set/get value)
ID_BG_COLOR1_LABEL = 3021   # Text label
ID_BG_COLOR2 = 303          # HStack wrapper (show/hide)
ID_BG_COLOR2_PICKER = 3030  # actual ColorPicker (set/get value)
ID_BG_COLOR2_LABEL = 3031   # Text label
ID_LAYER_FILL = 311
ID_LAYER_COLOR1 = 312        # HStack wrapper (show/hide)
ID_LAYER_COLOR1_PICKER = 3120  # actual ColorPicker (set/get value)
ID_LAYER_COLOR1_LABEL = 3121  # Text label
ID_LAYER_COLOR2 = 313        # HStack wrapper (show/hide)
ID_LAYER_COLOR2_PICKER = 3130  # actual ColorPicker (set/get value)
ID_LAYER_COLOR2_LABEL = 3131  # Text label
ID_LAYER_SCALE = 314
ID_LAYER_SHIFT_X = 315
ID_LAYER_SHIFT_Y = 316
ID_LAYER_GLASS = 317
ID_LAYER_BLEND = 318
ID_LAYER_VISIBLE = 319
ID_LAYER_NAME = 320

# Group controls
ID_GROUP_NAME = 333
ID_GROUP_OPACITY = 334
ID_GROUP_BLEND = 335
ID_GROUP_BLUR = 336
ID_GROUP_LIGHTING = 337
ID_GROUP_SPECULAR = 338
ID_GROUP_VISIBLE = 339
ID_GROUP_SCALE = 340
ID_GROUP_SHIFT_X = 341
ID_GROUP_SHIFT_Y = 342
ID_GROUP_TRANSLUCENCY = 330
ID_GROUP_SHADOW = 331
ID_GROUP_SHADOW_OPACITY = 332

# Pane container IDs
ID_BG_PANE = 500
ID_LAYER_PANE = 501
ID_GROUP_PANE = 502

DEBUG = False

LOG = "/tmp/icedit_debug.log"
def log(msg):
    if DEBUG:
        with open(LOG, "a") as f:
            f.write(msg + "\n")


def set_value(view_id, value, target=None):
    """Set a view's value via omc_dialog_control."""
    t = target or WINDOW_UUID
    r = subprocess.run([DIALOG_TOOL, t, str(view_id), str(value)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        log(f"set_value({view_id}) FAILED rc={r.returncode} err={r.stderr.strip()}")


def set_property(view_id, prop, value, target=None):
    """Set a view property via omc_dialog_control."""
    t = target or WINDOW_UUID
    subprocess.run([DIALOG_TOOL, t, str(view_id), "omc_set_property", prop, str(value)],
                   capture_output=True)


def enable_view(view_id, enabled=True, target=None):
    """Enable or disable a view."""
    t = target or WINDOW_UUID
    cmd = "omc_enable" if enabled else "omc_disable"
    subprocess.run([DIALOG_TOOL, t, str(view_id), cmd],
                   capture_output=True)


def show_view(view_id, visible=True, target=None):
    """Show or hide a view."""
    t = target or WINDOW_UUID
    cmd = "omc_show" if visible else "omc_hide"
    subprocess.run([DIALOG_TOOL, t, str(view_id), cmd],
                   capture_output=True)


def show_bg_pane():
    """Show background settings, hide others."""
    show_view(ID_BG_PANE, True)
    show_view(ID_LAYER_PANE, False)
    show_view(ID_GROUP_PANE, False)


def show_layer_pane():
    """Show layer settings, hide others."""
    show_view(ID_BG_PANE, False)
    show_view(ID_LAYER_PANE, True)
    show_view(ID_GROUP_PANE, False)


def show_group_pane():
    """Show group settings, hide others."""
    show_view(ID_BG_PANE, False)
    show_view(ID_LAYER_PANE, False)
    show_view(ID_GROUP_PANE, True)


def set_state(view_id, key, value, target=None):
    """Set an ActionUI view state via omc_set_state."""
    t = target or WINDOW_UUID
    cmd = [DIALOG_TOOL, t, str(view_id), "omc_set_state", key, value]
    log(f"set_state: {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    log(f"set_state result: rc={r.returncode} out={r.stdout.strip()} err={r.stderr.strip()}")


def set_table_rows(view_id, rows, target=None):
    """Set ActionUI Table rows via omc_table_set_rows_from_stdin.
    Each row is a list of column values, joined by tabs.
    Uses omc_table_set_rows (replaces content) to preserve selection."""
    t = target or WINDOW_UUID
    data = "\n".join("\t".join(str(c) for c in row) for row in rows)
    log(f"set_table_rows({view_id}): {len(rows)} rows")
    r = subprocess.run([DIALOG_TOOL, t, str(view_id), "omc_table_set_rows_from_stdin"],
                       input=data.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log(f"set_table_rows result: rc={r.returncode}")


def pb_get(key):
    """Get a pasteboard value."""
    result = subprocess.run([PASTEBOARD_TOOL, key, "get"],
                           capture_output=True, text=True)
    return result.stdout.strip()


def pb_set(key, value):
    """Set a pasteboard value."""
    subprocess.run([PASTEBOARD_TOOL, key, "set", value],
                   capture_output=True)


def get_env_value(view_id):
    """Get a view's current value from environment."""
    return os.environ.get(f"OMC_ACTIONUI_VIEW_{view_id}_VALUE", "")


def get_table_value(view_id, column=1):
    """Get a table/list selected row column value from environment."""
    return os.environ.get(f"OMC_ACTIONUI_TABLE_{view_id}_COLUMN_{column}_VALUE", "")


def set_window_title(title):
    """Set the window title dynamically."""
    set_value("omc_window", title)


def set_status(msg):
    """Set the status label text."""
    set_value(ID_STATUS, msg)


def load_icon_json(icon_path):
    """Load and parse an icon's icon.json file."""
    json_path = os.path.join(icon_path, "icon.json")
    if not os.path.isfile(json_path):
        return None
    with open(json_path) as f:
        return json.load(f)


def get_icon_path():
    """Get the current icon path from pasteboard."""
    return pb_get(PB_ICON_PATH)


def get_selected_layer():
    """Get the currently selected layer name from pasteboard."""
    return pb_get(PB_SELECTED_LAYER)


def get_selected_type():
    """Get the type of the currently selected row from pasteboard."""
    return pb_get(PB_SELECTED_TYPE)


def is_group_selected():
    """Check if the currently selected row is a group."""
    return get_selected_type() == TYPE_GROUP


def is_bg_selected():
    """Check if the currently selected row is the background."""
    return get_selected_type() == TYPE_BG


# SF Symbol names for table type/visibility columns
TYPE_LAYER = "top-layer-small.png"
TYPE_GROUP = "folder"
TYPE_BG = "layer-small.png"
VIS_ON = "eye"
VIS_OFF = "eye.slash"


def get_layer_rows(icon_data):
    """Build table rows for the layer hierarchy.
    Returns list of [indent, type_symbol, name, visibility_symbol] rows.
    Layers get an indent column; groups and background do not."""
    rows = []
    if icon_data and "groups" in icon_data:
        for group in icon_data["groups"]:
            for layer in group.get("layers", []):
                name = layer.get("name", "unnamed")
                hidden = layer.get("hidden", False)
                rows.append(["", TYPE_LAYER, name, VIS_OFF if hidden else VIS_ON])
            group_name = group.get("name", "") or "Group"
            g_hidden = False
            for spec in group.get("hidden-specializations", []):
                if spec.get("idiom") == "square":
                    g_hidden = spec.get("value", False)
                    break
            rows.append([TYPE_GROUP, "", group_name, VIS_OFF if g_hidden else VIS_ON])
    rows.append([TYPE_BG, "", "Background", ""])
    return rows


def get_layers(icon_data):
    """Extract layer/group names from icon data (for compatibility).
    Returns flat list of names from column 3 of get_layer_rows."""
    return [row[2] for row in get_layer_rows(icon_data)]

def group_index_from_list(icon_data, list_item_name):
    """Get the 1-based group index for a group list item."""
    if not icon_data or "groups" not in icon_data:
        return 1

    for i, group in enumerate(icon_data["groups"]):
        shown = group.get("name", "") or "Group"
        if shown == list_item_name:
            return i + 1
    return 1


def find_layer(icon_data, layer_name):
    """Find a layer dict by name. Returns (group_index, layer_index, layer_dict) or None."""
    if not icon_data or "groups" not in icon_data:
        return None
    for gi, group in enumerate(icon_data["groups"]):
        for li, layer in enumerate(group.get("layers", [])):
            if layer.get("name") == layer_name:
                return (gi, li, layer)
    return None


def get_group(icon_data, group_index=1):
    """Get a group dict by 1-based index."""
    if not icon_data or "groups" not in icon_data:
        return None
    groups = icon_data["groups"]
    idx = group_index - 1
    if 0 <= idx < len(groups):
        return groups[idx]
    return None



def run_icedit(*args):
    """Run the icedit CLI tool and return the result."""
    cmd = [ICEDIT_TOOL] + [str(a) for a in args]
    log(f"run_icedit: {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    log(f"run_icedit result: rc={r.returncode} out={r.stdout.strip()} err={r.stderr.strip()}")
    return r


def populate_layer_list(icon_data, target=None):
    """Populate the layer table from icon data."""
    rows = get_layer_rows(icon_data)
    set_table_rows(ID_LAYER_LIST, rows, target=target)


def render_preview(icon_path, platform="macOS", target_uuid=None):
    """Render the icon to PNG using ictool and update the preview image."""
    if not os.path.isfile(ICTOOL):
        set_status("Icon Composer not installed")
        return None

    uuid = target_uuid or WINDOW_UUID
    # Alternate between two filenames so ActionUI.Image sees a different path each time
    slot_key = f"icedit_preview_slot_{uuid}"
    cur_slot = int(pb_get(slot_key) or "0")
    new_slot = 1 - cur_slot
    png_path = f"/tmp/icedit_preview_{uuid}_{new_slot}.png"
    old_path = f"/tmp/icedit_preview_{uuid}_{cur_slot}.png"

    result = subprocess.run([
        ICTOOL, icon_path,
        "--export-image",
        "--output-file", png_path,
        "--platform", platform,
        "--rendition", "Default",
        "--width", "1024",
        "--height", "1024",
        "--scale", "1"
    ], capture_output=True, text=True)

    if result.returncode != 0:
        err = (result.stderr.strip() or result.stdout.strip())
        log(f"ictool failed: {err}")
        set_status(f"ictool: {err}")
        return None

    if os.path.isfile(png_path):
        set_value(ID_PREVIEW, png_path, target=target_uuid)
        pb_set(slot_key, str(new_slot))
        # Remove the previous preview file
        try:
            if os.path.isfile(old_path):
                os.remove(old_path)
        except OSError:
            pass
        return png_path

    set_status("No PNG generated")
    return None


def color_to_hex(color_str):
    """Convert Icon Composer color string to '#RRGGBB' or '#RRGGBBAA'.
    Supports extended-srgb:, srgb:, display-p3:, extended-gray: prefixes."""
    if not color_str:
        return ""
    # All RGB color formats use 'prefix:R,G,B,A' with floats 0-1
    for prefix in ("extended-srgb:", "srgb:", "display-p3:"):
        if color_str.startswith(prefix):
            parts = color_str[len(prefix):].split(",")
            if len(parts) >= 3:
                r = max(0, min(255, int(float(parts[0]) * 255)))
                g = max(0, min(255, int(float(parts[1]) * 255)))
                b = max(0, min(255, int(float(parts[2]) * 255)))
                a = float(parts[3]) if len(parts) > 3 else 1.0
                if a >= 1.0:
                    return f"#{r:02X}{g:02X}{b:02X}"
                else:
                    ai = max(0, min(255, int(a * 255)))
                    return f"#{r:02X}{g:02X}{b:02X}{ai:02X}"
    if color_str.startswith("extended-gray:"):
        parts = color_str[len("extended-gray:"):].split(",")
        if len(parts) >= 1:
            v = max(0, min(255, int(float(parts[0]) * 255)))
            return f"#{v:02X}{v:02X}{v:02X}"
    # Already hex or named color — pass through
    return color_str



def parse_fill(fill_value):
    """Parse a fill value into (fill_type, color1, color2).
    Returns ('none'|'automatic'|'solid'|'auto-gradient'|'gradient', color_str, color_str_or_None).
    Missing/absent fill returns 'none'."""
    if fill_value is None:
        return ("none", "", None)
    if fill_value == "none":
        return ("none", "", None)
    if fill_value == "automatic":
        return ("automatic", "", None)
    if not isinstance(fill_value, dict):
        return ("none", "", None)
    if "solid" in fill_value:
        return ("solid", fill_value["solid"], None)
    if "automatic-gradient" in fill_value:
        return ("auto-gradient", fill_value["automatic-gradient"], None)
    if "linear-gradient" in fill_value:
        colors = fill_value["linear-gradient"]
        if isinstance(colors, list):
            c1 = colors[0] if len(colors) > 0 else ""
            c2 = colors[1] if len(colors) > 1 else ""
            return ("gradient", c1, c2)
    return ("none", "", None)


ALERT_TOOL = os.path.join(SUPPORT_PATH, "alert")


def file_hash(path):
    """Compute SHA-256 hash of a file. Returns hex string or empty on error."""
    import hashlib
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()
    except (OSError, IOError):
        return ""


def store_original_hash():
    """Compute and store the hash of the original icon.json on disk."""
    original = get_original_icon_path()
    if original:
        json_path = os.path.join(original, "icon.json")
        pb_set(PB_ORIGINAL_HASH, file_hash(json_path))
    else:
        pb_set(PB_ORIGINAL_HASH, "")


def is_dirty():
    """Return True if the working copy has unsaved changes."""
    return pb_get(PB_DIRTY) == "1"


def mark_dirty():
    """Mark the working copy as having unsaved changes."""
    pb_set(PB_DIRTY, "1")


def mark_clean():
    """Mark the working copy as saved (no unsaved changes)."""
    pb_set(PB_DIRTY, "")


def get_original_icon_path():
    """Get the original icon path (empty string for new unsaved icons)."""
    return pb_get(PB_ORIGINAL_ICON_PATH)


def create_working_copy(original_path):
    """Copy original .icon bundle to a temp working directory.
    Returns the path to the working copy."""
    import shutil
    work_dir = f"/tmp/icedit_work_{WINDOW_UUID}"
    work_icon = os.path.join(work_dir, os.path.basename(original_path))
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir)
    shutil.copytree(original_path, work_icon)
    return work_icon


def create_new_icon():
    """Create a new empty .icon bundle with default background fill.
    Uses icedit tool's create command. Returns the path to the working copy."""
    import shutil
    work_dir = f"/tmp/icedit_work_{WINDOW_UUID}"
    work_icon = os.path.join(work_dir, "Untitled.icon")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir)
    run_icedit("create", work_icon, "#0088FF")
    return work_icon


def save_icon_to(dest_path):
    """Copy the working icon to a destination path.
    Creates .icon extension if not present. Returns the final path."""
    import shutil
    if not dest_path.endswith(".icon"):
        dest_path += ".icon"
    work_icon = get_icon_path()
    if not work_icon:
        return None
    if os.path.exists(dest_path):
        shutil.rmtree(dest_path)
    shutil.copytree(work_icon, dest_path)
    return dest_path


def cleanup_state():
    """Clean up all pasteboard, temp files, and state for this window."""
    import shutil
    import glob as _glob
    work_dir = f"/tmp/icedit_work_{WINDOW_UUID}"
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    # Remove preview PNGs for this window
    for f in _glob.glob(f"/tmp/icedit_preview_{WINDOW_UUID}_*.png"):
        try:
            os.remove(f)
        except OSError:
            pass
    # Remove SF Symbol SVG for this window
    svg = f"/tmp/icedit_sfsymbol_{WINDOW_UUID}.svg"
    if os.path.isfile(svg):
        try:
            os.remove(svg)
        except OSError:
            pass
    pb_set(PB_ICON_PATH, "")
    pb_set(PB_ORIGINAL_ICON_PATH, "")
    pb_set(PB_SELECTED_LAYER, "")
    pb_set(PB_SELECTED_TYPE, "")
    pb_set(PB_DIRTY, "")
    pb_set(PB_ORIGINAL_HASH, "")
    pb_set(f"icedit_preview_slot_{WINDOW_UUID}", "")
    pb_set(PB_CLOSE_AFTER_SAVE, "")
