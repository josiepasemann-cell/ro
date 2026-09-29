import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

TEAL = (0.27, 0.82, 0.92)
ICE = (0.86, 1.0, 1.0)
MET = (0.16, 0.59, 0.69)


class Config(EggBase):
    name = "MysteryEgg_Rare"
    egg_budget = 4800
    egg_tex = 1024
    egg_cells = 220
    facet_amp = 0.03
    facet_size = 0.85
    egg_amp = 0.010
    ribs = 0
    bands = ((0.0, 0.05, 0.02),)
    belly = 0.35
    iris_color = (0.3, 0.8, 0.9)

    def extras(self, ctx, c, hx, hy):
        ex = []
        # crystal cluster crowning the egg (tilted glass shards)
        for i, (a, tilt, h) in enumerate([(0, 0.0, 0.95), (72, 0.5, 0.7), (144, 0.55, 0.62), (216, 0.5, 0.7), (288, 0.55, 0.62)]):
            dirv = np.array([np.cos(np.radians(a)) * tilt, 1.0, np.sin(np.radians(a)) * tilt])
            base = c + np.array([0, hy - 0.35, 0]) + (0 if i == 0 else 1) * np.array([np.cos(np.radians(a)) * 0.32, -0.1, np.sin(np.radians(a)) * 0.32])
            ex.append(CExtra("ellipsoid", [0.3, h, 0.3], base + unit(dirv) * h * 0.3, 0.05, ICE if i == 0 else TEAL, "Glass", 0.5, orient(dirv)))
        # metallic belts + neon studs
        ex += egg_ring(c, hx, hy, 6, 0.0, [0.3, 0.3, 0.2], ICE, "Neon", 0.05, 30)
        ex += egg_ring(c, hx, hy, 6, -0.95, [0.22, 0.34, 0.16], MET, "Metal", 0.05, 0, tilt=True)
        return ex

    def pat_fn(self):
        return combine((egg_facets(3, 0.85), 1.0))
