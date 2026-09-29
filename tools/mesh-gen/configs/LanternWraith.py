"""LanternWraith: dark violet ghost-angler with big head, fangs, spine crest, glowing lantern lure."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "LanternWraith"
    iris_color = (0.35, 0.9, 0.5)
    ao_radius = 0.12
    eye_inset = -0.1
    wobble = 0.005
    blend_tau = 0.03
    extra_roots = r"^LureTip$"                                # stalk + tip = one glowing lure mesh
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|Tooth|GhostShimmer|BackStripe"
    tex_small = 256

    def k(self, g): return {"Body": 0.28, "LureTip": 0.1, "LowerJaw": 0.1}.get(g, 0.08)
    def part_k(self, n, kg): return 0.4 if n in ("Head", "TailBase") else kg
    def budget(self, g): return {"Body": 6500, "LureTip": 900, "LowerJaw": 700}.get(g, 700)
    def cells(self, g): return 230 if g == "Body" else 140
    def tex(self, g): return 1024 if g == "Body" else (256 if g in ("LureTip", "LowerJaw") else 256)
    def amp(self, g): return 0.005

    def sculpt(self, g, ctx, dim):
        BODY, LIGHT = rgb(45, 26, 58), rgb(75, 48, 96)
        TOOTH = rgb(235, 232, 240)
        LURE = rgb(180, 255, 210)
        if g == "Body":
            head = ctx.shape("Head")
            hc = head.c

            def pre(P):                          # slim, slightly lifted tail
                Q = P.copy()
                t = S.smoothstep(0.6, 2.6, P[:, 2])
                s = 1 - 0.32 * t
                Q[:, 0] = P[:, 0] / s
                Q[:, 1] = (P[:, 1] - 0.18 * t) / s
                return Q
            ex = [sock(ctx, f"Eye{i}", "Head", BODY) for i in (1, 2)]
            for s in (-1, 1):
                ex.append(Tint("ellipsoid", [0.5, 0.24, 0.4], [s * 0.6, 0.95, -1.5], 0.12, BODY))
                ex.append(Tint("ellipsoid", [0.5, 0.45, 0.5], [s * 0.8, -0.35, -1.3], 0.2, BODY))                   # cheeks
            # upper fangs above the mouth line
            for x in (-0.42, -0.14, 0.14, 0.42):
                z = -1.92 + 0.12 * abs(x) * 2
                ex.append(Cone([x, -0.30, z], [x * 1.05, -0.62, z - 0.03], 0.075, 0.03, TOOTH, "SmoothPlastic", blunt=0.0))
            # dorsal spine crest
            for i, z in enumerate((-0.55, 0.0, 0.55, 1.1, 1.65)):
                h = 0.5 - 0.05 * i
                y0 = 0.72 - 0.02 * i
                ex.append(Cone([0, y0 + 0.05, z], [0, y0 + h, z + 0.28], 0.15 - 0.012 * i, 0.06, LIGHT, "SmoothPlastic"))
            # lure stalk root grows out of the crown
            ex.append(Fn(capsule([0, 0.75, -1.62], [0, 1.05, -1.95], 0.16, 0.11), 0.14, BODY))

            def post(Q, d):
                lip = Extra("ellipsoid", [1.5, 0.06, 0.42], [0, -0.31, -1.96], 0, "Body")._sh(Q)
                return S.smax(d, -lip, 0.02)
            return Sculpt(pre, post, ex, margin=0.15)
        if g == "LowerJaw":
            j = ctx.shape("LowerJaw")
            ex = []
            for x in (-0.36, -0.12, 0.12, 0.36):
                ex.append(Cone([x, 0.05, -0.32], [x, 0.36, -0.32], 0.06, 0.03, TOOTH, "SmoothPlastic"))
            return Sculpt(None, None, ex, margin=0.05)
        if g == "LureTip":
            head = ctx.shape("Head")
            R = head.R
            w2g = lambda v: head.c + R @ np.asarray(v, float)
            s1 = ctx.shape("LureStalk1").c
            ex = [Fn(capsule(w2g([0, 0.5, -0.42]), s1, 0.17, 0.10), 0.1, rgb(180, 255, 210), "Neon", True)]
            return Sculpt(None, None, ex, margin=0.05)
        return None

    def paint(self, g, field):
        if g != "Body":
            return []
        LIGHT = rgb(95, 64, 122)
        top = lambda Q: -(Q[:, 1] - 0.15)
        glow = Paint(dots(0.4, 0.03, 0.06, 7, 0.5, mask=top), rgb(140, 240, 190), True, 0.9)
        belly = Paint(lambda Q: np.where(Q[:, 1] < -0.2, -1.0, 1.0), rgb(85, 58, 110), False, 0.5)
        return [belly, glow]

    def detail(self, g):
        if g == "Body":
            return lambda m: {"SmoothPlastic": pebble(0.2, 0.05, 5, 0.05), "Neon": pebble(0.06, 0.04, 2, 0)}.get(m)
        if g.startswith("SideFin"):
            return lambda m: rays((0, 2), (0.0, -0.4), 12, 0.2) if m == "Glass" else None
        return lambda m: {"SmoothPlastic": rays((1, 2), (0.0, -0.3), 12, 0.16), "Neon": pebble(0.05, 0.03, 2, 0)}.get(m)
