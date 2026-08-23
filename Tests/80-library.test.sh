#!/bin/sh
# Tests/80-library.test.sh - the functions the handlers are built out of.
#
# Whole-handler dispatch is coarse. The rules that decide what a fill means,
# what a color looks like in a picker, what shape the layer table takes and
# which symbol a search puts first all live in named functions, and they are
# cheaper and sharper to test directly. Every call goes through the applet's own
# interpreter with its own libraries imported - see helpers/icedit_eval.py.
#
# No trailer of ui_unknown_writes / ui_suspect_writes checks in this file: not
# one call below touches a window, so those checks would be vacuous here rather
# than reassuring. The seven other files carry them.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

section "1. parse_fill reads every fill shape the format has"
check "an absent fill"                        "('none', '', None)"          "$(icedit_eval 'parse_fill(None)')"
check "an explicit none"                      "('none', '', None)"          "$(icedit_eval 'parse_fill(ARGV[0])' none)"
check "automatic"                             "('automatic', '', None)"     "$(icedit_eval 'parse_fill(ARGV[0])' automatic)"
check "a solid color"                         "('solid', 'srgb:1,0,0,1', None)" \
    "$(icedit_eval 'parse_fill({"solid": ARGV[0]})' 'srgb:1,0,0,1')"
check "an automatic gradient"                 "('auto-gradient', 'srgb:1,0,0,1', None)" \
    "$(icedit_eval 'parse_fill({"automatic-gradient": ARGV[0]})' 'srgb:1,0,0,1')"
check "a two-stop linear gradient"            "('gradient', 'a', 'b')" \
    "$(icedit_eval 'parse_fill({"linear-gradient": ["a", "b"]})')"
# A one-element gradient is malformed, and the second stop comes back as the
# empty string rather than raising - which is what keeps a hand-edited icon.json
# from taking the whole selection handler down.
check "a one-stop gradient degrades"          "('gradient', 'a', '')" \
    "$(icedit_eval 'parse_fill({"linear-gradient": ["a"]})')"
check "an empty gradient degrades"            "('gradient', '', '')" \
    "$(icedit_eval 'parse_fill({"linear-gradient": []})')"
check "a gradient that is not a list"         "('none', '', None)" \
    "$(icedit_eval 'parse_fill({"linear-gradient": ARGV[0]})' 'not a list')"
check "a dict naming no known fill"           "('none', '', None)" \
    "$(icedit_eval 'parse_fill({"nonsense": 1})')"
check "a number where a fill should be"       "('none', '', None)" "$(icedit_eval 'parse_fill(7)')"
check "and an unknown string"                 "('none', '', None)" \
    "$(icedit_eval 'parse_fill(ARGV[0])' 'chartreuse')"

section "2. color_to_hex converts every color space the format uses"
check "extended-srgb"                         "#FF0000"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-srgb:1.0,0.0,0.0,1.0')"
check "srgb"                                  "#00FF00"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'srgb:0.0,1.0,0.0,1.0')"
check "display-p3"                            "#0000FF"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'display-p3:0.0,0.0,1.0,1.0')"
check "extended-gray expands to three channels" "#808080"   "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-gray:0.501960785,1.0')"
# Alpha only appears in the string when it is not fully opaque, because the
# ColorPicker treats a six-digit value as opaque.
check "a translucent color carries its alpha" "#FF000080"   "$(icedit_eval 'color_to_hex(ARGV[0])' 'srgb:1.0,0.0,0.0,0.501960785')"
check "an opaque one does not"                "#FF0000"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'srgb:1.0,0.0,0.0,1.0')"
# Empty rather than a raise, and since helpers/icedit_eval.py reports a raise as
# "RAISED: <type>" rather than as nothing, this can now tell the two apart.
check "an empty color stays empty"            ""            "$(icedit_eval 'color_to_hex(ARGV[0])' '')"
# Anything already hex, or a named color, passes through untouched: the function
# is called on values that have been round-tripped through the picker.
check "hex passes through"                    "#123456"     "$(icedit_eval 'color_to_hex(ARGV[0])' '#123456')"
check "and so does a name"                    "chartreuse"  "$(icedit_eval 'color_to_hex(ARGV[0])' 'chartreuse')"
check "a prefix with too few components"      "srgb:1.0"    "$(icedit_eval 'color_to_hex(ARGV[0])' 'srgb:1.0')"
check "channels above one are clamped"        "#FFFFFF"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-srgb:2.0,3.0,4.0,1.0')"
check "and below zero"                        "#000000"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-srgb:-1.0,-2.0,-3.0,1.0')"

section "3. KNOWN DEFECT: color_to_hex truncates where it should round"
# int(float * 255) discards the fraction rather than rounding it, so a channel
# lands one step low whenever the float is not an exact multiple of 1/255 - and
# icedit writes five decimal places, so it usually is not. 0.53333 * 255 =
# 135.99, which becomes 135.
#
# The consequence is display-only today: settings.apply compares the picker's
# value against color_to_hex of the stored one, and both sides truncate
# identically, so the value on disk does not drift. What is wrong is the color
# well the user is looking at, which is off by one step in each affected
# channel. The fix is round() in place of int(); 40-selection's two hex checks
# are the ones that will turn red when it lands.
check "the exact value round-trips"           "#0088FF"     "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-srgb:0.0,0.533333334,1.0,1.0')"
check "DEFECT: but icedit's own encoding does not" "#0087FF" \
    "$(icedit_eval 'color_to_hex(ARGV[0])' 'extended-srgb:0.00000,0.53333,1.00000,1.00000')"
check "DEFECT: one step low, not two"         "yes" \
    "$(icedit_is 'int(color_to_hex(ARGV[0])[3:5], 16) == int(color_to_hex(ARGV[1])[3:5], 16) - 1' \
        'extended-srgb:0.00000,0.53333,1.00000,1.00000' 'extended-srgb:0.0,0.533333334,1.0,1.0')"

section "4. get_layer_rows builds the table the user sees"
# Four cells per row, and which cell carries the type is what tells a layer from
# a group - 30-layers and 40-selection both depend on this shape.
check "an empty document is one row"          "[['layer-small.png', '', 'Background', '']]" \
    "$(icedit_eval 'get_layer_rows({"groups": []})')"
check "no groups key at all is the same"      "[['layer-small.png', '', 'Background', '']]" \
    "$(icedit_eval 'get_layer_rows({})')"
check "and so is nothing at all"              "[['layer-small.png', '', 'Background', '']]" \
    "$(icedit_eval 'get_layer_rows(None)')"
check "a layer is indented, a group is not" \
    "[['', 'top-layer-small.png', 'a', 'eye'], ['folder', '', 'Group', 'eye'], ['layer-small.png', '', 'Background', '']]" \
    "$(icedit_eval 'get_layer_rows({"groups": [{"layers": [{"name": "a"}]}]})')"
check "an unnamed layer says so"              "yes" \
    "$(icedit_is '"unnamed" in str(get_layer_rows({"groups": [{"layers": [{}]}]}))')"
# An empty NAME and an absent one are different: an empty string is a name the
# user chose, and it still falls back to the placeholder in the table.
check "an unnamed group gets a placeholder"   "yes" \
    "$(icedit_is 'get_layer_rows({"groups": [{"name": "", "layers": []}]})[0][2] == "Group"')"
check "a hidden layer shows the closed eye"   "yes" \
    "$(icedit_is 'get_layer_rows({"groups": [{"layers": [{"name": "a", "hidden": True}]}]})[0][3] == VIS_OFF')"
check "a hidden group does too"               "yes" \
    "$(icedit_is 'get_layer_rows({"groups": [{"name": "g", "layers": [], "hidden-specializations": [{"idiom": "square", "value": True}]}]})[0][3] == VIS_OFF')"
# The lookup is by idiom, not by position, so a specialization for some other
# idiom must not decide what the square window shows.
check "another idiom's flag is ignored"       "yes" \
    "$(icedit_is 'get_layer_rows({"groups": [{"name": "g", "layers": [], "hidden-specializations": [{"idiom": "round", "value": True}]}]})[0][3] == VIS_ON')"
check "two groups both appear"                "yes" \
    "$(icedit_is 'len(get_layer_rows({"groups": [{"layers": [{"name": "a"}]}, {"layers": [{"name": "b"}]}]})) == 5')"

section "5. get_layers is get_layer_rows' name column"
check "names come out in table order"         "['a', 'Group', 'Background']" \
    "$(icedit_eval 'get_layers({"groups": [{"layers": [{"name": "a"}]}]})')"
check "and an empty document is just the background" "['Background']" \
    "$(icedit_eval 'get_layers({"groups": []})')"

section "6. find_layer locates a layer by name across groups"
check "in the first group"                    "yes" \
    "$(icedit_is 'find_layer({"groups": [{"layers": [{"name": "a"}]}]}, ARGV[0])[:2] == (0, 0)' a)"
check "in the second"                         "yes" \
    "$(icedit_is 'find_layer({"groups": [{"layers": [{"name": "a"}]}, {"layers": [{"name": "b"}]}]}, ARGV[0])[:2] == (1, 0)' b)"
check "and it returns the layer itself"       "yes" \
    "$(icedit_is 'find_layer({"groups": [{"layers": [{"name": "a", "glass": False}]}]}, ARGV[0])[2]["glass"] is False' a)"
# None rather than a raise or a wrong hit: every caller tests for it, and the
# alternative is silently editing whichever layer happened to be first.
check "a name that is not there finds nothing" "no" \
    "$(icedit_is 'find_layer({"groups": [{"layers": [{"name": "a"}]}]}, ARGV[0])' b)"
check "and neither does an empty document"    "no" \
    "$(icedit_is 'find_layer({"groups": []}, ARGV[0])' a)"
check "nor a None document"                   "no" "$(icedit_is 'find_layer(None, ARGV[0])' a)"

section "7. get_group takes a 1-based index, as the icedit CLI does"
check "the first group is 1"                  "yes" \
    "$(icedit_is 'get_group({"groups": [{"name": "a"}, {"name": "b"}]}, 1)["name"] == "a"')"
check "the second is 2"                       "yes" \
    "$(icedit_is 'get_group({"groups": [{"name": "a"}, {"name": "b"}]}, 2)["name"] == "b"')"
# 0 would be the last group under Python indexing, which is the bug this guard
# exists to prevent - a caller that forgot to convert would silently edit the
# wrong end of the stack.
check "0 is out of range, not the last one"   "no" \
    "$(icedit_is 'get_group({"groups": [{"name": "a"}, {"name": "b"}]}, 0)')"
check "and so is one past the end"            "no" \
    "$(icedit_is 'get_group({"groups": [{"name": "a"}]}, 2)')"
check "a negative index too"                  "no" \
    "$(icedit_is 'get_group({"groups": [{"name": "a"}]}, -1)')"

section "8. group_index_from_list maps a table row back to a group"
check "by name"                               "2" \
    "$(icedit_eval 'group_index_from_list({"groups": [{"name": "a"}, {"name": "b"}]}, ARGV[0])' b)"
# The table shows "Group" for an unnamed group, so the lookup has to accept the
# placeholder back - it is the only string the row can hand it.
check "and by the placeholder for an unnamed one" "2" \
    "$(icedit_eval 'group_index_from_list({"groups": [{"name": "a"}, {"layers": []}]}, ARGV[0])' Group)"
# 1 is the documented fallback rather than an error, because there is always at
# least a first group to fall back to.
check "an unknown name falls back to the first" "1" \
    "$(icedit_eval 'group_index_from_list({"groups": [{"name": "a"}]}, ARGV[0])' zzz)"
check "and so does an empty document"         "1" \
    "$(icedit_eval 'group_index_from_list({"groups": []}, ARGV[0])' a)"

section "9. lib_material ranks a search by how well it matches"
names="$(icedit_eval 'len(lib_material.load_names())')"
check "the font's names loaded"               "yes"         "$([ "$names" -gt 100 ] && echo yes || echo no)"
check "and its search metadata"               "yes" \
    "$(icedit_is 'len(lib_material.load_search_index()) > 100')"
# The library half of the "Material Symbols not installed" branch, which is the
# state a fresh checkout is in - download_material_symbols.sh has not run and
# there is no .codepoints file. The handler half (the branch in
# ICEdit.materialsymbols.init that puts the download instruction on screen) is
# not reachable under test and is called out in 60-symbols' header.
check "a missing codepoints file yields no names" "[]" \
    "$(icedit_eval 'setattr(lib_material, "CODEPOINTS_FILE", ARGV[0]) or lib_material.load_names()' \
        "$OMCTEST_WORK/no-such.codepoints")"
check "and a missing metadata file no index"  "{}" \
    "$(icedit_eval 'setattr(lib_material, "METADATA_FILE", ARGV[0]) or lib_material.load_search_index()' \
        "$OMCTEST_WORK/no-such.json")"
printf 'this is not json\n' > "$OMCTEST_WORK/not-metadata.json"
check "metadata that is not JSON is survived" "{}" \
    "$(icedit_eval 'setattr(lib_material, "METADATA_FILE", ARGV[0]) or lib_material.load_search_index()' \
        "$OMCTEST_WORK/not-metadata.json")"
check "an empty search changes nothing"       "yes" \
    "$(icedit_is 'lib_material.filter_names(["b", "a"], {}, ARGV[0]) == ["b", "a"]' '')"
check "and neither does whitespace"           "yes" \
    "$(icedit_is 'lib_material.filter_names(["b", "a"], {}, ARGV[0]) == ["b", "a"]' '   ')"
# The ranking rule that matters: a term matching a whole word of the name beats
# one matching only part of a word. Without it "scorecard" outranks "car".
check "a whole-word match wins"               "['car', 'directions_car', 'scorecard']" \
    "$(icedit_eval 'lib_material.filter_names(["car", "directions_car", "scorecard"], {}, ARGV[0])' car)"
check "a name that cannot match is dropped"   "['car']" \
    "$(icedit_eval 'lib_material.filter_names(["car", "house"], {}, ARGV[0])' car)"
# Tags are searched too, and a tag-only hit ranks below a name hit.
check "a tag-only match is found"             "['van']" \
    "$(icedit_eval 'lib_material.filter_names(["van"], {"van": "van automobile"}, ARGV[0])' automobile)"
check "but ranks below a name match"          "['car', 'van']" \
    "$(icedit_eval 'lib_material.filter_names(["van", "car"], {"van": "van car transport", "car": "car"}, ARGV[0])' car)"
check "several terms match any of them"       "['a', 'b']" \
    "$(icedit_eval 'lib_material.filter_names(["a", "b", "c"], {}, ARGV[0])' 'a b')"
check "and the case does not matter"          "['car']" \
    "$(icedit_eval 'lib_material.filter_names(["car"], {}, ARGV[0])' CAR)"

section "10. the search debounce lets only the last keystroke through"
# Two invocations racing on one key: the first is superseded while it waits and
# must bow out, so a burst of keystrokes rebuilds the list once rather than once
# per character. The two run concurrently on purpose - sequentially each would
# be the latest claim in turn and both would return True, which is exactly the
# check that cannot fail.
"$OMCTEST_PYTHON" -c '
import os, sys, threading
sys.path.insert(0, os.path.join(os.environ["OMC_APP_BUNDLE_PATH"], "Contents/Resources/Scripts"))
import lib_debounce
answers = {}
def claim(tag, delay):
    answers[tag] = lib_debounce.should_rebuild("racekey", delay)
# Wide margins on purpose. The first claim is published at t=0 and does not look
# again until t=0.9; the second publishes at t=0.15 and answers at t=0.30. A
# narrower gap can invert under load, and a flaky check is worse than a slow one.
first = threading.Thread(target=claim, args=("first", 0.90))
first.start()
threading.Event().wait(0.15)
second = threading.Thread(target=claim, args=("second", 0.15))
second.start()
first.join(); second.join()
print("%s %s" % (answers["first"], answers["second"]))
' > "$OMCTEST_WORK/debounce.out" 2>&1
check "the superseded keystroke bows out, the last one rebuilds" "False True" \
    "$(/bin/cat "$OMCTEST_WORK/debounce.out")"
# A lone keystroke is nobody's predecessor and must always rebuild - the
# positive control for the False above.
check "an unopposed keystroke rebuilds"       "yes" \
    "$(icedit_is 'lib_debounce.should_rebuild(ARGV[0], 0.01)' 'lonekey')"
# Different windows must not supersede each other: two pickers open at once are
# two independent searches.
check "and a different window is a different race" "yes" \
    "$(icedit_is 'lib_debounce.should_rebuild(ARGV[0], 0.01)' 'otherkey')"

section "11. file_hash fingerprints a file and survives a missing one"
printf 'the same bytes\n' > "$OMCTEST_WORK/hash-a.txt"
printf 'the same bytes\n' > "$OMCTEST_WORK/hash-b.txt"
printf 'different bytes\n' > "$OMCTEST_WORK/hash-c.txt"
check "equal contents hash equally"           "yes" \
    "$(icedit_is 'file_hash(ARGV[0]) == file_hash(ARGV[1])' "$OMCTEST_WORK/hash-a.txt" "$OMCTEST_WORK/hash-b.txt")"
check "different contents do not"             "no" \
    "$(icedit_is 'file_hash(ARGV[0]) == file_hash(ARGV[1])' "$OMCTEST_WORK/hash-a.txt" "$OMCTEST_WORK/hash-c.txt")"
check "and it is a full SHA-256"              "64" \
    "$(icedit_eval 'len(file_hash(ARGV[0]))' "$OMCTEST_WORK/hash-a.txt")"
# Empty rather than a raise, because window.activated calls this on a file the
# user may have deleted between activations - and an empty hash reads as "no
# fingerprint", which that handler already knows how to treat. This is the check
# for file_hash's own except clause, and it was passing vacuously until
# helpers/icedit_eval.py learned to print "RAISED: <type>" instead of nothing:
# with the guard deleted the helper failed silently to empty and the check could
# not tell the difference.
check "a missing file hashes to nothing"      ""            "$(icedit_eval 'file_hash(ARGV[0])' "$OMCTEST_WORK/not-there")"
check "and a directory does too"              ""            "$(icedit_eval 'file_hash(ARGV[0])' "$OMCTEST_WORK")"

section "12. load_icon_json reads a bundle, or says it could not"
sample="$(make_sample_icon Library.icon)"
check "the fixture parses"                    "yes"         "$(icedit_is 'load_icon_json(ARGV[0])' "$sample")"
check "with its two layers"                   "2"           "$(icedit_eval 'len(load_icon_json(ARGV[0])["groups"][0]["layers"])' "$sample")"
check "a directory with no icon.json is None" "no"          "$(icedit_is 'load_icon_json(ARGV[0])' "$OMCTEST_WORK")"
check "and so is a path that is not there"    "no"          "$(icedit_is 'load_icon_json(ARGV[0])' "$OMCTEST_WORK/not-there.icon")"

omctest_end
