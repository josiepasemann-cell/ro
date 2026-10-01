# Prestige ("Resurface")

GDD sections 3 and 6. Not tested in Studio yet.

## Rules

- **Eligible** when the player reached the Hadal Depths in the current run
  (`PlayerDataService.GetDeepestZone() >= 4`) or is level 45+
  (`PrestigeConfig.REQUIRED_ZONE` / `REQUIRED_LEVEL`).
  The zone is recorded by `ZoneProgressService` (zone tracking feature); without it, level 45 is the only working gate.
- **Blocked** while a raid runs, within 60 s of the last resurface, or while a
  finished Brood Pool egg is waiting (it would be lost).
- **Keeps**: creatures, Abyssal Shards, codex (and its income bonus), cosmetics,
  titles, achievements, abilities, gamepasses and purchases, all-time deepest zone.
- **Resets** (done by `PlayerDataService.ApplyAscend`): level and XP, Tide Coins
  (back to the starter amount), all buildings on all plots, running incubations,
  the current zone progress, the raid timer (next raid in 25 minutes, raids stay
  paused until level 8 again).

## Numbers (`src/shared/PrestigeConfig.lua`)

| Ascend | Bonus | Total after the last ascend of the tier |
|---|---|---|
| 1 - 9 | +10% each | x1.90 |
| 10 - 19 | +8% each | x2.70 |
| 20 - 29 | +6% each | x3.30 |
| 30+ | +4% each | |

The multiplier is derived from the ascend count every time, never added to the
old value. It scales passive idle income (`IdleIncomeService` already multiplies
`PlayerDataService.GetIncomeMultiplier`, online and offline). Flat rewards (raid
loot, quests) are not scaled, like the codex bonus.

Titles (`AddUnlockedTitle`): #1 Resurfaced, #3 Tide Turner, #5 Abyss Walker,
#10 Trench Veteran, #20 Leviathan's Friend, #30 Master of the Deep.
Abyssal Shards, once per ascend: 5 for #1, +1 per ascend, capped at 15, plus 10
extra on ascends that unlock a title. Achievements: "Back to the Surface" (1),
"Tide Master" (5), counted through the `Resurfaced` GameEvent.

## Flow and files

1. More drawer -> "Resurface" (`PrestigeUIController`, no hotkey on purpose).
   The panel lists what is kept and what resets, the next bonus, title and shards.
2. Dialog 1 -> `ArmResurface` (server checks eligibility and arms the player for 45 s)
   -> dialog 2 -> `RequestResurface` (consumes the armed state).
3. `PrestigeService.RequestResurface`: rate limited, re-checks everything, calls
   `ApplyAscend`, grants shards and title, destroys the placed models
   (`PlacementService.ClearPlayerBuildings`, both plots), swaps an open raid quest
   (`QuestService.RefreshAfterPrestige`), fires `GameEvents.Resurfaced`, sends the
   player back to plot 1, answers the client, then `ForceSave`.
4. HUD: `HUDServer` pushes the full state on `DataChanged "Ascend"`; the HUD level line
   shows "Resurfaced xN (xM.MM income)". The client fires the bridge event
   `PrestigeCompleted`, which makes the quest and raid UIs re-fetch their state.

Files: `src/shared/PrestigeConfig.lua`, `PrestigeRemotes.lua`,
`src/server/PrestigeService.lua`, `PrestigeServer.server.lua`,
`src/client/PrestigeUIController.client.lua`.

## Open points

- Leaderboards that use the player level will drop after a resurface.
- A player standing in a deeper zone is sent to plot 1 via `TravelService`; if the travel
  cooldown is active they stay where they are for a moment.
