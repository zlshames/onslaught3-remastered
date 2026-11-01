#!/usr/bin/env bash
# Re-exports the classic asset pack from the original SWF (developer machine
# only; needs Java 21 and JPEXS FFDec 26.3 — see the ffdec-asset-export skill —
# and rsvg-convert (`brew install librsvg`) for the vector redraws in tool/art/).
#
#   tool/export_assets.sh            # export + pack
#   FFDEC=/path/to/ffdec-cli.jar tool/export_assets.sh
#
# Never writes into .legacy/ (rule R11). Output (committed):
#   assets/images/classic/  atlases at every density in SCALES, ground image, manifest.json
#   assets/images/enhanced/ the Enhanced pack (vector creep redraws), same layout
#   assets/audio/classic/   sound clips named by clip id
set -euo pipefail

cd "$(dirname "$0")/.."
FFDEC="${FFDEC:-$HOME/Downloads/ffdec_26.3.0_macosx/FFDec.app/Contents/Resources/ffdec-cli.jar}"
SWF=.legacy/Onslaught2.swf
# Atlas densities (image px per world px). The renderer picks the smallest
# one that covers camera zoom × device pixel ratio. Measured at max zoom:
# Pixel 10 ≈ 5.1 device px per world px, a retina desktop window ≈ 6, an
# iPad Pro ≈ 9.5.
SCALES="${SCALES:-1 2 3 4 6 9}"
OUT="${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/onslaught-ffdec.XXXXXX")}"

[[ -f "$FFDEC" ]] || { echo "FFDec CLI not found at $FFDEC" >&2; exit 1; }
command -v java >/dev/null || { echo "java not on PATH" >&2; exit 1; }
command -v rsvg-convert >/dev/null || { echo "rsvg-convert not on PATH (brew install librsvg)" >&2; exit 1; }

# Every sprite and shape symbol listed in tool/asset_map.json.
IDS=$(python3 -c 'import json;print(",".join(str(v["symbol"]) for v in json.load(open("tool/asset_map.json"))["sprites"].values() if v.get("kind") != "shape"))')
SHAPES=$(python3 -c 'import json;print(",".join(str(v["symbol"]) for v in json.load(open("tool/asset_map.json"))["sprites"].values() if v.get("kind") == "shape"))')

echo "Exporting $(echo "$IDS" | tr ',' '\n' | wc -l | tr -d ' ') symbols to $OUT"
for z in $SCALES; do
  java -jar "$FFDEC" -zoom "$z" -selectid "$IDS" -format sprite:png -export sprite "$OUT/png${z}x" "$SWF" >/dev/null
done
java -jar "$FFDEC" -selectid "$IDS" -format sprite:svg -export sprite "$OUT/svg" "$SWF" >/dev/null
if [[ -n "$SHAPES" ]]; then
  for z in $SCALES; do
    java -jar "$FFDEC" -zoom "$z" -selectid "$SHAPES" -format shape:png -export shape "$OUT/shape_png${z}x" "$SWF" >/dev/null
  done
  java -jar "$FFDEC" -selectid "$SHAPES" -format shape:svg -export shape "$OUT/shape_svg" "$SWF" >/dev/null
fi

fvm dart run tool/pack_atlas.dart --ffdec "$OUT"
fvm dart run tool/pack_atlas.dart --ffdec "$OUT" --map tool/asset_map_enhanced.json
echo "Export kept in $OUT (delete when done)."
