import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Inky the egg keeper: plump lilac-violet squid-keeper, round specs, glowing violet belts, tentacle skirt, guarded egg."""
    name = "EggKeeper"
    iris_color = (0.35, 0.22, 0.55)
    eye_scale = 1.75
    ao_radius = 0.1

    def restyle(self, p):
        if p.name == "Mouth":                                   # was hovering in front of the head, never painted
            self.sw(p, [0, 0.03, 0.22])
            resize(p, [0.62, 0.16, 0.16])
        if p.name == "MantleGlowRing":
            resize(p, [3.42, 0.2, 3.42])
        if p.name == "MantleGlowRing2":
            resize(p, [3.3, 0.3, 3.3])
        if p.name in ("GuardedEgg", "GuardedEggBand"):            # make the guarded egg readable
            resize(p, [1.15, 1.15, 1.15] if p.name == "GuardedEgg" else [1.22, 0.2, 1.22])
            self.sw(p, [0, -0.02, -0.18])
        if p.name in ("ArmL", "ArmR"):                          # fuse arm + tip into one limb (tip used to sit loose in the body mesh)
            resize(p, [0.62, 2.4, 0.62])
            shift(p, [0, -0.55, 0])

    def rounding(self, p): return 0.6
    def k(self, g): return {"Body": 0.22, "Head": 0.16}.get(g, 0.1)
    def part_k(self, n, kg):
        return {"MantleGlowRing": 0.08, "MantleGlowRing2": 0.08, "GuardedEggBand": 0.02, "Mouth": 0.02,
                "GuardedEgg": 0.05, "SpecsBridge": 0.03}.get(n, kg)
    def budget(self, g):
        return {"Body": 6500, "Head": 2600, "ArmL": 1300, "ArmR": 1300}.get(g, 650 if g.startswith("Tentacle") else 800)
    def cells(self, g): return 230 if g == "Body" else 160
    def tex(self, g):
        return 512 if g == "Body" else (512 if g == "Head" else (256 if g in ("ArmL", "ArmR") else 128))
    def amp(self, g): return 0.02 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            return None
        if g == "Head":
            h = ctx.shape("Head")
            hc, hh = h.c, h.half
            ex = []
            # round specs: ring of small blobs that follow the head surface around each eye
            for sx in (-1, 1):
                cx, cy = sx * 0.42, 0.02
                for a in np.linspace(0, 2 * np.pi, 14, endpoint=False):
                    x, y = cx + 0.37 * np.cos(a), cy + 0.37 * np.sin(a)
                    zz = -hh[2] * np.sqrt(max(0.06, 1 - (x / hh[0]) ** 2 - (y / hh[1]) ** 2)) - 0.02
                    ex.append(Extra("ellipsoid", [0.13, 0.13, 0.13], hc + np.array([x, y, zz]), 0.05, "SpecsBridge"))
            # forehead dome + chubby cheeks
            ex.append(Extra("ellipsoid", [1.5, 0.7, 1.2], [0, 0.28, -0.1], 0.2, "Head"))
            ex += [Extra("ellipsoid", [0.6, 0.45, 0.5], [sx * 0.55, -0.24, -0.5], 0.14, "Head") for sx in (-1, 1)]
            return Sculpt(None, None, ex, margin=0.06)
        return None

    def detail(self, g):
        marble = soft_marble(0.6, 0.1)
        m = {"Marble": marble, "SmoothPlastic": pebble(0.1, 0.05, 3, 0.08), "Neon": pebble(0.07, 0.04, 2), "Foil": None}
        return lambda mat: m.get(mat, pebble(0.08, 0.05)) if mat != "Foil" else None
