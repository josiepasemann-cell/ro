# Texture Pack: Abyssara – Deep Tide Tycoon

28 stylized, seamless 512×512 RGBA textures for the model buildscripts.
This file is the **source of truth** for texture keys and the buildscript convention.

- Generator: `tools/texture-gen/generate.py` (numpy + Pillow). Re-run with
  `python3 tools/texture-gen/generate.py` (all) or `... generate.py FishScales CoinPile` (some).
- Config: `src/shared/TextureConfig.lua` (key → `Id`, `StudsPerTile`, `Tintable`).
- Runtime: `src/client/TextureApplier.client.lua` fills in `rbxassetid://<Id>`;
  an empty `Id` hides the texture (`Transparency = 1`), so un-uploaded textures never look broken.
- Preview: the model preview renderer loads `assets/textures/<Key>.png` by the same key.

## How the images work

**Tintable (overlay)** textures are white highlights and near-black shadows on a
transparent background. The part's own `Color` shows through, so one texture works on
a pink fish and a blue fish. The Texture's `Color3` multiplies the highlights:
use white or a light version of the part color for bright rims, or a gray to tone them down.

**Baked** textures (`GoldFoil`, `CoinPile`, `LavaCracks`, `BioVeins`) carry their own colors.
Keep `Color3` white. `GoldFoil` and `CoinPile` are opaque. `LavaCracks` and `BioVeins` are mostly transparent except for their glow. Put them on a dark part: LavaCracks goes on charcoal, BioVeins on deep navy or black. A `Neon` or glowing part color underneath is not needed.

## Buildscript convention (all model agents)

One `Texture` instance per textured face:

| Property | Value |
|---|---|
| `Name` | `"Tex_<Key>"` |
| Attribute `TextureKey` | `"<Key>"` (exact key from the table below) |
| CollectionService tag | `"KeyedTexture"` |
| `Texture` | `""`, always empty in the script. The applier sets it at runtime. |
| `Face` | the `Enum.NormalId` to cover |
| `StudsPerTileU` / `StudsPerTileV` | start from the table below, then scale to the part size |
| `Color3`, `Transparency` | the script's choice. For baked textures, keep `Color3` white. |

```lua
local CollectionService = game:GetService("CollectionService")
local function addKeyedTexture(parent, key, face, studsU, studsV, color, transparency)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = studsU
	tex.StudsPerTileV = studsV
	tex.Color3 = color or Color3.new(1, 1, 1)
	tex.Transparency = transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = parent
	return tex
end
```

A `Decal` with the same attribute and tag also works. It stretches instead of tiling.

## Textures

Studs/tile values are for a typical 4–10 stud model and go into both U and V.
Use about half for tiny parts and about double for big terrain.
U runs along the image's horizontal axis, so stripes and grain run along U.

| Key | Look | Studs/tile (U = V) | Tintable | Suits |
|---|---|---|---|---|
| `FishScales` | Rounded overlapping scales with dark outlines and a soft sheen, 8 scales across per tile | 2 | yes | Fish bodies, dragon-fish, pufferfish backs |
| `FishScalesFine` | Same as FishScales at double density (16 across) | 1 | yes | Small fish, fins, tails, baby creatures, NPC fish |
| `SharkSkin` | Soft mottling with horizontal streaks and tiny denticle bumps (subtle) | 3 | yes | Sharks, big predators, IronMawBrute, TrenchWardenBoss |
| `JellyMembrane` | Glowing cell web with soft inner blobs | 2 | yes (use a bright Color3 for glow) | Jellyfish bells, PhantomJelly, bubbles, egg shells |
| `CrabShell` | Scattered round bumps (tubercles) with a mottled base | 1.5 | yes | Crabs, lobsters, claws, SpineDrifter shells |
| `IsopodPlates` | Gently curved horizontal armor bands with a lip and seam | 2 | yes | Isopods, pill-bug and armored enemies, shrimp backs, tails |
| `TurtleShellHex` | Large hexagonal scutes with dark grooves and growth rings, 4×4 per tile | 3 | yes | Turtle shells, armored backs, shields |
| `CoralPorous` | Porous coral: small pits with raised lips | 1.5 | yes | Coral, CoralBarrier, reef decorations, sponges |
| `CrystalFacets` | Flat facets with varied brightness, bright edges, a few sparkles | 2 | yes | Crystals, IceSpire, gems, Mythic accents |
| `GoldFoil` | Crinkled gold leaf, opaque | 2 | **no** (baked gold) | Trophies, chest trim, crowns, gold buildings |
| `CoinPile` | Heap of shiny gold coins with glints, opaque | 3 | **no** (baked gold) | TreasurePile, SunkenChest contents, shop counter, reward props |
| `IceFrost` | Frost cracks at two scales with icy haze and specks | 3 | yes | FrozenSpore, IceSpire, frozen creatures, winter event |
| `LavaCracks` | Glowing orange-yellow cracks over a semi-transparent dark crust | 4 | **no** (baked glow) | MagmaVent, lava creatures, Hadal vents. Put it on a dark part. |
| `GhostWisp` | Soft swirling white wisps, highlights only | 4 | yes | Ghost/phantom creatures, TrenchWisp, Halloween event, portals |
| `MothWing` | Eyespots, fine veins and a dusty sheen | 3 | yes | Moth-/butterfly-fish fins, wings, fancy tails |
| `EelStripes` | Wavy horizontal bands with a bright leading edge and dots | 3 | yes | Eels, ElectricEelTrap, sea snakes, striped fish |
| `SlugSpots` | Glossy round spots with dark rings and tiny dots | 2 | yes | Sea slugs/nudibranchs, cute critters, mushrooms |
| `ToxicBlotches` | Irregular outlined blotches and small dots | 3 | yes (lime/purple Color3) | VenomDrip, poison creatures, ThornSwarmer, event hazards |
| `MetalPanels` | Brushed metal panels with bevels, seams and corner bolts | 2 | yes | Buildings (FilterPlant, towers), machines, hub stalls |
| `RivetedPlates` | Staggered plates with overlapping lips and rows of rivets | 2.5 | yes | Bases, submarine hulls, chests, pipes, bridges |
| `WoodPlanks` | Horizontal planks with grain, staggered joints, nails, a knot | 3 | yes | Docks, shipwreck, crates, SunkenChest, market stands |
| `StoneTiles` | Irregular flagstones with mortar and a bevel | 3 | yes | Floors, foundations, plot base, paths, hub plaza |
| `BasaltRock` | Columnar basalt tops with deep grooves, cracks, pits | 6 | yes | Terrain chunks, cliffs, Hadal rocks, vent bases |
| `SandRipples` | Wavy sand ripples with grain specks | 8 | yes | Sea floor, sand patches, Sun Zone terrain, plot ground |
| `KelpFibers` | Vertical fibers with midribs and small air bladders | 2 | yes | Kelp, seaweed, plant leaves, rope, nets |
| `EggSpeckle` | Dark and light speckles with a soft sheen (subtle) | 1.5 | yes | Common/rare gacha eggs, pickups, pebbles |
| `EggRunes` | Glowing abstract glyphs (circle, spiral, star, wave, chevrons) in a 4×4 grid, no letters | 2 | yes (bright Color3 for glow) | Epic/Mythic eggs, portals, NPC signs, ancient ruins |
| `BioVeins` | Branching cyan glowing veins, transparent elsewhere | 3 | **no** (baked cyan glow) | Bioluminescent creatures, GlowBuoyStation, GlowSporePickup, Midnight Zone accents |

## Uploading (once)

Studio → View → Asset Manager → **Bulk Import** all PNGs from this folder. Then right-click
each image → **Copy Asset ID** and paste it into `Id` in `src/shared/TextureConfig.lua`.
Until then those textures are hidden, and the models keep their plain colors.
