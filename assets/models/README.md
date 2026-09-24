# Abyssara – Deep Tide Tycoon: 3D Assets (MVP Scope)

These buildscripts generate the 3D geometry for the MVP scope (Sun Zone +
Twilight Zone) of **Abyssara – Deep Tide Tycoon**, per Section 8 and
Section 10 of the Game Design Document (`/home/user/ro/docs/game-design-doc.md`).
The terrain chunks for all 4 zones (including the Midnight Zone and Hadal
Depths planned for Phase 2/3, see `/home/user/ro/docs/expansion-concepts.md`
Section 1.1 / 2.8) have been significantly expanded — details, research
sources and the design principles behind them are in
`/home/user/ro/docs/terrain-design-notes.md`.

This is **pure geometry generation only** (Luau, `Instance.new`/`CFrame`/CSG
union operations). It contains **no gameplay logic** (no controls, no
economy, no collision/raid logic) — that is deliberately added later by the
code agent.

## Asset overview

### `terrain/` – Environment
All 4 zone chunks follow a recurring composition pattern since the terrain
expansion (see `/home/user/ro/docs/terrain-design-notes.md`): a kept-clear
sightline/lane from the hub-facing edge to a distinctive landmark at the
opposite end of the zone, with height variation and CSG (`UnionAsync`/
`SubtractAsync`) instead of purely flat surfaces. Chunk size was increased
from 50 to 90-120 studs for this.

| File | Asset | Description |
|---|---|---|
| `HabitatPlotBase.lua` | Modular Habitat Plot base | Hexagonal platform (~60 studs flat-to-flat), CSG hexagon, 6 visibly marked build fields (neon sector lines + slot markers) |
| `SunZoneTerrainChunk.lua` | Seabed terrain, Sun Zone | Bright, sandy low-poly floor (100 studs) with CSG basin, 2 dune hills, rock arch landmark "Sun Gate" (CSG union) and a beached shipwreck as second landmark |
| `TwilightZoneTerrainChunk.lua` | Seabed terrain, Twilight Zone | Dark, rocky low-poly floor (100 studs) with CSG rock crevice, 2 CSG rock spires and a procedurally curved kelp arch landmark |
| `MidnightZoneTerrainChunk.lua` | Cave/lava-rift terrain, Midnight Zone (new, Phase 2) | Dark basalt cave system (110 studs): narrow entry passage -> open cavern with stalagmites/stalactites and glowing lava rifts/pools (Neon + PointLight) -> arena entrance landmark "The Trench Warden" (CSG cave gate + lava rock spires) |
| `HadalDepthsTerrainChunk.lua` | Abyss/crystal terrain, Hadal Depths (new, Phase 3) | Walkable plateau (120 stud footprint, 78 studs deep) ending at a sheer, bottomless abyss edge; crystal fields (WedgePart splinters, neon quartet) with a scale crescendo to a monumental CSG crystal-spire landmark and a floating overlook platform |

### `buildings/` – Buildings (base stage each)
| File | Asset | Description |
|---|---|---|
| `BroodPool_Basic.lua` | Brood Pool (Stage 1/3) | Round basin (CSG subtraction), glowing water, 3 egg placeholders |
| `GlowBuoyStation.lua` | Glow Buoy Station | Mast with main glow orb + 3 satellite orbs |
| `FilterPlant.lua` | Filter Plant | Main tank + 2 side tanks, pipes, status light |
| `AnglerfishTower.lua` | Defense tower: Anglerfish Tower | Tapered tower shaft, curved illicium with lure orb (target/muzzle point) |
| `CoralBarrier.lua` | Defense tower: Coral Barrier (area slow/tank) | Ø7-stud base like AnglerfishTower, CSG-welded coral spike ring, neon-turquoise pulse core `SlowPulseCore` (LureOrb equivalent) + `MuzzlePoint` attachment |
| `ElectricEelTrap.lua` | Defense tower: Electric Eel Trap (chain damage) | Ø7-stud base like AnglerfishTower, coiled eel body around a rock anchor, attack origin `EelHead` + `MuzzlePoint` attachment, visible `ChargeCore` part (+ `ChargeLight`) for a later charge-state indicator |

### `buildings/` – Upgrade stages 2/3 (content update, upgrade system)
Two more buildscripts per base building, for Stage 2 and Stage 3, used by
the upgrade system (code agent) via model swap. **Naming convention:** file
and model name are `<BuildingId>_Stage2` / `<BuildingId>_Stage3` (the
`BuildingId` from `BuildingConfig.lua`, NOT the `TemplateName` of the
Stage-1 template — e.g. `BroodPool_Stage2`/`BroodPool_Stage3` instead of
`BroodPool_Basic_Stage2`, since the upgrade system looks up exactly
`"<BuildingId>_Stage2"`/`"_Stage3"` as specified). Every stage has an
**identical `Base` foundation** (size/shape/offset) to the Stage-1 template
for grid compatibility, unchanged required part/attachment names (`LureOrb`,
`SlowPulseCore`, `EelHead`, `MuzzlePoint`, `ChargeCore` stays a DIRECT child
of the Model, `StatusLight`, `EggSlot1`-`EggSlot3`), attributes
`BuildingType` (unchanged) and `Stage` (`2`/`3`). Placement for testing:
Stage 2 at `z = -140`, Stage 3 at `z = -160`, 15 studs apart on the X axis
in the order BroodPool/GlowBuoyStation/FilterPlant/AnglerfishTower/
CoralBarrier/ElectricEelTrap. Stage 2 adds more structure + glow, Stage 3 is
the lavish final stage (CSG-welded crowns/rings, extra glow elements,
subtle particle accents at a low rate), with Stage 3 PartCount deliberately
kept at roughly double Stage 1 at most.

| File | Asset | Description |
|---|---|---|
| `BroodPool_Stage2.lua` | Brood Pool (Stage 2/3) | Taller CSG basin ring, neon rim ring, 4 pillar glow strips, CSG-welded `UpperCollarRing` |
| `BroodPool_Stage3.lua` | Brood Pool (Stage 3/3) | All Stage-2 elements, plus CSG thorn crown `CrownSpireCluster`, floating `CrownCore` with `PointLight`, `BubbleEmitter` (rate 4) |
| `GlowBuoyStation_Stage2.lua` | Glow Buoy Station (Stage 2/3) | Taller mast, 2nd strut ring `UpperCollarStrut1-4`, larger `MainOrb`, 4 instead of 3 `OrbitOrb`, `MastGlowStrip` |
| `GlowBuoyStation_Stage3.lua` | Glow Buoy Station (Stage 3/3) | Even taller mast, CSG-welded `CrownRing` around `MainOrb` (+ `PointLight`), 6 `OrbitOrb`, `SparkleEmitter` (rate 5) |
| `FilterPlant_Stage2.lua` | Filter Plant (Stage 2/3) | 3rd side tank, 3rd pipe, `PipeGlowStripe` neon accents, 2nd `StatusLight2` (original `StatusLight` stays) |
| `FilterPlant_Stage3.lua` | Filter Plant (Stage 3/3) | All Stage-2 elements, `ExhaustStack` with CSG `StackGlowRing`, 3rd `StatusLight3`, `SteamEmitter` (rate 4) |
| `AnglerfishTower_Stage2.lua` | Defense tower: Anglerfish Tower (Stage 2/3) | 4 instead of 3 tower segments, 4 `SpineFin` accents, larger/brighter `LureOrb` (+ `PointLight`) |
| `AnglerfishTower_Stage3.lua` | Defense tower: Anglerfish Tower (Stage 3/3) | All Stage-2 elements, CSG `CrownSpikeCluster` on the tower head, 4-piece illicium rod, `SparkleEmitter` (rate 5) |
| `CoralBarrier_Stage2.lua` | Defense tower: Coral Barrier (Stage 2/3) | Larger base, CSG `BaseGlowRing`, CSG `InnerRing` made of short spikes, larger `SlowPulseCore` (+ `PointLight`) |
| `CoralBarrier_Stage3.lua` | Defense tower: Coral Barrier (Stage 3/3) | All Stage-2 elements, CSG `CrownSpikeCluster` above the core, 2 `PulseOrbit` accents, `PulseEmitter` (rate 4) |
| `ElectricEelTrap_Stage2.lua` | Defense tower: Electric Eel Trap (Stage 2/3) | 8 instead of 6 body segments, CSG `AnchorGlowRing`, larger `ChargeCore` (+ `PointLight`) |
| `ElectricEelTrap_Stage3.lua` | Defense tower: Electric Eel Trap (Stage 3/3) | 10 body segments, CSG `CrownArc` at the rock anchor base, larger `ChargeCore`, `ChargeSparkEmitter` (rate 4) |

### `creatures/` – Creatures (MVP set, 6 models)
| File | Asset | Rarity (placeholder) | Zone |
|---|---|---|---|
| `GlowJelly.lua` | Glow Jelly | Common | SunZone |
| `GlowShrimp.lua` | Glow Shrimp | Common | SunZone |
| `GlowRay.lua` | Glow Ray (free 6th pick) | Uncommon | SunZone |
| `Anglerfish.lua` | Anglerfish | Rare | TwilightZone |
| `BioluminescentEel.lua` | Bioluminescent Eel | Epic | TwilightZone |
| `CrystalKraken.lua` | Crystal Kraken | Legendary | TwilightZone |

### `creatures/` – Event-exclusive creatures (Content Update 1, Section 2.3)
| File | Asset | Rarity (placeholder) | Event |
|---|---|---|---|
| `ToxinPuffer.lua` | Toxin Puffer | Rare | ToxicTide |
| `PhantomJelly.lua` | Phantom Jelly | Epic | SpookyTide |
| `BloomMoth.lua` | Bloom Moth | Uncommon | BioluminescentBloom |
| `FrostAnglerPup.lua` | Frost Angler Pup | Rare | FrozenCurrent |
| `EmberSlug.lua` | Ember Slug | Uncommon | VolcanicVent |
| `VentDrake.lua` | Vent Drake | Legendary | VolcanicVent |
| `GoldGuppy.lua` | Gold Guppy | Rare | TreasureTide |
| `TreasureTurtle.lua` | Treasure Turtle | Epic | TreasureTide |

### `creatures/` – Zone 3/4 creatures (Content Update 1, 8 models)
| File | Asset | Rarity (placeholder) | Zone |
|---|---|---|---|
| `LanternWraith.lua` | Lantern Wraith | Rare | MidnightZone |
| `ObsidianCrab.lua` | Obsidian Crab | Uncommon | MidnightZone |
| `MagmaSquid.lua` | Magma Squid | Epic | MidnightZone |
| `VoidHammerhead.lua` | Void Hammerhead | Legendary | MidnightZone |
| `TrenchWisp.lua` | Trench Wisp | Uncommon | HadalDepths |
| `AbyssalIsopod.lua` | Abyssal Isopod | Rare | HadalDepths |
| `GhostFinTuna.lua` | Ghost Fin Tuna | Epic | HadalDepths |
| `CrystalLeviathan.lua` | Crystal Leviathan | Mythic | HadalDepths |

### `enemies/` – Raid enemies
| File | Asset | Description |
|---|---|---|
| `ShadowKraken.lua` | Shadow Kraken (placeholder raid enemy) | Larger, menacing kraken with 8 tentacles, red glowing eyes, `EnemyTier` attribute |
| `SpineDrifter.lua` | Spine Drifter (`EnemyId "Drifter"`) | Slender, spindly eel body, thin dorsal spines, `EnemyTier = "Trash"` |
| `ThornSwarmer.lua` | Thorn Swarmer (`EnemyId "Swarmer"`) | Compact urchin-fish hybrid, 6 radial thorn spikes, `EnemyTier = "Trash"` |
| `IronMawBrute.lua` | Iron Maw Brute (`EnemyId "Brute"`) | Squat tank body, oversized jaw, CSG-welded `ArmorPlate`, `EnemyTier = "Elite"` |
| `TrenchWardenBoss.lua` | The Trench Warden (`EnemyId "TrenchWarden"`, boss) | Towering kraken lord, 8 thick tentacles, thorn-crown cluster with `PointLight`, `EnemyTier = "Boss"` |

### `decorations/` – Event cosmetic decorations (Content Update 1, Section 1.3/7a)
Purely cosmetic decoration objects placeable on a player's build field,
purchasable per event shop. `PrimaryPart` = `"Base"`, footprint small enough
for ONE `BuildField` (see `HabitatPlotBase.lua`, `FIELD_MARKER_DIAMETER = 15`),
attributes `DecorationId` and `Event`. Placed under
`Workspace.Assets.Decorations`.

| File | Asset | `DecorationId` | Event |
|---|---|---|---|
| `VenomDrip.lua` | Venom Drip (dripping poison crystal spike) | `VenomDrip` | ToxicTide |
| `JackOCoral.lua` | Jack-o-Coral (carved glow coral head, CSG union) | `JackOCoral` | SpookyTide |
| `CoralGardenSet.lua` | Coral Garden Set (3 mini clusters `Cluster1`-`Cluster3` on 1 base) | `CoralGardenSet` | BioluminescentBloom |
| `IceSpire.lua` | Ice Spire (5-piece, translucent ice crystal cluster) | `IceSpire` | FrozenCurrent |
| `MagmaVent.lua` | Magma Vent (glow crack + active ember `ParticleEmitter`) | `MagmaVent` | VolcanicVent |
| `TreasurePile.lua` | Treasure Pile (coin pile + half-open chest) | `TreasurePile` | TreasureTide |

### `pickups/` – Collectible world pickups
`PrimaryPart` = `"Body"`, `Attachment "PulseAttachment"` on `Body`,
`model:SetAttribute("PickupKind", ...)`. `PickupSpawner.lua` clones the
templates from `ReplicatedStorage.AssetTemplates.Pickups` (see the header
comment in `GlowSporePickup.lua`). Placed under `Workspace.Assets.Pickups`.

| File | Asset | `PickupKind` | Event | Notes |
|---|---|---|---|---|
| `GlowSporePickup.lua` | Glow Spore (base resource) | `GlowSpore` | – | Ball body + glass shell + 3 `GlimmerSpeck` anchors |
| `SunkenChest.lua` | Sunken Chest (gold recolor of GlowSporePickup) | `SunkenChest` | TreasureTide | Attribute `Event = "TreasureTide"`, chest shape instead of ball |
| `FrozenSpore.lua` | Frozen Spore (3-state thaw pickup) | `FrozenSpore` | FrozenCurrent | 3 state models `IcyShellState`/`CrackedState`/`OpenState` under the Model, toggled via Transparency; order in attribute `ThawStates = "IcyShellState,CrackedState,OpenState"` |

### `gacha/` – Mystery Egg gacha (Expansion Concept 1.7, compliance-friendly)
Pure geometry/effect rig assets for the gacha system described in the
GDD/expansion concepts. **Contains no random-roll, pity, or purchase
logic** (`GachaService` & co. are deliberately added later by the code
agent).

| File | Asset | EggTier (placeholder) | Description |
|---|---|---|---|
| `MysteryEgg_Common.lua` | Mystery Egg (Common) | `Common` | Smooth egg shape, matte SmoothPlastic, 1 thin neon seam ring |
| `MysteryEgg_Uncommon.lua` | Mystery Egg (Uncommon) | `Uncommon` | Richer teal, 2 seam rings, speckled dot pattern |
| `MysteryEgg_Rare.lua` | Mystery Egg (Rare) | `Rare` | Glass shell (CSG union with facet bumps), 2 seam rings + dot pattern |
| `MysteryEgg_Epic.lua` | Mystery Egg (Epic) | `Epic` | Violet-neon crystalline shell (CSG union with crystal shards), 4 vein lines, glowing tip |
| `MysteryEgg_Legendary.lua` | Mystery Egg (Legendary) | `Legendary` | Two-tone crystal shell, thorn crown (5 spikes), floating rune ring (CSG subtraction), `PointLight` |
| `MysteryEgg_Mythic.lua` | Mystery Egg (Mythic) | `Mythic` | Most elaborate stage: crystal shell with glow core, 7-spike thorn crown, 2 offset tilted rune rings, 3 crystal-shard satellites, brightest `PointLight` |
| `GachaEggOpenVFX.lua` | Opening VFX rig | – | Reusable effect model: `ParticleEmitter`s (shell crack + light burst), `PointLight` flash, rarity-colored `Beam`. All disabled (`Enabled = false`) by default |

### `hub/` – Hub world "Tidal Market"
Central marketplace/lobby world per GDD Section 4 & 8: landmark, NPC
stands, trade dock, leaderboard, quest board, 4 zone portals,
SpawnLocations, and a symbolic, glowing path to the player plots. Follows
the same 8 design principles as the zone terrain chunks (see
`/home/user/ro/docs/terrain-design-notes.md`), adapted to a marketplace
setting rather than an exploration terrain.

| File | Asset | Description |
|---|---|---|
| `TidalMarketHub.lua` | Hub world "Tidal Market" | Dark basalt round plaza (Ø 220 studs) with a central landmark ("Lighthouse Coral": CSG coral tower + giant jellyfish with multi-neon tentacles), 5 interactable stands in a ring (Shop/Gacha/Trade/Leaderboard/Quests), 4 zone portals (CSG archways, color-coded per zone), and 6 SpawnLocations |

**World placement (important):** The hub deliberately sits at
`CFrame.new(-500, 0, -500)` — far away from both the player plot grid
(`PlotRegistry.lua`: slots start at `(0,0,0)` and grow across `x/z >= 0`)
and the zone terrain chunk cluster (all 4 chunks sit within a ~170-stud
radius of the world origin `(0,0,0)`). Without this offset the hub would
collide directly with plot slot #1 and the zone chunks — a placement
conflict between two already-existing systems not changeable here (details
in the header comment of `TidalMarketHub.lua`). Zone portals and the "plot
road" are therefore deliberately **logical teleport points** (attributes,
see below), not physically walkable connections to the real zone/plot
geometry — this fits the existing design, since `PlotRegistry` assigns
players a runtime-changing world slot on every join anyway.

**Interactable attributes (for the UI/code agent):**

| Sub-model | `Interactable` attribute | Notes |
|---|---|---|
| `ShopStand` | `"Shop"` | `DisplayPanel` surface for a later shop UI, `InteractionPoint` attachment |
| `GachaStation` | `"Gacha"` | 3x `EggDisplaySlot<n>` attachment (space for `gacha/MysteryEgg_*.lua` models), `DisplayPanel` |
| `TradeDock` | `"Trade"` | 2x `TradePodium<n>` (stand points for a safe 2-player trade) |
| `LeaderboardBoard` | `"Leaderboard"` | `DisplayPanel` surface for a later `SurfaceGui` (OrderedDataStore leaderboards) |
| `QuestBoard` | `"Quests"` | `DisplayPanel` surface (wooden board) for the daily quest UI |
| `PlotGate` (bonus, beyond the brief) | `"PlotGate"` | Symbolic end of the "plot road"; optional hook for `PlotRegistry.AssignPlot()` + teleport |

The 4 zone portals (`Portal_<Zone>`) instead carry `ZonePortal`
(`"SunZone"` / `"TwilightZone"` / `"MidnightZone"` / `"HadalDepths"`) and
`RequiredLevel` (`1` / `10` / `25` / `45`), plus a `TeleportPoint`
attachment as the target anchor for later teleport logic.

### `npcs/` – Hub NPCs (non-humanoid marketplace characters)
Five stylized, non-humanoid sea-dwellers (no `Humanoid`, no animation
assets) bring "Tidal Market" to life: each buildscript finds its stand in
`Workspace.Assets.Hub.TidalMarketHub` via that stand's `Interactable`
attribute and places itself beside its `InteractionPoint` attachment
(without blocking the prompt), with a documented fallback offset in case
the hub hasn't been built yet. `PrimaryPart` = `"Body"`; movable parts
named by the client agent: `Head`, `ArmL`/`ArmR`, `Eye1`/`Eye2` (direct
sibling parts of `Body`, not nested under `Head`). Attributes: `NpcId`,
`DisplayName`, `StandInteractable`, `SpeechHeight`. `CollectionService` tag
`"NpcAmbient"` for runtime detection by
`src/client/NpcAmbientController.client.lua` (procedural idle animation +
speech bubbles, see `docs/npcs.md`). Placed under `Workspace.Assets.Npcs`.

| File | Asset | `NpcId` | Stands at (`Interactable`) |
|---|---|---|---|
| `Shopkeeper.lua` | Shelly (hermit crab merchant) | `Shopkeeper` | `Shop` |
| `EggKeeper.lua` | Inky (old glow octopus) | `EggKeeper` | `Gacha` |
| `QuestGiver.lua` | Captain Finn (seahorse captain) | `QuestGiver` | `Quests` |
| `Trader.lua` | Splash (clownfish) | `Trader` | `Trade` |
| `Guide.lua` | Bubbles (jellyfish) | `Guide` | near `HubSpawn1` (`StandInteractable = "Spawn"`, marker only) |

### `ui/` – UI layout scaffolding
Pure `ScreenGui`/`Frame` layouts with no functional logic (no `LocalScript`
loads data or handles clicks — that is deliberately added later).

| File | Asset | Description |
|---|---|---|
| `GachaOddsPanel.lua` | Odds-display UI panel | `ScreenGui "GachaOddsUI"` with title, 6 rarity rows (Common–Mythic) with placeholder percentages, Close button (no click connection) |

## How to run the scripts in Roblox Studio

**Option A – Command Bar (recommended for single tests):**
1. Open Roblox Studio, load the desired place.
2. Open the **View → Command Bar** menu.
3. Paste the contents of the `.lua` file in and run it with Enter.
4. The model appears under `Workspace.Assets.<Category>.<AssetName>`
   (for the `ui/` scripts, under `game.StarterGui.<ScreenGuiName>` instead).

**Option B – Temporary script:**
1. Insert a new `Script` in `ServerScriptService` (or `ServerStorage`).
2. Paste the contents of the `.lua` file in.
3. Start a play test (or run it once in Studio via a trigger/command) — the
   script builds the geometry once.
4. Delete the temporary script afterward (it contains no ongoing gameplay
   logic, so it is no longer needed).

All scripts are **idempotent**: an existing model with the same name in the
target folder is automatically removed before the rebuild, so running them
multiple times is safe.

Each script has a configuration block at the top (`ORIGIN`, optionally
`RARITY`, `ZONE`, random seed, etc.) — adjust the target position (`CFrame`)
before running if needed, so assets don't overlap during shared testing.

## Naming conventions for the later code agent

- **PrimaryPart:**
  - Creatures & raid enemies: `PrimaryPart` is always **`"Body"`** —
    attachment point for server-side movement control (equivalent to
    `HumanoidRootPart`).
  - Buildings & terrain: `PrimaryPart` is always **`"Base"`**
    (terrain chunks: `"ChunkBase"`) — attachment point for placement logic /
    snap-to-grid.
  - The Habitat Plot base: `PrimaryPart` is the hexagon part
    **`"PlatformBase"`**.

- **Idle-pulse attachment:**
  - Every creature and the raid enemy have an `Attachment` object named
    **`"PulseAttachment"`**, hanging directly off the `PrimaryPart`. The
    code agent can hook the idle float/pulse animation (e.g. periodic
    scale/bobbing) onto it without having to modify the geometry itself.

- **Rarity attribute (creatures):**
  - Every creature model carries `model:SetAttribute("Rarity", "<value>")`
    as a placeholder (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary` in
    the current MVP set). The full scale per the GDD (Section 3) is
    `Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal` — the
    code agent can use it later to drive glow color/emission/particle
    intensity.
  - Also set: `Zone` (origin zone) and `CreatureName` (display name) as
    attributes.

- **Other attributes:**
  - Buildings: `BuildingType` (string) and `Stage` (number, currently
    always `1` for the base stage) as placeholders for later upgrade logic.
  - Terrain chunks: `Zone` (`"SunZone"` / `"TwilightZone"` / `"MidnightZone"` /
    `"HadalDepths"`).
  - Raid enemies: `EnemyTier` (placeholder, currently `"Elite"`) and `Zone`.

- **Other named hooks:**
  - `HabitatPlotBase`: 6 attachments `BuildField1` .. `BuildField6` on
    `PlatformBase` mark the centers of the build fields (for
    snap-to-grid placement).
  - `AnglerfishTower` / `Anglerfish` (creature): part `LureOrb` +
    attachment `MuzzlePoint` (tower only) mark the lure/muzzle point for
    later attack VFX.
  - `BroodPool_Basic`: attachments `EggSlot1` .. `EggSlot3` mark egg
    positions for later breeding/incubation logic.

- **Mystery Egg models (`gacha/MysteryEgg_*.lua`):**
  - `PrimaryPart` is always **`"Shell"`** (instead of `"Body"` as with
    creatures) — attachment point for the opening animation and for
    docking the opening VFX rig.
  - Every egg carries `model:SetAttribute("EggTier", "<value>")` as a
    placeholder (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic`
    in the current gacha set — a subset of the full GDD rarity scale
    `Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal`).
    The code agent later links this attribute to the real drop table/
    `GachaService`; it does not drive any random logic itself.
  - Also set: `EggName` (display name, placeholder).
  - Every egg also has an `Attachment "PulseAttachment"` on `Shell`,
    analogous to the creatures — the same attachment point for an idle
    float/pulse animation.
  - `MysteryEgg_Legendary` / `MysteryEgg_Mythic`: an extra
    `PointLight "ShineLight"` on `Shell` as a purely decorative shine
    accent.
  - `MysteryEgg_Mythic`: also 3 parts `Satellite1`..`Satellite3` as
    attachment points for a later orbit/rotation animation (purely
    geometric placement, no movement in the buildscript).

- **Opening VFX rig (`gacha/GachaEggOpenVFX.lua`):**
  - `PrimaryPart` is **`"EffectCore"`** (an invisible, central anchor part)
    — attachment point for positioning/docking the whole rig onto an
    opening egg.
  - `ParticleEmitter "ShellCrackEmitter"` (on attachment
    `"ShellCrackPoint"`) and `ParticleEmitter "LightExplosionEmitter"` (on
    attachment `"LightBurstPoint"`), as well as `PointLight "ShineBurst"`
    and `Beam "RarityBeam"` (between attachments `"BeamBase"` /
    `"BeamTop"` on parts `BeamAnchorBottom` / `BeamAnchorTop`) are
    **all disabled (`Enabled = false`) by default** — the code agent
    switches them on/off specifically for the opening ceremony and sets
    `RarityBeam.Color` to match the rolled rarity. The rig itself plays
    nothing automatically and contains no random/gacha logic.

- **Odds-display UI panel (`ui/GachaOddsPanel.lua`):**
  - Created under `game.StarterGui` as `ScreenGui "GachaOddsUI"` (starts
    with `Enabled = false`), with main panel `Frame "OddsPanel"`.
  - Rarity rows are named `RarityRow_<Tier>` (`Tier` = the same wording as
    `EggTier` on the egg models), each with `Frame "ColorSwatch"`,
    `TextLabel "NameLabel"` (also carries `SetAttribute("EggTier", ...)`)
    and `TextLabel "PercentLabel"`.
  - `PercentLabel` carries `SetAttribute("PlaceholderOnly", true)` — the
    displayed text is only a layout placeholder and **not** tied to a real
    drop table; the code agent later replaces this value with server-side
    synchronous compliance odds data.
  - `TextButton "CloseButton"` deliberately has no `MouseButton1Click`
    connection — a purely visual scaffold.

## How the hub gets into the live game

Like all other buildscripts in this folder, `hub/TidalMarketHub.lua` is a
**one-time Studio script**, not runtime code. Workflow (identical to the
existing `AssetTemplateSetup.lua` pattern for plot/building templates, see
there):

1. Run `TidalMarketHub.lua` once in the Studio Command Bar (see the header
   comment in the file). The model is created under
   `Workspace.Assets.Hub.TidalMarketHub`.
2. Save/publish the place — the hub then becomes a permanent part of the
   world, just like terrain chunks and the Habitat Plot base.
3. `src/server/WorldSetup.server.lua` runs on every server start and
   **only checks** whether the hub is present (no rebuild — that would
   needlessly repeat expensive CSG computations). If it's missing, a
   warning is logged and a minimal emergency spawn is created so players
   can still join safely instead of falling into the void.

## Mobile performance (hub & world atmosphere)

- `Workspace.StreamingEnabled = true` is recommended (not enforced by
  `WorldSetup.server.lua` itself, since this is a global Workspace
  property that should be coordinated with the zone/plot streaming
  boundaries used by other agents) — important, since the world can grow
  large with the hub + 4 zones + potentially many player plots.
- Particle rates in `WorldSetup.server.lua` are kept deliberately moderate
  (bubbles: `Rate = 5` per source, 4 sources at the hub; plankton:
  `Rate = 8` per source, 2 sources) instead of a single, world-wide
  high-frequency emitter.
- Light sources are limited: `PointLight.Shadows = false` everywhere (see
  the hub and terrain buildscripts), and the global, soft flicker runs via
  `ColorCorrectionEffect.Brightness` (a single Heartbeat tween instead of
  dozens of individually animated lights).
- All ambient FX instances carry the `CollectionService` tag `"AmbientFX"`
  and mirror their base rate in the `BaseRate` attribute — prepared for a
  later client-side quality-tier hook (see the comment block at the end of
  `WorldSetup.server.lua`), since the server shouldn't reliably decide
  client graphics quality or (fairly) player-count load spikes on its own.
- Hub PartCount deliberately kept in the low three digits (~220, comparable
  to the zone terrain chunks) despite 4 portals + 5 stands + landmark, via
  CSG union for all archways/podiums/the coral tower.

## Technical notes

- Scale: 1 stud ≈ 0.28 m, consistent with the standard Roblox character
  size.
- Style: low-poly/blocky, Roblox-typical, PartCount per model deliberately
  kept low.
- Materials: `Enum.Material.Neon` for bioluminescence/glow effects,
  `Enum.Material.Glass` for translucent body parts, `Slate`/`Rock`/`Metal`
  for buildings/terrain, `Sand` for the Sun Zone.
- CSG (`UnionAsync`/`SubtractAsync`/`IntersectAsync`) is used selectively
  for simple shapes (e.g. hexagon platform, basin ring, ray body) to keep
  PartCount low. In the terrain chunks (see
  `/home/user/ro/docs/terrain-design-notes.md`), the same technique is used
  for landmarks: `SubtractAsync` for basins/crevices/cave gates sunk into
  the ground (NegateOperation results), `UnionAsync` for rock
  arches/spires/stalagmites/crystal clusters made of several overlapping
  parts.
- All model scripts place their models under `game.Workspace.Assets.<Category>`
  (`Terrain`, `Buildings`, `Creatures`, `Enemies`, `Gacha`), so they are
  easy to find and can be addressed programmatically by the code agent.
  The `ui/` scripts differ from this and place their `ScreenGui`s under
  `game.StarterGui` instead, since these are UI, not Workspace geometry.
