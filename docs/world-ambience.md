# World ambience: set dressing and client animation

The map is dressed by buildscripts in `assets/models/world/` (static geometry, run once in Studio)
and brought to life by **one** client script, `src/client/WorldAmbience.client.lua`, tuned through
`src/shared/WorldAmbienceConfig.lua`. Nothing here runs on the server; nothing replicates except the
static dressing itself.

## Zone identities (v3: terrain, palettes, glow budget)

Every zone is now sculpted with Roblox smooth **Workspace.Terrain** (FillBall / FillBlock / FillCylinder /
FillWedge, Air to carve) plus a few landmark parts, then dressed by a separate script. Terrain colours are
global per place (`Terrain:SetMaterialColor`), so each zone owns its own materials. Every terrain script sets
the same palette block, so the order does not matter.

| Zone | Mood / palette | Ground materials | Landmarks and layout | Lighting (ZoneAtmosphere) |
|---|---|---|---|---|
| Hub (Tidal Market) | cozy harbour, warm sand, wood, striped awnings | Sand, Limestone, Sandstone, LeafyGrass | round sand plaza, 8 market stalls, 8 wooden piers with rowboats, dune wall, plot-road causeway | bright teal water, light fog |
| Sun Zone | sunny coral-pink reef shallows | Sand, Limestone, Salt, Sandstone, LeafyGrass | sunken pirate ship (boardable gangway), coral garden terrace, tide pool, Sun Gate arch, dunes | warm sun, turquoise fog, ClockTime 13 |
| Twilight Zone | blue-violet dusk | Slate (violet), Mud (indigo cliffs), Rock (paths), Grass (kelp beds) | tall kelp-forest canyon with a stone gate, spire field with a natural arch, chasm with a stone bridge | violet fog, ClockTime 18.7 |
| Midnight Zone | near-black basalt and fire | Basalt, Asphalt, CrackedLava | whale-skeleton rib tunnel into the flat raid arena, volcano with lava river, black smokers, lava-crack ring | dark red haze, strong bloom only here |
| Hadal Depths | pale ice-blue trench | Glacier, Ice, Snow | stone causeway over the trench to an ivory temple with one glowing crystal, crystal groves, column circle, stone fish statue | cold deep fog (160 studs) |

Glow policy: Neon only for lantern lamps, crystal cores, the temple altar crystal, portal gates, a few
mushroom caps / bulb cores, and CrackedLava (terrain material) in Midnight. Light shafts are 94 to 97 percent
transparent **SmoothPlastic** planes, not Neon. Neon share of all buildscript parts went from 35.3 percent to
4.6 percent (per zone: Sun 18.6 -> 1.9, Twilight 27.9 -> 8.0, Midnight 40.2 -> 2.9, Hadal 45.2 -> 6.2,
Hub 41.1 -> 3.3).

Underwater look: the game is not inside Terrain Water (players would swim instead of walk). The water feel is
fog + Atmosphere + colour grading, set per zone by `ZoneAtmosphere.client.lua`.

## Build order

See `docs/release-checklist.md` section 3: `PlotSurroundings.lua` right after `HabitatPlotBase.lua`
(step 1), the zone terrain chunks (step 7), `hub/HubTerrain.lua` + `TidalMarketHub.lua` (step 9) and the world
dressing (step 11). Each script is idempotent. **Terrain scripts first wipe their own region** with an Air
`FillBlock` (zone: chunk centre +-(half size + 4); hub: +-174), then rebuild; dressing scripts replace
`Workspace.Assets.World.<Name>` (the plot add-on creates a `PlotDecor` model inside the plot template instead).
The scripts embed shared helper blocks (copy-pasted on purpose, Command Bar scripts cannot require each other);
the `ORIGIN` constants at the top must match between a zone's terrain script and its dressing script. The
dressing scripts stand every prop on the ground by raycasting `Workspace.Terrain`, so run the terrain first.

Part counts (from the preview export) and terrain fills (the dressing is the part count minus the chunk):

| Zone | Terrain fills | Chunk parts (landmarks) | Dressing parts | Neon parts / share |
|---|---|---|---|---|
| Sun | 152 (85 ball, 63 cylinder, 3 block, 1 wedge) | 44 | 318 | 7 / 1.9 percent |
| Twilight | 193 | 23 | 202 | 18 / 8.0 percent |
| Midnight | 268 (220 basalt columns) | 86 | 121 | 6 / 2.9 percent |
| Hadal | 192 | 37 | 204 | 15 / 6.2 percent |
| Hub | 101 | hub 201 (same geometry, repainted) | 471 | 22 / 3.3 percent |
| PlotSurroundings | none | HabitatPlotBase 145 incl. decor | 126 per plot | 18 (build-field markers + 6 lanterns), 12 percent |

(Before: 499 / 577 / 455 / 473 / 950 parts for Sun / Twilight / Midnight / Hadal / Hub, all of it flat slabs
plus scattered decor.) All decor parts are anchored, `CanCollide = false`, `CanQuery = false`,
`CanTouch = false`, `CastShadow = false`. Collidable parts are only the landmarks (ship hull and deck,
gate arches, whale bones, temple, hub piers) and the hidden `ChunkBase` safety floors. Animated models are
`ModelStreamingMode = Atomic`. Gameplay areas (landing spot at each chunk centre, trails, lanes, bridges, arena,
hub lanes, spawns, stands, plot road) are reserved with `blockCircle/blockRect` and are flat terrain.

`TravelService` is unchanged: it raycasts straight down at `ChunkBase.Position.X/Z` (the chunk centre) and
reads the `Zone` attribute. `ChunkBase` is a hidden slab buried at y = -44 (the ray starts 60 studs above it, i.e. 16 studs above the flat landing plaza, so it hits the terrain first),
the landing spot is a flat plaza of at least 12 studs radius in every zone, and no landmark stands within
16 studs of it. The Midnight raid arena (flat disc, r 13) and its lane stay free of lava and props.

## Tags and attributes

The client discovers everything via `CollectionService` tags (names in `WorldAmbienceConfig.Tags`).
Attributes are read once when the instance is added.

| Tag | On | Attributes (default) | Effect |
|---|---|---|---|
| `WA_Sway` | Model or Part | `WA_Amp` deg (6), `WA_Speed` (0.8), `WA_Phase`, `WA_Hang` (false) | Parts bend around the model base (`WA_Hang`: around the top, for vines), more with height |
| `WA_Pulse` | Model or Part | `WA_Speed` (0.8), `WA_Depth` (0.35), `WA_Phase` | Neon transparency and light brightness breathe |
| `WA_Flicker` | Part or Model | `WA_Speed` (1.8), `WA_Phase` | Lantern flicker with occasional dips |
| `WA_Rotate` | Model or Part | `WA_Spin` deg/s (6) | Slow spin around the vertical axis (light shafts) |
| `WA_Bob` | Model or Part | `WA_BobAmp` studs (0.8), `WA_BobSpeed` (0.7), `WA_Spin` (0), `WA_Phase` | Gentle float (wisps, islets, jelly lamps) |
| `WA_Bubbles` | Part with `ParticleEmitter` children | emitter attribute `BaseRate` | Emitters only run near the camera, rate scaled by quality |
| `WA_School` | invisible marker Part | `WA_Kind` (`Fish`/`Jelly`/`Ray`), `WA_Count`, `WA_Size`, `WA_Color`, `WA_Color2`, `WA_RadiusX/Y/Z`, `WA_Speed`, `WA_Seed` | Client spawns local fish/jellies/rays that roam on smooth Lissajous-style paths around the marker |

Both `WA_Rotate` and `WA_Bob` on one instance share one motion entry. Instances inside a
`Buildings` folder or under any `ModelAnimationTags` tag (gameplay models handled by
`ModelAnimator`) are ignored. Instances outside `Workspace` (for example the plot template in
`ReplicatedStorage.AssetTemplates`) are ignored until they are cloned into the world.

To animate your own prop: tag a Model (or Part) and set attributes, no code change needed:

```lua
CollectionService:AddTag(model, "WA_Sway")
model:SetAttribute("WA_Amp", 8)
```

Besides the tagged props the client creates (local only) a camera-attached plankton emitter tinted by zone
and, every 30 to 100 seconds, one ambient creature (ray, big fish group, jellyfish) that crosses the area
at about 140 studs from the camera, chosen by the zone the camera is in (`WorldAmbienceConfig.Zones`).

## Zone atmosphere (`src/client/ZoneAtmosphere.client.lua`)

A small client script blends Lighting (ClockTime, Brightness, Ambient, OutdoorAmbient, Fog), the
`DeepTideAtmosphere`, `DeepTideColorCorrection` (tint, saturation, contrast; never its Brightness, which the
server flickers) and `DeepTideBloom` per zone. The zone comes from the character position (camera as
fallback) and `WorldAmbienceConfig.Zones`, so it follows `TravelService` teleports without a remote. Profiles
are in `WorldAmbienceConfig.Atmosphere` (keys `Hub`, `SunZone`, `TwilightZone`, `MidnightZone`,
`HadalDepths`; the plot area uses `Hub`); blend time is `AtmosphereBlendSeconds` (2.5 s). It also sets the
LocalPlayer attribute `CurrentZone`. While a live event runs, `LiveEventService` values win; when the server
values return to the `Baseline*` attributes the zone mood is restored. Bloom is deliberately restrained
(`BloomThreshold` 0.9 to 1.15, intensity 0.2 to 0.5), and halved in size on touch-only devices.

## Performance knobs (`WorldAmbienceConfig.Quality`)

One `RunService.PreRender` connection, one `Workspace:BulkMoveTo` call per frame, distances recomputed
every `LodRecomputeInterval` (0.35 s).

| Knob | Meaning |
|---|---|
| `NearDistance` / `MidDistance` / `FarDistance` | Near: updated every frame. Mid: every `MidInterval`. Far: every `FarInterval`. Beyond: frozen |
| `MaxPartMovesPerFrame` | Hard cap for swaying/rotating parts per frame (rotating start index keeps it fair) |
| `Sway`, `Pulse`, `Flicker`, `Motion` | Switch a whole system off |
| `BubbleDistance`, `BubbleRateScale` | Bubble emitters only within this distance, rate multiplier (0 distance = off) |
| `SchoolSpawnDistance`, `SchoolCountScale`, `MaxCreatures` | Schools exist only while the camera is near their marker; total creature cap (schools + pass-bys) |
| `PassBy`, `PassByInterval` | Occasional creature crossing |
| `PlanktonRate` | Camera plankton particles per second (0 = off) |

Glow animation is gentle on purpose: `PulseDepthScale` (0.55) scales every `WA_Depth`, and a flickering lantern
only dips to `FlickerMin` (0.72, was 0.3) with a small `FlickerDipFactor` (0.85). Creature caps and sway budgets
were lowered as well (High: 40 creatures, 500 part moves per frame; Medium: 22 / 260; Low: 8 / 100), because there
are fewer glowing props and fewer animated parts.

Tiers: `High` (desktop default), `Medium` (touch-only devices), `Low` (forced by UIKit "Reduced Effects":
sway only near, no pulse/flicker/rotation, few bubbles, 35 percent of the school size, no pass-bys),
`Off` (nothing animated, no particles, no creatures). The script only reads `UIKit.Settings`
(`GetReducedEffects`), it never changes it. Override per client with the attribute
`WorldAmbienceQuality` on the LocalPlayer or on Workspace, for example from a future graphics menu:

```lua
Players.LocalPlayer:SetAttribute("WorldAmbienceQuality", "Low")
```

The tier is re-evaluated once per second.

## Previews

`docs/previews/map-<area>-after.png` (hub, sun, twilight, midnight, hadal; `-before.png` are the old flat
slabs), `map-zones-compare.png` (hub + 4 zones side by side) and `terrain.png`. Regenerate with `tools/model-preview`
(`export.mjs` then `render.mjs --only map-sun,map-twilight,map-midnight,map-hadal,map-hub,map-zones-compare`).
`Workspace.Terrain` Fill* calls are rendered as a smoothed 2-stud heightfield coloured by terrain material
(overhangs are not shown, Air carves are); each zone is lit with an approximation of its ZoneAtmosphere
profile. Particles, animation and creatures are not part of the images. `render.mjs --terrain <script>` renders
the terrain of one script alone.
