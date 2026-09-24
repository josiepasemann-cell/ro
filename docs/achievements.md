# Abyssara – Achievements, Titles & Roblox Badges

This document describes the Achievements system: the full list of
achievements, how rewards/titles/badges work, and how to create real Roblox
badges and plug their ids into the game.

## Where things live

| File | Responsibility |
|---|---|
| `src/shared/AchievementConfig.lua` | Data only: the list of achievements (category, name, description, progress metric, target, reward, `BadgeId`). |
| `src/shared/AchievementRemotes.lua` | Client<->server remote channels (`GetState`, `AchievementUnlocked`, `AchievementProgressUpdated`, `RequestClaimReward`, `ClaimRewardResult`, `RequestEquipTitle`, `EquipTitleResult`). |
| `src/server/AchievementService.lua` | Core logic: counts progress from `GameEvents`, persists it, unlocks achievements, validates claims, grants Roblox badges, manages the equipped-title billboard above the player's head. |
| `src/server/AchievementServer.server.lua` | Thin bootstrap that wires `AchievementRemotes` to `AchievementService`. |
| `src/client/AchievementUIController.client.lua` | The Achievements panel (tabs per category + a Titles tab), progress bars, claim buttons, toast/FX on unlock, title picker. |
| `src/server/PlayerDataService.lua` | Additive `AchievementState` (`Counters`, `Unlocked`, `Claimed`, `EquippedTitle`, `BackfillCompleted`) persisted per player. |

The Achievements panel is opened from the main menu bar (🏅 "Achievements",
keyboard shortcut `K` on PC) via `MainMenuController.client.lua`.

## How progress is tracked

Every achievement has a `Metric`:

- **Counter** achievements accumulate as `GameEvents` fire (e.g. `RaidWon`
  increments the `RaidsWon` counter by 1 each time). These start at 0 for
  everyone except a couple of keys (`BuildingsPlaced`,
  `RaidsLostWithAbduction`) that get a one-time, best-effort starting value
  derived from existing save data the first time a player logs in after this
  system ships (see `AchievementService.runBackfill`).
- **Snapshot** achievements are computed live from data that was already
  being persisted before this system existed (player level, unique
  creatures owned, completed codex zones, owned live-event shop items, ...).
  Because they're always recomputed from the current save, they are
  automatically correct for existing players retroactively - no backfill
  code needed for these.

Once an achievement is unlocked it **stays unlocked forever**, even if the
underlying value later drops again (for example, a creature that was
counted toward a Collection achievement gets abducted in a raid).

Unlocking an achievement is separate from claiming its reward: unlocking
happens automatically and immediately shows a toast + screen flash and
grants the Roblox badge (if one is configured). Claiming the Tide
Coins/Abyssal Shards/title reward is a separate, explicit button press in
the Achievements panel (server-validated, can only happen once).

## Titles

Titles earned from achievements are added to the same title-ownership pool
used by the Creature Codex zone-collection rewards and Live Event quest
lines (`PlayerDataService` field `CodexState.UnlockedTitles`, via the
existing `AddUnlockedTitle` function) - there is only one title pool in the
whole game, achievements just add to it.

The currently **equipped** title (`AchievementState.EquippedTitle`, a
separate field - equipping doesn't "use up" a title) is shown:

- As a neon `BillboardGui` above the player's head in the 3D world
  (`AchievementService.RefreshTitleBillboard`), readable at a distance
  (`MaxDistance = 90`), rebuilt on every `CharacterAdded`.
- **Not** currently reflected in `LeaderboardService`'s leaderboard entries
  or its Hub `SurfaceGui` board - that service's entry format (`Rank, UserId,
  Name, Score`) has no display/title field today. If a future agent wants
  titles on the leaderboard, `LeaderboardService` would need a small,
  additive change to read `PlayerDataService.GetAchievementState(player)
  .EquippedTitle` when building its rows.

Players pick their equipped title from the "Titles" tab in the Achievements
panel.

## The achievement list (25 total)

All rewards below are Tide Coins / Abyssal Shards, plus a title where noted.
Secret achievements show as "???" with a vague hint until unlocked.

### Building
| Achievement | Requirement | Reward |
|---|---|---|
| First Foundations | Place 1 building | 100 🪙 |
| Habitat Architect | Place 25 buildings total | 400 🪙 + 2 💎 + title "Habitat Architect" |
| Master Builder | Place every one of the 6 building types at least once | 600 🪙 + 3 💎 + title "Master Builder" |

### Breeding
| Achievement | Requirement | Reward |
|---|---|---|
| First Clutch | Complete 1 breeding | 120 🪙 + 1 💎 |
| Broodkeeper | Complete 25 breedings total | 500 🪙 + 3 💎 + title "Broodkeeper" |
| Rare Bloodline | Breed a Legendary or Mythic creature | 350 🪙 + 5 💎 + title "Bloodline Keeper" |

### Trench Raids
| Achievement | Requirement | Reward |
|---|---|---|
| Trench Defender I | Win 1 raid | 150 🪙 + 1 💎 + title "Trench Defender" |
| Trench Defender II | Win 10 raids total | 600 🪙 + 4 💎 + title "Trench Guardian" |
| Trench Defender III | Win 50 raids total | 2000 🪙 + 10 💎 + title "Trench Legend" |

### Collection (Creature Codex)
| Achievement | Requirement | Reward |
|---|---|---|
| Budding Collector | Own 10 different creature species | 300 🪙 + 2 💎 |
| Abyssal Cataloguer | Own 25 different creature species | 800 🪙 + 5 💎 + title "Cataloguer" |
| Zone Completionist | Fully catalogue all 4 zones | 1000 🪙 + 6 💎 + title "Zone Master" |

### Mystery Eggs
| Achievement | Requirement | Reward |
|---|---|---|
| Cracked Open | Open 1 Mystery Egg | 80 🪙 |
| Egg Enthusiast | Open 50 Mystery Eggs total | 500 🪙 + 3 💎 + title "Egg Enthusiast" |
| Legendary Luck | Hatch a Legendary or Mythic creature from an egg | 400 🪙 + 5 💎 + title "Egg Whisperer" |

### Glow Spores
| Achievement | Requirement | Reward |
|---|---|---|
| Spore Gatherer | Deliver 100 Glow Spores total | 200 🪙 + 1 💎 |
| Spore Tycoon | Deliver 1000 Glow Spores total | 900 🪙 + 4 💎 + title "Spore Tycoon" |

### Levels
| Achievement | Requirement | Reward |
|---|---|---|
| Rising Diver | Reach level 5 | 150 🪙 |
| Deep Diver | Reach level 15 | 500 🪙 + 3 💎 + title "Deep Diver" |
| Abyssal Master | Reach the max level, 25 | 1500 🪙 + 8 💎 + title "Abyssal Master" |

### Live Events
| Achievement | Requirement | Reward |
|---|---|---|
| Tide Rider | Acquire 1 Live Event shop item | 150 🪙 |
| Storm Chaser | Acquire 5 different Live Event shop items total | 600 🪙 + 3 💎 + title "Storm Chaser" |

### Secret
| Achievement | Requirement | Reward |
|---|---|---|
| Night Owl | Play something between 2 AM and 4 AM server time (UTC) | 250 🪙 + 1 💎 + title "Night Owl" |
| Unlucky Dive | Lose a raid and get a creature abducted | 200 🪙 + 1 💎 |
| True Abyssal | Reach level 25 while owning a Mythic creature | 2500 🪙 + 12 💎 + title "True Abyssal" |

## Note on Live Events

`src/server/LiveEventService.lua` already existed, so the "Events" category
above was included. However, that service resets most of its per-player
state on every 12h slot change for fairness reasons (see its header
comment) - the one thing that **does** persist across slots is
`LiveEventState.OwnedEventItems` (a record of every event-shop item ever
purchased), so both event achievements are built on that persistent count
rather than anything that resets.

## Creating real Roblox badges

Every achievement has a `BadgeId` field in `AchievementConfig.lua`. `0`
means "no badge, currency/title reward only" - that's the default for all
25 achievements right now, since real badge ids can only be created by the
game's owner on roblox.com (they're specific to this Roblox experience and
this account).

**Recommended achievements to back with a real badge** (major milestones,
marked with a `-- Recommended: create a badge` comment in
`AchievementConfig.lua`):

- `Building_MasterBuilder` - Master Builder
- `Raids_Tier3` - Trench Defender III
- `Levels_AbyssalMaster` - Abyssal Master
- `Secret_TrueAbyssal` - True Abyssal

Steps to create one and wire it up:

1. Go to <https://create.roblox.com/dashboard/creations>.
2. Open the experience (Abyssara – Deep Tide Tycoon).
3. Go to the **Badges** tab (under Engagement/Monetization, depending on the
   current Creator Hub layout) and click **Create a Badge**.
4. Upload an icon (512x512 recommended), give it a name and description
   matching the achievement (e.g. "Master Builder" / the achievement's
   `Description` text works well here), and save.
5. Copy the numeric **Badge Id** shown on the badge's page (also visible in
   the URL, `.../badges/<id>/...`).
6. Open `src/shared/AchievementConfig.lua`, find the matching achievement
   entry by its `Id` (e.g. `Building_MasterBuilder`), and replace
   `BadgeId = 0` with the real number, e.g. `BadgeId = 123456789`.
7. Publish. `AchievementService` awards the badge automatically the moment
   a player unlocks that achievement (via `BadgeService:AwardBadge`, wrapped
   in `pcall` with a `UserHasBadgeAsync` check first so it never
   double-awards and never blocks gameplay if the Badge API has an outage).

You can add a real badge to **any** achievement this way, not just the four
recommended ones above - just fill in its `BadgeId`.

## Adding a new achievement

1. Add a new entry to `AchievementConfig.LIST` with a unique `Id`, a
   `Category` from `AchievementConfig.Category`, an `Icon`, `Name`/
   `Description` (and `SecretHint` if `Secret = true`), a `Metric`
   (`{ Type = "Counter", Key = "..." }` or `{ Type = "Snapshot", Key = "..." }`),
   a `Target`, a `Reward`, and `BadgeId = 0` (or a real id).
2. If it's a **Counter** metric with a new `Key`, make sure
   `AchievementService` actually increments that key somewhere (usually in
   one of the existing `GameEvents.Connect(...)` handlers near the bottom
   half of the file) - otherwise it will simply never unlock.
3. If it's a **Snapshot** metric with a new `Key`, add a function for it to
   the `SNAPSHOT_PROVIDERS` table in `AchievementService.lua`.
4. No client or `PlayerDataService` changes are needed for a new
   achievement definition itself - `AchievementState.Counters` is a generic
   `[string]: number` map and the UI reads the full list from
   `AchievementConfig.LIST` automatically.
