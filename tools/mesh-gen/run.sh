#!/usr/bin/env bash
# Full prototype run: export parts JSON -> build meshes -> render comparison.
# usage: LUAU=/path/to/luau THREE_DIR=/path/to/node_modules/three tools/mesh-gen/run.sh [Model ...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
LUAU="${LUAU:-luau}"; THREE_DIR="${THREE_DIR:-$REPO/tools/model-preview/node_modules/three}"
MODELS=("$@"); [ ${#MODELS[@]} -eq 0 ] && MODELS=(GoldGuppy TreasureTurtle Shopkeeper)
mkdir -p "$HERE/cache"
(cd "$REPO/tools/model-preview" && node export.mjs --luau "$LUAU" --only "$(IFS=,; echo "${MODELS[*]}")" --out "$HERE/cache/models.json")
for m in "${MODELS[@]}"; do python3 "$HERE/pipeline.py" --models "$HERE/cache/models.json" --model "$m"; done
node "$HERE/preview.mjs" --three "$THREE_DIR" --models "$HERE/cache/models.json" --names "$(IFS=,; echo "${MODELS[*]}")"
