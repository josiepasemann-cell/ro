"""Generate assets/meshes/ApplyMeshes.lua from every assets/meshes/*/manifest.json.

The Luau body lives in apply_template.lua; this script only fills in the
LAYOUT table. Replaced parts are stored with their position relative to the
model's PrimaryPart (from cache/models.json) because buildscripts reuse part
names inside one model.

Usage: python3 make_apply_script.py
"""

import json
import pathlib

import numpy as np

HERE = pathlib.Path(__file__).parent
REPO = HERE.parent.parent
MESHES = REPO / "assets" / "meshes"


def fmt(values):
    return "{" + ", ".join(f"{v:.5g}" for v in values) + "}"


def world_cf(cf):
    rot = np.array(cf[3:12], dtype=float).reshape(3, 3)
    return np.array(cf[0:3], dtype=float), rot


def main():
    models = {}
    for cache in sorted((HERE / "cache").glob("models*.json")):
        for m in json.loads(cache.read_text())["models"]:
            models[m["name"]] = m

    lines = ["local LAYOUT = {"]
    for manifest_path in sorted(MESHES.glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text())
        name = manifest["model"]
        source = models[name]
        parts = source["parts"]
        primary = next(p for p in parts if p["name"] == manifest["primaryPart"])
        base_pos, base_rot = world_cf(primary["cf"])

        lines.append(f"\t{name} = {{ Meshes = {{")
        for mesh in manifest["meshes"]:
            replaces = []
            used = set()
            for part_name in mesh["replaces"]:
                # Buildscripts reuse names, so each listed name consumes the next unused part with it.
                idx = next(i for i, p in enumerate(parts) if p["name"] == part_name and i not in used and i not in claimed)
                used.add(idx)
                claimed.add(idx)
                pos, _ = world_cf(parts[idx]["cf"])
                local = base_rot.T @ (pos - base_pos)
                replaces.append(f'{{ Name = "{part_name}", Pos = {fmt(local)} }}')
            lines.append(
                "\t\t{ "
                f'Name = "{mesh["name"]}", Center = {fmt(mesh["center"])}, Pivot = {fmt(mesh["pivot"])}, '
                f'Size = {fmt(mesh["size"])}, Material = "{mesh["material"]}", Transparency = {mesh["transparency"]:.3g}, '
                f"Replaces = {{ {', '.join(replaces)} }} }},"
            )
        lines.append("\t} },")
        claimed.clear()
    lines.append("}")

    template = (HERE / "apply_template.lua").read_text()
    out = MESHES / "ApplyMeshes.lua"
    out.write_text(template.replace("--@@LAYOUT@@", "\n".join(lines)))
    print(f"wrote {out}")


claimed: set = set()

if __name__ == "__main__":
    main()
