import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Slim dark deep-sea drifter fish: pink glow spines, curly tail, big friendly-scary eyes."""
    name = "SpineDrifter"
    iris_color = (0.95, 0.35, 0.5)
    eye_scale = 1.45
    ao_radius = 0.12
    normal_gain = 0.45

    def rounding(self, p): return 0.6
    def k(self, g): return {"Body": 0.22, "Mantle": 0.14, "TailFin": 0.16}.get(g, 0.08)
    def part_k(self, n, kg): return 0.06 if n.startswith("DorsalSpine") else (0.14 if n in ("BellyStripe", "TailStalk") else kg)
    def budget(self, g): return {"Body": 6500, "Mantle": 2600, "TailFin": 1500}.get(g, 800)
    def cells(self, g): return 220 if g == "Body" else 160
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Mantle" else 256)
    def amp(self, g): return 0.014 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")
            hx, hy, hz = b.half

            def post(Q, d):
                # soft ridge of the back and a crease where head meets trunk
                ring = 0.02 * np.exp(-((Q[:, 2] + 1.05) / 0.06) ** 2)
                return d + ring
            ex = [Extra("ellipsoid", [1.35, 1.0, 2.2], [0, -0.28, 0.1], 0.3, "BellyStripe"),   # soft chubby belly
                  Extra("ellipsoid", [1.2, 1.15, 1.6], [0, 0.05, -0.9], 0.3, "Body")]          # shoulders
            return Sculpt(None, post, ex, margin=0.06)
        if g == "Mantle":
            ex = []
            return Sculpt(None, None, ex, margin=0.05)
        return None

    def detail(self, g):
        if g == "Body" or g == "Mantle":
            skin = pebble(0.08, 0.07, 2, 0.1)
            return lambda m: {"Pebble": skin, "Neon": pebble(0.08, 0.06, 4)}.get(m, pebble(0.08, 0.1))
        if g.startswith("SideFin"):
            return lambda m: rays((0, 2), (0.0, -0.4), 11, 0.24)
        if g == "TailFin":
            return lambda m: rays((1, 2), (0.0, -0.45), 14, 0.22)
        return lambda m: pebble(0.07, 0.08)
