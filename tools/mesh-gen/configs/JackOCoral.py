import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _props_common import *

ORANGE = (1.0, 0.55, 0.16)
ORANGE2 = (1.0, 0.59, 0.2)
TIP = (1.0, 0.8, 0.4)
MINT = (0.75, 1.0, 0.82)


def brain(P):
    """Brain-coral meanders: worley ridges."""
    F1, F2, cid = S.worley(P / 0.16, 4)
    e = S.smoothstep(0.02, 0.2, F2 - F1)
    return e, 1 + 0.07 * (e - 0.6) + 0.05 * (cid - 0.5), 0.06 * (1 - e)


class Config(Cfg):
    """Jack-o'-lantern brain coral: ribbed pumpkin head with carved recessed neon face (eye wedges stay Roblox parts), coral crown."""
    name = "JackOCoral"
    keep_re = r"^Eye[12]$"
    decal_re = r"Blush|Smile|Seam|ShellMark|Highlight|Glint|Pupil"      # Mouth is real geometry here
    ao_radius = 0.1
    wobble = 0.003
    belly = 0.2
    egg = None

    def k(self, g): return 0.25
    def part_k(self, n, kg): return 0.3 if n in ("Stalk", "CoralHead") else 0.1
    def budget(self, g): return 8000
    def cells(self, g): return 240
    def tex(self, g): return 768
    def amp(self, g): return 0.018

    def sculpt(self, g, ctx, dim):
        head, base, stalk, mouth = ctx.shape("CoralHead"), ctx.shape("Base"), ctx.shape("Stalk"), ctx.shape("Mouth")
        hc = head.c; hh = head.half
        polyps = [ctx.shape(f"BasePolyp{i}") for i in (1, 2, 3, 4)]
        eyes = [np.array([-0.8, 2.3, 1.45]), np.array([0.8, 2.3, 1.45])]   # Eye1/2 are kept parts (not in ctx)
        ex = []
        # coral crown on top: tubes radiating from the crown centre with bright polyp tips
        top = hc + np.array([0, hh[1] - 0.35, 0])
        for i in range(8):
            a = np.radians(45 * i + 10)
            d = np.array([np.cos(a) * 0.55, 1.0, np.sin(a) * 0.55]); L = 0.75 + 0.2 * (i % 3)
            b0 = top + np.array([np.cos(a) * 0.55, 0, np.sin(a) * 0.55])
            ex.append(CExtra("ellipsoid", [0.36, L, 0.36], b0 + unit(d) * L * 0.4, 0.1, ORANGE2, "SmoothPlastic", 0.5, orient(d)))
            ex.append(CExtra("ellipsoid", [0.34, 0.3, 0.34], b0 + unit(d) * L * 0.85, 0.08, TIP, "SmoothPlastic"))
        ex.append(CExtra("ellipsoid", [0.5, 1.0, 0.5], top + np.array([0, 0.35, 0]), 0.1, (0.35, 0.55, 0.25), "SmoothPlastic", 0.5, orient([0.2, 1, 0.1])))
        # teeth
        teeth = [CExtra("box", [0.34, 0.42, 0.3], [x, 1.78, 1.3], 0.03, ORANGE, "SmoothPlastic", 0.35) for x in (-0.55, 0.0, 0.55)]
        teeth += [CExtra("box", [0.3, 0.36, 0.3], [x, 1.22, 1.3], 0.03, ORANGE, "SmoothPlastic", 0.35) for x in (-0.3, 0.3)]
        ex += teeth
        glow = CExtra("ellipsoid", [1.9, 0.62, 0.3], [0.0, 1.5, 1.35], 0.03, MINT, "Neon")
        ex.append(glow)
        cfg = self
        R45 = np.array([[0.7071, -0.7071], [0.7071, 0.7071]])

        def cavity(Q, cx, cy, hx_, hy_, zmin):
            q = np.stack([(Q[:, 0] - cx) / hx_, (Q[:, 1] - cy) / hy_], -1)
            d2 = (np.linalg.norm(q, axis=-1) - 1.0) * min(hx_, hy_)
            return np.maximum(d2, zmin - Q[:, 2])

        def dia(Q, cx, cy, hw, zmin):
            u = (Q[:, 0] - cx); v = (Q[:, 1] - cy)
            r_ = (np.abs(u + v) + np.abs(u - v)) * 0.7071 * 0.5      # rotated-box (diamond) 'radius'
            d2 = np.maximum(np.abs(u), np.abs(v)) * 0 + (np.abs(u) + np.abs(v)) * 0.7071 - hw
            return np.maximum(d2, zmin - Q[:, 2])

        def post(Q, d):
            q = Q - hc
            ell = (np.linalg.norm(q / (hh * 0.99), axis=-1) - 1.0) * hh.min()
            hd = S.smax(head(Q), ell, 0.5)
            ang = np.arctan2(q[:, 2], q[:, 0])
            env = S.smoothstep(0.25, 0.65, np.hypot(q[:, 0], q[:, 2]) / hh[0]) * S.smoothstep(-hh[1] * 0.95, -hh[1] * 0.6, q[:, 1])
            hd = hd + 0.11 * (0.5 + 0.5 * np.cos(ang * 10)) ** 4 * env      # pumpkin rib grooves
            out = S.smin(base(Q), stalk(Q), 0.3)
            for p in polyps:
                out = S.smin(out, p(Q), 0.12)
            out = S.smin(out, hd, 0.3)
            # carved face: mouth cavity + two diamond eye sockets (Eye wedges stay as glowing parts inside)
            cav = cavity(Q, 0.0, 1.5, 1.08, 0.42, 1.12)
            for e in eyes:
                cav = np.minimum(cav, dia(Q, e[0], e[1], 0.62, 1.1))
            out = S.smax(out, -cav, 0.05)
            for e_ in ex:
                out = S.smin(out, e_.shape(Q), e_.k)
            return out
        return Sculpt(None, post, ex, margin=0.15)

    def detail(self, g):
        return lambda m: {"SmoothPlastic": brain, "Basalt": pebble(0.14, 0.12, 2), "Neon": pebble(0.1, 0.03)}.get(m)
