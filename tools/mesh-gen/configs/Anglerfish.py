import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "Anglerfish"
    iris_color = (0.55, 0.25, 0.85)
    iris_ratio = 1.5
    ao_radius = 0.1
    wobble = 0.005
    eye_inset = 0.6

    def k(self, g): return 0.2 if g == "Body" else 0.08
    def part_k(self, n, kg):
        if n.startswith("Tooth"): return 0.02
        return {"Belly": 0.3, "BackShade": 0.25, "UpperJaw": 0.16, "LowerJaw": 0.12, "IlliciumBase": 0.06,
                "IlliciumTipRod": 0.05, "TailPeduncle": 0.25}.get(n, kg)
    def budget(self, g): return {"Body": 7500, "LowerJaw": 1600, "TailFin": 1200}.get(g, 500)
    def cells(self, g): return 230 if g == "Body" else 130
    def tex(self, g): return 768 if g == "Body" else (256 if g == "LowerJaw" else (64 if g == "LureOrb" else 128))
    def amp(self, g): return 0.016
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = [socket(ctx, "Eye1", "Body", "Body", 0.1, 1.2), socket(ctx, "Eye2", "Body", "Body", 0.1, 1.2)]
            b = ctx.shape("Body").c
            ex.append(Extra("ellipsoid", [0.9, 0.5, 0.7], b + [0, 0.98, -0.75], 0.2, "BackShade"))            # lure bump
            for sx in (-1, 1):
                ex.append(Extra("ellipsoid", [0.6, 0.5, 0.6], b + [sx * 0.85, -0.55, -1.0], 0.16, "Belly"))   # chubby cheek
            uj = ctx.shape("UpperJaw")
            def post(Q, d):                                        # mouth line between the jaws
                return groove(Q, d, uj.c + [0, -0.3, -0.5], [1.65, 0.05, 0.6], 0.15, 0.03)
            return Sculpt(None, post, ex, margin=0.08)
        if g == "LowerJaw":
            return Sculpt(None, None, [], margin=0.04)
        return None

    def detail(self, g):
        skin = mix(pebble(0.07, 0.08, 3), spots(0.22, 0.14, 0.45, 5))
        return lambda m: {"SmoothPlastic": skin, "Neon": pebble(0.1, 0.03)}.get(m)
