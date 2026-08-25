#!/usr/bin/env python3
"""Add the selected symbol as a layer to the current icon."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *
# Aliased, not imported under its own name: lib_icedit's ID_STATUS is 399, the
# DOCUMENT window's status label, and the star-import above brings it in. The
# two would resolve by import order alone, and a reordering would send this
# picker's messages to the wrong window with nothing failing.
from lib_symbolfonts import ID_STATUS as PICKER_STATUS
from lib_symbolfonts import (render_symbol, resolve_face, resolve_weight,
                             scratch_svg, set_info)

log("=== ICEdit.symbolfonts.add.py ===")

PICKER_UUID = WINDOW_UUID  # this dialog's own UUID


def decline(message):
    subprocess.run([DIALOG_TOOL, PICKER_UUID, str(PICKER_STATUS), message],
                   capture_output=True)
    sys.exit(0)


symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
set_name = os.environ.get("OMC_ACTIONUI_VIEW_4_VALUE", "").strip()
requested_face = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "").strip()
requested_weight = os.environ.get("OMC_ACTIONUI_VIEW_12_VALUE", "").strip()

if not symbol:
    decline("No symbol selected")
if not set_name:
    decline("No font selected")

icon_path = pb_get(PB_ICON_PATH)
if not icon_path:
    decline("No icon open in ICEdit")

info = set_info(set_name)
if not info.get("faces"):
    decline("'%s' did not resolve - re-run update_icedit.sh" % set_name)
face = resolve_face(info, requested_face)
face_info = info if face == info.get("face") else set_info(set_name, face)
# Resolved from the same snapshot that names the layer, for the same reason the
# render below is not reused from the preview: the artwork, its weight and its
# name have to agree by construction, not by timing.
weight = resolve_weight(face_info, requested_weight)

# Rendered here rather than reused from the preview handler's file.
#
# Reusing it looks like an optimization and is a correctness bug: glyphsvg opens
# its output only after a glyph is serialized, so a FAILED render leaves the
# previous SVG in place. Selecting a name the font does not have, then clicking
# Add, would add the previously previewed artwork under the newly selected name.
# A font switch leaves the same stale file behind, and because handlers overlap,
# a preview render landing mid-add could swap the file under this handler's feet.
# Rendering from the same environment snapshot that names the layer is what makes
# the artwork and the name agree by construction.
svg_path = scratch_svg(PICKER_UUID, "add")
ok, message = render_symbol(set_name, face, symbol, svg_path, weight)
if not ok:
    decline("Cannot add '%s': %s" % (symbol, message))

result = run_icedit("add_svg", icon_path, svg_path, symbol, "--auto-scale")
if result.returncode != 0:
    subprocess.run([DIALOG_TOOL, PICKER_UUID, str(PICKER_STATUS),
                    f"Failed: {result.stderr.strip()[:80]}"],
                   capture_output=True)
    sys.exit(1)

# Refresh ICEdit main window - target parent document window
icon_data = load_icon_json(icon_path)
if icon_data:
    populate_layer_list(icon_data, target=DOCUMENT_UUID)
    render_preview(icon_path, target_uuid=DOCUMENT_UUID)

mark_dirty()

subprocess.run([DIALOG_TOOL, PICKER_UUID, str(PICKER_STATUS),
                f"Added '{symbol}' as layer"], capture_output=True)

log("=== ICEdit.symbolfonts.add.py done ===")
