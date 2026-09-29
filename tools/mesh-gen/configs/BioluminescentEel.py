import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "BioluminescentEel"
    iris_color = (0.35, 0.85, 1.0)
    iris_ratio = 2.2
    ao_radius = 0.12
    wobble = 0.004
    eye_inset = 0.8
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|GlowStripe"

    def k(self, g): return 0.09 if g == "Body" else 0.06
    def part_k(self, n, kg): return {"HeadTop": 0.25, "Throat": 0.25, "Jaw": 0.12}.get(n, 0.07 if n.startswith("Segment") else kg)
    def budget(self, g): return 8000 if g == "Body" else 350
    def cells(self, g): return 250 if g == "Body" else 100
    def tex(self, g): return 768 if g == "Body" else (64 if g == "TailTip" else 128)
    def amp(self, g): return 0.014
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        ex = [socket(ctx, "Eye1", "Body", "HeadTop", 0.1, 1.2), socket(ctx, "Eye2", "Body", "HeadTop", 0.1, 1.2)]
        b = ctx.shape("Body").c
        for sx in (-1, 1):
            ex.append(Extra("ellipsoid", [0.42, 0.32, 0.5], b + [sx * 0.45, -0.12, -0.55], 0.1, "Throat"))   # cheeks
        jw = ctx.shape("Jaw")
        def post(Q, d):
            return groove(Q, d, jw.c + [0, 0.13, -0.15], [0.6, 0.04, 0.35], 0.35, 0.02)
        return Sculpt(None, post, ex, margin=0.05)

    def detail(self, g):
        # fine eel scales along the body axis + glowing spots
        skin = mix(pebble(0.08, 0.09, 6), spots(0.16, 0.12, 0.3, 8))
        return lambda m: {"SmoothPlastic": skin, "Neon": pebble(0.05, 0.02)}.get(m)
