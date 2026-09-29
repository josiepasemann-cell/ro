import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

WOOD = (0.47, 0.31, 0.18)
DWOOD = (0.36, 0.23, 0.13)
GOLD = (1.0, 0.8, 0.28)
GOLD2 = (1.0, 0.9, 0.5)


def planks(P):
    """Wood planks running along the chest length (horizontal grooves + grain)."""
    y = P[:, 1] / 0.26
    g = np.abs(np.sin(y * np.pi)) ** 0.5
    n = 0.5 + 0.5 * S.vnoise(np.stack([P[:, 0] * 5, P[:, 1] * 40, P[:, 2] * 5], -1), 3)
    return 0.6 * g + 0.4 * n, 1 + 0.16 * (g - 0.7) + 0.06 * (n - 0.5), 0.15 * (1 - g)


class Config(Cfg):
    """Sunken treasure chest with domed lid, gold bands, lock and studs.  Transparent OuterShell stays a Roblox part.
    (Nothing in src/ animates a lid, so it is not split out.)"""
    name = "SunkenChest"
    keep_re = r"^OuterShell$"
    ao_radius = 0.1
    wobble = 0.003
    belly = 0.3
    blend_tau = 0.02

    def k(self, g): return 0.06
    def part_k(self, n, kg): return 0.03
    def rounding(self, p): return 0.3 if p.kind == "box" else 0.5
    def budget(self, g): return 4200
    def cells(self, g): return 190
    def tex(self, g): return 1024
    def amp(self, g): return 0.012

    def sculpt(self, g, ctx, dim):
        ex = []
        # domed lid (barrel half along X) sitting on the case
        ex.append(CExtra("cylx", [1.92, 0.95, 1.38], [0, 0.4, 0], 0.08, DWOOD, "Wood", 0.6))
        # gold bands wrapping case + lid
        for sx in (-0.58, 0.58):
            ex.append(CExtra("box", [0.2, 1.45, 1.46], [sx, 0.06, 0], 0.04, GOLD, "SmoothPlastic", 0.35))
            ex.append(CExtra("cylx", [0.2, 0.98, 1.42], [sx, 0.4, 0], 0.04, GOLD, "SmoothPlastic", 0.6))
        # front (-Z) lock plate with keyhole, corner studs on the case
        ex.append(CExtra("box", [0.42, 0.5, 0.16], [0, 0.42, -0.72], 0.03, GOLD2, "SmoothPlastic", 0.4))
        ex.append(CExtra("ellipsoid", [0.12, 0.2, 0.1], [0, 0.4, -0.82], 0.02, (0.2, 0.12, 0.06), "SmoothPlastic", 0.5))
        for sx in (-0.9, 0.9):
            for sz in (-0.63, 0.63):
                ex.append(CExtra("ellipsoid", [0.2, 0.2, 0.2], [sx, -0.55, sz], 0.05, GOLD, "SmoothPlastic"))
        # glowing treasure light leaking from the seam between case and lid
        ex.append(CExtra("box", [1.5, 0.05, 0.05], [0, 0.22, -0.7], 0.02, (1.0, 0.85, 0.4), "Neon", 0.3))
        return Sculpt(None, None, ex, margin=0.06)

    def detail(self, g):
        return lambda m: {"Wood": planks, "SmoothPlastic": pebble(0.09, 0.025, 2), "Metal": pebble(0.09, 0.025, 6), "Neon": pebble(0.1, 0.03)}.get(m)
