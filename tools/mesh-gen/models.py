"""Per-model sculpt / style configuration for the mesh pipeline.

Everything is expressed in the *anchor-local* frame of the mesh group (the frame of the original part
that becomes the mesh pivot), so the same code works no matter where the model sits in the world.
"""
import re
import numpy as np
import sdf as S


# ------------------------------------------------------------------ helpers
class Extra:
    """Additional (sculpted) smooth-unioned blob: cheeks, belly, eye sockets ... Coloured like part `like_name`."""

    def __init__(self, kind, size, center, k, like, rounding=0.5, R=None):
        M = np.eye(4)
        M[:3, 3] = center
        if R is not None:
            M[:3, :3] = R
        self.kind, self.size, self.M, self.k, self.like_name, self.rounding = kind, np.asarray(size, float), M, k, like, rounding
        self._sh = S.Shape(kind, self.size, M, rounding)
        self.like = None

    def shape(self, Q):
        return self._sh(Q)


class Sculpt:
    def __init__(self, pre=None, post=None, extras=None, margin=0.0):
        self.pre, self.post, self.extras, self.margin = pre, post, extras or [], margin


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def socket(ctx, eye_part, toward, like, k=0.08, grow=1.35):
    """Soft eyelid/socket bump around an eye so the eyeball sits in the head instead of on it."""
    e = ctx.shape(eye_part)
    tc = ctx.shape(toward).c
    c = e.c - 0.06 * unit(e.c - tc)
    return Extra("ellipsoid", e.half * 2 * grow, c, k, like, R=e.R)


def cheek(ctx, blush, toward, like, k=0.12, grow=1.7, inward=0.5):
    b = ctx.shape(blush)
    tc = ctx.shape(toward).c
    c = b.c - inward * (np.abs(b.half).max()) * unit(b.c - tc)
    return Extra("ellipsoid", np.maximum(b.half * 2 * grow, 0.2), c, k, like, R=b.R)


# ------------------------------------------------------------------ texture patterns: fn(P) -> (height 0..1, brightness mult, roughness add)
def hash1(a):
    return (np.sin(a * 127.1 + 311.7) * 43758.5453) % 1.0


def pebble(size, contrast=0.12, seed=0, rough=0.12):
    def fn(P):
        F1, F2, cid = S.worley(P / size, seed)
        edge = S.smoothstep(0.0, 0.32, F2 - F1)
        h = edge * (0.7 + 0.3 * (1 - np.clip(F1, 0, 1)))
        bright = 1 + contrast * (h - 0.5) + 0.05 * (cid - 0.5)
        return h, bright, rough * (1 - edge)
    return fn


def scales(rad, cell, axis_len=2, n_cells=None, contrast=0.3, seed=1):
    """Fish scales wrapped around the local Z axis (rows of half-shifted round scales)."""
    N = n_cells or max(6, int(round(2 * np.pi * rad / cell)))

    def fn(P):
        ang = np.arctan2(P[:, 1], P[:, 0])
        u = (ang / (2 * np.pi) + 0.5) * N
        v = P[:, 2] / (cell * 0.78)
        row = np.floor(v)
        best = np.full(len(P), 9.0, np.float32); cid = np.zeros(len(P), np.float32); bdv = np.zeros(len(P), np.float32)
        for r in (row - 1, row, row + 1):
            uu = u - 0.5 * (r % 2)
            du = uu - np.round(uu)
            dv = (v - (r + 0.5)) * 0.78
            d = np.hypot(du, dv)
            m = d < best
            best = np.where(m, d, best); bdv = np.where(m, dv, bdv)
            cid = np.where(m, hash1(np.round(uu) * 7.13 + r * 3.7 + seed), cid)
        crown = (1 - S.smoothstep(0.30, 0.62, best)) * S.smoothstep(0.05, 0.2, np.hypot(P[:, 0], P[:, 1]))
        lip = S.smoothstep(-0.1, 0.5, bdv) * (1 - crown) * 0.0
        h = crown
        bright = 1 + contrast * (crown - 0.55) + 0.07 * (cid - 0.5) - 0.10 * S.smoothstep(0.1, 0.5, bdv) * (1 - crown)
        return h.astype(np.float32), bright.astype(np.float32), 0.10 * (1 - crown)
    return fn


def rays(plane, origin, n, contrast=0.16, wob=0.0):
    a, b = plane

    def fn(P):
        ang = np.arctan2(P[:, a] - origin[0], P[:, b] - origin[1])
        r = 0.5 + 0.5 * np.cos(ang * n)
        return r, 1 + contrast * (r - 0.5), 0.08 * (1 - r)
    return fn


def weave(size, contrast=0.1):
    def fn(P):
        q = P / size * 2 * np.pi
        h = 0.5 + 0.25 * (np.sin(q[:, 0]) * np.sin(q[:, 1]) + np.sin(q[:, 1]) * np.sin(q[:, 2]) + np.sin(q[:, 0]) * np.sin(q[:, 2]))
        return h, 1 + contrast * (h - 0.5), 0.0 * h
    return fn


def combine(*fns_w):
    """Blend patterns: [(fn, weight_fn(P) or const)]."""
    def fn(P):
        H = B = R = 0
        for f, w in fns_w:
            ww = w(P) if callable(w) else w
            h, b, r = f(P)
            H = H + ww * h; B = B + ww * (b - 1); R = R + ww * r
        return H, 1 + B, R
    return fn


# ------------------------------------------------------------------ base config
class Cfg:
    name = "?"
    wobble = 0.006            # organic irregularity: fbm amplitude relative to group size
    blend_tau = 0.03          # colour blend width relative to group size
    decal_edge = 0.01
    ao_radius = 0.12
    ao_strength = 1.0
    belly = 1.0
    normal_gain = 1.0
    iris_ratio = 1.25
    iris_color = (0.85, 0.5, 0.1)
    eye_tex = 512
    decal_re = r"Blush|Mouth|Smile|Seam|ShellMark|Highlight|Glint|Pupil"

    def is_decal(self, p):
        return bool(re.search(self.decal_re, p.name)) and not (p.name.startswith("Eye") and p.name in ("Eye1", "Eye2"))

    def rounding(self, p):
        return 0.55

    def k(self, g): return 0.15
    def part_k(self, name, kg): return kg
    def budget(self, g): return 3000
    def cells(self, g): return 200
    def tex(self, g): return 1024
    def amp(self, g): return 0.02

    def sculpt(self, g, ctx, dim): return None
    def prepare(self, g, ctx): pass

    def detail(self, g):
        return lambda mat: {"SmoothPlastic": pebble(0.08), "Slate": pebble(0.1, 0.16), "Foil": pebble(0.12, 0.06),
                            "Fabric": weave(0.06)}.get(mat)


# ------------------------------------------------------------------ GoldGuppy
class GoldGuppy(Cfg):
    name = "GoldGuppy"
    iris_color = (0.9, 0.5, 0.1)
    ao_radius = 0.16

    def k(self, g): return 0.09
    def part_k(self, n, kg): return 0.04 if "Tip" in n else (0.07 if "Lamella" in n else kg)
    def budget(self, g): return {"Body": 4200, "TailFin": 1600}.get(g, 700)
    def cells(self, g): return 220 if g == "Body" else 150
    def tex(self, g): return 1024 if g == "Body" else (512 if g == "TailFin" else 256)
    def amp(self, g): return 0.009 if g == "Body" else 0.010
    def rounding(self, p): return 0.5

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")
            hx, hy, hz = b.half

            def pre(P):                    # taper the rear into a slim tail root, slightly lift the tail
                Q = P.copy()
                s = 1 - 0.46 * S.smoothstep(-0.05, 1.0, P[:, 2] / hz)
                Q[:, 0] = P[:, 0] / s
                Q[:, 1] = (P[:, 1] - 0.07 * S.smoothstep(0.1, 1.0, P[:, 2] / hz) * hy) / (s * 0.98 + 0.02)
                return Q

            def post(Q, d):
                side = S.smoothstep(0.3, 0.7, np.abs(Q[:, 0]) / hx)
                gill = 0.016 * np.exp(-((Q[:, 2] + 0.30 * hz / 0.875) / 0.035) ** 2) * side          # gill crease
                lip = Extra("ellipsoid", [0.30, 0.05, 0.16], [0, -0.16, -hz * 0.985], 0, "Body")._sh(Q)
                d = d + gill
                return S.smax(d, -lip, 0.02)                                                        # mouth slit

            ex = [Extra("ellipsoid", [0.36, 0.28, 0.34], [sx * 0.33, -0.2, -0.55], 0.1, "Body") for sx in (-1, 1)]
            ex.append(Extra("ellipsoid", [0.85, 0.5, 0.9], [0, -0.22, -0.1], 0.2, "Body"))
            return Sculpt(pre, post, ex, margin=0.05)
        if g == "DorsalFin":
            hy = ctx.shape("DorsalFin").half[1]
            return Sculpt(pre=lambda P: np.stack([P[:, 0], P[:, 1], P[:, 2] - 0.35 * P[:, 1]], -1))
        return None

    def detail(self, g):
        if g == "Body":
            return lambda m: scales(0.46, 0.1, contrast=0.2) if m == "Foil" else pebble(0.06, 0.05)
        if g in ("TailFin",):
            return lambda m: rays((1, 2), (0.0, -0.55), 26, 0.22) if m == "Foil" else None
        if g == "DorsalFin":
            return lambda m: rays((1, 2), (-0.35, 0.0), 14, 0.22) if m == "Foil" else None
        if g.startswith("SideFin"):
            return lambda m: rays((0, 2), (0.0, -0.3), 12, 0.22) if m == "Foil" else None
        return super().detail(g)


# ------------------------------------------------------------------ TreasureTurtle
def plate_seeds():
    s = [[0, 1, 0]]
    for ring, n, pol, off in ((1, 5, 36, 0), (2, 10, 66, 0)):
        for k in range(n):
            th, ph = np.radians(pol), np.radians(360 / n * k + off)
            s.append([np.sin(th) * np.sin(ph), np.cos(th), -np.sin(th) * np.cos(ph)])
    return np.array(s, np.float32)


SEEDS = plate_seeds()


def plate_metric(u):
    """u: (N,3) coordinates normalised by the dome's semi-axes.  -> (m, id, angular F1)."""
    un = u / np.maximum(np.linalg.norm(u, axis=-1, keepdims=True), 1e-6)
    dots = un @ SEEDS.T
    i1 = np.argmax(dots, 1)
    f1 = dots[np.arange(len(u)), i1]
    dots[np.arange(len(u)), i1] = -9
    f2 = dots.max(1)
    return f1 - f2, i1, np.arccos(np.clip(f1, -1, 1)), un[:, 1]


class TreasureTurtle(Cfg):
    name = "TreasureTurtle"
    iris_color = (0.45, 0.28, 0.08)
    ao_radius = 0.1
    wobble = 0.004

    def k(self, g): return 0.24 if g == "Body" else 0.1
    def part_k(self, n, kg):
        return {"KeyholeDetail": 0.04, "BeakDetail": 0.06, "ShellRim": 0.10, "ShellLower": 0.14, "TailStub": 0.16,
                "Neck": 0.30, "Head": 0.26, "Shell": 0.12, "ShellCap": 0.18}.get(n, kg)
    def budget(self, g): return 8000 if g == "Body" else 900
    def cells(self, g): return 230 if g == "Body" else 140
    def tex(self, g): return 1024 if g == "Body" else (512 if g == "Head" else 256)
    def amp(self, g): return 0.018 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        shell, cap = ctx.shape("Shell"), ctx.shape("ShellCap")

        def dome(Q):
            return np.minimum(shell(Q), cap(Q))

        def post(Q, d):
            m, _, _, uy = plate_metric((Q - shell.c) / (shell.half * 1.0))
            mask = S.smoothstep(-0.05, 0.3, uy) * S.smoothstep(0.22, 0.04, dome(Q) - d)
            groove = S.smoothstep(0.03, 0.0, m)
            crown = S.smoothstep(0.02, 0.10, m)
            return d + mask * (0.075 * groove - 0.035 * crown)

        ex = [cheek(ctx, f"Blush{i}", "Head", "Head", 0.12, 1.9, 0.6) for i in (1, 2)]
        return Sculpt(None, post, ex, margin=0.1)

    def detail(self, g):
        if g != "Body":
            return lambda m: pebble(0.07, 0.12) if m == "SmoothPlastic" else None
        shell = getattr(self, "_shell", None)
        skin = pebble(0.09, 0.08, 3)
        rock = pebble(0.11, 0.1, 5)
        ctxbox = self

        def plates(P):
            c, half = ctxbox.shell_c, ctxbox.shell_half
            m, i1, ang, uy = plate_metric((P - c) / half)
            mask = S.smoothstep(-0.05, 0.3, uy)
            crown = S.smoothstep(0.0, 0.10, m)
            rings = 0.5 + 0.5 * np.cos(ang * 60.0)
            h = 0.62 * crown + 0.38 * rings * crown
            cid = hash1(i1.astype(np.float32) * 3.31)
            bright = 1 - 0.30 * (1 - S.smoothstep(0.0, 0.05, m)) + 0.08 * (cid - 0.5) + 0.05 * (rings - 0.5) * crown
            hr, br, rr = rock(P)
            h = mask * h + (1 - mask) * hr
            bright = mask * bright + (1 - mask) * br
            return h, bright, 0.2 * (1 - crown) * mask + 0.05

        return lambda m: {"SmoothPlastic": skin, "Slate": plates, "Foil": pebble(0.16, 0.08, 7)}.get(m)

    shell_c = np.zeros(3); shell_half = np.ones(3)

    def prepare(self, g, ctx):
        sh = ctx.shape("Shell")
        self.shell_c, self.shell_half = sh.c.astype(np.float32), sh.half.astype(np.float32)


# ------------------------------------------------------------------ Shopkeeper (crab)
class Shopkeeper(Cfg):
    name = "Shopkeeper"
    iris_color = (0.55, 0.22, 0.05)
    ao_radius = 0.1
    ridges = 16

    def rounding(self, p):
        return {"Head": 0.78, "Satchel": 0.3, "SatchelFlap": 0.4, "EyeStalkL": 0.5}.get(p.name, 0.55)
    def k(self, g): return {"Body": 0.2, "Head": 0.16, "ArmL": 0.12, "ArmR": 0.12}.get(g, 0.1)
    def part_k(self, n, kg):
        return {"Satchel": 0.06, "SatchelFlap": 0.05, "SatchelBuckle": 0.02, "SatchelCoin1": 0.02, "SatchelCoin2": 0.02,
                "SatchelCoin3": 0.02, "EyeStalkL": 0.12, "EyeStalkR": 0.12, "ArmStalkL": 0.18, "ArmStalkR": 0.18}.get(n, kg)
    def budget(self, g): return {"Body": 6500, "Head": 2600, "ArmL": 1400, "ArmR": 1400}.get(g, 700)
    def cells(self, g): return 230 if g == "Body" else 170
    def tex(self, g): return 1024 if g == "Body" else (512 if g == "Head" else 256)
    def amp(self, g): return 0.02 if g == "Body" else 0.01

    def sculpt(self, g, ctx, dim):
        if g == "Body":
            b = ctx.shape("Body")
            hx, hy, hz = b.half
            Rb = b.R

            def post(Q, d):
                q = (Q - b.c) @ Rb
                ang = np.arctan2(q[:, 0] / hx, q[:, 2] / hz)
                rad = np.hypot(q[:, 0] / hx, q[:, 2] / hz)
                top = S.smoothstep(-0.25, 0.25, q[:, 1] / hy) * S.smoothstep(0.15, 0.55, rad)
                ridge = 0.5 + 0.5 * np.cos(ang * Shopkeeper.ridges)
                lip = 0.03 * np.exp(-((q[:, 1] / hy + 0.42) / 0.06) ** 2)
                return d - top * 0.06 * ridge * ridge + lip
            return Sculpt(None, post, [], margin=0.08)
        if g == "Head":
            ex = [cheek(ctx, f"Blush{s}", "Head", "Head", 0.12, 1.7, 0.6) for s in ("L", "R")]
            return Sculpt(None, None, ex, margin=0.05)
        return None

    def detail(self, g):
        if g == "Body":
            b = getattr(self, "_b", None)
            skin = pebble(0.07, 0.10, 2)
            cfg = self

            def shellp(P):
                h, br, r = skin(P)
                ang = np.arctan2(P[:, 0] - cfg.bc[0], P[:, 2] - cfg.bc[2])
                ridge = 0.5 + 0.5 * np.cos(ang * Shopkeeper.ridges)
                top = S.smoothstep(-0.2, 0.3, (P[:, 1] - cfg.bc[1]) / 1.3)
                br = br * (1 - 0.13 * top * (1 - ridge)) * (1 + 0.05 * top * ridge)
                return 0.6 * h + 0.4 * ridge * top, br, r
            return lambda m: {"SmoothPlastic": shellp, "Fabric": weave(0.07, 0.14), "Foil": pebble(0.1, 0.05)}.get(m)
        return lambda m: {"SmoothPlastic": pebble(0.06, 0.1), "Neon": pebble(0.07, 0.05)}.get(m)

    bc = np.zeros(3)

    def prepare(self, g, ctx):
        self.bc = ctx.shape("Body").c.astype(np.float32)


CONFIGS = {"GoldGuppy": GoldGuppy, "TreasureTurtle": TreasureTurtle, "Shopkeeper": Shopkeeper}


def get(name):
    return CONFIGS.get(name, Cfg)()
