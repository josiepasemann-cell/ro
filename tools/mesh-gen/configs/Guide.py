import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Bubbles the guide: glassy jellyfish bell with a glowing core, cute face bump, cyan arms + lantern, frilly tentacles."""
    name = "Guide"
    iris_color = (0.1, 0.55, 0.6)
    eye_scale = 2.2
    ao_radius = 0.1
    extra_roots = r"^GlowCore$"                 # keep the glowing core as its own mesh, visible through the glass bell
    LIFT = 0.3

    def restyle(self, p):
        n = p.name
        if n == "Body":
            p.kind = "ellipsoid"; resize(p, [3.4, 2.3, 3.4])
        elif n == "GlowCore":
            resize(p, [1.15, 1.15, 1.15])
        elif n == "Head":
            resize(p, [1.3, 1.3, 1.3]); self.sw(p, [0, 0.1, -0.4])
        elif re.match(r"^Eye[12]", n):
            self.sw(p, [0, 0.05, -0.39])
        elif n == "Mouth":
            self.sw(p, [0, 0.0, -0.49]); resize(p, [0.42, 0.11, 0.14])
        elif n in ("ArmL", "ArmR"):
            L = 3.05 if n == "ArmL" else 3.85           # fuse arm + tip (+ lantern on the right) into one limb
            resize(p, [0.62, L, 0.62]); shift(p, [0, 0.8 - L / 2, 0]); self.sw(p, [0, self.LIFT, 0])
        elif n.startswith(("Lantern", "Tentacle", "ArmLTip", "ArmRTip")):
            self.sw(p, [0, self.LIFT, 0])

    def rounding(self, p): return 0.6
    def k(self, g): return {"Body": 0.2, "Head": 0.14}.get(g, 0.1)
    def part_k(self, n, kg): return {"LanternHandle": 0.04, "LanternGlow": 0.05, "Lantern": 0.06}.get(n, kg)
    def budget(self, g):
        return {"Body": 5000, "Head": 2200, "ArmL": 1400, "ArmR": 1800, "GlowCore": 900}.get(g, 650)
    def cells(self, g): return 220 if g == "Body" else 150
    def tex(self, g):
        return 512 if g == "Body" else (256 if g == "Head" else (256 if g in ("ArmL", "ArmR", "GlowCore") else 128))
    def amp(self, g): return 0.012

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")

            def post(Q, d):
                q = Q - b.c
                ang = np.arctan2(q[:, 0], q[:, 2])
                low = S.smoothstep(0.45, -0.75, q[:, 1])
                ridge = 0.5 + 0.5 * np.cos(ang * 12)
                return d - 0.055 * low * ridge * ridge               # scalloped frilly bell edge
            ex = [Extra("ellipsoid", [3.0, 0.5, 3.0], [0, -0.85, 0], 0.22, "Body")]
            return Sculpt(None, post, ex, margin=0.08)
        if g == "Head":
            return Sculpt(None, None, [Extra("ellipsoid", [0.5, 0.4, 0.4], [sx * 0.42, -0.2, -0.28], 0.1, "Head") for sx in (-1, 1)], margin=0.04)
        return None

    def detail(self, g):
        bubble = None
        m = {"Neon": pebble(0.1, 0.03, 2), "SmoothPlastic": pebble(0.09, 0.06, 4, 0.1), "Foil": pebble(0.05, 0.03)}
        return lambda mat: m.get(mat)
