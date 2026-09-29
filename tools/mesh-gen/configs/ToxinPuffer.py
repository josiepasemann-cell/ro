import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "ToxinPuffer"
    eye_inset = 0.35
    iris_color = (0.2, 0.12, 0.08)
    ao_radius = 0.12
    decal_re = r"Blush|Mouth|Smile|BellySeam|Highlight|Glint|Pupil|ToxicBlotch"

    def k(self, g): return 0.2 if g == "Body" else 0.1
    def part_k(self, n, kg): return {"BellyPatch": 0.3}.get(n, 0.1 if n.startswith("Spine") else kg)
    def budget(self, g): return 7500 if g == "Body" else 600
    def cells(self, g): return 220 if g == "Body" else 120
    def tex(self, g): return 768 if g == "Body" else 256
    def amp(self, g): return 0.02

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        ex = [cheek(ctx, f"Blush{i}", "Body", "Body", 0.12, 1.8, 0.6) for i in (1, 2)]
        for i in (1, 2):
            ex.append(socket(ctx, f"EyeWhite{i}", "Body", "Body", 0.06, 1.2))
        # longer, pointier spines than the original nubs (same anchors and directions)
        for n in [f"Spine{i}" for i in range(1, 9)] + [f"SpineTop{i}" for i in range(1, 6)]:
            s = ctx.shape(n)
            zdir = s.R[:, 2]
            ex.append(Extra("ellipsoid", [s.half[0] * 2 * 0.95, s.half[1] * 2 * 0.95, s.half[2] * 2 * 1.5], s.c + zdir * 0.06, 0.05, n, R=s.R))
        # little fins and a tail fan, tinted like the spines
        for sx in (-1, 1):
            ex.append(Extra("ellipsoid", [0.6, 0.16, 0.5], [sx * 1.68, -0.3, -0.1], 0.1, "Spine1",
                            R=np.array([[np.cos(sx * .5), -np.sin(sx * .5), 0], [np.sin(sx * .5), np.cos(sx * .5), 0], [0, 0, 1]])))
        ex.append(Extra("ellipsoid", [0.14, 0.95, 0.85], [0, 0.0, 1.8], 0.12, "Spine1"))

        m = ctx.shape("Mouth")

        def post(Q, d):
            ang = np.arctan2(Q[:, 0], -Q[:, 2])
            return d
        return Sculpt(None, None, ex, margin=0.15)

    def detail(self, g):
        return lambda m: {"Pebble": combine((pebble(0.11, 0.2, 4), 0.55), (pebble(0.045, 0.12, 1), 0.45)),
                          "SmoothPlastic": pebble(0.07, 0.08, 2)}.get(m)
