import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

VIO = (0.53, 0.24, 1.0)
CY = (0.47, 0.98, 1.0)
MET = (0.31, 0.14, 0.59)
GOLD = (1.0, 0.93, 0.55)
PINK = (1.0, 0.6, 0.9)


class Config(EggBase):
    name = "MysteryEgg_Mythic"
    egg_budget = 8800
    egg_tex = 1024
    egg_cells = 240
    ribs = 10
    rib_amp = 0.13
    facet_amp = 0.0
    facet_size = 0.45
    belly = 0.25
    iris_color = (0.5, 0.9, 1.0)
    bands = ((1.35, 0.05, 0.035), (-1.35, 0.05, 0.035), (0.0, 0.06, 0.03))

    def part_k(self, n, kg):
        if "Tether" in n:
            return 0.02
        if n.startswith("Satellite"):
            return 0.05
        return super().part_k(n, kg)

    def extras(self, ctx, c, hx, hy):
        ex = []
        R45 = np.array([[np.cos(0.785), -np.sin(0.785), 0], [np.sin(0.785), np.cos(0.785), 0], [0, 0, 1]])
        ex.append(CExtra("box", [1.1, 1.1, 0.24], c + np.array([0, 0.0, -egg_r(0.0, hx, hy) + 0.08]), 0.05, GOLD, "Plastic", 0.4, R45))
        ex.append(CExtra("box", [0.7, 0.7, 0.28], c + np.array([0, 0.0, -egg_r(0.0, hx, hy) - 0.04]), 0.03, (1, 1, 1), "Neon", 0.4, R45))
        for y in (1.35, -1.35):
            ex += egg_ring(c, hx, hy, 12, y, [0.2, 0.2, 0.16], GOLD, "Plastic", 0.05, 0 if y < 0 else 15, 0.0)
        # spiky halo of petals around the top + aurora gem
        for a in range(0, 360, 30):
            d = np.array([np.cos(np.radians(a)) * 0.9, 1.0, np.sin(np.radians(a)) * 0.9])
            ex.append(CExtra("ellipsoid", [0.22, 0.9, 0.14], c + np.array([np.cos(np.radians(a)) * 0.3, hy - 0.5, np.sin(np.radians(a)) * 0.3]) + unit(d) * 0.3, 0.06, PINK if a % 60 else CY, "Neon", 0.5, orient(d)))
        for i in (1, 2, 3):                                   # chunky orbit arms so the satellites stay welded to the egg
            s = ctx.shape(f"Satellite{i}").c
            h = np.array([s[0], 0.0, s[2]]); L = np.linalg.norm(h); u = h / L
            for t in np.linspace(1.25, L - 0.2, 5):
                ex.append(CExtra("ellipsoid", [0.2, 0.2, 0.2], u * t + np.array([0, s[1] * t / L, 0]), 0.05, CY, "Neon"))
        ex += egg_ring(c, hx, hy, 6, -1.5, [0.66, 0.46, 0.28], MET, "Metal", 0.08, 0, 0.05, tilt=True)
        return ex

    def pat_fn(self):
        return combine((pebble(0.2, 0.03, 4), 0.5), (egg_facets(13, 0.8), 0.12))
