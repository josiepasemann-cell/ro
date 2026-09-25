"""Report parts that float free of the rest of each model.

Reads out/models.json (written by export.mjs) and treats every visible part
as an oriented box. Balls use their smallest axis (Roblox renders a Ball as
a sphere of that diameter); cylinders run along X with the smaller of Y/Z as
diameter. Two parts count as connected when their boxes overlap or come
within TOLERANCE studs. Any group of parts not connected to the model's
largest group is reported as floating.

Usage: python3 check_connectivity.py [--category Creatures] [--strict]
Exit code 1 when a floating group is found (useful as a gate).
"""

import argparse
import json
import pathlib
import sys

import numpy as np

TOLERANCE = 0.08
SKIP_CATEGORIES = {"Hub", "Terrain"}


def part_box(part):
    size = np.array(part["size"], dtype=float)
    shape = part.get("shape", "Block")
    if part.get("meshScale") is not None:
        size = size * np.array(part["meshScale"], dtype=float)
    if shape == "Ball" and part.get("meshType") is None:
        size = np.full(3, size.min())
    elif shape == "Cylinder":
        d = min(size[1], size[2])
        size = np.array([size[0], d, d])
    cf = part["cf"]
    center = np.array(cf[0:3], dtype=float)
    rot = np.array(cf[3:12], dtype=float).reshape(3, 3)
    return center, rot, size / 2.0


def boxes_touch(a, b, tol):
    ca, ra, ha = a
    cb, rb, hb = b
    ha = ha + tol / 2
    hb = hb + tol / 2
    axes_a = [ra[:, i] for i in range(3)]
    axes_b = [rb[:, i] for i in range(3)]
    axes = axes_a + axes_b
    for u in axes_a:
        for v in axes_b:
            c = np.cross(u, v)
            n = np.linalg.norm(c)
            if n > 1e-6:
                axes.append(c / n)
    d = cb - ca
    for axis in axes:
        pa = sum(ha[i] * abs(np.dot(axes_a[i], axis)) for i in range(3))
        pb = sum(hb[i] * abs(np.dot(axes_b[i], axis)) for i in range(3))
        if abs(np.dot(d, axis)) > pa + pb:
            return False
    return True


def components(parts):
    visible = [p for p in parts if p.get("transparency", 0) < 0.98]
    boxes = [part_box(p) for p in visible]
    n = len(visible)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(n):
        for j in range(i + 1, n):
            if find(i) != find(j) and boxes_touch(boxes[i], boxes[j], TOLERANCE):
                parent[find(i)] = find(j)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return visible, sorted(groups.values(), key=len, reverse=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--category")
    ap.add_argument("--json", default=str(pathlib.Path(__file__).parent / "out" / "models.json"))
    args = ap.parse_args()

    data = json.loads(pathlib.Path(args.json).read_text())
    bad_models = 0
    for model in data["models"]:
        if model["category"] in SKIP_CATEGORIES:
            continue
        if args.category and model["category"] != args.category:
            continue
        visible, groups = components(model["parts"])
        if len(groups) <= 1:
            continue
        bad_models += 1
        floating = [visible[i]["name"] for g in groups[1:] for i in g]
        print(f"{model['category']}/{model['name']}: {len(groups) - 1} floating group(s): {', '.join(floating)}")
    print(f"\n{bad_models} model(s) with floating parts")
    sys.exit(1 if bad_models else 0)


if __name__ == "__main__":
    main()
