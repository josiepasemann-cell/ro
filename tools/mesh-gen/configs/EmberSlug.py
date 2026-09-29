import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "EmberSlug"
    iris_color = (1.0, 0.55, 0.12)
    iris_ratio = 3.0
    ao_radius = 0.12
    wobble = 0.006
    eye_inset = 0.8
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|EmberCrack"

    def k(self, g): return 0.2 if g == "Body" else 0.06
    def part_k(self, n, kg):
        if n.startswith("RidgeSegment"): return 0.09
        return {"BellyPlate": 0.28, "Head": 0.3, "TailRidge": 0.3}.get(n, kg)
    def budget(self, g): return 8000 if g == "Body" else 350
    def cells(self, g): return 230 if g == "Body" else 100
    def tex(self, g): return 768 if g == "Body" else 128
    def amp(self, g): return 0.022
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        b = ctx.shape("Body")
        hd = ctx.shape("Head").c
        ex = [socket(ctx, "Eye1", "Head", "Head", 0.1, 1.2), socket(ctx, "Eye2", "Head", "Head", 0.1, 1.2)]
        for i in range(1, 5):                          # glowing ember ridge: bumps on the back (originally buried in the body)
            r = ctx.shape(f"RidgeSegment{i}").c
            top = b.half[1] * np.sqrt(max(0.0, 1 - (r[2] - b.c[2]) ** 2 / b.half[2] ** 2))
            ex.append(Extra("ellipsoid", [0.55, 0.42, 0.72], [b.c[0], b.c[1] + top - 0.02, r[2]], 0.07, f"RidgeSegment{i}"))
        for i in range(1, 5):                          # glowing lava cracks along both flanks
            c = ctx.shape(f"EmberCrack{i}").c
            zz = (c[2] - b.c[2]) / b.half[2]
            for sx in (-1, 1):
                w = b.half[0] * np.sqrt(max(0.0, 1 - zz ** 2)) * 0.97
                ex.append(Extra("ellipsoid", [0.18, 0.3, 0.62], [b.c[0] + sx * w, b.c[1] + 0.05, c[2] + sx * 0.18], 0.04, f"EmberCrack{i}"))
        for sx in (-1, 1):                             # cheeks
            ex.append(Extra("ellipsoid", [0.4, 0.36, 0.36], hd + [sx * 0.42, -0.2, -0.28], 0.12, "Head"))
        ex.append(Extra("ellipsoid", [2.3, 0.4, 3.3], b.c + [0, -0.55, 0], 0.15, "BellyPlate"))     # foot skirt
        def post(Q, d):
            return groove(Q, d, hd + [0, -0.3, -0.5], [0.6, 0.05, 0.3], 0.5, 0.03)
        return Sculpt(None, post, ex, margin=0.1)

    def detail(self, g):
        rock = mix(pebble(0.22, 0.20, 7), pebble(0.08, 0.08, 3))
        return lambda m: {"CrackedLava": rock, "SmoothPlastic": pebble(0.1, 0.1, 4), "Neon": pebble(0.1, 0.04)}.get(m)
