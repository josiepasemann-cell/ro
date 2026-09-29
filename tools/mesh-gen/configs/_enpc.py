"""Shared helpers for the enemy / NPC configs (batch tag enemiesnpcs).  Not a model config itself."""
import re
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import numpy as np
import sdf as S
from models import *  # noqa: F401,F403  (Cfg, Sculpt, Extra, socket, cheek, pebble, scales, rays, weave, combine, hash1, unit)


# ------------------------------------------------------------------ math
def rotx(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def align_y(d):
    """Rotation matrix whose local +Y axis points along d (used for spikes / horns / tusks)."""
    y = np.asarray(d, float)
    y = y / np.linalg.norm(y)
    ref = np.array([0, 0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0, 0])
    x = np.cross(y, ref)
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], 1)


def spike(center, base_dir, length, width, k, like, base_center=None):
    """Ellipsoid 'horn' whose base sits at `center` and that grows along base_dir by `length`."""
    d = np.asarray(base_dir, float)
    d = d / np.linalg.norm(d)
    c = np.asarray(center, float) + d * length * 0.5
    return Extra("ellipsoid", [width, length, width], c, k, like, R=align_y(d))


# ------------------------------------------------------------------ part mutation helpers (run before grouping)
def shift(p, v):
    """Move part by v given in the part's own axes."""
    M = p.M.copy()
    M[:3, 3] = M[:3, 3] + M[:3, :3] @ np.asarray(v, float)
    p.M = M


def shift_w(p, v):
    """Move part by v given in model axes."""
    M = p.M.copy()
    M[:3, 3] = M[:3, 3] + np.asarray(v, float)
    p.M = M


def resize(p, size):
    p.size = np.asarray(size, float)


EYE_RE = re.compile(r"^Eye[12]$|^Eye[12](Pupil|Glint|Highlight)$|^EyePupil[LR]$|^EyeGlint[LR]$|^EyeHighlight[12LR]$")


class StyledCfg(Cfg):
    """Cfg with a `restyle(p)` hook that may mutate parts once (called from is_decal, which the pipeline runs on
    every part before it groups anything).  Lets a config fix source-geometry problems (flat plates, tiny balls,
    stray decals) without touching the buildscripts."""
    eye_scale = 1.0
    eye_tex = 256
    R = np.eye(3)                                   # model rotation (from Body), so shifts can be given in model axes

    def sw(self, p, v):
        shift_w(p, self.R @ np.asarray(v, float))

    def restyle(self, p):
        pass

    def is_decal(self, p):
        if p.name == "Body":
            self.R = p.M[:3, :3].copy()
        if not getattr(p, "_restyled", False):
            p._restyled = True
            if self.eye_scale != 1.0 and EYE_RE.match(p.name):
                p.size = p.size * self.eye_scale
            self.restyle(p)
        return super().is_decal(p)


# ------------------------------------------------------------------ texture patterns
def hammered(size=0.16, contrast=0.2, seed=4):
    """Armour plate / corroded metal: broad hammered dents + fine grit, mildly glossy."""
    a = pebble(size, contrast, seed, 0.25)
    b = pebble(size * 0.35, contrast * 0.5, seed + 3, 0.15)

    def fn(P):
        h1, b1, r1 = a(P)
        h2, b2, r2 = b(P)
        return 0.65 * h1 + 0.35 * h2, 1 + (b1 - 1) + (b2 - 1), 0.5 * (r1 + r2) + 0.1
    return fn


def planks(width=0.22, contrast=0.16, axis=0):
    def fn(P):
        u = P[:, axis] / width
        f = u - np.floor(u)
        seam = S.smoothstep(0.0, 0.08, f) * S.smoothstep(1.0, 0.92, f)
        grain = 0.5 + 0.5 * np.sin(P[:, (axis + 2) % 3] * 38 + 3.1 * hash1(np.floor(u)) * 6)
        h = 0.7 * seam + 0.3 * grain
        return h, 1 + contrast * (h - 0.6) + 0.06 * (hash1(np.floor(u) * 5.1) - 0.5), 0.2 * (1 - seam)
    return fn


def soft_marble(size=0.5, contrast=0.09):
    def fn(P):
        n = S.fbm(P / size, 5, 3)
        v = np.abs(n)
        h = 0.6 + 0.4 * n
        return h, 1 + contrast * (0.5 - v * 2), 0.05 * np.ones(len(P))
    return fn


def ring_bumps(axis_pts, n):
    return None


def fin_rays_x(origin, n, contrast=0.2):
    """Rays for fins that are thin along X (plane Y/Z)."""
    return rays((1, 2), origin, n, contrast)
