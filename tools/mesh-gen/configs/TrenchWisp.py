import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "TrenchWisp"
    eye_inset = 0.2
    extra_roots = r"^GlowCore$"
    iris_color = (0.08, 0.28, 0.28)
    ao_radius = 0.1
    belly = 0.5
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil"

    def is_decal(self, p):
        # floating sparkles + the huge translucent aura are ambient effects, not body geometry: keep them as untouched parts
        if p.name.startswith("GlimmerSpeck") or p.name == "GlimmerAura":
            p.hidden = True
            return False
        return super().is_decal(p)

    def k(self, g): return 0.2 if g == "Body" else 0.08
    def budget(self, g):
        return {"Body": 4500, "GlowCore": 500}.get(g, 400)
    def cells(self, g): return 200 if g == "Body" else 120
    def tex(self, g): return 512 if g == "Body" else 128
    def amp(self, g): return 0.006

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = [socket(ctx, f"Eye{i}", "Body", "Body", 0.06, 1.2) for i in (1, 2)]
            for sx in (-1, 1):   # chubby cheeks
                ex.append(Extra("ellipsoid", [0.34, 0.24, 0.3], [sx * 0.5, -0.12, -0.52], 0.1, "Body"))
            return Sculpt(None, None, ex, margin=0.08)
        if g.startswith("Tip") or g.startswith("Tentacle"):
            return Sculpt(None, None, [capsule(ctx, g, 0.18, 0.02, 0.9)], margin=0.02)
        return None

    def detail(self, g):
        return lambda m: {"Glass": pebble(0.14, 0.03, 2), "Neon": pebble(0.08, 0.05), "SmoothPlastic": pebble(0.06, 0.05)}.get(m)
