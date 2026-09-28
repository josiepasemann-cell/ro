#!/usr/bin/env python3
"""Part-based Luau model (exported JSON) -> smooth organic meshes + baked PBR textures.

    python3 pipeline.py --models <models.json> --model GoldGuppy [--out assets/meshes] [--fast]

Stages per mesh group: smooth-union SDF -> marching cubes -> Taubin -> quadric decimation -> SDF re-projection
-> xatlas UVs -> texture bake (colour / normal / roughness / metalness / emissive mask) -> obj + manifest;
finally one combined <Model>.glb with every mesh as a named node.
"""
import argparse, json, os, re, sys, time, hashlib, types
import numpy as np
import trimesh, xatlas, fast_simplification
from PIL import Image
from scipy import ndimage
from skimage import measure

import sdf as S
import models as M

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# ------------------------------------------------------------------ grouping rules
ANIM_PREFIXES = ["tailfin", "dorsalfin", "sidefin", "wing", "tentacle", "spinespike", "tailtip", "tip", "lowerjaw",
                 "horn", "nose", "facet", "claw", "antenna", "leg"]
EXTRA_ROOTS = {"Eye1", "Eye2"}                       # eyes are always separate, crisp meshes
NPC_ROOTS = {"Head", "ArmL", "ArmR"}                 # + eyes, for NPC models
ATTACH_TOL = 0.15                                    # studs: child joins a root if its centre is this close to the root's surface
MESH_KIND = {"Sphere": "ellipsoid", "Cylinder": "cylx", "CylinderMesh": "cyly", "Head": "cyly"}
HIDDEN_TRANSP = 0.95


def cfmat(cf):
    m = np.eye(4)
    m[:3, 3] = cf[:3]
    m[:3, :3] = np.array(cf[3:12], float).reshape(3, 3)
    return m


def mat12(m):
    return [round(float(x), 5) for x in list(m[:3, 3]) + list(m[:3, :3].reshape(-1))]


class Part:
    def __init__(self, p):
        self.raw, self.name = p, p["name"]
        self.cf = cfmat(p["cf"])                      # original part CFrame (pivot)
        size = np.array(p["size"], float)
        M_ = self.cf.copy()
        mt = p.get("meshType")
        if mt:                                         # SpecialMesh: fills size*scale, shifted by offset (see render.html)
            sc = p.get("meshScale") or [1, 1, 1]
            off = p.get("meshOffset") or [0, 0, 0]
            size = size * np.array(sc)
            M_[:3, 3] = M_[:3, 3] + M_[:3, :3] @ np.array(off)
            self.kind = MESH_KIND.get(mt, "box")
        elif p["shape"] == "Ball":                     # Roblox balls are round: smallest axis
            size = np.full(3, size.min())
            self.kind = "ellipsoid"
        elif p["shape"] == "Cylinder":                 # axis along X, circular cross-section
            d = min(size[1], size[2])
            size = np.array([size[0], d, d])
            self.kind = "cylx"
        else:
            self.kind = "box"
        self.size, self.M = size, M_
        self.color = np.array(p["color"], float)
        self.material = p["material"]
        self.transp = p.get("transparency", 0.0)
        self.hidden = self.transp >= HIDDEN_TRANSP
        self.neon = self.material == "Neon"
        self.decal = False
        self.k = None

    def shape(self, frame_inv, rounding):
        return S.Shape(self.kind, self.size, frame_inv @ self.M, rounding)

    def world_shape(self, rounding=0.45):
        return S.Shape(self.kind, self.size, self.M, rounding)


def is_anim(name, npc):
    l = name.lower()
    return any(l.startswith(p) for p in ANIM_PREFIXES) or name in EXTRA_ROOTS or (npc and name in NPC_ROOTS)


def first_word(n):
    m = re.match(r"[A-Z][a-z]*", n)
    return m.group(0) if m else n


def group_parts(parts, primary, npc):
    """Grouping rule (documented in README):
       1. Primary part (Body) and everything not claimed below -> body mesh.
       2. Parts matching the animated-name list (+ Eye1/Eye2, + Head/ArmL/ArmR for NPCs) are roots: one separate mesh each.
       3. Every other part attaches to a root if (a) it shares the first CamelCase word with exactly one root
          (TailLamella1 -> TailFin) or (b) its centre lies within ATTACH_TOL studs of the root's surface (smallest SDF wins:
          EyeWhite1/Highlight -> Eye1, EyeStalkL -> Head, ArmStalkL -> ArmL). Otherwise it stays in the body."""
    roots = [p for p in parts if p is not primary and is_anim(p.name, npc)]
    groups = {primary.name: [primary]}
    for r in roots:
        groups[r.name] = [r]
    rshape = {r.name: r.world_shape(0.45) for r in roots}
    for p in parts:
        if p is primary or p in roots:
            continue
        fw = first_word(p.name)
        same = [r for r in roots if first_word(r.name) == fw]
        if len(same) == 1:
            groups[same[0].name].append(p)
            continue
        best, bd = None, ATTACH_TOL
        for r in roots:
            d = float(rshape[r.name](p.M[:3, 3][None])[0])
            if d < bd:
                best, bd = r, d
        groups[best.name if best else primary.name].append(p)
    return roots, groups


# ------------------------------------------------------------------ group field
class Field:
    """Smooth-union SDF of a group's geometry parts (+ sculpt extras), evaluated in the anchor-local frame."""

    def __init__(self, geo, cfg, gname, dim, sculpt):
        self.geo, self.cfg, self.dim, self.sculpt = geo, cfg, dim, sculpt
        self.kg = cfg.k(gname)
        self.items = []                                   # (part, Shape, k)
        for p in sorted(geo, key=lambda q: -np.prod(q.size)):
            k = cfg.part_k(p.name, self.kg)
            self.items.append((p, p.lshape, min(k, 0.6 * float(p.size.min()))))
        self.extras = sculpt.extras if sculpt else []
        self.wob = cfg.wobble * dim
        self.seed = abs(hash(gname)) % 1000

    def parts_d(self, Q):
        return [it[1](Q) for it in self.items] + [e.shape(Q) for e in self.extras]

    def __call__(self, P):
        Q = self.sculpt.pre(P) if self.sculpt and self.sculpt.pre else P
        d = None
        for p, sh, k in self.items:
            di = sh(Q)
            d = di if d is None else S.smin(d, di, k)
        for e in self.extras:
            d = S.smin(d, e.shape(Q), e.k)
        if self.sculpt and self.sculpt.post:
            d = self.sculpt.post(Q, d)
        if self.wob > 0:
            d = d + self.wob * S.fbm(P / (0.45 * self.dim), self.seed, 2)
        return d


def grad(f, P, eps):
    g = np.stack([(f(P + np.eye(3)[i] * eps) - f(P - np.eye(3)[i] * eps)) for i in range(3)], -1) / (2 * eps)
    return g


def chunked(fn, P, n=400000):
    return np.concatenate([fn(P[i:i + n]) for i in range(0, len(P), n)]) if len(P) else np.zeros(0)


# ------------------------------------------------------------------ meshing
def mesh_from_field(field, lo, hi, vs, budget, log):
    ax = [np.arange(lo[i], hi[i] + vs, vs, dtype=np.float32) for i in range(3)]
    vol = np.empty((len(ax[0]), len(ax[1]), len(ax[2])), np.float32)
    YZ = np.stack(np.meshgrid(ax[1], ax[2], indexing="ij"), -1).reshape(-1, 2)
    step = max(1, 350000 // len(YZ))
    for i in range(0, len(ax[0]), step):
        xs = ax[0][i:i + step]
        P = np.concatenate([np.stack([np.full(len(YZ), x, np.float32), YZ[:, 0], YZ[:, 1]], -1) for x in xs])
        vol[i:i + len(xs)] = field(P).reshape(len(xs), len(ax[1]), len(ax[2]))
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(vs, vs, vs))
    verts = verts + np.array(lo, np.float32)
    m = trimesh.Trimesh(verts, faces, process=True)
    parts = m.split(only_watertight=False)
    if len(parts) > 1:
        big = max(len(p.faces) for p in parts)
        m = trimesh.util.concatenate([p for p in parts if len(p.faces) > 0.04 * big])
    log(f"    MC: {len(m.faces)} tris on {vol.shape} grid (vs={vs:.4f})")
    trimesh.smoothing.filter_taubin(m, lamb=0.5, nu=-0.53, iterations=12)
    v, f = fast_simplification.simplify(np.asarray(m.vertices, np.float32), np.asarray(m.faces, np.int32),
                                        target_count=budget, agg=6)
    v = v.astype(np.float64)
    for _ in range(4):                                    # snap decimated verts back onto the exact surface
        d = field(v.astype(np.float32))
        g = grad(field, v.astype(np.float32), vs * 0.5)
        gn = np.maximum((g * g).sum(-1), 1e-6)
        v = v - np.clip(d[:, None] * g / gn[:, None], -vs * 1.5, vs * 1.5)
    n = grad(field, v.astype(np.float32), vs * 0.5)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    flip = (fn * n[f].mean(1)).sum(-1) < 0
    f = np.where(flip[:, None], f[:, ::-1], f)
    log(f"    decimated to {len(f)} tris ({flip.sum()} flipped)")
    return v, f, n


def uv_unwrap(v, f, n, res, log):
    atlas = xatlas.Atlas()
    atlas.add_mesh(v.astype(np.float32), f.astype(np.uint32), n.astype(np.float32))
    co = xatlas.ChartOptions()
    co.max_iterations = 2
    co.normal_seam_weight = 2.0
    po = xatlas.PackOptions()
    po.resolution = res
    po.padding = 6
    po.bilinear = True
    atlas.generate(co, po)
    vmap, idx, uv = atlas[0]
    log(f"    xatlas: {len(v)} -> {len(vmap)} verts, {int(atlas.chart_count)} charts")
    return vmap, idx.astype(np.int64), uv.astype(np.float64)


def rasterize(uv, faces, res):
    """Texel -> (triangle id, barycentric); texel centre convention, row 0 = v 1 (top)."""
    tri = np.full((res, res), -1, np.int32)
    bary = np.zeros((res, res, 3), np.float32)
    px = uv[:, 0] * res
    py = (1 - uv[:, 1]) * res
    for t, (a, b, c) in enumerate(faces):
        x = px[[a, b, c]]; y = py[[a, b, c]]
        x0, x1 = int(np.floor(x.min() - 0.5)), int(np.ceil(x.max() + 0.5))
        y0, y1 = int(np.floor(y.min() - 0.5)), int(np.ceil(y.max() + 0.5))
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, res - 1), min(y1, res - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(den) < 1e-12:
            continue
        w0 = ((y[1] - y[2]) * (gx - x[2]) + (x[2] - x[1]) * (gy - y[2])) / den
        w1 = ((y[2] - y[0]) * (gx - x[2]) + (x[0] - x[2]) * (gy - y[2])) / den
        w2 = 1 - w0 - w1
        e = -0.02
        m = (w0 >= e) & (w1 >= e) & (w2 >= e)
        ys, xs = np.nonzero(m)
        tri[ys + y0, xs + x0] = t
        bary[ys + y0, xs + x0] = np.stack([w0[m], w1[m], w2[m]], -1)
    return tri, bary


def dilate(img, valid, iters=None):
    """Fill invalid texels with the nearest valid texel (edge padding against bilinear/mip bleeding)."""
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    return img[idx[0], idx[1]]


# ------------------------------------------------------------------ bake
def lighten(c, a):
    return c + (1 - c) * a


def bake_surface(g, field, geo, decals, occluders, cfg, v, f, n, uv, res, frame, log):
    """Bake all maps for a body-type mesh.  Returns dict of PIL images + stats."""
    tri, bary = rasterize(uv, f, res)
    valid = tri >= 0
    ty, tx = np.nonzero(valid)
    t = tri[ty, tx]
    b = bary[ty, tx]
    P = (v[f[t]] * b[..., None]).sum(1)
    N = (n[f[t]] * b[..., None]).sum(1)
    N /= np.maximum(np.linalg.norm(N, axis=-1, keepdims=True), 1e-9)
    # per-triangle tangent frame from UVs
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    u0, u1, u2 = uv[f[:, 0]], uv[f[:, 1]], uv[f[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = u1 - u0, u2 - u0
    det = d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]
    det = np.where(np.abs(det) < 1e-14, 1e-14, det)
    Tt = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / det[:, None]
    Bt = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / det[:, None]
    T = Tt[t]; Bv = Bt[t]
    T = T - N * (T * N).sum(-1, keepdims=True)
    T /= np.maximum(np.linalg.norm(T, axis=-1, keepdims=True), 1e-9)
    Bo = np.cross(N, T)
    Bo = np.where(((Bo * Bv).sum(-1) < 0)[:, None], -Bo, Bo)
    dim = field.dim
    Pf = P.astype(np.float32)
    # ---- part weights -> colour / material
    Q = field.sculpt.pre(Pf) if field.sculpt and field.sculpt.pre else Pf
    ds = np.stack(chunked_multi(field.parts_d, Q), 0)                       # (nparts, N)
    tau = cfg.blend_tau * dim
    w = np.exp(-(ds - ds.min(0, keepdims=True)) / tau)
    w /= w.sum(0, keepdims=True)
    geo_all = [it[0] for it in field.items] + [e.like for e in field.extras]
    col = sum(w[i][:, None] * geo_all[i].color[None] for i in range(len(geo_all)))
    mats = sorted({p.material for p in geo_all})
    W = {m_: sum(w[i] for i in range(len(geo_all)) if geo_all[i].material == m_) for m_ in mats}
    neon = sum(w[i] for i in range(len(geo_all)) if geo_all[i].neon) if any(p.neon for p in geo_all) else np.zeros(len(P))
    # decals (painted onto the surface)
    edge = cfg.decal_edge * dim
    for dp in decals:
        dd = dp.lshape(Q)
        a = S.smoothstep(edge, -edge, dd) * (1 - dp.transp)
        col = col * (1 - a[:, None]) + dp.color[None] * a[:, None]
        if dp.neon:
            neon = np.maximum(neon, a)
            W["Neon"] = W.get("Neon", 0) * (1 - a) + a
    col_pure = col.copy()
    # ---- ambient occlusion from the field (+ neighbouring groups) -> crevices darken
    def full(Pq):
        d = field(Pq)
        return np.minimum(d, occluders(Pq)) if occluders else d
    ao_s = float(np.clip(cfg.ao_radius * dim, 0.05, 0.5))
    occl = np.zeros(len(P))
    Ps = Pf + N.astype(np.float32) * 0.004 * dim
    for i in range(1, 6):
        h = ao_s * i / 5
        dsamp = chunked(full, Ps + N.astype(np.float32) * h)
        occl += np.clip(h - dsamp, 0, None) / h * (0.5 ** (i - 1))
    ao = np.clip(1 - cfg.ao_strength * occl / 1.9, 0.42, 1.0)
    # ---- detail height (normal map) + colour modulation
    hfun = cfg.detail(g)
    amp = cfg.amp(g)
    h0, bright, rough_add = detail_eval(hfun, Pf, W, cfg, g)
    eps = 0.002 * dim
    hx = [detail_eval(hfun, Pf + np.eye(3, dtype=np.float32)[i] * eps, W, cfg, g)[0] for i in range(3)]
    gh = np.stack([(hx[i] - h0) / eps for i in range(3)], -1) * amp
    gt = gh - N * (gh * N).sum(-1, keepdims=True)
    Nn = N - gt * cfg.normal_gain
    Nn /= np.linalg.norm(Nn, axis=-1, keepdims=True)
    nt = np.stack([(Nn * T).sum(-1), (Nn * Bo).sum(-1), (Nn * N).sum(-1)], -1)
    # ---- colour: cartoon shading in the texture
    R = frame[:3, :3]                                                        # group-local -> model frame
    ny = (N @ R.T)[:, 1]
    belly = S.smoothstep(0.25, -0.75, ny)
    top = S.smoothstep(0.35, 0.95, ny)
    col = lighten(col, 0.30 * cfg.belly * belly[:, None])
    col = col * (1 - 0.07 * top[:, None]) 
    col = col * bright[:, None]
    ao_c = ao[:, None]
    col = np.clip(col, 0, 1)
    shade = col * col * (1 - ao_c) + col * ao_c                                # crevices: darker AND more saturated
    col = shade * (0.72 + 0.28 * ao_c)
    col = col * (1 - neon[:, None]) + lighten(col_pure, 0.06) * neon[:, None]      # neon regions stay unshaded / bright
    # ---- roughness / metalness / emissive
    base_r = {"SmoothPlastic": 0.42, "Plastic": 0.5, "Slate": 0.62, "Foil": 0.26, "Metal": 0.3, "Fabric": 0.9, "Neon": 0.35,
              "Glass": 0.1, "Marble": 0.35}
    base_m = {"Foil": 0.9, "Metal": 0.95}
    rough = sum(W[m_] * base_r.get(m_, 0.55) for m_ in mats) + rough_add + (1 - ao) * 0.15
    metal = sum(W[m_] * base_m.get(m_, 0.0) for m_ in mats if m_ in base_m) if any(m_ in base_m for m_ in mats) else np.zeros(len(P))
    metal = np.clip(metal * (0.92 + 0.08 * h0) * (0.6 + 0.4 * ao), 0, 1)
    rough = np.clip(rough, 0.05, 1)

    def to_img(vals, ch):
        arr = np.zeros((res, res, ch), np.float32)
        arr[ty, tx] = vals.reshape(len(vals), -1)
        return arr

    vmask = valid
    col_i = dilate(to_img(col, 3), vmask)
    nrm_i = to_img(nt * 0.5 + 0.5, 3)
    nrm_i = dilate(nrm_i, vmask)
    r_i = dilate(to_img(rough, 1), vmask)[..., 0]
    m_i = dilate(to_img(metal, 1), vmask)[..., 0]
    e_i = dilate(to_img(neon, 1), vmask)[..., 0]
    def u8(a, q=1):   # 8-bit with optional posterisation (q = step): keeps PNGs small, invisible at these amplitudes
        v = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.int32)
        return (np.minimum(v // q * q + q // 2, 255) if q > 1 else v).astype(np.uint8)
    out = {"ColorMap": Image.fromarray(u8(col_i, 3)), "NormalMap": Image.fromarray(u8(nrm_i, 6)),
           "RoughnessMap": Image.fromarray(u8(r_i, 8), "L"), "MetalnessMap": Image.fromarray(u8(m_i, 8), "L")}
    neon_frac = float(neon.mean())
    if (neon > 0.3).sum() > 40:
        out["EmissiveMask"] = Image.fromarray(u8(e_i), "L")
    stats = {"materials": {m_: float(W[m_].mean()) for m_ in mats}, "neonFraction": neon_frac}
    return out, stats


def w_col(geo_all, w, neon):
    return sum(w[i][:, None] * geo_all[i].color[None] for i in range(len(geo_all)))


def chunked_multi(fn, Q, n=300000):
    outs = [fn(Q[i:i + n]) for i in range(0, len(Q), n)]
    return [np.concatenate([o[j] for o in outs]) for j in range(len(outs[0]))]


def detail_eval(hfun, P, W, cfg, g):
    h = np.zeros(len(P), np.float32); b = np.ones(len(P), np.float32); r = np.zeros(len(P), np.float32)
    tot = sum(W.values())
    for m_, wm in W.items():
        fn = hfun(m_)
        if fn is None:
            continue
        hm, bm, rm = fn(P)
        h += wm * hm; b += wm * (bm - 1); r += wm * rm
    return h, b, r


# ------------------------------------------------------------------ eyes
def build_eye(group_name, members, anchor, cfg, log):
    ball = max([p for p in members if not p.hidden and p.kind == "ellipsoid" and not re.search(r"Pupil|Glint|Highlight", p.name)],
               key=lambda p: np.prod(p.size))
    Ainv = np.linalg.inv(anchor.cf)
    sh = ball.shape(Ainv, 0.5)
    half, c, R = sh.half, sh.c, sh.R
    pup = next((p for p in members if p is not ball and (p is anchor or "Pupil" in p.name)), None)
    hl = [p for p in members if p is not ball and (re.search(r"Highlight|Glint", p.name) or (p.neon and p is not pup))]
    front = np.array([0, 0, -1.0])
    def udir(p, default):
        if p is None:
            return default
        q = ((Ainv @ p.M)[:3, 3] - c) @ R / half
        return q / np.linalg.norm(q) if np.linalg.norm(q) > 1e-3 else default
    dirv = udir(pup, front @ R)
    rel = lambda p: float(np.clip(np.mean((p.size / 2.0)[:] / half), 0.05, 0.98))
    th_p = np.arcsin(min(0.95, rel(pup))) if pup is not None else 0.6
    th_i = min(th_p * cfg.iris_ratio, 1.25)
    hdirs = [(udir(p, dirv), np.arcsin(min(0.9, rel(p)))) for p in hl]
    # UV sphere with the pole along the gaze direction
    e1 = np.cross(dirv, [0, 1, 0] if abs(dirv[1]) < 0.9 else [1, 0, 0]); e1 /= np.linalg.norm(e1); e2 = np.cross(dirv, e1)
    nth, nph = 16, 24
    th = np.linspace(0, np.pi, nth + 1); ph = np.linspace(0, 2 * np.pi, nph + 1)
    TH, PH = np.meshgrid(th, ph, indexing="ij")
    q = dirv[None, None] * np.cos(TH)[..., None] + np.sin(TH)[..., None] * (e1 * np.cos(PH)[..., None] + e2 * np.sin(PH)[..., None])
    q = q.reshape(-1, 3)
    verts = c + (q * half) @ R.T
    nrm = ((q / half) @ R.T); nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    uv = np.stack([PH.reshape(-1) / (2 * np.pi), 1 - TH.reshape(-1) / np.pi], -1)
    idx = np.arange((nth + 1) * (nph + 1)).reshape(nth + 1, nph + 1)
    faces = []
    for i in range(nth):
        for j in range(nph):
            a, b, c2, d = idx[i, j], idx[i, j + 1], idx[i + 1, j], idx[i + 1, j + 1]
            if i > 0: faces.append([a, c2, b])
            if i < nth - 1: faces.append([b, c2, d])
    faces = np.array(faces)
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    if (fn * nrm[faces].mean(1)).sum() < 0:
        faces = faces[:, ::-1]
    # texture: lat-long around the gaze pole -> circles stay perfectly round
    res = cfg.eye_tex
    rr, cc = np.meshgrid((np.arange(res) + 0.5) / res, (np.arange(res) + 0.5) / res, indexing="ij")
    TH2, PH2 = rr * np.pi, cc * 2 * np.pi
    qq = dirv * np.cos(TH2)[..., None] + np.sin(TH2)[..., None] * (e1 * np.cos(PH2)[..., None] + e2 * np.sin(PH2)[..., None])
    ang = TH2
    px = np.pi / res * 1.2
    sc = np.array([0.98, 0.99, 0.97]) * (0.86 + 0.14 * S.smoothstep(2.0, 0.6, ang))[..., None]
    iris_c = np.array(cfg.iris_color)
    ir = np.clip(ang / max(th_i, 1e-3), 0, 1)
    iris = iris_c[None, None] * (0.55 + 0.6 * (1 - ir))[..., None] ** 1.0
    iris = np.clip(iris + 0.18 * S.smoothstep(0.45, 0.0, np.abs(ir - 0.5))[..., None] * lighten(iris_c, 0.5)[None, None], 0, 1)
    limb = S.smoothstep(0.78, 1.0, ir)[..., None]
    iris = iris * (1 - 0.55 * limb)
    a_iris = S.smoothstep(th_i + px, th_i - px, ang)[..., None]
    col = sc * (1 - a_iris) + iris * a_iris
    a_pup = S.smoothstep(th_p + px, th_p - px, ang)[..., None]
    col = col * (1 - a_pup) + np.array([0.03, 0.03, 0.05]) * a_pup
    emis = np.zeros((res, res)); glossy = np.zeros((res, res))
    for hdw, hr in hdirs:
        d_h = np.arccos(np.clip((qq * hdw).sum(-1), -1, 1))
        a_h = S.smoothstep(hr + px, hr - px, d_h)
        col = col * (1 - a_h[..., None]) + 1.0 * a_h[..., None]
        emis = np.maximum(emis, a_h)
        # small secondary catch-light opposite the main one
        sec = dirv * 2 * (hdw @ dirv) - hdw
        d2 = np.arccos(np.clip((qq * sec).sum(-1), -1, 1))
        a2 = S.smoothstep(hr * 0.45 + px, hr * 0.45 - px, d2) * 0.85
        col = col * (1 - a2[..., None]) + a2[..., None]
    rough = np.where(ang < th_i, 0.06, 0.2)
    u8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    flat = np.zeros((res, res, 3)); flat[..., :] = [0.5, 0.5, 1.0]
    tex = {"ColorMap": Image.fromarray(u8(col)), "NormalMap": Image.fromarray(u8(flat)),
           "RoughnessMap": Image.fromarray(u8(rough), "L"), "MetalnessMap": Image.fromarray(u8(np.zeros((res, res))), "L")}
    if emis.max() > 0.3:
        tex["EmissiveMask"] = Image.fromarray(u8(emis), "L")
    return verts, faces, nrm, uv, tex


# ------------------------------------------------------------------ writers
def write_obj(path, v, f, n, uv, header):
    with open(path, "w") as fh:
        fh.write(f"# {header}\n")
        np.savetxt(fh, v, fmt="v %.5f %.5f %.5f")
        np.savetxt(fh, uv, fmt="vt %.5f %.5f")
        np.savetxt(fh, n, fmt="vn %.4f %.4f %.4f")
        i = f + 1
        for a, b, c in i:
            fh.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


def save_png(img, path):
    img.save(path, optimize=True)


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", default=os.path.join(REPO, "assets", "meshes"))
    ap.add_argument("--fast", action="store_true", help="lower resolution, for quick iteration")
    a = ap.parse_args()
    t0 = time.time()
    log = lambda s: print(f"[{time.time() - t0:5.1f}s] {s}", flush=True)
    data = json.load(open(a.models))
    mdl = next(m for m in data["models"] if m["name"] == a.model)
    cfg = M.get(a.model)
    npc = mdl["category"] == "Npcs"
    parts = [Part(p) for p in mdl["parts"]]
    Ap = cfmat(mdl["primary"])
    primary = next(p for p in parts if np.allclose(p.cf, Ap, atol=1e-4) and p.name in ("Body", "Torso", "Root", "Hull")) \
        if any(np.allclose(p.cf, Ap, atol=1e-4) and p.name in ("Body", "Torso", "Root", "Hull") for p in parts) \
        else next(p for p in parts if np.allclose(p.cf, Ap, atol=1e-4))
    for p in parts:
        p.decal = bool(cfg.is_decal(p))
    roots, groups = group_parts(parts, primary, npc)
    log(f"{a.model}: {len(parts)} parts -> {len(groups)} groups: " + ", ".join(f"{k}[{len(v)}]" for k, v in groups.items()))
    outdir = os.path.join(a.out, a.model)
    os.makedirs(outdir, exist_ok=True)
    for fn in os.listdir(outdir):
        os.remove(os.path.join(outdir, fn))
    Apinv = np.linalg.inv(Ap)

    # global occluder shapes per group (world frame), used for AO contact shadows
    all_geo = {gn: [p for p in mem if not p.decal and not p.hidden] for gn, mem in groups.items()}

    built, entries, dedupe = {}, [], {}
    for gname, members in groups.items():
        anchor = next(p for p in members if p.name == gname)
        A = anchor.cf
        Ainv = np.linalg.inv(A)
        is_eye = gname in EXTRA_ROOTS
        key_items = sorted([(q.kind, tuple(np.round(q.size, 3)), tuple(np.round((Ainv @ q.M).reshape(-1), 3)), tuple(np.round(q.color, 3)),
                             q.material, q.decal, q.hidden, round(q.transp, 2)) for q in members], key=str)
        key = hashlib.md5((cfg.name + str(key_items) + ("eye" if is_eye else "")).encode()).hexdigest()
        if key in dedupe:
            entries.append({"group": gname, "anchor": anchor, "members": members, "dup": dedupe[key]})
            log(f"  {gname}: identical to {dedupe[key]} (shared mesh)")
            continue
        dedupe[key] = gname
        log(f"  {gname}: building ({len(members)} parts)")
        if is_eye:
            v, f, n, uv, tex = build_eye(gname, members, anchor, cfg, log)
            stats = {"materials": {"SmoothPlastic": 1.0}, "neonFraction": 0.0}
            frame = None
        else:
            geo = [q for q in members if not q.decal and not q.hidden]
            decals = [q for q in members if q.decal and not q.hidden]
            for q in geo + decals:
                q.lshape = q.shape(Ainv, cfg.rounding(q))
            lo = np.min([q.lshape.bbox()[0] for q in geo], 0); hi = np.max([q.lshape.bbox()[1] for q in geo], 0)
            dim = float((hi - lo).max())
            byname = {q.name: q for q in parts}
            ctx = types.SimpleNamespace(shape=lambda n, Ainv=Ainv: byname[n].shape(Ainv, cfg.rounding(byname[n])))
            cfg.prepare(gname, ctx)
            sculpt = cfg.sculpt(gname, ctx, dim)
            if sculpt:
                for e in sculpt.extras:
                    e.like = next(q for q in members if q.name == e.like_name)
            field = Field(geo, cfg, gname, dim, sculpt)
            margin = max(field.kg * 1.2, 0.05 * dim) + 0.06 * dim
            if sculpt and sculpt.margin:
                margin += sculpt.margin
            lo_, hi_ = lo - margin, hi + margin
            res_cells = cfg.cells(gname) // (2 if a.fast else 1)
            vs = float((hi_ - lo_).max()) / res_cells
            v, f, n = mesh_from_field(field, lo_, hi_, vs, cfg.budget(gname), log)
            vmap, idx, uv = uv_unwrap(v, f, n, cfg.tex(gname) // (2 if a.fast else 1), log)
            v2, n2 = v[vmap], n[vmap]
            # occluders: every other group's geometry in this group's frame (hard union)
            oshapes = [q.shape(Ainv, cfg.rounding(q)) for gn2, lst in all_geo.items() if gn2 != gname for q in lst]
            def occ(Pq, oshapes=oshapes):
                d = oshapes[0](Pq)
                for s_ in oshapes[1:]:
                    d = np.minimum(d, s_(Pq))
                return d
            frame = Apinv @ A
            tex, stats = bake_surface(gname, field, geo, decals, occ if oshapes else None, cfg, v2, idx, n2, uv, cfg.tex(gname) // (2 if a.fast else 1), frame, log)
            v, f, n = v2, idx, n2
            f = f  # already indices into the split vertex list
        ctr = (v.min(0) + v.max(0)) / 2
        v_c = v - ctr
        size = v.max(0) - v.min(0)
        mesh_file = f"{a.model}_{gname}"
        write_obj(os.path.join(outdir, mesh_file + ".obj"), v_c, f, n, uv, f"{a.model} / {gname}  (local frame of part '{gname}', bbox-centred; -Z = front)")
        texfiles = {}
        for k, img in tex.items():
            fn = f"{mesh_file}_{k}.png"
            save_png(img, os.path.join(outdir, fn))
            texfiles[k] = fn
        built[gname] = {"v": v_c, "f": f, "n": n, "uv": uv, "tex": tex, "center": ctr, "size": size, "files": texfiles,
                        "obj": mesh_file + ".obj", "stats": stats}
        log(f"    -> {len(f)} tris, {len(v)} verts, size {np.round(size, 2)}")
        entries.append({"group": gname, "anchor": anchor, "members": members, "dup": None})

    # ---------------------------------------------------------------- manifest + glb
    manifest_meshes = []
    scene = trimesh.Scene()
    total_tris = 0
    for e in entries:
        gname = e["group"]; anchor = e["anchor"]
        src = e["dup"] or gname
        b = built[src]
        # center CFrame: anchor pivot * translate(bbox centre)   (relative to model PrimaryPart)
        Tc = np.eye(4); Tc[:3, 3] = b["center"]
        center_rel = Apinv @ anchor.cf @ Tc
        pivot_rel = Apinv @ anchor.cf
        st = b["stats"]
        mats = st["materials"]
        dom = max(mats, key=mats.get)
        vis_transp = float(np.mean([q.transp for q in e["members"] if not q.hidden and not q.decal])) if any(not q.hidden and not q.decal for q in e["members"]) else 0.0
        neon_parts = [q.name for q in e["members"] if q.neon]
        material = "Neon" if st["neonFraction"] > 0.6 else dom
        ent = {"name": gname, "primary": anchor is primary, "animated": anchor is not primary,
               "file": b["obj"], "glbNode": gname, "sharedWith": e["dup"],
               "pivot": mat12(pivot_rel), "center": mat12(center_rel), "size": [round(float(x), 4) for x in b["size"]],
               "replaces": [q.name for q in e["members"]],
               "material": material, "transparency": round(vis_transp, 3),
               "materialMix": {k: round(v_, 3) for k, v_ in mats.items()},
               "neon": {"fraction": round(st["neonFraction"], 4), "parts": neon_parts,
                        "advice": ("Set MeshPart.Material = Neon (whole mesh glows)" if st["neonFraction"] > 0.6 else
                                   ("Use EmissiveMask via SurfaceAppearance (EmissiveStrength) or overlay a small Neon mesh" if neon_parts else "none"))},
               "textures": b["files"], "tris": int(len(b["f"])), "verts": int(len(b["v"])),
               "textureSize": list(next(iter(b["tex"].values())).size),
               "collisionFidelity": "Hull" if anchor is primary else "Box", "canCollide": False}
        manifest_meshes.append(ent)
        total_tris += len(b["f"])
        # glb: one geometry per unique mesh, one node per instance
        if f"{src}_mesh" not in scene.geometry:
            tm = trimesh.Trimesh(b["v"], b["f"], process=False)
            tm.vertex_normals = b["n"]
            t = b["tex"]
            mr = np.zeros((*t["RoughnessMap"].size[::-1], 3), np.uint8)
            mr[..., 1] = np.asarray(t["RoughnessMap"]); mr[..., 2] = np.asarray(t["MetalnessMap"])
            kw = {}
            if "EmissiveMask" in t:
                em = np.asarray(t["ColorMap"], np.float32) * (np.asarray(t["EmissiveMask"], np.float32)[..., None] / 255.0)
                kw = {"emissiveTexture": Image.fromarray(em.astype(np.uint8)), "emissiveFactor": [1, 1, 1]}
            mat = trimesh.visual.material.PBRMaterial(baseColorTexture=t["ColorMap"], normalTexture=t["NormalMap"],
                                                      metallicRoughnessTexture=Image.fromarray(mr), metallicFactor=1.0, roughnessFactor=1.0, name=f"{a.model}_{src}", **kw)
            tm.visual = trimesh.visual.TextureVisuals(uv=b["uv"], material=mat)
            tm.metadata["src"] = src
            scene.add_geometry(tm, node_name=gname, geom_name=f"{src}_mesh", transform=center_rel)
        else:
            scene.graph.update(frame_to=gname, frame_from=scene.graph.base_frame, matrix=center_rel, geometry=f"{src}_mesh")
    glb = scene.export(file_type="glb", include_normals=True)
    open(os.path.join(outdir, f"{a.model}.glb"), "wb").write(glb)
    man = {"model": a.model, "generator": "tools/mesh-gen/pipeline.py", "primaryPart": primary.name,
           "convention": "original coordinates, -Z = front, studs = glTF metres; obj vertices are bbox-centred in the local frame of the pivot part",
           "cframeFormat": "x,y,z,R00,R01,R02,R10,R11,R12,R20,R21,R22 (row-major, Roblox CFrame:GetComponents order), relative to PrimaryPart",
           "totalTris": int(total_tris), "meshes": manifest_meshes}
    json.dump(man, open(os.path.join(outdir, "manifest.json"), "w"), indent=1)
    size = sum(os.path.getsize(os.path.join(outdir, x)) for x in os.listdir(outdir))
    log(f"done: {len(manifest_meshes)} nodes, {len(built)} unique meshes, {total_tris} tris, {size / 1e6:.2f} MB in {outdir}")


if __name__ == "__main__":
    main()
