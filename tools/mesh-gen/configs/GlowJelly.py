"""GlowJelly: glassy bell with scalloped skirt + inner glow core, cute face, frilly mouth arms, glowing tentacles."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _creaturesB import *


class Config(CreatureCfg):
    name = "GlowJelly"
    iris_color = (0.1, 0.45, 0.6)
    ao_radius = 0.1
    ao_strength = 0.6
    eye_inset = -0.1
    wobble = 0.004
    blend_tau = 0.03
    extra_roots = r"^GlowCore$"          # inner glow core stays its own mesh (otherwise it vanishes inside the bell)
    tex_small = 128

    def k(self, g): return {"Body": 0.2, "GlowCore": 0.15}.get(g, 0.08)
    def part_k(self, n, kg): return 0.16 if n.startswith("OralArm") else kg
    def budget(self, g): return {"Body": 6000, "GlowCore": 700}.get(g, 550)
    def cells(self, g): return 220 if g == "Body" else 110
    def tex(self, g): return 1024 if g == "Body" else (256 if g == "GlowCore" else 128)
    def amp(self, g): return 0.0025

    def sculpt(self, g, ctx, dim):
        if g != "Body":
            return None
        BELL = rgb(150, 230, 255)
        ARM = rgb(200, 245, 255)
        R0, Y0 = 0.93, -0.72

        def skirt(Q):                                    # scalloped bell rim (torus with wavy radius/height)
            ang = np.arctan2(Q[:, 0], Q[:, 2])
            rr = np.hypot(Q[:, 0], Q[:, 2])
            wave = np.cos(ang * 8)
            R = R0 + 0.07 * wave
            y0 = Y0 - 0.10 * (0.5 + 0.5 * wave)
            return np.hypot(rr - R, (Q[:, 1] - y0) * 1.15) - 0.15

        ex = [Fn(skirt, 0.12, BELL, "Glass")]
        ex += [sock(ctx, f"Eye{i}", "Body", BELL) for i in (1, 2)]
        ex += [Tint("ellipsoid", [0.36, 0.2, 0.3], [s * 0.85, -0.25, -0.85], 0.15, BELL) for s in (-1, 1)]   # round cheeks

        def post(Q, d):
            ang = np.arctan2(Q[:, 0], Q[:, 2])
            rib = 0.5 + 0.5 * np.cos(ang * 8)
            low = S.smoothstep(0.55, -0.55, Q[:, 1])
            return d + 0.045 * low * (1 - rib) * (1 - rib) * 1.0
        return Sculpt(None, post, ex, margin=0.15)

    def paint(self, g, field):
        if g != "Body":
            return []
        GLOW = rgb(120, 245, 255)

        def meridians(Q):                                # faint glowing radial lines from the crown
            ang = np.arctan2(Q[:, 0], Q[:, 2])
            rr = np.hypot(Q[:, 0], Q[:, 2])
            w = np.abs(np.sin(ang * 4)) * np.maximum(rr, 0.05) - 0.022
            return np.where((Q[:, 1] > -0.65) & (Q[:, 1] < 0.9) & (rr > 0.25), w, 1.0)
        top = lambda Q: -(Q[:, 1] - 0.2)
        return [Paint(meridians, GLOW, True, 0.55),
                Paint(dots(0.34, 0.03, 0.07, 5, 0.6, mask=top), rgb(215, 250, 255), False, 0.7)]

    def detail(self, g):
        if g == "Body":
            return lambda m: pebble(0.3, 0.012, 4, 0.02) if m == "Glass" else None
        return lambda m: {"Glass": rays((0, 1), (0, 0), 6, 0.15), "Neon": pebble(0.06, 0.04, 2, 0.0)}.get(m)
