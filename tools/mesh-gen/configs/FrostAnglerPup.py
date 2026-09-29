"""FrostAnglerPup: chubby ice-blue angler pup, frost crystal spikes, glowing lure, glassy fins."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "FrostAnglerPup"
    iris_color = (0.25, 0.5, 0.75)
    ao_radius = 0.14
    eye_inset = -0.25
    wobble = 0.005
    blend_tau = 0.02
    decal_re = r"Blush|Mouth|Smile|Seam|Highlight|Glint|Pupil|FrostCrystal"   # crystals become real cones (see sculpt)

    def k(self, g): return 0.2 if g == "Body" else 0.08
    def part_k(self, n, kg): return 0.10 if n == "Belly" else kg
    def budget(self, g): return {"Body": 6000, "LureOrb": 900}.get(g, 700)
    def tex(self, g): return 512 if g == "Body" else (256 if g == "LureOrb" else 256)
    def amp(self, g): return 0.005

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        b = ctx.shape("Body")
        hx, hy, hz = b.half
        ICE = rgb(235, 248, 255)
        BODY = rgb(180, 220, 240)
        ex = []
        for s in (-1, 1):                                                       # chubby cheeks
            ex.append(Tint("ellipsoid", [0.45, 0.4, 0.5], [s * 0.62, -0.27, -0.5], 0.16, BODY))
        ex.append(Tint("ellipsoid", [0.9, 0.30, 0.5], [0, -0.42, -0.75], 0.14, rgb(220, 240, 250)))   # lower lip / chin
        # frost crystal spikes along the back (pointing up and slightly back)
        for (z, h, r, lean) in ((-0.5, 0.36, 0.15, 0.04), (-0.05, 0.52, 0.19, 0.08), (0.5, 0.4, 0.15, 0.12),
                                (0.05, 0.3, 0.09, -0.03)):
            x = 0.0 if z != 0.05 else 0.26
            yb = 0.5
            ex.append(Cone([x, yb, z], [x * 1.3, yb + h, z + lean], r, 0.05, ICE, "Ice", blunt=0.01))
        ex.append(Cone([-0.3, 0.42, 0.25], [-0.36, 0.42 + 0.3, 0.32], 0.09, 0.05, ICE, "Ice", blunt=0.01))
        ex.append(Tint("ellipsoid", [0.36, 0.3, 0.7], [0, 0.0, 1.15], 0.25, BODY))    # tail root nub

        def post(Q, d):
            lip = Extra("ellipsoid", [0.62, 0.05, 0.30], [0, -0.13, -hz * 0.975], 0, "Body")._sh(Q)
            side = S.smoothstep(0.2, 0.7, np.abs(Q[:, 0]) / hx)
            gill = 0.014 * np.exp(-((Q[:, 2] + 0.2) / 0.05) ** 2) * side * S.smoothstep(0.4, -0.2, Q[:, 1] / hy)
            return S.smax(d + gill, -lip, 0.02)
        return Sculpt(None, post, ex, margin=0.15)

    def paint(self, g, field):
        if g != "Body":
            return []
        top = lambda Q: (-Q[:, 1] - 0.05) * 1.0            # only upper half (d>0 below y=-0.05)
        return [Paint(dots(0.22, 0.012, 0.03, 4, 0.55, mask=top), rgb(255, 255, 255), False, 0.75)]

    def detail(self, g):
        fin = lambda m: rays((1, 2), (0.0, -0.1), 14, 0.2) if m in ("Glass",) else None
        if g == "Body":
            return lambda m: {"SmoothPlastic": pebble(0.07, 0.04, 2, 0.04), "Ice": pebble(0.09, 0.05, 6, 0.0)}.get(m)
        if g == "LureOrb":
            return lambda m: pebble(0.05, 0.04, 3, 0.02) if m == "Ice" else None
        return fin
