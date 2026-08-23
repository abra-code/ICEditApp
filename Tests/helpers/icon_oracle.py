"""Read back what is really in a .icon bundle, for Tests/lib.test.icedit.sh.

Deliberately the SYSTEM python's own json module, and deliberately neither the
applet's icedit tool nor lib_icedit.load_icon_json: an assertion about what a
remove removed, or about the fill a change_fill wrote, is worth nothing if the
thing reporting the contents is the same code that performed the change. This
file knows the .icon format and nothing else about ICEdit.

Every subcommand answers with a single value and prints UNREADABLE - never an
empty string - when icon.json is missing or malformed, so a check that expects
"" cannot be satisfied by a bundle that could not be read at all.

Values that are not plain strings come back as compact JSON with sorted keys, so
a check can compare them literally without depending on how the writer happened
to order or space the file.
"""

import json
import os
import sys

UNREADABLE = "UNREADABLE"


def load(icon_path):
    try:
        with open(os.path.join(icon_path, "icon.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def dump(value):
    if isinstance(value, str):
        return value
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def group_at(data, index):
    """1-based, matching the icedit CLI and every --group argument in the app."""
    groups = data.get("groups", [])
    if not 1 <= index <= len(groups):
        return None
    return groups[index - 1]


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(
            "usage: icon_oracle.py <count|layers|groups|fill|assets|layer|group>"
            " <icon-path> [argument ...]\n")
        return 2
    command, icon_path, rest = argv[1], argv[2], argv[3:]
    data = load(icon_path)
    if data is None:
        print(UNREADABLE)
        return 0

    if command == "layers":
        # Every group's layers, in file order: topmost layer of group 1 first.
        for group in data.get("groups", []):
            for layer in group.get("layers", []):
                print(layer.get("name", ""))
    elif command == "count":
        print(sum(len(g.get("layers", [])) for g in data.get("groups", [])))
    elif command == "groups":
        for group in data.get("groups", []):
            print(group.get("name", ""))
    elif command == "fill":
        print(dump(data.get("fill", "")))
    elif command == "assets":
        assets = os.path.join(icon_path, "Assets")
        try:
            for name in sorted(os.listdir(assets)):
                print(name)
        except OSError:
            print(UNREADABLE)
    elif command == "layer":
        # layer <icon> <layer-name> <key>: the key's value on that named layer.
        name, key = rest[0], rest[1]
        for group in data.get("groups", []):
            for layer in group.get("layers", []):
                if layer.get("name") == name:
                    print(dump(layer.get(key, "")))
                    return 0
        print("NO SUCH LAYER")
    elif command == "group":
        # group <icon> <1-based-index> <key>
        group = group_at(data, int(rest[0]))
        if group is None:
            print("NO SUCH GROUP")
            return 0
        print(dump(group.get(rest[1], "")))
    else:
        sys.stderr.write("icon_oracle.py: unknown subcommand %s\n" % command)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
