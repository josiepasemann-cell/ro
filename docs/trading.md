# Creature trading

A secure 2-player creature trade at the hub's trade dock (GDD section 7).
Creatures only: no Robux, no currencies.

Files:

| File | Role |
|---|---|
| `src/shared/TradeConfig.lua` | Numbers (min level, cooldown, countdown, distances) and the English reason texts |
| `src/shared/TradeRemotes.lua` | All remotes (see below) |
| `src/server/TradeService.lua` | All trade logic, server-authoritative; creates the dock prompt |
| `src/server/TradeServer.server.lua` | Wires the remotes to the service |
| `src/client/TradeUIController.client.lua` | Picker, request dialog and trade window (UIKit) |

## How a player trades

1. Walk to the trade dock in the Tidal Market hub and use the **Trade** prompt
   (or open **More -> Trade**; the menu entry works anywhere).
2. Pick a player standing close (within 60 studs) and press **Request**.
3. They get an Accept/Decline dialog (30 s timeout).
4. Both pick up to 4 creatures. Tap a creature in "Your creatures" to offer
   it, tap it in "You offer" to take it back. Rarity is shown by color and name.
5. Both press **Ready**. Any change to either offer clears both Ready flags.
6. A **final check** screen lists what you give and get. **Confirm** unlocks
   after a 5 second countdown. Both press Confirm and the swap happens.
   A one-sided offer is allowed (a gift) and is labeled as such.
7. The server swaps the creatures, force-saves both players, refreshes
   the buddy and the plot display, and logs the trade.

Closing the window cancels the trade.

## Rules (all enforced by the server)

- Both players: data loaded, in this server, level >= 5, not in a raid.
- One trade or open request per player at a time.
- Cooldown: 60 s after a completed trade. It uses the persisted
  `TradeState.LastTradeAt`, so rejoining does not skip it.
- Request spam limits: 4 s between requests, 20 s before asking the same
  player again after a decline or timeout.
- The trade is cancelled when a player leaves, dies (or has no character),
  moves more than 90 studs from the partner, or when nothing happens for 3 minutes.
- Max 4 creatures per side, ids must be unique and owned by the offering
  player. The whole offer is validated again right before the swap.
- Anti-scam: `Ready` and `Confirm` carry the **revision** the client saw. Every
  offer change bumps the revision, so a swap in the last second makes
  the other player's pending click fail with "The offer changed".

## Which creatures are locked

| Reference | How it works in the code | Handling |
|---|---|---|
| Buddy | `BuddyService` stores the buddy by **species** (`CreatureId`), not by instance | Locked when the offer would leave the player with no instance of a buddy species. Extra copies can be traded. |
| Incubating | `BreedingState.Incubations` holds the pre-rolled **result** (`CreatureId`, `Rarity`), never an inventory instance | Nothing in the inventory can be "incubating", so there is nothing to lock. If breeding ever consumes parent instances, add the lock in `validateOffer`. |
| Displayed | `CreatureDisplayService` derives the shown set from the inventory (rarest 6, or codex favorites by species) and has no list of "displayed instances" | Not locked (that would block the best creatures). `RefreshForPlayer` is called for both players after the trade. |
| Abducted | Moved out of `CreatureInventory` into `RaidState.AbductedCreatures` | Cannot be offered (not in the inventory); also checked defensively. |
| Raid guardian loadout | `PlayerDataService.ExecuteCreatureTrade` removes traded ids from the loadout | Allowed; shown as "Guardian" in the list. |

## Remotes (`ReplicatedStorage.TradeRemotes`)

Client to server (RemoteEvent): `RequestTrade(targetUserId)`,
`RespondTradeRequest(requestId, accept)`, `SetTradeOffer(tradeId, ids)`,
`SetTradeReady(tradeId, ready, revision)`, `ConfirmTrade(tradeId, revision)`,
`CancelTrade(tradeId | "request")`.
RemoteFunction: `GetTradeInfo()` returns the picker data and the tradable inventory.
Server to client (RemoteEvent): `OpenTradePicker`, `TradeRequestReceived`,
`TradeRequestClosed`, `TradeState`, `TradeClosed`, `TradeNotice`.
Every handler type-checks its arguments and is rate limited per player.

## Dock prompt

`TradeService` waits up to 30 s for `Workspace.Assets.Hub.TidalMarketHub`,
finds the model named `TradeDock` (`TradeConfig.DOCK_MODEL_NAME`) and parents a
`ProximityPrompt` named `TradeDockPrompt` to its `InteractionPoint` attachment
(fallback: `PrimaryPart`, then any part). The hub buildscript is not edited. If
the hub or the dock is missing it logs a warning and trading still works from
the menu.

## Hooks

- Output log: `[Trade] <id> COMPLETED: A (userId) gave [Creature(Rarity,id8)] <-> B ...`
  plus open / save lines and warnings.
- `GameEvents` `"TradeCompleted"` (player, `{ TradeId, PartnerUserId, Gave, Received }`),
  fired once per player. Used by:
  - `AchievementService`: "Fair Swap" (1 trade) and "Dock Regular" (10 trades,
    title), category "Social", based on `TradeState.TradesCompleted`.
  - `LeaderboardService`: marks the player dirty (the Rarest Collection score changes).

## Limits / open points

- DataStore has no cross-key transactions. Both players are saved at the same
  moment right after the swap, but a server crash between the two saves
  could still duplicate or lose a creature. `ForceSave` failures are logged.
- Players must be within 60 studs of each other to start, not necessarily at the dock.
- Not tested in Studio yet. Test with 2 clients: request, accept, offer,
  change an offer during the countdown (Ready must reset), walk away (cancel),
  reset a character (cancel), leave the game (cancel), set a creature as buddy
  and try to offer it, trade at level < 5.
