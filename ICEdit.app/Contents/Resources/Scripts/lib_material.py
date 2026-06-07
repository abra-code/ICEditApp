"""Shared helpers for the Material Symbols picker.

The Material Symbols data (font, codepoints, search metadata) is fetched into
the bundle by download_material_symbols.sh and is NOT committed to the repo.
Only the Rounded style is embedded."""

import os
import json

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
    render — each line is '<name> <hexcode>'."""
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


def filter_names(names, search_index, search):
    """Filter and rank names by a search string. A name matches if ANY of the
    whitespace-separated terms appears in its name+tags text (OR logic). Results
    are ranked primarily by how many distinct terms match — a name matching all
    N terms ranks above one matching N-1, and so on — so the best matches bubble
    to the top. As a secondary tie-break, matches in the symbol *name* outrank
    matches that only hit the tags/metadata, so e.g. searching "car" lists the
    symbols whose name contains "car" above ones that merely have "car" as a
    tag. Within an equal rank the input (alphabetical) order is preserved.
    Falls back to the name alone for symbols that have no metadata entry."""
    search = (search or "").lower().strip()
    if not search:
        return names
    terms = search.split()
    scored = []
    for n in names:
        name_text = n.lower()
        haystack = search_index.get(n, name_text)
        rank = sum(1 for t in terms if t in haystack)
        if rank > 0:
            name_rank = sum(1 for t in terms if t in name_text)
            scored.append((rank, name_rank, n))
    # names arrive sorted; stable sort by descending (rank, name_rank) keeps
    # alpha order within an equal score
    scored.sort(key=lambda x: (-x[0], -x[1]))
    return [n for _, _, n in scored]
