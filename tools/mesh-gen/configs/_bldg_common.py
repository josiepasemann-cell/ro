"""Shared toolkit for the building configs (Anglerfish/BroodPool/CoralBarrier/EelTrap/FilterPlant/GlowBuoy).

Everything is expressed in *model coordinates*: origin = centre of the `Base` part, world axes (Y up, front = -Z),
so the numbers can be read straight off the buildscripts.  Blobs / custom shapes are converted into the anchor frame of the
group that is currently being built.

Workarounds implemented here (pipeline files are shared and untouched):
  * `Cfg.is_decal(p)` is called once for every Part before grouping -> used as a hook to mutate parts (custom SDFs for the
    CSG placeholders the exporter flattens to boxes, minimum thicknesses ...).
  * Extra blobs get their own colour/material through a `like` property that ignores the pipeline's name lookup, so
    decorations (moss, barnacles, rivets, spikes ...) do not have to exist as buildscript parts (and therefore never appear in
    manifest `replaces`, which would break make_apply_script.py).
  * Custom SDF parts keep their original name/size (bbox) so `replaces` stays valid.
"""
import sys, pathlib, types, re
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import numpy as np
import sdf as S
from models import Cfg, Extra, Sculpt, pebble, weave, combine, hash1, scales, rays

F32 = np.float32
smin, smax, sstep = S.smin, S.smax, S.smoothstep


# ------------------------------------------------------------------ model-space SDF primitives  (m: (N,3))
def v3(*a): return np.array(a, np.float32)


def sd_tcap(m, a, b, ra, rb):
    """Tapered capsule from a (radius ra) to b (radius rb)."""
    a, b = v3(*a), v3(*b)
    pa, ba = m - a, b - a
    h = np.clip((pa @ ba) / max(float(ba @ ba), 1e-9), 0, 1)
    return np.linalg.norm(pa - h[:, None] * ba, axis=-1) - (ra + (rb - ra) * h)


def sd_ell(m, c, r):
    q = m - v3(*c)
    r = v3(*r) if np.ndim(r) else v3(r, r, r)
    k0 = np.linalg.norm(q / r, axis=-1)
    k1 = np.linalg.norm(q / (r * r), axis=-1)
    return np.where(k0 < 1e-3, -r.min(), k0 * (k0 - 1) / np.maximum(k1, 1e-9))


def sd_rbox(m, c, half, r):
    q = np.abs(m - v3(*c)) - (v3(*half) - r)
    return np.linalg.norm(np.maximum(q, 0), axis=-1) + np.minimum(q.max(-1), 0) - r


def sd_cyl(m, c, R, hy, r=0.0):
    """Y-axis rounded cylinder, radius R, half height hy."""
    q = m - v3(*c)
    rad = np.hypot(q[:, 0], q[:, 2])
    w0, w1 = rad - (R - r), np.abs(q[:, 1]) - (hy - r)
    return np.hypot(np.maximum(w0, 0), np.maximum(w1, 0)) + np.minimum(np.maximum(w0, w1), 0) - r


def sd_ring(m, c, rin, rout, hy, r=0.05):
    """Y-axis ring (annulus) with rounded rectangular section."""
    q = m - v3(*c)
    rad = np.hypot(q[:, 0], q[:, 2])
    mid, hw = 0.5 * (rin + rout), 0.5 * (rout - rin)
    w = np.stack([np.abs(rad - mid) - (hw - r), np.abs(q[:, 1]) - (hy - r)], -1)
    return np.linalg.norm(np.maximum(w, 0), axis=-1) + np.minimum(w.max(-1), 0) - r


def sd_torus(m, c, R, r):
    q = m - v3(*c)
    return np.hypot(np.hypot(q[:, 0], q[:, 2]) - R, q[:, 1]) - r


def umin(fns, k=0.0):
    def f(m):
        d = fns[0](m)
        for g in fns[1:]:
            d = smin(d, g(m), k) if k > 0 else np.minimum(d, g(m))
        return d
    return f


def ring_pts(n, R, y, phase=0.0):
    return [(R * np.cos(np.radians(360 / n * i + phase)), y, R * np.sin(np.radians(360 / n * i + phase))) for i in range(n)]


def radial_spike(ang_deg, R, y0, length, ra, rb, lean_deg=0.0):
    """Spike rising from radius R at height y0; lean_deg > 0 leans it inwards (towards the axis), < 0 outwards."""
    a = np.radians(ang_deg)
    d = np.array([np.cos(a), 0, np.sin(a)])
    l = np.radians(lean_deg)
    p0 = np.array([R * d[0], y0, R * d[2]])
    p1 = p0 + length * (np.array([0, 1, 0]) * np.cos(l) - d * np.sin(l))
    return p0, p1, ra, rb


def spike_ring(n, R, y0, length, ra, rb, lean_deg=0.0, phase=0.0, k=0.0):
    fs = []
    for i in range(n):
        p0, p1, a, b = radial_spike(360 / n * i + phase, R, y0, length, ra, rb, lean_deg)
        fs.append(lambda m, p0=p0, p1=p1, a=a, b=b: sd_tcap(m, p0, p1, a, b))
    return umin(fs, k)


# ------------------------------------------------------------------ culled (bounded) primitive factories
def culled(fn, c, R):
    c = v3(*c)

    def f(m):
        d = np.linalg.norm(m - c, axis=-1) - R
        sel = d < 0.6
        if sel.any():
            d = d.copy()
            d[sel] = fn(m[sel])
        return d
    return f


def ell(c, r):
    r = (r, r, r) if np.ndim(r) == 0 else r
    return culled(lambda m: sd_ell(m, c, r), c, max(r))


def tcap(a, b, ra, rb=None):
    rb = ra if rb is None else rb
    a, b = np.array(a, float), np.array(b, float)
    return culled(lambda m: sd_tcap(m, a, b, ra, rb), (a + b) / 2, np.linalg.norm(b - a) / 2 + max(ra, rb))


def rbox(c, half, r):
    return culled(lambda m: sd_rbox(m, c, half, r), c, float(np.linalg.norm(half)))


def cyl(c, R, hy, r=0.0):
    return culled(lambda m: sd_cyl(m, c, R, hy, r), c, float(np.hypot(R, hy)))


def ring(c, rin, rout, hy, r=0.05):
    return culled(lambda m: sd_ring(m, c, rin, rout, hy, r), c, float(np.hypot(rout, hy)))


def torus(c, R, r):
    return culled(lambda m: sd_torus(m, c, R, r), c, R + r)


def torus_x(c, R, r):
    c = v3(*c)

    def fn(m):
        q = m - c
        return np.hypot(np.hypot(q[:, 1], q[:, 2]) - R, q[:, 0]) - r
    return culled(fn, c, R + r)


def U(*fns, k=0.0):
    return umin(list(fns), k)


def spheres_on_ring(n, R, y, r, phase=0.0, sq=1.0):
    return U(*[ell(p, r) for p in ring_pts(n, R, y, phase)])


def moss_at(c, s=1.0):
    c = np.array(c, float)
    return U(*[ell(c + np.array([dx, dy, dz]) * s, (rr * s * 1.15, rr * s * 0.7, rr * s * 1.15))
               for dx, dz, dy, rr in ((0, 0, 0, .42), (.35, .1, .05, .3), (-.28, .22, .0, .28), (.05, -.3, .05, .26))], k=0.12)


def barnacles(pts, h=0.3, r=0.17, seed=0):
    fs = []
    for i, pt in enumerate(pts):
        hh = h * (0.7 + 0.5 * ((i * 7 + seed) % 3) / 2.0)
        fs.append(tcap(pt, (pt[0], pt[1] + hh, pt[2]), r, r * 0.55))
    return U(*fs)


def tuft(base, n, height, spread, r0=0.14, phase=0.0, k=0.0):
    """fan of tapered fingers (anemone / coral fingers / kelp) from `base`"""
    b = np.array(base, float)
    fs = []
    for i in range(n):
        a = np.radians(360 / n * i + phase)
        d = np.array([np.cos(a), 0, np.sin(a)])
        h = height * (0.75 + 0.25 * ((i * 5) % 3) / 2.0)
        fs.append(tcap(b, b + d * spread * (0.6 + 0.4 * (i % 2)) + (0, h, 0), r0, r0 * 0.4))
    return U(*fs, k=k)


def eye_blobs(mk, c, d, r, iris=(0.7, 0.35, 1.0), iris_mat="Neon"):
    """cartoon eye (sclera / iris / pupil) bulging out of a surface point c along horizontal direction d; each layer protrudes beyond the last"""
    c, d = np.array(c, float), np.array(d, float)
    d = d / np.linalg.norm(d)
    return [mk(ell(c, r), 0.02, rgb(250, 246, 232)),
            mk(ell(c + d * 0.55 * r, 0.58 * r), 0.02, iris, iris_mat),
            mk(ell(c + d * 0.98 * r, 0.3 * r), 0.02, rgb(16, 14, 24))]


def spikes(n, R, y0, length, ra, rb, lean=0.0, phase=0.0):
    fs = []
    for i in range(n):
        p0, p1, a, b = radial_spike(360 / n * i + phase, R, y0, length, ra, rb, lean)
        fs.append(tcap(p0, p1, a, b))
    return U(*fs)


# ------------------------------------------------------------------ custom part shapes / blobs
class CustomShape(S.Shape):
    def __init__(self, part, fi, fn, cfg):
        super().__init__("box", part.size, fi @ part.M, 0.5)
        self.A = np.linalg.inv(fi)
        self.fn, self.cfg = fn, cfg

    def __call__(self, P):
        R, t = self.A[:3, :3], self.A[:3, 3] - self.cfg.origin
        return self.fn((P @ R.T + t).astype(np.float32))


def setcustom(cfg, p, fn, size=None):
    if size is not None:
        p.size = np.array(size, float)
    p.kind = "custom"
    p.shape = lambda fi, rounding=None, p=p: CustomShape(p, fi, fn, cfg)
    p.world_shape = lambda rounding=0.45, p=p: CustomShape(p, np.eye(4), fn, cfg)


class Blob(Extra):
    like = property(lambda s: s._like, lambda s, v: None)

    def __init__(self, cfg, g, fn, k, color, mat="SmoothPlastic"):
        Extra.__init__(self, "ellipsoid", [1, 1, 1], [0, 0, 0], k, g)
        self._like = types.SimpleNamespace(name="blob", color=np.array(color, float), material=mat, neon=(mat == "Neon"),
                                           transp=0.0, hidden=False, decal=False)
        self.fn, self.frame = fn, cfg.frame(g)

    def shape(self, Q):
        R, t = self.frame
        return self.fn((Q @ R.T + t).astype(np.float32))


def rgb(r, g, b): return (r / 255.0, g / 255.0, b / 255.0)


PAL = dict(
    moss=rgb(96, 170, 84), moss2=rgb(130, 200, 96), barn=rgb(236, 226, 200), coral=rgb(255, 140, 120), coral2=rgb(255, 176, 150),
    teal=rgb(80, 230, 210), gold=rgb(240, 190, 80), steel=rgb(150, 162, 178), dark=rgb(48, 54, 64), rust=rgb(176, 110, 70),
    stone=rgb(120, 128, 142), sand=rgb(214, 196, 150), kelp=rgb(60, 140, 96),
)


# ------------------------------------------------------------------ texture helpers (model-space aware)
def to_model(cfg, g, fn):
    def f(P):
        R, t = cfg.frame(g)
        return fn((P @ R.T + t).astype(np.float32))
    return f


def rust_patina(size=0.5, contrast=0.2, seed=4):
    pb = pebble(size * 0.35, 0.12, seed, 0.15)

    def fn(P):
        h, b, r = pb(P)
        n = S.fbm(P / size, seed, 3)
        return 0.6 * h + 0.2 * (n * 0.5 + 0.5), b * (1 + contrast * n), r + 0.1 * (n * 0.5 + 0.5)
    return fn


def diamond(size=0.16, contrast=0.12):
    def fn(P):
        u = (P[:, 0] + P[:, 2]) / size * np.pi
        w = (P[:, 0] - P[:, 2]) / size * np.pi
        h = (0.5 + 0.5 * np.cos(u)) * (0.5 + 0.5 * np.cos(w))
        h = np.maximum(h, 0.5 + 0.5 * np.cos(P[:, 1] / size * np.pi * 2) * 0.0)
        return h, 1 + contrast * (h - 0.5), 0.08 * (1 - h)
    return fn


def planks(width=0.5, contrast=0.16):
    def fn(P):
        ang = np.arctan2(P[:, 2], P[:, 0])
        r = np.hypot(P[:, 0], P[:, 2])
        u = (P[:, 0] + 0.31 * np.sin(P[:, 2] * 0.8)) / width
        f = u - np.floor(u)
        seam = sstep(0.06, 0.0, f) + sstep(0.94, 1.0, f)
        grain = 0.5 + 0.5 * S.vnoise(np.stack([P[:, 0] * 3, P[:, 1] * 30, P[:, 2] * 3], -1))
        h = 1 - seam * 0.9
        return h, 1 + contrast * (grain - 0.5) - 0.18 * seam, 0.1 * seam
    return fn


# ------------------------------------------------------------------ base config
class BCfg(Cfg):
    """Chunky cartoon building.  Subclasses override tweak(p), blobs(g) and stage-dependent numbers."""
    name = "?"
    stage = 1
    wobble = 0.004
    blend_tau = 0.02
    ao_radius = 0.09
    ao_strength = 1.0
    normal_gain = 1.0
    decal_re = r"Stripe$|Stripe\d|Highlight|Glint"
    extra_roots = None
    keep_re = None
    body_tex = 768
    body_cells = 210
    body_budget = 6500
    body_k = 0.2
    margin = 0.5
    lift = 1.0
    sat = 1.25
    val = 0.92

    def __init__(self):
        self.cf = {}
        self.sz = {}
        self.origin = np.zeros(3)

    # --- frames
    def frame(self, g):
        A = self.cf[g]
        return np.array(A[:3, :3], np.float32), np.array(A[:3, 3] - self.origin, np.float32)

    def L(self, name):
        """centre of a part in model coordinates"""
        return self.cf[name][:3, 3] - self.origin

    # --- hooks
    def is_decal(self, p):
        self.cf[p.name] = p.cf
        self.sz[p.name] = np.array(p.size, float)
        if p.name == "Base":
            self.origin = np.array(p.cf[:3, 3], float)
        if self.lift != 1.0 and not p.neon:
            p.color = np.clip(p.color * self.lift, 0, 1)
        rs = np.array(p.raw["size"], float)
        if p.kind == "cylx" and abs(rs[1] - rs[2]) > 1e-3:   # buildscripts give Size=(D,h,D) to a Cylinder (axis = X) -> intended disc is (h,D,D)
            p.size = np.array([rs.min(), rs.max(), rs.max()])
        if p.transp > 0 and not p.hidden and p.name != "GlowWater":               # translucency of single parts would average into the whole mesh
            p.transp = 0.0
        self.tweak(p)
        if not p.neon:
            c = np.array(p.color, float)
            m = c.mean()
            p.color = np.clip((m + (c - m) * self.sat) * self.val, 0, 1)
        return bool(re.search(self.decal_re, p.name)) and p.name not in ("Eye1", "Eye2")

    def tweak(self, p): pass

    # --- part tweak helpers
    def tcap_part(self, p, ra, rb=None, axis=1, pad=0.0):
        """turn a box/cylinder part into a tapered capsule along its local `axis` (radius ra at -axis end, rb at +axis end)"""
        rb = ra if rb is None else rb
        h = p.size[axis] / 2.0
        cfm, cfp = p.cf.copy(), p.cf[:3, 3].copy()
        size = p.size.copy()
        size[[i for i in range(3) if i != axis]] = 2 * max(ra, rb) + pad

        def fn(m, self=self):
            ax = cfm[:3, axis]
            a = cfp - ax * (h - ra) - self.origin
            b = cfp + ax * (h - rb) - self.origin
            return sd_tcap(m, a, b, ra, rb)
        setcustom(self, p, fn, size)

    def drop(self, p, dy):
        p.M = p.M.copy()
        p.M[1, 3] += dy

    def rounding(self, p): return 0.6

    def k(self, g): return self.body_k if g == "Base" else 0.12
    def part_k(self, name, kg): return self.pk(name, kg)
    def pk(self, name, kg): return kg

    def budget(self, g): return self.body_budget if g == "Base" else self.root_budget(g)
    def root_budget(self, g): return 700
    def cells(self, g): return self.body_cells if g == "Base" else 150
    def tex(self, g): return self.body_tex if g == "Base" else 256
    def amp(self, g): return 0.02

    def blobs(self, g, mk):
        """override: return list of Blobs using mk(fn, k, color, mat)"""
        return []

    def sculpt(self, g, ctx, dim):
        mk = lambda fn, k, color, mat="SmoothPlastic": Blob(self, g, fn, k, color, mat)
        ex = self.blobs(g, mk)
        return Sculpt(None, self.post(g, dim), ex, margin=self.margin if g == "Base" else 0.1)

    def post(self, g, dim): return None

    # --- textures
    def mat_patterns(self):
        return {}

    def detail(self, g):
        pats = {
            "Cobblestone": pebble(0.55, 0.26, 3, 0.2), "Rock": pebble(0.42, 0.22, 5, 0.2), "Basalt": pebble(0.7, 0.2, 8, 0.2),
            "Pebble": pebble(0.22, 0.2, 9, 0.2), "Concrete": pebble(0.3, 0.1, 11, 0.15),
            "CorrodedMetal": rust_patina(0.5, 0.22), "Metal": rust_patina(0.9, 0.08, 6), "DiamondPlate": diamond(),
            "WoodPlanks": planks(), "SmoothPlastic": pebble(0.16, 0.07, 2, 0.1), "Glass": pebble(0.5, 0.03, 4, 0.02),
            "Neon": pebble(0.14, 0.05, 12, 0.0),
        }
        pats.update(self.mat_patterns())
        return lambda mat: (lambda fn: (to_model(self, g, fn) if fn else None))(pats.get(mat))
