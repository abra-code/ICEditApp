#!/usr/bin/env python3
"""Render the selected symbol to SVG and show it in the preview. Bound to the
list, and to the face picker so a face change re-renders."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_symbolfonts import (ID_PREVIEW, dialog, render_symbol, resolve_face,
                             scratch_svg, set_info, set_status)

WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
set_name = os.environ.get("OMC_ACTIONUI_VIEW_4_VALUE", "").strip()
requested_face = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "").strip()

if not symbol or not set_name:
    sys.exit(0)

info = set_info(set_name)
if not info.get("faces"):
    sys.exit(0)
# Never render with the face as handed over: switching fonts leaves the picker's
# old tag in place until SwiftUI resyncs, and that resync dispatches this very
# action carrying a face the new font may not have.
face = resolve_face(info, requested_face)

svg_path = scratch_svg(WINDOW_UUID)
ok, message = render_symbol(set_name, face, symbol, svg_path)
if not ok:
    set_status(WINDOW_UUID, "Error: %s" % message)
    sys.exit(0)

dialog(WINDOW_UUID, ID_PREVIEW, svg_path)
