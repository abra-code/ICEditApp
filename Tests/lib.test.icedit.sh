#!/bin/sh
# lib.test.icedit.sh - the ICEdit applet's own test vocabulary.
#
# Sourced by every Tests/*.test.sh file, after omctest.sh. omctest supplies the
# generic half - the scratch tree, the interposition directory, the alert and
# omc_dialog_control stubs, check/section/omctest_end - and knows nothing about
# this applet. Everything below encodes ICEdit's private layout: where the
# working copy of the open document lives, which pasteboard keys carry its
# state, what a layer row looks like in the table, and how to call into
# lib_icedit.py directly.
#
# ICEdit is a Python applet; the test files are still POSIX sh, because the
# assertion surface (files, exit codes, recorded window writes) is
# language-neutral. Where a helper genuinely needs Python it lives in
# Tests/helpers/ as a real .py file with its own docstring, rather than as a
# here-doc inside a shell function.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".

TEST_HELPERS="$OMCTEST_TESTS/helpers"

# API 4 is the floor: this suite relies on ui_reset not dropping the diagnostic
# logs, so the cumulative check at the end of each file answers for the whole
# file rather than only for its last section.
[ "${OMCTEST_API_VERSION:-0}" -ge 4 ] || {
    printf 'lib.test.icedit: needs omctest API 4 or newer, got %s\n' \
        "${OMCTEST_API_VERSION:-none}" >&2
    exit 1
}

# --- Where the applet keeps things --------------------------------------------

# lib_icedit.py: DOCUMENT_UUID = PARENT_UUID or WINDOW_UUID. The symbol pickers
# are separate ACTIONUI_WINDOWs raised over the document, so inside one of them
# the document's state is still addressed by the PARENT guid - which is the only
# reason ICEdit.sfsymbols.add can find the icon the user has open.
document_uuid() { printf '%s' "${OMC_PARENT_DIALOG_GUID:-$OMC_ACTIONUI_WINDOW_UUID}"; }

# The working copy directory is keyed on WINDOW_UUID, NOT on DOCUMENT_UUID.
# lib_icedit.create_working_copy / create_new_icon / cleanup_state all
# interpolate WINDOW_UUID directly, so a sheet has no working directory of its
# own and must never be asked for one. Kept distinct from document_uuid() above
# so the difference is visible rather than accidental.
#
# lib_icedit builds these with an f-string, "{SCRATCH_DIR}/icedit_work_{uuid}",
# where SCRATCH_DIR is os.environ["TMPDIR"].rstrip("/"). Shell interpolation of
# $TMPDIR does NOT strip the trailing slash macOS puts there, so "${TMPDIR}/x"
# would be a doubled slash that only bites when a path is compared as a string.
# ${TMPDIR%/} reproduces what Python actually produces, either way.
scratch_dir() {
    local tmp_dir="${TMPDIR:-/tmp}"
    printf '%s' "${tmp_dir%/}"
}

work_dir() { printf '%s/icedit_work_%s' "$(scratch_dir)" "$OMC_ACTIONUI_WINDOW_UUID"; }

# render_preview alternates between two filenames so ActionUI.Image sees a
# changed path each time, and it keys the slot on the TARGET window - the
# document window when a picker sheet drives the refresh.
preview_png() { # <slot 0|1> [window-uuid, default the current window]
    printf '%s/icedit_preview_%s_%s.png' \
        "$(scratch_dir)" "${2:-$OMC_ACTIONUI_WINDOW_UUID}" "$1"
}

# The rendered symbol each picker hands to its add handler, keyed on the
# PICKER's own window uuid rather than the document's.
sfsymbol_svg() { printf '%s/icedit_sfsymbol_%s.svg' "$(scratch_dir)" "$OMC_ACTIONUI_WINDOW_UUID"; }
matsymbol_svg() { printf '%s/icedit_matsymbol_%s.svg' "$(scratch_dir)" "$OMC_ACTIONUI_WINDOW_UUID"; }
# The Symbol Fonts picker keeps two renders, not one: the preview handler's, and
# the add handler's, which renders its own rather than trusting the preview's.
symbolfont_svg() { printf '%s/icedit_symbolfont_preview_%s.svg' "$(scratch_dir)" "$OMC_ACTIONUI_WINDOW_UUID"; }
symbolfont_add_svg() { printf '%s/icedit_symbolfont_add_%s.svg' "$(scratch_dir)" "$OMC_ACTIONUI_WINDOW_UUID"; }

# --- Per-document state, which lives entirely in the pasteboard ----------------
#
# Reached through the interposition directory exactly as the handlers reach it,
# not the framework copy directly - so a test reads back through the same
# file-backed stub the handler wrote through. Reading the framework copy would
# ask the machine's real pasteboard server, which holds none of this run's data.
pb_key() { printf 'icedit_%s_%s' "$1" "$(document_uuid)"; }
pb_get() { "$OMC_OMC_SUPPORT_PATH/pasteboard" "$(pb_key "$1")" get 2>/dev/null; }
pb_set() { printf '%s' "$2" | "$OMC_OMC_SUPPORT_PATH/pasteboard" "$(pb_key "$1")" set; }

# lib_icedit's PB_* names, one accessor each. "icon_path" is the WORKING copy in
# $TMPDIR; "original" is the document on disk, and is empty for a document that
# has never been saved - which is the flag ICEdit.save reads to decide whether
# to overwrite or to chain to Save As.
work_icon() { pb_get icon_path; }
original() { pb_get original_path; }
dirty() { pb_get dirty; }
selected_layer() { pb_get selected_layer; }
selected_type() { pb_get selected_type; }
original_hash() { pb_get original_hash; }
close_after_save() { pb_get close_after_save; }

# --- Calling lib_icedit directly ------------------------------------------------
#
# Whole-handler dispatch is coarse: the rules that decide what the window shows
# live in named functions - parse_fill, color_to_hex, get_layer_rows, find_layer
# - and those are worth testing on their own. See helpers/icedit_eval.py for why
# arguments go through ARGV rather than into the expression text.
icedit_eval() { # <python-expression> [argument ...]
    "$OMCTEST_PYTHON" "$TEST_HELPERS/icedit_eval.py" "$@"
}

# yes/no for an expression that answers a question, so the check line reads as
# the rule rather than as the plumbing.
#
# It answers "no" for a Python-level failure too - a traceback is not True - so
# a check whose expected value happens to BE "no" could pass on a broken
# expression. Every such check in this suite is paired with its opposite, which
# cannot pass that way.
icedit_is() { # <python-expression> [argument ...]
    local expression="$1"
    shift
    if [ "$(icedit_eval "bool($expression)" "$@")" = "True" ]; then echo yes; else echo no; fi
}

# --- An independent oracle for what is really in a .icon -------------------------
#
# The SYSTEM python's json, deliberately neither the icedit CLI that performed
# the edit nor lib_icedit's own loader. helpers/icon_oracle.py says UNREADABLE
# rather than "" when it cannot read the bundle at all, so a check expecting an
# empty value cannot be satisfied by a document that does not parse.
icon_layers() { # <icon-path> -> layer names, topmost first, one per line
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" layers "$1"
}

icon_layer_count() { # <icon-path>
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" count "$1"
}

icon_groups() { # <icon-path> -> group names, one per line ("" for an unnamed group)
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" groups "$1"
}

icon_fill() { # <icon-path> -> the document's top-level fill, as compact JSON
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" fill "$1"
}

icon_assets() { # <icon-path> -> the files in Assets/, sorted
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" assets "$1"
}

icon_layer_key() { # <icon-path> <layer-name> <key> -> that key, as compact JSON
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" layer "$1" "$2" "$3"
}

icon_group_key() { # <icon-path> <1-based-group-index> <key>
    /usr/bin/python3 "$TEST_HELPERS/icon_oracle.py" group "$1" "$2" "$3"
}

# --- Fixtures --------------------------------------------------------------------
#
# Written out by hand rather than built with the applet's own icedit CLI. Two
# reasons: no binaries in the repository, and a fixture the tool under test
# produced cannot be evidence about that tool. The literal below is a readable
# statement of exactly the shape every assertion in this suite depends on - one
# unnamed group holding two glass SVG layers over an automatic-gradient
# background, which is what "create plus two add_svg" actually produces.
#
# Icon Composer is asserted present where the fixture is built rather than
# discovered 200 lines later as a run of failures that read like an applet
# defect: ICEdit renders its preview with ictool, and without Icon Composer
# every handler that refreshes the preview quietly sets a status message
# instead.
make_sample_icon() { # [name, default Sample.icon] -> prints the icon path
    local icon_name="${1:-Sample.icon}" icon_path
    # Asserted once per test file rather than once per rebuild: the sample is
    # rebuilt for nearly every section, and thirty identical precondition lines
    # would bury the sections that actually say something.
    [ -n "$ICEDIT_FIXTURE_PRECONDITION_CHECKED" ] || {
        check "fixture precondition: Icon Composer is installed" "yes" \
            "$(icedit_is 'ICTOOL is not None')"
        ICEDIT_FIXTURE_PRECONDITION_CHECKED=1
    }
    icon_path="$OMCTEST_WORK/$icon_name"
    /bin/rm -rf "$icon_path"
    /bin/mkdir -p "$icon_path/Assets"
    make_sample_svg "$icon_path/Assets/Circle.svg" "#FF0000"
    make_sample_svg "$icon_path/Assets/Square.svg" "#00FF00"
    /bin/cat > "$icon_path/icon.json" <<'JSON'
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:0.00000,0.53333,1.00000,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "Square.svg",
          "name" : "Square",
          "position" : {
            "scale" : 7.68,
            "translation-in-points" : [ 0, 0 ]
          }
        },
        {
          "glass" : true,
          "image-name" : "Circle.svg",
          "name" : "Circle",
          "position" : {
            "scale" : 7.68,
            "translation-in-points" : [ 0, 0 ]
          }
        }
      ]
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
JSON
    printf '%s' "$icon_path"
}

# A one-shape SVG, small enough to read and valid enough for icedit add_svg and
# for ictool to rasterize.
make_sample_svg() { # <path> <fill-color>
    /bin/cat > "$1" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <circle cx="50" cy="50" r="40" fill="$2"/>
</svg>
SVG
}

# A layer source that is NOT already in the document, so an added layer gets a
# name of its own and cannot be confused with one the fixture shipped. icedit
# names a new layer after the file it came from, which is what makes the name
# predictable here.
added_layer_svg() { # [layer-name, default Local] -> prints the path
    local svg_path="$OMCTEST_WORK/${1:-Local}.svg"
    [ -f "$svg_path" ] || make_sample_svg "$svg_path" "#FF00FF"
    printf '%s' "$svg_path"
}

# A solid-color PNG, for the add_image half of the layer-adding code. The
# extension is what routes a chosen file to add_image rather than add_svg, so a
# suite that only ever added SVGs would never walk that branch at all.
added_layer_png() { # [layer-name, default Bitmap] -> prints the path
    local png_path="$OMCTEST_WORK/${1:-Bitmap}.png"
    [ -f "$png_path" ] || /usr/bin/python3 "$TEST_HELPERS/make_png.py" \
        "$png_path" 64 255 0 255
    printf '%s' "$png_path"
}

# Simulate another application editing the document on disk while ICEdit has it
# open - Icon Composer saving over it, a checkout, a Finder replace. The icedit
# CLI stands in for that other application: what matters is that icon.json's
# bytes change behind the applet's back, not which program changed them, and
# every assertion about the result reads back through the independent oracle
# above rather than through the tool that made the change.
edit_original_behind_the_app() { # <new-layer-name>
    local intruder_svg="$OMCTEST_WORK/$1.svg"
    [ -f "$intruder_svg" ] || make_sample_svg "$intruder_svg" "#0000FF"
    "$OMCTEST_PYTHON" "$OMC_APP_BUNDLE_PATH/Contents/Helpers/icedit/icedit" \
        add_svg "$(original)" "$intruder_svg" "$1" --auto-scale >/dev/null
}

# --- The layer table the handlers read back ---------------------------------------
#
# lib_icedit.get_layer_rows emits four tab-separated cells per row, and
# ICEdit.layer.select reads them back by number. The applet names none of the
# columns, so they are named here once, against get_layer_rows' own docstring,
# rather than spelled as bare digits at thirty call sites.
#
# Which cell carries the type depends on the KIND of row, which is the part
# worth stating: a layer leaves column 1 empty and puts TYPE_LAYER in column 2
# (the empty first cell is the indent that makes layers hang under their group);
# a group and the background put their type in column 1 and leave column 2
# empty. ICEdit.layer.select's "col1 or col2 or TYPE_BG" reads exactly that.
COL_INDENT=1
COL_TYPE=2
COL_NAME=3
COL_VISIBILITY=4

# Hand ICEdit.layer.select one table row exactly as the engine would, for each
# of the three kinds of row the table can hold. Selecting is also what records
# the selection in the pasteboard, so every later handler that acts on "the
# selected layer" has to be reached through one of these.
select_layer() { # <layer-name>
    omc_table_cell "$ID_LAYER_LIST" "$COL_INDENT" ""
    omc_table_cell "$ID_LAYER_LIST" "$COL_TYPE" "$TYPE_LAYER"
    omc_table_cell "$ID_LAYER_LIST" "$COL_NAME" "$1"
    omc_table_cell "$ID_LAYER_LIST" "$COL_VISIBILITY" "$VIS_ON"
    omc_fire ICEdit.layer.select "$ID_LAYER_LIST"
}

select_group() { # [group-display-name, default "Group"]
    omc_table_cell "$ID_LAYER_LIST" "$COL_INDENT" "$TYPE_GROUP"
    omc_table_cell "$ID_LAYER_LIST" "$COL_TYPE" ""
    omc_table_cell "$ID_LAYER_LIST" "$COL_NAME" "${1:-Group}"
    omc_table_cell "$ID_LAYER_LIST" "$COL_VISIBILITY" "$VIS_ON"
    omc_fire ICEdit.layer.select "$ID_LAYER_LIST"
}

select_background() {
    omc_table_cell "$ID_LAYER_LIST" "$COL_INDENT" "$TYPE_BG"
    omc_table_cell "$ID_LAYER_LIST" "$COL_TYPE" ""
    omc_table_cell "$ID_LAYER_LIST" "$COL_NAME" "Background"
    omc_table_cell "$ID_LAYER_LIST" "$COL_VISIBILITY" ""
    omc_fire ICEdit.layer.select "$ID_LAYER_LIST"
}

# One cell out of one row of the table as the window last received it.
row_cell() { # <1-based-row> <1-based-column>
    ui_rows "$ID_LAYER_LIST" | /usr/bin/sed -n "${1}p" | /usr/bin/cut -f "$2"
}

# --- Driving the settings panes --------------------------------------------------
#
# The engine exports every control's CURRENT value on each dispatch, so what
# ICEdit.settings.apply reads is whatever ICEdit.layer.select last pushed into
# the window, modified by whatever the user then touched. The harness does not
# wire the two together - a value written to the virtual window does not become
# an OMC_ACTIONUI_VIEW_*_VALUE by itself - so a test that dispatched
# settings.apply straight after a selection would hand it a pane full of empty
# strings, and empty is not a value the user can produce.
#
# It is not a harmless difference either: an empty scale reads as 1.0, an empty
# Visible toggle reads as hidden, and an empty Glass toggle reads as off, so the
# apply would silently rewrite three properties nobody touched. Adopting the
# window's own values first is what makes "apply with nothing changed" mean what
# it says.
adopt_window_values() { # <view-id> ...
    local view_id
    for view_id; do
        omc_control "$view_id" "$(ui_value "$view_id")"
    done
}

adopt_background_controls() {
    adopt_window_values "$ID_BG_FILL" "$ID_BG_COLOR1_PICKER" "$ID_BG_COLOR2_PICKER"
}

adopt_layer_controls() {
    adopt_window_values "$ID_LAYER_NAME" "$ID_LAYER_FILL" "$ID_LAYER_COLOR1_PICKER" \
        "$ID_LAYER_COLOR2_PICKER" "$ID_LAYER_SCALE" "$ID_LAYER_SHIFT_X" \
        "$ID_LAYER_SHIFT_Y" "$ID_LAYER_VISIBLE" "$ID_LAYER_GLASS" "$ID_LAYER_BLEND"
}

adopt_group_controls() {
    adopt_window_values "$ID_GROUP_NAME" "$ID_GROUP_OPACITY" "$ID_GROUP_BLEND" \
        "$ID_GROUP_BLUR" "$ID_GROUP_LIGHTING" "$ID_GROUP_SPECULAR" \
        "$ID_GROUP_TRANSLUCENCY" "$ID_GROUP_SHADOW" "$ID_GROUP_SHADOW_OPACITY" \
        "$ID_GROUP_VISIBLE" "$ID_GROUP_SCALE" "$ID_GROUP_SHIFT_X" "$ID_GROUP_SHIFT_Y"
}

# --- The symbol pickers -----------------------------------------------------------
#
# Each picker script declares its own view ids as local constants (ID_LIST = 2,
# ID_STATUS = 3, ...) rather than sharing lib_icedit's, so there is nothing to
# import: lib_icedit's own ID_STATUS is 399, the main window's status label, and
# importing the pickers' copies would silently overwrite it. Named here, once,
# with a PICK_ prefix that cannot collide.
PICK_SEARCH=1
PICK_LIST=2
PICK_STATUS=3
PICK_PREVIEW=10
PICK_WEIGHT=11
PICK_FILL=12

# The Symbol Fonts picker adds a font chooser, and uses id 11 for the FACE where
# the Material picker uses it for a weight. Named separately because a test
# asserting on id 11 should say which of the two it means.
#
# Its weight control is a slider on id 12 rather than a picker of named weights,
# because its text fonts carry a real wght axis: Nunito's runs to 1000, and no
# named weight reaches past black/900. Id 13 is the label beside it. Both are
# inert for a static font (Bungee), which is what section 13b asserts.
PICK_FONT=4
PICK_FONT_LICENSE=5
PICK_FACE=11
PICK_FONT_WEIGHT=12
PICK_FONT_WEIGHT_LABEL=13

# The picker's list hands the chosen name to its handlers through the table
# family, exactly as the engine does for a List element.
pick_symbol() { # <command-id> <symbol-name>
    omc_table_cell "$PICK_LIST" 1 "$2"
    omc_run "$1"
}

# --- Intercepting the one external binary that can be intercepted --------------
#
# ICEdit.open.in.composer ends with subprocess.run(["open", "-a", ...]). A bare
# command name, not an absolute path - so unlike the system binaries the omctest
# guide's section 8 rules out, this one is reachable through $PATH. Nothing else
# in the applet is: ictool and actool are located by absolute path and are run
# for real, which is what makes the export and install assertions worth having.
#
# Without this, every dispatch of that handler launches Icon Composer on the
# desktop of whoever is running the suite.
intercept_open() {
    ICEDIT_OPEN_LOG="$OMCTEST_WORK/open.log"
    : > "$ICEDIT_OPEN_LOG"
    PATH="$TEST_HELPERS/fake-bin:$PATH"
    export ICEDIT_OPEN_LOG PATH
    check "the interceptor is the one that answers" "$TEST_HELPERS/fake-bin/open" \
        "$(command -v open)"
}

opens_reset() { : > "${ICEDIT_OPEN_LOG:?call intercept_open first}"; }
opens_count() { /usr/bin/awk 'END { print NR }' "$ICEDIT_OPEN_LOG" 2>/dev/null; }
opens_mention() { /usr/bin/grep -c -- "$1" "$ICEDIT_OPEN_LOG" 2>/dev/null | /usr/bin/tr -d ' '; }

# --- Resetting between scenarios ----------------------------------------------------
#
# Discard the whole document: the working copy AND every pasteboard key. Removing
# only the directory would leave icon_path and dirty pointing at a document that
# no longer exists, and the next section would inherit them - the pasteboard lives
# in the per-login server and outlives the process that wrote it.
#
# The preview slot key is keyed on the window rather than on the document, so it
# is cleared separately, exactly as lib_icedit.cleanup_state does.
reset_document() {
    local state_key
    /bin/rm -rf "$(work_dir)"
    /bin/rm -f "$(preview_png 0)" "$(preview_png 1)"
    for state_key in icon_path original_path selected_layer selected_type \
        dirty original_hash close_after_save; do
        pb_set "$state_key" ""
    done
    printf '' | "$OMC_OMC_SUPPORT_PATH/pasteboard" \
        "icedit_preview_slot_$OMC_ACTIONUI_WINDOW_UUID" set
    omc_object ""
    ui_reset
    alerts_reset
    alert_answers_reset
    chains_reset
}

# A fresh sample document, opened into a fresh window - the state almost every
# section below wants to start from. Prints the path of the document ON DISK;
# the caller reads the working copy back with work_icon().
#
# Rebuilt every time on purpose. Several sections write THROUGH to the original
# - Save, Save on close, an external editor - and a fixture shared across
# sections would carry one section's write into the next section's assertion
# about what is on disk, which is exactly how the first draft of 20-close came
# out green in the wrong places.
open_sample() { # [name, default Sample.icon] -> prints the document path
    local icon_path
    icon_path="$(make_sample_icon "${1:-Sample.icon}")"
    reset_document
    omc_object "$icon_path"
    omc_run ICEdit.main
    printf '%s' "$icon_path"
}

# --- View ids and row symbols, imported from the applet rather than restated --------
#
# lib_icedit.py already names every view the applet drives (ID_LAYER_LIST = 100,
# ...) and every SF Symbol the table puts in its type and visibility columns
# (TYPE_GROUP = "folder", VIS_OFF = "eye.slash"). A second list here is a list
# that can disagree with the first, and the way it disagrees is silent: a name
# that fails to import expands to the empty string, omc_control writes
# OMC_ACTIONUI_VIEW__VALUE, and every check fails one by one with no hint why.
#
# Four expressions rather than one alternation: "\|" is a GNU extension and BSD
# sed matches it literally, which yields nothing and takes the guard below down
# with it. Two of the four exist because most - but not all - of lib_icedit's id
# lines carry a trailing comment naming what the id actually addresses
# (ID_BG_COLOR1 = 302 is the HStack wrapper, ID_BG_COLOR1_PICKER = 3020 the
# ColorPicker inside it), and a pattern anchored at the digits would skip
# exactly those.
omctest_import_view_ids() { # <script ...>
    local script
    for script; do
        eval "$(/usr/bin/sed -n \
            -e 's/^\(ID_[A-Z0-9_]*\) *= *\([0-9][0-9]*\) *$/\1=\2/p' \
            -e 's/^\(ID_[A-Z0-9_]*\) *= *\([0-9][0-9]*\)  *#.*$/\1=\2/p' \
            -e 's/^\(TYPE_[A-Z]*\) *= *"\([^"]*\)"$/\1="\2"/p' \
            -e 's/^\(VIS_[A-Z]*\) *= *"\([^"]*\)"$/\1="\2"/p' \
            "$script")"
    done
}
omctest_import_view_ids \
    "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib_icedit.py"

# Fail once, here, and name every id and symbol the suite drives rather than a
# sample of them: one that went missing from the app is exactly the case this is
# for.
for omctest_required_id in ID_LAYER_LIST ID_BTN_ADD ID_BTN_REMOVE ID_PREVIEW \
    ID_PREVIEW_NOTICE ID_STATUS ID_BG_FILL ID_BG_COLOR1 ID_BG_COLOR1_PICKER ID_BG_COLOR1_LABEL \
    ID_BG_COLOR2 ID_BG_COLOR2_PICKER ID_BG_COLOR2_LABEL ID_LAYER_FILL \
    ID_LAYER_COLOR1 ID_LAYER_COLOR1_PICKER ID_LAYER_COLOR1_LABEL \
    ID_LAYER_COLOR2 ID_LAYER_COLOR2_PICKER ID_LAYER_COLOR2_LABEL \
    ID_LAYER_SCALE ID_LAYER_SHIFT_X ID_LAYER_SHIFT_Y ID_LAYER_GLASS \
    ID_LAYER_BLEND ID_LAYER_VISIBLE ID_LAYER_NAME ID_GROUP_NAME \
    ID_GROUP_OPACITY ID_GROUP_BLEND ID_GROUP_BLUR ID_GROUP_LIGHTING \
    ID_GROUP_SPECULAR ID_GROUP_VISIBLE ID_GROUP_SCALE ID_GROUP_SHIFT_X \
    ID_GROUP_SHIFT_Y ID_GROUP_TRANSLUCENCY ID_GROUP_SHADOW \
    ID_GROUP_SHADOW_OPACITY ID_BG_PANE ID_LAYER_PANE ID_GROUP_PANE \
    TYPE_LAYER TYPE_GROUP TYPE_BG VIS_ON VIS_OFF; do
    eval "omctest_required_value=\$$omctest_required_id"
    [ -n "$omctest_required_value" ] || {
        printf 'lib.test.icedit: %s did not import from lib_icedit.py\n' \
            "$omctest_required_id" >&2
        exit 1
    }
done
unset omctest_required_id omctest_required_value
