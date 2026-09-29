"""GlowBuoyStation (3 stages): wooden raft, tall mast with orbiting light spokes and a big glowing main orb."""
from _bldg_common import *


class Glow(BCfg):
    stage = 1
    body_cells = 230
    body_budget = 7500
    body_k = 0.2
    margin = 0.7
    ST = {1: dict(wood=rgb(176, 128, 88), mast=rgb(112, 134, 158)),
          2: dict(wood=rgb(168, 124, 96), mast=rgb(118, 140, 172)),
          3: dict(wood=rgb(160, 120, 104), mast=rgb(126, 146, 186))}

    def mast_top(self):
        return self.L("Mast")[1] + self.sz["Mast"][1] / 2

    def orb(self):
        return self.L("MainOrb"), self.sz["MainOrb"][0] / 2

    def tweak(self, p):
        st, n = self.stage, p.name
        c = self.ST[st]
        if n == "Base":
            p.color = np.array(c["wood"])
        elif n == "Mast":
            p.color = np.array(c["mast"])
            self.tcap_part(p, 0.7, 0.5)
        elif n == "MastGlowStrip":
            self.tcap_part(p, 0.17, 0.17)
        elif n == "MastCollar":
            p.size = np.array([1.0, 2.8, 2.8])
            p.color = np.array(rgb(96, 108, 128))
        elif n.startswith("BasketStrut"):
            i = int(n[-1]) - 1
            p.color = np.array(PAL["steel"])
            ang = np.radians(90 * i + 45 * (1 if st > 1 else 0) )
            d = np.array([np.cos(ang), 0, np.sin(ang)])

            def fn(m, self=self, d=d):
                oc, r = self.orb()
                top = self.mast_top()
                a = d * 0.4 + (0, top - 0.9, 0)
                b = d * (r * 0.85) + (0, oc[1] - r * 0.35, 0)
                return sd_tcap(m, a, b, 0.24, 0.16)
            setcustom(self, p, fn, (4.5, 5.0, 4.5))
            p.M = p.M.copy(); p.M[1, 3] = self.origin[1] + self.mast_top() + 1.0
        elif n.startswith("UpperCollarStrut"):
            i = int(n[-1]) - 1
            ang = np.radians(90 * i + 45 * (0 if st > 1 else 1))
            d = np.array([np.cos(ang), 0, np.sin(ang)])

            def fn(m, self=self, d=d):
                oc, r = self.orb()
                a = d * (r * 0.95) + (0, oc[1] - r * 0.62, 0)
                b = d * (r * 0.7) + (0, oc[1] + r * 0.55, 0)
                return sd_tcap(m, a, b, 0.17, 0.12)
            setcustom(self, p, fn, (4.5, 4.0, 4.5))
        elif n.startswith("OrbitArm"):
            p.size = np.array([0.36, 0.36, p.size[2]])
        elif n.startswith("OrbitOrb"):
            p.size = p.size * 1.1
        elif n == "CrownRing":
            def fn(m, self=self):
                oc, r = self.orb()
                return spikes(6, r * 0.93, oc[1] + r * 0.1, r * 0.95, 0.34, 0.08, lean=-38)(m)
            setcustom(self, p, fn, (7.0, 3.0, 7.0))
        elif n == "MastTip":
            p.size = np.array([0.7, 0.7, 2.7])

    def pk(self, name, kg):
        base = re.sub(r"\d+$", "", name)
        return {"Mast": 0.3, "MastGlowStrip": 0.08, "MastCollar": 0.25, "BasketStrut": 0.15, "UpperCollarStrut": 0.08, "OrbitArm": 0.1,
                "OrbitOrb": 0.12, "CrownRing": 0.1, "Base": 0.2}.get(base, kg)

    def rounding(self, p):
        return 0.35 if p.name == "Base" else 0.6

    def root_budget(self, g): return 1800 if g == "MainOrb" else 500
    def cells(self, g): return self.body_cells if g == "Base" else 150

    def mat_patterns(self):
        return {"WoodPlanks": planks(0.62, 0.2), "Metal": rust_patina(0.9, 0.08, 6), "CorrodedMetal": rust_patina(0.5, 0.2)}

    def blobs(self, g, mk):
        st = self.stage
        B = []
        if g == "MainOrb":
            oc, r = self.orb()
            B.append(mk(U(torus(oc, r * 1.0, 0.16), torus_x(oc, r * 1.0, 0.13), ell((oc[0], oc[1] - r * 0.98, oc[2]), (0.5, 0.3, 0.5))), 0.1,
                        PAL["gold"] if st == 3 else PAL["steel"], "Metal"))
            return B
        if g != "Base":
            return B
        # rope ring, fenders, cleats, lifebuoy on the raft
        B.append(mk(U(torus((0, 0.05, 0), 3.72, 0.24)), 0.08, rgb(226, 200, 150), "Fabric"))
        fen = [ell((3.42 * np.cos(np.radians(a)), -0.05, 3.42 * np.sin(np.radians(a))), (0.56, 0.42, 0.56)) for a in (45, 135, 225, 315)]
        B.append(mk(U(*fen), 0.1, rgb(232, 84, 66)))
        cleat = [tcap((2.9 * np.cos(np.radians(a)) - 0.25, 0.75, 2.9 * np.sin(np.radians(a))), (2.9 * np.cos(np.radians(a)) + 0.25, 0.75, 2.9 * np.sin(np.radians(a))), 0.17, 0.17)
                 for a in (0, 90, 180, 270)]
        B.append(mk(U(*cleat), 0.1, PAL["steel"], "Metal"))
        B.append(mk(U(torus((1.7, 0.72, -1.4), 0.62, 0.24)), 0.08, rgb(255, 150, 50)))
        B.append(mk(U(*[ell((1.7 + 0.62 * np.cos(np.radians(a)), 0.72, -1.4 + 0.62 * np.sin(np.radians(a))), 0.25) for a in (0, 90, 180, 270)]), 0.05, rgb(250, 246, 232)))
        moss = [moss_at((R * np.cos(np.radians(a)), 0.45, R * np.sin(np.radians(a))), s) for a, R, s in ((-60, 3.1, 0.9), (110, 3.0, 1.0), (200, 3.15, 0.8))]
        B.append(mk(U(*moss), 0.15, PAL["moss"]))
        B.append(mk(barnacles(ring_pts(7, 3.35, 0.45, 20), 0.28, 0.16), 0.05, PAL["barn"]))
        # mast head socket that carries the orb (no floating orb)
        top = self.mast_top()
        oc, r = self.orb()
        B.append(mk(U(tcap((0, top - 0.6, 0), (0, oc[1] - r * 0.85, 0), 0.62, 1.05), ell((0, top - 0.05, 0), (1.05, 0.3, 1.05))), 0.2, PAL["steel"], "Metal"))
        # rigging
        n = {1: 0, 2: 2, 3: 3}[st]
        rig = []
        for i in range(n):
            a = np.radians(120 * i + 60 + (30 if st == 2 else 0))
            rig.append(tcap((0.35 * np.cos(a), top - 2.2 - 0.6 * st, 0.35 * np.sin(a)), (3.2 * np.cos(a), 0.6, 3.2 * np.sin(a)), 0.09, 0.11))
        if rig:
            B.append(mk(U(*rig), 0.05, rgb(226, 200, 150), "Fabric"))
        # bollards with glowing caps
        nb = {1: 0, 2: 4, 3: 6}[st]
        if nb:
            pts = ring_pts(nb, 3.3, 0.5, 45)
            B.append(mk(U(*[tcap(p, (p[0], p[1] + 0.9, p[2]), 0.26, 0.2) for p in pts]), 0.1, rgb(96, 108, 128), "Metal"))
            B.append(mk(U(*[ell((p[0], p[1] + 1.05, p[2]), 0.3) for p in pts]), 0.05, rgb(120, 255, 240), "Neon"))
        return B
