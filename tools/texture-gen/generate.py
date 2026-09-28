#!/usr/bin/env python3
"""
Abyssara - Deep Tide Tycoon: procedural texture pack generator.

Writes 512x512 RGBA, seamlessly tileable PNGs to assets/textures/<Key>.png.
Re-run any time:   python3 tools/texture-gen/generate.py [Key ...]
Requires: numpy, Pillow  (pip install numpy pillow)

Design rules
- Everything is computed on a periodic (torus) domain at 1024x1024 and box-
  downsampled 2x to 512, so every texture tiles with no seam and edges are
  anti-aliased.
- Tintable textures are "overlays": RGB is white (highlights) or near-black
  (shadows) and the alpha channel carries the pattern. On a Roblox part the
  part color shows through, the Texture's Color3 tints the highlights.
- Baked-color textures (GoldFoil, CoinPile, LavaCracks, BioVeins) carry their
  own colors because the look depends on them (metal hue, glow gradient).
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

N = 1024          # working resolution (torus)
OUT = 512         # output resolution
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "textures"))

_yy, _xx = np.mgrid[0:N, 0:N].astype(np.float32)
X = _xx + 0.5
Y = _yy + 0.5


# --------------------------------------------------------------------------
# periodic helpers
# --------------------------------------------------------------------------
def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def wrap(d):
    """Signed shortest distance on the torus."""
    return (d + N / 2) % N - N / 2


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def norm01(a):
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a


_FY = np.fft.fftfreq(N)[:, None].astype(np.float32)
_FX = np.fft.fftfreq(N)[None, :].astype(np.float32)


def noise(seed: int, feature: float, ax: float = 1.0, ay: float = 1.0):
    """Periodic smooth noise (Gaussian-filtered white noise), 0..1.
    feature = rough blob size in working pixels; ax/ay stretch the blobs."""
    w = rng(seed).standard_normal((N, N)).astype(np.float32)
    k2 = (_FX * feature * ax) ** 2 + (_FY * feature * ay) ** 2
    f = np.fft.fft2(w) * np.exp(-k2 * 9.0)
    return norm01(np.real(np.fft.ifft2(f)).astype(np.float32))


def blur(a, sigma: float):
    """Periodic Gaussian blur."""
    k2 = (_FX ** 2 + _FY ** 2) * (2 * np.pi * sigma) ** 2
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.exp(-k2 / 2))).astype(np.float32)


def fbm(seed: int, feature: float, octaves: int = 4, ax=1.0, ay=1.0):
    total = np.zeros((N, N), np.float32)
    amp, s, norm = 1.0, feature, 0.0
    for o in range(octaves):
        total += amp * (noise(seed + o * 101, s, ax, ay) - 0.5)
        norm += amp
        amp *= 0.5
        s *= 0.5
    return norm01(total)


def sample(a, sx, sy):
    """Bilinear periodic sampling of a at float coords."""
    x0 = np.floor(sx).astype(np.int64)
    y0 = np.floor(sy).astype(np.int64)
    fx = (sx - x0).astype(np.float32)
    fy = (sy - y0).astype(np.float32)
    x0 %= N
    y0 %= N
    x1 = (x0 + 1) % N
    y1 = (y0 + 1) % N
    return (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x1] * fx * (1 - fy)
            + a[y1, x0] * (1 - fx) * fy + a[y1, x1] * fx * fy)


def voronoi(points):
    """Periodic Voronoi. Returns (F1, edge_distance, cell_id)."""
    f1 = np.full((N, N), 1e9, np.float32)
    f2 = np.full((N, N), 1e9, np.float32)
    v1x = np.zeros((N, N), np.float32)
    v1y = np.zeros((N, N), np.float32)
    v2x = np.zeros((N, N), np.float32)
    v2y = np.zeros((N, N), np.float32)
    cid = np.zeros((N, N), np.int32)
    for i, (px, py) in enumerate(points):
        dx = wrap(X - px)
        dy = wrap(Y - py)
        d = dx * dx + dy * dy
        closer = d < f1
        second = (~closer) & (d < f2)
        # demote old nearest to second
        f2 = np.where(closer, f1, np.where(second, d, f2))
        v2x = np.where(closer, v1x, np.where(second, dx, v2x))
        v2y = np.where(closer, v1y, np.where(second, dy, v2y))
        f1 = np.where(closer, d, f1)
        v1x = np.where(closer, dx, v1x)
        v1y = np.where(closer, dy, v1y)
        cid = np.where(closer, i, cid)
    sep = np.sqrt((v1x - v2x) ** 2 + (v1y - v2y) ** 2) + 1e-6
    edge = (f2 - f1) / (2 * sep)   # exact distance to the cell border
    return np.sqrt(f1), edge, cid


def jitter_grid(nx, ny, jitter, seed, stagger=False):
    r = rng(seed)
    pts = []
    cw, ch = N / nx, N / ny
    for j in range(ny):
        for i in range(nx):
            ox = (0.5 * cw if (stagger and j % 2) else 0.0)
            x = (i + 0.5) * cw + ox + r.uniform(-jitter, jitter) * cw
            y = (j + 0.5) * ch + r.uniform(-jitter, jitter) * ch
            pts.append((x % N, y % N))
    return pts


def random_points(n, seed, min_dist=0.0):
    r = rng(seed)
    pts = []
    tries = 0
    while len(pts) < n and tries < n * 200:
        tries += 1
        p = r.uniform(0, N, 2)
        ok = True
        for q in pts:
            dx = (p[0] - q[0] + N / 2) % N - N / 2
            dy = (p[1] - q[1] + N / 2) % N - N / 2
            if dx * dx + dy * dy < min_dist * min_dist:
                ok = False
                break
        if ok:
            pts.append((p[0], p[1]))
    return pts


def emboss(h, strength=6.0, light=(-0.6, -0.8)):
    """Height -> (highlight, shadow) 0..1 using a top-left light."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    s = -(gx * light[0] + gy * light[1]) * strength
    return np.clip(s, 0, 1), np.clip(-s, 0, 1)


def disc_dist(cx, cy):
    return np.sqrt(wrap(X - cx) ** 2 + wrap(Y - cy) ** 2)


# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------
DARK = 14.0   # shadow gray for overlays


def overlay(light, dark):
    """Combine highlight and shadow coverages into white/near-black RGBA."""
    light = np.clip(light, 0, 1)
    dark = np.clip(dark, 0, 1)
    d_eff = dark * (1 - light)
    a = light + d_eff
    c = np.where(a > 1e-5, (255.0 * light + DARK * d_eff) / np.maximum(a, 1e-5), 255.0)
    return np.stack([c, c, c, a * 255.0], -1)


def baked(rgb, alpha):
    """rgb: (N,N,3) 0..1, alpha: (N,N) 0..1."""
    return np.concatenate([np.clip(rgb, 0, 1) * 255.0,
                           np.clip(alpha, 0, 1)[..., None] * 255.0], -1)


def save(key, img):
    img = img.astype(np.float32)
    # premultiplied box downsample so transparent pixels don't bleed color
    a = img[..., 3:4] / 255.0
    pm = np.concatenate([img[..., :3] * a, a], -1)
    pm = pm.reshape(OUT, 2, OUT, 2, 4).mean((1, 3))
    alpha = pm[..., 3:4]
    rgb = np.where(alpha > 1e-4, pm[..., :3] / np.maximum(alpha, 1e-4), 255.0)
    out = np.concatenate([rgb, alpha * 255.0], -1)
    out = np.clip(np.round(out), 0, 255).astype(np.uint8)
    os.makedirs(OUT_DIR, exist_ok=True)
    Image.fromarray(out, "RGBA").save(os.path.join(OUT_DIR, key + ".png"), optimize=True)


def ramp(t, stops):
    """Piecewise-linear color ramp. stops: [(pos, (r,g,b) 0..255)]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        f = ((t - p0) / max(p1 - p0, 1e-6))[..., None]
        col = np.array(c0, np.float32) * (1 - f) + np.array(c1, np.float32) * f
        out = np.where(m[..., None], col, out)
    return out / 255.0


# --------------------------------------------------------------------------
# textures
# --------------------------------------------------------------------------
def scales(s, seed):
    """Overlapping fish scales: circles of radius s/2 on a pitch of s, rows
    every s/2 offset by half a scale; lower rows overlap upper rows, so only
    the rounded lower edge of each scale shows. s = pitch (working px)."""
    hs = s / 2
    r = s / 2
    base = np.floor(Y / hs)
    t_map = np.ones((N, N), np.float32)
    dy_map = np.zeros((N, N), np.float32)
    shade = np.zeros((N, N), np.float32)
    var = rng(seed).uniform(0.0, 1.0, 4096)
    for o in range(-3, 4):
        j = base + o
        cy = j * hs
        off = np.mod(j, 2) * (s / 2)
        dx = np.mod(X - off, s) - s / 2
        dy = Y - cy
        d = np.sqrt(dx * dx + dy * dy)
        inside = d < r
        col = np.floor((X - off) / s)
        # index per-scale variation modulo the tile's scale counts -> seamless
        v = var[(np.mod(col, N // s) * 64 + np.mod(j, N // hs)).astype(np.int64)]
        t_map = np.where(inside, d / r, t_map)
        dy_map = np.where(inside, dy / r, dy_map)
        shade = np.where(inside, v, shade)
    t = t_map
    outline = smoothstep(0.86, 0.97, t)
    # soft sheen toward the upper-middle of every visible crescent
    sheen = smoothstep(0.85, 0.35, t) * smoothstep(-0.2, 0.45, dy_map)
    edge_hi = smoothstep(0.66, 0.8, t) * smoothstep(0.9, 0.8, t) * smoothstep(0.0, 0.6, dy_map)
    light = sheen * 0.30 + edge_hi * 0.45 + shade * 0.10
    dark = outline * 0.8 + smoothstep(0.2, -0.4, dy_map) * 0.25 * (1 - outline)
    return overlay(light, dark)


def tex_FishScales():
    return scales(128, 11)


def tex_FishScalesFine():
    return scales(64, 12)


def tex_SharkSkin():
    mott = fbm(21, 260, 3)
    streak = noise(22, 60, ax=3.0, ay=0.25)  # long horizontal streaks
    # tiny staggered denticles
    s = 32
    j = np.floor(Y / (s * 0.75))
    off = np.mod(j, 2) * s / 2
    dx = np.mod(X - off, s) - s / 2
    dy = np.mod(Y, s * 0.75) - s * 0.375
    d = np.sqrt((dx / 1.6) ** 2 + dy ** 2)
    dent = smoothstep(7, 4, d) * (0.5 + 0.5 * noise(23, 30))
    hl, sh = emboss(blur(dent, 1.0), 3.0)
    light = smoothstep(0.55, 0.9, mott) * 0.18 + hl * 0.35 + smoothstep(0.6, 0.9, streak) * 0.10
    dark = smoothstep(0.45, 0.1, mott) * 0.22 + sh * 0.35
    return overlay(light, dark)


def tex_JellyMembrane():
    pts = jitter_grid(7, 7, 0.35, 31, stagger=True)
    f1, edge, cid = voronoi(pts)
    lines = smoothstep(7, 1.5, edge)
    glow = smoothstep(40, 0, edge)
    blob = fbm(32, 200, 3)
    center = smoothstep(90, 0, f1)
    light = lines * 0.55 + glow * 0.18 + smoothstep(0.5, 0.95, blob) * 0.20 + center * 0.08
    dark = smoothstep(0.45, 0.05, blob) * 0.10
    return overlay(light, dark)


def tex_CrabShell():
    h = np.zeros((N, N), np.float32)
    pts = random_points(160, 41, 44)
    r = rng(42)
    for (cx, cy) in pts:
        rad = r.uniform(12, 30)
        d = disc_dist(cx, cy)
        h = np.maximum(h, np.sqrt(np.clip(1 - (d / rad) ** 2, 0, 1)) * rad / 30)
    mott = fbm(43, 180, 3)
    hl, sh = emboss(blur(h, 1.0), 14.0)
    tip = smoothstep(0.75, 1.0, h)
    light = hl * 0.6 + tip * 0.25 + smoothstep(0.6, 0.95, mott) * 0.12
    dark = sh * 0.55 + smoothstep(0.4, 0.05, mott) * 0.25
    return overlay(light, dark)


def tex_IsopodPlates():
    band = 128                       # 8 plates per tile
    wav = 14 * np.sin(2 * np.pi * X / N * 2)   # plates bow gently
    yy = Y + wav
    t = np.mod(yy, band) / band      # 0 top of plate .. 1 bottom edge
    h = np.where(t < 0.9, t * 0.9, (1 - t) * 8)   # rises to the overlapping lip
    pits = fbm(51, 40, 2)
    hl, sh = emboss(blur(h, 1.5), 55.0)
    seam = smoothstep(0.93, 0.985, t) * smoothstep(1.0, 0.985, t)
    edge_light = smoothstep(0.72, 0.88, t) * smoothstep(0.93, 0.88, t)
    light = hl * 0.4 + edge_light * 0.35 + smoothstep(0.7, 0.95, pits) * 0.10
    dark = sh * 0.4 + smoothstep(0.9, 0.99, t) * 0.7 + (1 - t) * 0.12 + smoothstep(0.3, 0.05, pits) * 0.12
    return overlay(light, dark + seam * 0.2)


def tex_TurtleShellHex():
    pts = jitter_grid(4, 4, 0.08, 61, stagger=True)
    f1, edge, cid = voronoi(pts)
    groove = smoothstep(12, 4, edge)
    rings = 0.5 + 0.5 * np.cos(edge / 14.0 * 2 * np.pi)
    rings = rings * smoothstep(20, 40, edge) * smoothstep(170, 60, edge)
    hl, sh = emboss(blur(np.clip(edge, 0, 60) / 60, 3), 60.0)
    center = smoothstep(90, 10, f1)
    light = hl * 0.35 + center * 0.22 + rings * 0.10
    dark = groove * 0.85 + sh * 0.3 + (1 - rings) * smoothstep(20, 40, edge) * 0.08
    return overlay(light, dark)


def tex_CoralPorous():
    pts = random_points(240, 71, 48)
    f1, edge, cid = voronoi(pts)
    r = rng(72).uniform(9, 17, len(pts)).astype(np.float32)
    rad = r[cid]
    pore = smoothstep(rad, rad * 0.55, f1)
    lip = smoothstep(rad * 0.7, rad, f1) * smoothstep(rad * 1.6, rad, f1)
    ridge = smoothstep(4, 14, edge)
    h = lip * 0.8 + ridge * 0.3 - pore * 0.8
    hl, sh = emboss(blur(h, 1.2), 6.0)
    light = hl * 0.45 + lip * 0.30
    dark = pore * 0.8 + sh * 0.4 + smoothstep(8, 0, edge) * 0.15
    return overlay(light, dark)


def tex_CrystalFacets():
    pts = random_points(70, 81, 90)
    f1, edge, cid = voronoi(pts)
    r = rng(82)
    bright = r.uniform(0, 1, len(pts)).astype(np.float32)[cid]
    gx = r.uniform(-1, 1, len(pts)).astype(np.float32)[cid]
    gy = r.uniform(-1, 1, len(pts)).astype(np.float32)[cid]
    grad = (wrap(X) * 0 + 0.5 + 0.35 * np.tanh((gx * X + gy * Y) * 0))  # flat facets
    edge_line = smoothstep(4, 1.2, edge)
    edge_glow = smoothstep(18, 0, edge)
    light = bright * 0.38 + edge_line * 0.75 + edge_glow * 0.12 + grad * 0.0
    dark = (1 - bright) * 0.25 * smoothstep(3, 8, edge)
    # a few sparkles
    sp = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(14, 83, 150):
        dx, dy = np.abs(wrap(X - cx)), np.abs(wrap(Y - cy))
        star = smoothstep(2.5, 0, dx) * smoothstep(22, 0, dy) + smoothstep(2.5, 0, dy) * smoothstep(22, 0, dx)
        sp = np.maximum(sp, star + smoothstep(7, 0, np.sqrt(dx * dx + dy * dy)))
    return overlay(np.clip(light + sp, 0, 1), dark)


def tex_GoldFoil():
    pts = random_points(130, 91, 60)
    f1, edge, cid = voronoi(pts)
    b = rng(92).uniform(0, 1, len(pts)).astype(np.float32)[cid]
    wrinkle = fbm(93, 120, 4)
    t = 0.35 + b * 0.35 + (wrinkle - 0.5) * 0.35
    crease = smoothstep(3.5, 0.8, edge)
    t = t - crease * 0.25 + smoothstep(10, 3, edge) * 0.12
    spark = smoothstep(0.82, 0.95, noise(94, 18)) * 0.35
    t = np.clip(t + spark, 0, 1)
    rgb = ramp(t, [(0.0, (92, 52, 8)), (0.35, (184, 120, 22)), (0.6, (240, 186, 60)),
                   (0.85, (255, 226, 130)), (1.0, (255, 250, 220))])
    return baked(rgb, np.ones((N, N), np.float32))


def tex_CoinPile():
    rgb = ramp(fbm(101, 160, 2) * 0.25, [(0, (54, 30, 6)), (1, (120, 72, 14))])
    r = rng(102)
    coins = [(r.uniform(0, N), r.uniform(0, N), r.uniform(46, 64)) for _ in range(170)]
    for (cx, cy, rad) in coins:
        dx, dy = wrap(X - cx), wrap(Y - cy) * 1.25   # slightly tilted coins
        d = np.sqrt(dx * dx + dy * dy)
        if True:
            m = smoothstep(rad + 1.2, rad - 1.2, d)
            rimm = smoothstep(rad * 0.78, rad * 0.84, d)
            inner = smoothstep(rad * 0.52, rad * 0.46, d)
            # face shading: lit from top-left
            lit = 0.55 - (dx * 0.6 + dy * 0.8) / rad * 0.25
            t = lit + rimm * 0.18 - (smoothstep(rad * 0.70, rad * 0.76, d) * (1 - rimm)) * 0.25
            t = t + inner * 0.12
            # embossed star/shell dot in the middle
            star = smoothstep(rad * 0.16, rad * 0.10, d) * 0.2
            t = np.clip(t + star, 0, 1)
            col = ramp(t, [(0.0, (120, 70, 10)), (0.4, (214, 150, 34)), (0.7, (250, 204, 80)),
                           (1.0, (255, 246, 200))])
            # thin dark outline so coins read separately
            out = smoothstep(rad - 3.5, rad - 1.0, d) * m
            col = col * (1 - out[..., None] * 0.6)
            rgb = rgb * (1 - m[..., None]) + col * m[..., None]
    # glints
    for (cx, cy) in random_points(12, 103, 180):
        dx, dy = np.abs(wrap(X - cx)), np.abs(wrap(Y - cy))
        star = smoothstep(2.5, 0, dx) * smoothstep(26, 0, dy) + smoothstep(2.5, 0, dy) * smoothstep(26, 0, dx)
        star = np.clip(star + smoothstep(6, 0, np.sqrt(dx * dx + dy * dy)), 0, 1)
        rgb = rgb * (1 - star[..., None]) + star[..., None]
    return baked(rgb, np.ones((N, N), np.float32))


def tex_IceFrost():
    f1, e1, _ = voronoi(random_points(55, 111, 100))
    f2, e2, _ = voronoi(random_points(200, 112, 50))
    cracks = smoothstep(3.0, 0.8, e1) * 0.8 + smoothstep(2.0, 0.6, e2) * 0.4
    frost = fbm(113, 150, 4)
    speck = smoothstep(0.78, 0.9, noise(114, 8)) * 0.35
    light = cracks + smoothstep(0.45, 0.9, frost) * 0.40 + speck + smoothstep(16, 0, e1) * 0.10
    dark = smoothstep(0.35, 0.05, frost) * 0.10
    return overlay(light, dark)


def tex_LavaCracks():
    wx = (noise(121, 200) - 0.5) * 70
    wy = (noise(122, 200) - 0.5) * 70
    pts = random_points(34, 123, 130)
    # warped voronoi: evaluate edge on warped coords by sampling
    f1, edge, cid = voronoi(pts)
    edge = sample(edge, X + wx - 0.5, Y + wy - 0.5)
    fine = smoothstep(0.5, 0.0, np.abs(noise(124, 60) - 0.5)) * 0.0
    core = smoothstep(4.0, 1.0, edge)
    glow = smoothstep(22, 0, edge)
    heat = np.clip(core * 0.7 + glow * 0.6, 0, 1)
    rgb_glow = ramp(heat, [(0.0, (120, 20, 0)), (0.35, (230, 70, 10)), (0.7, (255, 150, 30)),
                           (1.0, (255, 240, 170))])
    crust_noise = fbm(125, 90, 3)
    crust_rgb = ramp(crust_noise, [(0, (20, 14, 14)), (1, (70, 50, 46))])
    crust_a = 0.35 + crust_noise * 0.25
    ga = np.clip(glow * 1.2, 0, 1)
    rgb = crust_rgb * (1 - ga[..., None]) + rgb_glow * ga[..., None]
    alpha = np.maximum(crust_a, ga) + fine
    return baked(rgb, alpha)


def tex_GhostWisp():
    base = fbm(131, 300, 3)
    wx = (noise(132, 260) - 0.5) * 260
    wy = (noise(133, 260) - 0.5) * 160
    s = sample(base, X + wx, Y + wy)
    band = 0.5 + 0.5 * np.sin(s * 2 * np.pi * 4.0)
    wisp = smoothstep(0.55, 0.98, band) * smoothstep(0.2, 0.6, noise(134, 280))
    soft = blur(wisp, 6)
    light = wisp * 0.45 + soft * 0.35 + smoothstep(0.93, 0.99, band) * 0.25
    return overlay(light, np.zeros_like(light))


def tex_MothWing():
    veins_pts = jitter_grid(5, 3, 0.25, 141)
    f1, edge, cid = voronoi(veins_pts)
    veins = smoothstep(4.5, 1.2, edge)
    # eyespots on a staggered lattice (2 x 2 per tile)
    eyes_l = np.zeros((N, N), np.float32)
    eyes_d = np.zeros((N, N), np.float32)
    for (cx, cy) in [(256, 256), (768, 768), (768, 200), (256, 800)]:
        big = (cx + cy) % 3 == 0
        rad = 95 if big else 60
        d = disc_dist(cx, cy) / rad
        eyes_d = np.maximum(eyes_d, smoothstep(1.0, 0.92, d) * smoothstep(0.62, 0.7, d) * 0.9)
        eyes_l = np.maximum(eyes_l, smoothstep(0.62, 0.55, d) * smoothstep(0.30, 0.36, d) * 0.7)
        eyes_d = np.maximum(eyes_d, smoothstep(0.32, 0.26, d) * 0.85)
        eyes_l = np.maximum(eyes_l, smoothstep(0.12, 0.06, disc_dist(cx - rad * 0.1, cy - rad * 0.1) / rad) * 0.95)
    dust = smoothstep(0.6, 0.95, noise(142, 6)) * 0.15
    bands = smoothstep(0.55, 0.7, noise(143, 140, ax=0.4, ay=2.0)) * 0.18
    light = eyes_l + dust + bands
    dark = np.maximum(eyes_d, veins * 0.55)
    return overlay(light, dark)


def tex_EelStripes():
    k, m = 8, 2
    phase = Y / N * k + 0.18 * np.sin(2 * np.pi * X / N * m) + 0.05 * np.sin(2 * np.pi * X / N * 5)
    s = np.mod(phase, 1.0)
    stripe = smoothstep(0.02, 0.06, s) * smoothstep(0.42, 0.38, s)
    edge_hi = smoothstep(0.04, 0.08, s) * smoothstep(0.14, 0.10, s)
    dots = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(60, 151, 70):
        dots = np.maximum(dots, smoothstep(7, 4, disc_dist(cx, cy)))
    dots = dots * (1 - stripe)
    light = stripe * 0.45 + edge_hi * 0.35 + dots * 0.55
    dark = (1 - stripe) * 0.10 + smoothstep(0.42, 0.46, s) * smoothstep(0.52, 0.46, s) * 0.5
    return overlay(light, dark)


def tex_SlugSpots():
    light = np.zeros((N, N), np.float32)
    dark = np.zeros((N, N), np.float32)
    r = rng(161)
    for (cx, cy) in random_points(55, 162, 95):
        rad = r.uniform(18, 42)
        d = disc_dist(cx, cy) / rad
        dark = np.maximum(dark, smoothstep(1.0, 0.92, d) * smoothstep(0.72, 0.8, d) * 0.8)
        light = np.maximum(light, smoothstep(0.78, 0.7, d) * 0.75)
        light = np.maximum(light, smoothstep(0.28, 0.12, disc_dist(cx - rad * 0.3, cy - rad * 0.3) / rad))
    for (cx, cy) in random_points(160, 163, 30):
        light = np.maximum(light, smoothstep(5, 3, disc_dist(cx, cy)) * 0.5)
    sheen = smoothstep(0.55, 0.9, fbm(164, 220, 2)) * 0.12
    return overlay(light + sheen, dark)


def tex_ToxicBlotches():
    n = fbm(171, 80, 4)
    wob = (noise(172, 80) - 0.5) * 0.08
    v = n + wob
    blob = smoothstep(0.58, 0.61, v)
    ring = smoothstep(0.54, 0.57, v) * smoothstep(0.61, 0.58, v)
    inner = smoothstep(0.68, 0.72, v)
    small = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(70, 173, 60):
        small = np.maximum(small, smoothstep(9, 6, disc_dist(cx, cy)))
    small = small * (1 - smoothstep(0.5, 0.56, v))
    light = blob * 0.55 + inner * 0.25 + small * 0.5
    dark = ring * 0.8 + smoothstep(0.4, 0.2, v) * 0.12
    return overlay(light, dark)


def panel_seams(cell_x, cell_y, width=3.0):
    """Returns distances to panel seams for a regular grid (periodic)."""
    ex = np.minimum(np.mod(X, cell_x), cell_x - np.mod(X, cell_x))
    ey = np.minimum(np.mod(Y, cell_y), cell_y - np.mod(Y, cell_y))
    return ex, ey


def tex_MetalPanels():
    cell = 256
    ex, ey = panel_seams(cell, cell)
    e = np.minimum(ex, ey)
    # sub-split every other panel horizontally
    col = np.floor(X / cell)
    row = np.floor(Y / cell)
    split = np.mod(col + row, 2) == 1
    ey2 = np.abs(np.mod(Y, cell) - cell / 2)
    e = np.where(split, np.minimum(e, np.where(np.mod(X, cell) > 0, ey2, 999)), e)
    seam = smoothstep(4, 2, e)
    bevel_hi = smoothstep(4, 6, e) * smoothstep(10, 6, e)
    brushed = noise(181, 40, ax=4.0, ay=0.15)
    per_panel = rng(182).uniform(0, 1, 64).astype(np.float32)[
        (np.mod(col, 8) * 8 + np.mod(row * 2 + (split & (np.mod(Y, cell) > cell / 2)), 8)).astype(np.int64)]
    bolts = np.zeros((N, N), np.float32)
    bolt_hi = np.zeros((N, N), np.float32)
    for bx in range(0, N, cell):
        for by in range(0, N, cell):
            for (ox, oy) in [(16, 16), (cell - 16, 16), (16, cell - 16), (cell - 16, cell - 16)]:
                d = disc_dist(bx + ox, by + oy)
                bolts = np.maximum(bolts, smoothstep(7, 5, d) * 0.6)
                bolt_hi = np.maximum(bolt_hi, smoothstep(3.5, 1, disc_dist(bx + ox - 2, by + oy - 2)))
    light = bevel_hi * 0.35 + (brushed - 0.5) * 0.12 + 0.06 + per_panel * 0.10 + bolt_hi * 0.7
    dark = seam * 0.85 + bolts * (1 - bolt_hi) + smoothstep(0.35, 0.1, brushed) * 0.08
    return overlay(np.clip(light, 0, 1), dark)


def tex_RivetedPlates():
    cw, ch = 256, 170.666666  # 4 x 6 plates, rows staggered
    row = np.floor(Y / ch)
    off = np.mod(row, 2) * cw / 2
    lx = np.mod(X - off, cw)
    ly = np.mod(Y, ch)
    ex = np.minimum(lx, cw - lx)
    ey = np.minimum(ly, ch - ly)
    e = np.minimum(ex, ey)
    seam = smoothstep(4, 1.5, e)
    # overlapping lip: bottom edge of each plate casts a shadow on the next
    lip_shadow = smoothstep(14, 0, ly) * 0.35
    lip_hi = smoothstep(ch - 12, ch - 5, ly) * smoothstep(ch - 1, ch - 4, ly) * 0.45
    rivets = np.zeros((N, N), np.float32)
    rivet_hi = np.zeros((N, N), np.float32)
    rivet_sh = np.zeros((N, N), np.float32)
    # rivets along each plate's top and bottom edge, evenly every 32 px
    for r_i in range(6):
        y0 = r_i * ch
        o = (r_i % 2) * cw / 2
        for yy in (y0 + 14, y0 + ch - 16):
            for k in range(0, N, 32):
                cx = k + 16 + o
                rivets = np.maximum(rivets, smoothstep(6.5, 5, disc_dist(cx, yy)))
                rivet_hi = np.maximum(rivet_hi, smoothstep(3.5, 1, disc_dist(cx - 1.8, yy - 1.8)))
                rivet_sh = np.maximum(rivet_sh, smoothstep(7.5, 5.5, disc_dist(cx + 2.5, yy + 2.5)) * (1 - smoothstep(6.5, 5, disc_dist(cx, yy))))
    grime = fbm(191, 160, 3)
    light = lip_hi + rivets * 0.30 + rivet_hi * 0.75 + smoothstep(0.6, 0.9, grime) * 0.10
    dark = seam * 0.8 + lip_shadow + rivet_sh * 0.6 + smoothstep(0.4, 0.1, grime) * 0.15
    return overlay(np.clip(light, 0, 1), np.clip(dark, 0, 1))


def tex_WoodPlanks():
    ph = 128                     # 8 planks per tile
    row = np.floor(Y / ph)
    r = rng(201)
    plen = 512
    offs = r.integers(0, 8, 64) * 64
    off = offs[np.mod(row, 64).astype(np.int64)].astype(np.float32)
    lx = np.mod(X + off, plen)
    ly = np.mod(Y, ph)
    end_d = np.minimum(lx, plen - lx)
    gap = smoothstep(4, 1.5, np.minimum(np.minimum(ly, ph - ly), end_d))
    # grain: stretched noise + warped stripes along X
    gn = noise(202, 50, ax=4.0, ay=0.4)
    stripes = 0.5 + 0.5 * np.sin((Y / N * 64 + gn * 3.0 + row * 0.37) * 2 * np.pi)
    grain = smoothstep(0.75, 0.95, stripes)
    knots = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(6, 203, 250):
        d = np.sqrt((wrap(X - cx) / 2.2) ** 2 + wrap(Y - cy) ** 2)
        knots = np.maximum(knots, smoothstep(14, 9, d) * 0.6 + smoothstep(22, 18, d) * smoothstep(14, 18, d) * 0.4)
    tone = rng(204).uniform(0, 1, 64).astype(np.float32)[np.mod(row, 64).astype(np.int64)]
    nails = np.zeros((N, N), np.float32)
    for rr in range(8):
        for xx in (0, 256):
            base = xx - offs[rr] + 20
            for yy in (rr * ph + 26, rr * ph + ph - 26):
                nails = np.maximum(nails, smoothstep(5, 3, disc_dist(base % N, yy)))
    top_hi = smoothstep(4, 6, ly) * smoothstep(12, 6, ly)
    light = top_hi * 0.30 + tone * 0.12 + smoothstep(0.3, 0.1, stripes) * 0.08
    dark = gap * 0.9 + grain * 0.30 + knots + nails * 0.7 + (1 - tone) * 0.10 + smoothstep(ph - 16, ph - 4, ly) * 0.15
    return overlay(light, dark)


def tex_StoneTiles():
    pts = jitter_grid(5, 5, 0.3, 211)
    f1, edge, cid = voronoi(pts)
    tone = rng(212).uniform(0, 1, len(pts)).astype(np.float32)[cid]
    mortar = smoothstep(7, 4, edge)
    h = smoothstep(4, 18, edge)
    hl, sh = emboss(blur(h, 2), 22.0)
    rough = fbm(213, 70, 3)
    light = hl * 0.45 + tone * 0.15 + smoothstep(0.65, 0.9, rough) * 0.12
    dark = mortar * 0.8 + sh * 0.4 + (1 - tone) * 0.12 + smoothstep(0.35, 0.1, rough) * 0.15
    return overlay(light, dark)


def tex_BasaltRock():
    pts = jitter_grid(6, 7, 0.22, 221, stagger=True)
    f1, edge, cid = voronoi(pts)
    tone = rng(222).uniform(0, 1, len(pts)).astype(np.float32)[cid]
    groove = smoothstep(5, 2, edge)
    h = smoothstep(2, 12, edge) + (fbm(223, 60, 3) - 0.5) * 0.3
    hl, sh = emboss(blur(h, 1.5), 16.0)
    crack_f1, crack_e, _ = voronoi(random_points(90, 224, 70))
    crack = smoothstep(1.6, 0.4, crack_e) * smoothstep(0.55, 0.65, noise(225, 60)) * smoothstep(3, 10, edge)
    pits = smoothstep(0.82, 0.9, noise(226, 10)) * 0.4
    light = hl * 0.35 + tone * 0.10
    dark = groove * 0.9 + sh * 0.35 + (1 - tone) * 0.18 + crack * 0.6 + pits
    return overlay(light, dark)


def tex_SandRipples():
    k, m = 10, 3
    warp = 0.25 * np.sin(2 * np.pi * (X / N * m)) + 0.35 * (noise(231, 300) - 0.5)
    # the noise term is periodic so the phase stays periodic
    phase = Y / N * k + warp
    s = np.mod(phase, 1.0)
    # asymmetric ripple: gentle upslope, steep lee slope
    h = np.where(s < 0.75, s / 0.75, (1 - s) / 0.25)
    hl, sh = emboss(blur(h.astype(np.float32), 2), 40.0)
    grains = smoothstep(0.7, 0.85, noise(232, 3)) * 0.18
    dgrains = smoothstep(0.3, 0.15, noise(233, 3)) * 0.12
    light = hl * 0.45 + grains + smoothstep(0.6, 0.72, s) * smoothstep(0.78, 0.72, s) * 0.2
    dark = sh * 0.45 + dgrains
    return overlay(light, dark)


def tex_KelpFibers():
    warp = noise(241, 110, ax=0.35, ay=3.0)     # varies slowly along V
    stripes = 0.5 + 0.5 * np.sin(2 * np.pi * (X / N * 36 + warp * 3.0))
    fine = 0.5 + 0.5 * np.sin(2 * np.pi * (X / N * 110 + warp * 7.0))
    rib = 0.5 + 0.5 * np.cos(2 * np.pi * (X / N * 2 + (warp - 0.5) * 0.6))
    rib_line = smoothstep(0.985, 0.999, rib)
    bulge = fbm(243, 200, 2)
    light = (smoothstep(0.75, 0.97, stripes) * 0.28 + smoothstep(0.8, 1.0, fine) * 0.10
             + rib_line * 0.55 + smoothstep(0.6, 0.9, bulge) * 0.12)
    dark = (smoothstep(0.3, 0.03, stripes) * 0.25 + smoothstep(0.93, 0.975, rib) * (1 - rib_line) * 0.35
            + smoothstep(0.35, 0.1, bulge) * 0.12)
    # air bladder dots
    for (cx, cy) in random_points(10, 244, 250):
        d = np.sqrt(wrap(X - cx) ** 2 + (wrap(Y - cy) / 1.6) ** 2)
        light = np.maximum(light, smoothstep(12, 9, d) * smoothstep(3, 7, d) * 0.6)
        light = np.maximum(light, smoothstep(4, 1, disc_dist(cx - 4, cy - 6)) * 0.8)
    return overlay(light, dark)


def tex_EggSpeckle():
    light = np.zeros((N, N), np.float32)
    dark = np.zeros((N, N), np.float32)
    r = rng(251)
    for (cx, cy) in random_points(140, 252, 40):
        rad = r.uniform(5, 16)
        sx = r.uniform(0.8, 1.3)
        d = np.sqrt((wrap(X - cx) / sx) ** 2 + wrap(Y - cy) ** 2)
        dark = np.maximum(dark, smoothstep(rad, rad * 0.7, d) * r.uniform(0.35, 0.7))
    for (cx, cy) in random_points(60, 253, 60):
        rad = r.uniform(5, 11)
        light = np.maximum(light, smoothstep(rad, rad * 0.6, disc_dist(cx, cy)) * 0.55)
    tiny = smoothstep(0.8, 0.88, noise(254, 5)) * 0.3
    sheen = smoothstep(0.55, 0.95, fbm(255, 260, 2)) * 0.12
    return overlay(light + sheen, dark + tiny)


def _rune_strokes(kind, cx, cy, s):
    """Returns list of line segments / circles for simple abstract glyphs."""
    L = []
    if kind == 0:   # circle with dot
        L.append(("c", cx, cy, s * 0.8))
        L.append(("d", cx, cy, s * 0.18))
    elif kind == 1:  # triangle
        p = [(cx, cy - s * 0.85), (cx + s * 0.8, cy + s * 0.6), (cx - s * 0.8, cy + s * 0.6)]
        L += [("l", *p[0], *p[1]), ("l", *p[1], *p[2]), ("l", *p[2], *p[0])]
    elif kind == 2:  # wave / tide
        prev = None
        for i in range(13):
            t = i / 12
            x = cx - s * 0.9 + t * s * 1.8
            y = cy + np.sin(t * 2 * np.pi * 1.5) * s * 0.35
            if prev:
                L.append(("l", *prev, x, y))
            prev = (x, y)
        L.append(("d", cx, cy - s * 0.7, s * 0.14))
    elif kind == 3:  # diamond with cross
        p = [(cx, cy - s * 0.9), (cx + s * 0.7, cy), (cx, cy + s * 0.9), (cx - s * 0.7, cy)]
        L += [("l", *p[i], *p[(i + 1) % 4]) for i in range(4)]
        L.append(("l", cx, cy - s * 0.4, cx, cy + s * 0.4))
    elif kind == 4:  # spiral
        prev = None
        for i in range(40):
            t = i / 39
            a = t * 2 * np.pi * 1.8
            rr = s * (0.1 + 0.75 * t)
            x, y = cx + np.cos(a) * rr, cy + np.sin(a) * rr
            if prev:
                L.append(("l", *prev, x, y))
            prev = (x, y)
    elif kind == 5:  # star-fish / 3 spokes
        for k in range(5):
            a = -np.pi / 2 + k * 2 * np.pi / 5
            L.append(("l", cx, cy, cx + np.cos(a) * s * 0.85, cy + np.sin(a) * s * 0.85))
        L.append(("d", cx, cy, s * 0.15))
    elif kind == 6:  # eye / moon
        L.append(("c", cx, cy, s * 0.75))
        L.append(("l", cx - s * 0.75, cy, cx + s * 0.75, cy))
        L.append(("d", cx, cy - s * 0.35, s * 0.14))
    else:            # double chevron
        for dy in (-0.35, 0.25):
            L.append(("l", cx - s * 0.7, cy + s * dy + s * 0.3, cx, cy + s * dy - s * 0.3))
            L.append(("l", cx, cy + s * dy - s * 0.3, cx + s * 0.7, cy + s * dy + s * 0.3))
    return L


def _seg_dist(ax, ay, bx, by):
    pxm, pym = wrap(X - ax), wrap(Y - ay)
    vx, vy = bx - ax, by - ay
    t = np.clip((pxm * vx + pym * vy) / max(vx * vx + vy * vy, 1e-6), 0, 1)
    return np.sqrt((pxm - vx * t) ** 2 + (pym - vy * t) ** 2)


def tex_EggRunes():
    # 4 x 4 grid of glyphs, staggered, fully inside their cells (no wrap needed)
    d = np.full((N, N), 1e9, np.float32)
    cell = N / 4
    r = rng(261)
    kinds = r.permutation(np.tile(np.arange(8), 2))
    for j in range(4):
        for i in range(4):
            cx = (i + 0.5) * cell + (cell * 0.25 if j % 2 else -cell * 0.1)
            cy = (j + 0.5) * cell
            cx = cx % N
            s = cell * 0.28
            for st in _rune_strokes(int(kinds[j * 4 + i]), cx, cy, s):
                if st[0] == "l":
                    d = np.minimum(d, _seg_dist(*st[1:]))
                elif st[0] == "c":
                    d = np.minimum(d, np.abs(disc_dist(st[1], st[2]) - st[3]))
                else:
                    d = np.minimum(d, np.maximum(disc_dist(st[1], st[2]) - st[3], 0))
    line = smoothstep(6.5, 4.0, d)
    glow = smoothstep(26, 0, d)
    dots = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(40, 262, 80):
        dots = np.maximum(dots, smoothstep(4, 2, disc_dist(cx, cy)) * 0.4)
    dots = dots * smoothstep(20, 40, d)
    light = line * 0.95 + glow * 0.30 + dots
    dark = smoothstep(9, 6.5, d) * (1 - line) * 0.35
    return overlay(light, dark)


def tex_BioVeins():
    wx = (noise(271, 160) - 0.5) * 90
    wy = (noise(272, 160) - 0.5) * 90
    f1, e1, _ = voronoi(random_points(26, 273, 150))
    f2, e2, _ = voronoi(random_points(90, 274, 80))
    e1 = sample(e1, X + wx - 0.5, Y + wy - 0.5)
    e2 = sample(e2, X + wy * 0.7 - 0.5, Y - wx * 0.7 - 0.5)
    # thin secondary veins only in some areas -> branching look
    mask2 = smoothstep(0.45, 0.6, noise(275, 180))
    core = np.maximum(smoothstep(3.2, 1.0, e1), smoothstep(2.0, 0.6, e2) * mask2 * 0.8)
    glow = np.maximum(smoothstep(26, 0, e1) ** 2, smoothstep(14, 0, e2) ** 2 * mask2 * 0.7)
    nodes = np.zeros((N, N), np.float32)
    for (cx, cy) in random_points(18, 276, 160):
        nodes = np.maximum(nodes, smoothstep(9, 4, disc_dist(cx, cy)) * smoothstep(12.0, 2.0, float(e1[int(cy) % N, int(cx) % N])))
    t = np.clip(core + nodes, 0, 1)
    col_glow = np.array([40, 230, 255], np.float32) / 255
    col_core = np.array([225, 255, 255], np.float32) / 255
    rgb = col_glow[None, None, :] * (1 - t[..., None]) + col_core[None, None, :] * t[..., None]
    alpha = np.clip(glow * 0.75 + core + nodes, 0, 1)
    return baked(rgb, alpha)


KEYS = [
    "FishScales", "FishScalesFine", "SharkSkin", "JellyMembrane", "CrabShell",
    "IsopodPlates", "TurtleShellHex", "CoralPorous", "CrystalFacets", "GoldFoil",
    "CoinPile", "IceFrost", "LavaCracks", "GhostWisp", "MothWing", "EelStripes",
    "SlugSpots", "ToxicBlotches", "MetalPanels", "RivetedPlates", "WoodPlanks",
    "StoneTiles", "BasaltRock", "SandRipples", "KelpFibers", "EggSpeckle",
    "EggRunes", "BioVeins",
]


def main(argv):
    keys = argv or KEYS
    for k in keys:
        fn = globals().get("tex_" + k)
        if fn is None:
            print("unknown key:", k)
            continue
        save(k, fn())
        print("wrote", os.path.join(OUT_DIR, k + ".png"))


if __name__ == "__main__":
    main(sys.argv[1:])
