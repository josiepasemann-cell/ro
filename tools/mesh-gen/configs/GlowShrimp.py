"""GlowShrimp: chubby peach shrimp, segmented back, glowing spots and tail fan."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "GlowShrimp"
    iris_color = (0.3, 0.15, 0.05)
    ao_radius = 0.09
    eye_inset = -0.1
    wobble = 0.004
    blend_tau = 0.03
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|GlowSpot"
    tex_small = 128

    def k(self, g): return 0.16 if g == "Body" else 0.06
    def part_k(self, n, kg): return 0.1 if n == "Belly" else (0.12 if n == "Rostrum" else kg)
    def budget(self, g): return {"Body": 6000, "TailFin": 700, "TailFin1": 700, "TailFin3": 700}.get(g, 500)
    def cells(self, g): return 220 if g == "Body" else 110
    def tex(self, g): return 1024 if g == "Body" else (256 if g.startswith("TailFin") else 128)
    def amp(self, g): return 0.004 if g == "Body" else 0.004

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        SHELL, DARK, BELLY = rgb(255, 200, 150), rgb(215, 150, 105), rgb(255, 228, 200)
        ex = [Tint("ellipsoid", [0.42, 0.36, 0.42], [s * 0.34, -0.08, -0.92], 0.14, SHELL) for s in (-1, 1)]     # cheeks
        ex += [sock(ctx, f"Eye{i}", "HeadSegment", SHELL) for i in (1, 2)]
        for i in range(-1, 2):                                                                                      # tiny tail-side swimmerets bumps
            pass

        def post(Q, d):
            z = Q[:, 2]
            band = 0.5 + 0.5 * np.cos((z - 0.05) / 0.36 * 2 * np.pi)          # segment bands along the back
            dorsal = S.smoothstep(-0.25, 0.3, Q[:, 1]) * S.smoothstep(-0.55, -0.2, z)
            tailseg = S.smoothstep(0.1, 0.45, z)
            groove = 0.013 * (1 - band) ** 2 * (0.35 + 0.65 * dorsal * 0 + 0.65 * S.smoothstep(-0.9, 0.5, -Q[:, 1]) * 0 + 0.65 * tailseg + 0.35 * (S.smoothstep(-0.3, 0.6, Q[:, 1])))
            lip = Extra("ellipsoid", [0.32, 0.05, 0.16], [0, -0.22, -1.12], 0, "Body")._sh(Q)
            return S.smax(d + groove, -lip, 0.02)
        return Sculpt(None, post, ex, margin=0.15)

    def paint(self, g, field):
        if g != "Body":
            return []
        GLOW = rgb(255, 150, 220)
        zs = [-0.75, -0.3, 0.02, 0.72, 1.2]

        def spots_fn(Q):
            d = np.full(len(Q), 9.0, np.float32)
            for i, z in enumerate(zs):
                r = 0.10 if i < 4 else 0.08
                d = np.minimum(d, np.where(Q[:, 1] > 0.0, np.hypot(Q[:, 0], Q[:, 2] - z) - r, 9.0))
            return d
        bands = lambda Q: np.where(Q[:, 1] > -0.1, 0.3 * (0.5 - 0.5 * np.cos((Q[:, 2] - 0.05) / 0.36 * 2 * np.pi)) * 2 - 0.3 + 0.3 * 0 - 0.15, 1.0)
        return [Paint(spots_fn, GLOW, True, 1.0), Paint(bands, rgb(225, 150, 110), False, 0.5)]

    def detail(self, g):
        if g == "Body":
            return lambda m: {"Pebble": pebble(0.1, 0.04, 2, 0.06), "SmoothPlastic": pebble(0.1, 0.04, 3, 0.05)}.get(m)
        return lambda m: {"Neon": rays((0, 2), (0.0, -0.3), 14, 0.14), "SmoothPlastic": pebble(0.05, 0.05, 3, 0.05)}.get(m)
