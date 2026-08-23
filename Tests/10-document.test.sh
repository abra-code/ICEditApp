#!/bin/sh
# Tests/10-document.test.sh - ICEdit's document lifecycle.
#
# The spine of the applet: what a new document is, what opening a .icon bundle
# puts in the window, that editing goes to a working copy and not to the file on
# disk, and the three ways a document reaches disk again - Save over the
# original, Save chaining to Save As when there is no original, and Save As
# itself, including its canceled path.
#
# Window close, external-change detection and cleanup are in 20-close; the layer
# table is in 30-layers. Nothing below should be read as evidence about those.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

# The sample document is one unnamed group holding two glass SVG layers over an
# automatic gradient, and open_sample rebuilds it for every section that wants
# one. Square is topmost because icedit's add_svg prepends, and the row-order
# assertions in section 3 depend on that.

section "1. a new untitled document"
reset_document
omc_object ""
omc_run ICEdit.main
check_status "the handler succeeded"        0
check "nothing on disk yet"                 ""              "$(original)"
check "a working copy was made"             "Untitled.icon" "$(/usr/bin/basename "$(work_icon)")"
check_exists "and it is a real bundle"      "$(work_icon)/icon.json"
# Empty here is the point, and section 2 is its positive control: the same
# oracle reads two layer names out of the sample document.
check "with no layers in it"                "0"             "$(icon_layer_count "$(work_icon)")"
check "but with a background fill"          '{"automatic-gradient":"extended-srgb:0.00000,0.53333,1.00000,1.00000"}' \
                                                            "$(icon_fill "$(work_icon)")"
# One row, not zero: get_layer_rows always appends the Background row, and the
# background is a real selectable thing in this applet rather than a heading.
check "the table shows the background only" "1"             "$(ui_row_count $ID_LAYER_LIST)"
check "and names it"                        "Background"    "$(row_cell 1 $COL_NAME)"
check "a new document is not dirty"         ""              "$(dirty)"
check "titled Untitled"                     "Untitled"      "$(ui_title)"
check "and says so"                         "New icon"      "$(ui_value $ID_STATUS)"
check "the preview pane got a real file"    "yes"           "$([ -f "$(ui_value $ID_PREVIEW)" ] && echo yes || echo no)"

section "2. opening an existing .icon bundle"
reset_document
# Dirtied first, so "clean on open" has something to clear. Without this the
# check asserts the state reset_document already set, and passes on a handler
# that never calls mark_clean at all - which matters in production, because
# PB_DIRTY is keyed on the window and a window opening a SECOND document is
# exactly where mark_clean earns its keep.
pb_set dirty 1
sample="$(make_sample_icon)"
omc_object "$sample"
omc_run ICEdit.main
check_status "the handler succeeded"        0
check "the original was adopted"            "$sample"       "$(original)"
check "clean on open"                       ""              "$(dirty)"
# The edit target must be a COPY in the scratch tree. If these two were ever the
# same path every unsaved edit would already be on the user's disk, which is the
# single worst thing this applet could do.
check "the working copy is not the original" "no"           "$([ "$(work_icon)" = "$sample" ] && echo yes || echo no)"
check "and it lives in the scratch tree"    "yes"           "$([ "$(work_icon)" != "${work_icon#$(work_dir)/}" ] && echo yes || echo no)"
check "it keeps the document's name"        "Sample.icon"   "$(/usr/bin/basename "$(work_icon)")"
check "both layers came across"             "2"             "$(icon_layer_count "$(work_icon)")"
check "and both assets"                     "$(printf 'Circle.svg\nSquare.svg')" "$(icon_assets "$(work_icon)")"
# A hash of the original's icon.json, taken at load, is what 20-close's
# external-change detection compares against later.
check "the original was fingerprinted"      "yes"           "$([ -n "$(original_hash)" ] && echo yes || echo no)"

section "3. what opening puts in the window"
# Four rows: the two layers, then their group, then the background. Layers are
# listed above the group that owns them, topmost layer first.
check "every row reached the table"         "4"             "$(ui_row_count $ID_LAYER_LIST)"
check "topmost layer first"                 "Square"        "$(row_cell 1 $COL_NAME)"
check "then the one below it"               "Circle"        "$(row_cell 2 $COL_NAME)"
check "then the group that owns them"       "Group"         "$(row_cell 3 $COL_NAME)"
check "and the background last"             "Background"    "$(row_cell 4 $COL_NAME)"
# A layer's type cell is column 2 and its column 1 is the indent; a group's is
# column 1. ICEdit.layer.select depends on exactly this to tell them apart.
check "a layer is indented"                 ""              "$(row_cell 1 $COL_INDENT)"
check "and typed in the type column"        "$TYPE_LAYER"   "$(row_cell 1 $COL_TYPE)"
check "a group is typed in column one"      "$TYPE_GROUP"   "$(row_cell 3 $COL_INDENT)"
check "visible layers show the open eye"    "$VIS_ON"       "$(row_cell 1 $COL_VISIBILITY)"
check "titled after the document"           "Sample.icon"   "$(ui_title)"
check "the status line names it"            "Loaded Sample.icon" "$(ui_value $ID_STATUS)"

section "4. an object that is not a .icon falls back to a new document"
# The positive control for section 2's guard: same handler, same variable set,
# and the ONLY difference is that the path is not an icon bundle.
reset_document
omc_object "$(added_layer_svg)"
omc_run ICEdit.main
check_status "the handler succeeded"        0
check "the SVG was not adopted"             ""              "$(original)"
check "an untitled document was made"       "Untitled.icon" "$(/usr/bin/basename "$(work_icon)")"
check "titled Untitled"                     "Untitled"      "$(ui_title)"

section "5. editing goes to the working copy, not to the file on disk"
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
check_status "the layer was added"          0
check "the working copy has three layers"   "3"             "$(icon_layer_count "$(work_icon)")"
check "the document became dirty"           "1"             "$(dirty)"
# The whole point of the working copy. Section 6 is the positive control: the
# same oracle reads three layers off the original once Save has run.
check "the original on disk is untouched"   "2"             "$(icon_layer_count "$sample")"

section "6. Save writes the working copy over the original"
before_hash="$(original_hash)"
omc_run ICEdit.save
check_status "the handler succeeded"        0
check "the edit reached the disk"           "3"             "$(icon_layer_count "$sample")"
check "the document is clean again"         ""              "$(dirty)"
check "and it is still the same document"   "$sample"       "$(original)"
check "the fingerprint was refreshed"       "no"            "$([ "$(original_hash)" = "$before_hash" ] && echo yes || echo no)"
check "the status line confirms it"         "Saved Sample.icon" "$(ui_value $ID_STATUS)"
# Save must not raise a dialog when it already knows where the document lives.
check "no Save As was needed"               "0"             "$(chain_asked ICEdit.save.as)"

section "7. Save on a never-saved document chains to Save As"
reset_document
omc_object ""
omc_run ICEdit.main
omc_run ICEdit.save
check_status "the handler succeeded"        0
check "Save As was asked for"               "1"             "$(chain_asked ICEdit.save.as)"
check "and it is the pending request"       "1"             "$(chain_requested ICEdit.save.as)"
# Nothing was written anywhere, because nowhere is where it would have gone.
check "the document is still unsaved"       ""              "$(original)"

section "8. Save As writes to the chosen path and adopts it"
chains_reset
omc_dialog_answer save_as "$OMCTEST_WORK/Chosen.icon"
omc_run ICEdit.save.as
check_status "the handler succeeded"        0
check_exists "the document is on disk"      "$OMCTEST_WORK/Chosen.icon/icon.json"
check "as a readable icon"                  "0"             "$(icon_layer_count "$OMCTEST_WORK/Chosen.icon")"
check "the new path became the original"    "$OMCTEST_WORK/Chosen.icon" "$(original)"
check "the document is clean"               ""              "$(dirty)"
check "and it was fingerprinted"            "yes"           "$([ -n "$(original_hash)" ] && echo yes || echo no)"
check "the status line names the file"      "Saved Chosen.icon" "$(ui_value $ID_STATUS)"
# setTitleWithRepresentedFilename: is journaled but not replayed into the
# virtual window, so it is asserted through the journal rather than ui_title.
check "the window got the represented file" "1" "$(ui_calls 'omc_invoke.setTitleWithRepresentedFilename:')"

section "9. Save As supplies the .icon extension when the user does not"
reset_document
omc_object ""
omc_run ICEdit.main
omc_dialog_answer save_as "$OMCTEST_WORK/NoExtension"
omc_run ICEdit.save.as
check_absent "nothing was written bare"     "$OMCTEST_WORK/NoExtension"
check_exists "the extension was added"      "$OMCTEST_WORK/NoExtension.icon/icon.json"
check "and the full path was adopted"       "$OMCTEST_WORK/NoExtension.icon" "$(original)"

section "10. a canceled Save As leaves the document alone"
open_sample > /dev/null
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
before_original="$(original)"
# An empty dialog answer is how omctest spells Cancel: the whole OMC_DLG_SAVE_AS
# family is unset, exactly as the engine leaves it.
omc_dialog_answer save_as ""
omc_run ICEdit.save.as
check_status "the handler succeeded"        0
check "the document was not re-homed"       "$before_original" "$(original)"
check "and it is still dirty"               "1"             "$(dirty)"
check "the working copy survived"           "yes"           "$([ -d "$(work_icon)" ] && echo yes || echo no)"
check "the status line says so"             "Save cancelled" "$(ui_value $ID_STATUS)"

section "11. ICEdit.open loads a second document into an open window"
# The other loading path, and the one a user reaches through File > Open. It is
# not ICEdit.main: main is the launch handler and open.py is what runs when a
# window already exists, so everything below is about REPLACING the document in
# a live window rather than about starting one.
open_sample First.icon > /dev/null
second="$(make_sample_icon Second.icon)"
omc_object "$second"
omc_run ICEdit.open
check_status "the handler succeeded"        0
check "the new document was adopted"        "$second"       "$(original)"
check "with a working copy of its own"      "Second.icon"   "$(/usr/bin/basename "$(work_icon)")"
check "it is clean"                         ""              "$(dirty)"
check "and fingerprinted"                   "yes"           "$([ -n "$(original_hash)" ] && echo yes || echo no)"
check "the table was rebuilt"               "4"             "$(ui_row_count $ID_LAYER_LIST)"
check "the title followed"                  "Second.icon"   "$(ui_title)"
check "and the status line says so"         "Opened Second.icon" "$(ui_value $ID_STATUS)"

section "12. ICEdit.open shows the background pane, which ICEdit.main does not"
# A real disagreement between the two loaders, pinned rather than smoothed over:
# open.py populates and reveals the background pane, while the same block in
# main.py is commented out (ICEdit.main.py, the block under "Show background
# pane with initial values"). So a document reached through File > Open opens
# with the inspector filled in and the same document reached at launch opens
# with it blank. Whichever way that is settled, one of these two checks has to
# be revisited, which is the point of asserting both.
check "Open reveals the background pane"    "1"             "$(ui_visible $ID_BG_PANE)"
check "with the fill read out"              "auto-gradient" "$(ui_value $ID_BG_FILL)"
check "and the layer pane hidden"           "0"             "$(ui_visible $ID_LAYER_PANE)"
check "and no selection carried over"       ""              "$(selected_layer)"
reset_document
omc_object "$second"
omc_run ICEdit.main
check "but launch leaves the pane untouched" ""             "$(ui_visible $ID_BG_PANE)"

section "13. ICEdit.open refuses an object that is not a .icon"
first="$(open_sample First.icon)"
omc_object "$(added_layer_svg)"
omc_run ICEdit.open
check_status "the handler stops cleanly"    0
check "and says so"                         "Not a valid .icon bundle" "$(ui_value $ID_STATUS)"
# The document already open must survive a refused Open - section 11 is the
# positive control, where a good one replaces it.
check "the open document was left alone"    "$first"        "$(original)"
check "and so was its working copy"         "First.icon"    "$(/usr/bin/basename "$(work_icon)")"

section "14. ICEdit.open warns before discarding unsaved changes"
first="$(open_sample First.icon)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
old_work="$(work_icon)"
# Cancel is anything but the OK slot; here OK is "Discard and Open".
alert_answer 1
omc_object "$second"
omc_run ICEdit.open
check_status "the handler stops cleanly"    0
check "the user was asked"                  "1"             "$(alerts_mention 'Unsaved Changes')"
check "Cancel kept the first document"      "$first"        "$(original)"
check "with its unsaved edit intact"        "3"             "$(icon_layer_count "$(work_icon)")"
check "and still dirty"                     "1"             "$(dirty)"
alerts_reset
alert_answer 0
omc_object "$second"
omc_run ICEdit.open
check "Discard and Open went through"       "$second"       "$(original)"
check "the edit was discarded"              "2"             "$(icon_layer_count "$(work_icon)")"
check "the document is clean"               ""              "$(dirty)"
# The abandoned working copy does not survive into $TMPDIR - unlike a window
# close, which does leak one (20-close section 4). Stated as the guarantee
# rather than as a test of open.py's explicit rmtree: create_working_copy wipes
# the whole work directory before repopulating it, so this would hold even with
# that teardown deleted. It is the user-visible invariant that is worth having.
check_absent "and the old working copy went" "$old_work"
check "leaving exactly one document behind" "1" \
    "$(/bin/ls "$(work_dir)" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "15. KNOWN DEFECT: Save destroys the document if the working copy is gone"
# lib_icedit.save_icon_to removes the destination BEFORE it copies:
#
#     if os.path.exists(dest_path):
#         shutil.rmtree(dest_path)
#     shutil.copytree(work_icon, dest_path)
#
# and the only guard above it is "if not work_icon", which tests the pasteboard
# STRING, not whether the directory it names is still there. $TMPDIR is swept on
# reboot and by tmp cleaners, and the pasteboard entry outlives the files - so a
# window left open across a sweep is a live document whose working copy no
# longer exists. Pressing Save then deletes the user's .icon bundle and raises
# on the copytree that was supposed to replace it.
#
# The document is not corrupted, it is GONE, and the status line still shows the
# previous message, so the first the user knows of it is an empty Finder window.
# This is the worst thing in the applet.
#
# The fix is one line: refuse when os.path.isdir(work_icon) is false, the way
# every other handler tests the paths it is about to act on. Copy to a temporary
# sibling and rename over the destination if the replace itself should be atomic.
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
check "the edit is in the working copy"     "3"             "$(icon_layer_count "$(work_icon)")"
check_exists "and the document is on disk"  "$sample/icon.json"
# The sweep. The pasteboard still names the working copy, exactly as it would
# after a reboot with the window still open.
/bin/rm -rf "$(work_dir)"
check "the applet still thinks it has one"  "yes"           "$([ -n "$(work_icon)" ] && echo yes || echo no)"
omc_run ICEdit.save
check_status "DEFECT: Save raises"          1
check_absent "DEFECT: and the user's document is gone" "$sample"
# Not merely emptied or truncated - the whole bundle directory was removed, and
# the oracle says so rather than reporting an empty document.
check "DEFECT: not even readable as one"    "UNREADABLE"    "$(icon_layer_count "$sample")"
# It raised before reaching any status write, so nothing on screen changed: the
# status line still carries the message the layer add left there.
check "DEFECT: with nothing said about it"  "Added layer 'Local'" "$(ui_value $ID_STATUS)"

section "16. KNOWN DEFECT: a malformed icon.json crashes the open handler"
# lib_icedit.load_icon_json calls json.load with no try, so a bundle whose
# icon.json does not parse takes ICEdit.main down with an unhandled
# JSONDecodeError. The handler even has a message for this case -
# set_status("Failed to load icon.json") - but it is unreachable: the only way
# to reach the else branch is an ABSENT icon.json, and the guard at the top of
# main.py has already excluded that.
#
# A hand-edited icon, a truncated copy, or a file from a newer Icon Composer
# would all land here. The fix is to catch ValueError in load_icon_json and
# return None, which is what every caller already tests for.
reset_document
malformed="$OMCTEST_WORK/Malformed.icon"
/bin/rm -rf "$malformed"
/bin/mkdir -p "$malformed/Assets"
printf '{ this is not json' > "$malformed/icon.json"
omc_object "$malformed"
omc_run ICEdit.main
check_status "DEFECT: the handler raises"   1
# It got far enough to adopt the document and copy it, so the window is left
# with a working copy it cannot read and no message explaining why.
check "the document was adopted first"      "$malformed"    "$(original)"
check "DEFECT: and nothing was said"        ""              "$(ui_value $ID_STATUS)"
check "DEFECT: the message it has is unreachable" "0" \
    "$(ui_calls "$ID_STATUS.Failed to load")"
# The positive control that this is about the JSON and not about the bundle
# shape: the same directory with a PARSEABLE icon.json opens normally.
reset_document
printf '{"fill": "none", "groups": [], "supported-platforms": {"squares": "shared"}}' \
    > "$malformed/icon.json"
omc_object "$malformed"
omc_run ICEdit.main
check_status "a parseable one opens"        0
check "and reports itself"                  "Loaded Malformed.icon" "$(ui_value $ID_STATUS)"

section "cumulative: the window never wrote to a view id it does not declare"
# unknown_ids.log accumulates across the whole file, so this one assertion covers
# every section above it. The line before it is its positive control: if the
# bundle's id extraction had produced nothing the detector would be silently
# inert, and the assertion could not fail.
check "the id set was extracted"            "yes"           "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"
check "no undeclared ids"                   ""              "$(ui_unknown_writes)"
check "no bare value clobbered a table"     ""              "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
