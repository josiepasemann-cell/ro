import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "BloomMoth"
    iris_color = (0.5, 0.3, 0.2)
    iris_ratio = 1.6
    ao_radius = 0.1
    wobble = 0.002
    eye_inset = 0.35

    def k(self, g): return 0.15 if g == "Body" else 0.05
    def part_k(self, n, kg): return {"Head": 0.18, "Belly": 0.2}.get(n, kg)
    def budget(self, g): return {"Body": 5500, "WingRight": 900, "WingLeft": 900}.get(g, 250)
    def cells(self, g): return 220 if g == "Body" else (140 if g.startswith("Wing") and "Fore" not in g and len(g) <= 9 else 90)
    def tex(self, g):
        if g == "Body": return 512
        if g in ("WingRight", "WingLeft"): return 256
        if g.startswith("WingRightFore") or g.startswith("WingLeftFore"): return 128
        return 32
    def amp(self, g): return 0.014
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        hd = ctx.shape("Head").c
        ex = [socket(ctx, "EyeWhite1", "Head", "Head", 0.08, 1.1), socket(ctx, "EyeWhite2", "Head", "Head", 0.08, 1.1)]
        for sx in (-1, 1):
            ex.append(Extra("ellipsoid", [0.28, 0.24, 0.24], hd + [sx * 0.27, -0.12, -0.13], 0.1, "Belly"))   # rosy cheeks
        return Sculpt(None, None, ex, margin=0.04)

    def detail(self, g):
        if g.startswith("Wing") and not g.startswith("WingSpot") and not g.startswith("WingEdge"):
            side = 1.0 if "Right" in g else -1.0
            veins = rays((0, 2), (0.42 * side, 0.0), 9, 0.14)
            return lambda m: veins
        fuzz = mix(pebble(0.045, 0.08, 4), bands(2, 0.36, 0.05))
        return lambda m: {"SmoothPlastic": fuzz, "Neon": pebble(0.05, 0.02)}.get(m)
