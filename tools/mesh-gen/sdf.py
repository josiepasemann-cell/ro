"""Signed-distance-field primitives, smooth booleans and cheap procedural noise (numpy, vectorised).

All functions take P as an (N,3) float array in some local frame and return (N,) distances
(negative inside).  Nothing here knows about Roblox; see pipeline.py for the part -> SDF mapping.
"""
import numpy as np


def smin(a, b, k):
    """Polynomial smooth minimum (smooth union)."""
    if k <= 1e-6:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Shape:
    """One Roblox part as an SDF.  kind: box | ellipsoid | cylx | cyly.  M = 4x4 world-from-shape."""

    def __init__(self, kind, size, M, rounding=0.5):
        self.kind = kind
        self.half = np.asarray(size, float) / 2.0
        self.c = np.asarray(M[:3, 3], float)
        self.R = np.asarray(M[:3, :3], float)
        self.rounding = rounding

    def local(self, P):
        return (P - self.c) @ self.R  # == R^T (P - c) for row vectors

    def __call__(self, P):
        q = self.local(P)
        h = self.half
        if self.kind == "box":
            r = self.rounding * h.min()
            w = np.abs(q) - (h - r)
            return np.linalg.norm(np.maximum(w, 0), axis=-1) + np.minimum(w.max(-1), 0) - r
        if self.kind == "ellipsoid":
            k0 = np.linalg.norm(q / h, axis=-1)
            k1 = np.linalg.norm(q / (h * h), axis=-1)
            d = k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
            return np.where(k0 < 1e-3, -h.min(), d)
        ax = 0 if self.kind == "cylx" else 1  # axis of the cylinder
        o = [i for i in range(3) if i != ax]
        ea, eb = h[o[0]], h[o[1]]
        rad = np.sqrt((q[:, o[0]] / ea) ** 2 + (q[:, o[1]] / eb) ** 2) * min(ea, eb)
        Rr, L = min(ea, eb), h[ax]
        r = self.rounding * min(Rr, L)
        w0, w1 = rad - (Rr - r), np.abs(q[:, ax]) - (L - r)
        return np.hypot(np.maximum(w0, 0), np.maximum(w1, 0)) + np.minimum(np.maximum(w0, w1), 0) - r

    def bbox(self):
        """Axis-aligned bounds (in the frame P lives in) of the shape's oriented box."""
        ext = np.abs(self.R) @ self.half
        return self.c - ext, self.c + ext


# ------------------------------------------------------------------ noise
def _hash3(ix, iy, iz, seed=0):
    h = (ix.astype(np.uint32) * np.uint32(374761393)) ^ (iy.astype(np.uint32) * np.uint32(668265263)) \
        ^ (iz.astype(np.uint32) * np.uint32(2147483629)) ^ np.uint32(seed * 1274126177 & 0xFFFFFFFF)
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    h = h ^ (h >> np.uint32(16))
    return h.astype(np.float32) / np.float32(4294967295.0)  # [0,1]


def vnoise(P, seed=0):
    """Smooth 3D value noise in [-1,1] (unit lattice)."""
    P = np.asarray(P, np.float32)
    i = np.floor(P)
    f = P - i
    u = f * f * f * (f * (f * 6 - 15) + 10)
    ix, iy, iz = i[:, 0].astype(np.int64), i[:, 1].astype(np.int64), i[:, 2].astype(np.int64)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                wgt = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + wgt * _hash3(ix + dx, iy + dy, iz + dz, seed)
    return out * 2 - 1


def fbm(P, seed=0, octaves=3):
    a, s, tot = 1.0, 1.0, 0.0
    out = 0.0
    for o in range(octaves):
        out = out + a * vnoise(P * s, seed + o * 17)
        tot += a
        a *= 0.5
        s *= 2.03
    return out / tot


def worley(P, seed=0, jitter=0.9):
    """3D cellular noise on a unit lattice -> (F1, F2, cell_id in [0,1])."""
    P = np.asarray(P, np.float32)
    i = np.floor(P).astype(np.int64)
    f = P - i
    F1 = np.full(len(P), 9.0, np.float32)
    F2 = np.full(len(P), 9.0, np.float32)
    cid = np.zeros(len(P), np.float32)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz
                o = np.stack([_hash3(cx, cy, cz, seed + 1), _hash3(cx, cy, cz, seed + 2), _hash3(cx, cy, cz, seed + 3)], -1)
                pt = np.array([dx, dy, dz], np.float32) + 0.5 + (o - 0.5) * jitter
                d = np.linalg.norm(f - pt, axis=-1)
                closer = d < F1
                F2 = np.where(closer, F1, np.minimum(F2, d))
                cid = np.where(closer, _hash3(cx, cy, cz, seed + 9), cid)
                F1 = np.where(closer, d, F1)
    return F1, F2, cid
