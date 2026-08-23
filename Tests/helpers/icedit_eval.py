"""Evaluate one expression in lib_icedit's namespace, for Tests/lib.test.icedit.sh.

Run under the applet's OWN interpreter (the harness resolves it into
$OMCTEST_PYTHON, which is the embedded Contents/Library/Python/bin/python3 when
the bundle ships one). Testing lib_icedit under a different Python than the
engine uses would be testing a different library.

A separate process per call on purpose: lib_icedit's module-level code reads
WINDOW_UUID, PARENT_UUID and TMPDIR at import and bakes them into DOCUMENT_UUID,
the pasteboard key names and SCRATCH_DIR. An in-process cache would go stale the
moment a test entered a child sheet or switched windows.

The expression's arguments arrive as a list named ARGV rather than being pasted
into the expression text. That is a correctness requirement, not a style
preference: the values worth testing here are colors, layer names and fill
strings containing quotes, commas and backslashes, and an interpolated
expression would be a quoting bug the first time a test did its job.

An expression that RAISES prints "RAISED: <type>" rather than nothing, for the
same reason icon_oracle.py prints UNREADABLE rather than an empty line. `check`
compares command substitution output and throws the exit status away, so a
helper that failed silently to empty would satisfy every check whose expected
value is "" - and those are exactly the checks written to prove a function's
except-clause catches something. Two of them in 80-library were passing that
way before this was added.
"""

import os
import sys

_BUNDLE = os.environ.get("OMC_APP_BUNDLE_PATH", "")
if not _BUNDLE:
    sys.exit("icedit_eval.py: OMC_APP_BUNDLE_PATH is not set")

sys.path.insert(0, os.path.join(_BUNDLE, "Contents/Resources/Scripts"))
import lib_icedit  # noqa: E402  - the path above has to be set first
import lib_material  # noqa: E402
import lib_debounce  # noqa: E402


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: icedit_eval.py <expression> [argument ...]\n")
        return 2
    namespace = dict(vars(lib_icedit))
    namespace["lib_icedit"] = lib_icedit
    namespace["lib_material"] = lib_material
    namespace["lib_debounce"] = lib_debounce
    namespace["ARGV"] = argv[2:]
    try:
        value = eval(argv[1], namespace)
    except Exception as failure:  # noqa: BLE001 - any raise is a result here
        sys.stdout.write("RAISED: %s" % type(failure).__name__)
        sys.stderr.write("icedit_eval.py: %r\n" % (failure,))
        return 1
    sys.stdout.write("" if value is None else str(value))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
