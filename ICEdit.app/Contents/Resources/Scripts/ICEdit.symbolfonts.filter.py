#!/usr/bin/env python3
"""Filter the current font's symbol names by the search text."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_symbolfonts import (ID_LIST, dialog, filter_names, load_names,
                             load_search_index, resolve_face, set_info,
                             set_status)
from lib_debounce import should_rebuild

WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

set_name = os.environ.get("OMC_ACTIONUI_VIEW_4_VALUE", "").strip()
requested_face = os.environ.get("OMC_ACTIONUI_VIEW_11_VALUE", "").strip()
search = os.environ.get("OMC_ACTIONUI_VIEW_1_VALUE", "")

if not set_name:
    sys.exit(0)

# Collapse fast bursts of keystrokes into a single rebuild - bail out if a newer
# keystroke arrived while we waited.
if not should_rebuild(WINDOW_UUID):
    sys.exit(0)

info = set_info(set_name)
if not info.get("faces"):
    sys.exit(0)
face = resolve_face(info, requested_face)
face_info = info if face == info.get("face") else set_info(set_name, face)

names = load_names(face_info.get("codepoints"))
index = load_search_index(face_info.get("metadata"))
filtered = filter_names(names, index, search)

dialog(WINDOW_UUID, ID_LIST, "omc_list_set_items_from_stdin",
       data="\n".join(filtered))
set_status(WINDOW_UUID, "%d symbols" % len(filtered))
