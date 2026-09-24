# Server Features for Release – Abyssara – Deep Tide Tycoon

As of: 2026-09-24. Reference: `docs/game-design-doc.md` Sections 3, 6, 7, 9
(points 10, 11), 10; `docs/held-items.md`; `assets/models/README.md`
section "hub".

This document describes the four new server systems (daily quests + daily
login reward, leaderboards, travel/teleports) and the central event hub
that connects them to the already-existing gameplay services. For the
following UI agent: **all remotes below are fully wired and server-side
validated** - only client UI needs to be built on top, no further server
logic.

## 1. New files

| File | Role |
|---|---|
| `src/server/GameEvents.lua` | Central, purely server-internal event hub (BindableEvent registry) |
| `src/shared/QuestConfig.lua` | Daily quest template pool |
| `src/shared/DailyRewardConfig.lua` | 7-day streak reward table |
| `src/shared/QuestRemotes.lua` | Remotes for daily quests AND daily login reward (bundled) |
| `src/shared/LeaderboardRemotes.lua` | Remote for leaderboard queries |
| `src/shared/TravelRemotes.lua` | Remotes for hub/plot/zone teleport |
| `src/server/QuestService.lua` + `QuestServer.server.lua` | Daily quest logic + bootstrap |
| `src/server/DailyRewardService.lua` + `DailyRewardServer.server.lua` | Login streak logic + bootstrap |
| `src/server/LeaderboardService.lua` + `LeaderboardServer.server.lua` | Leaderboard logic (OrderedDataStore) + bootstrap |
| `src/server/TravelService.lua` + `TravelServer.server.lua` | Teleport logic (ProximityPrompts + remotes) + bootstrap |

Rojo mapping: unchanged, `default.project.json` already includes `src/server`
and `src/shared` fully/flat - no changes needed.

## 2. Central event hub (`GameEvents`)

Instead of scattering quest/leaderboard calls across every service, the
existing services fire exactly one `GameEvents.Fire(eventName, player,
payload)` at their existing success points (the same points where
`ProgressionService.AwardXP` is already called today):

| Event | Firing location | Payload |
|---|---|---|
| `BuildingPlaced` | `PlacementService.RequestPlace` | `{ BuildingId, PlacementId }` |
| `BreedingCompleted` | `BreedingService.RequestClaimBreeding` / `RequestInstantComplete` | `{ CreatureId, Rarity, PlacementId, Instant? }` |
| `RaidWon` | `RaidService.finishRaid` (live) + `evaluateOfflineRaids` (offline) | `{ WavesCleared, RewardTideCoins?, Offline? }` |
| `RaidLost` | `RaidService.finishRaid` + `evaluateOfflineRaids` | `{ AbductedInstanceId?, Offline? }` |
| `EggOpened` | `GachaService.performRoll` (free and Robux path) | `{ Rarity, CreatureId, ResultType, Purchased }` |
| `SporeDelivered` | `PickupSpawner.onDepositTriggered` | `{ Amount }` |
| `CoinsEarned` | `PlayerDataService.AddCurrency` (central, TideCoins only, positive gains only) | `{ Amount, NewLifetimeTotal }` |

`QuestService` and `LeaderboardService` are the only current subscribers -
no circular `require`s (GameEvents itself has no dependencies).

## 3. Remote API for the UI agent

### 3.1 Daily quests (`ReplicatedStorage.QuestRemotes`)

- `GetQuestState` (RemoteFunction, no payload) →
  `{ DateKey, Quests: { { TemplateId, Description, Target, Progress, Completed, Claimed, RewardTideCoins, RewardAbyssalShards, RewardXP } } }`
- `QuestProgressUpdated` (Server→Client push) →
  `{ TemplateId, Progress, Target, Completed }`
- `RequestClaimQuestReward` (Client→Server) → payload `templateId: string`
- `ClaimQuestRewardResult` (Server→Client) →
  `{ Success, Reason?, TemplateId?, RewardTideCoins?, RewardAbyssalShards?, RewardXP?, NewTideCoinBalance? }`
  (`Reason`: `DataNotLoaded` | `UnknownQuest` | `NotCompleted` | `AlreadyClaimed`)

3 random quest templates from a pool of 4 daily (deliver spores, complete
breeding, win a raid, build a building), reset at 00:00 UTC.

### 3.2 Daily login reward (also `QuestRemotes`)

- `GetDailyRewardState` (RemoteFunction) →
  `{ CanClaim, PendingStreakDay, PreviewTideCoins, PreviewAbyssalShards, VipBonusActive, AlreadyClaimedToday }`
- `RequestClaimDailyReward` (Client→Server, no payload)
- `DailyRewardClaimed` (Server→Client) →
  `{ Success, Reason?, StreakDay?, RewardTideCoins?, RewardAbyssalShards?, NewTideCoinBalance? }`
  (`Reason`: `DataNotLoaded` | `AlreadyClaimedToday`)

Streak 1-7 increasing, resets (cyclically back to 1) on a missed day. The
VIP Diver gamepass gives `+50%` on this system's TideCoins payout
(`DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER`) - **completely
independent** of the already-existing `MonetizationService` VIP chest
(`Get/SetLastVipChestClaimedDate`), which keeps running unchanged. No data
duplication.

### 3.3 Leaderboards (`ReplicatedStorage.LeaderboardRemotes`)

- `GetLeaderboard` (RemoteFunction) → payload `category: "Level" | "TideCoins" | "RarestCollection"`
  → `{ Category, Entries: { { Rank, UserId, Name, Score } }, UpdatedAt } | nil`

Categories: `Level` (MVP proxy for "Deepest Zone", see the reasoning in the
header comment of `LeaderboardService.lua` - a real zone-depth field
doesn't exist in the MVP yet), `TideCoins` (lifetime total, NOT current
balance), `RarestCollection` (sum of rarity indices across the creature
inventory). The server also directly populates a `SurfaceGui` on the hub
object `LeaderboardBoard/DisplayPanel` (cycling between the 3 categories
every 10s) - no client code needed for that.

### 3.4 Travel/teleports (`ReplicatedStorage.TravelRemotes`)

- `RequestTravelToPlot` / `RequestTravelToHub` (Client→Server, no payload)
- `RequestTravelToZone` (Client→Server) → payload `zoneId: "SunZone" | "TwilightZone" | "MidnightZone" | "HadalDepths"`
- `TravelResult` (Server→Client) →
  `{ Success, Reason?, Destination?, RequiredLevel?, CurrentLevel? }`
  (`Reason`: `OnCooldown` | `NoPlot` | `UnknownZone` | `LevelTooLow` | `ZoneComingSoon` | `NoCharacter` | `NoHub`)

The same logic is also already usable via `ProximityPrompt`s at the hub (no
UI code needed): `PlotGate` → your own plot, `Portal_<Zone>` → the
respective zone (checks the `RequiredLevel` attribute server-side). The
remotes are meant for an optional fast-travel UI panel. `SunZone`/
`TwilightZone` are actually walkable in the MVP; `MidnightZone`/
`HadalDepths` currently respond with `Reason = "ZoneComingSoon"` until
their terrain chunks are placed in the world (the assets already exist, see
`assets/models/README.md`).

## 4. Schema changes (`PlayerDataService`, SchemaVersion 2 → 3)

Purely additive fields, no renaming/splitting - the existing
`fillMissing()` migration automatically upgrades old records, no dedicated
`MIGRATIONS[2]` function needed (identical pattern to version 1 → 2):

```lua
QuestState: { DateKey: string?, Quests: { { TemplateId, Target, Progress, Claimed } } }
DailyRewardState: { LastClaimedDate: string?, Streak: number }
Stats: { LifetimeTideCoinsEarned: number }
```

New `PlayerDataService` API: `Get/SetQuestState`, `GetDailyRewardState`,
`SetDailyRewardClaimed`, `GetLifetimeTideCoinsEarned`.
`AddCurrency` writes `Stats.LifetimeTideCoinsEarned` forward on every
positive TideCoins gain and fires `GameEvents.CoinsEarned`.

**Additional minimal change outside the explicit file list:**
`src/shared/ProgressionConfig.lua` got two new, purely additive
`XP_REWARDS` entries (`QuestCompleted = 20`, `DailyLoginClaimed = 10`) plus
the matching type extension - necessary so that `QuestService`/
`DailyRewardService` keep going exclusively through
`ProgressionService.AwardXP` (the single source of truth for XP), instead
of inventing a second XP-granting logic.

## 5. Hand-off (`docs/held-items.md`, Section 7)

`GachaService.performRoll` and `BreedingService.RequestClaimBreeding` /
`RequestInstantComplete` now call `HeldItemService.HoldItem(player,
"Creature", <live creature model from Workspace.Assets.Creatures>, {
DisplayName = ... })`. Auto-drop after 6 seconds via a local `task.delay`
(with a check for whether the player is already holding a different item in
the meantime, so it doesn't accidentally drop an already-new item) -
`HeldItemService.lua` itself was NOT changed for this (not part of the
allowed changes). No double inventory bookkeeping: `AddCreatureToInventory`
already ran before this, the hand-off call doesn't book anything again, it
only moves a cloned display instance.

The "purchased egg moves into the hand" sub-aspect of point 5 is
deliberately NOT implemented separately: `GachaService.OpenPurchasedEgg`
internally triggers the same `performRoll` path as the free opening (no
separate "buy, then open later" intermediate step exists in the current
gacha flow) - the hatched creature moves into the hand identically via
either path.

## 6. Robustness

All new DataStore access (`LeaderboardService`) runs in `pcall` with
retry+backoff (`withRetry`, analogous to `PlayerDataService`). No
`while true do wait() end` without `task.wait`. `PlayerRemoving` cleanup in
all four new services (cooldown/dirty-flag tables). Leaderboard writes are
throttled (dirty flag + 90s interval + stagger between individual
`SetAsync` calls), reads run only every 5 minutes and are cached
server-side - no live read per client request.

## 7. Open items

- The `LeaderboardService` category "Level" is a documented MVP proxy for
  "Deepest Zone" - once a real zone-depth field exists, only
  `computeScores().Level` needs to be replaced.
- `TravelService` only teleports to `MidnightZone`/`HadalDepths` once their
  terrain chunks are actually placed in the world (currently
  `"ZoneComingSoon"`).
- No dedicated UI for quests/daily reward/leaderboards/travel yet - all
  remotes are ready, the panel UI follows in the next step via the UI
  agent.
- The VIP bonus in `DailyRewardService` and the existing VIP chest in
  `MonetizationService` are deliberately two separate, additive bonuses
  (see Section 3.2) - if the game design considers this "too much VIP", a
  later consolidation would be a pure balancing change, not an
  architecture rework.
