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
# Entries carrying a tag, not entries. The list also holds {"section": ...}
# markers, which are headers rather than choices, so counting the raw list would
# make this assertion depend on how many kinds the bundle happens to hold.
check "every installed set is offered"        "$set_count" \
    "$(icedit_eval 'len([o for o in json.loads(ARGV[0]) if "tag" in o])' "$(ui_prop $PICK_FONT options)")"
# The headers themselves, in order. Emitted only when the bundle holds more than
# one kind - one header over the whole list labels nothing - so the expectation
# is derived rather than written down, for the same reason set_count is.
check "the two kinds are grouped under headers" \
    "$(icedit_eval '",".join(lib_symbolfonts.KIND_TITLES[k] for k in lib_symbolfonts.KIND_ORDER if any(s["kind"] == k for s in lib_symbolfonts.list_sets())) if len({s["kind"] for s in lib_symbolfonts.list_sets()}) > 1 else ""')" \
    "$(icedit_eval '",".join(o["section"] for o in json.loads(ARGV[0]) if "section" in o)' "$(ui_prop $PICK_FONT options)")"
# A header owns every entry after it until the next one, so the grouping is only
# real if the tagged entries arrive already sorted by kind. Compare the order the
# picker was given against the order the library reports.
check "and the sets are listed in that order" \
    "$(icedit_eval '",".join(s["name"] for s in lib_symbolfonts.list_sets())')" \
    "$(icedit_eval '",".join(o["tag"] for o in json.loads(ARGV[0]) if "tag" in o)' "$(ui_prop $PICK_FONT options)")"
# Selected explicitly, not left to the placeholder in SymbolFonts.json: that
# placeholder's tag is the empty string, and a handler reading it would treat
# the picker as having no font at all.
first_set="$(icedit_eval 'lib_symbolfonts.list_sets()[0]["name"]')"
check "and one of them is selected"           "$first_set"  "$(ui_value $PICK_FONT)"
check "the name list was filled"              "1"  "$(ui_calls "$PICK_LIST.omc_list_set_items_from_stdin")"
first_names="$(icedit_eval 'len(lib_symbolfonts.load_names(lib_symbolfonts.set_info(ARGV[0]).get("codepoints")))' "$first_set")"
check "with the font's own symbol count"      "$first_names symbols" "$(ui_value $PICK_STATUS)"
# The license comes from the set's manifest by way of glyphsvg --info, so it is
# checked against what --info reports rather than against a literal: a font whose
# terms change upstream should move this line, not fail this test.
check "and the font's license is named"       \
    "$(icedit_eval 'lib_symbolfonts.set_info(ARGV[0]).get("license", "")' "$first_set")" \
    "$(ui_value $PICK_FONT_LICENSE)"
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
# The license line is per font, so it has to move with the font. Left standing,
# it would name the terms of a font the dialog is no longer showing - which is a
# worse failure than showing nothing, because it reads as an assertion.
check "the license line followed the font"    \
    "$(icedit_eval 'lib_symbolfonts.set_info("mdi").get("license", "")')" \
    "$(ui_value $PICK_FONT_LICENSE)"
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

section "13. the weight slider is driven by the font's own axis"
# The reason this control is a slider and not the Material picker's list of
# named weights: named weights stop at black, black maps to 900, and Nunito's
# axis runs to 1000. A fixed name list literally cannot reach the heaviest
# weight the font has, which is the weight an app icon most often wants.
omc_control "$PICK_FONT" "nunito"
omc_run ICEdit.symbolfonts.font
check_status "the handler succeeded"          0
check "nunito really is variable"             "yes" \
    "$(icedit_eval 'lib_symbolfonts.set_info("nunito").get("variable")')"
check "the slider is enabled"                 "1"    "$(ui_enabled $PICK_FONT_WEIGHT)"
# Asserted against the axis glyphsvg reports, not a literal: this keeps meaning
# something if upstream ever reissues the font with a different range.
# icedit_eval takes an EXPRESSION, so the two ends are read separately rather
# than built up in one statement.
nunito_range="$(ui_prop $PICK_FONT_WEIGHT range)"
check "its range starts at the axis minimum"  \
    "$(icedit_eval 'lib_symbolfonts.wght_axis(lib_symbolfonts.set_info("nunito"))[0]')" \
    "$(icedit_eval 'json.loads(ARGV[0])["min"]' "$nunito_range")"
check "and ends at its maximum"               \
    "$(icedit_eval 'lib_symbolfonts.wght_axis(lib_symbolfonts.set_info("nunito"))[2]')" \
    "$(icedit_eval 'json.loads(ARGV[0])["max"]' "$nunito_range")"
check "it opens on the icon default"          "700"  "$(ui_value $PICK_FONT_WEIGHT)"
check "and the label agrees"                  "Weight 700" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"
adopt_window_values "$PICK_FONT_WEIGHT"

section "13a. the slider is declared with the property a Slider actually fires"
# This assertion exists because the whole suite is blind to the bug it catches.
# ActionUI's Slider dispatches ONLY valueChangeActionID - Slider.swift reads
# that key and nothing else - while Picker dispatches actionID. Both are legal
# baseline properties, so a Slider carrying actionID validates, warns about
# nothing, and silently never fires. omc_run calls handlers directly, so every
# behavioral test below passes either way; only the document can be checked.
#
# The live symptom is worse than a dead control: the slider's model value still
# changes, so VIEW_12_VALUE is current at dispatch. The preview and the label
# would keep showing the old weight while Add committed the dragged one - the
# artwork-disagrees-with-what-was-shown failure that 11b and 13e exist to stop.
sf_json="$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/SymbolFonts.json"
check "the slider fires valueChangeActionID" "ICEdit.symbolfonts.select" \
    "$(icedit_eval 'next(c for c in json.load(open(ARGV[0]))["children"][1]["children"][3]["children"] if c.get("id") == 12)["properties"].get("valueChangeActionID","")' "$sf_json")"
check "and does not rely on actionID"        "" \
    "$(icedit_eval 'next(c for c in json.load(open(ARGV[0]))["children"][1]["children"][3]["children"] if c.get("id") == 12)["properties"].get("actionID","")' "$sf_json")"

section "13b. a static font leaves the slider inert"
# Bungee has no wght axis. Disabled rather than hidden, for the same reason the
# face picker is: hiding reflows the control bar on every font change.
omc_control "$PICK_FONT" "bungee"
omc_run ICEdit.symbolfonts.font
check "bungee really is static"               "no" \
    "$(icedit_eval 'lib_symbolfonts.set_info("bungee").get("variable")')"
check "the slider is disabled"                "0"    "$(ui_enabled $PICK_FONT_WEIGHT)"
check "and the label says so"                 "Single weight" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"
# resolve_weight returning None is what keeps --weight off a static font's
# command line, where it would mean "pick the nearest face" instead of an axis.
check "no weight is resolved for it"          "None" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("bungee"), "700"))')"

section "13c. moving the slider actually changes the artwork"
# The oracle that matters. A slider that is wired to the handler but whose value
# never reaches glyphsvg would pass every assertion above and render one weight
# forever.
omc_control "$PICK_FONT" "nunito"
omc_run ICEdit.symbolfonts.font
omc_control "$PICK_FONT_WEIGHT" "200"
pick_symbol ICEdit.symbolfonts.select "Q"
light="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"
omc_control "$PICK_FONT_WEIGHT" "1000"
pick_symbol ICEdit.symbolfonts.select "Q"
heavy="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"
check "light and heavy are different glyphs"  "differ" \
    "$([ "$light" = "$heavy" ] && echo same || echo differ)"
check "the label followed the slider"         "Weight 1000" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"

section "13d. a weight is carried across a font change, and clamped to the new axis"
# Unlike the face, which is discarded: a face name means nothing outside its own
# font, but a weight is a number on a scale every font shares. Carrying it lets
# one weight be compared across fonts. Clamping is what makes that safe - 1000
# is off the end of Monaspace's axis, which stops at 800.
check "monaspace really stops at 800"         "800.0" \
    "$(icedit_eval 'print(lib_symbolfonts.wght_axis(lib_symbolfonts.set_info("monaspace"))[2])')"
omc_control "$PICK_FONT" "monaspace"
omc_run ICEdit.symbolfonts.font
check "the slider clamped to the new maximum" "800"  "$(ui_value $PICK_FONT_WEIGHT)"
check "and the label with it"                 "Weight 800" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"

section "13e. the added layer carries the weight that was on screen"
# The correctness test for the add path, and the counterpart to 11b. add.py
# renders its own SVG rather than reusing the preview's; that protects the
# NAME/artwork pairing. This asserts the WEIGHT pairing: an add that dropped the
# weight and let glyphsvg fall back to the font's default would silently commit
# ExtraLight artwork - Nunito's own default is 200 - under a heavy preview.
omc_control "$PICK_FONT" "nunito"
omc_run ICEdit.symbolfonts.font
omc_control "$PICK_FONT_WEIGHT" "900"
pick_symbol ICEdit.symbolfonts.select "Q"
preview_900="$(/usr/bin/shasum "$(symbolfont_svg)" | /usr/bin/cut -d" " -f1)"
pick_symbol ICEdit.symbolfonts.add "Q"
check_status "the add succeeded"              0
check "add rendered the same bytes as the preview" "$preview_900" \
    "$(/usr/bin/shasum "$(symbolfont_add_svg)" | /usr/bin/cut -d" " -f1)"

add_900="$(/usr/bin/shasum "$(symbolfont_add_svg)" | /usr/bin/cut -d" " -f1)"

omc_control "$PICK_FONT_WEIGHT" "200"
pick_symbol ICEdit.symbolfonts.add "Q"
check_status "the lighter add succeeded"      0
# Compared against the heavy ADD, not against the heavy preview. Comparing with
# the preview would still read "differ" if add ignored the slider entirely and
# rendered both at the font's default - the two sides would differ for the wrong
# reason. Only add-vs-add can tell whether the slider reaches this path.
check "and the two adds differ from each other" "differ" \
    "$([ "$add_900" = "$(/usr/bin/shasum "$(symbolfont_add_svg)" | /usr/bin/cut -d" " -f1)" ] \
       && echo same || echo differ)"

section "13f. a slider value the dialog should never send is survived anyway"
# resolve_weight never trusts what it is handed, for the same reason resolve_face
# does not: the environment is a dispatch-time snapshot, and applying a new range
# can itself dispatch this action carrying a number from the font being left.
check "text is replaced by the default"       "700" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), "not-a-number"))')"
check "empty is replaced by the default"      "700" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), ""))')"
check "far too heavy clamps to the maximum"   "1000" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), "99999"))')"
check "far too light clamps to the minimum"   "200" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), "-5"))')"
# And the whole way through, not just in the helper: a garbage slider value must
# still render rather than putting an error on the status line.
check "and so is a non-finite one"            "700" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), "nan"))')"
check "as is an infinite one"                 "700" \
    "$(icedit_eval 'print(lib_symbolfonts.resolve_weight(lib_symbolfonts.set_info("nunito"), "inf"))')"
# And the whole way through, not just in the helper: a garbage slider value must
# still render rather than putting an error on the status line. check_status is
# what stops a handler that DIED on the value from passing here - a traceback
# would leave the status at its previous text, which starts with neither "Error"
# nor anything else this could notice.
omc_control "$PICK_FONT_WEIGHT" "not-a-number"
pick_symbol ICEdit.symbolfonts.select "Q"
check_status "the handler survived it"        0
check "a garbage slider value still renders"  "no" \
    "$(starts_with "$(ui_value $PICK_STATUS)" "Error:")"
check "and the preview was written"           "yes" \
    "$([ -s "$(symbolfont_svg)" ] && echo yes || echo no)"
omc_control "$PICK_FONT_WEIGHT" "700"

section "13g. only a slider drag is debounced"
# A drag dispatches once per step, so the slider is debounced where a list click
# is not. The gate is the trigger view id, which is what keeps a click instant.
#
# The font is set explicitly rather than inherited: a weight assertion is only
# meaningful over a font that HAS a weight axis, and an earlier section leaving
# a static one selected would make every check here read "Single weight" and
# pass or fail for reasons that have nothing to do with debouncing.
omc_control "$PICK_FONT" "nunito"
omc_run ICEdit.symbolfonts.font
omc_control "$PICK_FONT_WEIGHT" "500"
omc_trigger "$PICK_FONT_WEIGHT"
pick_symbol ICEdit.symbolfonts.select "Q"
check_status "a debounced drag still renders" 0
check "and updated the label"                 "Weight 500" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"
check "and the preview with it"               "yes" \
    "$([ -s "$(symbolfont_svg)" ] && echo yes || echo no)"

section "13h. the weight label tracks the slider before any symbol is picked"
# The label is the slider's only readout, so it must not sit behind the
# no-symbol early exit - dragging on a freshly opened picker has to show
# something.
omc_table_cell "$PICK_LIST" 1 ""
omc_control "$PICK_FONT_WEIGHT" "350"
omc_run ICEdit.symbolfonts.select
check_status "the handler succeeded"          0
check "the label still followed"              "Weight 350" "$(ui_value $PICK_FONT_WEIGHT_LABEL)"
omc_control "$PICK_FONT_WEIGHT" "700"
omc_control "$PICK_FONT" "mdi"
omc_run ICEdit.symbolfonts.font

section "14. an emoji set is searchable in words people actually use"
# Unicode names are formal: the page emoji is PAGE FACING UP, so an index built
# from names alone cannot answer "document". notoemoji's sidecar merges CLDR
# keywords, and this asserts the DATA is there rather than that a file exists.
#
# emoji_hit returns yes/no for "is this character in the top six results", which
# is the question every check below asks. Written once here because the
# expression is long enough that six copies would hide their own differences.
emoji_hit() { # <python-escaped-char> <search>
    icedit_eval 'print("yes" if ARGV[0] in lib_symbolfonts.filter_names(
        lib_symbolfonts.load_names(lib_symbolfonts.set_info("notoemoji")["codepoints"]),
        lib_symbolfonts.load_search_index(lib_symbolfonts.set_info("notoemoji")["metadata"]),
        ARGV[1])[:6] else "no")' "$1" "$2"
}

emoji_names="$(icedit_eval 'len(lib_symbolfonts.load_names(lib_symbolfonts.set_info("notoemoji").get("codepoints")))')"
check "notoemoji resolved with its symbols"   "yes" \
    "$([ "$emoji_names" -gt 1000 ] && echo yes || echo no)"
check "and carries a search index"            "yes" \
    "$(icedit_eval 'print("yes" if len(lib_symbolfonts.load_search_index(lib_symbolfonts.set_info("notoemoji").get("metadata"))) > 1000 else "no")')"

# None of these words appears in the Unicode name of the glyph it should find -
# PAGE FACING UP, MAGNIFYING GLASS TILTED LEFT, WASTEBASKET - so a hit can only
# come from CLDR. These fail if the annotations stop being merged.
check "'document' finds the page"             "yes" "$(emoji_hit "$(printf '\360\237\223\204')" document)"
check "'search' finds the magnifier"          "yes" "$(emoji_hit "$(printf '\360\237\224\215')" search)"
check "'trash' finds the wastebasket"         "yes" "$(emoji_hit "$(printf '\360\237\227\221')" trash)"

section "14b. a whole-word tag match outranks a merely-containing one"
# The ranking tier this set forced. Three of the four original tiers read the
# NAME, which here is a single character with no words in it, so every candidate
# scored identically and fell back to alphabetical: searching "lock" listed
# clocks first, because "clock" CONTAINS "lock". Ranking a whole-word hit in the
# tags above a substring hit is the fix.
check "'lock' surfaces the padlock"           "yes" "$(emoji_hit "$(printf '\360\237\224\222')" lock)"
check "and the alarm clock is pushed out"     "no"  "$(emoji_hit "$(printf '\342\217\260')" lock)"
# The same tier in isolation, so a failure points at the ranking rather than at
# the emoji data.
check "a tag word beats a tag substring"      "b a" \
    "$(icedit_eval 'print(" ".join(lib_glyphsearch.filter_names(["a","b"], {"a":"a clock","b":"b lock"}, "lock")))')"

section "12. the picker wrote only where it was allowed to"
check "no undeclared ids"                     ""            "$(ui_unknown_writes)"
check "no bare value clobbered a table"       ""            "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
