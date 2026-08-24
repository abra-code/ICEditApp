"""Name filtering and ranking shared by every symbol picker.

Split out of lib_material.py when the generic Symbol Fonts picker arrived: the
ranking is not specific to Material Symbols, and two copies would have drifted.
Nothing here knows about a particular font - callers supply the names and an
optional {name: searchable_text} index."""

import re

# Word separator in a symbol name. Material Symbols and Fluent use '_'
# (photo_camera, access_time), MDI uses '-' (ab-testing, airplane-plus). Both
# have to break into words or full-word ranking silently stops working for one
# of them - a whole-name match like "car" would score no better than a
# substring hit inside "scorecard".
_WORD_SPLIT = re.compile(r"[-_\s]+")


def name_words(name):
    """Return the lowercased words of a symbol name, split on - and _."""
    return [w for w in _WORD_SPLIT.split(name.lower()) if w]


def filter_names(names, search_index, search):
    """Filter and rank names by a search string. A name matches if ANY of the
    whitespace-separated terms appears in its name+tags text (OR logic). Results
    are ranked by a tuple of scores, most significant first:

      1. exact name match - the search equals the whole symbol name, so "cog"
         leads the several hundred *-cog icons instead of sorting into them
         alphabetically. This tier exists because splitting names on '-' makes
         every hyphenated name score a full-word match: without it the thing
         the user literally typed vanishes into a tie hundreds long;
      2. full-word name matches - terms that equal a whole word of the symbol
         name, so searching "car" puts "car" and "directions_car" above
         "scorecard" where "car" is only part of a word;
      3. total matches - how many distinct terms appear anywhere in name+tags;
      4. name matches - terms that appear in the name (vs tags only), so a
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
        words = name_words(n)
        haystack = search_index.get(n, name_text)
        rank = sum(1 for t in terms if t in haystack)
        if rank > 0:
            exact = 1 if name_text == search else 0
            word_rank = sum(1 for t in terms if t in words)
            name_rank = sum(1 for t in terms if t in name_text)
            scored.append((exact, word_rank, rank, name_rank, n))
    # names arrive sorted; stable sort by descending score keeps alpha order
    # within an equal score
    scored.sort(key=lambda x: (-x[0], -x[1], -x[2], -x[3]))
    return [n for *_, n in scored]
