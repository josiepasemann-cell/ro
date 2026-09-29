"""MagmaSquid: dark basalt-red squid with glowing lava cracks, pointed mantle crest, fins and curly tentacles."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "MagmaSquid"
    iris_color = (0.9, 0.35, 0.05)
    ao_radius = 0.1
    eye_inset = -0.1
    wobble = 0.005
    blend_tau = 0.03
    tex_small = 128

    def k(self, g): return 0.3 if g == "Body" else 0.08
    def part_k(self, n, kg): return 0.26 if n in ("MantleTip", "MantleBelly") else kg
    def budget(self, g):
        if g == "Body": return 6500
        if g.startswith("Wing"): return 700
        return 500
    def cells(self, g): return 230 if g == "Body" else 110
    def tex(self, g): return 512 if g == "Body" else (128 if g.startswith("Wing") else (64 if ("Tip" in g or "Vein" in g) else 96))
    def amp(self, g): return 0.006 if g == "Body" else 0.005

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        DARK, MID = rgb(45, 10, 14), rgb(70, 18, 22)
        b = ctx.shape("Body")
        ex = []
        for s in (-1, 1):
            ex.append(Tint("ellipsoid", [0.6, 0.22, 0.5], [s * 0.6, 0.86, -1.2], 0.12, MID))
        ex.append(Cone([0, 1.05, 0.0], [0, 1.85, 0.95], 0.75, 0.25, DARK, "CrackedLava", blunt=0.02))    # pointed mantle crest

        def post(Q, d):
            ang = np.arctan2(Q[:, 0], Q[:, 2])
            rr = np.hypot(Q[:, 0], Q[:, 2])
            rib = 0.5 + 0.5 * np.cos(ang * 10)
            back = S.smoothstep(-0.2, 0.9, Q[:, 2]) * S.smoothstep(-0.9, 0.5, Q[:, 1])       # plates on the rear mantle
            mouth = Extra("ellipsoid", [0.55, 0.06, 0.3], [0, -0.55, -1.52], 0, "Body")._sh(Q)
            return S.smax(d - 0.025 * back * rib * rib, -mouth, 0.02)
        return Sculpt(None, post, ex, margin=0.2)

    def paint(self, g, field):
        HOT = rgb(255, 115, 30)
        if g == "Body":
            veins = voronoi_veins(0.62, 0.032, 11, warp=0.3)
            face = lambda Q: np.where((Q[:, 2] < -0.9) & (Q[:, 1] < 1.0), 1.0, 0.0)
            v = lambda Q: np.where(face(Q) > 0.5, 1.0, veins(Q))
            glow = lambda Q: np.where(Q[:, 1] > 0.9, dots(0.3, 0.03, 0.06, 5, 0.5)(Q), 1.0)
            return [Paint(v, HOT, True, 1.0), Paint(glow, rgb(255, 190, 60), True, 1.0)]
        return []

    def detail(self, g):
        if g == "Body":
            return lambda m: {"CrackedLava": pebble(0.16, 0.1, 4, 0.1), "SmoothPlastic": pebble(0.08, 0.06, 3, 0.05), "Neon": pebble(0.1, 0.05, 2, 0)}.get(m)
        if g.startswith("Wing"):
            return lambda m: {"SmoothPlastic": rays((1, 2), (0.0, -0.6), 10, 0.16), "Neon": rays((1, 2), (0.0, -0.6), 10, 0.14)}.get(m)
        return lambda m: {"SmoothPlastic": pebble(0.05, 0.1, 3, 0.05), "Neon": pebble(0.05, 0.04, 2, 0)}.get(m)
