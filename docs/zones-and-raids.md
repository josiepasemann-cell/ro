# Zones & Raids — Content Update 1 Implementation Notes

*Companion to `docs/content-update-1.md` sections 2.1, 2.2, 3, 3.1, 4, 6 —
documents what was actually built by the code agent, the exact numbers used,
and the one design decision the spec left open.*

## 1. "The player's zone" — design decision

`docs/content-update-1.md` talks about raids and Glow-Spore value "for a
player in MidnightZone/HadalDepths", but each player owns exactly one plot
(raids always happen there, never in a zone terrain chunk — see
`RaidService.startRaid`, `CenterPosition = plot.PrimaryPart.Position`), and
zones are travel destinations (`TravelService`), not a place a player
persistently occupies. This needed a concrete, simple, deterministic,
server-only rule.

**Decision: "the player's zone" = the deepest zone unlocked by the player's
current level**, computed by `ZoneEconomyConfig.GetZoneForLevel(level)`:

| Zone | Unlock level (mirrors `TravelService.ZONE_REQUIRED_LEVEL_FALLBACK`) |
|---|---|
| SunZone | 1 |
| TwilightZone | 10 |
| MidnightZone | 25 |
| HadalDepths | 45 |

This value is **derived, not persisted** — no new `PlayerDataService` field
was added. It is recomputed from `PlayerDataService.GetLevel(player)` at the
two points that need it:

- `RaidService.startRaid`: stored once per raid as `RaidRuntime.Zone`, used
  by `RaidConfig.GetScaledEnemy` for the whole raid duration (a raid that's
  already running doesn't re-scale mid-fight even if the player levels up
  during it).
- `IdleIncomeService.computeIncomePerMinute`: recomputed every tick (cheap,
  single table lookup), feeds `ZoneEconomyConfig.GetIncomeMultiplier`.

**Why not physical position:** Glow Spore pickups only ever spawn on the
player's own plot (`PickupSpawner`), never inside the zone terrain chunks —
a literal "standing in MidnightZone" rule would need to track live character
position for a bonus that, given the current pickup system, could never
actually apply in the zone chunks themselves. Deriving from level instead
keeps the rule simple, fully server-authoritative, free of new persistent
state, and — because both raid difficulty and the income bonus read the same
value — internally consistent (no "hard raids but SunZone income" mismatch).
Full reasoning lives in `src/shared/ZoneEconomyConfig.lua`'s header comment.

**Consequence:** the Glow-Spore/Tide-Coin bonus is implemented as a
multiplier on `IdleIncomeService`'s per-minute building income (the only
actually-recurring Tide-Coin source in the current MVP), not as a per-pickup
value bump — the practical effect described in section 6 ("deeper zones pay
better") is preserved even though the literal wording ("Glow Spores
collected while standing in X") doesn't map onto a real code path.

## 2. Raid enemies (section 3)

`RaidConfig.ENEMIES[*].TemplateName` now points at the 4 dedicated models
instead of the shared `ShadowKraken` placeholder:

| EnemyId | TemplateName |
|---|---|
| Drifter | SpineDrifter |
| Swarmer | ThornSwarmer |
| Brute | IronMawBrute |
| TrenchWarden (boss) | TrenchWardenBoss |

`RaidService.applyEnemyVisual` no longer overwrites `Body`/`Mantle`/`Eye1`/
`Eye2` colors — each model now has its own distinct, already-correct look
(this used to be necessary only because all 4 enemy types shared one
model). `RaidConfig.EnemyDefinition.BodyColor`/`EyeColor` are kept as data
(match the models' baked-in colors, and are left as a hook for a future
`LiveEventService` visual-variant override — e.g. "Venom-Slick" —, which is
out of this task's scope).

`AssetTemplateSetup` promotes all 4 new enemy models plus keeps
`ShadowKraken` in its list purely as the **fail-soft fallback**: if a
specific enemy template is missing at runtime (Studio buildscript not run
yet), `GetEnemyTemplate` warns once and returns `ShadowKraken` instead of
`nil`, so `RaidService.spawnWave` never silently skips a spawn.

### 3.1 Zone scaling

`RaidConfig.ZONE_SCALING` + `RaidConfig.GetScaledEnemy(enemyId, zoneId)`:

| Zone | MaxHP × | MoveSpeed × | ScaleMultiplier × |
|---|---|---|---|
| SunZone / TwilightZone | 1.0 | 1.0 | 1.0 |
| MidnightZone | 1.6 | 1.1 | 1.1 |
| HadalDepths | 2.4 | 1.2 | 1.2 |

Applied at wave-spawn time only (`RaidService.spawnWave`), never written
back into `RaidConfig.ENEMIES`. `ContactDamage` is never scaled (matches
spec — `DEFEAT_ENEMY_REACH_COUNT` stays the sole breach-difficulty lever).
The offline-raid formula (`evaluateOfflineRaidWin`) intentionally stays
zone-agnostic, consistent with its existing "simple, no simulation" design.

## 3. New towers (section 4)

Both added to `BuildingConfig.DEFINITIONS` (auto-appear in the build bar via
`BuildingConfig.ORDER` — `PlacementService`/`PlacementPreviewController`
already read `BuildingConfig` generically, no changes needed there) and
`RaidConfig.TOWER_STATS`.

| Tower | Cost | Unlock Lvl | Range | Damage | FireRate | Special |
|---|---|---|---|---|---|---|
| CoralBarrier | 550 | 12 | 14 | 8 | 2.5 (20 DPS) | `BlockRadius = 10`, `CORAL_BARRIER_SLOW_FRACTION = 0.4` (40% MoveSpeed reduction while an enemy is inside radius) |
| ElectricEelTrap | 900 | 18 | 22 | 14 | 1.2 (~16.8 DPS to primary) | `ChainCount = 2`, `ChainRadius = 10`, `CHAIN_DAMAGE_FRACTION = 0.5` (chain targets take 50% damage) |

Both towers run through the **same shared raid tick loop** as
`AnglerfishTower` (`RaidService.tickTowers`/`tickEnemyMovement`) — no
per-tower-type loop was added.

- **Firing origin** is now resolved generically
  (`RaidService.getTowerOriginPosition`): prefers the `MuzzlePoint`
  attachment (present on all 3 tower models), falls back to a known part
  name (`LureOrb`/`SlowPulseCore`/`EelHead`), falls back to the model pivot.
  This replaced the old hardcoded `FindFirstChild("LureOrb")` lookup.
- **CoralBarrier's slow** is a continuous area effect, not a "shot" — it's
  computed per enemy per tick in `computeSpeedMultiplier` (checked against
  every friendly `CoralBarrier`'s `BlockRadius`; multiple barriers don't
  stack, the strongest single effect applies) and folded into
  `tickEnemyMovement`'s speed calculation, rather than being tied to
  `FireRate`/cooldown.
- **ElectricEelTrap's chain** fires alongside its normal single-target hit:
  after damaging the primary target, it finds up to `ChainCount` other
  enemies within `ChainRadius` of the primary target (nearest first) and
  applies `CHAIN_DAMAGE_FRACTION × Damage` to each. `ChargeCore`/
  `ChargeLight` (if present on the model) flash briefly on every shot via
  `flashChargeCore` — fails soft (no-op) on models without a `ChargeCore`
  part, e.g. `AnglerfishTower`/`CoralBarrier`.
- Dead-enemy cleanup (`removeDeadEnemies`) runs once per tower-fire event
  (not per tick) and is index-safe against multi-target hits (primary +
  chain kills in the same shot).

`AssetTemplateSetup` promotes `CoralBarrier`/`ElectricEelTrap` alongside the
existing building templates, with the same fail-soft pattern as enemies:
missing tower template → warn once → fall back to `AnglerfishTower`.

## 4. Creatures (sections 2.1, 2.2, 6)

### Breeding (`BreedingConfig.lua`)

- `RARITY_ORDER`/`RARITY_DEFINITIONS` extended with `"Mythic"` (color
  matches `GachaConfig.DROP_TABLE.Mythic.Color` for codex-UI consistency).
- New `BreedingConfig.GetCreaturePool(rarity, tierLevel)` combines the base
  6-creature pool (always available) with `MIDNIGHT_ZONE_CREATURE_POOL`
  (added from BroodPool tier ≥ 2) and `HADAL_DEPTHS_CREATURE_POOL` (tier ≥
  3). `BreedingService.pickCreatureForRarity` now calls this instead of
  indexing `CREATURE_POOL` directly (the one necessary `BreedingService`
  edit — `BreedingConfig` alone couldn't gate by tier since the pool lookup
  lived in the service).
- `CrystalLeviathan` lives directly in `CREATURE_POOL.Mythic` (not a
  zone-gated table): it's already effectively gated by tier because
  `TIERS[3].RarityWeights.Mythic = 0.5` is the *only* tier with any Mythic
  weight at all (tiers 1/2 have no `Mythic` key → `rollWeightedRarity` can
  never return it there). Tier 3's `Legendary` weight was trimmed from 3 to
  2.5 to keep the tier's total weight at 100.
- `CREATURE_DISPLAY_NAME_FALLBACK` extended with all 8 new zone creatures.

### Gacha (`GachaConfig.lua`)

- `CREATURE_POOL.Mythic = { "CrystalLeviathan" }` (was `{}`). No change
  needed in `GachaService`: `_pickCreatureForRarity` already had a
  "fall back to next-lower non-empty pool" mechanism for the empty-Mythic
  case — with a non-empty pool it now simply returns `CrystalLeviathan` at
  the rolled Mythic rate (0.5%) without any fallback warning.
- `CREATURE_DISPLAY_NAME_FALLBACK.CrystalLeviathan` added.

## 5. Fail-soft summary

Every new template lookup (enemies, towers) warns once and substitutes a
known-good fallback (`ShadowKraken` / `AnglerfishTower`) instead of
returning `nil` outright — matches the existing `AssetTemplateSetup`
pattern for missing buildscript results. `RaidService`/`PlacementService`
still ultimately handle a *fully* missing fallback (fresh server, no
buildscripts run at all) the same way they always did (`TemplateMissing`
reason / skipped spawn with a warning).

## 6. Files not touched (and why)

- `PlacementService.lua` / `PlacementPreviewController.client.lua`: both
  already read `BuildingConfig` generically (`ORDER` + `Get`), so the two
  new towers are placeable/previewable without any code change.
- `PlayerDataService.lua`: no new persisted field — "the player's zone" is
  derived from the existing `GetLevel`, see section 1 above.
- `RaidUIController.client.lua`: already renders `RaidRemotes.EnemyHit`
  generically (tower/enemy positions only, no hardcoded model/part names),
  so the extra chain-hit events and new tower types need no client change.
- `GachaService.lua`: no change needed, see section 4.
