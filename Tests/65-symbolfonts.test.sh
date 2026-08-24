#!/bin/sh
# Tests/65-symbolfonts.test.sh - the generic Symbol Fonts picker.
#
# Where 60-symbols covers two pickers each hardwired to one font, this one
# covers the picker that chooses its font at run time. That difference is the
# whole point of the file: the font list, the face list and the name list are
# all populated by handlers rather than declared in SymbolFonts.json, so the
# things worth asserting are the ones a static document could never get wrong.
#
# Three of those deserve naming up front, because they are the reasons the
# handlers are shaped the way they are:
#
#   - Setting a Picker's options does NOT reset its selection. ActionUI leaves
#     the old tag in place until SwiftUI notices it is gone, so every options
#     swap here must be followed by an explicit value write, and section 4
#     asserts exactly that.
#   - That resync dispatches the picker's own action, carrying whatever value
#     SwiftUI settled on. So a handler can be handed a face belonging to the
#     font the user just left. Section 6 feeds one in deliberately.
#   - The set data is provisioned by update_icedit.sh and is NOT in the
#     repository, so section 2 states that as a precondition rather than
#     letting a fresh checkout produce a dozen puzzling failures.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

# A `case` pattern's ")" closes a $( ) command substitution before the shell
# ever sees the case, so these live here as functions rather than inline.
starts_with() { # <string> <prefix> -> yes/no
    case "$1" in
        "$2"*) echo yes ;;
        *) echo no ;;
    esac
}

ends_with() { # <string> <suffix> -> yes/no
    case "$1" in
        *"$2") echo yes ;;
        *) echo no ;;
    esac
}

section "1. raising the picker is the window's job, not the script's"
# ICEdit.symbolfonts carries the ACTIONUI_WINDOW and nothing else. It still has
# to resolve and exit cleanly, which a missing script would fail here with 127.
open_sample > /dev/null
omc_run ICEdit.symbolfonts
check_status "the script resolved and ran"    0

section "2. init discovers the embedded fonts"
check "precondition: symbol font sets are installed" "yes" \
    "$(icedit_is 'len(lib_symbolfonts.list_sets()) > 0')"
open_sample > /dev/null
omc_child_sheet SymbolFonts
omc_run ICEdit.symbolfonts.init
check_status "the handler succeeded"          0
# The option list is built from what is on disk, so the count comes from the
# library rather than from a number written down here - a set added to the
# bundle later must not have to edit this test.
set_count="$(icedit_eval 'len(lib_symbolfonts.list_sets())')"
check "the font picker was populated"         "1"  "$(ui_calls "$PICK_FONT.omc_set_property")"
check "every installed set is offered"        "$set_count" \
    "$(icedit_eval 'len(json.loads(ARGV[0]))' "$(ui_prop $PICK_FONT options)")"
# Selected explicitly, not left to the placeholder in SymbolFonts.json: that
# placeholder's tag is the empty string, and a handler reading it would treat
# the picker as having no font at all.
first_set="$(icedit_eval 'lib_symbolfonts.list_sets()[0]["name"]')"
check "and one of them is selected"           "$first_set"  "$(ui_value $PICK_FONT)"
check "the name list was filled"              "1"  "$(ui_calls "$PICK_LIST.omc_list_set_items_from_stdin")"
first_names="$(icedit_eval 'len(lib_symbolfonts.load_names(lib_symbolfonts.set_info(ARGV[0]).get("codepoints")))' "$first_set")"
check "with the font's own symbol count"      "$first_names symbols" "$(ui_value $PICK_STATUS)"
adopt_window_values "$PICK_FONT" "$PICK_FACE"

section "3. a single-face font has nothing to choose, and says so"
# mdi ships one face. Disabled rather than hidden, so the control bar does not
# reflow every time the font changes.
check "mdi really has one face"               "1" \
    "$(icedit_eval 'len(lib_symbolfonts.set_info("mdi")["faces"])')"
omc_control "$PICK_FONT" "mdi"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
check "the style picker is disabled"          "0"          "$(ui_enabled $PICK_FACE)"
check "and still carries a usable face"       "regular"     "$(ui_value $PICK_FACE)"
# Only the FACE. adopt_window_values copies back what a handler WROTE, and
# nothing writes the font picker after init - so adopting it here would quietly
# revert the font to whatever init selected and undo the switch under test.
adopt_window_values "$PICK_FACE"

section "4. switching to a two-face font repoints the whole dialog"
check "fluent really has two faces"           "2" \
    "$(icedit_eval 'len(lib_symbolfonts.set_info("fluent")["faces"])')"
omc_control "$PICK_FONT" "fluent"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
check "the style picker is enabled again"     "1"         "$(ui_enabled $PICK_FACE)"
check "its options were replaced"             "2" \
    "$(icedit_eval 'len(json.loads(ARGV[0]))' "$(ui_prop $PICK_FACE options)")"
# The assertion this section exists for. Swapping options leaves the previous
# tag in place, so without an explicit write the picker would still be reading
# "regular" from mdi - which fluent happens to share, hiding the bug. The value
# is checked against the set's declared default rather than a literal, so this
# keeps meaning something if the manifest's default changes.
check "and the selection was re-anchored"     "$(icedit_eval 'lib_symbolfonts.set_info("fluent")["face"]')" \
    "$(ui_value $PICK_FACE)"
fluent_names="$(icedit_eval 'len(lib_symbolfonts.load_names(lib_symbolfonts.set_info("fluent").get("codepoints")))')"
check "the list is fluent's now"              "$fluent_names symbols" "$(ui_value $PICK_STATUS)"
check "and the stale preview was cleared"     ""            "$(ui_value $PICK_PREVIEW)"
adopt_window_values "$PICK_FACE"

section "4b. and re-anchoring is proved by a face the new font does not have"
# The check above cannot fail on its own: mdi and fluent both call their default
# face "regular", so a handler that never re-anchored would still be holding a
# tag that happens to be right. Going the other way is what bites - pick
# fluent's "filled", switch to mdi, which has no such face, and the old tag can
# only survive if nothing re-anchored it.
# omc_control sets what the handler READS; ui_value reports what a handler
# WROTE. Only the second is worth asserting here, so the input is just set.
omc_control "$PICK_FACE" "filled"
check "mdi has no such face"                  "no" \
    "$(icedit_is '"filled" in lib_symbolfonts.set_info("mdi")["faces"]')"
omc_control "$PICK_FONT" "mdi"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
check "the dangling face was replaced"        "regular"     "$(ui_value $PICK_FACE)"
adopt_window_values "$PICK_FACE"

section "4c. a font with real weights offers them, heaviest included"
# The reason this set is bundled at all. MDI and Fluent are single-weight fonts,
# so the Style picker over either can only ever offer what they have - and app
# icons generally want a heavier stroke than a UI icon font's default. Phosphor
# ships five separate static fonts, so the weight is a FACE here rather than a
# wght axis, and the picker surfaces them the same way it surfaces any face.
omc_control "$PICK_FONT" "phosphor"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
check "five faces are offered"                "5" \
    "$(icedit_eval 'len(json.loads(ARGV[0]))' "$(ui_prop $PICK_FACE options)")"
# Named explicitly rather than counted: a set that offered six LIGHT faces would
# satisfy a count and none of the intent.
check "bold is one of them"                   "yes" \
    "$(icedit_is '"bold" in [o["tag"] for o in json.loads(ARGV[0])]' "$(ui_prop $PICK_FACE options)")"
check "and fill, the heaviest"                "yes" \
    "$(icedit_is '"fill" in [o["tag"] for o in json.loads(ARGV[0])]' "$(ui_prop $PICK_FACE options)")"
# Light to heavy, so the menu reads as a ramp rather than as manifest order.
check "they run light to heavy"               "thin light regular bold fill" \
    "$(icedit_eval '" ".join(o["tag"] for o in json.loads(ARGV[0]))' "$(ui_prop $PICK_FACE options)")"
adopt_window_values "$PICK_FACE"
# And the weights are real artwork, not the same glyph relabelled.
omc_control "$PICK_FACE" "thin"
pick_symbol ICEdit.symbolfonts.select "heart"
thin_render="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"
omc_control "$PICK_FACE" "bold"
pick_symbol ICEdit.symbolfonts.select "heart"
bold_render="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"
check "thin and bold are different artwork"   "no" \
    "$([ "$thin_render" = "$bold_render" ] && echo yes || echo no)"
omc_control "$PICK_FONT" "mdi"
omc_run ICEdit.symbolfonts.font
adopt_window_values "$PICK_FACE"

section "5. an active search survives a font change"
# The search is about what the user is looking for, not about which font
# supplies it. Clearing the list while the field still reads "camera" would be
# the confusing half of either choice.
omc_control "$PICK_SEARCH" "camera"
omc_control "$PICK_FONT" "mdi"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
searched="$(ui_value $PICK_STATUS)"
# Recomputed for the font actually under test rather than reusing section 2's
# baseline: that one came from list_sets()[0], which is mdi only because
# "Material Design Icons" happens to sort before "Microsoft Fluent System Icons".
mdi_names="$(icedit_eval 'len(lib_symbolfonts.load_names(lib_symbolfonts.set_info("mdi").get("codepoints")))')"
check "the list is filtered, not whole"       "yes" \
    "$([ "${searched% symbols}" -lt "$mdi_names" ] && echo yes || echo no)"
check "but not empty"                         "yes" \
    "$([ "${searched% symbols}" -gt 0 ] && echo yes || echo no)"
omc_control "$PICK_SEARCH" ""
adopt_window_values "$PICK_FACE"

section "6. a face belonging to the previous font is refused"
# Fed in exactly as the engine can deliver it: mdi selected, but id 11 still
# holding fluent's "filled". The handler must fall back to a face mdi has
# instead of asking glyphsvg for one it does not.
omc_control "$PICK_FONT" "mdi"
omc_control "$PICK_FACE" "filled"
pick_symbol ICEdit.symbolfonts.select "home"
check_status "the handler succeeded"          0
check "the preview was still rendered"        "yes" \
    "$([ -n "$(ui_value $PICK_PREVIEW)" ] && echo yes || echo no)"
check "and the status carries no error"       "no" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Error:")"
# The library rule underneath it, asserted directly so a regression names itself.
check "an unknown face resolves to a real one" "regular" \
    "$(icedit_eval 'lib_symbolfonts.resolve_face(lib_symbolfonts.set_info("mdi"), "filled")')"
check "and a known one is left alone"         "filled" \
    "$(icedit_eval 'lib_symbolfonts.resolve_face(lib_symbolfonts.set_info("fluent"), "filled")')"

section "7. filtering ranks the name you typed first"
# MDI separates words with "-", not "_". Splitting on both is what makes the
# whole-word tier work at all here, and the exact-match tier is what keeps the
# typed name from sinking into the resulting tie - hundreds of names long for a
# term like "cog".
omc_control "$PICK_FONT" "mdi"
omc_control "$PICK_FACE" "regular"
omc_control "$PICK_SEARCH" "cog"
omc_run ICEdit.symbolfonts.filter
check_status "the handler succeeded"          0
check "the list was rebuilt from stdin"       "yes" \
    "$([ "$(ui_calls "$PICK_LIST.omc_list_set_items_from_stdin")" -gt 0 ] && echo yes || echo no)"
check "the exact name leads"                  "cog"  "$(ui_rows $PICK_LIST | /usr/bin/sed -n 1p)"
# The positive control: alphabetically "account-cog" precedes "cog", so this is
# not passing because the list happens to be sorted.
check "sorted by name it would not"           "account-cog" \
    "$(printf 'cog\naccount-cog\n' | /usr/bin/sort | /usr/bin/sed -n 1p)"
# And the whole-word tier itself: "car" as a word beats "car" inside "scorecard".
omc_control "$PICK_SEARCH" "car"
omc_run ICEdit.symbolfonts.filter
rank_of() { # <symbol-name> -> its 1-based position in the current list
    ui_rows "$PICK_LIST" | /usr/bin/grep -n -x -e "$1" | /usr/bin/cut -d: -f1
}
whole_word="$(rank_of car-back)"
fragment="$(rank_of account-card)"
check "both names matched"                    "yes" \
    "$([ -n "$whole_word" ] && [ -n "$fragment" ] && echo yes || echo no)"
check "the whole word ranks first"            "yes" \
    "$([ "${whole_word:-0}" -lt "${fragment:-0}" ] && echo yes || echo no)"
check "sorted by name it would be the reverse" "account-card" \
    "$(printf 'car-back\naccount-card\n' | /usr/bin/sort | /usr/bin/sed -n 1p)"

section "8. a search matching nothing empties the list rather than failing"
omc_control "$PICK_SEARCH" "zzzzznotasymbol"
omc_run ICEdit.symbolfonts.filter
check_status "the handler succeeded"          0
check "and says so honestly"                  "0 symbols"   "$(ui_value $PICK_STATUS)"
omc_control "$PICK_SEARCH" ""

section "9. selecting renders, and a name the font lacks is reported"
omc_control "$PICK_FONT" "fluent"
omc_control "$PICK_FACE" "regular"
pick_symbol ICEdit.symbolfonts.select "home"
check_status "the handler succeeded"          0
rendered="$(ui_value $PICK_PREVIEW)"
check "the preview points at an SVG"          "yes" \
    "$(ends_with "$rendered" ".svg")"
check "and the file exists"                   "yes" \
    "$([ -s "$rendered" ] && echo yes || echo no)"
# An MDI name, asked of fluent. Reported on the status line, not raised as a
# failure: the picker must survive a stale selection surviving a font change.
pick_symbol ICEdit.symbolfonts.select "ab-testing"
check_status "the handler still succeeded"    0
check "the status reports the miss"           "yes" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Error:")"
# glyphsvg prefixes its own diagnostics with "Error: " and the handler prefixes
# again for the status line; one is a message, two is a bug.
check "and does not stutter the prefix"       "no" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Error: Error:")"

section "10. the two faces of one font are different artwork"
# fluent points both faces at a single .ttf and separates them only by
# codepoint table, so a manifest that got the tables wrong would render the same
# glyph twice and every other check here would still pass.
outline="$(icedit_eval 'lib_symbolfonts.set_info("fluent", "regular")["codepoints"]')"
filled="$(icedit_eval 'lib_symbolfonts.set_info("fluent", "filled")["codepoints"]')"
check "the faces read different tables"       "yes" \
    "$([ "$outline" != "$filled" ] && echo yes || echo no)"
check "and both tables exist"                 "yes" \
    "$([ -s "$outline" ] && [ -s "$filled" ] && echo yes || echo no)"
check "'home' has a different codepoint in each" "yes" \
    "$([ "$(/usr/bin/awk '$1 == "home" { print $2 }' "$outline")" \
        != "$(/usr/bin/awk '$1 == "home" { print $2 }' "$filled")" ] && echo yes || echo no)"

section "11. adding puts the selected symbol in the document"
# Leave section 2's sheet first. open_sample called from inside a sheet opens
# the document in the sheet's own context, so the picker raised over it would
# have a stale parent - and every pasteboard read would answer "no icon open".
omc_leave_sheet
open_sample > /dev/null
omc_child_sheet SymbolFonts
omc_run ICEdit.symbolfonts.init
omc_control "$PICK_FONT" "mdi"
omc_control "$PICK_FACE" "regular"
omc_control "$PICK_SEARCH" ""
adopt_window_values "$PICK_FACE"
pick_symbol ICEdit.symbolfonts.select "home"
check_status "select succeeded"               0
pick_symbol ICEdit.symbolfonts.add "home"
check_status "add succeeded"                  0
check "the layer is in the document"          "3"           "$(icon_layer_count "$(work_icon)")"
check "named after the symbol"                "home"        "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 1p)"
check "the document was marked dirty"         "1"           "$(dirty)"
# The add handler renders its own SVG rather than reusing the preview's, so both
# exist and are distinct files.
check "add rendered its own file"             "yes" \
    "$([ -s "$(symbolfont_add_svg)" ] && echo yes || echo no)"
check "which is not the preview's"            "no" \
    "$([ "$(symbolfont_add_svg)" = "$(symbolfont_svg)" ] && echo yes || echo no)"

section "11b. a symbol that will not render is not added under some other artwork"
# The defect this section exists for. glyphsvg opens its output only after a
# glyph is serialized, so a FAILED render leaves the PREVIOUS SVG on disk intact.
# An add handler that reused the preview handler's file would therefore add the
# previously previewed artwork under the newly selected name - silently, with the
# right layer name on the wrong picture.
#
# The font is changed with omc_control alone, WITHOUT running the font handler.
# That is deliberate: the font handler deletes the stale render as a second line
# of defense, and running it here would hide whether the first line works. It is
# also the real state whenever handlers overlap - env is a dispatch-time
# snapshot, so a select or an add can carry a font the cleanup has not caught up
# with yet.
layers_before="$(icon_layer_count "$(work_icon)")"
pick_symbol ICEdit.symbolfonts.select "home"
check "the preview holds mdi's home"          "yes" \
    "$([ -s "$(symbolfont_svg)" ] && echo yes || echo no)"
stale_render="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"

omc_control "$PICK_FONT" "fluent"
pick_symbol ICEdit.symbolfonts.select "ab-testing"
check "the render failed"                     "yes" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Error:")"
# The precondition that makes this test meaningful: the stale file is still
# sitting there, byte for byte, after the failed render.
check "and left the stale render in place"    "$stale_render" \
    "$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"

pick_symbol ICEdit.symbolfonts.add "ab-testing"
check_status "add declined without failing"   0
check "nothing was added"                     "$layers_before" "$(icon_layer_count "$(work_icon)")"
check "and no layer carries that name"        "0" \
    "$(icon_layers "$(work_icon)" | /usr/bin/grep -c -x -e "ab-testing")"
check "the status explains the refusal"       "yes" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Cannot add")"
omc_control "$PICK_FONT" "mdi"

section "11c. adding with nothing selected, and with no document, both decline"
omc_table_cell "$PICK_LIST" 1 ""
omc_run ICEdit.symbolfonts.add
check_status "the handler succeeded"          0
check "and says nothing is selected"          "No symbol selected"  "$(ui_value $PICK_STATUS)"

section "12. the picker wrote only where it was allowed to"
check "no undeclared ids"                     ""            "$(ui_unknown_writes)"
check "no bare value clobbered a table"       ""            "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
