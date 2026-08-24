#!/bin/bash
# update_icedit.sh
# Build and assemble the app-specific helper payload inside ICEdit.app - everything under
# Contents/Helpers, plus the Material Symbols resources that are too large to commit.
# AppletBuilder supplies the OMC engine side (Contents/MacOS, Contents/Frameworks/Abracode.framework,
# Contents/Library/Python); this script owns everything beyond it.
#
# Steps: (1) deploy the icedit CLI plus its icon_editor package to Contents/Helpers/icedit/,
# (2) build glyphsvg with its own build.sh and deploy glyphsvg + sfmap.plist + names.txt to
# Contents/Helpers/glyphsvg/, (3) provision the Google Material Symbols font/codepoints/metadata
# into Contents/Helpers/glyphsvg/material/, (4) verify the whole payload BEFORE it is sealed,
# (5) deep-sign the bundle via codesign_applet.sh, (6) re-check the signature and that the signed
# helpers still launch. The icedit and glyphsvg sources come from sibling checkouts, and the
# script offers to clone them when they are missing.
#
# Step 3 folds in the old standalone download_material_symbols.sh, which this script replaces.
# It differs from that script in three ways that matter: the download is staged in a temp dir and
# validated before anything is moved into the bundle (curl -o straight into Contents/ truncated
# the existing font first, so a dropped connection left a 0-byte .ttf in a bundle we then signed),
# the resources are fetched only when absent since they are ~22 MB, and an already-downloaded copy
# in the glyphsvg repo is preferred over re-fetching.
#
# Verification runs BEFORE signing, not after: a bundle that gets sealed and only then found to be
# broken is worse than one that never got sealed. Only the signature check and a re-launch of the
# signed binaries happen afterwards.
#
# What is NOT here: thin_icedit.sh, which thins the embedded Python distribution. It acts on the
# AppletBuilder-provided runtime rather than on this script's payload, and it has its own two-phase
# plan/apply protocol with a committed plan file - not something to fold into a refresh. It does
# have one dependency on this script, though: the plan is derived from ICEdit's own imports, and
# the analyzer discovers Contents/Helpers/icedit/icedit as an entry point and reads the icon_editor
# package beside it. An icedit update that pulls in a module the old package did not use means
# re-running `./thin_icedit.sh plan` before the next apply.
#
# The .app bundle is auto-detected from this script's directory, or named with --app=PATH.

set -uo pipefail

GREEN=$(printf '\033[92m'); RED=$(printf '\033[91m'); YELLOW=$(printf '\033[93m'); RESET=$(printf '\033[0m')

CONFIG="release"
SIGNING_IDENTITY="-"
DO_BUILD="yes"
DO_CODESIGN="yes"
DO_ICEDIT="yes"
DO_GLYPHSVG="yes"
DO_MATERIAL="yes"
FORCE_ICEDIT="no"
REFRESH_MATERIAL="no"
APP_OVERRIDE=""

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"
ICEDIT_REPO="${ICEDIT_REPO:-}"
GLYPHSVG_REPO="${GLYPHSVG_REPO:-}"

# Per-component rollup, printed at the end. Anything a run does not touch stays "skipped".
ICEDIT_STATUS="skipped"
GLYPHSVG_STATUS="skipped"
SFSYMBOLS_STATUS="skipped"
MATERIAL_STATUS="skipped"
CODESIGN_STATUS="skipped"

WORK_DIR=""
cleanup() { [ -n "$WORK_DIR" ] && /bin/rm -rf "$WORK_DIR"; return 0; }
fail() { echo "${RED}$*${RESET}" >&2; exit 1; }

# Every fail() past the material download would otherwise exit with a ~22 MB temp tree behind it,
# so hang the cleanup off EXIT rather than repeating it at each site. The signal traps must exit:
# a handler that cleans up and returns resumes the script where it was interrupted, so Ctrl-C
# during the download would carry on into signing and print "Done." Exiting re-fires EXIT, so the
# temp tree is reclaimed on every path.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT
# PIPE too: bash's default SIGPIPE disposition kills the process outright, skipping the EXIT trap,
# so anything as ordinary as `./update_icedit.sh | head -5` leaked the temp tree.
trap 'exit 141' PIPE

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Assembles the app-specific helper payload in the .app bundle beside this script:
  icedit            -> Contents/Helpers/icedit/             (copied from the icedit repo)
  glyphsvg          -> Contents/Helpers/glyphsvg/           (built from the glyphsvg repo)
  SF Symbols map    -> Contents/Helpers/glyphsvg/           (sfmap.plist + names.txt)
  Material Symbols  -> Contents/Helpers/glyphsvg/material/  (downloaded, ~22 MB)

Both source repos are expected as siblings of this one (../icedit, ../glyphsvg); if one is
missing you are offered a git clone into that location (interactive runs only).

Options:
  --app=PATH              the .app bundle to update (default: the single one beside this script)
  --config=debug|release  glyphsvg build mode (default: release)
  --debug                 same as --config=debug
  --icedit-repo=PATH      path to the icedit checkout (env: ICEDIT_REPO)
  --glyphsvg-repo=PATH    path to the glyphsvg checkout (env: GLYPHSVG_REPO)
  --skip-build            do not run glyphsvg's build.sh; deploy its existing build products
  --skip-icedit           leave Contents/Helpers/icedit alone
  --skip-glyphsvg         leave Contents/Helpers/glyphsvg alone (binary, sfmap, names)
  --skip-material         leave Contents/Helpers/glyphsvg/material alone (no network access)
  --force-icedit          overwrite deployed icedit files that differ from the repo
  --refresh-material      re-fetch the Material Symbols resources even if already present
  --identity=CERT         signing identity ('-' for ad-hoc, the default)
  --no-codesign           skip the codesign_applet.sh step
  --help                  show this message

Note that a normal run rewrites git-tracked files: Contents/Helpers/glyphsvg/names.txt and
sfmap.plist always, and Contents/Helpers/icedit/* under --force-icedit.

Examples:
  ./$(/usr/bin/basename "$0")
  ./$(/usr/bin/basename "$0") --refresh-material
  ./$(/usr/bin/basename "$0") --app=/Applications/ICEdit.app --skip-build
  ./$(/usr/bin/basename "$0") --identity='Developer ID Application: ...'
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app=*) APP_OVERRIDE="${1#*=}" ;;
        --config=*) CONFIG="${1#*=}" ;;
        --debug) CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        --icedit-repo=*) ICEDIT_REPO="${1#*=}" ;;
        --glyphsvg-repo=*) GLYPHSVG_REPO="${1#*=}" ;;
        --skip-build) DO_BUILD="no" ;;
        --skip-icedit) DO_ICEDIT="no" ;;
        --skip-glyphsvg) DO_GLYPHSVG="no" ;;
        --skip-material) DO_MATERIAL="no" ;;
        --force-icedit) FORCE_ICEDIT="yes" ;;
        --refresh-material) REFRESH_MATERIAL="yes" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}" ;;
        --no-codesign) DO_CODESIGN="no" ;;
        --help) show_help ;;
        # Exit nonzero rather than falling into show_help: a typo'd flag that returns 0 having
        # done nothing reads as success to any Makefile or CI step that calls this.
        *) echo "${RED}Unknown option: $1${RESET}" >&2; echo "Try: $0 --help" >&2; exit 1 ;;
    esac
    shift
done

case "$CONFIG" in debug|release) ;; *) fail "Invalid --config: $CONFIG (expected debug or release)" ;; esac

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/update_icedit.XXXXXX")" || fail "mktemp failed"

# Resolve the target bundle. Auto-detection insists on exactly one candidate: this directory grows
# an export or backup copy from time to time, and silently picking whichever sorts first would
# rm -rf inside, deploy into, and sign the wrong bundle with only its basename shown.
if [ -n "$APP_OVERRIDE" ]; then
    [ -d "$APP_OVERRIDE" ] || fail "No .app bundle at $APP_OVERRIDE"
    [ -f "$APP_OVERRIDE/Contents/Info.plist" ] || fail "$APP_OVERRIDE is not an app bundle (no Contents/Info.plist)"
    APP_BUNDLE="$(cd "$APP_OVERRIDE" && pwd)"
else
    APP_BUNDLE=""
    _napps=0
    for _c in "$SCRIPT_DIR"/*.app; do
        [ -d "$_c" ] || continue
        _napps=$((_napps + 1))
        APP_BUNDLE="$_c"
    done
    [ "$_napps" -gt 0 ] || fail "No .app bundle found in $SCRIPT_DIR"
    [ "$_napps" -eq 1 ] || fail "$_napps .app bundles in $SCRIPT_DIR - name the one to update with --app=PATH"
fi

HELPERS_DIR="$APP_BUNDLE/Contents/Helpers"
ICEDIT_DEST="$HELPERS_DIR/icedit"
GLYPHSVG_DEST="$HELPERS_DIR/glyphsvg"
MATERIAL_DEST="$GLYPHSVG_DEST/material"
APP_SCRIPTS_DIR="$APP_BUNDLE/Contents/Resources/Scripts"

# A dependency repo is missing: offer to git-clone it into the sibling location and continue.
# Interactive runs only - without a TTY (CI, piped stdin) this declines silently and the caller's
# fail() fires with the manual instructions. $1 = repo URL, $2 = destination dir.
offer_clone() {
    [ -t 0 ] || return 1
    printf "%s  %s not found. Clone %s\n  into %s now? [y/N] %s" \
        "$YELLOW" "$(/usr/bin/basename "$2")" "$1" "$2" "$RESET"
    local _ans
    IFS= read -r _ans
    case "$_ans" in [yY]|[yY][eE][sS]) ;; *) return 1 ;; esac
    /usr/bin/git clone "$1" "$2"
}

# Locate the icedit repo (github.com/abra-code/icedit): env override, then the sibling dir,
# offering to clone it there when missing. Identified by the CLI plus its package, so a
# half-checked-out or unrelated directory named "icedit" does not satisfy the probe.
if [ "$DO_ICEDIT" = "yes" ]; then
    if [ -z "$ICEDIT_REPO" ] && [ -f "$SCRIPT_DIR/../icedit/icedit" ] && [ -f "$SCRIPT_DIR/../icedit/icon_editor/core.py" ]; then
        ICEDIT_REPO="$(cd "$SCRIPT_DIR/../icedit" && pwd)"
    fi
    if [ -z "$ICEDIT_REPO" ]; then
        offer_clone "https://github.com/abra-code/icedit" "$(cd "$SCRIPT_DIR/.." && pwd)/icedit" \
            && [ -f "$SCRIPT_DIR/../icedit/icedit" ] \
            && ICEDIT_REPO="$(cd "$SCRIPT_DIR/../icedit" && pwd)"
    fi
    [ -n "$ICEDIT_REPO" ] && [ -f "$ICEDIT_REPO/icedit" ] && [ -f "$ICEDIT_REPO/icon_editor/core.py" ] \
        || fail "icedit repo not found (looked for icedit + icon_editor/core.py); clone github.com/abra-code/icedit beside this repo, pass --icedit-repo=PATH, or use --skip-icedit"
fi

# Locate the glyphsvg repo (github.com/abra-code/glyphsvg): same pattern. Identified by build.sh
# plus the SF Symbols name/symbol lists, since both the binary and the sfmap come from here.
if [ "$DO_GLYPHSVG" = "yes" ]; then
    if [ -z "$GLYPHSVG_REPO" ] && [ -f "$SCRIPT_DIR/../glyphsvg/build.sh" ] && [ -d "$SCRIPT_DIR/../glyphsvg/sfmap" ]; then
        GLYPHSVG_REPO="$(cd "$SCRIPT_DIR/../glyphsvg" && pwd)"
    fi
    if [ -z "$GLYPHSVG_REPO" ]; then
        offer_clone "https://github.com/abra-code/glyphsvg" "$(cd "$SCRIPT_DIR/.." && pwd)/glyphsvg" \
            && [ -f "$SCRIPT_DIR/../glyphsvg/build.sh" ] \
            && GLYPHSVG_REPO="$(cd "$SCRIPT_DIR/../glyphsvg" && pwd)"
    fi
    [ -n "$GLYPHSVG_REPO" ] && [ -f "$GLYPHSVG_REPO/build.sh" ] && [ -d "$GLYPHSVG_REPO/sfmap" ] \
        || fail "glyphsvg repo not found (looked for build.sh + sfmap/); clone github.com/abra-code/glyphsvg beside this repo, pass --glyphsvg-repo=PATH, or use --skip-glyphsvg"
fi

# Which Material Symbols variant the app expects. Read from lib_material.py rather than hardcoded
# here: only one style is embedded, and the picker resolves its font and codepoints file by that
# name - a script that provisioned a different style would leave the picker with an empty list.
#
# BOTH constants are read, because they are used for different things and can disagree. STYLE
# names the files ("Rounded"); MATERIAL_STYLE_ARG is what the picker passes to glyphsvg as
# --material=<style> ("rounded"), and glyphsvg turns THAT back into a filename. Changing one
# without the other downloads a font nothing will ever ask for and deletes the one in use.
MATERIAL_STYLE="$(/usr/bin/sed -n 's/^STYLE = "\([A-Za-z]*\)".*/\1/p' "$APP_SCRIPTS_DIR/lib_material.py" 2>/dev/null | /usr/bin/head -1)"
MATERIAL_STYLE_ARG="$(/usr/bin/sed -n 's/^MATERIAL_STYLE_ARG = "\([A-Za-z]*\)".*/\1/p' "$APP_SCRIPTS_DIR/lib_material.py" 2>/dev/null | /usr/bin/head -1)"
[ -n "$MATERIAL_STYLE" ] && [ -n "$MATERIAL_STYLE_ARG" ] \
    || fail "Could not read STYLE and MATERIAL_STYLE_ARG from $APP_SCRIPTS_DIR/lib_material.py - the Material Symbols variant the app expects is unknown"
[ "$(echo "$MATERIAL_STYLE" | /usr/bin/tr '[:upper:]' '[:lower:]')" = "$MATERIAL_STYLE_ARG" ] \
    || fail "lib_material.py disagrees with itself: STYLE=\"$MATERIAL_STYLE\" but MATERIAL_STYLE_ARG=\"$MATERIAL_STYLE_ARG\". The picker would render one style and look names up in the other. Fix both before running this."

MATERIAL_TTF="MaterialSymbols${MATERIAL_STYLE}.ttf"
MATERIAL_CODEPOINTS="MaterialSymbols${MATERIAL_STYLE}.codepoints"
MATERIAL_METADATA="material_symbols_metadata.json"

echo
echo "==== Updating $(/usr/bin/basename "$APP_BUNDLE") (glyphsvg: $CONFIG) ===="
[ "$DO_ICEDIT"   = "yes" ] && echo "  icedit    : $ICEDIT_REPO"
[ "$DO_GLYPHSVG" = "yes" ] && echo "  glyphsvg  : $GLYPHSVG_REPO"
[ "$DO_MATERIAL" = "yes" ] && echo "  material  : Material Symbols $MATERIAL_STYLE"
echo "  deploy to : $APP_BUNDLE"
echo

# Leftovers from a run that was interrupted mid-swap. Each stage below stages into a dot-prefixed
# sibling of its target so a failure never leaves a half-written file under its real name; clear
# any such remains up front so they cannot be picked up or sealed into the signature.
/bin/rm -rf "$ICEDIT_DEST/.stage"
[ -d "$HELPERS_DIR" ] && /usr/bin/find "$HELPERS_DIR" -name ".*.new" -type f -delete

# ── 1. icedit CLI + icon_editor package ───────────────────────────────────
# Pure-stdlib Python, so there is nothing to build: the repo is copied verbatim. Only the tracked
# sources travel - __pycache__ and .DS_Store would otherwise be sealed into the signature.
if [ "$DO_ICEDIT" = "yes" ]; then
    echo "── 1. icedit ──"
    _icedit_files="$WORK_DIR/icedit.files"
    ( cd "$ICEDIT_REPO" && /usr/bin/find icedit icon_editor -type f \
        ! -name "*.pyc" ! -name ".DS_Store" ! -path "*/__pycache__/*" -print ) > "$_icedit_files" \
        || fail "Could not list the icedit sources in $ICEDIT_REPO"
    # find exits 0 when nothing matched, so count rather than trusting the status: an empty list
    # would replace icon_editor with nothing and call it a success.
    _n=$(/usr/bin/wc -l < "$_icedit_files" | /usr/bin/tr -d " ")
    [ "${_n:-0}" -gt 1 ] || fail "Only ${_n:-0} source file(s) found in $ICEDIT_REPO - that is not an icedit checkout"
    # Checked up front so an unreadable source is reported as such: cmp exits 2 for "could not
    # open", which the drift loop below would otherwise report as "the bundle copy has diverged".
    while IFS= read -r _rel; do
        [ -r "$ICEDIT_REPO/$_rel" ] || fail "Cannot read $ICEDIT_REPO/$_rel - check permissions."
    done < "$_icedit_files"

    # The bundle copy has been an EDIT target, not only a deployment target: commit 8de1dbf moved
    # icon_validator.py's scratch dir from /tmp to $TMPDIR in the bundle without upstreaming it,
    # so a blind copy would silently revert a shipped fix. Diff first and stop on any difference -
    # the fix belongs in the icedit repo, and --force-icedit is the escape hatch once it has been
    # either upstreamed or knowingly discarded.
    _drift=""
    while IFS= read -r _rel; do
        [ -f "$ICEDIT_DEST/$_rel" ] || continue
        /usr/bin/cmp -s "$ICEDIT_REPO/$_rel" "$ICEDIT_DEST/$_rel" || _drift="$_drift
    $_rel"
    done < "$_icedit_files"
    if [ -n "$_drift" ] && [ "$FORCE_ICEDIT" = "no" ]; then
        fail "Deployed icedit files differ from $ICEDIT_REPO:$_drift

  The bundle copy is ahead of (or has diverged from) the repo. Upstream the change to the icedit
  repo first, or re-run with --force-icedit to overwrite it, or --skip-icedit to leave it be."
    fi
    [ -n "$_drift" ] && echo "${YELLOW}  overwriting locally-modified files (--force-icedit):$_drift${RESET}"

    # Build the new tree beside the old one and swap it in, rather than deleting first and copying
    # into the hole: a copy that dies partway (ENOSPC, Ctrl-C) would otherwise leave the bundle
    # holding a partial icon_editor package, which a later --skip-icedit run would happily sign.
    # The staging dir sits inside the bundle, so the swap is a same-filesystem rename.
    _stage="$ICEDIT_DEST/.stage"
    /bin/mkdir -p "$_stage" || fail "Could not create $_stage"
    while IFS= read -r _rel; do
        /bin/mkdir -p "$_stage/$(/usr/bin/dirname "$_rel")" \
            && /bin/cp -f "$ICEDIT_REPO/$_rel" "$_stage/$_rel" \
            || fail "Could not stage $_rel"
    done < "$_icedit_files"
    # Prove every byte landed before anything in the live tree is touched. cp can report success
    # on a short write, and this runs before signing, so the comparison is against raw bytes.
    while IFS= read -r _rel; do
        /usr/bin/cmp -s "$ICEDIT_REPO/$_rel" "$_stage/$_rel" \
            || fail "Staged $_rel differs from the repo - copy did not take."
    done < "$_icedit_files"
    /bin/chmod +x "$_stage/icedit" || fail "Could not make icedit executable"

    /bin/rm -rf "$ICEDIT_DEST/icon_editor" || fail "Could not clear $ICEDIT_DEST/icon_editor"
    /bin/mv -f "$_stage/icon_editor" "$ICEDIT_DEST/icon_editor" || fail "Could not install icon_editor"
    /bin/mv -f "$_stage/icedit" "$ICEDIT_DEST/icedit" || fail "Could not install the icedit CLI"
    /bin/rm -rf "$_stage"
    ICEDIT_STATUS="$_n file(s) from $(/usr/bin/basename "$ICEDIT_REPO")"
    echo "  ${GREEN}Deployed${RESET} icedit ($_n files)"
    echo
fi

# ── 2. glyphsvg: build, then deploy the binary and the SF Symbols map ─────
# The repo's own build.sh drives clang directly (CoreText/CoreGraphics only, no package manager)
# and produces universal arm64 + x86_64 binaries with a macOS 11.0 floor. ICEdit itself needs
# 14.6, so the lower floor costs nothing; override with MIN_MACOS=... in the environment, which
# build.sh reads. It also generates sfmap.plist from the SF Symbols name/symbol lists as part of
# the same run, which is why the plist is taken from the build output and not from the repo.
GLYPHSVG_BUILD_DIR="${GLYPHSVG_REPO:-}/build/bin"
if [ "$DO_GLYPHSVG" = "yes" ]; then
    echo "── 2. glyphsvg ──"
    if [ "$DO_BUILD" = "yes" ]; then
        /usr/bin/xcrun --find clang >/dev/null 2>&1 || fail "clang not found. Install the Xcode command line tools: xcode-select --install"
        echo "  Building glyphsvg ($CONFIG, universal)..."
        ( cd "$GLYPHSVG_REPO" && ./build.sh "$CONFIG" ) || fail "glyphsvg build.sh failed"
    fi
    [ -x "$GLYPHSVG_BUILD_DIR/glyphsvg" ] || fail "No built glyphsvg at $GLYPHSVG_BUILD_DIR (build first, or drop --skip-build)."
    [ -s "$GLYPHSVG_BUILD_DIR/sfmap.plist" ] || fail "No sfmap.plist at $GLYPHSVG_BUILD_DIR (build first, or drop --skip-build)."

    /bin/mkdir -p "$GLYPHSVG_DEST" || fail "Could not create $GLYPHSVG_DEST"
    /bin/cp -f "$GLYPHSVG_BUILD_DIR/glyphsvg" "$GLYPHSVG_DEST/glyphsvg" || fail "Could not deploy glyphsvg"
    /bin/chmod +x "$GLYPHSVG_DEST/glyphsvg" || fail "Could not make glyphsvg executable"
    /usr/bin/cmp -s "$GLYPHSVG_BUILD_DIR/glyphsvg" "$GLYPHSVG_DEST/glyphsvg" \
        || fail "Deployed glyphsvg differs from the build product - copy did not take."
    /bin/cp -f "$GLYPHSVG_BUILD_DIR/sfmap.plist" "$GLYPHSVG_DEST/sfmap.plist" || fail "Could not deploy sfmap.plist"
    /usr/bin/cmp -s "$GLYPHSVG_BUILD_DIR/sfmap.plist" "$GLYPHSVG_DEST/sfmap.plist" \
        || fail "Deployed sfmap.plist differs from the build product - copy did not take."
    _archs="$(/usr/bin/lipo -archs "$GLYPHSVG_DEST/glyphsvg" 2>/dev/null)"
    GLYPHSVG_STATUS="$CONFIG build (${_archs:-unknown})"
    echo "  ${GREEN}Deployed${RESET} glyphsvg (${_archs:-unknown}) + sfmap.plist"

    # names.txt is the picker's symbol list. It is sfmap's names file SORTED: the filter script
    # ranks matches and relies on a stable sort to preserve alphabetical order within a rank, so
    # the raw file (which is in SF Symbols app browsing order) would come out shuffled in the UI.
    # LC_ALL=C to match the byte ordering the list was built with - a locale-aware sort collates
    # the dots in names like "square.and.arrow.up" differently.
    # The version comes from build.sh rather than a glob, so names.txt can only ever be the list
    # that produced the sfmap.plist deployed just above.
    SF_VERSION="$(/usr/bin/sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$GLYPHSVG_REPO/build.sh" | /usr/bin/head -1)"
    [ -n "$SF_VERSION" ] || fail "Could not read VERSION from $GLYPHSVG_REPO/build.sh - the SF Symbols release to deploy is unknown"
    _names_src="$GLYPHSVG_REPO/sfmap/names_$SF_VERSION.txt"
    [ -s "$_names_src" ] || fail "No $_names_src - the glyphsvg checkout does not carry the SF Symbols $SF_VERSION name list"
    # Sort beside the target and rename: a sort that dies partway would otherwise leave a
    # truncated symbol list under the real name, in a bundle this script goes on to sign. The
    # dot-prefixed name is what the leftover sweep at the top of the run looks for.
    _names_tmp="$GLYPHSVG_DEST/.names.txt.new"
    LC_ALL=C /usr/bin/sort "$_names_src" > "$_names_tmp" \
        && /bin/mv -f "$_names_tmp" "$GLYPHSVG_DEST/names.txt" \
        || { /bin/rm -f "$_names_tmp"; fail "Could not build names.txt from $_names_src"; }
    _ncount=$(/usr/bin/wc -l < "$GLYPHSVG_DEST/names.txt" | /usr/bin/tr -d " ")
    SFSYMBOLS_STATUS="$SF_VERSION, $_ncount names"
    echo "  ${GREEN}Deployed${RESET} SF Symbols $SF_VERSION map ($_ncount names)"
    echo
fi

# ── 3. Material Symbols resources ─────────────────────────────────────────
# Google's variable font, its name->codepoint map, and the search metadata. ~22 MB, not committed
# (see .gitignore), so every fresh checkout needs this once. Sources, in order of preference:
# a copy already sitting in the glyphsvg repo (same files, no download), otherwise Google.

material_present() {
    [ -s "$1/$MATERIAL_TTF" ] && [ -s "$1/$MATERIAL_CODEPOINTS" ] && [ -s "$1/$MATERIAL_METADATA" ]
}

# Structural checks on a candidate set. Deliberately not size-based: a captive-portal or
# rate-limit response is a small HTML page that curl writes out with a zero exit, and a bundle
# holding an .html named .ttf renders an empty picker rather than failing.
material_validate() {
    material_present "$1" || return 1
    # Command substitution, not a pipe into grep -q: under pipefail, grep -q exiting on its first
    # match SIGPIPEs the producer, and that 141 becomes the status of the whole pipeline.
    case "$(/usr/bin/file -b "$1/$MATERIAL_TTF" 2>/dev/null)" in
        *[Ff]ont*) ;;
        *) return 1 ;;
    esac
    # The codepoints file is what the picker lists, and it has the same captive-portal exposure as
    # the font, so check its shape rather than merely that it has content: every line reads
    # "<name> <hex>", and a real map has thousands of them.
    local _cp_lines
    _cp_lines=$(LC_ALL=C /usr/bin/grep -cE '^[A-Za-z0-9_.]+ [0-9a-fA-F]{4,6}$' "$1/$MATERIAL_CODEPOINTS" 2>/dev/null)
    [ "${_cp_lines:-0}" -ge 100 ] || return 1
    # The app reads this with json.load, so validate with the same parser where it is available.
    # plutil is the fallback: it does parse JSON, but its plist object model has no null, so it
    # rejects a payload Python would accept - fine as a backstop, wrong as the only check.
    if [ -x /usr/bin/python3 ]; then
        /usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1/$MATERIAL_METADATA" >/dev/null 2>&1 || return 1
    else
        /usr/bin/plutil -convert xml1 -o /dev/null "$1/$MATERIAL_METADATA" >/dev/null 2>&1 || return 1
    fi
    return 0
}

# The check that actually matters: hand the font to the deployed glyphsvg and see whether a symbol
# renders. A truncated .ttf passes every header heuristic above - `file` reads the first bytes and
# reports "TrueType Font data" for a 200 KB fragment of a 15 MB font - but CoreText refuses to
# load it, so this catches exactly the corruption the cheap checks cannot. It also proves the
# style the app asks for resolves to the file that was deployed. Needs a deployed glyphsvg; when
# there is none (a --skip-glyphsvg run on a fresh checkout) it returns 2 and the caller falls back
# to the structural checks alone.
material_render_probe() {
    [ -x "$GLYPHSVG_DEST/glyphsvg" ] || return 2
    local _sym _out
    _sym="$(/usr/bin/head -1 "$1/$MATERIAL_CODEPOINTS" | /usr/bin/cut -d" " -f1)"
    [ -n "$_sym" ] || return 1
    _out="$WORK_DIR/probe.svg"
    /bin/rm -f "$_out"
    GLYPHSVG_MATERIAL_DIR="$1" "$GLYPHSVG_DEST/glyphsvg" --material="$MATERIAL_STYLE_ARG" \
        "$_sym" 64 --output="$_out" >/dev/null 2>&1 || return 1
    [ -s "$_out" ] || return 1
    return 0
}

# Both checks together: what the short-circuit below needs is "is the deployed set usable", and
# neither half answers that alone. A render probe with no glyphsvg to run (exit 2) is not a
# failure, just an unanswered question, so it counts as passing.
material_ok() {
    material_validate "$1" || return 1
    material_render_probe "$1"
    case "$?" in 0|2) return 0 ;; *) return 1 ;; esac
}

echo "── 3. Material Symbols ──"
if [ "$DO_MATERIAL" = "no" ]; then
    echo "  Skipped (--skip-material)"
    MATERIAL_STATUS="skipped (--skip-material)"
elif [ "$REFRESH_MATERIAL" = "no" ] && material_ok "$MATERIAL_DEST"; then
    _mcount=$(/usr/bin/wc -l < "$MATERIAL_DEST/$MATERIAL_CODEPOINTS" | /usr/bin/tr -d " ")
    MATERIAL_STATUS="$MATERIAL_STYLE, $_mcount symbols (already present)"
    echo "  Already present ($_mcount symbols) - re-run with --refresh-material to update"
else
    # Gating the short-circuit on usability rather than mere presence means a payload left
    # truncated by an earlier interrupted run repairs itself here, from the sibling repo when it
    # has a copy - rather than surviving every run until someone reads the failure at step 4 and
    # re-downloads 22 MB by hand.
    if [ "$REFRESH_MATERIAL" = "no" ] && material_present "$MATERIAL_DEST"; then
        echo "${YELLOW}  present but not usable (corrupt or truncated) - re-provisioning${RESET}"
    fi
    _staged="$WORK_DIR/material"
    /bin/mkdir -p "$_staged" || fail "Could not create $_staged"
    _source=""

    # The fast path needs the glyphsvg checkout, which --skip-glyphsvg leaves unlocated. Probe for
    # it here without the fail() the deploy stage applies: a missing repo just means the download
    # runs instead. Skipped entirely under --refresh-material, whose whole point is to go to the
    # upstream source rather than to a local copy of unknown age.
    _repo_material=""
    if [ -n "$GLYPHSVG_REPO" ]; then
        _repo_material="$GLYPHSVG_REPO/material"
    elif [ -d "$SCRIPT_DIR/../glyphsvg/material" ]; then
        _repo_material="$(cd "$SCRIPT_DIR/../glyphsvg" && pwd)/material"
    fi
    if [ -n "$_repo_material" ] && [ "$REFRESH_MATERIAL" = "no" ] && material_present "$_repo_material"; then
        echo "  Copying from $_repo_material ..."
        for _f in "$MATERIAL_TTF" "$MATERIAL_CODEPOINTS" "$MATERIAL_METADATA"; do
            /bin/cp -f "$_repo_material/$_f" "$_staged/$_f" || fail "Could not copy $_f from $_repo_material"
        done
        _source="glyphsvg repo"
    else
        # Google publishes the variable fonts with their variation axes in the filename; the
        # bracketed suffix has to be percent-encoded once for the raw.githubusercontent URL.
        # The timeouts are explicit: a black-holed connection would otherwise hang a signing
        # workflow indefinitely instead of failing.
        BASE_URL="https://raw.githubusercontent.com/google/material-design-icons/master/variablefont"
        AXES="FILL,GRAD,opsz,wght"
        ENCODED_AXES="%5B${AXES//,/%2C}%5D"
        for _ext in codepoints ttf; do
            _url="${BASE_URL}/MaterialSymbols${MATERIAL_STYLE}${ENCODED_AXES}.${_ext}"
            echo "  Downloading MaterialSymbols${MATERIAL_STYLE}.${_ext} ..."
            /usr/bin/curl -fgL --retry 3 --connect-timeout 30 --max-time 900 --show-error --progress-bar \
                -o "$_staged/MaterialSymbols${MATERIAL_STYLE}.${_ext}" "$_url" \
                || fail "Download failed: $_url"
        done
        # Per-symbol tags / synonyms / categories, used for the picker's ranked search. The
        # response carries an XSSI guard ")]}'" ahead of the JSON; drop everything before the
        # first brace on line 1, which handles both the guard-on-its-own-line and inline forms.
        echo "  Downloading $MATERIAL_METADATA ..."
        META_URL="https://fonts.google.com/metadata/icons?key=material_symbols&incomplete=true"
        /usr/bin/curl -fgL --retry 3 --connect-timeout 30 --max-time 900 --show-error --progress-bar \
            -o "$_staged/metadata.raw" "$META_URL" \
            || fail "Download failed: $META_URL"
        LC_ALL=C /usr/bin/sed '1s/^[^{]*//' "$_staged/metadata.raw" > "$_staged/$MATERIAL_METADATA" \
            || fail "Could not strip the XSSI guard from the Material Symbols metadata"
        /bin/rm -f "$_staged/metadata.raw"
        _source="google"
    fi

    material_validate "$_staged" \
        || fail "The staged Material Symbols files did not validate (expected a font, a '<name> <hex>' codepoints map and JSON the app can parse). Nothing was written to the bundle."
    material_render_probe "$_staged"
    case "$?" in
        0) ;;
        2) echo "${YELLOW}  no deployed glyphsvg to render-test the font against - structural checks only${RESET}" ;;
        *) fail "glyphsvg could not render a symbol from the staged font - it is corrupt or truncated. Nothing was written to the bundle." ;;
    esac

    # Only now does anything touch the bundle, and even then in two passes: copy every file under
    # a dot-prefixed name and verify it, then rename them all into place. A plain cp -f over the
    # live file would leave a truncated 15 MB font behind on ENOSPC or Ctrl-C - which both the -s
    # test and `file` accept, so the next run would sign it without a word.
    /bin/mkdir -p "$MATERIAL_DEST" || fail "Could not create $MATERIAL_DEST"
    for _f in "$MATERIAL_TTF" "$MATERIAL_CODEPOINTS" "$MATERIAL_METADATA"; do
        /bin/cp -f "$_staged/$_f" "$MATERIAL_DEST/.$_f.new" || fail "Could not deploy $_f"
        /usr/bin/cmp -s "$_staged/$_f" "$MATERIAL_DEST/.$_f.new" \
            || fail "Deployed $_f differs from the staged copy - the write did not complete."
    done
    for _f in "$MATERIAL_TTF" "$MATERIAL_CODEPOINTS" "$MATERIAL_METADATA"; do
        /bin/mv -f "$MATERIAL_DEST/.$_f.new" "$MATERIAL_DEST/$_f" || fail "Could not install $_f"
    done
    # Only one style is embedded. Sweep any other style left over from an earlier run or a changed
    # lib_material.py STYLE: each unused font is another 9-15 MB signed into the bundle.
    for _stale in "$MATERIAL_DEST"/MaterialSymbols*.ttf "$MATERIAL_DEST"/MaterialSymbols*.codepoints; do
        [ -f "$_stale" ] || continue
        case "$(/usr/bin/basename "$_stale")" in
            "$MATERIAL_TTF"|"$MATERIAL_CODEPOINTS") ;;
            *) /bin/rm -f "$_stale" && echo "  removed unused ${_stale#"$MATERIAL_DEST"/}" ;;
        esac
    done
    _mcount=$(/usr/bin/wc -l < "$MATERIAL_DEST/$MATERIAL_CODEPOINTS" | /usr/bin/tr -d " ")
    MATERIAL_STATUS="$MATERIAL_STYLE, $_mcount symbols (from $_source)"
    echo "  ${GREEN}Deployed${RESET} Material Symbols $MATERIAL_STYLE ($_mcount symbols, from $_source):"
    for _f in "$MATERIAL_TTF" "$MATERIAL_CODEPOINTS" "$MATERIAL_METADATA"; do
        printf "    %-40s %s\n" "$_f" "$(/usr/bin/du -h "$MATERIAL_DEST/$_f" | /usr/bin/cut -f1)"
    done
fi
echo

# ── Sweep build/editor droppings out of the payload ───────────────────────
# Python byte-code caches and .DS_Store would be sealed into the signature. Scoped to the two
# trees this script and the app's own scripts write - NOT the whole bundle, because the embedded
# Python distribution under Contents/Library/Python legitimately ships .pyc files and a blanket
# sweep would gut it.
for _tree in "$HELPERS_DIR" "$APP_SCRIPTS_DIR"; do
    [ -d "$_tree" ] || continue
    /usr/bin/find "$_tree" -name "__pycache__" -type d -prune -exec /bin/rm -rf {} +
    /usr/bin/find "$_tree" \( -name "*.pyc" -o -name ".DS_Store" -o -name ".*.new" \) -delete
done

# ── Sweep agent droppings and empty dot-directories out of the payload ─────
# Editor and agent tooling drops working directories such as .claude/ and .claude/.cc-writes into
# whatever tree it happens to run in. codesign treats one as a subcomponent and refuses to seal it:
#   In subcomponent: .../ICEdit.app/Contents/Helpers/glyphsvg/.claude
#   error: failed to sign app bundle
# Unlike the sweep above this covers the WHOLE bundle, because they appear wherever the tool was
# run - Contents/ and Contents/Resources/ as readily as the two trees this script writes.
#
# .claude is never payload, so it goes whole, contents and all: it is an agent's working directory
# that happened to land inside the bundle, and a non-empty one breaks signing exactly like an empty
# one. -prune keeps find from descending into what it is about to delete.
_claudedirs=$(/usr/bin/find "$APP_BUNDLE" -mindepth 1 -type d -name ".claude" -prune -print)
if [ -n "$_claudedirs" ]; then
    /usr/bin/find "$APP_BUNDLE" -mindepth 1 -type d -name ".claude" -prune -exec /bin/rm -rf {} +
    echo "  ${YELLOW}Removed${RESET} agent working directories that would have broken signing:"
    echo "$_claudedirs" | while IFS= read -r _d; do echo "    ${_d#"$APP_BUNDLE"/}"; done
fi

# Any other empty dot-directory goes too. Safe here where a blanket .pyc sweep is not: an empty
# directory carries nothing, so no payload can depend on one. -depth makes a single pass enough for
# a nest, since children are visited first and the parent is already empty when -empty reaches it.
_dotdirs=$(/usr/bin/find "$APP_BUNDLE" -mindepth 1 -depth -type d -name ".*" -empty -print -delete)
if [ -n "$_dotdirs" ]; then
    echo "  ${YELLOW}Removed${RESET} empty dot-directories that would have broken signing:"
    echo "$_dotdirs" | while IFS= read -r _d; do echo "    ${_d#"$APP_BUNDLE"/}"; done
fi

# What is left is a dot-directory with real content in it and a name this script does not recognize
# as droppings. It breaks signing the same way, but deleting it could throw away something the
# operator wanted. Name it instead, so the cause is obvious here rather than in codesign's output
# several stages later.
_dotleft=$(/usr/bin/find "$APP_BUNDLE" -mindepth 1 -type d -name ".*" -print)
if [ -n "$_dotleft" ]; then
    echo "  ${YELLOW}Warning${RESET}: dot-directories remain in the bundle and will likely fail codesign:"
    echo "$_dotleft" | while IFS= read -r _d; do echo "    ${_d#"$APP_BUNDLE"/}"; done
    echo "    They hold content and are not a name this script sweeps - remove them by hand if they are droppings."
fi

# ── 4. Verify the payload ─────────────────────────────────────────────────
# Before signing, not after. Sealing a bundle and only then finding the payload broken leaves a
# signed, broken app on disk together with a nonzero exit - the worst of both. Everything that can
# be checked without a signature is checked here.
echo "── 4. Verify ──"

# icedit is pure-stdlib Python, so the system interpreter proves the package imports and the CLI
# parses - the app runs it under its embedded Python, but a broken deploy fails identically here.
if [ -f "$ICEDIT_DEST/icedit" ]; then
    # Captured rather than piped into grep -q: see the note in material_validate.
    case "$(/usr/bin/python3 "$ICEDIT_DEST/icedit" --help 2>/dev/null)" in
        *"Icon Composer Editor"*) echo "  ${GREEN}Verify OK${RESET}: icedit runs and its icon_editor package imports" ;;
        *) fail "icedit did not print its usage - a missing icon_editor module or a syntax error." ;;
    esac
elif [ "$DO_ICEDIT" = "yes" ]; then
    fail "No icedit at $ICEDIT_DEST/icedit after the deploy stage."
fi

if [ -f "$GLYPHSVG_DEST/glyphsvg" ]; then
    # --version, not an SF Symbols render: rendering one needs SF Pro installed on THIS machine,
    # which is a property of the operator's Mac and not of the build. --version also catches the
    # failure this stage exists for - a stale binary left behind by a copy that did not happen -
    # since older glyphsvg builds print usage instead of a version, which the pattern rejects.
    _gver="$("$GLYPHSVG_DEST/glyphsvg" --version 2>/dev/null | /usr/bin/head -1)"
    case "$_gver" in
        [0-9]*) echo "  ${GREEN}Verify OK${RESET}: glyphsvg $_gver launches" ;;
        *) fail "glyphsvg did not report a version (got: ${_gver:-nothing}) - stale binary or a link failure." ;;
    esac

    /usr/bin/plutil -lint "$GLYPHSVG_DEST/sfmap.plist" >/dev/null 2>&1 \
        || fail "sfmap.plist is missing or not a valid property list."
    [ -s "$GLYPHSVG_DEST/names.txt" ] || fail "names.txt is missing or empty - the SF Symbols picker would open blank."
    echo "  ${GREEN}Verify OK${RESET}: sfmap.plist parses, names.txt has $(/usr/bin/wc -l < "$GLYPHSVG_DEST/names.txt" | /usr/bin/tr -d " ") entries"
elif [ "$DO_GLYPHSVG" = "yes" ]; then
    fail "No glyphsvg at $GLYPHSVG_DEST/glyphsvg after the deploy stage."
fi

# Checked against what is in the BUNDLE, not against the staged copy: this also covers the
# --skip-material and already-present paths, where nothing was staged and the resources on disk
# are whatever an earlier run left behind.
if [ -d "$MATERIAL_DEST" ]; then
    material_validate "$MATERIAL_DEST" \
        || fail "The deployed Material Symbols resources did not validate. A plain re-run re-provisions them; --refresh-material forces a fresh download."
    material_render_probe "$MATERIAL_DEST"
    case "$?" in
        0) echo "  ${GREEN}Verify OK${RESET}: glyphsvg renders a Material Symbols $MATERIAL_STYLE glyph from the deployed font" ;;
        2) echo "  ${GREEN}Verify OK${RESET}: Material Symbols $MATERIAL_STYLE files are intact (no glyphsvg to render-test against)" ;;
        *) fail "glyphsvg could not render from the deployed Material Symbols font - it is corrupt or truncated. A plain re-run re-provisions it; --refresh-material forces a fresh download." ;;
    esac
elif [ "$DO_MATERIAL" = "yes" ]; then
    fail "No Material Symbols resources at $MATERIAL_DEST after the provisioning stage."
fi
echo

# ── 5. Codesign ───────────────────────────────────────────────────────────
# Deep-sign with codesign_applet.sh (shipped beside this script): it signs every loose Mach-O and
# nested code bundle deepest-first - the helpers just deployed included - then the app itself,
# replacing the deprecated `codesign --deep`, and verifies the result. --brief keeps its output to
# per-bundle summary lines.
#
# The entitlements are named explicitly, with the auto-search switched off. Left to itself the
# script looks for a .entitlements file beside the BUNDLE, which is this directory for a default
# run but an arbitrary folder under --app=PATH - so signing an installed copy could silently adopt
# a stray entitlements file the operator never saw. This repo's OMCApplet.entitlements is the one
# that belongs to this app wherever the bundle happens to live.
if [ "$DO_CODESIGN" = "yes" ]; then
    echo "── 5. Codesign ──"
    [ -x "$SCRIPT_DIR/codesign_applet.sh" ] || fail "codesign_applet.sh not found beside this script"
    _entitlements="$SCRIPT_DIR/OMCApplet.entitlements"
    [ -f "$_entitlements" ] || fail "No $_entitlements - the applet's entitlements must ship with this script"
    "$SCRIPT_DIR/codesign_applet.sh" --brief --no-entitlements-search \
        "$APP_BUNDLE" "$SIGNING_IDENTITY" "$_entitlements" \
        || fail "codesign_applet.sh failed"
    CODESIGN_STATUS="signed ($SIGNING_IDENTITY)"
    echo

    # ── 6. Re-check after sealing ─────────────────────────────────────────
    # Everything above ran unsigned. Confirm the seal covers what is on disk and that the signed
    # binaries still launch - a helper that wrote into its own directory during verification, or a
    # signature that did not take, shows up here and nowhere else.
    echo "── 6. Re-check ──"
    /usr/bin/codesign --verify --deep "$APP_BUNDLE" 2>/dev/null \
        || fail "$(/usr/bin/basename "$APP_BUNDLE") does not satisfy its own code signature."
    if [ -f "$GLYPHSVG_DEST/glyphsvg" ]; then
        "$GLYPHSVG_DEST/glyphsvg" --version >/dev/null 2>&1 || fail "glyphsvg does not launch after signing."
    fi
    if [ -f "$ICEDIT_DEST/icedit" ]; then
        /usr/bin/python3 "$ICEDIT_DEST/icedit" --help >/dev/null 2>&1 || fail "icedit does not run after signing."
    fi
    echo "  ${GREEN}Re-check OK${RESET}: signature valid, signed helpers launch"
    echo
fi

echo "==== Done ===="
echo
echo "  icedit     : $ICEDIT_STATUS"
echo "  glyphsvg   : $GLYPHSVG_STATUS"
echo "  SF Symbols : $SFSYMBOLS_STATUS"
echo "  material   : $MATERIAL_STATUS"
echo "  codesign   : $CODESIGN_STATUS"
echo
echo "  ${GREEN}$(/usr/bin/basename "$APP_BUNDLE") is ready.${RESET}"
echo
