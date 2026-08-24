"""Shared helpers for the generic Symbol Fonts picker.

Unlike lib_material.py, nothing here is specific to one font. A glyph set is a
directory under Contents/Helpers/glyphsvg/sets/ holding a glyphset.conf manifest
plus its font and codepoint tables; update_icedit.sh provisions them and they
are NOT committed to the repo.

The manifest is never parsed here. glyphsvg --info already reports the resolved
faces, font, codepoints and metadata paths as 'key: value' lines, and that is a
published contract; re-implementing the manifest parser in Python would be a
second thing to keep in step with the C every time the format grows."""

import os
import re
import subprocess

from lib_glyphsearch import filter_names  # noqa: F401 - re-exported for handlers

APP_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
GLYPHSVG_DIR = os.path.join(APP_BUNDLE, "Contents/Helpers/glyphsvg")
GLYPHSVG = os.path.join(GLYPHSVG_DIR, "glyphsvg")
SETS_DIR = os.path.join(GLYPHSVG_DIR, "sets")

# Rendered at a fixed large size and scaled down by the icon compositor, the
# same size the Material picker uses. Independent of the preview frame.
RENDER_SIZE = "768"


def _run_glyphsvg(args):
    """Run glyphsvg and return (returncode, stdout, stderr). Never raises."""
    if not os.path.isfile(GLYPHSVG):
        return 127, "", "glyphsvg helper is missing from the app bundle"
    try:
        result = subprocess.run([GLYPHSVG] + args, capture_output=True, text=True)
    except OSError as exc:
        return 127, "", str(exc)
    return result.returncode, result.stdout, result.stderr


def _parse_info(text):
    """Turn glyphsvg --info output into a dict. 'faces' becomes a list; every
    other key keeps its string value. Repeated keys (axis:) collect into a
    list."""
    info = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        if not sep:
            continue
        key, value = key.strip(), value.strip()
        if key == "faces":
            info[key] = value.split()
        elif key == "axis":
            info.setdefault("axes", []).append(value)
        else:
            info[key] = value
    return info


# A set name reaches us from a dialog value, and os.path.join returns an
# absolute argument unchanged rather than joining it. Nothing today can put a
# path there, which is exactly why the guard is worth having before something
# can.
_SET_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def set_dir(set_name):
    """Absolute path of a set inside the bundle, or "" if the name is not one."""
    if not set_name or set_name in (".", "..") or not _SET_NAME.match(set_name):
        return ""
    return os.path.join(SETS_DIR, set_name)


def scratch_svg(window_uuid, purpose="preview"):
    """Where a rendered glyph is staged. One definition: two handlers agreeing
    on this path by hand is a bug waiting for the next person to edit one."""
    scratch = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    return "%s/icedit_symbolfont_%s_%s.svg" % (scratch, purpose, window_uuid)


def set_info(set_name, face=None):
    """Return glyphsvg's resolved view of a set as a dict, or {} if it will not
    resolve. Keys of interest: title, dir, faces (list), face, font, codepoints,
    metadata (absent when the set has none), variable ('yes'/'no')."""
    directory = set_dir(set_name)
    if not directory or not os.path.isdir(directory):
        return {}
    args = ["--set=" + directory]
    if face:
        args.append("--face=" + face)
    args.append("--info")
    code, out, _ = _run_glyphsvg(args)
    if code != 0:
        return {}
    return _parse_info(out)


def list_sets():
    """Return [{name, title, faces}] for every usable set in the bundle, sorted
    by title. A directory that glyphsvg will not resolve is skipped rather than
    offered and then failing on selection."""
    sets = []
    if not os.path.isdir(SETS_DIR):
        return sets
    for entry in sorted(os.listdir(SETS_DIR)):
        if entry.startswith("."):
            continue
        info = set_info(entry)
        if not info.get("faces"):
            continue
        sets.append({
            "name": entry,
            "title": info.get("title") or entry,
            "faces": info["faces"],
        })
    sets.sort(key=lambda s: s["title"].lower())
    return sets


def resolve_face(info, requested):
    """Return a face that actually exists in this set.

    Handlers cannot trust the face they are handed. The environment is a
    snapshot taken at dispatch, two handlers can overlap, and swapping a
    Picker's options leaves its old selection dangling until SwiftUI resyncs -
    which can itself dispatch an action carrying a face belonging to the
    previously selected font. So a face is used only if the set has it, and
    otherwise the set's own default (the face --info reports with no --face
    argument) wins."""
    faces = info.get("faces") or []
    if requested and requested in faces:
        return requested
    return info.get("face") or (faces[0] if faces else "")


def load_names(codepoints_path):
    """Return the sorted symbol names a codepoints file can render. Each line is
    '<name> <hexcode>'."""
    names = []
    if not codepoints_path or not os.path.isfile(codepoints_path):
        return names
    # errors="replace": a codepoints file that is not UTF-8 is a broken set, not
    # a reason for the whole picker to disappear with a traceback.
    with open(codepoints_path, errors="replace") as f:
        for line in f:
            parts = line.split()
            if parts:
                names.append(parts[0])
    names.sort()
    return names


def load_search_index(metadata_path):
    """Return {name: searchable_text} from an optional metadata sidecar, in the
    {"icons":[{name,tags,categories}]} shape Google publishes for Material
    Symbols and our MDI converter reproduces. A set without one (Fluent) gets an
    empty index and search degrades to name matching."""
    import json

    index = {}
    if not metadata_path or not os.path.isfile(metadata_path):
        return index
    try:
        with open(metadata_path, errors="replace") as f:
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


def render_symbol(set_name, face, symbol, out_path):
    """Render one symbol to out_path. Returns (ok, message).

    out_path is replaced atomically. glyphsvg opens its output only after the
    glyph is serialized, so a FAILED render leaves whatever was there before -
    which would let a caller read a stale glyph and believe it rendered. It also
    writes without a temp file of its own, so a reader can catch a partial one."""
    directory = set_dir(set_name)
    if not directory:
        return False, "'%s' is not a valid set name" % set_name
    args = ["--set=" + directory]
    if face:
        args.append("--face=" + face)
    staging = out_path + ".new"
    args += [symbol, RENDER_SIZE, "--output=" + staging]
    try:
        code, _, err = _run_glyphsvg(args)
        if code != 0:
            message = (err.strip().splitlines() or ["glyphsvg failed"])[-1]
            # glyphsvg prefixes its own diagnostics with "Error: " and the
            # callers here prefix again for the status line, which would read as
            # "Error: Error:". The codepoints path it names is not useful in a
            # status line either.
            if message.startswith("Error: "):
                message = message[len("Error: "):]
            cut = message.find(" in /")
            if cut > 0:
                message = message[:cut]
            return False, message
        # Completeness, not existence. glyphsvg checks neither its fprintf nor
        # its fclose, so a full disk yields a truncated file, "SVG saved to ..."
        # on stdout and exit 0.
        try:
            with open(staging, errors="replace") as f:
                body = f.read()
        except OSError:
            return False, "glyphsvg wrote no readable file"
        if "</svg>" not in body[-32:]:
            return False, "glyphsvg wrote a truncated SVG (disk full?)"
        os.replace(staging, out_path)
    finally:
        if os.path.exists(staging):
            try:
                os.remove(staging)
            except OSError:
                pass
    return True, ""


# ---------------------------------------------------------------------------
# Dialog plumbing
#
# The font and face pickers are populated at runtime rather than declared in
# SymbolFonts.json, because which fonts are embedded is decided by
# update_icedit.sh and a hardcoded option list would silently disagree with the
# bundle the moment a set is added or skipped.
# ---------------------------------------------------------------------------

DIALOG_TOOL = os.path.join(os.environ.get("OMC_OMC_SUPPORT_PATH", ""),
                           "omc_dialog_control")

ID_FILTER = 1
ID_LIST = 2
ID_STATUS = 3
ID_FONT = 4
ID_PREVIEW = 10
ID_FACE = 11
ID_ADD = 20


def dialog(window_uuid, view_id, *args, **kwargs):
    """Send one omc_dialog_control command. `data` is piped on stdin.

    Never raises. The first thing the no-sets path does is write a status line,
    so an unset OMC_OMC_SUPPORT_PATH would take down the least-tested branch of
    the picker with a traceback instead of showing its message."""
    data = kwargs.get("data")
    cmd = [DIALOG_TOOL, window_uuid, str(view_id)] + [str(a) for a in args]
    try:
        if data is None:
            return subprocess.run(cmd, capture_output=True)
        return subprocess.run(cmd, input=data.encode(), capture_output=True)
    except OSError:
        return None


def set_status(window_uuid, message):
    dialog(window_uuid, ID_STATUS, message)


def _picker_options(pairs):
    """Build the JSON option list a Picker takes: [{"title","tag"}, ...]."""
    import json
    return json.dumps([{"title": t, "tag": g} for t, g in pairs])


def populate_fonts(window_uuid, sets, selected=None):
    """Fill the font picker from the sets found in the bundle and return the
    set name left selected."""
    if not sets:
        return ""
    dialog(window_uuid, ID_FONT, "omc_set_property", "options",
           _picker_options([(s["title"], s["name"]) for s in sets]))
    names = [s["name"] for s in sets]
    chosen = selected if selected in names else names[0]
    # Setting options never touches the selection, so an option list that no
    # longer holds the old tag would leave the picker showing a dangling value
    # until SwiftUI resynced it - and that resync dispatches the picker's action
    # carrying whatever it picked. Anchor it explicitly instead.
    dialog(window_uuid, ID_FONT, chosen)
    return chosen


def apply_font(window_uuid, set_name, requested_face=None, search=""):
    """Point the whole dialog at one font: refill the face picker, reload the
    name list, update the status line. Returns (info, face, names) where info is
    glyphsvg's --info for the resolved face, or ({}, "", []) if the set will not
    resolve.

    Shared by the init and font-change handlers so the two cannot drift."""
    info = set_info(set_name)
    faces = info.get("faces") or []
    if not faces:
        set_status(window_uuid, "'%s' did not resolve - re-run update_icedit.sh" % set_name)
        return {}, "", []

    face = resolve_face(info, requested_face)
    dialog(window_uuid, ID_FACE, "omc_set_property", "options",
           _picker_options([(f.capitalize(), f) for f in faces]))
    dialog(window_uuid, ID_FACE, face)
    # A single-face set has nothing to choose. Disabled rather than hidden:
    # hiding it reflows the control bar every time the font changes.
    dialog(window_uuid, ID_FACE, "omc_enable" if len(faces) > 1 else "omc_disable")

    face_info = info if face == info.get("face") else set_info(set_name, face)
    names = load_names(face_info.get("codepoints"))
    if search:
        index = load_search_index(face_info.get("metadata"))
        names = filter_names(names, index, search)
    dialog(window_uuid, ID_LIST, "omc_list_set_items_from_stdin", data="\n".join(names))
    set_status(window_uuid, "%d symbols" % len(names))
    return face_info, face, names
