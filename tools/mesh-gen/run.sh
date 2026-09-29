#!/usr/bin/env bash
# Export parts JSON -> build meshes -> render comparison.
# usage: LUAU=/path/to/luau THREE_DIR=/path/to/node_modules/three tools/mesh-gen/run.sh [Model ...]
# Optional env: TAG (separate cache/preview names so several runs can go in parallel),
#               PREVIEW_OUT (comparison PNG path), FAST=1 (quick low-res iteration).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
LUAU="${LUAU:-luau}"; THREE_DIR="${THREE_DIR:-$REPO/tools/model-preview/node_modules/three}"
MODELS=("$@"); [ ${#MODELS[@]} -eq 0 ] && MODELS=(GoldGuppy TreasureTurtle Shopkeeper)
TAG="${TAG:-default}"
CACHE="$HERE/cache/models-$TAG.json"
PREVIEW_OUT="${PREVIEW_OUT:-$REPO/docs/previews/mesh-prototype.png}"
FASTFLAG=(); [ "${FAST:-0}" = "1" ] && FASTFLAG=(--fast)
mkdir -p "$HERE/cache"
(cd "$REPO/tools/model-preview" && node export.mjs --luau "$LUAU" --only "$(IFS=,; echo "${MODELS[*]}")" --out "$CACHE")
for m in "${MODELS[@]}"; do python3 "$HERE/pipeline.py" --models "$CACHE" --model "$m" "${FASTFLAG[@]}"; done
node "$HERE/preview.mjs" --three "$THREE_DIR" --models "$CACHE" --meshes "$HERE/build" --names "$(IFS=,; echo "${MODELS[*]}")" --out "$PREVIEW_OUT"
