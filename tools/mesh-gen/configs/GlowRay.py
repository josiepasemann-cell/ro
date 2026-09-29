"""GlowRay: soft blue manta ray with glowing underside rim, spotted back, wing fins and whip tail."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "GlowRay"
    iris_color = (0.2, 0.4, 0.85)
    ao_radius = 0.1
    eye_inset = 0.0
    eye_gaze_forward = True
    eye_gaze = (0.0, 0.6, -1.0)          # thin flat body: look forward and up so the pupils show from above
    wobble = 0.004
    blend_tau = 0.025
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|GlowRim|Spot|GillSlit"

    def k(self, g): return 0.16 if g == "Body" else 0.1
    def part_k(self, n, kg): return 0.22 if n in ("BackDome",) else kg
    def budget(self, g): return {"Body": 6000, "SideFin1": 900, "SideFin2": 900, "TailTip": 600}.get(g, 600)
    def cells(self, g): return 230 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else 256
    def amp(self, g): return 0.006

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            RAY = rgb(120, 150, 255)
            ex = []
            ex += [sock(ctx, f"Eye{i}", "Body", RAY) for i in (1, 2)]
            ex.append(Tint("ellipsoid", [0.5, 0.2, 0.9], [0, 0.0, 1.35], 0.2, RAY))                                  # tail root

            def post(Q, d):
                # snout ridge line and two nostril dimples
                m = Extra("ellipsoid", [0.5, 0.05, 0.26], [0, -0.06, -1.33], 0, "Body")._sh(Q)
                return S.smax(d, -m, 0.02)
            return Sculpt(None, post, ex, margin=0.12)
        return None

    def paint(self, g, field):
        GLOW = rgb(140, 225, 255)
        if g == "Body":
            spots_c = [(0.55, 0.55), (-0.55, 0.55), (0.45, -0.35), (-0.45, -0.35), (0.0, 0.95), (0.9, 0.15), (-0.9, 0.15), (0.0, 0.3)]

            def spots_fn(Q):
                d = np.full(len(Q), 9.0, np.float32)
                for (x, z) in spots_c:
                    dd = np.hypot(Q[:, 0] - x, Q[:, 2] - z) - 0.085
                    d = np.minimum(d, np.where(Q[:, 1] > 0.05, dd, 9.0))
                return d
            rim = lambda Q: np.where(Q[:, 1] < -0.12, (np.hypot(Q[:, 0] / 1.42, Q[:, 2] / 1.28) - 0.98) * 1.2, 1.0)
            slit = lambda Q: np.where(Q[:, 1] < -0.1, np.hypot(Q[:, 0] * 1.0, (Q[:, 2] - 0.3) * 0.28) - 0.0, 9.0)
            gills = []
            for i in range(5):
                x = -0.7 + i * 0.35
                gills.append((x, 0.85))
            gfn = lambda Q: np.min(np.stack([np.where(Q[:, 1] < -0.1, np.maximum(np.abs(Q[:, 0] - x) - 0.045, np.abs(Q[:, 2] + z) - 0.16), 9.0) for x, z in gills]), 0)
            return [Paint(rim, GLOW, True, 0.85), Paint(spots_fn, GLOW, True, 1.0), Paint(gfn, rgb(60, 65, 110), False, 0.9)]
        if g.startswith("SideFin") and g.endswith("Tip"):
            return []
        return []

    def detail(self, g):
        if g == "Body":
            return lambda m: {"SmoothPlastic": pebble(0.09, 0.05, 2, 0.05), "Neon": pebble(0.1, 0.03, 4, 0)}.get(m)
        if g.startswith("SideFin"):
            return lambda m: {"SmoothPlastic": rays((0, 2), (0.0, 0.6), 14, 0.14), "Neon": rays((0, 2), (0.0, 0.6), 14, 0.14)}.get(m)
        return lambda m: pebble(0.06, 0.05, 3, 0.05) if m == "SmoothPlastic" else None
