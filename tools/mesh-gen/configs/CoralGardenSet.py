import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

# cluster centres relative to Base centre, colour of the neon fronds
CLUSTERS = [((-1.6, 0.0, -1.2), (1.0, 0.35, 0.78)), ((1.5, 0.0, -0.6), (0.35, 0.86, 1.0)), ((0.0, 0.0, 1.7), (0.67, 1.0, 0.35))]


def sand(P):
    n = S.vnoise(P * np.array([6.0, 12.0, 6.0]), 5)
    rip = 0.5 + 0.5 * np.sin(P[:, 0] * 9 + P[:, 2] * 5 + 2.0 * n)
    return 0.6 * rip + 0.4 * (0.5 + 0.5 * n), 1 + 0.10 * (rip - 0.5), 0.05


class Config(Cfg):
    name = "CoralGardenSet"
    ao_radius = 0.09
    wobble = 0.004
    belly = 0.25
    blend_tau = 0.025

    def k(self, g): return 0.1
    def part_k(self, n, kg): return 0.2 if n.startswith("ClusterBase") else (0.09 if "Frond" in n else 0.05)
    def rounding(self, p): return 0.5
    def budget(self, g): return 6500
    def cells(self, g): return 230
    def tex(self, g): return 768
    def amp(self, g): return 0.014

    def sculpt(self, g, ctx, dim):
        b = ctx.shape("Base"); bc = b.c
        ex = []
        rng = np.random.RandomState(2)
        for (cx, cy, cz), col in CLUSTERS:
            cc = bc + np.array([cx, 0.2, cz])
            lite = tuple(min(1, c + 0.35) for c in col)
            # branching coral tubes leaning outward, each with a bright tip bulb and polyp dots
            for i in range(5):
                a = np.radians(72 * i + 20 * (cx + cz))
                lean = np.array([np.cos(a) * 0.55, 1.0, np.sin(a) * 0.55])
                L = 0.62 + 0.18 * ((i * 7) % 3)
                base = cc + np.array([np.cos(a) * 0.3, 0.0, np.sin(a) * 0.3])
                mid = base + unit(lean) * L * 0.5
                ex.append(CExtra("ellipsoid", [0.26, L, 0.26], mid, 0.1, col, "Neon", 0.5, orient(lean)))
                tip = base + unit(lean) * L
                ex.append(CExtra("ellipsoid", [0.26, 0.3, 0.26], tip, 0.08, lite, "Neon"))
            for i in range(6):
                a = np.radians(60 * i + 15)
                ex.append(CExtra("ellipsoid", [0.17, 0.12, 0.17], cc + np.array([np.cos(a) * 0.5, 0.02, np.sin(a) * 0.5]), 0.05, (0.75, 0.68, 0.55), "Slate"))
        # starfish on the sand
        sc = bc + np.array([1.2, 0.2, 1.6])
        for i in range(5):
            a = np.radians(72 * i + 10)
            d = np.array([np.cos(a), 0.0, np.sin(a)])
            ex.append(CExtra("ellipsoid", [0.2, 0.56, 0.1], sc + d * 0.28, 0.06, (1.0, 0.55, 0.25), "SmoothPlastic", 0.5, orient(d)))
        ex.append(CExtra("ellipsoid", [0.36, 0.18, 0.36], sc + [0, 0.01, 0], 0.08, (1.0, 0.62, 0.3), "SmoothPlastic"))
        # spiral shell and small stones
        ex.append(CExtra("ellipsoid", [0.42, 0.3, 0.3], bc + np.array([-0.6, 0.3, 1.6]), 0.05, (0.98, 0.9, 0.82), "SmoothPlastic", 0.5, orient([1, 0.3, 0.2])))
        for i in range(4):
            ex.append(CExtra("ellipsoid", [0.24, 0.16, 0.22], bc + np.array([-2.0 + i * 0.35, 0.22, 0.4 + 0.5 * (i % 2)]), 0.04, (0.75, 0.7, 0.59), "Slate"))

        def post(Q, d):
            r = np.hypot(Q[:, 0] - bc[0], Q[:, 2] - bc[2])
            rim = S.smax(d, r - 2.5, 0.35)                         # round island instead of a square slab
            return rim
        return Sculpt(None, post, ex, margin=0.1)

    def detail(self, g):
        return lambda m: {"Sand": sand, "Pebble": pebble(0.08, 0.14, 3), "Slate": pebble(0.07, 0.1, 8), "SmoothPlastic": pebble(0.05, 0.06, 2), "Neon": pebble(0.06, 0.08, 6)}.get(m)
