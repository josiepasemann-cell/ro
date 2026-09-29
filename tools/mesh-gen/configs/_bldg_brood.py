"""BroodPool (3 stages): round stone brood pool with glowing water, floating eggs held in kelp nests, pillars."""
from _bldg_common import *


def ripples(P):
    r = np.hypot(P[:, 0], P[:, 2])
    h = 0.5 + 0.5 * np.cos(r * 8.0 + 1.5 * S.fbm(P * 0.6, 3, 2))
    return h.astype(np.float32), (1 + 0.16 * (h - 0.5)).astype(np.float32), (0.05 * h).astype(np.float32)


class Brood(BCfg):
    stage = 1
    body_cells = 220
    body_budget = 7500
    body_k = 0.2
    extra_roots = r"^GlowWater$"
    # rim top, floor top, outer centre y, outer height, basin colour, pillar height
    ST = {
        1: dict(cy=2.2, h=3.0, floor=1.0, col=rgb(126, 160, 178), pil=3.2, pcol=rgb(104, 122, 146)),
        2: dict(cy=2.2, h=3.4, floor=0.8, col=rgb(104, 152, 206), pil=3.2, pcol=rgb(110, 132, 170)),
        3: dict(cy=2.2, h=3.6, floor=0.7, col=rgb(110, 138, 226), pil=4.0, pcol=rgb(122, 140, 186)),
    }

    def rim_top(self): return self.ST[self.stage]["cy"] + self.ST[self.stage]["h"] / 2

    def tweak(self, p):
        st, n = self.stage, p.name
        c = self.ST[st]
        top = self.rim_top()
        if n == "Base":
            p.color = np.array(rgb(88, 96, 114))
        elif n == "PoolBasin":
            p.color = np.array(c["col"])
            cy, h, fl = c["cy"], c["h"], c["floor"]

            def fn(m, cy=cy, h=h, fl=fl, top=top):
                outer = sd_cyl(m, (0, cy, 0), 5.5, h / 2, 0.3)
                yc = (fl + top + 1.5) / 2
                inner = sd_cyl(m, (0, yc, 0), 4.7, (top + 1.5 - fl) / 2, 0.18)
                return smax(outer, -inner, 0.1)
            setcustom(self, p, fn, (11.2, h + 0.4, 11.2))
        elif n == "GlowWater":
            p.size = np.array([1.8, 9.0, 9.0])
        elif n == "RimGlowRing":
            setcustom(self, p, lambda m, top=top: sd_ring(m, (0, top - 0.05, 0), 4.85, 5.35, 0.16, 0.08), (10.8, 0.5, 10.8))
        elif re.match(r"Egg\d", n):
            p.kind = "ellipsoid"
            p.size = np.array(p.raw["size"], float) * 1.05
        elif n.startswith("SupportPillar"):
            p.color = np.array(c["pcol"])
            self.tcap_part(p, 0.62, 0.52)
        elif n.startswith("PillarGlowStrip"):
            self.tcap_part(p, 0.15, 0.15)
        elif n == "UpperCollarRing":
            y = 3.4 if st == 2 else 4.0
            cs = [(4.4, y, 4.4), (-4.4, y, 4.4), (-4.4, y, -4.4), (4.4, y, -4.4)]
            fn = U(*[tcap(cs[i], cs[(i + 1) % 4], 0.32, 0.32) for i in range(4)])
            setcustom(self, p, fn, (10.4, 1.2, 10.4))
        elif n == "CrownSpireCluster":
            fn = spikes(6, 5.15, top - 0.15, 2.9, 0.4, 0.09, lean=14)
            setcustom(self, p, fn, (12.2, 4.0, 12.2))
            p.M = p.M.copy(); p.M[1, 3] = self.origin[1] + top + 1.2
        elif n == "CrownCore":
            p.size = np.array([2.4, 2.4, 2.4])
        elif n.startswith("FoundationPebble"):
            p.size = p.size * 1.25
        elif n.startswith("CoralNub"):
            p.size = p.size * 1.1

    def pk(self, name, kg):
        base = re.sub(r"\d+$", "", name)
        return {"PoolBasin": 0.3, "GlowWater": 0.06, "SupportPillar": 0.25, "RimGlowRing": 0.05, "UpperCollarRing": 0.15,
                "PillarGlowStrip": 0.1, "Egg": 0.05, "CrownCore": 0.2, "CoralNub": 0.2, "FoundationPebble": 0.2}.get(base, kg)

    def rounding(self, p):
        return 0.3 if p.name == "GlowWater" else 0.6

    def mat_patterns(self):
        return {"Neon": ripples, "SmoothPlastic": pebble(0.3, 0.09, 2, 0.1), "Glass": pebble(0.9, 0.04, 4, 0.02)}

    def blobs(self, g, mk):
        st = self.stage
        top = self.rim_top()
        B = []
        if g != "Base":
            return B
        # nests of kelp around the egg slots (eggs sit in the water, no floating)
        eggs = [np.array(self.L(f"Egg{i}")) for i in (1, 2, 3)]
        nest = [torus((e[0], 2.75, e[2]), 1.0 + 0.05 * st, 0.17) for e in eggs]
        nest += [tuft((e[0], 2.7, e[2]), 5, 0.55, 1.05, 0.11, phase=20 * i) for i, e in enumerate(eggs)]
        B.append(mk(U(*nest), 0.1, PAL["kelp"], "Fabric"))
        # moss on the base ring, barnacles + a metal belt round the basin
        moss = [moss_at((R * np.cos(np.radians(a)), 0.55, R * np.sin(np.radians(a))), s) for a, R, s in ((-80, 6.4, 1.1), (20, 6.3, 0.9), (115, 6.4, 1.2), (200, 6.3, 1.0), (-140, 6.35, 0.8))]
        B.append(mk(U(*moss), 0.15, PAL["moss"]))
        B.append(mk(barnacles(ring_pts(13, 6.55, 0.5, 8), 0.34, 0.2), 0.05, PAL["barn"]))
        belt_y = 1.75
        B.append(mk(U(torus((0, belt_y, 0), 5.5, 0.22 + 0.03 * st)), 0.08, PAL["gold"] if st == 3 else PAL["steel"], "Metal"))
        B.append(mk(U(*[ell(p, 0.27) for p in ring_pts(16, 5.72, belt_y, 5)]), 0.05, PAL["barn"], "Metal"))
        if st >= 2:                                    # pillar caps
            caps = [ell((x, self.ST[st]["pil"] + 0.05, z), (0.68, 0.42, 0.68)) for x in (-4.4, 4.4) for z in (-4.4, 4.4)]
            B.append(mk(U(*caps), 0.15, PAL["gold"] if st == 3 else PAL["steel"], "Metal"))
        if st == 3:                                    # energy geyser from the water up to the crown core
            B.append(mk(U(tcap((0, 2.6, 0), (0, 6.8, 0), 0.6, 0.35), ell((0, 2.85, 0), (1.3, 0.35, 1.3)), k=0.3), 0.2, rgb(255, 130, 240), "Neon"))
        return B

    def sculpt(self, g, ctx, dim):
        sc = super().sculpt(g, ctx, dim)
        sc.margin = 0.6
        return sc

    def root_budget(self, g): return 900
    def cells(self, g): return self.body_cells if g == "Base" else 150
    def tex(self, g): return 704 if g == "Base" else 384
