"""Shared helpers for the creaturesA configs (SDF cones, curved grooves, brightness patterns)."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import numpy as np
import sdf as S
from models import *


def round_cone(P, a, b, r1, r2):
    """iq's round cone SDF between points a (radius r1) and b (radius r2); P (N,3)."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    ba = b - a; l2 = float(ba @ ba); rr = r1 - r2; a2 = l2 - rr * rr; il2 = 1.0 / l2
    pa = P - a; y = pa @ ba; z = y - l2
    x2 = ((pa * l2 - ba[None] * y[:, None]) ** 2).sum(-1)
    y2 = y * y * l2; z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    return np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
                    np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                             (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))


def groove(Q, d, center, size, curve=0.0, k=0.02, axis=0):
    """Carve a (optionally curved) slit: thin ellipsoid centred on the surface. curve bends it in y along `axis`."""
    Qw = Q.copy()
    Qw[:, 1] = Qw[:, 1] + curve * (Q[:, axis] - center[axis]) ** 2
    e = Extra("ellipsoid", size, center, 0, "Body")._sh(Qw)
    return S.smax(d, -e, k)


def spots(size, thr=0.16, gain=0.5, seed=4, rough=0.0):
    """Brightness freckles (worley cells)."""
    def fn(P):
        F1, F2, cid = S.worley(P / size, seed)
        m = S.smoothstep(thr, thr * 0.4, F1) * (cid > 0.55)
        return 0.6 * m, 1 + gain * m, rough * m
    return fn


def bands(axis, period, amp=0.1, phase=0.0):
    def fn(P):
        w = 0.5 + 0.5 * np.sin(P[:, axis] / period * 2 * np.pi + phase)
        return 0.7 * w, 1 + amp * (w - 0.5) * 2, 0.06 * (1 - w)
    return fn


def mix(*fs):
    """Sum several pattern fns with weight 1 (each returns h, brightness, rough)."""
    def fn(P):
        H = B = R = 0
        for f in fs:
            h, b, r = f(P); H = H + h; B = B + (b - 1); R = R + r
        return H / len(fs), 1 + B, R
    return fn
