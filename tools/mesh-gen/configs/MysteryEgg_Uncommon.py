import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

MINT = (0.78, 1.0, 0.94)
NEON = (0.35, 0.98, 0.86)
DARK = (0.27, 0.75, 0.65)


class Config(EggBase):
    name = "MysteryEgg_Uncommon"
    egg_budget = 3600
    egg_tex = 512
    egg_cells = 200
    ribs = 6
    rib_amp = 0.04
    bands = ((0.75, 0.06, 0.03), (-0.75, 0.06, 0.03))

    def extras(self, ctx, c, hx, hy):
        ex = []
        # raised polka-dot belt between the two neon rings + a lower ring of dots
        ex += egg_ring(c, hx, hy, 8, 0.0, [0.46, 0.46, 0.2], MINT, "SmoothPlastic", 0.06, 10)
        ex += egg_ring(c, hx, hy, 6, -1.05, [0.24, 0.24, 0.16], NEON, "Neon", 0.05, 30)
        ex += egg_ring(c, hx, hy, 5, 1.05, [0.22, 0.22, 0.15], NEON, "Neon", 0.05, 0)
        # dark scalloped collar at the base
        ex.append(CExtra("cylx", [0.3, 1.8, 1.8], c + np.array([0, -hy + 0.3, 0]), 0.05, DARK, "SmoothPlastic", 0.5,
                         orient([0, 0, 1]) @ np.eye(3)))
        return ex

    def pat_fn(self):
        return combine((pebble(0.11, 0.035, 4), 0.8), (dots(0.42, 0.13, 6, 0.3, 0.3), 0.7))
