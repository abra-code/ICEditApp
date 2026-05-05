#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/ICEdit.app"
    exit 1
fi

APP_PATH="$1"
PYTHON_DIR="$APP_PATH/Contents/Library/Python"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THIN_PYTHON_SCRIPT="$SCRIPT_DIR/../Python-Embedding/thin_python_distribution.sh"
if [ ! -f "$THIN_PYTHON_SCRIPT" ]; then
    echo "Error: thin_python_distribution.sh not found at: $THIN_PYTHON_SCRIPT"
    echo "Please fetch Python-Embedding from: https://github.com/abra-code/Python-Embedding"
    exit 1
fi

if [ ! -d "$PYTHON_DIR" ]; then
    echo "Error: Python distribution not found at: $PYTHON_DIR"
    exit 1
fi

echo "Thinning $APP_PATH"
echo
echo "Removing unused modules..."
"$THIN_PYTHON_SCRIPT" \
  "$PYTHON_DIR" \
  ssl sqlite3 curses dbm decimal ctypes multiprocessing unittest xmlrpc pip setuptools certifi include pyc codecs_east_asian delocate "dist-info"

echo
echo "Removing unused build tools and dependencies..."
"$THIN_PYTHON_SCRIPT" \
  "$PYTHON_DIR" \
  altgraph macholib packaging typing_extensions asyncio requests urllib3 idna charset_normalizer pydoc email html http wsgiref zipfile tomllib lsprof statistics

echo
echo "Done."
