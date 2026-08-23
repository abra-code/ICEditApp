#!/bin/sh
# Tests/30-layers.test.sh - the layer table's five mutations.
#
# Adding a layer through the Add Layer dialog and through a drop on the table,
# removing one, moving one up and down within its group, and toggling what is
# visible. Each is checked twice over: against the document on disk through the
# independent oracle, and against the table the user is actually looking at.
#
# The three of these that act on "the selected layer" read the selection out of
# the pasteboard rather than out of the table, so every such section reaches
# them through select_layer / select_group / select_background - which is also
# what 40-selection covers on its own.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

section "1. adding an SVG through the Add Layer dialog"
open_sample > /dev/null
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
check_status "the handler succeeded"          0
check "the layer is in the document"          "3"           "$(icon_layer_count "$(work_icon)")"
# add_svg prepends, so a new layer arrives on top - which is what a user
# dropping artwork onto an icon expects to see happen.
check "and it went on top"                    "Local"       "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 1p)"
check "its asset was copied in"               "1"           "$(icon_assets "$(work_icon)" | /usr/bin/grep -c '^Local.svg$')"
check "glass is on by default"                "true"        "$(icon_layer_key "$(work_icon)" Local glass)"
check "the table shows it first"              "Local"       "$(row_cell 1 $COL_NAME)"
check "and grew by one row"                   "5"           "$(ui_row_count $ID_LAYER_LIST)"
check "the document became dirty"             "1"           "$(dirty)"
check "the status line names the layer"       "Added layer 'Local'" "$(ui_value $ID_STATUS)"
check "the preview was re-rendered"           "yes"         "$([ -f "$(ui_value $ID_PREVIEW)" ] && echo yes || echo no)"

section "2. adding a bitmap takes the other branch"
# The extension is what routes the chosen file to add_image rather than add_svg.
# Without this section that branch is never walked at all.
open_sample > /dev/null
omc_dialog_answer choose_file "$(added_layer_png)"
omc_run ICEdit.layer.add
check_status "the handler succeeded"          0
check "the bitmap became a layer"             "3"           "$(icon_layer_count "$(work_icon)")"
check "named after the file"                  "Bitmap"      "$(icon_layers "$(work_icon)" | /usr/bin/sed -n 1p)"
check "and its asset came across as a png"    "1"           "$(icon_assets "$(work_icon)" | /usr/bin/grep -c '^Bitmap.png$')"

section "3. a canceled Add Layer changes nothing"
open_sample > /dev/null
# An empty dialog answer is Cancel: the whole OMC_DLG_CHOOSE_FILE family is
# unset, exactly as the engine leaves it.
omc_dialog_answer choose_file ""
omc_run ICEdit.layer.add
check_status "the handler succeeded"          0
check "no layer was added"                    "2"           "$(icon_layer_count "$(work_icon)")"
check "and the document stays clean"          ""            "$(dirty)"

section "4. a chosen path that is not a file changes nothing"
omc_dialog_answer choose_file "$OMCTEST_WORK/does-not-exist.svg"
omc_run ICEdit.layer.add
check_status "the handler succeeded"          0
check "no layer was added"                    "2"           "$(icon_layer_count "$(work_icon)")"
check "and the document stays clean"          ""            "$(dirty)"

section "5. dropping files on the table adds them all"
open_sample > /dev/null
omc_trigger "$ID_LAYER_LIST"
omc_drop "$(added_layer_svg Dropped)" "$(added_layer_png Raster)"
omc_run ICEdit.layer.drop
check_status "the handler succeeded"          0
check "both landed"                           "4"           "$(icon_layer_count "$(work_icon)")"
check "the SVG among them"                    "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Dropped$')"
check "and the bitmap"                        "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Raster$')"
check "the table was rebuilt"                 "6"           "$(ui_row_count $ID_LAYER_LIST)"
check "the document became dirty"             "1"           "$(dirty)"
check "the status line counts them"           "1"           "$(ui_calls "$ID_STATUS.Added 2 layers")"

section "6. a drop of files it cannot use is refused whole"
open_sample > /dev/null
printf 'not an image\n' > "$OMCTEST_WORK/notes.txt"
ui_reset
omc_trigger "$ID_LAYER_LIST"
omc_drop "$OMCTEST_WORK/notes.txt"
omc_run ICEdit.layer.drop
check_status "the handler succeeded"          0
check "nothing was added"                     "2"           "$(icon_layer_count "$(work_icon)")"
check "the document stays clean"              ""            "$(dirty)"
# Silently, and deliberately so: a drop the applet cannot use is not an error
# the user needs a status line about. The point of the check is that it also
# does not touch the window - section 5 is the positive control.
check "and the window was left alone"         "0"           "$(ui_calls '.')"

section "7. a drop mixing usable and unusable files takes the usable ones"
open_sample > /dev/null
omc_trigger "$ID_LAYER_LIST"
omc_drop "$OMCTEST_WORK/notes.txt" "$(added_layer_svg Dropped)"
omc_run ICEdit.layer.drop
check "the image was taken"                   "3"           "$(icon_layer_count "$(work_icon)")"
check "and it is the right one"               "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Dropped$')"
# The text file was filtered out before any add ran, so this reports one added
# and no failures rather than one of each.
check "the text file was not reported failed" "1"           "$(ui_calls "$ID_STATUS.Added 1 layer: Dropped")"

section "8. a drop whose payload is not JSON is refused"
open_sample > /dev/null
ui_reset
omc_trigger "$ID_LAYER_LIST" "" "this is not json"
omc_run ICEdit.layer.drop
check_status "the handler survived"           0
check "nothing was added"                     "2"           "$(icon_layer_count "$(work_icon)")"
check "and the window was left alone"         "0"           "$(ui_calls '.')"

section "9. removing the selected layer"
open_sample > /dev/null
select_layer Circle
omc_run ICEdit.layer.remove
check_status "the handler succeeded"          0
check "the layer is gone from the document"   "1"           "$(icon_layer_count "$(work_icon)")"
check "and the right one went"                "Square"      "$(icon_layers "$(work_icon)")"
check "its row left the table"                "3"           "$(ui_row_count $ID_LAYER_LIST)"
check "the selection was cleared"             ""            "$(selected_layer)"
check "the settings panes went away"          "0"           "$(ui_visible $ID_LAYER_PANE)"
check "the document became dirty"             "1"           "$(dirty)"
check "the status line names the layer"       "Removed layer 'Circle'" "$(ui_value $ID_STATUS)"

section "10. the background and the group are not removable"
open_sample > /dev/null
select_background
omc_run ICEdit.layer.remove
check_status "the handler succeeded"          0
check "the background survived"               "2"           "$(icon_layer_count "$(work_icon)")"
check "and said why"                          "Cannot remove this item" "$(ui_value $ID_STATUS)"
check "nothing became dirty"                  ""            "$(dirty)"
select_group
omc_run ICEdit.layer.remove
check "the group survived"                    "1"           "$(icon_groups "$(work_icon)" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "and said why"                          "Cannot remove this item" "$(ui_value $ID_STATUS)"

section "11. moving a layer down and back up"
open_sample > /dev/null
select_layer Square
omc_run ICEdit.layer.move.down
check_status "the handler succeeded"          0
check "it swapped with the one below"         "$(printf 'Circle\nSquare')" "$(icon_layers "$(work_icon)")"
check "the table followed"                    "Circle"      "$(row_cell 1 $COL_NAME)"
check "the document became dirty"             "1"           "$(dirty)"
omc_run ICEdit.layer.move.up
check "and back up again"                     "$(printf 'Square\nCircle')" "$(icon_layers "$(work_icon)")"
check "the table followed again"              "Square"      "$(row_cell 1 $COL_NAME)"

section "12. a layer at the end of the stack does not move past it"
open_sample > /dev/null
select_layer Square
ui_reset
omc_run ICEdit.layer.move.up
check_status "the handler succeeded"          0
check "the order is unchanged"                "$(printf 'Square\nCircle')" "$(icon_layers "$(work_icon)")"
# Nothing at all was pushed toward the window: the handler exits before it
# rebuilds anything. Section 11 is the positive control.
check "and the window was left alone"         "0"           "$(ui_calls '.')"
check "and it did not become dirty"           ""            "$(dirty)"
select_layer Circle
ui_reset
omc_run ICEdit.layer.move.down
check "the bottom layer stays at the bottom"  "$(printf 'Square\nCircle')" "$(icon_layers "$(work_icon)")"
check "and the window was left alone"         "0"           "$(ui_calls '.')"

section "13. toggling a layer's visibility"
open_sample > /dev/null
select_layer Circle
omc_run ICEdit.layer.toggle.visible
check_status "the handler succeeded"          0
check "the layer is hidden in the document"   "true"        "$(icon_layer_key "$(work_icon)" Circle hidden)"
check "and its row shows the closed eye"      "$VIS_OFF"    "$(row_cell 2 $COL_VISIBILITY)"
check "the other layer is untouched"          ""            "$(icon_layer_key "$(work_icon)" Square hidden)"
check "the document became dirty"             "1"           "$(dirty)"
omc_run ICEdit.layer.toggle.visible
# icedit REMOVES the key rather than writing false, so a visible layer carries
# no "hidden" at all - which is also how Icon Composer writes one. The eye check
# below is this assertion's positive control: an empty read here would mean the
# same thing as a layer that was never found, and the eye cannot be wrong that way.
check "toggling again clears the flag"        ""            "$(icon_layer_key "$(work_icon)" Circle hidden)"
check "and the eye opens"                     "$VIS_ON"     "$(row_cell 2 $COL_VISIBILITY)"

section "14. toggling a group's visibility"
open_sample > /dev/null
select_group
omc_run ICEdit.layer.toggle.visible
check_status "the handler succeeded"          0
# A group's visibility is a per-idiom specialization, not a plain "hidden" key.
check "the square idiom was hidden" '[{"idiom":"square","value":true}]' \
                                                            "$(icon_group_key "$(work_icon)" 1 hidden-specializations)"
check "and the group row shows it"            "$VIS_OFF"    "$(row_cell 3 $COL_VISIBILITY)"
check "the layers inside are untouched"       ""            "$(icon_layer_key "$(work_icon)" Circle hidden)"
omc_run ICEdit.layer.toggle.visible
check "toggling again shows the group" '[{"idiom":"square","value":false}]' \
                                                            "$(icon_group_key "$(work_icon)" 1 hidden-specializations)"

section "15. the background has no visibility to toggle"
open_sample > /dev/null
select_background
ui_reset
omc_run ICEdit.layer.toggle.visible
check_status "the handler succeeded"          0
check "the document is untouched"             ""            "$(dirty)"
check "and the window was left alone"         "0"           "$(ui_calls '.')"

section "16. every mutation refuses to run with no document open"
# reset_document leaves no icon_path, which is what each handler checks first.
# Without this section those early returns are never walked.
reset_document
for handler in ICEdit.layer.add ICEdit.layer.remove ICEdit.layer.move.up \
    ICEdit.layer.move.down ICEdit.layer.toggle.visible ICEdit.layer.drop; do
    omc_run "$handler"
    check_status "$handler exits cleanly" 0
done
check "and none of them made a document"      ""            "$(work_icon)"

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
