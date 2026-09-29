import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Splash the trader: chubby clownfish (orange, white bands with black outlines, green fins) carrying a trade crate."""
    name = "Trader"
    iris_color = (0.1, 0.12, 0.15)
    eye_scale = 1.55
    ao_radius = 0.1
    decal_re = r"Blush|Mouth|Smile|Seam|ShellMark|Highlight|Glint|Pupil|Stripe"

    def restyle(self, p):
        n = p.name
        if n.startswith("StripeBlack"):                         # bands were fully hidden inside the body: paint them as decals, black outline wider
            resize(p, [p.size[0], p.size[1], 0.62])
        elif n.startswith("StripeWhite"):
            resize(p, [p.size[0], p.size[1], 0.36])
        elif n in ("ArmL", "ArmLEdge", "ArmR", "ArmREdge"):    # fins were buried in the flank
            self.sw(p, [(-1 if "L" in n[3:4] else 1) * 0.2, 0, 0])
        elif n.startswith("TradeCrate"):
            self.sw(p, [0, -0.1, -0.2])
        elif n == "Mouth":
            self.sw(p, [0, 0, 0.02])

    def rounding(self, p): return 0.6
    def k(self, g): return {"Body": 0.24, "Head": 0.14}.get(g, 0.08)
    def part_k(self, n, kg):
        return {"TradeCrate": 0.03, "TradeCrateBandX": 0.02, "TradeCrateGem": 0.03, "TailStalk": 0.14}.get(n, kg)
    def budget(self, g):
        return {"Body": 6500, "Head": 2400, "ArmL": 700, "ArmR": 700, "TailFinEdge": 900}.get(g, 500)
    def cells(self, g): return 230 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Head" else (256 if g in ("ArmL", "ArmR", "TailFinEdge", "TailFin") else 128))
    def amp(self, g): return 0.012 if g == "Body" else 0.008

    def sculpt(self, g, ctx, dim):
        if g == "Head":
            ex = [Extra("ellipsoid", [0.42, 0.4, 0.4], [sx * 0.27, -0.14, -0.14], 0.1, "Head") for sx in (-1, 1)]     # cheeks
            return Sculpt(None, None, ex, margin=0.05)
        return None

    def detail(self, g):
        if g == "Body":
            sc = scales(1.2, 0.17, contrast=0.16)
            crate = planks(0.2, 0.18, 0)
            m = {"SmoothPlastic": sc, "WoodPlanks": crate, "CorrodedMetal": hammered(0.1, 0.12, 4), "Neon": pebble(0.05, 0.03)}
            return lambda mat: m.get(mat, pebble(0.08, 0.05))
        if g.startswith(("TailFin", "DorsalFin", "Arm")):
            return lambda mat: rays((1, 2), (0.0, -0.3), 12, 0.2) if g.startswith("TailFin") else pebble(0.05, 0.05)
        return lambda mat: pebble(0.06, 0.05, 3)
