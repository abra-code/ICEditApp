#!/bin/sh
# Tests/40-selection.test.sh - what selecting a row puts in the inspector.
#
# ICEdit.layer.select is the applet's busiest handler and its only reader of the
# table: it decides which of the three settings panes the user sees, fills every
# control in it from the document, and records the selection in the pasteboard
# for the handlers in 30-layers and 50-settings to act on.
#
# The values it writes for keys the document does NOT carry are the point of
# several sections below. Icon Composer omits a key when it holds the default,
# so "absent" and "the default" have to mean the same thing in the window, and
# the defaults are per-key rather than uniform - glass and specular default on,
# lighting to "individual", a layer's missing fill to "automatic" rather than to
# parse_fill's own "none".
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

# A document with every optional key spelled out, so the sections below can tell
# "read from the file" apart from "fell back to the default". The sample fixture
# is its opposite: it omits nearly everything.
make_explicit_icon() { # -> prints the icon path
    local icon_path="$OMCTEST_WORK/Explicit.icon"
    /bin/rm -rf "$icon_path"
    /bin/mkdir -p "$icon_path/Assets"
    make_sample_svg "$icon_path/Assets/Mono.svg" "#123456"
    /bin/cat > "$icon_path/icon.json" <<'JSON'
{
  "fill" : { "linear-gradient" : [ "srgb:1.00000,0.00000,0.00000,1.00000",
                                   "srgb:0.00000,0.00000,1.00000,1.00000" ] },
  "groups" : [
    {
      "name" : "Marks",
      "opacity" : 0.5,
      "blend-mode" : "multiply",
      "blur-material" : 0.25,
      "lighting" : "combined",
      "specular" : false,
      "translucency" : { "enabled" : true, "value" : 0.75 },
      "shadow" : { "kind" : "neutral", "opacity" : 0.3 },
      "hidden-specializations" : [ { "idiom" : "square", "value" : true } ],
      "position-specializations" : [ { "idiom" : "square",
                                       "value" : { "scale" : 2.5,
                                                   "translation-in-points" : [ 12, -34 ] } } ],
      "layers" : [
        {
          "name" : "Mono",
          "image-name" : "Mono.svg",
          "fill" : { "solid" : "display-p3:0.25098,0.50196,0.75294,1.00000" },
          "blend-mode" : "plus-darker",
          "glass" : false,
          "hidden" : true,
          "position" : { "scale" : 3.5, "translation-in-points" : [ 7, -9 ] }
        }
      ]
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
JSON
    printf '%s' "$icon_path"
}

open_explicit() {
    local icon_path
    icon_path="$(make_explicit_icon)"
    reset_document
    omc_object "$icon_path"
    omc_run ICEdit.main
    printf '%s' "$icon_path"
}

section "1. selecting the background shows the background pane"
open_sample > /dev/null
select_background
check_status "the handler succeeded"          0
check "the background pane came forward"      "1"           "$(ui_visible $ID_BG_PANE)"
check "the layer pane went away"              "0"           "$(ui_visible $ID_LAYER_PANE)"
check "and the group pane too"                "0"           "$(ui_visible $ID_GROUP_PANE)"
check "the selection was recorded"            "Background"  "$(selected_layer)"
check "typed as the background"               "$TYPE_BG"    "$(selected_type)"
# Remove is only meaningful for a layer, and the background is not one.
check "Remove was disabled"                   "0"           "$(ui_enabled $ID_BTN_REMOVE)"
check "the fill kind was read out"            "auto-gradient" "$(ui_value $ID_BG_FILL)"
# The document stores extended-srgb floats; the ColorPicker takes hex. The
# fixture's gradient is icedit's own encoding of #0088FF, and it comes back one
# step short in the green channel: color_to_hex TRUNCATES rather than rounds, so
# 0.53333 * 255 = 135.99 becomes 135 rather than 136. Display-only - both sides
# of settings.apply's comparison truncate identically, so the value on disk does
# not drift - but the well the user is looking at is off by one. 80-library
# pins the truncation directly and shows the round trip failing.
check "and converted to hex for the picker"   "#0087FF"     "$(ui_value $ID_BG_COLOR1_PICKER)"
check "one color well is shown"               "1"           "$(ui_visible $ID_BG_COLOR1)"
check "the second is not"                     "0"           "$(ui_visible $ID_BG_COLOR2)"
check "and the first is labeled plainly"      "Color"       "$(ui_value $ID_BG_COLOR1_LABEL)"

section "2. a two-stop gradient shows both color wells"
open_explicit > /dev/null
select_background
check "the fill kind was read out"            "gradient"    "$(ui_value $ID_BG_FILL)"
check "the start color"                       "#FF0000"     "$(ui_value $ID_BG_COLOR1_PICKER)"
check "the stop color"                        "#0000FF"     "$(ui_value $ID_BG_COLOR2_PICKER)"
check "both wells are shown"                  "1"           "$(ui_visible $ID_BG_COLOR2)"
# The labels change meaning with the fill kind, which is the only thing telling
# the user which well is which end of the gradient.
check "and they are labeled as ends"          "Start"       "$(ui_value $ID_BG_COLOR1_LABEL)"
check "of a run"                              "Stop"        "$(ui_value $ID_BG_COLOR2_LABEL)"

section "3. selecting a layer shows the layer pane"
open_sample > /dev/null
select_layer Circle
check_status "the handler succeeded"          0
check "the layer pane came forward"           "1"           "$(ui_visible $ID_LAYER_PANE)"
check "the background pane went away"         "0"           "$(ui_visible $ID_BG_PANE)"
check "and the group pane too"                "0"           "$(ui_visible $ID_GROUP_PANE)"
check "the selection was recorded"            "Circle"      "$(selected_layer)"
check "typed as a layer"                      "$TYPE_LAYER" "$(selected_type)"
check "Remove was enabled"                    "1"           "$(ui_enabled $ID_BTN_REMOVE)"
check "the name reached the field"            "Circle"      "$(ui_value $ID_LAYER_NAME)"
check "the scale came from the position"      "7.68"        "$(ui_value $ID_LAYER_SCALE)"
check "and the shift"                         "0"           "$(ui_value $ID_LAYER_SHIFT_X)"
check "in both axes"                          "0"           "$(ui_value $ID_LAYER_SHIFT_Y)"

section "4. a layer's absent keys read as Icon Composer's defaults"
# The fixture writes none of these, so every value below is a default the
# handler supplied. Section 5 is the positive control: the same four controls
# read the file when the file says something.
check "a missing fill means automatic"        "automatic"   "$(ui_value $ID_LAYER_FILL)"
check "a missing blend means normal"          "normal"      "$(ui_value $ID_LAYER_BLEND)"
check "a missing hidden means visible"        "true"        "$(ui_value $ID_LAYER_VISIBLE)"
# glass IS present in the fixture and is true; the default when absent is also
# true, which is why section 5 sets it false to tell them apart.
check "glass is on"                           "true"        "$(ui_value $ID_LAYER_GLASS)"
check "and no color well is shown"            "0"           "$(ui_visible $ID_LAYER_COLOR1)"

section "5. a layer that spells its keys out reads them back"
open_explicit > /dev/null
select_layer Mono
check "the solid fill kind"                   "solid"       "$(ui_value $ID_LAYER_FILL)"
# display-p3 goes through the same conversion, and shows the same truncation:
# 0.25098 * 255 = 63.999 lands on 63 rather than 64, so the exact #4080C0 the
# fixture encodes reads back as #3F7FBF.
check "converted to hex"                      "#3F7FBF"     "$(ui_value $ID_LAYER_COLOR1_PICKER)"
check "one well is shown for a solid"         "1"           "$(ui_visible $ID_LAYER_COLOR1)"
check "and only one"                          "0"           "$(ui_visible $ID_LAYER_COLOR2)"
check "the blend mode"                        "plus-darker" "$(ui_value $ID_LAYER_BLEND)"
check "glass off means off"                   "false"       "$(ui_value $ID_LAYER_GLASS)"
check "hidden true means not visible"         "false"       "$(ui_value $ID_LAYER_VISIBLE)"
check "the scale"                             "3.5"         "$(ui_value $ID_LAYER_SCALE)"
check "the horizontal shift"                  "7"           "$(ui_value $ID_LAYER_SHIFT_X)"
check "and the vertical one, sign and all"    "-9"          "$(ui_value $ID_LAYER_SHIFT_Y)"

section "6. selecting a group shows the group pane"
open_sample > /dev/null
select_group
check_status "the handler succeeded"          0
check "the group pane came forward"           "1"           "$(ui_visible $ID_GROUP_PANE)"
check "the layer pane went away"              "0"           "$(ui_visible $ID_LAYER_PANE)"
check "the selection was recorded"            "Group"       "$(selected_layer)"
check "typed as a group"                      "$TYPE_GROUP" "$(selected_type)"
check "Remove was disabled"                   "0"           "$(ui_enabled $ID_BTN_REMOVE)"
# The fixture's group is unnamed, and the table shows "Group" for that. The NAME
# FIELD must stay empty rather than adopt the placeholder, or the first Apply
# would rename an unnamed group to "Group".
check "an unnamed group leaves the field empty" ""          "$(ui_value $ID_GROUP_NAME)"

section "7. a group's absent keys read as Icon Composer's defaults"
check "opacity"                               "1.0"         "$(ui_value $ID_GROUP_OPACITY)"
check "blend mode"                            "normal"      "$(ui_value $ID_GROUP_BLEND)"
check "blur"                                  "0.0"         "$(ui_value $ID_GROUP_BLUR)"
check "lighting"                              "individual"  "$(ui_value $ID_GROUP_LIGHTING)"
check "specular"                              "true"        "$(ui_value $ID_GROUP_SPECULAR)"
check "translucency"                          "1.0"         "$(ui_value $ID_GROUP_TRANSLUCENCY)"
check "shadow kind"                           "none"        "$(ui_value $ID_GROUP_SHADOW)"
check "shadow opacity"                        "0.5"         "$(ui_value $ID_GROUP_SHADOW_OPACITY)"
check "visibility"                            "true"        "$(ui_value $ID_GROUP_VISIBLE)"
check "scale"                                 "1.0"         "$(ui_value $ID_GROUP_SCALE)"
check "shift"                                 "0"           "$(ui_value $ID_GROUP_SHIFT_X)"
check "in both axes"                          "0"           "$(ui_value $ID_GROUP_SHIFT_Y)"

section "8. a group that spells its keys out reads them back"
open_explicit > /dev/null
select_group Marks
check "the name"                              "Marks"       "$(ui_value $ID_GROUP_NAME)"
check "opacity"                               "0.5"         "$(ui_value $ID_GROUP_OPACITY)"
check "blend mode"                            "multiply"    "$(ui_value $ID_GROUP_BLEND)"
check "blur"                                  "0.25"        "$(ui_value $ID_GROUP_BLUR)"
check "lighting"                              "combined"    "$(ui_value $ID_GROUP_LIGHTING)"
check "specular"                              "false"       "$(ui_value $ID_GROUP_SPECULAR)"
# Translucency is a nested {enabled, value}: with enabled false the VALUE is
# ignored and the control reads 1.0, which is why the fixture enables it.
check "translucency"                          "0.75"        "$(ui_value $ID_GROUP_TRANSLUCENCY)"
check "shadow kind"                           "neutral"     "$(ui_value $ID_GROUP_SHADOW)"
check "shadow opacity"                        "0.3"         "$(ui_value $ID_GROUP_SHADOW_OPACITY)"
# Group visibility and position are per-idiom specializations rather than plain
# keys, so these two also pin the square-idiom lookup.
check "visibility"                            "false"       "$(ui_value $ID_GROUP_VISIBLE)"
check "scale"                                 "2.5"         "$(ui_value $ID_GROUP_SCALE)"
check "the horizontal shift"                  "12"          "$(ui_value $ID_GROUP_SHIFT_X)"
check "and the vertical one, sign and all"    "-34"         "$(ui_value $ID_GROUP_SHIFT_Y)"

section "9. selecting an empty row clears everything"
open_sample > /dev/null
select_layer Circle
omc_table_cell "$ID_LAYER_LIST" "$COL_INDENT" ""
omc_table_cell "$ID_LAYER_LIST" "$COL_TYPE" ""
omc_table_cell "$ID_LAYER_LIST" "$COL_NAME" ""
omc_fire ICEdit.layer.select "$ID_LAYER_LIST"
check_status "the handler succeeded"          0
check "every pane went away"                  "0"           "$(ui_visible $ID_BG_PANE)"
check "including the layer one"               "0"           "$(ui_visible $ID_LAYER_PANE)"
check "and the group one"                     "0"           "$(ui_visible $ID_GROUP_PANE)"
check "the selection was forgotten"           ""            "$(selected_layer)"
check "and so was its type"                   ""            "$(selected_type)"

section "10. selecting a layer the document does not have clears the panes"
# The stale-row case: the table still holds a name the document lost. It must
# not leave the previous layer's values on screen under the new name.
open_sample > /dev/null
select_layer Circle
select_layer Vanished
check_status "the handler succeeded"          0
check "every pane went away"                  "0"           "$(ui_visible $ID_LAYER_PANE)"
check "and the background one"                "0"           "$(ui_visible $ID_BG_PANE)"
# The selection IS recorded before the lookup fails, which is what makes the
# pane-hiding above the thing that matters.
check "the name was still recorded"           "Vanished"    "$(selected_layer)"

section "11. selecting with no document open does nothing"
reset_document
select_layer Circle
check_status "the handler succeeded"          0
check "nothing was selected"                  ""            "$(selected_layer)"

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
