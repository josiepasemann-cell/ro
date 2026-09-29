import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _common import *


class Config(Cfg):
    name = "CrystalKraken"
    iris_color = (0.5, 0.25, 0.85)
    iris_ratio = 1.6
    ao_radius = 0.1
    wobble = 0.004
    eye_inset = 0.6
    extra_roots = r"^GlowCore$"          # glowing core stays its own (Neon) mesh inside the translucent glass body
    ao_strength = 0.7

    def k(self, g): return 0.2 if g == "Body" else 0.1
    def part_k(self, n, kg): return {"CrownShade": 0.3, "MantleSkirt": 0.3}.get(n, 0.06 if n.startswith("Crown") else kg)
    def budget(self, g):
        if g == "Body": return 6500
        if g == "GlowCore": return 700
        return 500
    def cells(self, g): return 230 if g == "Body" else 110
    def tex(self, g): return 768 if g == "Body" else (128 if g == "GlowCore" else 64)
    def amp(self, g): return 0.02
    def rounding(self, p): return 0.9 if p.name.startswith("Crown") else 0.5

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        b = ctx.shape("Body").c
        ex = [socket(ctx, "Eye1", "Body", "Body", 0.1, 1.2), socket(ctx, "Eye2", "Body", "Body", 0.1, 1.2)]
        crowns = [ctx.shape(f"Crown{i}").c for i in range(1, 6)]

        def post(Q, d):
            for c in crowns:                          # crystal crown: tall pointed shards leaning outwards
                out = np.array([c[0] - b[0], 0, c[2] - b[2]]); out /= max(np.linalg.norm(out), 1e-6)
                a = c + [0, -0.25, 0] - out * 0.05
                t = c + [0, 0.62, 0] + out * 0.12
                d = S.smin(d, round_cone(Q, a, t, 0.17, 0.03), 0.05)
            return groove(Q, d, b + [0, -0.55, -1.3], [0.55, 0.06, 0.4], 0.5, 0.03)   # smile
        return Sculpt(None, post, ex, margin=0.15)

    def detail(self, g):
        facets = mix(pebble(0.28, 0.16, 11), pebble(0.09, 0.05, 2))
        return lambda m: {"Glass": facets, "Neon": pebble(0.12, 0.04), "SmoothPlastic": pebble(0.07, 0.08)}.get(m)
