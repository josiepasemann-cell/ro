# Reef Cluster (co-op groups)

Groups of up to 4 players in the **same server** with one leader (GDD
sections 4 and 7, Phase 2). Membership lives only for the session; only the stats in
`PlayerData.CoopState` are saved.

Files:

| File | Role |
|---|---|
| `src/shared/ClusterConfig.lua` | Size, invite timing, income bonus, English reason texts |
| `src/shared/ClusterRemotes.lua` | All remotes |
| `src/server/ClusterService.lua` | All logic and the public API below |
| `src/server/ClusterServer.server.lua` | Wires the remotes to the service |
| `src/client/ClusterUIController.client.lua` | Cluster panel (More -> Cluster) and invite dialog |

## What players can do

- **Create** a cluster, or just invite someone (the inviter becomes leader).
- **Invite** any loaded player in the server who is not in a cluster (nearby ones first,
  45 s timeout). Only the leader can invite once a cluster exists.
- **Accept / decline** via a dialog. **Leave** any time. The leader can **kick**.
- If the leader leaves or disconnects, the longest-standing member becomes leader.
  The cluster ends when the last member leaves.
- **Visit**: teleport to a member's reef plot (8 s cooldown). Uses the same
  landing ray as `TravelService.RequestTravelToPlot`, with the target's plot
  from `PlotRegistry`.
- **Income bonus**: +5% idle income per other member online, capped at +15%
  (`ClusterConfig`). Applied in `IdleIncomeService.computeIncomePerMinute`
  (one commented block after the codex multiplier) via
  `ClusterService.GetIncomeMultiplier`. The cluster is empty at login, so offline
  income is not boosted.
- **Leaderboard**: a "Cluster" tab / board category `ClusterWave` = `CoopState.BestClusterWave`
  (own OrderedDataStore `Abyssara_LB_ClusterWave_v1`; players with 0 get no entry).

## API for the raid code

```lua
local ClusterService = require(ServerScriptService:WaitForChild("ClusterService"))

ClusterService.GetCluster(player)         -- { Id: string, Leader: Player, Members: { Player } }? ; nil if not in a cluster
ClusterService.GetClusterMembers(player)  -- { Player }; { player } if solo (always includes the player)
ClusterService.AreInSameCluster(a, b)     -- boolean
ClusterService.GetIncomeMultiplier(player)-- number >= 1
ClusterService.RecordClusterRaid(player, wave, won) -- call once per participating member
```

- `Members` is a fresh array each call (safe to modify) and only contains players still in the server.
- `RecordClusterRaid` calls `PlayerDataService.RecordClusterRaid` (best wave, raids won)
  and then fires `GameEvents` `"ClusterRaidFinished"` so the leaderboard refreshes.
  Calling `PlayerDataService.RecordClusterRaid` directly also persists the stats,
  but the board then updates only on the player's next dirty event.
- `GameEvents` `"ClusterChanged"` (player, `{ ClusterId: string?, Members: { Player }, LeaderUserId: number?, Reason: string }`)
  is fired for **every affected player** on create, join, leave, kick, disconnect and
  leader change (`Reason`: Created, Joined, Left, Kicked, Disconnected, LeaderChanged).
  A player who left gets `ClusterId = nil` and `Members = { player }`.

`RaidService` was not touched by this feature. Members joining and defending a
member's raid is built on this API, see `docs/guardians-and-coop.md`.

## Remotes (`ReplicatedStorage.ClusterRemotes`)

Client to server (RemoteEvent): `RequestCreateCluster()`, `RequestInviteToCluster(userId)`,
`RespondClusterInvite(inviteId, accept)`, `RequestLeaveCluster()`, `RequestKickFromCluster(userId)`,
`RequestTeleportToMember(userId)`. RemoteFunction: `GetClusterInfo()` (state and invite candidates).
Server to client (RemoteEvent): `ClusterState`, `ClusterInviteReceived`, `ClusterInviteClosed`, `ClusterNotice`.
All handlers type-check arguments and are rate limited.

## Limits / open points

- Not tested in Studio yet. Test with 2-4 clients: invite, accept, decline, leave, kick,
  leader leaves, visit a plot, income tick with 2 members, leaderboard tab.
- Invites work server-wide, not only for players standing close.
- No leader transfer button (automatic only).
- Cluster state is not kept across servers or teleports; players who rejoin start solo.
