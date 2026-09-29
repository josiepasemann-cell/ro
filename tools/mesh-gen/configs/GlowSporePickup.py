import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

CY = (0.47, 0.96, 1.0)
LIGHT = (0.82, 1.0, 1.0)
TEAL = (0.27, 0.78, 0.84)
MINT = (0.6, 1.0, 0.85)


class Config(Cfg):
    """Glowing spore: neon core with burr-like nubs, teal veins and a few filament tufts.  The glass OuterShell stays a Roblox part."""
    name = "GlowSporePickup"
    keep_re = r"^OuterShell$"
    ao_radius = 0.1
    wobble = 0.004
    belly = 0.2

    def k(self, g): return 0.12
    def part_k(self, n, kg): return 0.06
    def budget(self, g): return 2600
    def cells(self, g): return 170
    def tex(self, g): return 512
    def amp(self, g): return 0.012

    def sculpt(self, g, ctx, dim):
        b = ctx.shape("Body"); c = b.c; r = 0.7
        ex = []
        rng = np.random.RandomState(4)
        # burr nubs: fibonacci sphere, alternating light/cyan tips
        n = 22
        for i in range(n):
            y = 1 - 2 * (i + 0.5) / n
            rad = np.sqrt(1 - y * y); th = i * 2.399963
            d = np.array([rad * np.cos(th), y, rad * np.sin(th)])
            L = 0.24 if i % 3 else 0.32
            ex.append(CExtra("ellipsoid", [0.2, L, 0.2], c + d * (r + L * 0.05), 0.07, LIGHT if i % 3 == 0 else MINT, "Neon", 0.5, orient(d)))
        # dark teal veins hugging the surface (short arcs)
        for i in range(6):
            d = unit(rng.randn(3))
            ex.append(CExtra("ellipsoid", [0.1, 0.5, 0.06], c + d * (r - 0.005), 0.03, TEAL, "Neon", 0.5, orient(np.cross(d, unit(rng.randn(3))))))
        return Sculpt(None, None, ex, margin=0.08)

    def detail(self, g):
        return lambda m: pebble(0.07, 0.10, 2)
