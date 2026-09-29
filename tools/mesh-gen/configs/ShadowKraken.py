import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Near-black grumpy kraken: smug grin, angry brows, barnacle warts, glowing red eyes, 8 wobbly tentacles."""
    name = "ShadowKraken"
    iris_color = (1.0, 0.18, 0.25)
    eye_scale = 1.15
    ao_radius = 0.13
    normal_gain = 0.45

    def restyle(self, p):
        if p.name.startswith("Barnacle"):
            resize(p, p.size * 1.25)

    def rounding(self, p): return 0.75 if p.name.startswith("Beak") else 0.6
    def k(self, g): return {"Body": 0.24, "Mantle": 0.18}.get(g, 0.14)
    def part_k(self, n, kg):
        if n.startswith("Barnacle"): return 0.1
        if n.startswith("CrownRidge"): return 0.1
        if n.startswith("Eyebrow"): return 0.1
        return kg
    def budget(self, g): return {"Body": 7500, "Mantle": 2200}.get(g, 600)
    def cells(self, g): return 230 if g == "Body" else (150 if g == "Mantle" else 110)
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Mantle" else 64)
    def amp(self, g): return 0.016 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = []
            ex += [Extra("ellipsoid", [1.3, 1.0, 1.1], [sx * 1.25, -0.7, -1.55], 0.25, "Body") for sx in (-1, 1)]   # cheeks

            def post(Q, d):
                x = Q[:, 0]
                Qw = Q.copy()
                Qw[:, 1] = Q[:, 1] + 0.32 * (x / 1.1) ** 2                                   # curl the slit into a smirk
                lip = Extra("ellipsoid", [2.3, 0.11, 0.8], [0, -0.95, -2.2], 0, "Body")._sh(Qw)
                return S.smax(d, -lip, 0.025)
            return Sculpt(None, post, ex, margin=0.08)
        if g == "Mantle":
            return Sculpt(None, None, [Extra("ellipsoid", [0.5, 1.2, 2.4], [0, 0.6, 0], 0.15, "Mantle")], margin=0.05)
        return None

    def detail(self, g):
        skin = pebble(0.1, 0.07, 3, 0.1)
        m = {"Basalt": skin, "CorrodedMetal": hammered(0.12, 0.14, 5), "SmoothPlastic": pebble(0.06, 0.05), "Neon": pebble(0.05, 0.05)}
        return lambda mat: m.get(mat, skin)
