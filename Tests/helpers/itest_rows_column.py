#!/usr/bin/env python3
"""itest_rows_column.py - prints one column of each row of an actionui.getRows reply.

Usage: itest_rows_column.py <column, from 1>

Used by icedit.itest.sh: the reply comes on stdin as JSON (a list of rows, each a list of strings),
and each row's cell in that column is printed on a line of its own, in order (empty when the row
is shorter).
"""

import json
import sys


def main(argv):
    if len(argv) != 2 or not argv[1].isdigit() or int(argv[1]) < 1:
        print("usage: itest_rows_column.py <column, from 1>", file=sys.stderr)
        return 2
    column = int(argv[1]) - 1
    try:
        rows = json.load(sys.stdin)
    except ValueError as error:
        print("itest_rows_column: the reply is not JSON: %s" % error, file=sys.stderr)
        return 1
    if not isinstance(rows, list):
        print("itest_rows_column: the reply is not a list of rows", file=sys.stderr)
        return 1
    for row in rows:
        if isinstance(row, list) and len(row) > column:
            print(row[column])
        else:
            print("")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
