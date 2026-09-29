import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _enpc import *


class Config(StyledCfg):
    """Teal pufferfish with glowing thorns, big eyes and a tiny toothy underbite."""
    name = "ThornSwarmer"
    iris_color = (0.95, 0.65, 0.15)
    eye_scale = 1.15
    ao_radius = 0.12
    normal_gain = 0.45

    def rounding(self, p): return 0.6
    def k(self, g): return {"Body": 0.24, "Mantle": 0.16}.get(g, 0.1)
    def part_k(self, n, kg):
        if n.startswith("Thorn") or n.startswith("SmallThorn"): return 0.07
        if n == "Jaw": return 0.1
        if n.startswith("Tooth"): return 0.03
        return kg
    def budget(self, g): return {"Body": 6500, "Mantle": 1600, "TailFin": 1300}.get(g, 800)
    def cells(self, g): return 220 if g == "Body" else 150
    def tex(self, g): return 512 if g == "Body" else (256 if g == "Mantle" else 256)
    def amp(self, g): return 0.016 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            ex = []

            return Sculpt(None, None, ex, margin=0.05)
        return None

    def detail(self, g):
        skin = pebble(0.08, 0.07, 6, 0.1)
        return lambda m: {"Pebble": skin, "Neon": pebble(0.05, 0.05, 2), "SmoothPlastic": pebble(0.05, 0.08, 3)}.get(m, skin)
