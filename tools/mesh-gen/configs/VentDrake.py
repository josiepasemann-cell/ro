import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "VentDrake"
    eye_inset = -0.1
    iris_color = (1.0, 0.45, 0.08)
    ao_radius = 0.12
    belly = 1.2

    def rounding(self, p): return 0.55
    def k(self, g): return 0.3 if g == "Body" else 0.08
    def part_k(self, n, kg):
        return {"Snout": 0.3, "SnoutTip": 0.16}.get(n, kg)
    def budget(self, g):
        if g == "Body": return 8500
        if g.startswith("Wing"): return 1300 if "Tip" not in g else 600
        return 500
    def cells(self, g): return 230 if g == "Body" else 140
    def tex(self, g): return 768 if g == "Body" else (512 if g in ("Wing1", "Wing2") else 256)
    def amp(self, g): return 0.02 if g == "Body" else 0.012

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            st = ctx.shape("SnoutTip"); sn = ctx.shape("Snout")
            ex = [socket(ctx, f"EyeWhite{i}", "Body", "Body", 0.06, 1.2) for i in (1, 2)]
            # brow ridges over the eyes, cheek/jaw plates and a chin
            for i in (1, 2):
                e = ctx.shape(f"EyeWhite{i}").c
                ex.append(Extra("ellipsoid", [0.62, 0.22, 0.5], e + [0, 0.24, 0.02], 0.1, "Snout"))
            ex.append(Extra("ellipsoid", [0.6, 0.3, 0.8], sn.c + [0, -0.3, 0.1], 0.14, "BodySegment2"))
            # small horn bases so the separate horn meshes sit in the head
            for i in (1, 2, 3):
                h = ctx.shape(f"Horn{i}")
                ex.append(Extra("ellipsoid", [0.42, 0.3, 0.42], h.c + [0, -0.22, 0], 0.12, "Snout"))
            ex.append(Extra("ellipsoid", [0.4, 0.3, 0.55], st.c + [0, -0.12, 0.2], 0.1, "SnoutTip"))
            mouth = [Cut([0.62, 0.06, 0.62], st.c + [0, -0.12, -0.02]),
                     Cut([0.26, 0.06, 0.5], sn.c + [0, -0.22, -0.5])]
            nost = [Cut([0.09, 0.09, 0.14], st.c + [sx * 0.11, 0.1, -0.2]) for sx in (-1, 1)]
            zs = [-2.2, -1.1, 0.0, 1.1, 2.2]

            def post(Q, d):
                zm = (Q[:, 2] + 1.65) / 1.1                    # creases between the body segments
                gr = np.exp(-((zm - np.round(zm)) / 0.07) ** 2) * (np.abs(Q[:, 2]) < 2.7)
                gr = gr * (Q[:, 2] > -2.7)
                d = d + 0.03 * gr
                return cut(Q, d, mouth + nost, 0.025)
            return Sculpt(None, post, ex, margin=0.1)
        if g in ("Wing1", "Wing2"):
            s = ctx.shape(g); h = s.half
            notch = [Cut([0.22, 0.6, 0.26], s.c + [(-1 if g == "Wing1" else 1) * (i - 1) * 0.42 * 0 + (i - 1) * 0.42, 0, h[2] * 0.98]) for i in range(3)]
            ex = [Extra("ellipsoid", [h[0] * 0.5, 0.2, h[2] * 0.55], s.c + [(-1 if g == "Wing1" else 1) * -0.35, 0.02, 0.05], 0.12, g)]
            return Sculpt(None, lambda Q, d: cut(Q, d, notch, 0.05), ex, margin=0.05)
        if g.startswith("SpineSpike"):
            return Sculpt(None, None, [capsule(ctx, g, 0.0, 0.3, 1.1)], margin=0.02)
        return None

    def detail(self, g):
        if g == "Body":
            sc = scales(0.62, 0.13, contrast=0.24)
            return lambda m: {"SmoothPlastic": sc, "Neon": None}.get(m)
        if g.startswith("Wing"):
            cx = 0.0
            r = rays((0, 2), (0.6 if g == "Wing1" else -0.6, 0.5), 9, 0.2)
            return lambda m: r
        return lambda m: pebble(0.07, 0.08, 3)
