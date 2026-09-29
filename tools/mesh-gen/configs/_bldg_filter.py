"""FilterPlant (3 stages): chunky steel filtration tanks on a diamond-plate deck, with pipes, gauges and glowing status lights."""
from _bldg_common import *


class Filter(BCfg):
    stage = 1
    extra_roots = r"^StatusLight\d+$"
    body_cells = 220
    body_budget = 7500
    body_k = 0.22
    ST = {
        1: dict(tank=rgb(128, 156, 188), side=rgb(104, 134, 168), R=1.8, cy=4.0, len=6.5),
        2: dict(tank=rgb(120, 166, 208), side=rgb(100, 142, 190), R=2.1, cy=4.3, len=6.5),
        3: dict(tank=rgb(126, 176, 226), side=rgb(104, 152, 206), R=2.3, cy=4.5, len=6.5),
    }

    def tweak(self, p):
        st, n = self.stage, p.name
        c = self.ST[st]
        if n == "Base":
            p.color = np.array(rgb(80, 90, 108))
        elif n == "FoundationFooting":
            p.color = np.array(rgb(104, 108, 116))
        elif n == "MainTank":
            p.color = np.array(c["tank"])
        elif n.startswith("SideTank"):
            p.color = np.array(c["side"])
        elif n.startswith("ConnectorPipe"):
            p.color = np.array(rgb(196, 132, 84))
            sz = 1.0 if n.endswith("1") else -1.0
            if n.endswith("3"):
                sz = 0.0
            cy = c["cy"]

            def fn(m, sz=sz, cy=cy, R=c["R"]):
                if sz == 0.0:                               # S2/S3 third pipe: side tank 3 (x+) to the main tank
                    pts = [(3.2, 2.6, 0.0), (3.2, 3.8, 0.0), (1.0, 3.8, 0.0)]
                else:
                    pts = [(-0.8, 2.6, 2.6 * sz), (-0.8, 3.9, 2.6 * sz), (-0.8, 3.9, 1.2 * sz)]
                d = None
                for a, b in zip(pts[:-1], pts[1:]):
                    di = sd_tcap(m, a, b, 0.26, 0.26)
                    d = di if d is None else np.minimum(d, di)
                for a in pts[1:2]:
                    d = smin(d, sd_ell(m, a, 0.36), 0.1)
                return d
            setcustom(self, p, fn, (5.0, 4.0, 7.0))
            p.M = p.M.copy(); p.M[:3, 3] = self.origin + np.array([0.0, 3.0, 0.0])
        elif n.startswith("SupportLeg"):
            p.color = np.array(rgb(58, 68, 86))
            self.tcap_part(p, 0.4, 0.34)
        elif re.match(r"(Pipe|Tank)?GlowStripe\d|PipeGlowStripe\d", n):
            p.size = np.array([p.size[0], 1.0, 0.16])
        elif n == "ExhaustStack":
            p.color = np.array(rgb(92, 108, 132))
            self.tcap_part(p, 0.85, 0.6)
        elif n == "StackGlowRing":
            def fn(m, self=self):
                cc = self.L("StackGlowRing")
                return sd_ring(m, cc, 0.5, 1.15, 0.24, 0.1)
            setcustom(self, p, fn, (2.6, 0.7, 2.6))
        elif n.startswith("TankRivet"):
            p.size = p.size * 1.3
            p.color = np.array(PAL["barn"])
        elif n.startswith("StatusLight"):
            p.size = p.size * 1.15
            top = c["cy"] + 3.25
            self.drop(p, top + 0.32 - (p.cf[1, 3] - self.origin[1]))

    def pk(self, name, kg):
        base = re.sub(r"\d+$", "", name)
        return {"MainTank": 0.3, "SideTank": 0.25, "ConnectorPipe": 0.3, "SupportLeg": 0.2, "ExhaustStack": 0.25, "StackGlowRing": 0.05,
                "TankRivet": 0.06, "Base": 0.2, "FoundationFooting": 0.15}.get(base, kg)

    def rounding(self, p):
        return {"MainTank": 0.32, "SideTank1": 0.4, "SideTank2": 0.4, "SideTank3": 0.4, "Base": 0.3, "FoundationFooting": 0.4}.get(p.name, 0.6)

    def root_budget(self, g): return 500
    def cells(self, g): return self.body_cells if g == "Base" else 110

    def mat_patterns(self):
        return {"Metal": rust_patina(1.0, 0.07, 6), "DiamondPlate": diamond(0.22, 0.16), "Concrete": pebble(0.35, 0.14, 11, 0.15),
                "Neon": pebble(0.14, 0.05, 12, 0.0)}

    def blobs(self, g, mk):
        st = self.stage
        c = self.ST[st]
        B = []
        if g.startswith("StatusLight"):
            cc = self.L(g)
            r = self.sz[g][0] / 2 * 1.1
            col = tuple(self.cf_color(g))
            B.append(mk(U(torus((cc[0], cc[1] - r * 0.55, cc[2]), r * 0.95, r * 0.16)), 0.05, PAL["steel"], "Metal"))
            return B
        if g != "Base":
            return B
        R, cy = c["R"], c["cy"]
        top = cy + 3.25
        hoop_col = PAL["steel"] if st < 3 else PAL["gold"]
        ys = (cy - 2.3, cy, cy + 2.3) if st == 1 else (cy - 2.4, cy - 0.8, cy + 0.8, cy + 2.4)
        B.append(mk(U(*[torus((0, y, 0), R + 0.03, 0.27) for y in ys]), 0.1, hoop_col, "Metal"))
        bolts = []
        for y in ys:
            for i in range(12):
                a = np.radians(30 * i + (15 if y > cy else 0))
                bolts.append(ell(((R + 0.26) * np.cos(a), y, (R + 0.26) * np.sin(a)), 0.21))
        B.append(mk(U(*bolts), 0.05, PAL["barn"], "Metal"))
        # tank skirt (tank floats 0.25 above the deck in the buildscript), lid and vent
        B.append(mk(U(cyl((0, 0.85, 0), R + 0.35, 0.55, 0.25), cyl((0, top + 0.1, 0), R * 0.72, 0.28, 0.2), tcap((0, top + 0.2, 0), (0, top + 0.75, 0), 0.32, 0.26)), 0.15, rgb(84, 100, 128), "Metal"))
        # railing between the four corner posts
        rl = []
        for (ax, az, bx, bz) in ((-3.5, -3, 3.5, -3), (3.5, -3, 3.5, 3), (3.5, 3, -3.5, 3), (-3.5, 3, -3.5, -3)):
            rl.append(tcap((ax, 2.05, az), (bx, 2.05, bz), 0.16, 0.16))
            rl.append(tcap((ax, 1.25, az), (bx, 1.25, bz), 0.12, 0.12))
        B.append(mk(U(*rl), 0.08, rgb(226, 180, 70), "Metal"))
        B.append(mk(U(*[ell((sx * 3.5, 2.45, sz * 3.0), 0.42) for sx in (-1, 1) for sz in (-1, 1)]), 0.1, rgb(60, 72, 94), "Metal"))
        # pressure gauge on the front of the main tank
        gz = -(R + 0.05)
        B.append(mk(U(tcap((0.9, cy + 0.5, gz), (0.9, cy + 0.5, gz - 0.28), 0.62, 0.55)), 0.06, PAL["gold"], "Metal"))
        B.append(mk(U(tcap((0.9, cy + 0.5, gz - 0.24), (0.9, cy + 0.5, gz - 0.36), 0.46, 0.44)), 0.03, rgb(250, 246, 226)))
        B.append(mk(U(tcap((0.9, cy + 0.5, gz - 0.34), (0.9 + 0.22, cy + 0.72, gz - 0.38), 0.05, 0.03)), 0.02, rgb(230, 60, 60)))
        # valve wheels on the side tanks
        B.append(mk(U(*[torus((0.0, 3.2, sz * 2.6), 0.45, 0.13) for sz in (-1, 1)] + [tcap((0, 2.7, sz * 2.6), (0, 3.2, sz * 2.6), 0.16, 0.16) for sz in (-1, 1)]),
                    0.08, rgb(230, 90, 70), "Metal"))
        # moss and barnacles on the deck
        moss = [moss_at((x, 0.45, z), s) for x, z, s in ((4.3, 3.2, 1.0), (-4.5, 3.0, 0.8), (-4.2, -3.3, 1.1), (4.4, -3.1, 0.7))]
        B.append(mk(U(*moss), 0.15, PAL["moss"]))
        B.append(mk(barnacles([(x, 0.45, z) for x, z in ((-4.7, 0.6), (-4.6, -0.9), (4.7, 1.2), (4.6, -0.4), (2.5, 3.6), (-2.2, -3.6))], 0.32, 0.18), 0.05, PAL["barn"]))
        if st >= 2:                                       # extra intake hopper on the side
            B.append(mk(U(tcap((3.4, 0.5, 2.6), (3.4, 2.4, 2.6), 0.7, 0.4), tcap((3.4, 2.2, 2.6), (3.4, 2.9, 2.6), 0.9, 0.9)), 0.15, rgb(196, 132, 84), "Metal"))
        return B

    def cf_color(self, g):
        return (0, 1, 0)

    def sculpt(self, g, ctx, dim):
        sc = super().sculpt(g, ctx, dim)
        sc.margin = 0.6 if g == "Base" else 0.15
        return sc
