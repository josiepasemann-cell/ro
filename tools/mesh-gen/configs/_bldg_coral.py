"""CoralBarrier (3 stages): coral mound ringed by staghorn spikes, cradling a glowing slow-pulse core."""
from _bldg_common import *


class Coral(BCfg):
    stage = 1
    body_cells = 210
    body_budget = 6500
    body_k = 0.22
    # per stage: ring R, spike centre y, length(size y), width(size x), inner R, inner y0, inner len, tip y, core y, core r
    ST = {
        1: dict(R=2.6, cy=2.0, h=1.8, w=0.6, col=rgb(255, 140, 120), stone=rgb(92, 98, 114)),
        2: dict(R=2.8, cy=2.2, h=2.1, w=0.7, col=rgb(255, 100, 190), stone=rgb(96, 100, 122)),
        3: dict(R=3.0, cy=2.4, h=2.4, w=0.8, col=rgb(255, 84, 178), stone=rgb(102, 104, 128)),
    }

    def tweak(self, p):
        st, n = self.stage, p.name
        c = self.ST[st]
        if n == "Base":
            p.color = np.array(c["stone"])
        elif n in ("CoralMound", "CoralRing"):
            p.color = np.array(c["col"])
        elif n == "CoralRing":
            pass
        if n == "CoralRing":
            w, h = c["w"], c["h"]
            fn = spikes(8, c["R"], c["cy"] - h / 2 - 0.35, h + 0.35, w * 0.66, w * 0.2, lean=-7, phase=0)
            setcustom(self, p, fn, (2 * c["R"] + 2 * w, h + 0.6, 2 * c["R"] + 2 * w))
        elif n == "InnerRing":
            R = 1.5 if st == 2 else 1.6
            cy = 2.0 if st == 2 else 2.2
            h = 1.2 if st == 2 else 1.4
            fn = spikes(6, R, cy - h / 2 - 0.3, h + 0.3, 0.3, 0.1, lean=6, phase=30)
            setcustom(self, p, fn, (2 * R + 1, h + 0.6, 2 * R + 1))
        elif n == "BaseGlowRing":
            cy = 0.75 if st == 2 else 0.8
            rin, rout = (2.9, 3.2) if st == 2 else (3.1, 3.4)
            setcustom(self, p, lambda m, cy=cy, rin=rin, rout=rout: sd_ring(m, (0, cy, 0), rin, rout, 0.17, 0.08), (2 * rout, 0.5, 2 * rout))
        elif n == "CrownSpikeCluster":
            fn = spikes(6, 0.95, 3.75, 1.7, 0.26, 0.07, lean=-18, phase=0)
            setcustom(self, p, fn, (3.4, 2.4, 3.4))
        elif n.startswith("SpikeTip"):
            p.size = p.size * 1.15
        elif n.startswith("BasePebble"):
            p.size = p.size * np.array([1.2, 1.2, 1.2])
        elif n.startswith("PulseOrbit"):
            p.size = p.size * 1.1

    def pk(self, name, kg):
        return {"CoralMound": 0.4, "CoralRing": 0.3, "InnerRing": 0.2, "BaseGlowRing": 0.06, "SpikeTip": 0.05, "CrownSpikeCluster": 0.15}.get(
            re.sub(r"\d+$", "", name), kg)

    def rounding(self, p):
        return 0.6

    def root_budget(self, g): return 1100
    def cells(self, g): return self.body_cells if g == "Base" else 140

    def mat_patterns(self):
        return {"SmoothPlastic": pebble(0.24, 0.16, 2, 0.12)}

    def blobs(self, g, mk):
        st = self.stage
        c = self.ST[st]
        col = c["col"]
        B = []
        if g == "SlowPulseCore":
            cc = self.L("SlowPulseCore")
            r = self.sz["SlowPulseCore"][0] / 2
            # glowing polyp frills around the core equator
            B.append(mk(tuft(cc + (0, -r * 0.2, 0), 6 + 2 * st, r * 0.6, r * 1.15, r * 0.14, phase=15, k=0.0), 0.08, rgb(170, 255, 240), "Neon"))
            return B
        if g != "Base":
            return B
        core_y = {1: 3.4, 2: 3.6, 3: 3.9}[st]
        core_r = {1: 0.7, 2: 0.9, 3: 1.1}[st]
        # cradle fingers that hold the core (no floating parts)
        n = {1: 4, 2: 5, 3: 6}[st]
        fing = []
        Rb, Rt = (1.7, 1.0) if st == 1 else ((1.85, 1.25) if st == 2 else (2.0, 1.5))
        for i in range(n):
            a = np.radians((45 if st == 1 else 0) + 360 / n * i)
            d = np.array([np.cos(a), 0, np.sin(a)])
            p0 = d * Rb + (0, 1.6, 0)
            p1 = d * (Rb - 0.15) + (0, 2.55, 0)
            p2 = d * Rt + (0, core_y - 0.1, 0)
            fing += [tcap(p0, p1, 0.4, 0.3), tcap(p1, p2, 0.3, 0.2)]
            if st == 3:
                fing.append(tcap(p2, d * 0.95 + (0, core_y, 0), 0.16, 0.12))
        B.append(mk(U(*fing, k=0.15), 0.25, col))
        # coral branchlets / anemone tufts between the big spikes, pebbles nub
        nub = []
        for i in range(8):
            a = np.radians(22.5 + 45 * i)
            R = c["R"] - 0.55
            nub.append(tcap((R * np.cos(a), 1.2, R * np.sin(a)), ((R - 0.15) * np.cos(a), 1.7 + 0.25 * (i % 3), (R - 0.15) * np.sin(a)), 0.3, 0.16))
        B.append(mk(U(*nub), 0.2, rgb(255, 176, 150) if st == 1 else rgb(255, 150, 215)))
        # moss + barnacles on the stone plinth
        moss = [moss_at((R * np.cos(np.radians(a)), 0.55, R * np.sin(np.radians(a))), s) for a, R, s in ((-70, 3.0, 1.0), (60, 3.0, 0.8), (170, 3.05, 1.0), (245, 2.95, 0.7))]
        B.append(mk(U(*moss), 0.15, PAL["moss"]))
        B.append(mk(barnacles(ring_pts(9, 3.15, 0.5, 14), 0.32, 0.17), 0.05, PAL["barn"]))
        if st >= 2:                                   # starfish on the front + glowing ring studs
            sc = np.array([0.0, 0.68, -2.45])
            arms = []
            for i in range(5):
                a = np.radians(72 * i + 90)
                arms.append(tcap(sc, sc + (0.85 * np.cos(a), 0, 0.85 * np.sin(a)), 0.25, 0.1))
            B.append(mk(U(*arms, k=0.1), 0.12, rgb(255, 170, 60)))
        if st == 3:
            gold = [ell(p, 0.2) for p in ring_pts(12, 3.25, 0.98, 5)]
            B.append(mk(U(*gold), 0.05, PAL["gold"], "Metal"))
        return B

    def sculpt(self, g, ctx, dim):
        sc = super().sculpt(g, ctx, dim)
        sc.margin = 0.5
        return sc
