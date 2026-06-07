#!/bin/bash
set -euo pipefail

# Downloads the Google Material Symbols (Rounded) resources used by the
# "Layer with Material Symbol" picker into an ICEdit.app bundle:
#
#   Contents/Helpers/glyphsvg/material/
#       MaterialSymbolsRounded.ttf            <- the variable font glyphsvg renders
#       MaterialSymbolsRounded.codepoints     <- name -> glyph map (the symbol list)
#       material_symbols_metadata.json        <- tags/synonyms/categories for search
#
# These files are large and are NOT committed to the repo (see .gitignore). Run
# this once after checking out, and again whenever you want to refresh the data.
#
# Source: https://github.com/google/material-design-icons/tree/master/variablefont
#
# Usage: ./download_material_symbols.sh /path/to/ICEdit.app

if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/ICEdit.app" >&2
    exit 1
fi

APP_PATH="$1"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: app bundle not found at: $APP_PATH" >&2
    exit 1
fi

DEST_DIR="$APP_PATH/Contents/Helpers/glyphsvg/material"
mkdir -p "$DEST_DIR"

STYLE="Rounded"
BASE_URL="https://raw.githubusercontent.com/google/material-design-icons/master/variablefont"
AXES="FILL,GRAD,opsz,wght"

# URL-encode the bracketed axis suffix once: [FILL,GRAD,opsz,wght]
ENCODED_AXES="%5B${AXES//,/%2C}%5D"

for ext in codepoints ttf; do
    url="${BASE_URL}/MaterialSymbols${STYLE}${ENCODED_AXES}.${ext}"
    out="${DEST_DIR}/MaterialSymbols${STYLE}.${ext}"
    echo "Downloading MaterialSymbols${STYLE}.${ext} ..."
    curl -fgL --retry 3 -o "$out" "$url"
done

# Per-symbol search metadata (tags / synonyms / categories / popularity). The
# response has an XSSI guard ")]}'" prefix which we strip to leave valid JSON.
echo "Downloading material_symbols_metadata.json ..."
META_URL="https://fonts.google.com/metadata/icons?key=material_symbols&incomplete=true"
curl -fgL --retry 3 -o "${DEST_DIR}/material_symbols_metadata.raw" "$META_URL"
python3 -c "import sys; d=open('${DEST_DIR}/material_symbols_metadata.raw').read(); open('${DEST_DIR}/material_symbols_metadata.json','w').write(d[d.find('{'):])"
rm -f "${DEST_DIR}/material_symbols_metadata.raw"

echo ""
echo "Downloaded into ${DEST_DIR}:"
for f in "MaterialSymbols${STYLE}.ttf" "MaterialSymbols${STYLE}.codepoints" "material_symbols_metadata.json"; do
    printf "  %-40s %s\n" "$f" "$(du -h "${DEST_DIR}/$f" | cut -f1)"
done
echo ""
echo "Done. Re-sign the bundle (codesign_applet.sh) after refreshing resources."
