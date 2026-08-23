#!/bin/bash
# thin_icedit.sh - thin ICEdit.app's embedded Python down to the modules it actually uses.
#
# This is a thin front end over the shared OMC applet thinner, which does the real work:
#
#   OMC/Distribution/Scripts/thin_applet_python.py   (applet layout, cloning, sandbox)
#   Python-Embedding/analyze_python_deps.py          (the closure analysis)
#   Python-Embedding/thin_with_plan.sh               (removal + verification)
#
# Two phases, with a reviewable JSON plan in between:
#
#   ./thin_icedit.sh plan     -> writes ICEdit.thinning-plan.json (commit it)
#   ./thin_icedit.sh apply    -> performs the plan's removal, then verifies
#
# `plan` never touches the real bundle: it clones it, and runs every traced subprocess
# under sandbox-exec with no network and no writes outside the clone. `apply` backs the
# distribution up to Python.thinbak first and restores it if verification fails.
#
# Run `apply` AFTER `appletbuilder build ICEdit.app --update-python`, which replaces the
# embedded runtime wholesale and so restores the full, unthinned distribution. Re-run
# `plan` only when ICEdit's own Python changes, or when the interpreter is upgraded to a
# new Python version.
#
# ICEdit needs no per-app configuration. Contents/Helpers/icedit/icedit is a shebang
# script that lib_icedit.run_icedit() launches by path, which no import statement names;
# the analyzer discovers it as an entry point on its own and reads the icon_editor
# package beside it, so xml.etree.ElementTree and its _elementtree accelerator stay.
#
# Usage:
#   ./thin_icedit.sh plan  [/path/to/ICEdit.app] [extra thin_applet_python.py args]
#   ./thin_icedit.sh apply [/path/to/ICEdit.app] [--dry-run|--skip-verify]
#
# The bundle path, when given, must come FIRST, before any flag. It defaults to the
# ICEdit.app beside this script. A copy elsewhere is fine as long as it is still named
# ICEdit.app - that is how you test an apply on a throwaway - but any other bundle is
# refused: this script names ICEdit's committed plan, so another app would either be
# thinned by the wrong plan or overwrite it with its own.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THINNER="$SCRIPT_DIR/../OMC/Distribution/Scripts/thin_applet_python.py"
PLAN_FILE="$SCRIPT_DIR/ICEdit.thinning-plan.json"

usage() {
    # Non-zero means this is a diagnostic, so it belongs on stderr beside the error that
    # prompted it; only an explicit --help writes to stdout.
    if [ "${1:-1}" = "0" ]; then
        sed -n '/^# thin_icedit.sh -/,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'
    else
        sed -n '/^# thin_icedit.sh -/,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//' >&2
    fi
    exit "${1:-1}"
}

[ $# -ge 1 ] || usage 1
VERB="$1"; shift
case "$VERB" in
    plan|apply) ;;
    -h|--help|help) usage 0 ;;
    *) echo "Error: unknown verb '$VERB' (expected 'plan' or 'apply')" >&2; usage 1 ;;
esac

if [ ! -f "$THINNER" ]; then
    echo "Error: thin_applet_python.py not found at: $THINNER" >&2
    echo "Fetch OMC as a sibling checkout: https://github.com/abra-code/OMC" >&2
    exit 1
fi
if [ ! -x "$THINNER" ]; then
    echo "Error: not executable: $THINNER" >&2
    echo "Fix with: chmod +x \"$THINNER\"" >&2
    exit 1
fi

# An optional first positional argument overrides the bundle; everything after it is
# passed through to thin_applet_python.py untouched. The path has to come first, or the
# checks below would validate the default bundle while the thinner acted on another one.
APP="$SCRIPT_DIR/ICEdit.app"
if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then
    APP="$1"; shift
fi
# A bundle named after a flag would leave the checks below validating the DEFAULT app
# while the thinner acted on that one. Only existing *.app directories are rejected, so
# a flag value that is an ordinary path (--plan foo.json, --keep-file names.txt) passes
# through - though a flag value that IS an app bundle would be refused too, which no
# flag of the shared thinner takes.
for arg in ${@+"$@"}; do
    case "$arg" in
        *.app|*.app/) if [ -d "$arg" ]; then
               echo "Error: the bundle path must come first:" >&2
               echo "  \"$0\" $VERB \"${arg%/}\" [flags...]" >&2
               exit 1
           fi ;;
    esac
done

# Refuse a bundle that is not ICEdit: --plan below names ICEdit's committed plan, so
# another app would either be thinned by the wrong plan or overwrite it with its own.
if [ "$(basename "$APP")" != "ICEdit.app" ]; then
    echo "Error: not an ICEdit.app bundle: $APP" >&2
    echo "This script drives ICEdit's plan ($PLAN_FILE) and nothing else." >&2
    echo "To try an apply on a throwaway copy, keep the bundle name:" >&2
    echo "  mkdir -p /tmp/t && cp -Rc \"$SCRIPT_DIR/ICEdit.app\" /tmp/t/ && \"$0\" $VERB /tmp/t/ICEdit.app" >&2
    exit 1
fi

if [ ! -d "$APP/Contents/Library/Python" ]; then
    echo "Error: no embedded Python in $APP" >&2
    echo "Build the applet first: appletbuilder build \"$APP\"" >&2
    exit 1
fi

# --plan comes before the pass-through args on purpose: a --plan of the caller's own
# then wins, which is how you write a throwaway plan without touching the committed one.
exec "$THINNER" "$VERB" "$APP" --plan "$PLAN_FILE" ${@+"$@"}
