import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

VIO = (0.67, 0.35, 1.0)
VEIN = (0.82, 0.59, 1.0)
LIL = (0.88, 0.71, 1.0)
MET = (0.47, 0.24, 0.75)


class Config(EggBase):
    name = "MysteryEgg_Epic"
    egg_budget = 6000
    egg_tex = 1024
    egg_cells = 230
    ribs = 8
    rib_amp = 0.13
    facet_amp = 0.0
    clip_grow = 0.11
    belly = 0.3
    iris_color = (0.7, 0.4, 1.0)

    def extras(self, ctx, c, hx, hy):
        ex = []
        # lotus crown of petals around the crown tip
        for a in range(0, 360, 45):
            d = np.array([np.cos(np.radians(a)) * 0.9, 1.0, np.sin(np.radians(a)) * 0.9])
            ex.append(CExtra("ellipsoid", [0.28, 0.85, 0.16], c + np.array([np.cos(np.radians(a)) * 0.28, hy - 0.42, np.sin(np.radians(a)) * 0.28]) + unit(d) * 0.28, 0.06, LIL, "Glass", 0.5, orient(d)))
        # glowing nodules in every rib groove, three per groove
        for y, s in ((0.85, 0.2), (-0.1, 0.26), (-0.95, 0.2)):
            ex += egg_ring(c, hx, hy, 8, y, [s * 1.2, s * 1.6, s * 0.8], VEIN, "Neon", 0.06, 0, -0.03)
        # metallic base collar petals
        ex += egg_ring(c, hx, hy, 8, -1.3, [0.5, 0.42, 0.22], MET, "Metal", 0.08, 0, 0.05, tilt=True)
        return ex

    def pat_fn(self):
        return combine((pebble(0.2, 0.03, 4), 0.6), (egg_facets(7, 0.9), 0.12))
