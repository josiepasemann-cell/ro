# Release Checklist: Abyssara – Deep Tide Tycoon

As of: 2026-09-24. All code compiles (luau-compile), has been checked with
luau-lsp against the Roblox API, and has been reviewed three times for
runtime errors and exploits. **It has, however, never been run in Roblox
Studio.** Expect errors in the Output window on first launch.

## 0. Fastest way: the ready-made place file

`studio.project.json` builds a complete place: all scripts plus every
buildscript as a ModuleScript under `ServerStorage.AbyssaraBuild`.

1. Build it: `rojo build studio.project.json -o Abyssara.rbxlx` (or use the
   `Abyssara.rbxlx` you were sent) and open it in Roblox Studio.
2. Nothing else is required: when a server starts without a built world it
   builds it itself (`src/server/WorldBuild.lua`, a few seconds on the first
   start of each server). Just press Play or publish.
   Optional, for faster server starts: build it once in Studio and save. In
   **Edit mode** (not Play), View → Command Bar, run
   `require(game.ServerStorage.AbyssaraBuild.BuildWorld).Run()`; it runs all
   buildscripts in the order of §3 and lists failures in orange in the Output.
3. Optional meshes (§3b): import the `.glb` files into `Workspace.MeshImports`,
   then run `require(game.ServerStorage.AbyssaraBuild.ApplyMeshes)`.
4. Do §2 (API access, publish) and §5 (IDs), then test (§4).

For ongoing development keep using Rojo live sync (§1) with
`default.project.json`; the world only needs to be built once per place.

## 1. Get the project into Studio (Rojo)

1. Install Rojo (e.g. via the "Rojo" VS Code extension or `rokit add rojo-rbx/rojo`) and install the Rojo plugin in Studio.
2. In the repo folder, run `rojo serve`.
3. In Studio, open a new, empty place and click **Connect** in the Rojo plugin.
   `default.project.json` maps `src/shared` → ReplicatedStorage, `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts.

## 2. Studio settings

- Enable **Home → Game Settings → Security → "Enable Studio Access to API Services"**. Without this, saving (DataStore) and leaderboards won't work in Studio.
- Publish the place once (File → Publish to Roblox), otherwise there are no DataStores.
- Enable `Workspace.StreamingEnabled` (mobile performance, see `assets/models/README.md`).
- Avatar type R15 (`CharacterSetup.server.lua` enforces this anyway).

## 3. Build the models once

The models are buildscripts, not finished files. Copy each file into the
Command Bar in Studio **in Edit mode** (View → Command Bar) and run it. The
scripts are repeatable — running one twice just replaces the old model. The zone and hub terrain scripts also write **Workspace.Terrain** (smooth terrain); each of them first wipes its own region with `Terrain:FillBlock(..., Enum.Material.Air)` (zone region = chunk centre ±(half size + 4) studs, hub region = ±174 studs around the hub), so re-running one rebuilds just that zone without leaving old hills behind. Never run a terrain script with anything built in its region that you want to keep.

1. `assets/models/terrain/HabitatPlotBase.lua` (plot template), then `assets/models/world/PlotSurroundings.lua` right after it (adds the seabed floor, reef wall and decor to the plot template; must run before the server start that clones plots)
2. `assets/models/buildings/` all 18 files (6 base-stage buildings + their Stage 2/3 upgrade files: BroodPool, GlowBuoyStation, FilterPlant, AnglerfishTower, CoralBarrier, ElectricEelTrap)
3. `assets/models/enemies/` all 5 files (dedicated raid enemies SpineDrifter, ThornSwarmer, IronMawBrute, TrenchWardenBoss, plus the ShadowKraken fail-soft fallback template)
4. `assets/models/pickups/` all 3 files (GlowSporePickup, SunkenChest, FrozenSpore)
5. `assets/models/creatures/` all 22 files (6 MVP + 8 event-exclusive + 8 Zone 3/4 creatures)
6. `assets/models/gacha/` all 7 files (eggs + opening effect)
7. `assets/models/terrain/` the 4 `*TerrainChunk.lua` files (zones: sculpted terrain + landmark parts + the hidden `ChunkBase` floor that `TravelService` reads; stay in the world). Run these **before** the world dressing, because the dressing raycasts the terrain to stand props on the ground.
8. `assets/models/decorations/` all 6 files (event cosmetic decorations: VenomDrip, JackOCoral, CoralGardenSet, IceSpire, MagmaVent, TreasurePile)
9. `assets/models/hub/HubTerrain.lua` first (sand seabed, beach, dunes, plot-road causeway), then `assets/models/hub/TidalMarketHub.lua` (hub with spawn, shop stand, portals)
10. `assets/models/npcs/` all 5 files (Shopkeeper, EggKeeper, QuestGiver, Trader, Guide — run after the hub, since each NPC looks up its stand in `Workspace.Assets.Hub.TidalMarketHub`)
11. `assets/models/world/` the 5 set-dressing files (`SunZoneDressing`, `TwilightZoneDressing`, `MidnightZoneDressing`, `HadalDepthsDressing`, `HubDressing`). Run them after the 4 terrain chunks (step 7) and the hub terrain + hub (step 9); they only add scenery (hub dressing = market stalls, piers, lanterns; zone dressing = corals, kelp, treasure, crystals, lanterns, signs) and never touch gameplay parts. `PlotSurroundings.lua` belongs to step 1 (see above). The animation is client-side (`src/client/WorldAmbience.client.lua`), and the per-zone lighting/fog mood comes from `src/client/ZoneAtmosphere.client.lua` (both documented in `docs/world-ambience.md`; no build step).

### 3b. Swap in the real meshes (recommended)

64 models (all creatures, raid enemies, NPCs, eggs, Glow Spore / Sunken Chest,
event decorations, all 18 buildings) also exist as smooth, textured, low-poly
meshes in `assets/meshes/<Model>/<Model>.glb` (generated by `tools/mesh-gen/`).
Frozen Spore, the egg-opening VFX, hub and terrain stay part-built.

1. After step 3, create a Folder `MeshImports` in Workspace.
2. File → Import 3D for each `.glb` (the importer takes several files at once). Put each imported
   model into `MeshImports`, named exactly like the file (e.g. `GoldGuppy`). Keep the imported
   SurfaceAppearances.
3. Paste `assets/meshes/ApplyMeshes.lua` into the Command Bar and run it (large file, give it a
   moment). It swaps every model with a complete import and prints how many it swapped; models
   without an import keep their parts. Part names, the PrimaryPart, attributes, tags,
   attachments and prompts carry over, so game code and animations are unaffected.
4. Delete `MeshImports`. For glass eggs, Venom Drip and the jellies set the swapped MeshPart
   `Transparency` to ~0.1–0.6 if they look too solid.

Details: `tools/mesh-gen/README.md`. Not yet verified in Studio, so check the Output after running.

Then **save or publish**. On server start, `AssetTemplateSetup.lua`
automatically moves the templates to `ReplicatedStorage.AssetTemplates`. If a
model is missing, there's a warning in the Output instead of a crash;
without the hub, players land at an emergency spawn.

On server start, `GachaServer` places three display eggs (Common, Epic,
Mythic) on the Mystery Egg station in the hub; the remaining eggs become
templates. An egg at the station costs 350 Tide Coins
(`GachaConfig.EGG_COST_TIDE_COINS`). The creature models stay wherever their
buildscript places them (around z = 60 near the first plot). If you want them
elsewhere, change `ORIGIN` at the top of the respective file before running
it.

`assets/models/ui/GachaOddsPanel.lua` is no longer needed (the odds UI is
now generated by code).

## 4. Testing

- **Test → Play**: check the Output window (View → Output) for red errors. Every error there is a real bug.
- **Test → Clients and Servers** with 2 players: each gets their own plot, no one can build on someone else's plot, leaderboards fill in.
- **Test → Device** (device emulator): at least one phone in portrait and landscape, one tablet, one console. Check: the menu bar scrolls, nothing overlaps, building works by tapping, buttons are large enough.
- Play through: tutorial → travel to your plot → build → pick up and deliver a Glow Spore → start breeding and claim it → Mystery Egg → wait for a raid (25 min.; for testing, temporarily lower `RaidConfig.RAID_INTERVAL_SECONDS` and reset it before release) → level up → claim quests → open the shop.
- 2-player test (Test → Clients and Servers): trade at the dock (`docs/trading.md`) and form a Reef Cluster (`docs/coop.md`).
- Rejoin multiple times: data persists, the tutorial doesn't reappear, the daily reward isn't granted twice.
- Shop in Studio: "Studio: Test Purchase" buttons simulate purchases (invisible live).

## 5. Fill in yourself

| What | Where | Guide |
|---|---|---|
| Gamepass and product IDs | `src/shared/ShopConfig.lua` | `docs/monetization-setup.md` |
| Sounds (click, toast, level-up, Mythic, music, ambience) | `src/shared/UIKit/SoundConfig.lua` | Upload your own or licensed sounds (Creator Dashboard → Audio), enter `rbxassetid://…`. All IDs are empty; an empty ID = silence, not an error. |
| Custom animations (optional) | `src/shared/CharacterAnimation/AnimationConfig.lua` | `docs/animations.md` |
| Shop icons (optional) | `IconAssetId` in `ShopConfig.lua` | The shop currently shows neon symbols instead of images. |
| Upload textures (models look plain until this is done) | `src/shared/TextureConfig.lua` | Studio → View → Asset Manager → **Bulk Import** all 28 PNGs from `assets/textures/`. Then right-click each image → Copy Asset ID and paste it into that key's `Id`. An empty `Id` hides that texture, which is safe. Key list and usage: `assets/textures/README.md`. |
| Roblox badge IDs (optional, recommended for 4 milestone achievements) | `BadgeId` in `src/shared/AchievementConfig.lua` | `docs/achievements.md` § "Creating real Roblox badges" — recommended: `Building_MasterBuilder`, `Raids_Tier3`, `Levels_AbyssalMaster`, `Secret_TrueAbyssal`. `BadgeId = 0` means no badge (currency/title reward only) and works fine as-is. |

The "Extra Habitat Plot" gamepass **may now be created**: owners get a second
plot next to their first one (see `docs/extra-plot.md`). Create it like the
other gamepasses and paste its ID into `ShopConfig.GAMEPASSES.ExtraPlot.Id`.
Test the purchase flow in Studio with the simulated purchase first.

## 6. Publishing (Creator Dashboard)

- Fill out the age rating / content questionnaire (required for public games).
- Name, description, icon (512×512), at least one thumbnail, genre.
- Supported devices: computer, phone, tablet, console. (Only check console if it's been tested with a gamepad.)
- Test privately or with friends first, then switch to public.

## 7. Known gaps

Not built, even though it's in the concept (`docs/game-design-doc.md`):

- **Guardians and co-op raids** are built (`docs/guardians-and-coop.md`): loadout slots by level, guardians in raids, Reef Cluster members join a member's raid, shared rewards, boss scaling, real "Deepest Zone" leaderboard. Untested in Studio. Prestige ("Resurface") is built too, see `docs/prestige.md`.
- Trading and Reef Clusters have not been tested in Studio yet (see the 2-player test steps in `docs/trading.md` and `docs/coop.md`).
- No season pass — this is a deliberate design decision, not a gap: event rotation (six 12-hour live events, see `docs/live-events.md`) is the sole live-content mechanic for this game.
- Plot 2 is a raid-free safe plot (towers are rejected there, see `docs/extra-plot.md`); the creature display and spores run on plot 1 only.
