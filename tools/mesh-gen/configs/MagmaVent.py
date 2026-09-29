import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

LAVA = (1.0, 0.47, 0.12)
LAVA2 = (1.0, 0.62, 0.2)
HOT = (1.0, 0.8, 0.35)
ROCK = (0.2, 0.13, 0.1)
ROCK2 = (0.13, 0.08, 0.06)


def surf(x, z):
    return 0.5 * np.sqrt(max(0.0, 1 - (x * x + z * z) / 4.0))


class Config(Cfg):
    """Volcanic vent: dark craggy rock mound, raised glowing lava fissures with a bubbling pool and embers."""
    name = "MagmaVent"
    ao_radius = 0.09
    wobble = 0.006
    belly = 0.15

    def k(self, g): return 0.2
    def part_k(self, n, kg): return 0.05 if n.startswith(("Glow", "Ember")) else (0.18 if n.startswith("RockChunk") else 0.25)
    def budget(self, g): return 5200
    def cells(self, g): return 230
    def tex(self, g): return 768
    def amp(self, g): return 0.02

    def sculpt(self, g, ctx, dim):
        ex = []
        rng = np.random.RandomState(6)
        # central lava pool (slightly bulging, glowing)
        ex.append(CExtra("ellipsoid", [1.5, 0.3, 1.2], [0.0, 0.44, 0.0], 0.06, LAVA2, "Neon"))
        ex.append(CExtra("ellipsoid", [0.7, 0.22, 0.6], [0.05, 0.53, 0.0], 0.06, HOT, "Neon"))
        # raised fissures following the original crack + branch (segments hugging the mound)
        for (dx, dz, off, L) in ((0.94, -0.34, (0, 0), 1.7), (0.77, 0.64, (0.6, 0.6), 0.95)):
            for t in np.linspace(-L, L, 9):
                x = off[0] + dx * t; z = off[1] + dz * t
                w = 0.36 * (1 - 0.6 * abs(t) / L) + 0.05
                ex.append(CExtra("ellipsoid", [w * 1.5, 0.2, w * 1.0], [x, surf(x, z) - 0.03, z], 0.08, LAVA if abs(t) > 0.5 else LAVA2, "Neon", 0.5,
                                 orient([0, 1, 0]) @ np.array([[dx, 0, -dz], [0, 1, 0], [dz, 0, dx]]).T))
        # crater rim: ring of jagged rocks around the pool
        for i in range(9):
            a = np.radians(40 * i + 8)
            r_ = 1.15 + 0.15 * (i % 2)
            p = np.array([np.cos(a) * r_, surf(np.cos(a) * r_, np.sin(a) * r_) + 0.12, np.sin(a) * r_])
            ex.append(CExtra("ellipsoid", [0.42, 0.55 + 0.15 * (i % 3), 0.36], p, 0.1, ROCK if i % 2 else ROCK2, "Rock", 0.5, orient([np.cos(a) * 0.35, 1, np.sin(a) * 0.35])))
        # spires on the flanks
        for a, r_, h in ((200, 1.3, 1.0), (300, 1.4, 0.8), (110, 1.6, 0.7)):
            a = np.radians(a)
            ex.append(CExtra("ellipsoid", [0.5, h, 0.45], [np.cos(a) * r_, h * 0.4, np.sin(a) * r_], 0.12, ROCK2, "Rock", 0.5, orient([np.cos(a) * 0.3, 1, np.sin(a) * 0.3])))
        # embers
        for i in range(7):
            a = np.radians(51 * i + 20); r_ = 0.5 + 0.28 * ((i * 3) % 5)
            x, z = np.cos(a) * r_, np.sin(a) * r_
            ex.append(CExtra("ellipsoid", [0.17, 0.12, 0.17], [x, surf(x, z) + 0.02, z], 0.04, (1.0, 0.7, 0.25), "Neon"))
        return Sculpt(None, None, ex, margin=0.1)

    def detail(self, g):
        rock = combine((pebble(0.2, 0.2, 3), 0.7), (pebble(0.08, 0.12, 8), 0.5))
        return lambda m: {"Rock": rock, "Neon": pebble(0.12, 0.05, 2)}.get(m)
