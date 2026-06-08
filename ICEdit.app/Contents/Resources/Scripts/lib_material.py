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
    are ranked by a tuple of scores, most significant first:

      1. full-word name matches — terms that equal a whole word of the symbol
         name (words are split on '_'), so searching "car" puts "car" and
         "directions_car" above "scorecard" where "car" is only part of a word;
      2. total matches — how many distinct terms appear anywhere in name+tags;
      3. name matches — terms that appear in the name (vs tags only), so a
         name-substring match outranks a tag-only match.

    Within an equal score the input (alphabetical) order is preserved by the
    stable sort. Falls back to the name alone for symbols with no metadata."""
    search = (search or "").lower().strip()
    if not search:
        return names
    terms = search.split()
    scored = []
    for n in names:
        name_text = n.lower()
        name_words = name_text.replace("_", " ").split()
        haystack = search_index.get(n, name_text)
        rank = sum(1 for t in terms if t in haystack)
        if rank > 0:
            word_rank = sum(1 for t in terms if t in name_words)
            name_rank = sum(1 for t in terms if t in name_text)
            scored.append((word_rank, rank, name_rank, n))
    # names arrive sorted; stable sort by descending score keeps alpha order
    # within an equal score
    scored.sort(key=lambda x: (-x[0], -x[1], -x[2]))
    return [n for *_, n in scored]
