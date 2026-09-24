# Terrain Design Notes: **Abyssara – Deep Tide Tycoon**

*As of: 2026-09-24 · Companion to `game-design-doc.md` (Section 8) and
`expansion-concepts.md` (Section 1.1, 2.8) · Basis for the buildscripts
under `/home/user/ro/assets/models/terrain/`*

---

## 0. Purpose

The original terrain chunks for the Sun and Twilight Zones were
essentially flat base surfaces with a few scattered decoration objects
("dunes", "boulders", "kelp"). This document summarizes the research done
before expanding all four zone terrains, and describes how each of the
resulting principles was concretely implemented in the four buildscripts.

## 1. Research: core principles of compelling 3D terrain

Research sources (selection, full list at the end of the document):
Roblox Developer Forum ("Map Design Guidelines", "Large-Scale Roblox
Terrain", "Tips for Beautiful Terrain"), Sandboxr ("Best Practices for Game
Map Layout"), analyses of Subnautica/Abzù level design, as well as Roblox
performance threads on terrain vs. parts.

### 1. Verticality / height rhythm
Height differences create viewpoints, cover, landmarks and an emotional
rhythm (tight vs. open). A consistently flat surface is the single biggest
weakness of the original terrain set.

### 2. Landmarks / points of interest
A visible "landmark chain" keeps players from getting lost, and gives each
zone a distinctive identity ("that's the zone with the rock arch/gate/boss
gate/abyss").

### 3. Sightlines / "leading the eye"
Deliberate lighting, kept-clear sightlines, and formations that guide the
gaze spark curiosity and point the way (without UI) — a core principle from
Subnautica/Abzù, where light and empty spaces are deliberately used as
"breathing room" for navigation.

### 4. Silhouette readability at low-poly
With few polygons, the outline matters most: large, unambiguous block
shapes read better from a distance than many small detail pieces. Fits the
project's existing blocky Roblox style.

### 5. Color palette / contrast between zones
Every zone needs a clearly distinguishable color signature (value and
saturation contrast), so that "depth" is felt even without a UI level
indicator — from bright/warm (Sun Zone) to near-black with isolated neon
accents (Midnight Zone, Hadal Depths).

### 6. Decoration density rhythm (dense vs. open)
Evenly distributed decoration quickly feels monotonous and costs
performance without adding value. Dense "pockets" around landmarks,
alternating with deliberately calm/empty areas, create tension rhythm and
additionally guide attention (a principle from Roblox tycoon/decoration
analyses: dynamic setups beat static ones, but overcrowding hurts load
times/retention).

### 7. Pacing through tight/open transitions
Specifically for cave/deep-sea levels (a Subnautica principle): narrow
passages that open into large caverns/plazas create tension and
recognizable points along the route.

### 8. Performance limits (Roblox-specific)
Roblox terrain (Smooth Terrain) is ideal for very large, homogeneous
surfaces; for controlled, deterministic buildscripts with clear landmarks,
parts + CSG (`UnionAsync`/`SubtractAsync`) are the better choice, because
complex shapes (arches, cave gates, basins) get merged into **one**
performant part instead of needing dozens of individual pieces. PartCount
per chunk was therefore deliberately kept in the low-to-mid three-digit
range.

## 2. Implementation per zone

All four scripts share a recurring composition pattern: a **kept-clear
sightline/lane** from the hub-facing edge to a **landmark at the opposite
end of the zone**, flanked by **dense decoration pockets at the landmarks**
and **calmer areas in between** — this recurring pattern ties the four
very different biomes together stylistically, without making them look the
same.

### Sun Zone (`SunZoneTerrainChunk.lua`, revised)
- **Verticality:** a gentle, round basin ("Tidal Basin") sunk into the sand
  floor via CSG `SubtractAsync` (NegateOperation), plus two stepped dune
  hills with a lighter "sun crest" (color banding as a cheap depth cue).
- **Landmarks (2):** "Sun Gate" rock arch (CSG `UnionAsync` of two pillars
  + a lintel) near the hub edge; a beached shipwreck (blocky hull/bow/
  stern/rib silhouette) deeper in the zone.
- **Sightline:** a kept-clear hub lane (`LANE_HALF_WIDTH`), framed by two
  dune ridges.
- **Density rhythm:** dense rock/coral pockets around both landmarks, calm,
  open sand areas in between.
- **Palette:** warm sand/coral tones (tutorial-friendly).

### Twilight Zone (`TwilightZoneTerrainChunk.lua`, revised)
- **Verticality:** two towering rock spires (CSG `UnionAsync` of stacked,
  slightly offset blocks) plus a long, cut-in rock crevice via
  `SubtractAsync` (canyon character instead of a round basin).
- **Landmark:** "Kelp Arch" — two kelp stalks that curve toward each other
  **along a real curve** (not just rotational sway like the other kelp
  strands) and meet at the top in a glowing neon knot.
- **Sightline:** a narrower hub lane than the Sun Zone (deliberately more
  claustrophobic zone feel), lined with dense rock/kelp walls.
- **Density rhythm:** dense kelp forests at the edges, a clear lane in the
  middle.
- **Palette:** cool, darker gray/blue tones with turquoise-aqua neon
  accents (strong contrast with the Sun Zone).

### Midnight Zone (`MidnightZoneTerrainChunk.lua`, new)
- **Verticality/tight-open rhythm:** a narrow entry passage (dense walls +
  an overhanging ceiling slab) opens into a tall main cavern with
  stalagmites (CSG `UnionAsync` of stacked tiers) and stalactites.
- **Landmark:** arena entrance "The Trench Warden" — a round cave gate cut
  out of a rock block via `SubtractAsync` (NegateOperation), flanked by two
  lava-veined rock spires, in front of a lava-rimmed arena forecourt area
  sunk in via `SubtractAsync`.
- **Light as pathfinding:** since silhouettes are barely readable in the
  dark, glowing lava rifts/pools (`Enum.Material.Neon` + `PointLight`) take
  over the role of the Sun Zone's sightline and mark the walkable path from
  the entrance to the boss gate.
- **Density rhythm:** dense passage, sparse/monumental cavern, dense
  decoration right at the gate (anticipation tension).
- **Palette:** near-black basalt/obsidian + hot orange-red as the sole warm
  accent color.

### Hadal Depths (`HadalDepthsTerrainChunk.lua`, new)
- **Most extreme verticality:** the walkable plateau deliberately covers
  only part of the chunk footprint (`FLOOR_DEPTH < CHUNK_SIZE`) — beyond
  the abyss edge, there is **no floor at all**; tiny "deep glints"
  scattered far below reinforce the sense of bottomlessness.
- **Landmark:** a monumental crystal-spire ensemble (two CSG `UnionAsync`
  clusters of 5 crystal shards each) right at the edge, with a floating
  glass overlook platform jutting out from the edge ("void-tech" struts
  instead of organic shapes).
- **Sightline:** the "Void Lane" (same hub axis as the Midnight Zone) leads
  directly to the overlook platform; crystal fields grow larger toward the
  edge via a scale crescendo (further guiding the gaze).
- **Silhouettes/shape language:** sharp-edged `WedgePart` crystal splinters
  instead of organic curves — a deliberate stylistic break from the three
  more organic preceding zones.
- **Palette:** near-black abyss-violet + a neon quartet (cyan, magenta,
  violet, teal) — the strongest palette contrast of all four zones.

## 3. Technical implementation notes (for maintenance/expansion)

- CSG technique "basin/crevice": a (possibly stretched) `Enum.PartType.Ball`
  is positioned so its center sits exactly on the top edge of the base
  surface (`localY = BASE_TOP_Y`); `SubtractAsync` then removes the lower
  hemisphere, creating a gentle, round depression with depth = vertical
  sphere radius. Same technique, different aspect ratios: round basin (Sun
  Zone/Midnight Zone) vs. elongated canyon (Twilight Zone).
- CSG technique "arch/spire": several parts are arranged overlapping/
  touching and merged into a single part via `UnionAsync` (pillars + lintel
  = arch; stacked, slightly offset tiers = rock spire/stalagmite/crystal
  cluster).
- All `ORIGIN` CFrames in this project are pure translations (no rotation)
  — this significantly simplifies world-space/local-space conversions for
  procedural curves (e.g. the kelp arch).
- Every script stays idempotent (an existing model is removed before the
  rebuild) and exports `PrimaryPart = "ChunkBase"` as well as the `Zone`
  attribute — unchanged from the original pattern.

## 4. Sources (research links)

- [Map Design Guidelines – Roblox DevForum](https://devforum.roblox.com/t/map-design-guidelines-make-your-maps-superior/1293781)
- [Tips for Building Beautiful Terrain – Medium/Developer Baseplate](https://medium.com/roblox-developer/tips-for-building-beautiful-terrain-6a13fd1ba314)
- [Large-Scale Roblox Terrain: The Ultimate Guide – Roblox DevForum](https://devforum.roblox.com/t/large-scale-roblox-terrain-the-ultimate-guide/405672)
- [Best Practices for Game Map Layout: Flow, Landmarks & Player Navigation – Sandboxr](https://sandboxr.com/best-practices-for-game-map-layout-flow-landmarks-player-navigation/)
- [How to Optimize Roblox Art for Better Performance (Low-Poly Tips) – Vasundhara](https://www.vasundhara.io/blogs/how-to-optimize-roblox-art-for-better-performance-low-poly-tips)
- [Roblox Prop Design Tips: 7 Steps to Clean, Performant Props – Nilo](https://nilo.io/articles/roblox-prop-design-tips)
- [Terrain vs Part Performance – Roblox DevForum](https://devforum.roblox.com/t/terrain-vs-part-performance-impact/1647950)
- [Roblox 'Part vs Terrain' Complete Guide – note.com/v_rangers](https://note.com/v_rangers/n/n68619fce16b2?hl=en)
- [Subnautica's Underwater World: A Masterclass in Level Design – YouTube](https://www.youtube.com/watch?v=2ivClz9ZIK8)
- [Too Afraid to Go Deeper: Pervasive Dread in Subnautica – Game Studies](https://gamestudies.org/2404/articles/evans)
- [Roblox Decorations: Behavioral Design and Engagement Strategies – Coohom](https://www.coohom.com/article/roblox-decorations-innovative-strategies-for-immersive-design)
