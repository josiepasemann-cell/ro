import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "ObsidianCrab"
    eye_inset = 0.25
    iris_color = (0.95, 0.25, 0.2)
    ao_radius = 0.1
    wobble = 0.005

    def rounding(self, p): return 0.55
    def k(self, g): return 0.26 if g == "Body" else 0.08
    def part_k(self, n, kg): return {"EyeStalk1": 0.12, "EyeStalk2": 0.12, "Belly": 0.2, "CarapaceHighlight": 0.3}.get(n, kg)
    def budget(self, g):
        if g == "Body": return 7500
        if g.startswith("Claw"): return 1500 if "Pincer" not in g else 800
        return 700
    def cells(self, g): return 220 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else (256 if g.startswith("Claw") else 128)
    def amp(self, g): return 0.02 if g == "Body" else 0.012

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = []
            rim = ctx.shape("CarapaceRim")
            # spiky obsidian shards along the carapace edge
            for a in np.radians([35, 65, 95, 125, 155, 205, 235, 265, 295, 325]):
                dirv = np.array([np.sin(a), 0, -np.cos(a)])
                pos = rim.c + dirv * 1.55 + np.array([0, 0.12, 0])
                if abs(np.sin(a)) < 0.35 and np.cos(a) < 0:      # keep the front clear for claws / eyes
                    continue
                # ellipsoid long axis along dir
                ax = np.cross([0, 1, 0], dirv); ax /= np.linalg.norm(ax)
                R = np.stack([ax, np.array([0, 1, 0]), dirv], 1)
                ex.append(Extra("ellipsoid", [0.34, 0.34, 0.95], pos, 0.09, "CarapaceRim", R=R))
            # low dorsal bumps
            for sx in (-1, 1):
                ex.append(Extra("ellipsoid", [0.5, 0.16, 0.5], [sx * 0.55, 0.9, -0.3], 0.15, "CarapaceHighlight"))
                ex.append(Extra("ellipsoid", [0.5, 0.16, 0.5], [sx * 0.6, 0.82, 0.5], 0.15, "CarapaceHighlight"))
            for i in (1, 2):
                ex.append(socket(ctx, f"Eye{i}", "Body", "Body", 0.06, 1.2))
            return Sculpt(None, None, ex, margin=0.1)
        if g.startswith("ClawLeft") or g.startswith("ClawRight"):
            s = ctx.shape(g); h = s.half
            cs = [Cut([h[0] * 1.5, 0.07, h[2] * 0.9], s.c + [0, 0.08, -h[2] * 0.85])]
            ex = [Extra("ellipsoid", [h[0] * 0.5, h[1] * 0.5, h[2] * 0.5], s.c + [0, 0.05, h[2] * 0.7], 0.15, g)]
            return Sculpt(None, lambda Q, d: cut(Q, d, cs, 0.03), ex, margin=0.05)
        if g.startswith("Leg") and "Foot" not in g:
            return Sculpt(None, None, [capsule(ctx, g, 0.12, 0.12)], margin=0.02)
        return None

    def detail(self, g):
        rock = pebble(0.11, 0.18, 5)
        shard = combine((pebble(0.16, 0.22, 8), 0.75), (pebble(0.07, 0.08, 2), 0.25))
        return lambda m: {"Slate": shard if g == "Body" else rock, "SmoothPlastic": pebble(0.07, 0.1, 3),
                          "Neon": None}.get(m)
