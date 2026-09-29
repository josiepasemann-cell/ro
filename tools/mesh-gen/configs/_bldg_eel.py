"""ElectricEelTrap (3 stages): rock anchor on a stone plinth with a coiled, glowing eel (EelHead group = whole eel)."""
from _bldg_common import *


class Eel(BCfg):
    stage = 1
    body_cells = 210
    body_budget = 6000
    body_k = 0.2
    ST = {1: dict(eel=rgb(38, 78, 140), stripe=rgb(255, 229, 80)),
          2: dict(eel=rgb(30, 84, 158), stripe=rgb(255, 240, 0)),
          3: dict(eel=rgb(30, 70, 168), stripe=rgb(255, 244, 0))}

    def tweak(self, p):
        st, n = self.stage, p.name
        c = self.ST[st]
        if n == "Base":
            p.color = np.array(rgb(92, 98, 114))
        elif n == "RockAnchor":
            p.color = np.array(rgb(96, 86, 86))
            p.size = p.size * np.array([1.05, 1.0, 1.05])
        elif n.startswith("EelBodySegment"):
            p.color = np.array(c["eel"])
            p.size = np.array([p.size[0], p.size[1] * 1.3, p.size[2] * 1.3])
        elif n.startswith("EelStripe"):
            p.size = np.array([p.size[0], 0.7, 0.3])
        elif n == "EelHead":
            p.color = np.array(c["eel"])
            p.size = p.size * 1.2
        elif n.startswith("EelEye"):
            p.size = p.size * 1.7
        elif n == "AnchorGlowRing":
            top = 0.85
            setcustom(self, p, lambda m: sd_ring(m, (0, 0.85, 0), 0.75, 1.55 if self.stage == 2 else 1.65, 0.25, 0.12), (3.6, 0.8, 3.6))
        elif n == "CrownArc":
            fn = spikes(6, 1.2, 0.5, 1.5, 0.28, 0.07, lean=-52, phase=15)
            setcustom(self, p, fn, (6.0, 1.6, 6.0))
        elif n.startswith("AnchorClamp"):
            p.size = p.size * 1.15
        elif n == "ChargeCore":
            p.size = p.size * 1.2

    def pk(self, name, kg):
        base = re.sub(r"\d+$", "", name)
        if base == "Base":
            return 0.2
        return {"RockAnchor": 0.3, "EelBodySegment": 0.34, "EelHead": 0.3, "EelEye": 0.05, "AnchorGlowRing": 0.08, "CrownArc": 0.1, "AnchorClamp": 0.1}.get(base, kg)

    def k(self, g): return 0.2 if g == "Base" else 0.3

    def rounding(self, p):
        return 0.8 if p.name == "EelHead" else (0.6 if p.name != "RockAnchor" else 0.5)

    def root_budget(self, g): return 4200 if g == "EelHead" else 500
    def cells(self, g): return self.body_cells if g in ("Base", "EelHead") else 110
    def tex(self, g): return 640 if g == "Base" else (512 if g == "EelHead" else 256)

    def mat_patterns(self):
        return {"SmoothPlastic": pebble(0.14, 0.12, 2, 0.1), "Rock": pebble(0.5, 0.24, 5, 0.2), "DiamondPlate": diamond(0.12, 0.1),
                "Neon": pebble(0.14, 0.05, 12, 0.0)}

    def head_frame(self):
        h = self.L("EelHead")
        e = (self.L("EelEye1") + self.L("EelEye2")) / 2 - h
        f = np.array([e[0], 0, e[2]])
        f = f / max(np.linalg.norm(f), 1e-6)
        r = np.array([-f[2], 0, f[0]])
        return h, f, r

    def blobs(self, g, mk):
        st = self.stage
        c = self.ST[st]
        B = []
        if g == "EelHead":
            h, f, r = self.head_frame()
            hs = self.sz["EelHead"] * 1.2
            # teeth row + electric frills behind the head
            teeth = []
            for s in (-0.3, -0.15, 0.0, 0.15, 0.3):
                base = h + f * hs[2] * 0.36 + r * s * 1.4 + (0, -hs[1] * 0.28, 0)
                teeth.append(tcap(base, base + (0, -0.16, 0) + f * 0.06, 0.06, 0.02))
            B.append(mk(U(*teeth), 0.02, rgb(250, 248, 236)))
            n = 2 + st
            fr = []
            for s in (-1, 1):
                for i in range(n):
                    a = h + r * s * 0.5 + (0, 0.05 + 0.13 * i, 0) - f * 0.1
                    b = a + r * s * (0.55 + 0.1 * i) - f * (0.45 + 0.12 * i) + (0, 0.25, 0)
                    fr.append(tcap(a, b, 0.12, 0.03))
            B.append(mk(U(*fr, k=0.05), 0.1, c["stripe"], "Neon"))
            return B
        if g != "Base":
            return B
        # rubble, moss, barnacles on the plinth
        rock = [ell((2.6 * np.cos(np.radians(a)), 0.7, 2.6 * np.sin(np.radians(a))), (s * 0.55, s * 0.4, s * 0.5)) for a, s in ((30, 1.0), (150, 0.8), (255, 1.1), (330, 0.6))]
        B.append(mk(U(*rock, k=0.1), 0.12, rgb(96, 86, 86), "Rock"))
        moss = [moss_at((R * np.cos(np.radians(a)), 0.55, R * np.sin(np.radians(a))), s) for a, R, s in ((-75, 2.9, 1.0), (85, 2.85, 0.9), (200, 2.9, 1.1))]
        B.append(mk(U(*moss), 0.15, PAL["moss"]))
        B.append(mk(barnacles(ring_pts(8, 3.15, 0.55, 30), 0.3, 0.17), 0.05, PAL["barn"]))
        if st >= 2:                                    # tesla posts with glowing tips
            n = 3 if st == 2 else 5
            pts = ring_pts(n, 2.95, 0.5, 40)
            posts, tips = [], []
            for p in pts:
                d = np.array([p[0], 0, p[2]]) / 2.95
                top = np.array([p[0], 0, p[2]]) * 0.86 + (0, 2.4 + 0.3 * st, 0)
                posts.append(tcap(p, top, 0.36, 0.24))
                tips.append(ell(top + (0, 0.2, 0), 0.4))
            B.append(mk(U(*posts), 0.1, PAL["steel"], "Metal"))
            B.append(mk(U(*tips), 0.05, c["stripe"], "Neon"))
        return B

    def sculpt(self, g, ctx, dim):
        sc = super().sculpt(g, ctx, dim)
        sc.margin = 0.6 if g in ("Base", "EelHead") else 0.15
        return sc
