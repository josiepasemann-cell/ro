import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

ICE = (0.59, 0.82, 0.96)
CORE = (0.78, 0.96, 1.0)


def crystal(Q, ax, az, y0, y1, r, taper, rot=0.0):
    """Hexagonal crystal prism with a pointed top (approximate SDF)."""
    x = Q[:, 0] - ax; z = Q[:, 2] - az
    hexd = np.zeros(len(Q), np.float32) - 9
    for k in range(3):
        a = rot + k * np.pi / 3
        hexd = np.maximum(hexd, np.abs(x * np.cos(a) + z * np.sin(a)))
    yt = y1 - taper
    allowed = r * np.clip((y1 - Q[:, 1]) / taper, 0, 1) ** 0.9
    d = (hexd - allowed) * 0.85
    d = S.smax(d, y0 - Q[:, 1], 0.05)
    return S.smax(d, Q[:, 1] - y1, 0.03)


class Config(Cfg):
    name = "IceSpire"
    ao_radius = 0.09
    wobble = 0.0025
    belly = 0.2

    def k(self, g): return 0.2
    def budget(self, g): return 4200
    def cells(self, g): return 220
    def tex(self, g): return 768
    def amp(self, g): return 0.012

    def sculpt(self, g, ctx, dim):
        base = ctx.shape("Base")
        bc = base.c
        spikes = []
        for i in range(1, 6):
            s = ctx.shape(f"IceSpike{i}")
            spikes.append((s.c, s.half))
        shards = [ctx.shape(f"FrostShard{i}") for i in range(1, 5)]
        ex = []
        for c, h in spikes:                                    # glowing core seen through the front facets
            for j, a in enumerate((-90, 30, 150)):
                pos = c + np.array([np.cos(np.radians(a)) * h[0] * 0.55, -h[1] * 0.1, np.sin(np.radians(a)) * h[0] * 0.55])
                ex.append(CExtra("ellipsoid", [h[0] * 0.14, h[1] * 1.15, h[0] * 0.14], pos, 0.02, CORE, "Neon"))
        def post(Q, d):
            out = base(Q)
            for i, (c, h) in enumerate(spikes):
                cr = crystal(Q, c[0], c[2], c[1] - h[1] * 1.0, c[1] + h[1], h[0] * 0.5, h[1] * 0.55, rot=0.4 * i)
                out = S.smin(out, cr, 0.12)
            for i, sh in enumerate(shards):
                cr = crystal(Q, sh.c[0], sh.c[2], sh.c[1] - 0.35, sh.c[1] + 0.45, 0.2, 0.3, rot=1.0 + i)
                out = S.smin(out, cr, 0.08)
            for e in ex:
                out = S.smin(out, e.shape(Q), e.k)
            return out
        return Sculpt(None, post, ex, margin=0.15)

    def detail(self, g):
        facet = egg_facets(4, 0.5)
        return lambda m: {"Ice": pebble(0.15, 0.07, 4), "Glass": facet, "Neon": pebble(0.1, 0.03)}.get(m)
