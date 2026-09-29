# Playthrough Review: Abyssara - Deep Tide Tycoon

Date: 2026-09-29. Method: the whole player journey was traced by reading the
code (the game has never run in Roblox Studio). Every changed Luau file was
compiled with `luau-compile`. The whole `src/` tree was type-checked with
`luau-lsp` before and after; the set of reported diagnostics is identical
(only pre-existing noise about string-literal unions, cyclic `require` notes
and unused locals remains). Ratings are 1-10 and are **estimates from code
reading**, not from play testing.

Legend: A = works correctly, B = fun / clarity for a kid (8-14),
C = usability on phone / tablet / PC / console.

Overall: **before about 4.5 / 10, after about 7 / 10** (the jump is mostly the
first-join soft-lock, the plot streaming problem and the free-purchase
exploits; the rest is polish). Remaining risk is what only Studio can show.

## 1. Journey table (before -> after)

| # | Step | A | B | C | Notes |
|---|------|---|---|---|-------|
| 1 | First join, data load | 8 -> 9 | 7 | 8 | Solid session-lock + retry design. Fixed an auto-save race that could re-lock a released session. |
| 2 | Spawn at the hub | 7 | 7 | 8 | Fallback spawn exists if the hub was never built. Unchanged. |
| 3 | Onboarding / tutorial | 7 -> 8 | 6 -> 8 | 8 | Text now states the 150 starting coins, the Glow Buoy Station, Pick Up and Deposit. Still skippable, 6 cards. |
| 4 | Travel to own plot | 5 -> 8 | 7 -> 8 | 8 | Plot #1 used to sit in the middle of the four zone chunks; ray-cast ignored the plot; plot never streamed to the client. Menu now closes after travel. |
| 5 | First building | 2 -> 8 | 4 -> 8 | 6 -> 8 | **Soft-lock**: 0 coins vs 150 cost. Build mode now sends hub players to the plot, preselects a free field on touch / gamepad, shows kid-friendly failure text. |
| 6 | Glow Spore pickup and deposit | 6 -> 8 | 6 -> 8 | 8 | Deposit prompt appeared only on the next 20 s tick, and was lost when a station was upgraded. Now attached instantly. Deposit gives a little XP. |
| 7 | Idle income, HUD | 7 -> 9 | 7 | 8 | HUD showed 0/min after building until the next tick. Offline-income vs online-tick race fixed. HUD sync retries. |
| 8 | Breeding | 7 -> 8 | 7 -> 8 | 6 -> 7 | Raw reason codes replaced; pool status re-synced after layout restore; free "instant complete" exploit closed. Console uses the overview panel (ClickDetector does not work with a gamepad). |
| 9 | Mystery Egg at the hub | 6 -> 8 | 7 | 4 -> 8 | Was ClickDetector-only (no gamepad) and lost the click if the Shell part streamed late. Added a local ProximityPrompt and wait for the Shell. |
| 10 | Codex / display / buddy | 8 | 7 | 7 | Server validation is good. No change. |
| 11 | Quests, daily reward, achievements | 7 -> 8 | 7 | 7 | "Survive a Raid" quest could not be finished before raids were possible. Daily reward logic (double-claim guard, UTC streak) is fine. |
| 12 | Level ups, zone unlocks, zone travel | 6 -> 8 | 7 | 8 | Midnight / Hadal cards said "Coming soon" although the server allows travel. |
| 13 | Trench Raids | 6 -> 8 | 4 -> 7 | 7 | New players lost a creature after 25 min with no way to defend (tower unlocks at level 8). Raids now start only once the tower is unlocked. Free "rescue token" exploit closed. |
| 14 | Building upgrades | 8 | 7 | 7 | No change (upgrade also re-attaches deposit prompt now). |
| 15 | Live events (12 h) | 7 -> 8 | 8 | 7 | Event lighting could be overwritten by WorldSetup for up to 12 h; decoration could be bought twice. |
| 16 | Shop / monetization / abilities | 5 -> 8 | 6 -> 7 | 7 | Instant Hatch and Rescue Token could never work from the shop (always "MissingTarget"). Server now picks the target. All product IDs are still 0. |
| 17 | Leaderboards | 7 -> 8 | 7 | 7 | Final score is written on leave; fallback name was German. |
| 18 | Leave and rejoin | 8 -> 9 | 8 | - | Persistence, session lock and offline income are sound after the fixes. |

## 2. Issues found

Severity: **Critical** = blocks progress or lets players get paid content free;
**High** = broken feature or clear exploit-like flaw; **Medium** = confusing /
economy / robustness; **Low** = polish.

### Fixed

| Sev | Where | Problem | Change |
|-----|-------|---------|--------|
| Critical | `src/server/PlayerDataService.lua:529` | New players had 0 Tide Coins, first building costs 150 and spores can only be deposited at a station. Hard soft-lock. | Starting balance 150 (exactly one Glow Buoy Station). |
| Critical | `src/server/BreedingServer.server.lua:49` | `RequestInstantCompleteBreeding` let **any client** finish a breeding for free (paid dev product). | Remote now only answers `PurchaseRequired`. The effect stays in `ProcessReceipt`. |
| Critical | `src/server/RaidServer.server.lua:62` | `RequestRescueWithToken` let any client rescue an abducted creature for free (paid dev product). | Same fix. |
| Critical | `src/server/PlotRegistry.lua:53,128` | Plot #1 at (0,0,0) was inside the four zone chunks (radius about 170). With StreamingEnabled (checklist step) the far-away plot never replicated to the owner, so build mode / brood UI found "no plot". | Grid origin moved to (1000,1000); plot uses `PersistentPerPlayer` + `AddPersistentPlayer`. Client waits for the plot without a hard timeout (`PlacementPreviewController`, `BreedingUIController`). |
| High | `src/server/TravelService.lua:132` | Travel-to-plot ray excluded `PlayerPlots`, so it never hit the own plot. | New `landOnPlots` flag for the plot destination. |
| High | `src/server/PickupSpawner.lua:820` | Deposit prompt only attached on the 20 s spawn tick, and lost when a station model was replaced by an upgrade. | `Buildings.ChildAdded` re-attaches immediately. |
| High | `src/server/IdleIncomeService.lua:95` | An online tick between "data loaded" and the offline-progress grant could reset `LastIncomeAt` and swallow up to 4 h of offline income. | `offlineSettled` gate. |
| High | `src/server/PlayerDataService.lua:779` | An auto-save that ran after the leave-save could re-set the session lock, so a quick rejoin was kicked with "SessionLocked". | Auto-save is skipped when the player's cache is gone. |
| High | `src/server/RaidService.lua:448` | First raid after 25 min against a player who cannot build towers yet = guaranteed loss + abducted creature. | `raidsAllowedFor` (level >= AnglerfishTower unlock) for live and offline raids. |
| High | `src/server/MonetizationService.lua:419` | Shop "Buy" for Instant Hatch / Rescue Token always failed (`MissingTarget`) because no screen supplies a target. | Server picks the target from the player's own data. Shop note text updated. |
| High | `src/client/GachaOpenClient.client.lua:101` | Egg opening was ClickDetector-only (no gamepad) and skipped eggs whose Shell streamed in late. | Local ProximityPrompt + `WaitForChild("Shell")`. |
| Medium | `src/server/QuestService.lua:87` | "Survive a Raid" daily quest impossible before raids exist. | Excluded until the tower is unlocked. |
| Medium | `src/server/HUDServer.server.lua:108` | HUD income per minute stale after building / upgrading (coins are charged before the building exists). | Extra push on `BuildingPlaced` / `BuildingUpgraded`. |
| Medium | `src/server/PlacementService.lua:309` | A very early place request could race `RestorePlayerLayout` (which resets the occupancy tables) and orphan a building. | Reject until the layout is restored. |
| Medium | `src/server/LiveEventService.lua:655` | WorldSetup (no ordering guarantee) could overwrite the event lighting for the whole 12 h slot. | Re-apply the current event lighting 3 s after start. |
| Medium | `src/server/LiveEventService.lua:822` | Event decoration could be bought repeatedly. | `AlreadyOwned` check (+ client text). |
| Medium | `src/server/LeaderboardService.lua:448,159` | Score changes since the last 90 s tick lost on leave; German fallback name "Spieler_...". | Final write on leave; "Player_...". |
| Medium | `src/shared/ProgressionConfig.lua:119` | The core loop of the first minutes (spores) gave no XP. | `SporeDelivered = 4` XP, awarded in `PickupSpawner`. |
| Medium | `src/client/PlacementPreviewController.client.lua:486` | Build mode from the hub showed nothing; touch / gamepad had no target field. Raw codes ("InsufficientFunds") shown to kids. | Auto-travel to plot, preselect a free field, friendly texts. Same for `BreedingUIController`. |
| Low | `src/client/HUDController.client.lua` | Single initial sync attempt. | Up to 5 attempts. |
| Low | `src/client/TravelUIController.client.lua` | Zones 3 / 4 shown as "Coming soon"; menu stayed open after travel. | Flags corrected, panel closes on success. |
| Low | `src/client/OnboardingController.client.lua` | Tutorial did not name the station / buttons. | Text updated. |
| Low | `src/client/BreedingUIController.client.lua` | Statuses of restored Brood Pools only synced once at start (possibly empty). | Re-sync when a Brood Pool appears. |

### Checked and found OK (no change)

- Every `*Remotes` module: each RemoteEvent / RemoteFunction has a server
  handler and a client user with matching names and argument order
  (checked by script + reading the payload shapes on the main flows).
  `RequestInstantCompleteBreeding` / `RequestRescueWithToken` are the only
  remotes that had no client user (see the exploits above).
- All `require` paths resolve in the Rojo tree (LSP reports no missing module).
  Cyclic-require notes are the intended lazy requires inside function bodies.
- Player-facing text: no German strings found (only code comments are German).
- Daily reward (double-claim guard set before any yield), Codex zone reward,
  cosmetics purchase, receipt idempotency, Studio-only simulation gate.
- Mobile: touch tap targets in build mode, sprint / drop use `ContextActionService`
  touch buttons, menu bar scrolls horizontally.

## 3. Economy notes (with the new starter coins)

- Start 150 -> Glow Buoy Station (150). Then about 25 coins per spore
  (1 spore per 20 s, max 3 on the plot) plus 15 / min passive.
- Brood Pool 250, feed 100, 8 min hatch. Mystery Egg 350 (about 5-6 min of
  spore runs). Duplicate refunds are lower than the egg price (good sink).
- XP to level 2 is 120, to level 10 about 1500. Sources now: build 15, spore 4,
  egg 25, quest 20, breeding 40, raid 60. Level 10 (zone unlock) needs
  roughly 2-3 h of active play; that is slower than the GDD "5-10 min per
  unlock" for the early levels. **Needs a human decision** (see section 4).

## 4. Remaining recommendations (need a human or Studio)

1. **Run it in Studio first.** Highest-risk items: `PersistentPerPlayer`
   plot streaming (`Model:AddPersistentPlayer`, wrapped in `pcall`), plot
   position (1000,1000) vs terrain / void, hub spawn, prompts attached to
   streamed hub models, ProximityPrompt on the egg on phone / gamepad.
2. **All sounds are empty** (`UIKit/SoundConfig.lua`): the game is silent.
   Feedback is visual only (toasts, screen flash). Needs licensed asset IDs.
3. **All product / gamepass IDs are 0** (`ShopConfig`): every Robux item shows
   "Coming soon". Fill in before launch (`docs/monetization-setup.md`).
   Paid random item (Mystery Egg) policy gating exists but needs a real test.
4. **XP pacing**: consider more early XP (first building, first egg, first
   codex entry) or a lower early curve (`ProgressionConfig.BASE_XP_STEP`).
5. **Plot has no floor around it**: walking off the hex platform drops the
   player until respawn at the hub. Consider a kill-plane message or an
   invisible boundary (needs the plot model, which is owned by another process).
6. **Spore Magnet gamepass** deposits coins without the new spore XP and
   without the deposit sound / toast; add parity in `AbilityService.collectSporeForMagnet`.
7. **Twelve menu buttons** in one scrolling bar is a lot for a phone. Consider
   grouping (Collections: Codex / Achievements / Leaderboard) after play testing.
8. **Raids while away from the plot**: the fight runs on the plot; a player in
   the hub only gets the result toast. Consider a "Raid started - go defend!"
   prompt with a travel button.
9. **Zone travel is only a teleport**: zones have terrain but no zone-specific
   gameplay in the code (only income multiplier and raid scaling).
10. Old docs still mention the plot grid starting at (0,0,0)
    (`assets/models/hub/TidalMarketHub.lua` header, `docs/`); assets were not
    touched by request, update them together with the next asset pass.
11. Lock cost check: the second Brood Pool at level 6 and Advanced pool at
    level 25 have no in-game hint in the build cards beyond the lock text.
