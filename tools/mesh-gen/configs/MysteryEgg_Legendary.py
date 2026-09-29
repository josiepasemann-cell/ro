import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

VIO = (0.59, 0.27, 1.0)
CY = (0.43, 0.96, 1.0)
MET = (0.35, 0.16, 0.63)
GOLD = (1.0, 0.92, 0.5)


class Config(EggBase):
    name = "MysteryEgg_Legendary"
    egg_budget = 7500
    egg_tex = 1024
    egg_cells = 240
    ribs = 8
    rib_amp = 0.12
    facet_amp = 0.0
    facet_size = 0.5
    belly = 0.3
    iris_color = (0.5, 0.9, 1.0)
    bands = ((1.2, 0.05, 0.03), (-1.2, 0.05, 0.03))

    def extras(self, ctx, c, hx, hy):
        ex = []
        # golden frame + neon diamond emblem on the front (-Z)
        R45 = np.array([[np.cos(0.785), -np.sin(0.785), 0], [np.sin(0.785), np.cos(0.785), 0], [0, 0, 1]])
        ex.append(CExtra("box", [0.95, 0.95, 0.2], c + np.array([0, 0.35, -egg_r(0.35, hx, hy) + 0.06]), 0.05, GOLD, "Plastic", 0.4, R45))
        ex.append(CExtra("box", [0.58, 0.58, 0.24], c + np.array([0, 0.35, -egg_r(0.35, hx, hy) - 0.02]), 0.03, (1.0, 1.0, 1.0), "Neon", 0.4, R45))
        # gold studs crowning the top ring of ribs and a gold collar at the foot
        ex += egg_ring(c, hx, hy, 10, 1.2, [0.2, 0.2, 0.16], GOLD, "Plastic", 0.05, 18, 0.0)
        ex += egg_ring(c, hx, hy, 10, -1.2, [0.2, 0.2, 0.16], GOLD, "Plastic", 0.05, 0, 0.0)
        ex += egg_ring(c, hx, hy, 5, -1.42, [0.62, 0.44, 0.26], MET, "Plastic", 0.08, 36, 0.05, tilt=True)
        # glowing halo gem at the very top
        ex.append(CExtra("ellipsoid", [0.42, 0.5, 0.42], c + np.array([0, hy - 0.05, 0]), 0.1, (0.85, 1, 1), "Neon"))
        return ex

    def pat_fn(self):
        return combine((pebble(0.2, 0.03, 4), 0.5), (egg_facets(11, 0.8), 0.12))
