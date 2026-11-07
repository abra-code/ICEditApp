# Tests/icedit.itest.sh - ICEdit through the real engine (appletbuilder itest, OMC 5.5).
#
# The omctest suites (*.test.sh) run ICEdit's Python handlers one at a time with stand-in tools;
# this file launches the applet itself: the new document at launch, and opening a .icon bundle
# through ICEdit.open and its NEXT_COMMAND_ID ICEdit.main (the checklist's "open a document"),
# then Add Layer with Image and Save As in the launch's window. Those two are a menu item without a
# view id and a menu bar command for the key window, which a test launch does not have, so the test
# runs them as the window's subcommand (itest_run --window), as their menu items would.
# The test's own files stay in $ITEST_WORK and are never saved over; ICEdit keeps its working
# copies in $TMPDIR (the test's own), and its close handler removes them.
#
# Not here yet: plain Save of a document that has a file (ICEdit.save), and closing a window.

eval "$(/usr/bin/sed -n 's/^\(ID_[A-Z_]*\) *= *\([0-9][0-9]*\).*$/\1=\2/p' \
    "$ITEST_APP/Contents/Resources/Scripts/lib_icedit.py")"
check "the view ids imported from lib_icedit.py" "100 399" "$ID_LAYER_LIST $ID_STATUS"

# The layer table's row names, one per line: column 3 (COL_NAME in lib.test.icedit.sh; column 1 is
# the row's icon). The helper runs with the harness's own Python (AppletBuilder's), not whatever
# python3 the machine has.
COL_NAME=3
ICEDIT_ITEST_HELPERS="$(/usr/bin/dirname "${BASH_SOURCE[0]}")/helpers"
row_names() { # <window>
    itest_call actionui.getRows "{\"window\": \"$1\", \"viewID\": $ID_LAYER_LIST}" \
        | "$OMCITEST_PYTHON" "$ICEDIT_ITEST_HELPERS/itest_rows_column.py" "$COL_NAME"
}

make_svg() { # <path> <color>
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="%s"/></svg>\n' "$2" > "$1"
}

SAMPLE="$ITEST_WORK/Sample.icon"
/bin/mkdir -p "$SAMPLE/Assets"
make_svg "$SAMPLE/Assets/Square.svg" "#00FF00"
/bin/cat > "$SAMPLE/icon.json" <<'JSON'
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
        }
      ]
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
JSON
SAMPLE_JSON_BEFORE="$(/bin/cat "$SAMPLE/icon.json")"

section "The launch opens a new document"
launched="$(itest_windows)"
check "one window" "1" "$(printf '%s\n' "$launched" | /usr/bin/grep -c .)"
check "a new icon" "New icon" "$(itest_value "$launched" "$ID_STATUS")"
check "holding only the background" "Background" "$(row_names "$launched")"

section "ICEdit.open chains to ICEdit.main, which shows the document"
before="$(itest_windows)"
itest_run ICEdit.open --file "$SAMPLE" > /dev/null
itest_wait_idle 60
window="$(itest_new_window "$before")"
check "a second window opened" "yes" "$([ -n "$window" ] && printf yes || printf no)"
check "with the layer, its group and the background" "$(printf 'Square\nGroup\nBackground')" "$(row_names "$window")"
check "and says which document it loaded" "Loaded Sample.icon" "$(itest_value "$window" "$ID_STATUS")"
check "no open panel: the document came with the command" "0" "$(itest_panel_count)"

check "which still holds the new document" "Background" "$(row_names "$launched")"
check "the document on disk is untouched" "$SAMPLE_JSON_BEFORE" "$(/bin/cat "$SAMPLE/icon.json")"

section "Add Layer with Image, run as the window's subcommand"
make_svg "$ITEST_WORK/Circle.svg" "#FF0000"
itest_answer_open "$ITEST_WORK/Circle.svg"
run="$(itest_run ICEdit.layer.add --window "$launched")"
itest_wait_idle 60
check "a file chooser was asked for" "open" "$(itest_panel last kind)"
check "and answered" "false" "$(itest_panel last canceled)"
check "the layer joined the new document" "$(printf 'Circle\nGroup\nBackground')" "$(row_names "$launched")"
check_contains "the window took the command" '"dispatchedToWindow": true' "$(itest_call omc.test.log "{\"run\": $run}")"

section "Save As writes the document where the user chose"
itest_answer_save "$ITEST_WORK/Saved.icon"
itest_run ICEdit.save.as --window "$launched" > /dev/null
itest_wait_idle 60
check "a save panel" "save" "$(itest_panel last kind)"
check "offering the new document's name" "Untitled.icon" "$(itest_panel last defaultName)"
check "the bundle was written" "yes" "$([ -f "$ITEST_WORK/Saved.icon/icon.json" ] && printf yes || printf no)"
check_contains "with the added layer" '"Circle"' "$(/bin/cat "$ITEST_WORK/Saved.icon/icon.json" 2>/dev/null)"
check "and its image" "yes" "$([ -f "$ITEST_WORK/Saved.icon/Assets/Circle.svg" ] && printf yes || printf no)"
check "the status names the saved document" "Saved Saved.icon" "$(itest_value "$launched" "$ID_STATUS")"
check "the opened document is still untouched" "$SAMPLE_JSON_BEFORE" "$(/bin/cat "$SAMPLE/icon.json")"
