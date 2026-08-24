"""Shared helpers for the Material Symbols picker.

The Material Symbols data (font, codepoints, search metadata) is fetched into
the bundle by update_icedit.sh and is NOT committed to the repo.
Only the Rounded style is embedded."""

import os
import json

# Ranking lives in lib_glyphsearch so the Symbol Fonts picker shares one
# implementation with this one. Re-exported: handlers here import filter_names
# from this module.
#
# Not a pure code move. The shared version adds a tier above the old ones for an
# exact whole-name match, which MDI needs and which changes the ORDER Material
# Symbols comes back in - "home" now leads with "home" where it used to lead with
# "add_home". Same result set, better first row; 60-symbols asserts it.
from lib_glyphsearch import filter_names  # noqa: F401

APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
MATERIAL_DIR = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg/material")
GLYPHSVG = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg/glyphsvg")

STYLE = "Rounded"  # which Material Symbols variant we ship
MATERIAL_STYLE_ARG = "rounded"  # glyphsvg --material=<style>

CODEPOINTS_FILE = os.path.join(MATERIAL_DIR, f"MaterialSymbols{STYLE}.codepoints")
METADATA_FILE = os.path.join(MATERIAL_DIR, "material_symbols_metadata.json")


def load_names():
    """Return the sorted list of renderable Material Symbol names.

    The .codepoints file is the source of truth for what the embedded font can
    render - each line is '<name> <hexcode>'."""
    names = []
    if not os.path.isfile(CODEPOINTS_FILE):
        return names
    with open(CODEPOINTS_FILE) as f:
        for line in f:
            parts = line.split()
            if parts:
                names.append(parts[0])
    names.sort()
    return names


def load_search_index():
    """Return {name: searchable_text} where searchable_text is the lowercased
    name plus its tags and categories from the metadata. Used for richer
    filtering (search by concept, not just by name)."""
    index = {}
    if not os.path.isfile(METADATA_FILE):
        return index
    try:
        with open(METADATA_FILE) as f:
            data = json.load(f)
    except (ValueError, OSError):
        return index
    for icon in data.get("icons", []):
        name = icon.get("name")
        if not name:
            continue
        terms = [name]
        terms.extend(icon.get("tags", []))
        terms.extend(icon.get("categories", []))
        index[name] = " ".join(terms).lower()
    return index
