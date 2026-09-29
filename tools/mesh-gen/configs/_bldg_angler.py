"""AnglerfishTower (all 3 stages): stacked stone/metal tower with an illicium rod and a glowing lure."""
from _bldg_common import *


class Angler(BCfg):
    stage = 1
    extra_roots = None
    body_cells = 210
    body_budget = 6500
    body_k = 0.18
    lift = 1.0
    TOWER = {1: (rgb(56, 84, 128), rgb(88, 96, 120)), 2: (rgb(62, 84, 148), rgb(92, 96, 124)), 3: (rgb(78, 76, 160), rgb(98, 96, 130))}

    def tweak(self, p):
        st = self.stage
        n = p.name
        tower, stone = self.TOWER[st]
        if n == "Base":
            p.color = np.array(stone)
        elif n.startswith("TowerSegment"):
            p.color = np.array(tower)
            p.size = np.array([p.size[0], p.size[1] * self.TW, p.size[2] * self.TW])
        elif n == "ArmSocket":
            p.size = np.array([0.7, 1.0, 1.0])
            p.color = np.array(PAL["steel"]) * 0.6
        elif n.startswith("IlliciumSegment"):
            ra, rb = {1: (0.27, 0.21), 2: (0.31, 0.23), 3: (0.35, 0.25)}[st]
            self.tcap_part(p, ra, rb)
            p.color = np.array(rgb(60, 66, 84))
        elif n.startswith("SpineFin"):
            cfp, hgt = p.cf[:3, 3].copy(), float(p.size[1])
            size0 = np.array([1.6, hgt + 0.8, 1.6])

            def fn(m, self=self, cfp=cfp, hgt=hgt):
                c = cfp - self.origin
                R = float(np.hypot(c[0], c[2]))
                d = np.array([c[0], 0, c[2]]) / max(R, 1e-6)
                a = d * (R - 0.35) + (0, c[1] - hgt * 0.45, 0)
                b = d * (R + 0.75) + (0, c[1] + hgt * 0.55, 0)
                return sd_tcap(m, a, b, 0.3, 0.07)
            setcustom(self, p, fn, size0)
        elif n == "FoundationTrimBand":
            p.size = np.array([1.0, 6.3, 6.3])
            p.color = np.array(PAL["steel"]) * 0.55
        elif n.startswith("FoundationRivet"):
            p.size = np.array([0.7, 0.7, 0.7])
            self.drop(p, -0.28)
        elif n == "CrownSpikeCluster":
            y0 = self.crown_y
            fn = spikes(6, 1.25, y0, 1.7, 0.3, 0.07, lean=-22)
            setcustom(self, p, fn, (4.6, 2.6, 4.6))
            p.M = p.M.copy(); p.M[1, 3] = self.crown_y + self.origin[1] + 0.9

    crown_y = 11.15
    TW = 1.12

    def pk(self, name, kg):
        if name.startswith("TowerSegment"):
            return 0.5
        if name.startswith("IlliciumSegment"):
            return 0.3
        if name.startswith("Foundation"):
            return 0.3
        if name.startswith("SpineFin"):
            return 0.12
        return kg

    def rounding(self, p):
        if p.name.startswith("SpineFin"):
            return 0.35
        if p.name.startswith("TowerSegment"):
            return 0.5
        return 0.6

    def root_budget(self, g): return 900
    def cells(self, g): return self.body_cells if g == "Base" else 130

    def blobs(self, g, mk):
        st = self.stage
        B = []
        if g == "LureOrb":
            c = self.L("LureOrb")
            r = self.sz["LureOrb"][0] / 2
            n = {1: 3, 2: 5, 3: 7}[st]
            fil = []
            for i in range(n):
                a = np.radians(360 / n * i + 20)
                s = np.array([np.cos(a), 0, np.sin(a)])
                p0 = c + s * r * 0.55 + np.array([0, -r * 0.72, 0])
                p1 = p0 + s * r * 0.35 + np.array([0, -r * (0.7 + 0.15 * (i % 2)), 0])
                fil.append(tcap(p0, p1, 0.11, 0.05))
            B.append(mk(U(*fil, k=0.05), 0.12, rgb(230, 170, 255), "Neon"))
            return B
        if g != "Base":
            return B
        segs = sorted([k for k in self.cf if k.startswith("TowerSegment")])
        hoop, gold, bolt = PAL["steel"], PAL["gold"], PAL["barn"]
        hoops, bolts = [], []
        for nme in segs:
            c, sz = self.L(nme), self.sz[nme]
            h, d = sz[0], sz[1] * self.TW
            y0 = c[1] - h / 2
            hoops.append(torus((0, y0 + 0.3, 0), d / 2 + 0.03, 0.25))
            bolts.append(spheres_on_ring(8, d / 2 + 0.2, y0 + 0.3, 0.23, phase=(20 if nme[-1] in "13" else 0)))
        top = self.L(segs[-1]); topy = top[1] + self.sz[segs[-1]][0] / 2
        hoops.append(torus((0, topy - 0.12, 0), self.sz[segs[-1]][1] * self.TW / 2 + 0.04, 0.24))
        B.append(mk(U(*hoops), 0.1, gold if st == 3 else hoop, "Metal"))
        B.append(mk(U(*bolts), 0.05, PAL["barn"] if st < 3 else PAL["gold"], "Metal"))
        # anglerfish face on the first tier: two big cartoon eyes
        c1, h1, d1 = self.L("TowerSegment1"), self.sz["TowerSegment1"][0], self.sz["TowerSegment1"][1] * self.TW
        er = {1: 0.62, 2: 0.7, 3: 0.8}[st]
        ic = {1: (0.72, 0.4, 1.0), 2: (0.9, 0.3, 1.0), 3: (1.0, 0.25, 0.95)}[st]
        for sgn in (-1, 1):
            ang = np.radians(270 + 33 * sgn)
            dd = np.array([np.cos(ang), 0, np.sin(ang)])
            ctr = dd * (d1 / 2 - 0.02) + (0, c1[1] + h1 * 0.12, 0)
            B += eye_blobs(mk, ctr, dd, er, ic)
        # moss tufts + barnacles on the plinth
        moss = []
        for a, R, s in ((-60, 2.85, 1.0), (100, 2.7, 0.85), (205, 2.9, 1.1), (-125, 2.7, 0.7)):
            ca = np.array([R * np.cos(np.radians(a)), 0.55, R * np.sin(np.radians(a))])
            for dx, dz, dy, rr in ((0, 0, 0, .42), (.35, .1, .05, .3), (-.28, .22, .0, .28), (.05, -.3, .05, .26)):
                moss.append(ell(ca + np.array([dx, dy, dz]) * s, (rr * s * 1.1, rr * s * 0.7, rr * s * 1.1)))
        B.append(mk(U(*moss, k=0.12), 0.15, PAL["moss"]))
        barn = []
        for i, pt in enumerate(ring_pts(7, 3.05, 0.55, 12)):
            h = 0.28 + 0.14 * ((i * 7) % 3)
            barn.append(tcap(pt, (pt[0] * 0.98, pt[1] + h, pt[2] * 0.98), 0.17, 0.09))
        B.append(mk(U(*barn), 0.05, PAL["barn"]))
        if st >= 2:                                   # stone buttresses hugging the tower foot
            R0 = self.sz["TowerSegment1"][1] * self.TW / 2
            n = 4 if st == 2 else 5
            bt = [tcap((R0 + 0.55) * np.array([np.cos(np.radians(360 / n * i + 45)), 0, np.sin(np.radians(360 / n * i + 45))]) + (0, 0.5, 0),
                       (R0 - 0.15) * np.array([np.cos(np.radians(360 / n * i + 45)), 0, np.sin(np.radians(360 / n * i + 45))]) + (0, 2.9 if st == 2 else 3.4, 0),
                       0.4, 0.2) for i in range(n)]
            B.append(mk(U(*bt), 0.25, self.TOWER[st][1], "Cobblestone"))
        if st == 3:                                   # fang ring at the crown collar + gold second hoop
            B.append(mk(U(torus((0, self.crown_y - 0.05, 0), 1.05, 0.36)), 0.15, PAL["gold"], "Metal"))
            fang = spikes(8, 3.0, 0.5, 1.15, 0.26, 0.05, lean=14, phase=22)
            B.append(mk(fang, 0.1, PAL["barn"]))
        return B

    def post(self, g, dim): return None

    def sculpt(self, g, ctx, dim):
        sc = super().sculpt(g, ctx, dim)
        sc.margin = 0.7 if g == "LureOrb" else self.margin
        return sc
