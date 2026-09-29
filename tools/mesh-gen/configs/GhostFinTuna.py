"""GhostFinTuna: torpedo-shaped pale tuna, tapered tail stalk, translucent fan fins, big eyes."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "GhostFinTuna"
    iris_color = (0.3, 0.55, 0.8)
    ao_radius = 0.12
    eye_inset = -0.1
    wobble = 0.004
    blend_tau = 0.035
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|GillLine|BackStripe"   # stripe -> Tint below (it would steal the dorsal fin group)

    def k(self, g): return 0.2 if g == "Body" else 0.08
    def part_k(self, n, kg): return 0.12 if n in ("Belly", "TailPeduncle") else kg
    def budget(self, g): return {"Body": 6500, "Nose": 900, "DorsalFin": 600}.get(g, 700)
    def cells(self, g): return 240 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Nose" else 256)
    def amp(self, g): return 0.006 if g == "Body" else 0.006

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")
            hx, hy, hz = b.half
            DARK, LIGHT = rgb(150, 175, 200), rgb(230, 240, 250)

            def pre(P):                        # tuna: slim tail stalk, slight upward sweep at the rear
                Q = P.copy()
                t = S.smoothstep(0.15, 1.05, P[:, 2] / hz)
                s = 1 - 0.42 * t
                Q[:, 0] = P[:, 0] / s
                Q[:, 1] = (P[:, 1] - 0.10 * t * hy) / s
                return Q

            def post(Q, d):
                side = S.smoothstep(0.25, 0.7, np.abs(Q[:, 0]) / hx)
                gil = 0.0
                for zc in (-1.55, -1.72, -1.89):                # gill arches (three soft curved grooves)
                    gil = gil + 0.017 * np.exp(-((Q[:, 2] - zc + 0.25 * (np.abs(Q[:, 1]) / hy) ** 2) / 0.032) ** 2)
                gil = gil * side * S.smoothstep(0.75, 0.0, Q[:, 1] / hy)
                return d + gil

            ex = [Tint("ellipsoid", [1.05, 0.65, 4.4], [0, 0.66, 0.2], 0.25, DARK),          # dark back (was BackStripe)
                  Tint("ellipsoid", [0.9, 0.5, 2.2], [0, -0.5, -0.9], 0.2, LIGHT),           # pale chest
                  Tint("ellipsoid", [0.35, 0.5, 1.0], [0, 0.05, 2.4], 0.3, DARK)]            # stalk keel
            ex += [sock(ctx, f"Eye{i}", "Body", rgb(200, 220, 235)) for i in (1, 2)]
            return Sculpt(pre, post, ex, margin=0.15)
        if g == "Nose":
            n = ctx.shape("Nose")
            hz = n.half[2]

            def post(Q, d):
                lip = Extra("ellipsoid", [0.5, 0.05, 0.3], [0, -0.14, -hz * 0.97], 0, "Nose")._sh(Q)
                return S.smax(d, -lip, 0.02)
            return Sculpt(None, post, [], margin=0.05)
        return None

    def detail(self, g):
        if g in ("Body", "Nose"):
            return lambda m: scales(0.9, 0.16, contrast=0.09, seed=3) if m == "SmoothPlastic" else None
        if g.startswith("DorsalFin"):
            return lambda m: rays((1, 2), (-0.3, 0.0), 12, 0.2) if m == "Glass" else None
        if g.startswith("SideFin"):
            return lambda m: rays((0, 2), (0.0, -0.5), 12, 0.2) if m == "Glass" else None
        return lambda m: rays((1, 2), (0.0, -0.5), 16, 0.2) if m == "Glass" else None


from models import scales  # noqa: E402
