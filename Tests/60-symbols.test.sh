#!/bin/sh
# Tests/60-symbols.test.sh - the SF Symbols and Material Symbols pickers.
#
# Both pickers are separate ACTIONUI_WINDOWs raised over the document rather
# than controls inside it, so every section below enters one with
# omc_child_sheet: the picker gets its own window uuid, the document's uuid
# arrives as OMC_PARENT_DIALOG_GUID, and lib_icedit's DOCUMENT_UUID resolves to
# the parent - which is the only reason the add handlers can find the icon the
# user has open. Getting that wrong is silent: every pasteboard read would
# return empty and every check would read as "no icon open".
#
# The two pickers are near-copies of each other with different data sources, and
# they are tested as such. What differs is where the names come from: SF Symbols
# reads a names.txt shipped in the bundle, Material Symbols reads a .codepoints
# file that update_icedit.sh provisions and that is NOT in the
# repository - so section 9 states that as a precondition rather than passing
# quietly on a checkout that never ran the download.
#
# Not covered here, and not covered anywhere: the "Material Symbols not
# installed" branch of ICEdit.materialsymbols.init, which is the branch a fresh
# checkout hits. Both handlers derive the data path from OMC_APP_BUNDLE_PATH,
# which the harness controls, so the branch cannot be reached without modifying
# the bundle. 80-library section 9 covers the library half of it - load_names
# answering empty for a missing file - and the handler half is untested.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

section "1. raising the picker is the window's job, not the script's"
# ICEdit.sfsymbols exists only to carry the ACTIONUI_WINDOW; OMC presents the
# window and the script body is empty. It still has to exist and still has to
# exit cleanly, which is what a missing file would fail here with 127.
open_sample > /dev/null
omc_run ICEdit.sfsymbols
check_status "the script resolved and ran"    0
omc_run ICEdit.materialsymbols
check_status "and so did the other one"       0

section "2. the SF Symbols picker fills its list"
open_sample > /dev/null
document="$OMC_ACTIONUI_WINDOW_UUID"
omc_child_sheet SFSymbols
check "the sheet knows its parent"            "$document"   "$OMC_PARENT_DIALOG_GUID"
check "and has a window of its own"           "no"          "$([ "$OMC_ACTIONUI_WINDOW_UUID" = "$document" ] && echo yes || echo no)"
omc_run ICEdit.sfsymbols.init
check_status "the handler succeeded"          0
# Loaded straight from the file with omc_list_set_items_from_file, so the count
# in the status line and the length of names.txt are the same number by two
# different routes.
symbol_count="$(/usr/bin/awk 'END { print NR }' \
    "$OMC_APP_BUNDLE_PATH/Contents/Helpers/glyphsvg/names.txt")"
check "every name reached the list"           "1"           "$(ui_calls "$PICK_LIST.omc_list_set_items_from_file")"
check "and the count is the file's own"       "$symbol_count symbols" "$(ui_value $PICK_STATUS)"
# Heavy renders legibly at icon size, which is the reason for overriding the
# document's declared default at all.
check "the weight defaults to heavy"          "heavy"       "$(ui_value $PICK_WEIGHT)"
# And feed it back, the way the engine would on the next dispatch. Without this
# every render below runs at glyphsvg's own "regular" fallback, so the weight
# the applet actually ships would never be exercised at all.
adopt_window_values "$PICK_WEIGHT"

section "3. filtering narrows the list and says by how much"
omc_control "$PICK_SEARCH" "star"
omc_run ICEdit.sfsymbols.filter
check_status "the handler succeeded"          0
filtered="$(ui_value $PICK_STATUS)"
check "the list was rebuilt from stdin"       "1"           "$(ui_calls "$PICK_LIST.omc_list_set_items_from_stdin")"
check "and it is smaller than the whole set"  "yes" \
    "$([ "${filtered% symbols}" -lt "$symbol_count" ] && echo yes || echo no)"
check "but not empty"                         "yes" \
    "$([ "${filtered% symbols}" -gt 0 ] && echo yes || echo no)"

section "4. clearing the search restores every name"
omc_control "$PICK_SEARCH" ""
omc_run ICEdit.sfsymbols.filter
check "the whole set came back"               "$symbol_count symbols" "$(ui_value $PICK_STATUS)"

section "5. a search matching nothing empties the list rather than failing"
omc_control "$PICK_SEARCH" "zzzzznotasymbol"
omc_run ICEdit.sfsymbols.filter
check_status "the handler succeeded"          0
check "and says so honestly"                  "0 symbols"   "$(ui_value $PICK_STATUS)"

section "5b. the SF picker ranks a whole-word match above a partial one"
# ICEdit.sfsymbols.filter.py carries its OWN copy of the ranking rule rather
# than calling lib_material's - and it splits words on "." where lib_material
# splits on "_", so 80-library section 9 says nothing about this one. The rule
# is the same: a term matching a whole word of the name beats one matching only
# part of a word.
#
# The pairs below are chosen so that ALPHABETICAL order would give the opposite
# answer, which is the only way the word-rank tier is observable. Sorted by
# name, "autostartstop" precedes "star" and "airplay.audio" precedes "play"; a
# filter with no word-rank tier would list them that way round.
rank_of() { # <symbol-name> -> its 1-based position in the current list
    ui_rows "$PICK_LIST" | /usr/bin/grep -n -x -e "$1" | /usr/bin/cut -d: -f1
}
omc_control "$PICK_SEARCH" "star"
omc_run ICEdit.sfsymbols.filter
whole_word="$(rank_of star)"
fragment="$(rank_of autostartstop)"
check "both names matched"                    "yes" \
    "$([ -n "$whole_word" ] && [ -n "$fragment" ] && echo yes || echo no)"
check "the whole word ranks first"            "yes" \
    "$([ "${whole_word:-0}" -lt "${fragment:-0}" ] && echo yes || echo no)"
omc_control "$PICK_SEARCH" "play"
omc_run ICEdit.sfsymbols.filter
whole_word="$(rank_of play)"
fragment="$(rank_of airplay.audio)"
check "and again on a second pair"            "yes" \
    "$([ -n "$whole_word" ] && [ -n "$fragment" ] && echo yes || echo no)"
check "the whole word ranks first"            "yes" \
    "$([ "${whole_word:-0}" -lt "${fragment:-0}" ] && echo yes || echo no)"
# The positive control for the two "first" checks: alphabetical really is the
# other way round, so neither is passing because the list happens to be sorted.
check "sorted by name it would be the reverse" "autostartstop" \
    "$(printf 'star\nautostartstop\n' | /usr/bin/sort | /usr/bin/sed -n 1p)"

section "6. selecting a symbol renders it"
omc_control "$PICK_SEARCH" ""
pick_symbol ICEdit.sfsymbols.select "star.fill"
check_status "the handler succeeded"          0
check "the preview points at the render"      "$(sfsymbol_svg)" "$(ui_value $PICK_PREVIEW)"
check_exists "and the render is a real file"  "$(sfsymbol_svg)"
check "which is SVG"                          "1"           "$(/usr/bin/grep -c '<svg' "$(sfsymbol_svg)")"

section "7. adding the selected symbol reaches the document behind the sheet"
before_preview="$(ui_value $ID_PREVIEW "$OMC_PARENT_DIALOG_GUID")"
pick_symbol ICEdit.sfsymbols.add "star.fill"
check_status "the handler succeeded"          0
check "the layer is in the document"          "3"           "$(icon_layer_count "$(work_icon)")"
check "named after the symbol"                "star.fill"   "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 1p)"
check "the document was marked dirty"         "1"           "$(dirty)"
check "the sheet reported it"                 "Added 'star.fill' as layer" "$(ui_value $PICK_STATUS)"
# The refresh has to target the PARENT window: a table rebuild sent to the
# sheet's own uuid would go to a window with no table in it, and the user would
# watch nothing happen. Passing the parent uuid explicitly is how a sheet
# asserts about the window underneath it.
check "the document's table was rebuilt"      "5"           "$(ui_row_count $ID_LAYER_LIST "$OMC_PARENT_DIALOG_GUID")"
# render_preview alternates between two filenames so ActionUI.Image sees a path
# it has not seen before; a re-render to the SAME path would leave the user
# looking at the old artwork. So the assertion is that the path MOVED, not just
# that something was written.
check "and its preview re-rendered"           "no" \
    "$([ "$(ui_value $ID_PREVIEW "$OMC_PARENT_DIALOG_GUID")" = "$before_preview" ] && echo yes || echo no)"
check "to a file that is really there"        "yes" \
    "$([ -f "$(ui_value $ID_PREVIEW "$OMC_PARENT_DIALOG_GUID")" ] && echo yes || echo no)"

section "8. the picker refuses the three ways it can have nothing to add"
# Each of these is a separate early return, and each writes its own message to
# the sheet's status line rather than failing silently.
omc_table_cell "$PICK_LIST" 1 ""
omc_run ICEdit.sfsymbols.add
check_status "no selection is not an error"   0
check "and it says so"                        "No symbol selected" "$(ui_value $PICK_STATUS)"
/bin/rm -f "$(sfsymbol_svg)"
pick_symbol ICEdit.sfsymbols.add "star.fill"
check_status "no render is not an error"      0
# The only non-ASCII byte in this suite, and it has to be here: the dash is the
# applet's own U+2014, and an expected value is data copied from the app rather
# than prose. Replacing it with a hyphen would make the check fail.
check "and it says so"                        "No SVG rendered — select a symbol first" "$(ui_value $PICK_STATUS)"
omc_leave_sheet
reset_document
omc_child_sheet SFSymbols
pick_symbol ICEdit.sfsymbols.select "star.fill"
pick_symbol ICEdit.sfsymbols.add "star.fill"
check_status "no open document is not an error" 0
check "and it says so"                        "No icon open in ICEdit" "$(ui_value $PICK_STATUS)"
omc_leave_sheet

section "9. the Material Symbols picker fills its list"
# The font and its metadata are provisioned by update_icedit.sh and are
# deliberately not in the repository, so this is a real precondition rather than
# a formality. Asserted here, where the data is first needed, so a checkout that
# skipped the download fails once and says which script to run - instead of
# producing eight puzzling failures further down.
check "precondition: Material Symbols data is installed" "yes" \
    "$(icedit_is 'os.path.isfile(lib_material.CODEPOINTS_FILE)')"
open_sample > /dev/null
omc_child_sheet MaterialSymbols
omc_run ICEdit.materialsymbols.init
check_status "the handler succeeded"          0
material_count="$(icedit_eval 'len(lib_material.load_names())')"
check "every name reached the list"           "1"           "$(ui_calls "$PICK_LIST.omc_list_set_items_from_stdin")"
check "and the count is the font's own"       "$material_count symbols" "$(ui_value $PICK_STATUS)"
# Bold is the heaviest weight the shipped Rounded variant carries.
check "the weight defaults to bold"           "bold"        "$(ui_value $PICK_WEIGHT)"
# Fed back for the same reason as the SF picker's. PICK_FILL is left as the
# document declares it - unset, which the handler reads as unfilled.
adopt_window_values "$PICK_WEIGHT"

section "10. Material filtering searches tags, not only names"
# The distinguishing feature of this picker: "automobile" is not a substring of
# any Material Symbol name, and matches only through the metadata's tags. If the
# metadata failed to load, filter_names would fall back to names alone and this
# would come back empty - which is why the check is for a hit rather than for a
# count.
omc_control "$PICK_SEARCH" "automobile"
omc_run ICEdit.materialsymbols.filter
check_status "the handler succeeded"          0
tagged="$(ui_value $PICK_STATUS)"
check "a concept search finds symbols"        "yes" \
    "$([ "${tagged% symbols}" -gt 0 ] && echo yes || echo no)"
check "and not all of them"                   "yes" \
    "$([ "${tagged% symbols}" -lt "$material_count" ] && echo yes || echo no)"

section "11. selecting and adding a Material Symbol"
omc_control "$PICK_SEARCH" ""
pick_symbol ICEdit.materialsymbols.select "home"
check_status "the handler succeeded"          0
check "the preview points at the render"      "$(matsymbol_svg)" "$(ui_value $PICK_PREVIEW)"
check "which is SVG"                          "1"           "$(/usr/bin/grep -c '<svg' "$(matsymbol_svg)")"
pick_symbol ICEdit.materialsymbols.add "home"
check_status "the handler succeeded"          0
check "the layer is in the document"          "3"           "$(icon_layer_count "$(work_icon)")"
check "named after the symbol"                "home"        "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 1p)"
check "the document was marked dirty"         "1"           "$(dirty)"
check "and the document's table was rebuilt"  "5"           "$(ui_row_count $ID_LAYER_LIST "$OMC_PARENT_DIALOG_GUID")"
omc_leave_sheet

section "12. a picker names its render after its own window, not the document"
# Two pickers, or one picker over two documents, share a single scratch
# directory. Each render is keyed on the PICKER's window uuid, so they never
# collide; keyed on the document instead, the second picker to render would
# overwrite the artwork the first is about to add.
#
# The comparison has to be between two uuids for the SAME picker. Comparing
# sfsymbol_svg against matsymbol_svg answers "different" for any pair of uuids
# whatsoever, because those two differ by their filename prefix - it would be a
# check that cannot fail. And omc_child_sheet has to run outside a command
# substitution, or the uuid switch happens in a subshell and never reaches the
# paths being compared.
open_sample > /dev/null
omc_child_sheet SFSymbolsA
first_render="$(sfsymbol_svg)"
omc_leave_sheet
omc_child_sheet SFSymbolsB
second_render="$(sfsymbol_svg)"
omc_leave_sheet
check "two picker windows, two paths"         "no" \
    "$([ "$first_render" = "$second_render" ] && echo yes || echo no)"
# The positive control for that "no": one window always answers the same path,
# so the difference above is the uuid and not the helper being unstable.
omc_child_sheet SFSymbolsA
check "and one picker window, one path"       "yes" \
    "$([ "$(sfsymbol_svg)" = "$first_render" ] && echo yes || echo no)"
# The document underneath does not appear in either name, which is what lets the
# same picker be reopened over a different document without inheriting a render.
check "the document uuid is not in the name"  "0" \
    "$(printf '%s' "$first_render" | /usr/bin/grep -c "$OMC_PARENT_DIALOG_GUID")"
omc_leave_sheet

section "cumulative: the window never wrote to a view id it does not declare"
# unknown_ids.log accumulates across the whole file, so this one assertion covers
# every section above it, sheets included - the id set is a union across every
# ActionUI document in the bundle, so the pickers' ids are in it. The line
# before it is its positive control.
check "the id set was extracted"              "yes"         "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"
check "no undeclared ids"                     ""            "$(ui_unknown_writes)"
check "no bare value clobbered a table"       ""            "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
