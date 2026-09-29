import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *

PLATE_C = np.array([0.0, 0.25, -2.0])


class Config(StyledCfg):
    """Heavy purple-grey tank: rounded armoured chest plate (no flat slab), big chin guard, tusks and angry brows."""
    name = "IronMawBrute"
    iris_color = (1.0, 0.25, 0.3)
    eye_scale = 1.2
    ao_radius = 0.13
    normal_gain = 0.45

    def restyle(self, p):
        if p.name == "ArmorPlate":                    # CSG bounding box -> domed breastplate that hugs the body
            p.kind = "ellipsoid"
            resize(p, [3.0, 1.9, 1.05])
            p.color = np.array([0.44, 0.40, 0.50]); p.material = "Metal"
            M = p.M.copy(); M[:3, 3] = M[:3, 3] + [0, 0, -0.1]; p.M = M
        if p.name.startswith("Foot"):
            resize(p, p.size * np.array([1.15, 1.2, 1.2]))

    def rounding(self, p): return 0.7
    def k(self, g): return {"Body": 0.26, "Mantle": 0.2}.get(g, 0.1)
    def part_k(self, n, kg):
        return {"ArmorPlate": 0.22, "Jaw": 0.25, "JawUnderbite": 0.22}.get(n, 0.06 if n.startswith(("Tooth", "BackSpike")) else (0.14 if n.startswith("Foot") else kg))
    def budget(self, g): return {"Body": 8000, "Mantle": 2400}.get(g, 1300)
    def cells(self, g): return 230 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Mantle" else 256)
    def amp(self, g): return 0.02 if g == "Body" else 0.012

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            cx, cy, cz = PLATE_C
            ex = []
            # chin guard: rounded armoured jaw shell wrapped around the underbite
            ex.append(Extra("ellipsoid", [3.3, 1.25, 2.2], [0, -1.3, -2.3], 0.25, "JawUnderbite", R=rotx(-8)))
            ex.append(Extra("ellipsoid", [2.5, 0.7, 1.4], [0, -1.7, -2.65], 0.2, "JawUnderbite"))
            # jaw hinge cheeks
            ex += [Extra("ellipsoid", [1.0, 1.3, 1.5], [sx * 1.65, -0.85, -1.55], 0.22, "Jaw") for sx in (-1, 1)]
            # bone tusks curling up out of the jaw
            for sx in (-1, 1):
                ex.append(spike([sx * 1.25, -1.05, -2.5], [sx * 0.18, 1.0, -0.25], 1.0, 0.36, 0.05, "Tooth1"))
            # angry brow ridges (outer end up) so the eyes read as menacing-but-goofy
            for sx in (-1, 1):
                ex.append(Extra("ellipsoid", [1.35, 0.42, 0.75], [sx * 1.25, 1.12, -1.75], 0.14, "JawUnderbite", R=rotz(sx * 18)))
            # chest plate rim + rivets
            ex.append(Extra("ellipsoid", [3.3, 2.15, 0.9], [cx, cy, cz + 0.02], 0.2, "ArmorPlate"))
            for i, (rx, ry) in enumerate([(-1.15, 0.9), (1.15, 0.9), (-1.35, -0.3), (1.35, -0.3), (-0.55, 1.05), (0.55, 1.05)]):
                ex.append(Extra("ellipsoid", [0.26, 0.26, 0.2], [rx, cy + ry - 0.25, cz - 0.42], 0.04, "ArmorPlate"))

            def post(Q, d):
                x, y, z = Q[:, 0], Q[:, 1] - cy, Q[:, 2]
                front = S.smoothstep(-1.6, -2.1, z) * S.smoothstep(1.55, 1.2, np.abs(x)) * S.smoothstep(1.15, 0.85, np.abs(y + 0.05))
                groove = np.exp(-(x / 0.05) ** 2) + np.exp(-((y - 0.05) / 0.05) ** 2) * 0.8
                d = d + 0.05 * groove * front                        # plate seams (centre line + belt)
                return d
            return Sculpt(None, post, ex, margin=0.15)
        if g == "Mantle":
            ex = [Extra("ellipsoid", [0.8, 0.55, 0.8], [sx * 1.0, 0.65, -0.3], 0.12, "BackSpike2") for sx in (-1, 1)]
            return Sculpt(None, None, ex, margin=0.05)
        return None

    def detail(self, g):
        armor = hammered(0.16, 0.16, 4)
        skin = pebble(0.09, 0.08, 8, 0.12)
        m = {"Metal": armor, "Granite": skin, "CorrodedMetal": armor, "SmoothPlastic": pebble(0.06, 0.06, 2)}
        return lambda mat: m.get(mat, skin)
