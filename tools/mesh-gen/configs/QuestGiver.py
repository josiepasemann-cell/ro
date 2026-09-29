import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


def side(n):
    return -1 if (n.endswith("L") or n.endswith("1")) else 1


class Config(StyledCfg):
    """Captain Finn: mint-green seahorse with a captain's hat, rosy cheeks, neon-green crest, satchel and scroll."""
    name = "QuestGiver"
    iris_color = (0.2, 0.45, 0.35)
    eye_scale = 1.7
    ao_radius = 0.1
    normal_gain = 0.6

    def restyle(self, p):
        n = p.name
        if EYE_RE.match(n):                                    # eyes were buried inside the head -> put them on its surface
            self.sw(p, [side(n) * 0.06, 0.04, -0.35])
        elif n == "Mouth":
            self.sw(p, [0, 0.0, -0.14])
        elif n.startswith("Blush"):
            resize(p, [0.36, 0.36, 0.36]); self.sw(p, [0, 0, -0.1])
        elif n == "CaptainHat":
            self.sw(p, [0, -0.1, 0])
        elif n == "HatBadge":
            resize(p, [0.34, 0.34, 0.34]); self.sw(p, [0, -0.1, -0.02])
        elif n == "SnoutCrest":
            self.sw(p, [0, 0.1, 0])

    def rounding(self, p): return {"Satchel": 0.3, "ScrollTip": 0.6}.get(p.name, 0.6)
    def k(self, g): return {"Body": 0.2, "Head": 0.14}.get(g, 0.1)
    def part_k(self, n, kg):
        return {"HatBadge": 0.03, "HatTrim": 0.03, "Mouth": 0.02, "Satchel": 0.06, "SatchelStrap": 0.05, "ScrollTip": 0.04,
                "BellyPlate1": 0.1, "BellyPlate2": 0.1, "BellyPlate3": 0.1, "BellyPlate4": 0.1, "HatBrim": 0.08}.get(n, kg)
    def budget(self, g):
        return {"Body": 6500, "Head": 2800, "ArmL": 700, "ArmR": 700, "DorsalFin": 600, "DorsalFinTip": 400}.get(g, 700)
    def cells(self, g): return 230 if g == "Body" else 160
    def tex(self, g): return 512 if g == "Body" else (512 if g == "Head" else (256 if g.startswith("Arm") else 128))
    def amp(self, g): return 0.009 if g == "Body" else 0.006

    def sculpt(self, g, ctx, dim):
        if g == "Head":
            ex = [cheek(ctx, f"Blush{s}", "Head", "Head", 0.12, 1.5, 0.5) for s in ("L", "R")]
            ex.append(Extra("ellipsoid", [0.7, 0.5, 0.6], [0, -0.1, -0.7], 0.12, "Head"))                 # soft snout tip
            return Sculpt(None, None, ex, margin=0.05)
        if g == "Body":
            ex = [Extra("ellipsoid", [1.7, 1.0, 1.4], [0, -0.45, -0.05], 0.25, "BellyPlate2")]             # tummy
            return Sculpt(None, None, ex, margin=0.06)
        return None

    def detail(self, g):
        skin = pebble(0.07, 0.05, 2, 0.06)
        m = {"SmoothPlastic": skin, "Fabric": weave(0.06, 0.12), "Neon": pebble(0.06, 0.04)}
        return lambda mat: m.get(mat, skin)
