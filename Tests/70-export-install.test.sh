#!/bin/sh
# Tests/70-export-install.test.sh - getting the icon out of ICEdit.
#
# Export writes a compiled Assets.car, an .icns and a partial Info.plist into a
# chosen folder; Install puts the same two files into a chosen .app and rewrites
# its Info.plist. Both compile with actool, which is real here: it is
# deterministic, safe to run, and faking it would leave the assertions with
# nothing worth checking. Xcode is therefore a precondition, asserted where the
# first compile happens rather than discovered as a run of puzzling failures.
#
# Neither handler routes actool through an overridable variable, so there is no
# seam to point at a fake (omctest guide section 8). That is not a gap in
# coverage here - it is why the compiles below are real.
#
# Open in Icon Composer is the third way out and is covered here too; it is the
# one handler in the applet that reaches an external binary by bare name, so it
# is the one that can be intercepted rather than run for real.
#
# The .app fixture is synthesized: a Contents/MacOS/Info.plist skeleton and a
# copy of /bin/echo for a binary. Install rewrites and deletes files inside
# whatever it is given, so it is pointed at something built for the purpose and
# never at a real application.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

# A minimal but genuine .app: the two directories install.py checks for, an
# Info.plist plutil can rewrite, and a real executable so the bundle is not a
# shape no installer would ever meet.
make_target_app() { # [name, default Target.app] [existing-icon-name] -> prints the path
    local app_path="$OMCTEST_WORK/${1:-Target.app}" icon_name="$2"
    /bin/rm -rf "$app_path"
    /bin/mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    /bin/cp /bin/echo "$app_path/Contents/MacOS/Target"
    /bin/cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Target</string>
    <key>CFBundleIdentifier</key><string>com.example.target</string>
    <key>CFBundleIconFile</key><string>$icon_name</string>
    <key>CFBundleIconName</key><string>$icon_name</string>
</dict>
</plist>
PLIST
    printf '%s' "$app_path"
}

# An empty destination of its own for each exporting section.
fresh_export_dir() { # <label> -> prints the path
    local dir="$OMCTEST_WORK/exports-$1"
    /bin/rm -rf "$dir"
    /bin/mkdir -p "$dir"
    printf '%s' "$dir"
}

plist_string() { # <plist> <key>
    /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

section "1. Export refuses a document that has never been saved"
# actool compiles the ORIGINAL on disk, not the working copy, so a document with
# no original has nothing to compile - and saying so is better than compiling
# the wrong thing.
reset_document
omc_object ""
omc_run ICEdit.main
omc_dialog_answer choose_folder "$OMCTEST_WORK"
omc_run ICEdit.export
check_status "the handler stops cleanly"      0
check "and says what to do first"             "Save the icon first before exporting" "$(ui_value $ID_STATUS)"
check_absent "nothing was written"            "$OMCTEST_WORK/Untitled-Exported"

section "2. a canceled folder choice exports nothing"
open_sample > /dev/null
omc_dialog_answer choose_folder ""
omc_run ICEdit.export
check_status "the handler stops cleanly"      0
check "and says so"                           "Export cancelled" "$(ui_value $ID_STATUS)"
check_absent "nothing was written"            "$OMCTEST_WORK/Sample-Exported"

section "3. exporting a saved document compiles it"
check "precondition: Xcode's actool is available" "yes"     "$(icedit_is 'ACTOOL is not None')"
open_sample > /dev/null
# A destination of its own, and rebuilt. Sharing one across sections would let
# an artifact an earlier export wrote satisfy this one's check_exists, and the
# section would pass on a handler that compiled nothing at all.
exports="$(fresh_export_dir plain)"
omc_dialog_answer choose_folder "$exports"
omc_run ICEdit.export
check_status "the handler succeeded"          0
# The subdirectory is named after the document, so exporting two icons into one
# folder does not have them overwrite each other.
check_exists "the compiled catalog"           "$exports/Sample-Exported/Assets.car"
check_exists "the icon file"                  "$exports/Sample-Exported/Sample.icns"
check_exists "and the plist fragment"         "$exports/Sample-Exported/partial-Info.plist"
check "the fragment names the icon"           "Sample"      "$(plist_string "$exports/Sample-Exported/partial-Info.plist" CFBundleIconName)"
check "the status line lists what came out"   "1"           "$(ui_calls "$ID_STATUS.Exported to Sample-Exported")"
check "and the document was not made dirty"   ""            "$(dirty)"

section "4. exporting with unsaved changes offers to save first"
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
exports="$(fresh_export_dir canceled)"
omc_dialog_answer choose_folder "$exports"
# The --other slot is Cancel: stop before writing anything at all.
alert_answer 2
omc_run ICEdit.export
check_status "the handler stops cleanly"      0
check "the user was asked"                    "1"           "$(alerts_mention 'Unsaved Changes')"
check "Cancel left the edit unsaved"          "1"           "$(dirty)"
check "and did not touch the disk"            "2"           "$(icon_layer_count "$sample")"
check_absent "and compiled nothing"           "$exports/Sample-Exported"

section "5. Save and Export saves before compiling"
alerts_reset
alert_answer 0
exports="$(fresh_export_dir saved)"
omc_dialog_answer choose_folder "$exports"
omc_run ICEdit.export
check_status "the handler succeeded"          0
check "the edit reached the disk"             "3"           "$(icon_layer_count "$sample")"
check "the document is clean"                 ""            "$(dirty)"
check_exists "and it compiled"                "$exports/Sample-Exported/Assets.car"

section "6. Export Without Saving compiles the stale file on purpose"
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
alerts_reset
alert_answer 1
exports="$(fresh_export_dir stale)"
omc_dialog_answer choose_folder "$exports"
omc_run ICEdit.export
check_status "the handler succeeded"          0
check "the user was asked"                    "1"           "$(alerts_mention 'Unsaved Changes')"
# The whole point of the third button: the file on disk is what gets compiled,
# and the unsaved edit stays unsaved. Section 5 is its positive control.
check "the disk was not written"              "2"           "$(icon_layer_count "$sample")"
check "the edit is still unsaved"             "1"           "$(dirty)"
check_exists "and the stale version compiled" "$exports/Sample-Exported/Assets.car"

section "7. Install refuses anything that is not an app bundle"
open_sample > /dev/null
omc_dialog_answer choose_object "$OMCTEST_WORK/notes-not-an-app"
printf 'not an app\n' > "$OMCTEST_WORK/notes-not-an-app"
omc_run ICEdit.install
check_status "the handler reports failure"    1
check "the user was told"                     "1"           "$(alerts_mention 'Not an App Bundle')"
check "and the status line says so"           "Install failed: not a .app bundle" "$(ui_value $ID_STATUS)"

section "8. a canceled app choice installs nothing"
omc_dialog_answer choose_object ""
omc_run ICEdit.install
check_status "the handler stops cleanly"      0
check "and says so"                           "Install cancelled" "$(ui_value $ID_STATUS)"

section "9. an app bundle with no Resources directory is refused"
app="$(make_target_app)"
/bin/rm -rf "$app/Contents/Resources"
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler reports failure"    1
check "and names the missing piece"           "No Contents/Resources in Target.app" "$(ui_value $ID_STATUS)"

section "10. an app bundle with no Info.plist is refused"
app="$(make_target_app)"
/bin/rm -f "$app/Contents/Info.plist"
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler reports failure"    1
check "and names the missing piece"           "No Info.plist in Target.app" "$(ui_value $ID_STATUS)"

section "11. installing into a bare app"
open_sample > /dev/null
app="$(make_target_app)"
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler succeeded"          0
# The app had no Assets.car and no .icns, so nothing was at risk and nothing was
# asked. Section 13 is the case where something was.
check "the user was not interrupted"          "0"           "$(alerts_count)"
check_exists "the catalog was installed"      "$app/Contents/Resources/Assets.car"
check_exists "and the icon file"              "$app/Contents/Resources/Sample.icns"
check "Info.plist points at the new icon"     "Sample"      "$(plist_string "$app/Contents/Info.plist" CFBundleIconFile)"
check "under both keys"                       "Sample"      "$(plist_string "$app/Contents/Info.plist" CFBundleIconName)"
check "the status line names the app"         "1"           "$(ui_calls "$ID_STATUS.Installed into Target")"

section "12. installing compiles the WORKING copy, not the file on disk"
# Install and Export differ here, and it is worth pinning: export compiles the
# original, install compiles what the user is looking at. So an unsaved edit
# reaches the app, and install never asks about saving.
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
app="$(make_target_app)"
alerts_reset
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler succeeded"          0
check "it did not ask about saving"           "0"           "$(alerts_mention 'Unsaved Changes')"
check_exists "and it installed"               "$app/Contents/Resources/Assets.car"
check "the edit is still unsaved"             "1"           "$(dirty)"
check "and the disk copy is untouched"        "2"           "$(icon_layer_count "$sample")"

section "13. installing over existing resources asks first"
open_sample > /dev/null
app="$(make_target_app)"
printf 'old catalog\n' > "$app/Contents/Resources/Assets.car"
alerts_reset
alert_answer 1
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler stops cleanly"      0
check "the user was asked"                    "1"           "$(alerts_mention 'Replace Existing Files')"
check "and Cancel left the old file alone"    "old catalog" "$(/bin/cat "$app/Contents/Resources/Assets.car")"
check "the status line says so"               "Install cancelled" "$(ui_value $ID_STATUS)"

section "14. Replace goes through with it"
alerts_reset
alert_answer 0
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler succeeded"          0
check "the user was asked"                    "1"           "$(alerts_mention 'Replace Existing Files')"
check "and the old file was replaced"         "no"          "$([ "$(/bin/cat "$app/Contents/Resources/Assets.car")" = "old catalog" ] && echo yes || echo no)"

section "15. an app whose old icon had a different name loses it"
# The stale-icns case: an app previously carrying Old.icns must not end up with
# both files, or the icon cache can keep serving the one nobody asked for.
open_sample > /dev/null
app="$(make_target_app Target.app Old)"
printf 'old icon\n' > "$app/Contents/Resources/Old.icns"
alerts_reset
alert_answer 0
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler succeeded"          0
check "the replacement was announced"         "1"           "$(alerts_mention 'Old.icns')"
check_exists "the new icon is there"          "$app/Contents/Resources/Sample.icns"
check_absent "and the old one is gone"        "$app/Contents/Resources/Old.icns"
check "Info.plist was repointed"              "Sample"      "$(plist_string "$app/Contents/Info.plist" CFBundleIconFile)"

section "16. Install refuses with no document open"
reset_document
app="$(make_target_app)"
omc_dialog_answer choose_object "$app"
omc_run ICEdit.install
check_status "the handler reports failure"    1
check "and says so"                           "No icon to install" "$(ui_value $ID_STATUS)"
check_absent "the app was not touched"        "$app/Contents/Resources/Assets.car"

section "17. Open in Icon Composer refuses a document that has never been saved"
# Icon Composer is handed the ORIGINAL, so like Export there is nothing to hand
# it until the document has been saved once.
intercept_open
reset_document
omc_object ""
omc_run ICEdit.main
omc_run ICEdit.open.in.composer
check_status "the handler stops cleanly"      0
check "and says what to do first"             "Save the icon first before opening in Icon Composer" \
                                                            "$(ui_value $ID_STATUS)"
check "nothing was launched"                  "0"           "$(opens_count)"

section "18. a clean document opens without a word"
sample="$(open_sample)"
opens_reset
alerts_reset
omc_run ICEdit.open.in.composer
check_status "the handler succeeded"          0
check "the user was not interrupted"          "0"           "$(alerts_count)"
check "Icon Composer was launched once"       "1"           "$(opens_count)"
# The document on disk, never the working copy - Icon Composer editing a copy in
# $TMPDIR would put the user's changes somewhere they can never find them, and
# it is 20-close section 6 that notices when they come back.
check "and handed the document on disk"       "1"           "$(opens_mention "$sample")"
check "as an application argument"            "1"           "$(opens_mention 'Icon Composer.app')"
check "the status line says so"               "Opened in Icon Composer" "$(ui_value $ID_STATUS)"

section "19. unsaved changes are raised before handing the file over"
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
opens_reset
alerts_reset
alert_answers_reset
# The --other slot is Cancel.
alert_answer 2
omc_run ICEdit.open.in.composer
check_status "the handler stops cleanly"      0
check "the user was asked"                    "1"           "$(alerts_mention 'Unsaved Changes')"
check "Cancel launched nothing"               "0"           "$(opens_count)"
check "and left the edit unsaved"             "1"           "$(dirty)"
check "with the disk copy untouched"          "2"           "$(icon_layer_count "$sample")"

section "20. Save and Open writes first"
opens_reset
alerts_reset
alert_answers_reset
alert_answer 0
omc_run ICEdit.open.in.composer
check_status "the handler succeeded"          0
check "the edit reached the disk"             "3"           "$(icon_layer_count "$sample")"
check "the document is clean"                 ""            "$(dirty)"
check "and it was fingerprinted"              "yes"         "$([ -n "$(original_hash)" ] && echo yes || echo no)"
check "then it was launched"                  "1"           "$(opens_count)"

section "21. Open Without Saving hands over the stale file on purpose"
sample="$(open_sample)"
omc_dialog_answer choose_file "$(added_layer_svg)"
omc_run ICEdit.layer.add
opens_reset
alerts_reset
alert_answers_reset
alert_answer 1
omc_run ICEdit.open.in.composer
check_status "the handler succeeded"          0
check "the user was asked"                    "1"           "$(alerts_mention 'Unsaved Changes')"
# The point of the middle button, and the same shape as Export Without Saving in
# section 6: what reaches Icon Composer is the file on disk, and the unsaved
# edit stays unsaved. Section 20 is its positive control.
check "the disk was not written"              "2"           "$(icon_layer_count "$sample")"
check "the edit is still unsaved"             "1"           "$(dirty)"
check "and it was launched anyway"            "1"           "$(opens_count)"

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
