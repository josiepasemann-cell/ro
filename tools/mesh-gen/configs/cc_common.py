"""Shared helpers for the creaturesC configs (ObsidianCrab, PhantomJelly, ToxinPuffer, TrenchWisp, VentDrake, VoidHammerhead)."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
from models import *          # noqa: F401,F403  (Cfg, Sculpt, Extra, socket, cheek, pebble, scales, rays, combine, weave, S, np)
import sdf as S               # noqa: F811
import numpy as np


def slit(ctx, at, size, R=None):
    """Extra used only as a cutter (mouth slits, gill slits, nostrils): cut with cut(Q, d, ...)."""
    return Extra("ellipsoid", size, at, 0, "Body", R=R)


def cut(Q, d, cutters, k=0.02):
    for c in cutters:
        d = S.smax(d, -c._sh(Q), k)
    return d


def capsule(ctx, g, up=0.0, down=0.0, w=0.9, like=None):
    """Extra that lengthens a thin vertical ellipsoid part (tentacle segment, leg, tail tip) by `up`/`down` studs so that
    consecutive pieces overlap instead of touching at a point."""
    s = ctx.shape(g)
    h = s.half * 2
    ln = h[1] + up + down
    c = np.array([0, (up - down) / 2, 0.0])
    return Extra("ellipsoid", [h[0] * w, ln, h[2] * w], c, 0.1, like or g)


def top_y(shapes, x, z, y0=4.0, y1=-4.0, n=400):
    ys = np.linspace(y0, y1, n)
    P = np.stack([np.full(n, x), ys, np.full(n, z)], -1)
    d = shapes[0](P)
    for s in shapes[1:]:
        d = np.minimum(d, s(P))
    ins = np.nonzero(d <= 0)[0]
    return float(ys[ins[0]]) if len(ins) else None


def Cut(size, c, R=None):
    return Extra("ellipsoid", size, c, 0, "Body", R=R)
