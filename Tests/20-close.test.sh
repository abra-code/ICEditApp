#!/bin/sh
# Tests/20-close.test.sh - closing a window, and noticing the file changed under it.
#
# Two things that only happen at the edges of a document's life and are
# therefore the least likely to be walked by hand: what ICEdit.window.close does
# with unsaved changes, and what ICEdit.window.activated does when the file on
# disk no longer matches the one that was opened.
#
# Section 4 documents a real leak rather than blessing it - read its comment
# before treating a green run here as evidence that close cleans up.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.icedit.sh"

# Make the open document dirty the way a user would - by adding a layer - so
# every close scenario below starts from a state the applet itself produced.
dirty_the_document() {
    omc_dialog_answer choose_file "$(added_layer_svg)"
    omc_run ICEdit.layer.add
}

section "1. closing a document with unsaved changes asks first"
sample="$(open_sample)"
dirty_the_document
work_copy="$(work_icon)"
alert_answer 0
omc_run ICEdit.window.close
check_status "the handler succeeded"          0
check "the user was asked"                    "1"           "$(alerts_count)"
check "and asked about saving"                "1"           "$(alerts_mention 'Unsaved Changes')"
# The alert names the document, because "save changes to what" is the question.
check "the alert names the document"          "1"           "$(alerts_mention 'Sample.icon')"
check "Save wrote the edit to disk"           "3"           "$(icon_layer_count "$sample")"
check_absent "and the working copy was removed" "$work_copy"
check "the state was released"                ""            "$(work_icon)"
check "including the dirty flag"              ""            "$(dirty)"

section "2. an untitled document closes through Save As"
# There is nowhere to write, so Save on close cannot save: it flags the reason
# and chains, and save.as does the cleanup close would otherwise have done.
reset_document
omc_object ""
omc_run ICEdit.main
dirty_the_document
work_copy="$(work_icon)"
alert_answer 0
omc_run ICEdit.window.close
check "the user was asked"                    "1"           "$(alerts_count)"
check "the alert says Untitled"               "1"           "$(alerts_mention 'Untitled')"
check "Save As was asked for"                 "1"           "$(chain_asked ICEdit.save.as)"
check "and told it is closing"                "1"           "$(close_after_save)"
check "nothing was cleaned up yet"            "yes"         "$([ -d "$work_copy" ] && echo yes || echo no)"
omc_dialog_answer save_as "$OMCTEST_WORK/Closed.icon"
omc_run ICEdit.save.as
check_exists "the document reached disk"      "$OMCTEST_WORK/Closed.icon/icon.json"
check "with the unsaved layer in it"          "1"           "$(icon_layer_count "$OMCTEST_WORK/Closed.icon")"
check_absent "and now the working copy is gone" "$work_copy"
check "the state was released"                ""            "$(work_icon)"
# The window is going away either way, so a canceled Save As must still clean up
# rather than leave the scratch tree behind - section 3 is that case.

section "3. canceling the Save As of a closing window still cleans up"
reset_document
omc_object ""
omc_run ICEdit.main
dirty_the_document
work_copy="$(work_icon)"
alert_answer 0
omc_run ICEdit.window.close
check "it is closing"                         "1"           "$(close_after_save)"
omc_dialog_answer save_as ""
omc_run ICEdit.save.as
check_status "the handler succeeded"          0
check_absent "the working copy went away anyway" "$work_copy"
check "and so did the state"                  ""            "$(work_icon)"
check "the closing flag was cleared"          ""            "$(close_after_save)"

section "4. KNOWN DEFECT: every other close path leaks the working copy"
# ICEdit.window.close only ever calls cleanup_state() inside the "if is_dirty()"
# block, and inside that block only on the Save branch. So the two commonest
# closes there are - a document with no unsaved changes, and a Don't Save -
# return without releasing anything.
#
# What leaks, per closed window: the working copy directory under $TMPDIR (a
# full recursive copy of the .icon bundle, and for an icon with image layers
# that is megabytes), both preview PNGs, and all seven pasteboard keys. None of
# it is reclaimed until logout.
#
# The checks below assert the leak as it stands TODAY. They are deliberately
# written so that fixing it turns this section red and names itself, rather than
# leaving a fix silently uncovered. The fix is to lift cleanup_state() out to
# the end of the handler so it runs on every path except the chain-to-Save-As
# one, which hands the responsibility to save.as. When that lands, replace this
# section with the check_absent form used in sections 1 to 3.
section "4a. closing a clean document leaks it"
sample="$(open_sample)"
work_copy="$(work_icon)"
omc_run ICEdit.window.close
check_status "the handler succeeded"          0
check "nothing was asked, correctly"          "0"           "$(alerts_count)"
# Named one artifact at a time rather than as a single "did it clean up": a
# partial fix that removes the directory and forgets the pasteboard, or the
# other way round, has to be distinguishable from no fix at all.
check "DEFECT: the working copy survives"     "yes"         "$([ -d "$work_copy" ] && echo yes || echo no)"
check "DEFECT: and its whole directory"       "yes"         "$([ -d "$(work_dir)" ] && echo yes || echo no)"
check "DEFECT: so does the rendered preview"  "yes"         "$([ -f "$(ui_value $ID_PREVIEW)" ] && echo yes || echo no)"
check "DEFECT: the state is still set"        "$work_copy"  "$(work_icon)"
check "DEFECT: so is the original"            "$sample"     "$(original)"
check "DEFECT: and so is the fingerprint"     "yes"         "$([ -n "$(original_hash)" ] && echo yes || echo no)"

section "4b. Don't Save discards the edit but leaks it too"
sample="$(open_sample)"
dirty_the_document
work_copy="$(work_icon)"
# This applet wires the alert's Cancel slot to "Don't Save", so 1 discards.
alert_answer 1
omc_run ICEdit.window.close
check "the user was asked"                    "1"           "$(alerts_count)"
# The one thing this path gets right, and the important one: a discarded edit
# must not reach the disk. Two layers is the fixture's own shape.
check "the edit did not reach the disk"       "2"           "$(icon_layer_count "$sample")"
check "DEFECT: the working copy survives"     "yes"         "$([ -d "$work_copy" ] && echo yes || echo no)"
check "DEFECT: with the discarded edit in it" "3"           "$(icon_layer_count "$work_copy")"
check "DEFECT: still flagged dirty"           "1"           "$(dirty)"

section "4c. an alert that never reached the user is read as Don't Save"
# ICEdit.window.close.py tests "if r.returncode == 0" and treats everything else
# as Don't Save, so 2 (Other), 3 (timed out) and 255 (failed to display) all
# discard. Today that is harmless by accident - nothing is discarded because
# nothing is cleaned up - but the moment section 4's leak is fixed the obvious
# way, a close whose alert timed out silently throws the user's edit away with
# no window ever having appeared. Pinned now, while the fix is still ahead.
open_sample > /dev/null
dirty_the_document
work_copy="$(work_icon)"
alerts_reset
alert_answers_reset
alert_answer 3
omc_run ICEdit.window.close
check_status "the handler succeeded"          0
check "the alert was raised"                  "1"           "$(alerts_count)"
check "nothing was saved"                     "1"           "$(dirty)"
# The same three artifacts as 4a and 4b: this path is Don't Save by another
# name, and it leaks exactly as Don't Save does.
check "DEFECT: the working copy survives"     "yes"         "$([ -d "$work_copy" ] && echo yes || echo no)"
check "DEFECT: with the edit still in it"     "3"           "$(icon_layer_count "$work_copy")"

section "5. activating a window whose file has not changed does nothing"
open_sample > /dev/null
ui_reset
omc_run ICEdit.window.activated
check_status "the handler succeeded"          0
check "no alert"                              "0"           "$(alerts_count)"
# Nothing was pushed toward the window at all - the positive control is section
# 6, where the same assertion counts a full refresh.
check "and no window traffic"                 "0"           "$(ui_calls '.')"
check "the document stays clean"              ""            "$(dirty)"

section "6. an externally changed file is reloaded silently when clean"
open_sample > /dev/null
# Something has to BE selected for "the selection was dropped" to mean anything.
# reset_document leaves the key empty and ICEdit.main never selects, so without
# this the check asserts the starting state and passes on a reload that keeps
# the selection pointing at a layer the new document may not have.
select_layer Circle
check "a layer is selected to begin with"   "Circle"      "$(selected_layer)"
edit_original_behind_the_app Intruder
ui_reset
omc_run ICEdit.window.activated
check_status "the handler succeeded"          0
# No alert: there is nothing to lose, so asking would be noise.
check "the user was not interrupted"          "0"           "$(alerts_count)"
check "the external layer is in the working copy" "3"       "$(icon_layer_count "$(work_icon)")"
check "and it is the one that was added"      "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Intruder$')"
check "the table was rebuilt"                 "5"           "$(ui_row_count $ID_LAYER_LIST)"
check "the document is clean"                 ""            "$(dirty)"
check "the selection was dropped"             ""            "$(selected_layer)"
check "the background pane came forward"      "1"           "$(ui_visible $ID_BG_PANE)"
check "and the layer pane went away"          "0"           "$(ui_visible $ID_LAYER_PANE)"
check "the status line explains itself"       "Reloaded (changed externally)" "$(ui_value $ID_STATUS)"
# Re-fingerprinted, or every later activation would reload the same change over
# and over. Asserted as window traffic rather than as an alert count: this
# branch never alerts at all, so "no alert" is true whether the fingerprint was
# refreshed or not, and the check could not fail. Section 5 is the positive
# control for a silent activation, and the rebuild above for a noisy one.
ui_reset
omc_run ICEdit.window.activated
check "and it does not reload twice"          "0"           "$(ui_calls '.')"

section "7. an external change over unsaved edits asks what to keep"
open_sample > /dev/null
dirty_the_document
edit_original_behind_the_app Intruder
alert_answer 2
ui_reset
omc_run ICEdit.window.activated
check "the user was asked"                    "1"           "$(alerts_count)"
check "about the conflict"                    "1"           "$(alerts_mention 'Document Changed Externally')"
# Cancel means CANCEL: not one thing was pushed toward the window. Section 6 is
# the positive control, where the same counter reads a full refresh.
check "and the window was left alone"         "0"           "$(ui_calls '.')"
# Cancel is the --other slot: leave everything exactly as it was.
check "Cancel kept the local edit"            "3"           "$(icon_layer_count "$(work_icon)")"
check "and left the intruder out of it"       "0"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Intruder$')"
check "and the document is still dirty"       "1"           "$(dirty)"
check "with no status message"                ""            "$(ui_value $ID_STATUS)"

section "8. Keep My Changes stops the applet asking again"
alerts_reset
alert_answers_reset
alert_answer 0
omc_run ICEdit.window.activated
check "the user was asked once more"          "1"           "$(alerts_count)"
check "the local edit was kept"               "3"           "$(icon_layer_count "$(work_icon)")"
check "the document is still dirty"           "1"           "$(dirty)"
check "and the warning is explicit"  "Keeping local changes (external changes will be overwritten on save)" \
                                                            "$(ui_value $ID_STATUS)"
alerts_reset
omc_run ICEdit.window.activated
check "the same change is not raised twice"   "0"           "$(alerts_count)"

section "9. Reload from Disk discards the local edit"
open_sample > /dev/null
dirty_the_document
edit_original_behind_the_app Intruder
# Reload is wired to the alert's --cancel slot in this handler.
alert_answer 1
omc_run ICEdit.window.activated
check "the user was asked"                    "1"           "$(alerts_count)"
# The layer COUNT is deliberately not asserted here: the local working copy also
# holds three at this point (two from the fixture plus Local), so the number a
# reload produces is the number doing nothing produces. The two names below are
# what actually separate the two outcomes.
check "the external layer is present"         "1"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Intruder$')"
check "the local layer is gone"               "0"           "$(icon_layers "$(work_icon)" | /usr/bin/grep -c '^Local$')"
check "and the document is clean"             ""            "$(dirty)"
check "the status line explains itself"       "Reloaded (changed externally)" "$(ui_value $ID_STATUS)"

section "10. a never-saved document has nothing to compare against"
reset_document
omc_object ""
omc_run ICEdit.main
omc_run ICEdit.window.activated
check_status "the handler succeeded"          0
check "no alert"                              "0"           "$(alerts_count)"
check "and it stays untitled"                 ""            "$(original)"

section "cumulative: the window never wrote to a view id it does not declare"
# unknown_ids.log accumulates across the whole file, so this one assertion covers
# every section above it - including the ui_reset calls, which since API 4 no
# longer drop the diagnostic logs. The line before it is its positive control.
check "the id set was extracted"              "yes"         "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"
check "no undeclared ids"                     ""            "$(ui_unknown_writes)"
check "no bare value clobbered a table"       ""            "$(ui_suspect_writes)"
check "no malformed omc_dialog_control calls" ""            "$(ui_errors)"

omctest_end
