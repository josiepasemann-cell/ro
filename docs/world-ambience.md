# World ambience: set dressing and client animation

The map is dressed by buildscripts in `assets/models/world/` (static geometry, run once in Studio)
and brought to life by **one** client script, `src/client/WorldAmbience.client.lua`, tuned through
`src/shared/WorldAmbienceConfig.lua`. Nothing here runs on the server; nothing replicates except the
static dressing itself.

## Build order

See `docs/release-checklist.md` section 3: `PlotSurroundings.lua` right after `HabitatPlotBase.lua`
(step 1), the other five `world/*.lua` after the terrain chunks and the hub (step 11). Each script is
idempotent and creates `Workspace.Assets.World.<Name>` (the plot add-on creates a `PlotDecor` model
inside the plot template instead, so every cloned player plot carries it). The scripts embed one
shared helper block (copy-pasted on purpose, Command Bar scripts cannot require each other); the ORIGIN
constants at the top must match the terrain/hub scripts.

Part counts of the dressing (target in the script header, actual from the preview export):

| Script | Target | Actual |
|---|---|---|
| SunZoneDressing | ~400 | 438 |
| TwilightZoneDressing | ~420 | 487 |
| MidnightZoneDressing | ~400 | 355 |
| HadalDepthsDressing | ~380 | 397 |
| HubDressing | ~550 | 721 (plaza, seabed apron, reef ring, 4 lanes of lanterns) |
| PlotSurroundings | ~100 per plot | 126 per plot |

All decor parts are anchored, `CanCollide = false`, `CanQuery = false`, `CanTouch = false`,
`CastShadow = false`. Only these are solid: the hub seabed apron, the plot seabed disc and the plot reef
wall (so players who step off an edge land on a floor instead of dropping into the void). Animated
models are `ModelStreamingMode = Atomic`. Gameplay areas (hub lanes, spawns, stands, plot road, zone
lanes, landing spots, arenas, build fields) are reserved with `blockCircle/blockRect` in each script.

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

`docs/previews/map-<area>-before.png` and `map-<area>-after.png` (hub, sun, twilight, midnight, hadal,
terrain with the plot). Regenerate with `tools/model-preview` (`export.mjs` then `render.mjs --only
map-sun,map-twilight,map-midnight,map-hadal,map-hub`). The renderer shows geometry only: particles,
animation and the creatures are not part of the images, and Neon light shafts look brighter than in
Studio.
