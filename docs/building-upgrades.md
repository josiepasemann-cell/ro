# Building Upgrades (Stages 1 → 2 → 3)

*Companion to `docs/game-design-doc.md` sections 6 and 8 ("Brutbecken (3
Stufen: Basic, Advanced, Master)" / "Verteidigungsturm ... je 3
Upgrade-Stufen") — documents the upgrade system implemented on top of the
existing `HabitatPlacement.Level` field, the exact numbers used, and the
design decisions the spec left open.*

## 1. Why this exists

`BreedingConfig.TIERS[2]`/`TIERS[3]` (Advanced/Master brood pool tiers) and
their creature pools (`MIDNIGHT_ZONE_CREATURE_POOL`, `HADAL_DEPTHS_CREATURE_POOL`,
`CrystalLeviathan`) already existed, gated on `HabitatPlacement.Level`, but
nothing ever set `Level` above 1 — `PlayerDataService.AddHabitatPlacement`
always creates placements at `Level = 1`, and no upgrade flow existed. This
task adds that flow: a server-authoritative stage upgrade
(`PlacementService.RequestUpgrade`) that raises a placement's persisted
`Level`, which every consuming system (breeding, idle income, raid towers)
already reads generically.

No parallel "stage" field was introduced anywhere — `HabitatPlacement.Level`
remains the single source of truth, exactly as the task required.

## 2. Data (`BuildingConfig.lua`)

Every one of the 6 buildings now has `MaxStage = 3`, `UpgradeCosts[2]`,
`UpgradeCosts[3]` (Tide Coins + optional `LevelRequirement`, optional
`AbyssalShards`), and — depending on building role — either
`IncomeMultiplierByStage` (producers) or `TowerStageBonus` (defense towers).
`BroodPool` has neither: its "stage" already *is* the `BreedingConfig`
breeding tier, so no separate multiplier table was needed there.

The GDD's asset list (section 8) only explicitly calls out 3 stages for the
Brood Pool and the 3 defense towers, not for the 2 producer buildings
(GlowBuoyStation/FilterPlant). This task's instructions explicitly ask for
"income-rate multiplier for producers" as one of the upgrade effects, so
producers were extended with the same 3-stage system for a single,
predictable, symmetric upgrade system across every building type — documented
here since it's a step beyond the GDD's literal asset wording.

### Level requirements

| Building | Unlock Lvl | Stage 2 requires | Stage 3 requires |
|---|---|---|---|
| BroodPool | 1 | **Level 25** | **Level 45** |
| GlowBuoyStation | 1 | Level 10 | Level 25 |
| FilterPlant | 3 | Level 15 | Level 30 |
| AnglerfishTower | 8 | Level 20 | Level 35 |
| CoralBarrier | 12 | Level 22 | Level 38 |
| ElectricEelTrap | 18 | Level 28 | Level 42 |

**BroodPool's level requirements are the central design decision of this
task.** They are set to *exactly* match `ZoneEconomyConfig`/`TravelService`'s
MidnightZone (25) and HadalDepths (45) unlock levels. This matters because
`BreedingConfig.GetCreaturePool` gates the 7 new zone creatures and
`CrystalLeviathan` purely by *BroodPool stage*, not by the player's actual
zone-travel unlock (see `docs/zones-and-raids.md` section 4 — deliberately
not zone-gated in `BreedingConfig`). Without a level-gated upgrade cost, a
low-level player could rush-upgrade a BroodPool with idle income alone and
breed HadalDepths/Mythic creatures years before they could ever reach that
zone. Tying the upgrade's `LevelRequirement` to the matching zone-unlock
level closes that gap while keeping the two systems (zone travel, brood pool
upgrades) independent and each simple in isolation.

The other 5 buildings don't gate any content the way BroodPool does, so their
requirements are just plausibly staggered between their `UnlockLevel` and
level 45 (the GDD's top progression-curve breakpoint), each pair roughly
10–15 levels apart so upgrades feel like a mid/late-game goal rather than an
immediate day-one purchase.

### Costs & effects

| Building | Base Cost | Stage 2 Cost | Stage 3 Cost | Stage 1 effect | Stage 2 effect | Stage 3 effect |
|---|---|---|---|---|---|---|
| GlowBuoyStation | 150 | 400 | 950 | 15 coins/min | 24 coins/min (×1.6) | 36 coins/min (×2.4) |
| FilterPlant | 450 | 1000 | 2200 | 30 coins/min | 48 coins/min (×1.6) | 72 coins/min (×2.4) |
| BroodPool | 250 | 700 | 1800 + **5 Abyssal Shards** | Basic tier | Advanced tier | Master tier |
| AnglerfishTower | 700 | 1500 | 3200 | 27 DPS, Range 28 | 36.45 DPS, Range 32 | 48.6 DPS, Range 36 |
| CoralBarrier | 550 | 1200 | 2600 | 20 DPS, Slow-Radius 10 | 26 DPS, Radius 12 | 34 DPS, Radius 14 |
| ElectricEelTrap | 900 | 1900 | 4000 | 16.8 DPS, chains 2 (radius 10) | 21.84 DPS, chains 3 (radius 12) | 28.56 DPS, chains 4 (radius 14) |

Tower DPS/multiplier numbers derive from `RaidConfig.TOWER_STATS` (unchanged
base values) combined with `BuildingConfig.TowerStageBonus[stage]`
(`DamageMultiplier`/`RangeBonus`/`BlockRadiusBonus`/`ChainCountBonus`/
`ChainRadiusBonus`), applied at the point of use — never written back into
`RaidConfig`, identical pattern to the existing zone-scaling
(`RaidConfig.GetScaledEnemy`). `RaidConfig.CORAL_BARRIER_SLOW_FRACTION`
(40%) and `CHAIN_DAMAGE_FRACTION` (50%) stay stage-independent constants —
range/radius/chain-count growth is the upgrade lever instead of touching
those shared fractions.

Producer income multipliers (1.0 / 1.6 / 2.4) are read generically by
`IdleIncomeService.computeIncomePerMinute` via `BuildingConfig.GetIncomeMultiplier`
and multiply on top of the existing `LiveEventService`/zone/gamepass
multipliers (no change to that stacking order).

BroodPool's Stage 3 cost includes 5 Abyssal Shards — the only upgrade that
costs the premium-adjacent currency, since Stage 3 is the sole gate to
`CrystalLeviathan` (Mythic) and the HadalDepths creature pool, a
premium-feeling milestone that deserves a premium-adjacent cost the same way
the GDD reserves Abyssal Shards for "seltene Kreaturen, Kosmetik" (section 6).

`SellRefundFraction` (50%) is unchanged, but now applies to **base cost +
every already-purchased upgrade stage's cost** (Tide Coins and Abyssal
Shards separately) instead of just the base cost — see section 4.

## 3. Server flow (`PlacementService.RequestUpgrade`)

Mirrors `RequestPlace`/`RequestRemove`'s validation style exactly:

1. `PlayerDataService.IsDataLoaded` check.
2. `placementId` type check + ownership (looked up only in the requesting
   player's own runtime state, exactly like `RequestRemove` — a player can't
   even reference another player's `PlacementId`).
3. Current stage read **authoritatively from `PlayerDataService.GetHabitatLayout`**
   (not from the model's `Level` attribute, which is only a mirror) —
   confirms the placement still exists in the persisted layout at the same
   time.
4. `MaxStageReached` if already at `MaxStage`.
5. `LevelRequirement` check against `PlayerDataService.GetLevel`.
6. **BroodPool-only**: reject with `IncubationActive` if
   `PlayerDataService.GetIncubationForPlacement` returns anything — see the
   design decision below.
7. Tide Coins (and, if the target stage needs them, Abyssal Shards) balance
   checks, then charged via `PlayerDataService.AddCurrency` with rollback on
   any partial failure (identical rollback pattern to `RequestPlace`'s
   charge-then-persist-then-rollback-on-failure sequence).
8. Persisted via the new `PlayerDataService.SetHabitatPlacementLevel` setter
   (the one helper this task added to `PlayerDataService`, since no such
   setter existed).
9. Model swap/accent (section 5) + `GameEvents.Fire(GameEvents.Events.BuildingUpgraded, ...)`.

### Design decision: no BroodPool upgrade during an active incubation

`BreedingService`'s "roll at start, not at claim" design (see its header
comment) means a BroodPool's current incubation's `CreatureId`/`Rarity` are
already fixed the moment breeding started, using the *old* stage's tier —
upgrading mid-incubation would give the player zero benefit for the
in-flight breed but could easily read as "I just upgraded to Master, why
didn't my result get better?". Blocking the upgrade until the player claims
(or the incubation is empty) is the simplest rule that fully avoids that
confusion, without needing any special-case math on the already-persisted
`BreedingIncubation`. This was an explicit choice point called out in the
task and is intentionally the *only* restriction — a BroodPool with a
*ready-but-unclaimed* incubation can still be upgraded (nothing left to
invalidate at that point, `status.State == "Ready"` isn't blocked, only
`GetIncubationForPlacement` returning non-nil is — which is true for both
"Incubating" and "Ready" states in the current data model, so both are
blocked in practice; claim first, then upgrade).

## 4. Sell refund reflects total investment

`PlacementService.RequestRemove` used to refund `Cost * SellRefundFraction`.
It now reads the placement's stage from the model's `Level` attribute
(already kept in sync by `tagModel`/`applyStageToModel`, no extra
`PlayerDataService` lookup needed) and refunds
`(Cost + sum of UpgradeCosts[2..stage].TideCoins) * SellRefundFraction`, plus
a separate Abyssal Shard refund if any upgrade stage cost shards. This keeps
the existing "half your investment back, no buy/sell exploit" property
correct now that "investment" can include upgrade spending.

## 5. Model swap vs. fail-soft accent

The 3D agent's Stage 2/3 models are expected at
`Workspace.Assets.Buildings.<BuildingId>_Stage2` / `_Stage3` (named by
**BuildingId**, not `BuildingConfig.TemplateName` — those two diverge for
BroodPool: `TemplateName = "BroodPool_Basic"`, `BuildingId = "BroodPool"`).
`AssetTemplateSetup` promotes them to
`ReplicatedStorage.AssetTemplates.Buildings.<BuildingId>_Stage2/3` via a new
`promoteOptionalToTemplate` (silent if missing — unlike the mandatory Stage-1
templates, a missing Stage-2/3 model is the expected default state until the
3D agent delivers, not a configuration error worth a startup warning) and
exposes them via `AssetTemplateSetup.GetBuildingStageTemplate(buildingId, stage)`.

`PlacementService.applyStageToModel` (used by `RequestUpgrade`) and the
equivalent branch in `RestorePlayerLayout` (used on rejoin) both:

- If a real Stage-N template exists: destroy the old model, clone the new
  one, `PivotTo` the old model's exact pivot (preserves position/rotation),
  re-tag it with the same `PlacementId`/`FieldIndex`/`Level` attributes.
- Otherwise (**fail-soft**, the current default since no Stage 2/3 models
  exist yet): keep the Stage-1 model entirely unchanged, just update its
  `Level` attribute and add/refresh a `StageAccentRing` — a small anchored
  Neon cylinder + `PointLight` around the model's pivot, colored
  `Theme.Neon.Cyan` for stage 2 and `Theme.Neon.Violet` for stage 3 (matching
  `docs/ui-kit.md`'s neon palette without requiring the server module to
  depend on the client-oriented `UIKit` package — the colors are duplicated
  as plain `Color3` constants instead). Purely cosmetic, no gameplay effect.

Rejoin correctly restores whichever of the two states applies, purely from
the already-persisted `Level` — no extra persisted flag needed.

## 6. UI

- **In build mode**: a 5th action button ("⬆ Upgrade") next to Rotate/Build/
  Sell/Cancel in `PlacementPreviewController`'s build bar — targets whatever
  building currently occupies the aimed build field, same pattern as the
  existing Sell button.
- **Outside build mode**: clicking any placed non-BroodPool building
  (`ClickDetector` on its `PrimaryPart`, added generically in
  `PlacementPreviewController`) opens a small UIKit panel showing the
  building's name, current stage + effect, next stage + effect, cost, and an
  Upgrade button. BroodPool is deliberately excluded from this generic
  handler — it already had its own click-to-open panel in
  `BreedingUIController`, which got its own stage/cost/Upgrade section added
  directly instead (avoids two `ClickDetector`s firing on the same click and
  opening two panels).
- **Breeding panel tier display**: `BreedingUIController`'s "Empty" state
  used to hard-code `BreedingConfig.GetTier(1)` ("MVP: only BroodPool_Basic
  buildable"). It now reads the pool's actual current stage from a small
  local `placementLevelCache` (seeded from the model's `Level` attribute,
  kept live via `GetAttributeChangedSignal("Level")` and via the
  `UpgradeBuildingResult` remote), so a Stage 2/3 pool's panel correctly shows
  the Advanced/Master tier's feed cost, incubation time, and odds.
- **Big FX moment**: `PlacementPreviewController` listens to
  `HabitatRemotes.UpgradeBuildingResult` for *every* building type and fires
  `UIKit.Toast` + `UIKit.ScreenFX.BigMoment` on success (Cyan for stage 2,
  Violet for stage 3). `BreedingUIController` deliberately does **not** show
  a second toast for BroodPool upgrades — it only refreshes its own stage
  cache/panel text — to avoid duplicate feedback for the same event.

All new player-facing strings introduced by this task (the new Upgrade
panel, the new build-bar button, new toasts/rejection text) are in English
per the project's current localization direction. Pre-existing German
strings in the files this task touched (e.g. the rest of the build bar, the
breeding panel's existing feed-cost/odds line) were intentionally left
unchanged — an unrelated string, and a planned separate localization pass
will unify the whole UI's language later.

## 7. Remotes & events

- `HabitatRemotes.RequestUpgradeBuilding` (Client → Server, `placementId`)
  and `HabitatRemotes.UpgradeBuildingResult` (Server → Client) — new
  `RemoteEvent` pair, same bootstrap pattern as the existing Place/Remove
  pair.
- `GameEvents.Events.BuildingUpgraded` (`{ BuildingId, PlacementId, NewStage }`)
  — fired after a successful upgrade, alongside the existing
  `BuildingPlaced` event, so achievements/quests can hook in later without
  touching `PlacementService` itself.

## 8. Effects at the point of use (no new systems, existing readers extended)

- `IdleIncomeService.computeIncomePerMinute` multiplies each producer's
  `IncomeRate` by `BuildingConfig.GetIncomeMultiplier(buildingId, placement.Level)`
  before applying the existing zone/live-event/gamepass multipliers.
- `RaidService.collectTowerRuntimes` (live raids) and
  `computeTowerDpsFromLayout` (offline raid evaluation) both apply
  `BuildingConfig.GetTowerStageBonus` on top of `RaidConfig.GetTowerStats`
  via a new shared `applyTowerStageBonus` helper — a stage-2/3 tower is
  exactly as strong in an offline-evaluated raid as it would be live.
- `BreedingService` needed **no changes at all** — it already read
  `BreedingConfig.GetTier(placement.Level)` and
  `BreedingConfig.GetCreaturePool(rarity, tier.Level)` generically; those
  simply started receiving real stage-2/3 values once `RequestUpgrade`
  started writing them.

## 9. Files touched

Owned: `src/shared/BuildingConfig.lua`, `src/server/PlacementService.lua`,
`src/server/PlacementServer.server.lua`, `src/shared/HabitatRemotes.lua`,
`src/client/PlacementPreviewController.client.lua`,
`src/server/AssetTemplateSetup.lua`, this file.

Small targeted edits: `src/server/IdleIncomeService.lua` (income multiplier,
2 lines), `src/server/RaidService.lua` (new `BuildingConfig` require + new
`applyTowerStageBonus` helper + its 2 call sites), `src/client/BreedingUIController.client.lua`
(tier display + new upgrade section), `src/server/PlayerDataService.lua`
(one new setter, `SetHabitatPlacementLevel`), `src/server/GameEvents.lua`
(one new event name).

Not touched: `BreedingService.lua` (see section 8), `BreedingConfig.lua`,
`RaidConfig.lua` (stage bonuses live in `BuildingConfig` and are applied at
the call site, not written into either shared config module).
