import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cc_common import *


class Config(Cfg):
    name = "VoidHammerhead"
    eye_inset = -0.05
    iris_color = (0.63, 0.24, 1.0)
    ao_radius = 0.14
    blend_tau = 0.012
    belly = 1.1
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|StripeGlow"

    def is_decal(self, p):
        if p.name == "StripeGlow":
            # the stripe is rebuilt as a raised neon ridge on the Body mesh (sculpt extras). Shrink/move this part so it does not
            # get attached to the DorsalFin group and only serves as the colour source of the ridge.
            p.M = p.M.copy(); p.M[2, 3] -= 1.6; p.size = np.array([0.2, 0.2, 0.5])
            return True
        return super().is_decal(p)

    def k(self, g): return 0.3 if g == "Body" else 0.1
    def part_k(self, n, kg): return {"HammerBridge": 0.3, "HammerLobe1": 0.28, "HammerLobe2": 0.28, "TailPeduncle": 0.25}.get(n, kg)
    def budget(self, g):
        if g == "Body": return 9000
        if g.startswith("SideFin") or g.startswith("TailFin") or g.startswith("DorsalFin"): return 900
        return 500
    def cells(self, g): return 230 if g == "Body" else 140
    def tex(self, g): return 768 if g == "Body" else 256
    def amp(self, g): return 0.013 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            names = ["Head", "Body", "TailBase", "BackShade", "HammerLobe1", "HammerLobe2", "HammerBridge", "TailPeduncle"]
            shapes = [ctx.shape(n) for n in names]
            ex = [socket(ctx, f"Eye{i}", "Body", "Body", 0.06, 1.2) for i in (1, 2)]
            # raised glowing stripe following the back line (neon like StripeGlow)
            for z in np.linspace(-2.7, 3.7, 12):
                y = top_y(shapes, 0.0, z)
                if y is None:
                    continue
                ex.append(Extra("ellipsoid", [0.24, 0.3, 0.8], [0, y - 0.06, z], 0.03, "StripeGlow"))
            b = ctx.shape("Body")
            hx = b.half[0]
            gills = [Cut([0.34, 0.5, 0.07], [sx * 0.86, 0.0, -1.4 + 0.3 * i]) for sx in (-1, 1) for i in range(5)]
            grin = [Cut([1.1, 0.08, 0.45], [0, -0.12, -3.85])]

            def post(Q, d):
                return cut(Q, d, gills + grin, 0.03)
            return Sculpt(None, post, ex, margin=0.1)
        if g.startswith("SpineSpike"):
            return None
        return None

    def detail(self, g):
        skin = combine((pebble(0.12, 0.07, 6), 0.5), (pebble(0.05, 0.04, 2), 0.5))
        if g.startswith(("DorsalFin", "SideFin", "TailFin")):
            return lambda m: rays((1, 2), (0.0, -0.4), 12, 0.2)
        return lambda m: {"SmoothPlastic": skin, "Neon": None}.get(m)
