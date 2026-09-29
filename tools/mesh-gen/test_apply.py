"""Offline check of assets/meshes/ApplyMeshes.lua (no Studio needed).

Runs every meshed buildscript through the model-preview Roblox shim, fakes Workspace.MeshImports
from the manifests (one MeshPart + SurfaceAppearance per mesh), runs ApplyMeshes.lua and verifies
for every model: MeshSwapped is set, each manifest mesh exists as a MeshPart, and no replaced part is left.

Usage: python3 tools/mesh-gen/test_apply.py --luau /path/to/luau
"""

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).parent
REPO = HERE.parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--luau", default="luau")
    args = ap.parse_args()
    manifests = [json.loads(p.read_text()) for p in sorted((REPO / "assets" / "meshes").glob("*/manifest.json"))]

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="apply-test-"))
    lines = ['local imports = Instance.new("Folder"); imports.Name = "MeshImports"; imports.Parent = workspace']
    for man in manifests:
        lines.append(f'do local f = Instance.new("Model"); f.Name = "{man["model"]}"; f.Parent = imports')
        for e in man["meshes"]:
            lines.append(f'  local p = Instance.new("MeshPart"); p.Name = "{e["name"]}"; p.Parent = f; Instance.new("SurfaceAppearance").Parent = p')
        lines.append("end")
    (tmp / "fake_imports.lua").write_text("\n".join(lines))
    out = tmp / "swapped.json"
    only = "creatures,enemies,npcs,gacha,pickups,decorations,buildings"
    subprocess.run(["node", "export.mjs", "--luau", args.luau, "--only", only,
                    "--extra", f"{tmp / 'fake_imports.lua'},{REPO / 'assets' / 'meshes' / 'ApplyMeshes.lua'}",
                    "--out", str(out)], cwd=REPO / "tools" / "model-preview", check=True, stdout=subprocess.DEVNULL)

    models = {m["name"]: m for m in json.loads(out.read_text())["models"]}
    issues = []
    for man in manifests:
        m = models.get(man["model"])
        if m is None:
            issues.append(f'{man["model"]}: not built')
            continue
        by_name = {}
        for p in m["parts"]:
            by_name.setdefault(p["name"], []).append(p)
        mesh_names = {e["name"] for e in man["meshes"]}
        if not m["attributes"].get("MeshSwapped"):
            issues.append(f'{man["model"]}: not swapped')
        for e in man["meshes"]:
            if not any(p["class"] == "MeshPart" for p in by_name.get(e["name"], [])):
                issues.append(f'{man["model"]}: mesh {e["name"]} missing')
            for r in e["replaces"]:
                if r not in mesh_names and r in by_name:
                    issues.append(f'{man["model"]}: replaced part {r} still there')
    for i in issues:
        print(i)
    print(f"{len(manifests)} models checked, {len(issues)} issue(s)")
    sys.exit(1 if issues else 0)


if __name__ == "__main__":
    main()
