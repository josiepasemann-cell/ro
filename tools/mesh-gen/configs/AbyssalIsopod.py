import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "AbyssalIsopod"
    iris_color = (0.35, 0.55, 0.85)
    iris_ratio = 1.6
    ao_radius = 0.1
    wobble = 0.004
    eye_inset = 1.0
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil"

    def k(self, g): return 0.04 if g == "Body" else 0.08
    def part_k(self, n, kg): return {"Belly": 0.22}.get(n, kg)
    def budget(self, g): return 6500 if g == "Body" else 700
    def cells(self, g): return 230 if g == "Body" else 120
    def tex(self, g): return 768 if g == "Body" else (128 if g.startswith("Antenna") else 256)
    def amp(self, g): return 0.016
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        ex = []
        # arched carapace plates: a raised dorsal ridge blob on every segment + gentle side rims
        for i in range(1, 6):
            n = "Body" if i == 3 else f"Segment{i}"
            s = ctx.shape(n)
            hx, hy, hz = s.half
            ex.append(Extra("ellipsoid", [hx * 1.0, hy * 1.12, hz * 1.12], s.c + [0, hy * 0.12, 0], 0.07, n))
        for sx in (-1, 1):                                # brow ridges + eye sockets
            ex.append(socket(ctx, f"Eye{1 if sx > 0 else 2}", "Body", "Segment1", 0.08, 1.2))
        # chubby cheeks so the head reads as a face
        s1 = ctx.shape("Segment1")
        for sx in (-1, 1):
            ex.append(Extra("ellipsoid", [0.55, 0.42, 0.5], s1.c + [sx * 0.62, -0.22, -0.32], 0.1, "Segment1"))
        return Sculpt(None, None, ex, margin=0.05)

    def detail(self, g):
        shell = mix(pebble(0.13, 0.10, 2), bands(2, 0.82, 0.06))
        return lambda m: {"SmoothPlastic": shell, "Neon": pebble(0.1, 0.03)}.get(m)
