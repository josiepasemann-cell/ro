"""Helper library for the creaturesB configs (FrostAnglerPup, GhostFinTuna, GlowJelly, GlowRay, GlowShrimp,
LanternWraith, MagmaSquid).  Only imported by those configs; touches no shared file.

Provides:
  Tint       - sculpt Extra with its own colour/material (no source part needed)
  Cone       - pointed Extra (teeth, crystals, spines)
  Paint      - custom decal (arbitrary SDF) painted into the colour/emissive maps; injected through a runtime wrapper
               around pipeline.bake_surface (the pipeline has no hook for procedural decals)
  surf_point - point on the top surface of a set of shapes
"""
import sys, pathlib, types
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import sdf as S
from models import Cfg, Extra, Sculpt, unit, socket, cheek, pebble, rays, combine, hash1, weave  # noqa: F401


class _Like:
    def __init__(self, color, material, neon, name):
        self.color, self.material, self.neon, self.name = np.asarray(color, float), material, neon, name
        self.transp = 0.0
        self.hidden = False
        self.decal = False


def rgb(r, g, b):
    return np.array([r, g, b], float) / 255.0


class _Any:
    def __eq__(self, o): return True
    def __hash__(self): return 0


class Tint(Extra):
    """Extra blob with an explicit colour (ignores the pipeline's `like` lookup)."""

    def __init__(self, kind, size, center, k, color, material="SmoothPlastic", neon=False, rounding=0.5, R=None):
        super().__init__(kind, size, center, k, _Any(), rounding, R)
        self._lk = _Like(color, material, neon, "tint")

    @property
    def like(self):
        return self._lk

    @like.setter
    def like(self, v):
        pass


class Cone(Tint):
    """Tapered spike from `base` (radius r) to `tip`.  Rounded tip via marching-cubes smoothing."""

    def __init__(self, base, tip, r, k, color, material="SmoothPlastic", neon=False, blunt=0.0):
        super().__init__("ellipsoid", [0.1, 0.1, 0.1], base, k, color, material, neon)
        self.b, self.t = np.asarray(base, float), np.asarray(tip, float)
        self.r, self.blunt = r, blunt
        self.L = float(np.linalg.norm(self.t - self.b))
        self.u = (self.t - self.b) / self.L

    def shape(self, Q):
        q = Q - self.b
        a = q @ self.u
        rho = np.linalg.norm(q - a[:, None] * self.u, axis=-1)
        rad = self.r * np.clip(1 - a / self.L, 0, 1) ** 0.85 + self.blunt
        d1 = (rho - rad) * 0.9
        return np.maximum(np.maximum(d1, -a - 0.0), a - self.L)


class Fn(Tint):
    """Extra with an arbitrary SDF function (Q -> d)."""

    def __init__(self, fn, k, color, material="SmoothPlastic", neon=False):
        super().__init__("ellipsoid", [0.1, 0.1, 0.1], [0, 0, 0], k, color, material, neon)
        self.fn = fn

    def shape(self, Q):
        return self.fn(Q)


def capsule(A, B, r1, r2=None):
    """Tapered capsule SDF fn between points A, B."""
    A, B = np.asarray(A, np.float32), np.asarray(B, np.float32)
    r2 = r1 if r2 is None else r2
    ab = B - A
    L2 = float(ab @ ab)

    def fn(Q):
        t = np.clip(((Q - A) @ ab) / L2, 0, 1)
        return np.linalg.norm(Q - (A + t[:, None] * ab), axis=-1) - (r1 + (r2 - r1) * t)
    return fn


def surf_point(shape_fns, x, z, y0=4.0, y1=-4.0, n=800):
    """Highest y at (x, z) where min(shapes) crosses zero (top surface)."""
    ys = np.linspace(y0, y1, n).astype(np.float32)
    P = np.stack([np.full(n, x, np.float32), ys, np.full(n, z, np.float32)], -1)
    d = shape_fns[0](P)
    for s in shape_fns[1:]:
        d = np.minimum(d, s(P))
    i = np.nonzero(d < 0)[0]
    return float(ys[i[0]]) if len(i) else 0.0


def sock(ctx, eye, host, color, k=0.06, grow=1.1, back=0.10):
    """Very light eyelid bump: slightly larger than the eyeball and shifted back into the head."""
    e = ctx.shape(eye)
    tc = ctx.shape(host).c
    c = e.c - back * unit(e.c - tc)
    return Tint("ellipsoid", e.half * 2 * grow, c, k, color, R=e.R)


def norm_pt(pt, c, half):
    return (np.asarray(pt) - c) / half


# ------------------------------------------------------------------ custom decals
class Paint:
    """Decal with a custom signed distance: fn(Q)->d (negative = painted)."""

    def __init__(self, fn, color, neon=False, strength=1.0):
        self.fn, self.color, self.neon = fn, np.asarray(color, float), neon
        self.transp = 1.0 - strength

    def lshape(self, Q):
        return self.fn(Q)


def spots(centers, radius):
    C = np.asarray(centers, np.float32)
    R = np.broadcast_to(np.asarray(radius, np.float32), (len(C),))

    def fn(Q):
        d = np.full(len(Q), 9.0, np.float32)
        for c, r in zip(C, R):
            d = np.minimum(d, np.linalg.norm(Q - c, axis=-1) - r)
        return d
    return fn


def dots(cell, rmin, rmax, seed=1, keep=0.6, mask=None, offset=(0, 0, 0)):
    """Scattered round dots (one per Voronoi cell, `keep` = fraction of cells that get a dot)."""
    off = np.asarray(offset, np.float32)

    def fn(Q):
        F1, F2, cid = S.worley((Q + off) / cell, seed, 0.85)
        r = rmin + (rmax - rmin) * hash1(cid * 91.7)
        d = F1 * cell - r
        d = np.where(hash1(cid * 37.3 + 1.1) < keep, d, 1.0)
        if mask is not None:
            d = np.maximum(d, mask(Q))
        return d
    return fn


def voronoi_veins(cell, width, seed=3, offset=(0, 0, 0), warp=0.25, mask=None):
    """Network of thin veins along Voronoi cell borders (3D, so it wraps any shape). Returns SDF-ish fn."""
    off = np.asarray(offset, np.float32)

    def fn(Q):
        P = (Q + off) / cell
        P = P + warp * np.stack([S.vnoise(P * 1.7, seed), S.vnoise(P * 1.7, seed + 5), S.vnoise(P * 1.7, seed + 9)], -1)
        F1, F2, cid = S.worley(P, seed, 0.95)
        vd = (F2 - F1) * 0.5 * cell
        w = width * (0.55 + 0.45 * (S.vnoise(P * 2.3, seed + 3) * 0.5 + 0.5))
        d = vd - w
        if mask is not None:
            d = np.maximum(d, mask(Q))
        return d
    return fn


_installed = False


def install():
    """Wrap pipeline.bake_surface so cfg.paint(g, field) -> [Paint] are appended to the group's decals."""
    global _installed
    if _installed:
        return
    pm = sys.modules.get("__main__")
    if pm is None or not hasattr(pm, "bake_surface"):
        return
    orig = pm.bake_surface

    def wrapped(g, field, geo, decals, occluders, cfg, *a, **kw):
        extra = cfg.paint(g, field) if hasattr(cfg, "paint") else []
        return orig(g, field, geo, list(decals) + list(extra), occluders, cfg, *a, **kw)
    pm.bake_surface = wrapped

    orig_eye = pm.build_eye

    def eye(gname, members, anchor, cfg, log, *a, **kw):
        if getattr(cfg, "eye_gaze_forward", False):        # old buildscript pupils look sideways/backwards: rotate them to -Z
            import re as _re
            balls = [p for p in members if not p.hidden and p.kind == "ellipsoid" and not _re.search(r"Pupil|Glint|Highlight", p.name)]
            ball = max(balls, key=lambda p: np.prod(p.size))
            c = ball.M[:3, 3].copy()
            pup = next((p for p in members if p is not ball and "Pupil" in p.name), None)
            if pup is not None:
                o = pup.M[:3, 3] - c
                a0 = o / np.linalg.norm(o)
                b0 = np.asarray(getattr(cfg, "eye_gaze", (0.0, 0.0, -1.0)), float); b0 = b0 / np.linalg.norm(b0)
                v = np.cross(a0, b0)
                cs = float(a0 @ b0)
                if np.linalg.norm(v) > 1e-6:
                    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
                    Rm = np.eye(3) + K + K @ K / (1 + cs)
                    for p in members:
                        if p is not ball and _re.search(r"Pupil|Glint|Highlight", p.name):
                            p.M = p.M.copy()
                            p.M[:3, 3] = c + Rm @ (p.M[:3, 3] - c)
                            p.cf = p.M if False else p.cf
        return orig_eye(gname, members, anchor, cfg, log, *a, **kw)
    pm.build_eye = eye
    _installed = True


class CreatureCfg(Cfg):
    """Cfg with the runtime decal hook enabled + softer, low-poly friendly defaults."""
    decal_re = r"Blush|Mouth|Smile|Seam|ShellMark|Highlight|Glint|Pupil"
    tex_small = 256

    def __init__(self):
        install()

    def budget(self, g): return 6000 if g == "Body" else 700
    def cells(self, g): return 220 if g == "Body" else 140
    def tex(self, g): return 1024 if g == "Body" else self.tex_small
    def amp(self, g): return 0.010 if g == "Body" else 0.007
    def rounding(self, p): return 0.5

    def paint(self, g, field):
        return []
