import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "CrystalLeviathan"
    iris_color = (0.3, 0.75, 1.0)
    iris_ratio = 1.0          # no coloured iris ring: plain black pupil on white
    ao_radius = 0.09
    wobble = 0.003
    eye_inset = 0.1
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil"

    def k(self, g): return 0.1 if g == "Body" else 0.08
    def part_k(self, n, kg):
        if n.startswith("HeadTooth"): return 0.02
        return {"CoreGem": 0.05}.get(n, 0.07 if n.startswith("Crown") else kg)
    def budget(self, g):
        if g == "Body": return 10000
        if g.startswith("SideFin") and not g.endswith("Tip"): return 900
        return 400
    def cells(self, g): return 250 if g == "Body" else 110
    def tex(self, g): return 768 if g == "Body" else (128 if g.startswith("SideFin") and not g.endswith("Tip") else 64)
    def amp(self, g): return 0.016
    def rounding(self, p):
        return 0.25 if p.name.startswith(("Facet", "Crown", "SpineSpike")) else 0.5

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body").c
            ex = []                                # no sockets: they swallow the big front-facing eyes
            for eye, side in (("Eye1", 1.0), ("Eye2", -1.0)):   # angry brow ridges slanting down toward the snout
                e = ctx.shape(eye)
                ang = np.radians(28) * side
                Rz = np.array([[np.cos(ang), -np.sin(ang), 0], [np.sin(ang), np.cos(ang), 0], [0, 0, 1]])
                ex.append(Extra("ellipsoid", [1.05, 0.34, 0.7], e.c + [0.04 * side, 0.36, 0.02], 0.08, "Body", R=Rz))
            crowns = [ctx.shape(f"Crown{i}") for i in (1, 5)]
            teeth = [ctx.shape(f"HeadTooth{i}") for i in range(1, 5)]
            def post(Q, d):
                for s in crowns:                      # crystal crown: pointed shards
                    d = S.smin(d, round_cone(Q, s.c + [0, -0.3, 0], s.c + [0, 0.6, 0.02], 0.18, 0.03), 0.06)
                d = groove(Q, d, b + [0, -0.62, -0.95], [2.2, 0.14, 0.7], curve=0.22, k=0.03)   # wide frowning mouth
                for i, t in enumerate(teeth):         # long pointed fangs hanging from the mouth line (outer pair longest)
                    top = t.c + [0, 0.3, 0.02]            # tooth parts sit on the mouth line (buildscript), so they colour the fang
                    ln = 0.62 if i in (0, 3) else 0.42
                    d = S.smin(d, round_cone(Q, top, top + [0, -ln, -0.08], 0.12, 0.015), 0.02)
                return d
            return Sculpt(None, post, ex, margin=0.2)
        if g.startswith(("SpineSpike", "Facet")):     # wedge blocks -> clean pointed crystal shards along the back
            h = ctx.shape(g).half
            r = float(min(h[0], h[2])) * (0.8 if g.startswith("Facet") else 1.1)
            tip = float(h[1]) + (0.45 if g.startswith("Facet") else 0.25)
            extra = [(ctx.shape(f"Crown{i}"), 0.85 if i == 3 else 0.6) for i in (2, 3, 4)] if g == "Facet1" else []
            Ainv_c = ctx.shape(g).c
            def post(Q, d, r=r, tip=tip, extra=extra, c=Ainv_c, g=g, h=h):
                up = -1.0 if g.startswith("SpineSpike") else 1.0   # spikes are built rolled 180 deg: their local +Y points down
                d = round_cone(Q, c + [0, -up * float(h[1]), 0], c + [0, up * tip, 0], r, 0.02)
                for s_, hh in extra:                  # Facet1 also swallowed Crown2-4 (attach rule): crown shards
                    d = S.smin(d, round_cone(Q, s_.c + [0, -0.3, 0], s_.c + [0, hh, 0.02], 0.18, 0.03), 0.06)
                return d
            return Sculpt(None, post, [], margin=0.5)
        return None

    def detail(self, g):
        if g == "Body":
            plate = mix(pebble(0.16, 0.12, 2), bands(2, 0.98, 0.07))
            return lambda m: {"SmoothPlastic": plate, "Neon": pebble(0.1, 0.03), "Glass": pebble(0.2, 0.12, 5)}.get(m)
        if g.startswith("SideFin"):
            return lambda m: rays((1, 2), (0.0, -0.9), 12, 0.18) if m == "Glass" else None
        return lambda m: {"Glass": pebble(0.2, 0.12, 5), "Neon": pebble(0.1, 0.03)}.get(m)
