import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

GOLD = (1.0, 0.84, 0.35)
GOLD2 = (0.9, 0.7, 0.2)
GEMS = [(0.95, 0.15, 0.25), (0.2, 0.5, 1.0), (0.2, 0.95, 0.55), (0.75, 0.3, 1.0), (1.0, 0.55, 0.85), (0.3, 0.9, 1.0)]


def sand(P):
    n = S.vnoise(P * np.array([6.0, 10.0, 6.0]), 5)
    return 0.5 + 0.5 * n, 1 + 0.08 * n, 0.05


def planks(P):
    y = P[:, 1] / 0.22
    g = np.abs(np.sin(y * np.pi)) ** 0.5
    return g, 1 + 0.14 * (g - 0.7), 0.1 * (1 - g)


def coins(P):
    r = np.hypot(P[:, 0] * 0 + P[:, 1] * 0, P[:, 2] * 0)  # placeholder (kept flat: coins get their relief from geometry)
    n = 0.5 + 0.5 * S.vnoise(P * 9, 2)
    return n, 1 + 0.08 * (n - 0.5), 0.05


class Config(Cfg):
    name = "TreasurePile"
    ao_radius = 0.09
    wobble = 0.003
    belly = 0.2
    blend_tau = 0.02

    def k(self, g): return 0.1
    def part_k(self, n, kg):
        if n.startswith(("Sparkle", "Jewel")): return 0.04
        if n.startswith("Coin"): return 0.03
        if n == "Base": return 0.2
        return 0.06
    def rounding(self, p): return 0.35 if p.kind in ("box", "cylx") else 0.5
    def budget(self, g): return 7500
    def cells(self, g): return 240
    def tex(self, g): return 1024
    def amp(self, g): return 0.014

    def sculpt(self, g, ctx, dim):
        ex = []
        rng = np.random.RandomState(12)
        # heap of loose coins spilling in front of / around the chest (flat discs, random tilt)
        spots = [(-0.6, -1.0), (0.1, -1.25), (-1.3, -1.0), (0.7, -0.3), (1.0, 0.7), (0.2, 1.1), (-1.3, 1.0), (-0.3, 1.3), (1.6, 0.0),
                 (0.5, -0.8), (-0.9, -1.3), (1.4, -0.7), (-2.0, 0.2), (0.9, 1.4)]
        for i, (x, z) in enumerate(spots):
            tilt = np.array([rng.uniform(-0.6, 0.6), 1.0, rng.uniform(-0.6, 0.6)])
            ex.append(CExtra("cyly", [0.6, 0.15, 0.6], [x, 0.53 + 0.05 * (i % 3), z], 0.03, GOLD if i % 3 else GOLD2, "Foil", 0.5, orient(tilt)))
        # gems
        for i, col in enumerate(GEMS):
            a = np.radians(60 * i + 25); r_ = 1.35 + 0.35 * (i % 2)
            ex.append(CExtra("ellipsoid", [0.36, 0.42, 0.36], [np.cos(a) * r_ * 1.1 + 0.3, 0.62, np.sin(a) * r_ * 0.9], 0.04, col, "Glass", 0.5, orient([0.3 * (-1) ** i, 1, 0.2])))
        # two gold bars
        R = orient([0, 1, 0])
        ex.append(CExtra("box", [0.85, 0.28, 0.4], [1.2, 0.62, -1.4], 0.03, GOLD2, "Foil", 0.3))
        ex.append(CExtra("box", [0.85, 0.28, 0.4], [1.25, 0.9, -1.4], 0.03, GOLD, "Foil", 0.3))
        # lid hinge/latch so the propped lid is attached to the chest
        ex.append(CExtra("cylx", [1.9, 0.22, 0.22], [-0.6, 1.3, -0.72], 0.05, GOLD2, "Foil", 0.5))
        return Sculpt(None, None, ex, margin=0.1)

    def detail(self, g):
        return lambda m: {"Sand": sand, "WoodPlanks": planks, "Foil": coins, "Metal": pebble(0.05, 0.05, 6), "Neon": pebble(0.1, 0.03)}.get(m)
