#!/usr/bin/env python3
"""Render the selected symbol to SVG and show it in the preview. Bound to the
list, to the face picker, and to the weight slider, so a change to any of the
three re-renders."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_debounce import should_rebuild
from lib_symbolfonts import (ID_PREVIEW, ID_WEIGHT, dialog, render_symbol,
                             resolve_face, resolve_weight, scratch_svg,
                             set_info, set_status, set_weight_label)

WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

symbol = os.environ.get("OMC_ACTIONUI_TABLE_2_COLUMN_1_VALUE", "").strip()
set_name = os.environ.get("OMC_ACTIONUI_VIEW_4_VALUE", "").strip()
requested_face = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "").strip()
requested_weight = os.environ.get("OMC_ACTIONUI_VIEW_12_VALUE", "").strip()
trigger = os.environ.get("OMC_ACTIONUI_TRIGGER_VIEW_ID", "").strip()

if not set_name:
    sys.exit(0)

info = set_info(set_name)
if not info.get("faces"):
    sys.exit(0)
# Never render with the face as handed over: switching fonts leaves the picker's
# old tag in place until SwiftUI resyncs, and that resync dispatches this very
# action carrying a face the new font may not have.
face = resolve_face(info, requested_face)
# Re-read --info for the resolved face: the axes belong to the face's own font
# file, and on a multi-face set that need not be the one the default reports.
face_info = info if face == info.get("face") else set_info(set_name, face)
weight = resolve_weight(face_info, requested_weight)

# The label first, and before the no-symbol exit below. It is the only feedback
# the slider has, so it has to track the drag whether or not a symbol is picked
# yet - and it must not be held back by the debounce.
if weight is not None:
    set_weight_label(WINDOW_UUID, weight)

if not symbol:
    sys.exit(0)

# A slider drag dispatches once per step - the length of Nunito's axis is eighty
# of them - where a list click or a face change dispatches once. So only the
# slider is debounced: everything else stays instant. Keyed apart from the
# search field's debounce, which coordinates through a file of its own.
if trigger == str(ID_WEIGHT) and not should_rebuild("%s.weight" % WINDOW_UUID):
    sys.exit(0)

svg_path = scratch_svg(WINDOW_UUID)
ok, message = render_symbol(set_name, face, symbol, svg_path, weight)
if not ok:
    set_status(WINDOW_UUID, "Error: %s" % message)
    sys.exit(0)

dialog(WINDOW_UUID, ID_PREVIEW, svg_path)
