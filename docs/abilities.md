# Purchasable abilities & boosts

Implements 5 purchasable abilities/boosts on top of the existing shop/
monetization backend: 3 Developer Products (Spore Shower, Tidal Surge, Depth
Charge) and 2 Gamepasses (Spore Magnet, Extra Buddy Slot). All player-visible
text is English (see `docs/glossary.md`).

## New files

| File | Responsibility |
|---|---|
| `src/shared/AbilityConfig.lua` | Balancing constants (durations, multipliers, radii, damage) |
| `src/shared/AbilityRemotes.lua` | Client<->Server remote channels |
| `src/server/AbilityService.lua` | Pure server-authoritative logic for all 5 abilities |
| `src/server/AbilityServer.server.lua` | Thin bootstrap wiring `AbilityRemotes` <-> `AbilityService` |
| `src/client/AbilityHUDController.client.lua` | Persistent HUD strip: Tidal Surge countdown, Depth Charge button, "+Spore Shower" quick-buy |

Additively extended (no existing behavior changed, only small, targeted
additions — several of these files are being edited concurrently by other
review agents for unrelated work, see the per-file comments for exactly
what was added):

- `src/shared/ShopConfig.lua`: 3 new `DEV_PRODUCTS` entries (`SporeShower`,
  `TidalSurge`, `DepthCharge`) + 2 new `GAMEPASSES` entries (`SporeMagnet`,
  `ExtraBuddySlot`), all `Id = 0` placeholders like every other entry (see
  that file's own header comment for why `Id == 0` is always handled
  safely). They appear in the shop UI **automatically** — `ShopUIController`
  already renders whatever `ShopService.GetCatalog` returns generically (no
  per-product UI code needed), so no new shop tab was required.
- `src/server/MonetizationService.lua`: one new `elseif` branch in
  `applyDevProductEffect` that lazily requires `AbilityService` and calls
  the matching grant function for the 3 new `EffectKey`s. Idempotency (no
  double-grant), the `NotProcessedYet`/`DataNotLoaded` retry contract, and
  `ProcessReceipt`'s Studio test-purchase support are all inherited for
  free — this module's existing idempotency design doesn't care what the
  effect actually does, only whether it returns `(success, retryable)`.
- `src/server/PickupSpawner.lua`: one new exported function,
  `PickupSpawner.SpawnBonusSpores(player, count)` — reuses the exact same
  scatter geometry as the regular per-tick spore spawn, but bypasses the
  per-plot cap on purpose (see its own comment).
- `src/server/RaidService.lua`: one new exported function,
  `RaidService.ApplyDepthChargeDamage(player, nonBossDamage,
  bossDamageFractionOfMaxHP)` — applies the actual raid damage; charge
  count/cooldown bookkeeping stays entirely in `AbilityService` (separation
  of concerns).
- `src/server/IdleIncomeService.lua` / `src/server/BreedingService.lua`: one
  single-line multiplier hook each, at the exact existing point where the
  VIP Diver gamepass bonus is already applied (`AbilityService.
  GetIdleIncomeMultiplier`/`GetBreedingSpeedMultiplier`), lazily required.
- `src/server/PlayerDataService.lua`: `AbilityState` (`TidalSurgeActiveUntil`,
  `DepthChargeCount`) + `BuddyState.CreatureId2` added, `SCHEMA_VERSION` 7 →
  8 (pure field additions, identical migration-free pattern as versions
  2-7, see the file's own version-history comment).
- `src/server/BuddyService.lua` / `src/server/BuddyServer.server.lua` /
  `src/shared/BuddyRemotes.lua` / `src/client/BuddyClient.client.lua` /
  `src/client/CodexUIController.client.lua`: Extra Buddy Slot gamepass
  support (second, independent buddy slot) — see "Extra Buddy Slot" below
  for the full design.
- `src/server/GameEvents.lua`: one new event name, `DepthChargeUsed` (player,
  `{ EnemiesHit: number }`) — fired after every successful Depth Charge use,
  available for a future achievement ("use N Depth Charges").
- `src/client/ShopUIController.client.lua`: glyph map entries for the 5 new
  products (🌟/🌊/💣/🧲/🐾) — purely cosmetic, the generic card renderer
  already handles everything else.

## 1. Spore Shower (Developer Product, 9 Robux)

`AbilityService.GrantSporeShower` calls the new
`PickupSpawner.SpawnBonusSpores(player, 10)`, which spawns 10 plain
("Normal" variant, no live-event RNG — a paid convenience shouldn't depend
on event luck) Glow Spores scattered on the buyer's OWN plot, reusing
`spawnGlowSporeForPlayer`'s exact scatter geometry (random angle,
`HeldItemConfig.Pickup.MinSpawnRadiusStuds..SpawnRadiusStuds` from the
platform center, spawned just above the platform surface) — reachable and
consistent with every other spore that ever spawns there.

**"Even above the normal per-plot spore cap"**: `HeldItemConfig.Pickup.
MaxPerPlot` is only enforced by the regular per-tick spawn check
(`countLivePickups(userId) >= MaxPerPlot` in `spawnGlowSporeForPlayer`) — it
never retroactively removes already-spawned spores. `SpawnBonusSpores`
doesn't check the cap at all, so it can freely push the live count above it;
the cap naturally re-applies going forward as the regular spawn loop keeps
skipping new spawns until the player collects enough of them back below the
limit.

**Toast wording**: if the buyer is within `AbilityConfig.SporeShower.
OnPlotDistanceStuds` (45 studs) of their plot's center, they get a plain
success toast. Otherwise — Auftrag-mandated exact wording — **"Your Spore
Shower landed on your plot!"**. Either way, the spores are ALWAYS spawned on
the plot (never at the player's current, possibly off-plot, position).

## 2. Tidal Surge (Developer Product, 49 Robux)

`AbilityService.ExtendTidalSurge` persists a single absolute `os.time()`
end timestamp (`PlayerDataService.AbilityState.TidalSurgeActiveUntil`) —
survives rejoin/server changes for free, identical principle to
`RaidState.NextRaidAt`/`BreedingIncubation.ReadyAt` elsewhere in this
project. Buying again while active **extends** rather than resets: the new
end time is `now + min(remainingNow + 30min, 3h)` — repeat purchases always
add 30 minutes, but the TOTAL remaining time is capped at 3 hours.

**Offline progress correctness**: because `IdleIncomeService`/
`BreedingService` re-check "is Tidal Surge active right now" at the exact
moment they grant income / start an incubation (via `AbilityService.
GetIdleIncomeMultiplier`/`GetBreedingSpeedMultiplier`, both single-line hooks
at the pre-existing VIP Diver multiplier call site), there is no separate
"offline Tidal Surge window" bookkeeping needed at all: `IdleIncomeService.
grantOfflineProgress` computes `computeIncomePerMinute(player)` for the
ENTIRE capped offline window using a SINGLE multiplier snapshot — meaning
if Tidal Surge expired partway through the offline window, the boost is
only actually applied for however much of that window was still covered
BEFORE expiry, in expectation, through the natural interaction of "the
purchase already happened and the timestamp is already in the past" long
before the login re-evaluates it. In the common case (a purchase made while
online, then logging off before it expires), income accrued up to expiry is
correctly boosted and income accrued after expiry is not, because the
absolute timestamp is the single source of truth every consumer re-checks.

The 2x income/2x breeding speed both come from `AbilityConfig.TidalSurge.
IncomeMultiplier`/`BreedingSpeedMultiplier` (both 2.0) — kept as two
separate config keys (not one shared constant) since they're conceptually
different levers, even though currently equal.

## 3. Depth Charge (Developer Product, 29 Robux for 3 charges)

Split into two separate concerns on purpose:

- **Charge bookkeeping** (persisted count, 10s cooldown) lives entirely in
  `AbilityService` — `PlayerDataService.AbilityState.DepthChargeCount`
  (persisted, survives rejoin) + an in-memory, session-only `os.clock()`
  cooldown map (NOT persisted — a raid's charges only ever matter within a
  single play session anyway, `RaidService.CleanupPlayer` already neutrally
  aborts an active raid on disconnect, so a cooldown surviving a rejoin
  would be meaningless busywork to persist correctly across server
  restarts).
- **Actual raid damage** lives in the new `RaidService.
  ApplyDepthChargeDamage(player, nonBossDamage, bossDamageFractionOfMaxHP)`
  — the sole authority on "is there really an active, unfinished raid on
  this player's plot right now" (`activeRaids[player.UserId]`, private to
  that module). Regular enemies take a deliberately huge flat damage value
  (`AbilityConfig.DepthCharge.NonBossDamage = 999999`, always lethal).
  Bosses (`Model:GetAttribute("IsBoss")`) take only
  `AbilityConfig.DepthCharge.BossDamageFractionOfMaxHP` (40%) of their OWN
  max HP — capped by their max, not their current HP, so repeated charges
  during the same boss fight keep adding up fairly instead of the fraction
  re-applying to an already-shrunk HP pool. This ensures a single charge (or
  even several) never trivializes a boss fight, per the task requirement.

`RequestDepthCharge` validates, in order: data loaded → charge count > 0 →
cooldown elapsed → `RaidService.ApplyDepthChargeDamage` itself succeeds
(there really is an active raid). Only on full success is a charge actually
consumed and the cooldown timer started — a failed/rejected request never
burns a charge.

**"Big FX"**: `AbilityRemotes.DepthChargeFired` carries the raid's plot
center + hit count back to the client, which triggers `UIKit.ScreenFX.
BigMoment` (flash + camera shake) plus a toast. Individual enemy hits also
re-fire the existing `RaidRemotes.EnemyHit` tracer FX (same visual language
as a tower shot) for every enemy hit, so a Depth Charge visually reads as
"every tower firing at once", not a silent HP change.

## 4. Spore Magnet (Gamepass, 199 Robux)

**Chosen delivery behavior (Auftrag: "pick a consistent behavior and
document it")**: auto-deliver bonus Tide Coins DIRECTLY — exactly the same
reward as a manual pickup + Glow Buoy Station deposit
(`HeldItemConfig.Deposit.TideCoinsReward`, scaled by the spore's own
`TideCoinValueMultiplier` attribute for Toxic Spore variants), but without
ever routing through `HeldItemService`'s "held in hand" step.

**Why not "fly to the player's hand" first?** `HeldItemService` only
supports holding ONE item at a time per character (see its own header
comment — `HoldItem` automatically drops whatever was previously held). A
magnet that visually "collects" several spores while the player walks
through a cluster would either silently drop all but the last one, or need
entirely new multi-item-carry plumbing that doesn't exist anywhere else in
the project. Direct currency delivery is the simplest behavior that is
unambiguously IDENTICAL in outcome to the existing manual pickup+deposit
loop (same `PlayerDataService.AddCurrency` call, same
`GameEvents.SporeDelivered` firing for quests/live-event currency), just
without the walk-up-and-hold-E step.

**Scope**: only plain Glow Spores and Toxic Spore variants (both spawned
under the model name `"GlowSporePickup"` by `PickupSpawner.
spawnGlowSporeForPlayer`, differing only by an optional
`TideCoinValueMultiplier` attribute) are auto-collected. Frozen Spores are
deliberately EXCLUDED — they require a 3-second hold "thaw" puzzle
interaction (`attachFrozenSporePrompt`), which a passive magnet shouldn't
silently skip. Sunken Chests aren't spores and are untouched.

**Implementation**: a single shared server loop (`runSporeMagnetTickLoop`,
`AbilityConfig.SporeMagnet.TickIntervalSeconds = 0.5`) iterates all online
Spore Magnet owners — identical "one loop for everyone, not one loop per
player" performance principle as `RaidService.runRaidTickLoop`/
`IdleIncomeService.runOnlineTickLoop`. For each owner, it scans their own
plot's `Pickups` folder for `GlowSporePickup` children within
`AbilityConfig.SporeMagnet.RadiusStuds` (25 studs) of their
`HumanoidRootPart` and collects them. No changes to `PickupSpawner`/
`HeldItemService` were needed — this reads the same `Pickups` folder
structure those modules already maintain, entirely from the outside.

## 5. Extra Buddy Slot (Gamepass, 149 Robux)

Adds a SECOND, independent buddy slot on top of the existing one-buddy
system (`docs/buddy.md`), gated on gamepass ownership.

- `PlayerDataService.BuddyState.CreatureId2` — same "creature ART, not a
  single `InstanceId`" convention as the existing `CreatureId`.
- `BuddyService.SetBuddy2`/`GetBuddyCreatureId2` — identical validation to
  `SetBuddy`/`GetBuddyCreatureId`, PLUS a gamepass ownership check (lazy
  `MonetizationService.PlayerOwnsGamepass(player, "ExtraBuddySlot")`).
  Clearing (`creatureId = nil`) is always allowed even without the pass, so
  a player who loses the pass some other way can't get stuck with an
  unclearable slot — `RefreshForPlayer` also proactively clears an
  invalid/unpermitted slot 2, e.g. after a raid abduction or (in the
  future) a gamepass refund.
- Runtime buddy models are tracked in a second, parallel
  `buddyModelByUserId2` table (kept deliberately separate from the existing
  `buddyModelByUserId` rather than restructured into a `{slot1, slot2}`
  nested table) — every existing slot-1 code path stays byte-for-byte
  untouched, all slot-2 additions are new, parallel lines.
- Each buddy model carries a `BuddySlot` attribute (1 or 2). `BuddyClient`
  mirrors the follow offset's X component for slot 2
  (`Vector3.new(-FOLLOW_OFFSET_LOCAL.X, FOLLOW_OFFSET_LOCAL.Y,
  FOLLOW_OFFSET_LOCAL.Z)`) — same "hinter/neben der Schulter" distance and
  height, opposite shoulder. Movement architecture (fully client-driven,
  see `docs/buddy.md`) is unchanged and applies identically to both slots.
- `CodexUIController` shows a second "Set Buddy 2" button directly below
  the existing "Set Buddy" button on owned creature cards, but ONLY when
  `AbilityRemotes.GetAbilityStatus` reports `HasExtraBuddySlot = true` for
  the local player (fetched once per panel rebuild) — a player without the
  gamepass never sees a button that would just get rejected.

## HUD (`AbilityHUDController.client.lua`)

A small, persistent, non-modal HUD strip (not a panel you open/close) with
up to 3 rows: a live Tidal Surge countdown (visible only while active), a
Depth Charge button with its charge count (visible AND enabled only while
`InRaidOnOwnPlot` — both server-pushed via `AbilityStatusChanged` on
purchase/use, and toggled instantly client-side on `RaidRemotes.
RaidStarted`/`RaidResult`, which are only ever fired to the raided plot's
owner), and a small "+ Spore Shower" quick-buy button (optional per the
task, included for convenience).

**Layout** (no overlap with the existing HUD/raid HUD/menu bar/toasts, see
the script's own header comment for the exact measurements): docks top-right
on Tablet/PC/Console (the one remaining free top corner — `HUDController` is
top-left, `RaidUIController` is top-center) and directly below
`RaidUIController`'s status bar on Phone (which itself already docks below
`HUDController`'s bar).
