#!/usr/bin/env python3
"""Font picker changed - switch the whole dialog to the newly selected font."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_symbolfonts import ID_PREVIEW, apply_font, dialog, scratch_svg

WINDOW_UUID = os.environ.get("OMC_ACTIONUI_WINDOW_UUID", "")

set_name = os.environ.get("OMC_ACTIONUI_VIEW_4_VALUE", "").strip()
if not set_name:
    sys.exit(0)

# The face is deliberately NOT carried over from the environment. It names a
# face of the font we are leaving, and apply_font would only have to discard it;
# passing nothing asks for the new font's own default.
#
# The filter text IS carried over: the user's search is about what they are
# looking for, not about which font supplies it, and silently clearing the box
# would leave the list showing everything while the field still reads "camera".
search = os.environ.get("OMC_ACTIONUI_VIEW_1_VALUE", "")

# The weight IS carried over, unlike the face. A face name means nothing outside
# the font that declares it, but a weight is a number on a scale every font
# shares - keeping it lets the user compare fonts at one weight. apply_font
# clamps it into the new font's declared range, so carrying it is safe even
# between fonts whose axes do not overlap.
weight = os.environ.get("OMC_ACTIONUI_VIEW_12_VALUE", "")

info, face, names = apply_font(WINDOW_UUID, set_name, search=search,
                               requested_weight=weight)

# The preview still shows a glyph from the previous font. Rendering the same
# symbol from the new one is guesswork - the name usually does not exist there -
# so clear it and let the next selection fill it in.
#
# The rendered file goes with it. Leaving it behind is how a stale glyph outlives
# the font it came from, and nothing downstream should be able to find it.
if info:
    dialog(WINDOW_UUID, ID_PREVIEW, "")
    try:
        os.remove(scratch_svg(WINDOW_UUID))
    except OSError:
        pass
