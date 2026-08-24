#!/usr/bin/env python3
"""Initialize the Symbol Fonts picker - discover the embedded fonts, then load
the first one's faces and symbol names."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_symbolfonts import apply_font, list_sets, populate_fonts, set_status

WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

sets = list_sets()
if not sets:
    set_status(WINDOW_UUID, "No symbol fonts installed - run update_icedit.sh")
    sys.exit(0)

# Font first: apply_font reads the face list out of whichever set this leaves
# selected, so the order matters.
chosen = populate_fonts(WINDOW_UUID, sets)
apply_font(WINDOW_UUID, chosen)
