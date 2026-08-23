#!/bin/sh
# Tests/50-settings.test.sh - Apply, and what it writes back to the document.
#
# ICEdit.settings.apply is the write half of 40-selection's read half: it takes
# the pane the user has been editing, compares every control against the
# document, and runs one icedit command per property that actually moved. Which
# pane it acts on is decided entirely by the pasteboard selection, so every
# section here goes through select_background / select_layer / select_group
# first, then adopts the values that selection put on screen (see
# adopt_window_values in the app lib for why that step is not optional).
#
# The sections that matter most are 1, 1b and 1c: apply with nothing touched
# must write nothing, in each of the three panes. Every other section is only
# meaningful because those hold - and 1c does not, which is the third defect
# this suite documents.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

section "1. Apply with nothing touched writes nothing"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
before="$(icon_layer_key "$(work_icon)" Circle position)"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the layer is unchanged"                "$before"     "$(icon_layer_key "$(work_icon)" Circle position)"
check "its name is unchanged"                 "Circle"      "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 2p)"
check "glass was not rewritten"               "true"        "$(icon_layer_key "$(work_icon)" Circle glass)"
check "and it was not hidden"                 ""            "$(icon_layer_key "$(work_icon)" Circle hidden)"
# The dirty flag is the applet's own answer to "did anything change", and it is
# only set inside the "if changed" block. Section 2 is the positive control.
check "the document is still clean"           ""            "$(dirty)"
# "Settings applied" is written only inside the same "if changed" block, so the
# status line still says what opening the document said. Section 2 is the
# positive control, where the same read returns the apply's own message.
check "and nothing was said about it"         "Loaded Sample.icon" "$(ui_value $ID_STATUS)"

section "1b. Apply with nothing touched writes nothing in the background pane"
open_sample > /dev/null
before_fill="$(icon_fill "$(work_icon)")"
select_background
adopt_background_controls
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the fill is byte-identical"            "$before_fill" "$(icon_fill "$(work_icon)")"
check "the document is still clean"           ""            "$(dirty)"
check "and nothing was said about it"         "Loaded Sample.icon" "$(ui_value $ID_STATUS)"

section "1c. KNOWN DEFECT: Apply on an untouched group always writes a shadow"
# Selecting a group and pressing Apply without touching anything writes a
# shadow into the document and marks it dirty. Every user who inspects a group
# and hits Apply gets a modified file.
#
# ICEdit.settings.apply.py, the Shadow block:
#
#     old_shadow = group.get("shadow", {})
#     new_shadow = {"kind": shadow_kind, "opacity": shadow_opacity}
#     if new_shadow != old_shadow:
#
# A group with no "shadow" key gives old_shadow == {}, which can never equal a
# two-key dict - and the two values on the right are the pane's OWN defaults,
# pushed into the controls by ICEdit.layer.select and handed straight back. So
# the comparison is {"kind": "none", "opacity": 0.5} != {}, which is true
# forever. The same block done right is a few lines above it: translucency is
# compared value by value against its own default rather than as a whole dict.
#
# The fix is to compare the way translucency does, or to treat a missing shadow
# as {"kind": "none", "opacity": 0.5} before comparing. The checks below assert
# the defect as it stands; when it is fixed they turn red and name themselves,
# and the three lines marked DEFECT become copies of section 1b's.
open_sample > /dev/null
select_group
adopt_group_controls
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "DEFECT: a shadow was invented"         '{"kind":"none","opacity":0.5}' \
                                                            "$(icon_group_key "$(work_icon)" 1 shadow)"
check "DEFECT: and the document went dirty"   "1"           "$(dirty)"
check "DEFECT: with an Apply nobody asked for" "Settings applied" "$(ui_value $ID_STATUS)"
# Not part of the defect, and worth pinning separately so a fix to the shadow
# comparison is not mistaken for a fix to something else: no OTHER group
# property was rewritten by the same untouched Apply.
check "but the opacity was left alone"        ""            "$(icon_group_key "$(work_icon)" 1 opacity)"
check "and the blend mode"                    ""            "$(icon_group_key "$(work_icon)" 1 blend-mode)"
check "and the group is still unnamed"        ""            "$(icon_groups "$(work_icon)")"
check "and still visible"                     ""            "$(icon_group_key "$(work_icon)" 1 hidden-specializations)"

section "2. renaming a layer"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_NAME" "Renamed"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the document has the new name"         "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Renamed$')"
check "and not the old one"                   "0"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Circle$')"
check "the table followed"                    "Renamed"     "$(row_cell 2 $COL_NAME)"
# The selection has to follow the rename, or the next Apply would look up a name
# the document no longer has and silently do nothing.
check "the selection followed too"            "Renamed"     "$(selected_layer)"
check "the document became dirty"             "1"           "$(dirty)"
check "and said so"                           "Settings applied" "$(ui_value $ID_STATUS)"

section "3. the rest of an Apply still runs after a rename"
# A rename is the one property change that makes the handler reload the document
# and re-find the layer mid-apply, so it is the one place where the properties
# AFTER it could be dropped or applied to the wrong layer. Renaming and moving
# in a single Apply is what makes that observable: an early return after the
# rename leaves the scale where it was.
#
# Not claimed here: that the re-find protects anything. rename_layer touches only
# the name key, so a stale layer dict would compare identically for every other
# property - the block reads as a precaution rather than as load-bearing code.
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_NAME" "Moved"
omc_control "$ID_LAYER_SCALE" "3.0"
omc_control "$ID_LAYER_SHIFT_X" "15"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the rename landed"                     "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Moved$')"
check "and so did the move after it"          '{"scale":3.0,"translation-in-points":[15,0]}' \
                                                            "$(icon_layer_key "$(work_icon)" Moved position)"
check "on the renamed layer, not its neighbor" '{"scale":7.68,"translation-in-points":[0,0]}' \
                                                            "$(icon_layer_key "$(work_icon)" Square position)"
check "and nothing else was rewritten"        "true"        "$(icon_layer_key "$(work_icon)" Moved glass)"

section "4. giving a layer a solid fill"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_FILL" "solid"
omc_control "$ID_LAYER_COLOR1_PICKER" "#FF8000"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
# icedit normalizes every color it writes to the extended-srgb space, whatever
# space the value came in as - so the hex from the ColorPicker comes back as
# floats with a prefix the picker never sent.
check "the fill was written"                  '{"solid":"extended-srgb:1.00000,0.50196,0.00000,1.00000"}' \
                                                            "$(icon_layer_key "$(work_icon)" Circle fill)"
check "the color well stayed shown"           "1"           "$(ui_visible $ID_LAYER_COLOR1)"
check "the second stayed hidden"              "0"           "$(ui_visible $ID_LAYER_COLOR2)"
check "the document became dirty"             "1"           "$(dirty)"

section "5. giving a layer a two-stop gradient"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_FILL" "gradient"
omc_control "$ID_LAYER_COLOR1_PICKER" "#FF0000"
omc_control "$ID_LAYER_COLOR2_PICKER" "#0000FF"
omc_run ICEdit.settings.apply
# A linear gradient also acquires the default top-to-bottom orientation, which
# the pane has no control for and icedit supplies.
check "both stops were written" '{"linear-gradient":["extended-srgb:1.00000,0.00000,0.00000,1.00000","extended-srgb:0.00000,0.00000,1.00000,1.00000"],"orientation":{"start":{"x":0.5,"y":0},"stop":{"x":0.5,"y":1}}}' \
                                                            "$(icon_layer_key "$(work_icon)" Circle fill)"
check "the second well came out"              "1"           "$(ui_visible $ID_LAYER_COLOR2)"
check "and the labels became ends of a run"   "Start"       "$(ui_value $ID_LAYER_COLOR1_LABEL)"

section "6. a gradient with only one color set is not applied"
# The guard is "and layer_color2" - a half-filled gradient must not reach
# icedit, which would write a one-element linear-gradient. Section 5 is the
# positive control for the same two lines.
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_FILL" "gradient"
omc_control "$ID_LAYER_COLOR1_PICKER" "#FF0000"
omc_control "$ID_LAYER_COLOR2_PICKER" ""
omc_run ICEdit.settings.apply
check "the layer kept no fill at all"         ""            "$(icon_layer_key "$(work_icon)" Circle fill)"
check "and the document stays clean"          ""            "$(dirty)"

section "7. scale and shift"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_SCALE" "2.0"
omc_control "$ID_LAYER_SHIFT_X" "40"
omc_control "$ID_LAYER_SHIFT_Y" "-25"
omc_run ICEdit.settings.apply
check "the position was rewritten"            '{"scale":2.0,"translation-in-points":[40,-25]}' \
                                                            "$(icon_layer_key "$(work_icon)" Circle position)"
check "the document became dirty"             "1"           "$(dirty)"

section "8. a scale that is not a number falls back rather than crashing"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_SCALE" "not a number"
omc_run ICEdit.settings.apply
check_status "the handler survived"           0
# The fallback is 1.0, and the layer was at 7.68, so this IS a change - the
# check is that a garbage field produces the documented default rather than a
# traceback that takes the rest of the apply with it.
check "the fallback scale was written"        '{"scale":1.0,"translation-in-points":[0,0]}' \
                                                            "$(icon_layer_key "$(work_icon)" Circle position)"
# Everything after the scale in the handler still ran, which is the real point.
check "and glass was still compared"          "true"        "$(icon_layer_key "$(work_icon)" Circle glass)"

section "9. a scale below the floor is clamped, not passed through"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_SCALE" "-3"
omc_run ICEdit.settings.apply
check "a negative scale became the floor"     '{"scale":0.01,"translation-in-points":[0,0]}' \
                                                            "$(icon_layer_key "$(work_icon)" Circle position)"

section "10. hiding and unhiding a layer through the pane"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_VISIBLE" "false"
omc_run ICEdit.settings.apply
check "the layer was hidden"                  "true"        "$(icon_layer_key "$(work_icon)" Circle hidden)"
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_VISIBLE" "true"
omc_run ICEdit.settings.apply
check "and shown again"                       ""            "$(icon_layer_key "$(work_icon)" Circle hidden)"

section "11. glass and blend mode"
open_sample > /dev/null
select_layer Circle
adopt_layer_controls
omc_control "$ID_LAYER_GLASS" "false"
omc_control "$ID_LAYER_BLEND" "multiply"
omc_run ICEdit.settings.apply
check "glass was turned off"                  "false"       "$(icon_layer_key "$(work_icon)" Circle glass)"
check "and the blend mode written"            "multiply"    "$(icon_layer_key "$(work_icon)" Circle blend-mode)"

section "12. the background's fill"
open_sample > /dev/null
select_background
adopt_background_controls
omc_control "$ID_BG_FILL" "solid"
omc_control "$ID_BG_COLOR1_PICKER" "#101010"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the document fill was rewritten"       '{"solid":"extended-srgb:0.06275,0.06275,0.06275,1.00000"}' \
                                                            "$(icon_fill "$(work_icon)")"
check "the layers were left alone"            "2"           "$(icon_layer_count "$(work_icon)")"
check "the document became dirty"             "1"           "$(dirty)"

section "13. clearing the background's fill"
select_background
adopt_background_controls
omc_control "$ID_BG_FILL" "none"
omc_run ICEdit.settings.apply
check "the fill kind was written"             "none"        "$(icon_fill "$(work_icon)")"
check "and both color wells went away"        "0"           "$(ui_visible $ID_BG_COLOR1)"

section "14. a group's name and its numeric properties"
open_sample > /dev/null
select_group
adopt_group_controls
omc_control "$ID_GROUP_NAME" "Marks"
omc_control "$ID_GROUP_OPACITY" "0.4"
omc_control "$ID_GROUP_BLUR" "0.6"
omc_control "$ID_GROUP_BLEND" "screen"
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "the group was named"                   "Marks"       "$(icon_groups "$(work_icon)")"
check "the opacity was written"               "0.4"         "$(icon_group_key "$(work_icon)" 1 opacity)"
check "the blur was written"                  "0.6"         "$(icon_group_key "$(work_icon)" 1 blur-material)"
check "the blend mode was written"            "screen"      "$(icon_group_key "$(work_icon)" 1 blend-mode)"
check "the table shows the new name"          "Marks"       "$(row_cell 3 $COL_NAME)"
# Renaming changes the display name the table carries, so the recorded selection
# has to follow it exactly as a layer rename does.
check "the selection followed the rename"     "Marks"       "$(selected_layer)"
check "the document became dirty"             "1"           "$(dirty)"

section "15. group opacity and blur are clamped to their ranges"
open_sample > /dev/null
select_group
adopt_group_controls
# Clamped AWAY from each property's default on purpose. Clamping 5 to 1.0 would
# land exactly on the default opacity, the comparison against the document would
# find no change, and nothing would be written - so the check would pass on a
# handler that had no clamp at all and simply never wrote.
omc_control "$ID_GROUP_OPACITY" "-1"
omc_control "$ID_GROUP_BLUR" "5"
omc_run ICEdit.settings.apply
check "opacity was clamped to the bottom"     "0.0"         "$(icon_group_key "$(work_icon)" 1 opacity)"
check "and blur to the top"                   "1.0"         "$(icon_group_key "$(work_icon)" 1 blur-material)"

section "16. a group's lighting, specular and translucency"
open_sample > /dev/null
select_group
adopt_group_controls
omc_control "$ID_GROUP_LIGHTING" "combined"
omc_control "$ID_GROUP_SPECULAR" "false"
omc_control "$ID_GROUP_TRANSLUCENCY" "0.25"
omc_run ICEdit.settings.apply
check "lighting was written"                  "combined"    "$(icon_group_key "$(work_icon)" 1 lighting)"
check "specular was turned off"               "false"       "$(icon_group_key "$(work_icon)" 1 specular)"
check "and translucency was enabled with it"  '{"enabled":true,"value":0.25}' \
                                                            "$(icon_group_key "$(work_icon)" 1 translucency)"

section "17. a group's shadow"
open_sample > /dev/null
select_group
adopt_group_controls
omc_control "$ID_GROUP_SHADOW" "neutral"
omc_control "$ID_GROUP_SHADOW_OPACITY" "0.8"
omc_run ICEdit.settings.apply
check "the shadow was written whole"          '{"kind":"neutral","opacity":0.8}' \
                                                            "$(icon_group_key "$(work_icon)" 1 shadow)"

section "18. a group's visibility and position are specializations"
open_sample > /dev/null
select_group
adopt_group_controls
omc_control "$ID_GROUP_VISIBLE" "false"
omc_control "$ID_GROUP_SCALE" "1.5"
omc_control "$ID_GROUP_SHIFT_X" "10"
omc_control "$ID_GROUP_SHIFT_Y" "-10"
omc_run ICEdit.settings.apply
check "visibility went to the square idiom" '[{"idiom":"square","value":true}]' \
                                                            "$(icon_group_key "$(work_icon)" 1 hidden-specializations)"
check "and so did the position" '[{"idiom":"square","value":{"scale":1.5,"translation-in-points":[10,-10]}}]' \
                                                            "$(icon_group_key "$(work_icon)" 1 position-specializations)"

section "19. Apply with no document open does nothing"
reset_document
omc_run ICEdit.settings.apply
check_status "the handler succeeded"          0
check "no document appeared"                  ""            "$(work_icon)"

section "cumulative: the window never wrote to a view id it does not declare"
# unknown_ids.log accumulates across the whole file, so this one assertion covers
# every section above it. The line before it is its positive control: if the
# bundle's id extraction had produced nothing the detector would be silently
# inert, and the assertion could not fail.
check "the id set was extracted"              "yes"         "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"
check "no undeclared ids"                     ""            "$(ui_unknown_writes)"
check "no bare value clobbered a table"       ""            "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
