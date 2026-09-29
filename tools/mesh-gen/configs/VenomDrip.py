import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

TOX = (0.67, 1.0, 0.27)
TOX2 = (0.43, 0.86, 0.2)
GLOW = (0.85, 1.0, 0.3)


class Config(Cfg):
    """Toxic stalagmite: green glass spike with drip streaks, glowing droplets and bubbles on a basalt mound."""
    name = "VenomDrip"
    ao_radius = 0.09
    wobble = 0.004
    belly = 0.1

    def k(self, g): return 0.22
    def part_k(self, n, kg): return 0.06 if n.startswith(("Venom", "Minor")) else (0.3 if n.startswith("SpikeSeg") else 0.25)
    def budget(self, g): return 5200
    def cells(self, g): return 230
    def tex(self, g): return 768
    def amp(self, g): return 0.013

    def sculpt(self, g, ctx, dim):
        b = ctx.shape("Base"); bc = b.c
        ex = []
        rng = np.random.RandomState(9)
        rr = lambda y: max(0.3, 1.2 - 0.237 * (y - 1.0))      # spike radius at local height y
        # drip streaks running down the spike, ending in fat droplets
        for i in range(7):
            a = np.radians(51 * i + 12)
            ytop = 3.4 - 0.6 * (i % 3)
            L = 1.3 + 0.3 * (i % 2)
            rad = rr(ytop - L * 0.5) - 0.02
            pos = np.array([np.cos(a) * rad, ytop - L * 0.5, np.sin(a) * rad])
            ex.append(CExtra("ellipsoid", [0.16, L, 0.16], pos, 0.06, GLOW, "Neon", 0.5, orient([np.cos(a) * 0.15, 1, np.sin(a) * 0.15])))
            ex.append(CExtra("ellipsoid", [0.3, 0.36, 0.3], pos + np.array([np.cos(a) * 0.03, -L * 0.5, np.sin(a) * 0.03]), 0.08, GLOW, "Neon"))
        # toxic warts on the spike
        for i in range(10):
            a = np.radians(37 * i); y = 1.7 + 0.32 * i
            ex.append(CExtra("ellipsoid", [0.22, 0.22, 0.22], np.array([np.cos(a) * (rr(y) - 0.03), y, np.sin(a) * (rr(y) - 0.03)]), 0.06, TOX2, "Glass"))
        # gooey puddle around the base
        ex.append(CExtra("ellipsoid", [3.1, 0.2, 3.1], [0, 0.42, 0], 0.15, TOX2, "Neon"))
        return Sculpt(None, None, ex, margin=0.12)

    def detail(self, g):
        return lambda m: {"Basalt": pebble(0.16, 0.10, 2), "Glass": pebble(0.16, 0.03, 5), "Neon": pebble(0.1, 0.03)}.get(m)
