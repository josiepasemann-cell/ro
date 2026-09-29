"""Shared helpers for the props batch (eggs, pickups, decorations).  Not a model config (leading underscore)."""
import sys, pathlib, types
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import numpy as np
from models import *          # Cfg, Sculpt, Extra, socket, cheek, pebble, scales, rays, weave, combine, hash1, unit, S ...
import sdf as S


class _Any(str):
    def __eq__(self, o): return True
    __hash__ = str.__hash__


class CExtra(Extra):
    """Extra blob with explicit colour / material (not tied to an existing part): gems, bands, veins, coral polyps ..."""

    def __init__(self, kind, size, center, k, color, material="SmoothPlastic", rounding=0.5, R=None):
        super().__init__(kind, size, center, k, _Any("__x"), rounding, R)
        self._like = types.SimpleNamespace(color=np.array(color, float), material=material, neon=(material == "Neon"),
                                           name="__x", transp=0.0)

    like = property(lambda s: s._like, lambda s, v: None)      # pipeline assigns .like after sculpt(); ignore it


def orient(axis, roll=0.0):
    """Rotation matrix whose local +Y column points along `axis` (for tilted ellipsoids / spikes)."""
    y = unit(axis)
    ref = np.array([1.0, 0, 0]) if abs(y[0]) < 0.9 else np.array([0, 0, 1.0])
    x = unit(np.cross(ref, y)); z = np.cross(x, y)
    R = np.stack([x, y, z], 1)
    if roll:
        c, s = np.cos(roll), np.sin(roll)
        R = R @ np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return R


def polar(r, ang_deg, y):
    a = np.radians(ang_deg)
    return np.array([r * np.cos(a), y, r * np.sin(a)])


def dots(size, radius, seed=0, contrast=0.22, gate=0.0, rough=0.1):
    """Round dots (worley cell centres) -> raised, brightness shifted."""
    def fn(P):
        F1, F2, cid = S.worley(P / size, seed)
        on = S.smoothstep(radius + 0.06, radius - 0.06, F1) * (cid > gate)
        return on, 1 + contrast * (on - 0.3) + 0.06 * (cid - 0.5), rough * (1 - on)
    return fn


def egg_facets(seed=3, size=0.55):
    """Voronoi facet grooves (returns height, shade)."""
    def fn(P):
        F1, F2, cid = S.worley(P / size, seed)
        e = S.smoothstep(0.0, 0.18, F2 - F1)
        return e, 1 + 0.12 * (e - 0.6) + 0.10 * (cid - 0.5), 0.1 * (1 - e)
    return fn


class EggBase(Cfg):
    """Egg shell: slight egg taper (narrower top), flat resting base, tier specific ribs / facets, textures."""
    ao_radius = 0.1
    wobble = 0.003
    ribs = 0            # vertical rib count
    rib_amp = 0.0
    facet_amp = 0.0     # voronoi facet groove depth
    facet_size = 0.6
    bands = ()          # ((y_rel, half_width, depth), ...) carved horizontal grooves (positive = groove)
    egg_budget = 3500
    egg_tex = 1024
    egg_cells = 210
    pat_fn = None
    clip_grow = None    # trim protruding parts (neon veins ...) to the shell + this margin around the belly
    egg_amp = 0.006

    def k(self, g): return 0.12
    def part_k(self, n, kg):
        return 0.03 if (n.startswith(("Speck", "Spot", "RuneGem", "CrackGlow", "Vein", "Satellite")) or "Tether" in n) else (0.04 if "Ring" in n else kg)
    def budget(self, g): return self.egg_budget if g == 'Shell' else 700
    def cells(self, g): return self.egg_cells if g == 'Shell' else 110
    def tex(self, g): return self.egg_tex if g == 'Shell' else 256
    belly = 0.45
    blend_tau = 0.012
    def amp(self, g): return self.egg_amp
    def rounding(self, p): return 0.5

    def extras(self, ctx, c, hx, hy): return []
    def extra_post(self, Q, d, c, hx, hy): return d

    def sculpt(self, g, ctx, dim):
        b = ctx.shape("Shell")
        c = b.c.copy(); hx, hy = b.half[0], b.half[1]
        cfg = self

        def pre(P):
            Q = P.copy()
            ty = np.clip((P[:, 1] - c[1]) / hy, -1.2, 1.4)
            s = 1 - 0.10 * ty
            Q[:, 0] = c[0] + (P[:, 0] - c[0]) / s
            Q[:, 2] = c[2] + (P[:, 2] - c[2]) / s
            return Q

        def post(Q, d):
            y = Q[:, 1] - c[1]
            d = S.smax(d, (-hy + 0.12) - y, 0.10)                                    # flat resting base
            if cfg.ribs:
                ang = np.arctan2(Q[:, 2] - c[2], Q[:, 0] - c[0])
                rib = 0.5 + 0.5 * np.cos(ang * cfg.ribs)
                env = S.smoothstep(-hy * 0.95, -hy * 0.55, y) * S.smoothstep(hy * 0.98, hy * 0.6, y)
                d = d - cfg.rib_amp * (rib ** 2 - 0.5) * env
            if cfg.facet_amp:
                F1, F2, _ = S.worley((Q - c) / cfg.facet_size, 5)
                d = d + cfg.facet_amp * S.smoothstep(0.16, 0.0, F2 - F1)
            for yb, hw, dep in cfg.bands:
                d = d + dep * np.exp(-((y - yb) / hw) ** 2)
            if cfg.clip_grow is not None:
                q = (Q - c) / np.array([hx, hy, hx])
                de = (np.linalg.norm(q, axis=-1) - 1.0) * hx - cfg.clip_grow
                m = 1 - S.smoothstep(0.7, 0.9, np.abs(y) / hy)
                d = d * (1 - m) + S.smax(d, de, 0.05) * m
            return cfg.extra_post(Q, d, c, hx, hy)
        return Sculpt(pre, post, self.extras(ctx, c, hx, hy), margin=0.1)

    def detail(self, g):
        if self.pat_fn is None:
            f = pebble(0.09, 0.05, 4)
        else:
            f = self.pat_fn()
        return lambda m: f


def egg_r(y, hx, hy):
    return hx * np.sqrt(max(1 - (y / hy) ** 2, 0.0))


def egg_ring(c, hx, hy, n, y, size, color, material, k=0.05, phase=0.0, inset=0.0, kind="ellipsoid", tilt=True):
    """n blobs around the egg at height y (relative to centre), sitting on the surface."""
    out = []
    r = egg_r(y, hx, hy) - inset
    for i in range(n):
        a = phase + 360.0 / n * i
        p = c + polar(r, a, y)
        R = None
        if tilt:
            nrm = np.array([np.cos(np.radians(a)) * hy / hx * 0 + np.cos(np.radians(a)), 0.0, np.sin(np.radians(a))])
            nrm = nrm + np.array([0, y / hy * 0.6, 0])
            R = orient(nrm)
        sz = [size[0], size[2], size[1]] if tilt else size
        out.append(CExtra(kind, sz, p, k, color, material, 0.5, R))
    return out
