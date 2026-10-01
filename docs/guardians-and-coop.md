# Guardians, co-op raids and the Deepest Zone board

Status: compiled with luau-compile and checked with luau-lsp, **not run in
Roblox Studio**. All numbers are in `src/shared/RaidConfig.lua` (sections
"Guardians" and "Co-op raids").

## 1. Guardian creatures

Players pick creatures as raid allies in **More > Guardians** (key I) and the
server deploys the saved loadout in the raid.

- **Slots**: 1 from level 1, 2 from level 20, 3 from level 35
  (`GUARDIAN_SLOT_UNLOCK_LEVELS`, `RaidConfig.GetGuardianSlots`).
- **Persistence**: `PlayerDataService.Get/SetGuardianLoadout`.
- **Remotes** (`RaidRemotes`): `GetGuardianLoadout` (RemoteFunction),
  `RequestSetGuardianLoadout`, `RequestDeployGuardian` (no payload, the server
  deploys the saved loadout), plus the server pushes `GuardianStatus`,
  `GuardianAttack`, `GuardianDeployResult`, `GuardianLoadoutChanged`.
- **Rules**: creature must be an owned inventory instance. Abducted creatures
  are not in the inventory (they are listed greyed out) and incubating eggs are
  not creature instances yet; both are also checked explicitly. Loadout payload
  is capped (12 ids), type-checked, deduplicated and trimmed to the slots;
  deploy and loadout calls are rate limited; deploy works once per raid and
  player.
- **Models**: `Workspace.Assets.Creatures.<CreatureId>` cloned like
  `CreatureDisplayService`/`BuddyService` do (the creature models are not
  promoted to ReplicatedStorage). A missing model fails soft: the guardian
  still fights, the HUD shows a letter tile.
- **Combat** (inside the existing shared tick loop, `RaidService.tickGuardians`):
  move at 12 studs/s toward the nearest enemy within 36 studs of the plot
  centre, attack from 7 studs on a 1.2 s cooldown, return to a home ring
  (9 studs) when nothing is in reach. Enemies within 5 studs deal contact
  damage per second (Drifter 5, Swarmer 4, Brute 11, Boss 18). At 0 HP the
  guardian is knocked out for the rest of the raid (client fade, HUD shows
  "Knocked out"); it is never lost or abducted.
- **Movement** uses the animation system: tag `RaidGuardianMotion`
  (`ModelAnimationTags.RAID_GUARDIAN`), server writes `TargetPosition`,
  `ModelAnimator` chases it with the raid chase rate and plays the spawn/KO
  fade (`SpawnedAt`/`DyingAt`).
- **HUD**: `GuardianUIController` shows up to 6 cards (portrait, name, HP bar,
  own guardians first), a "Deploy Guardians" button (automatic at raid start,
  button is the manual fallback) and a coloured beam + particles per attack.

### Balance

| Rarity | DPS | HP |
|---|---|---|
| Common | 4 | 70 |
| Uncommon | 5 | 85 |
| Rare | 7 | 105 |
| Epic | 9.5 | 130 |
| Legendary | 12 | 160 |
| Mythic | 15 | 200 |
| Abyssal | 18 | 240 |

Creatures have no level, so the **owner's level** scales DPS and HP by +0.8 %
per level above 1, capped at +40 % (level 51+). An AnglerfishTower does 27 DPS;
a Mythic guardian at level 50 does about 21 DPS, and a full 3-slot loadout is
worth roughly two towers, while guardians can be knocked out and towers
cannot. Towers stay the backbone.

## 2. Co-op raids with Reef Clusters

`ClusterService` is required lazily (`script.Parent:FindFirstChild` + `pcall`);
without it, or without a cluster, everything stays solo.

- **Invite**: when a raid starts, every other online, loaded cluster member who
  is not in a raid gets `CoopRaidInvite` and a "Join & Defend" dialog.
- **Join**: `RequestJoinCoopRaid(ownerUserId)`. The server checks: number
  payload, rate limit, owner has an active raid, sender is not the owner, not
  already in a raid, sender is in the owner's cluster **at request time**
  (`ClusterService.GetClusterMembers`), fewer than 3 helpers, plot and
  character exist. Then it teleports the helper onto the owner's plot.
- **Helpers** deploy their own guardians and can use Depth Charges there
  (`ApplyDepthChargeDamage` resolves the caller's raid via `getLiveRaidFor`;
  `AbilityService` itself is unchanged, its status follows `GetStatus`). They do
  not fire the owner's towers.
- **Leaving**: `RequestLeaveCoopRaid`, disconnecting, or the owner leaving
  (raid ends neutrally, helpers are sent home). After a finished raid helpers
  are teleported back to their own plot after 8 s.
- **Scaling** (per helper at wave spawn): regular enemies +30 % HP, boss +75 %
  HP, +1 escort in the boss wave.
- **Rewards on victory**: each helper who was present at least 15 s and is
  still a cluster mate gets 75 % of the base coin reward (own 2x Coins gamepass
  applies), `RaidWon` XP, their own shard roll and the `RaidWon` game event;
  the owner gets +10 % coins per helper. Helpers never lose a creature when the
  raid is lost.
- **Stats**: `ClusterService.RecordClusterRaid` (wraps
  `PlayerDataService.RecordClusterRaid` and refreshes the Cluster board) is
  called for the owner and every eligible helper, with the reached wave and the
  result; direct `PlayerDataService.RecordClusterRaid` is the fallback.

## 3. Deepest Zone leaderboard

- `ZoneProgressService` calls `PlayerDataService.RecordZoneReached` on login and
  after every level-up (zone from `ZoneEconomyConfig.GetZoneForLevel`) and
  `TravelService.RequestTravelToZone` calls it after a successful travel.
- `LeaderboardService`: category id stays `"Level"` (client tab id), the label
  is "Deepest Zone", the score is `DeepestZoneEver * 1000 + level` in a new
  OrderedDataStore (`Abyssara_LB_DeepestZone_v2`, the v1 store held plain
  levels). `DataChanged` "DeepestZone" marks the player dirty.
- Display: "Zone N, Lv M" (hub board) / "ZN Lv M" (client panel).

## Files

Server: `RaidService.lua`, `RaidServer.server.lua`, `ZoneProgressService.lua`,
`ProgressionService.lua`, `TravelService.lua`, `LeaderboardService.lua`.
Shared: `RaidConfig.lua`, `RaidRemotes.lua`, `ZoneEconomyConfig.lua`,
`ModelAnimation/ModelAnimationTags.lua`, `LeaderboardRemotes.lua` (comment).
Client: `GuardianUIController.client.lua` (new), `RaidUIController.client.lua`,
`ModelAnimator.client.lua`, `MainMenuController.client.lua`,
`LeaderboardUIController.client.lua`.
