import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *

GOLD = np.array([0.82, 0.52, 0.06])


class Config(StyledCfg):
    """The Trench Warden: towering purple leviathan king in gold armour - big golden crown, shoulder pauldrons,
    belly armour with a glowing core, thick tentacles.  Grumpy but goofy, never scary-scary."""
    name = "TrenchWardenBoss"
    iris_color = (1.0, 0.72, 0.15)
    eye_scale = 1.55
    belly = 0.45
    ao_radius = 0.1
    normal_gain = 0.45

    def restyle(self, p):
        if p.name.startswith("ChestPlate"):           # flat slabs -> rounded golden belly armour
            i = int(p.name[-1])
            w = p.size[0]
            p.kind = "ellipsoid"
            resize(p, [w * 1.75, 1.6, 1.45])
            self.sw(p, [0, -1.9, 0.05])
            p.color = GOLD * (1.0 if i == 2 else 0.85)
            p.material = "Foil"
        if p.name == "WeakSpotCore":
            resize(p, [1.15, 1.15, 1.15])
            self.sw(p, [0, -1.9, -0.35])
        if p.name.startswith("CrownSpike") or p.name == "MantleGoldBand":     # real shiny gold instead of washed-out neon
            p.color = np.array([0.86, 0.52, 0.05]); p.material = "Foil"
        if p.name in ("Beak", "UpperSnout"):
            p.color = np.array([0.42, 0.16, 0.30])
        if p.name.startswith("Tooth"):
            resize(p, p.size * 1.15)

    def rounding(self, p): return 0.7
    def k(self, g): return {"Body": 0.4, "Mantle": 0.28}.get(g, 0.14)
    def part_k(self, n, kg):
        if n.startswith("ChestPlate"): return 0.25
        if n.startswith("CrownSpike"): return 0.15
        if n.startswith("Tooth"): return 0.04
        if n in ("Beak", "UpperSnout"): return 0.3
        if n.startswith("Eyebrow"): return 0.2
        if n == "WeakSpotCore": return 0.06
        return kg
    def budget(self, g):
        if g == "Body": return 8500
        if g == "Mantle": return 4200
        if g == "LureOrb": return 1000
        return 800
    def cells(self, g): return 240 if g == "Body" else (200 if g == "Mantle" else 130)
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Mantle" else (256 if g == "LureOrb" else 64))
    def amp(self, g): return 0.03 if g == "Body" else 0.015

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = []
            # gold angry brow ridges (outer end up) over the huge eyes
            for sx in (-1, 1):
                ex.append(Extra("ellipsoid", [2.7, 0.75, 1.1], [sx * 2.0, 2.45, -2.95], 0.2, "ChestPlate1", R=rotz(sx * 20)))
            # shoulder pauldrons + spikes
            for sx in (-1, 1):
                ex.append(Extra("ellipsoid", [2.5, 1.7, 2.6], [sx * 3.35, 1.85, -0.5], 0.3, "ChestPlate1", R=rotz(-sx * 22)))
                ex.append(spike([sx * 3.6, 2.5, -0.5], [sx * 0.55, 1.0, 0], 1.3, 0.75, 0.12, "ChestPlate1"))
                ex.append(Extra("ellipsoid", [1.25, 1.25, 1.25], [sx * 4.15, 1.2, -0.5], 0.15, "ChestPlate1"))

            def post(Q, d):
                x, y, z = Q[:, 0], Q[:, 1], Q[:, 2]
                # plate seams on the belly armour
                front = S.smoothstep(-3.0, -3.7, z) * S.smoothstep(-0.6, -1.4, y) * S.smoothstep(-3.6, -3.0, y) * 0 + S.smoothstep(-3.1, -3.9, z) * S.smoothstep(-0.9, -1.5, y) * S.smoothstep(-3.4, -2.9, y)
                seam = np.exp(-((np.abs(x) - 0.95) / 0.06) ** 2) * front
                return d + 0.07 * seam
            return Sculpt(None, post, ex, margin=0.25)
        if g == "Mantle":
            ex = [Extra("ellipsoid", [5.5, 0.6, 5.5], [0, 1.2, 0], 0.12, "MantleGoldBand")]
            n = 9
            for i in range(n):
                phi = np.radians(360.0 / n * i)
                fr = 0.5 + 0.5 * np.cos(phi)                     # 1 at the front (-Z), 0 at the back
                h = 1.5 + 1.2 * fr
                base = np.array([2.05 * np.sin(phi), 1.15, -2.05 * np.cos(phi)])
                dr = np.array([0.34 * np.sin(phi), 1.0, -0.34 * np.cos(phi)])
                ex.append(spike(base, dr, h, 0.95, 0.12, "CrownSpike1"))
            ex.append(Extra("ellipsoid", [0.85, 0.85, 0.5], [0, 1.2, -2.75], 0.1, "CrownSpike1"))   # front gem stud
            return Sculpt(None, None, ex, margin=0.2)
        return None

    def detail(self, g):
        skin = pebble(0.14, 0.07, 3, 0.1)
        gold = hammered(0.16, 0.09, 7)
        m = {"Basalt": skin, "Foil": gold, "Neon": pebble(0.1, 0.04, 2), "CorrodedMetal": hammered(0.18, 0.12, 5),
             "Granite": pebble(0.14, 0.08, 9), "SmoothPlastic": pebble(0.08, 0.05)}
        return lambda mat: m.get(mat, skin)
