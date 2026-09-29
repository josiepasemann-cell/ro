import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

CY = (0.55, 0.9, 1.0)


class Config(EggBase):
    name = "MysteryEgg_Common"
    egg_budget = 2800
    egg_tex = 512
    egg_cells = 190
    wobble = 0.006
    bands = ((0.0, 0.07, 0.02),)

    def extras(self, ctx, c, hx, hy):
        ex = egg_ring(c, hx, hy, 5, 0.75, [0.2, 0.2, 0.14], CY, "Neon", 0.04, 20)
        ex += egg_ring(c, hx, hy, 4, -0.7, [0.16, 0.16, 0.12], CY, "Neon", 0.04, 55)
        # small soft highlight bump near the tip
        ex.append(CExtra("ellipsoid", [0.5, 0.34, 0.5], c + np.array([0, hy - 0.4, 0]), 0.2, (0.94, 1, 0.99), "SmoothPlastic"))
        return ex

    def pat_fn(self):
        return combine((pebble(0.16, 0.03, 4), 1.0))
