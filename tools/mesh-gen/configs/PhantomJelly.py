import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "PhantomJelly"
    eye_inset = 0.3
    extra_roots = r"^GlowCore$"
    iris_color = (0.3, 0.35, 0.6)
    ao_radius = 0.12
    belly = 0.0
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil"

    def k(self, g): return 0.2 if g == "Body" else 0.08
    def budget(self, g):
        if g == "Body": return 5500
        if g == "GlowCore": return 700
        return 500
    def cells(self, g): return 210 if g == "Body" else 120
    def tex(self, g): return 640 if g == "Body" else (256 if g == "GlowCore" else 128)
    def amp(self, g): return 0.012 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")
            r = b.half.min()
            ex = []
            # flared bell skirt: lobes at every tentacle root + a soft skirt ring
            for i in range(1, 6):
                t = ctx.shape(f"Tentacle{i}_Segment1")
                ex.append(Extra("ellipsoid", [0.62, 0.5, 0.62], [t.c[0], -0.86, t.c[2]], 0.16, "Body"))
            for i in range(8):
                a = 2 * np.pi * (i + 0.5) / 8
                ex.append(Extra("ellipsoid", [0.7, 0.32, 0.7], [1.0 * np.sin(a), -0.62, 1.0 * np.cos(a)], 0.16, "Body"))
            for i in (1, 2):
                ex.append(socket(ctx, f"EyeWhite{i}", "Body", "Body", 0.06, 1.2))

            def post(Q, d):
                ang = np.arctan2(Q[:, 0], Q[:, 2])
                up = S.smoothstep(-0.3, 0.6, Q[:, 1] / r)
                rib = 0.5 + 0.5 * np.cos(ang * 10)
                return d + 0.035 * up * (rib - 0.5) * S.smoothstep(0.3, 0.9, np.hypot(Q[:, 0], Q[:, 2]) / r)
            return Sculpt(None, post, ex, margin=0.1)
        if "Segment" in g:
            return Sculpt(None, None, [capsule(ctx, g, 0.25, 0.25, 1.0)], margin=0.02)
        return None

    def detail(self, g):
        if g == "Body":
            return lambda m: {"Glass": combine((pebble(0.16, 0.06, 4), 0.35), (rays((0, 2), (0.0, 0.0), 10, 1.3), 0.5), (pebble(0.06, 0.04, 1), 0.3)), "SmoothPlastic": pebble(0.07, 0.06),
                              "Neon": None}.get(m)
        return lambda m: {"Glass": pebble(0.1, 0.08, 2), "Neon": pebble(0.1, 0.05)}.get(m)
