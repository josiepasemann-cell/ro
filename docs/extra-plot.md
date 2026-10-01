# Extra Habitat Plot (second plot per player)

ShopConfig key `ExtraPlot` (199 Robux). Owners get a second, independent
Habitat Plot right next to their first one. Not tested in Studio yet.

## How it works

| Part | What changed |
|---|---|
| `src/server/PlotRegistry.lua` | Each player gets a pair of grid columns (slot pair). Plot 1 = left column (named `<UserId>`, the same as before), plot 2 = right column (named `<UserId>_2`, +200 studs in X). The grid still starts at (1000, 0, 1000); a row now holds 5 players (10 columns). Every getter takes an optional `plotIndex` (nil = 1), so all old callers keep working on plot 1. Both plots are `PersistentPerPlayer` for the owner. Player attribute `PlotCount` (0/1/2) is set for the client UI. |
| `src/server/PlacementServer.server.lua` | Creates plot 2 on join for owners (before the layout restore) and when `MonetizationService.GamepassOwned` fires for `ExtraPlot` (purchase mid-session, Studio simulation). Passes the plot index of the place remote to `PlacementService`. |
| `src/server/PlacementService.lua` | `RequestPlace(player, buildingId, fieldIndex, rotationY, plotIndex)`: the plot index is validated (1 or 2, nil = 1, anything else `InvalidPlot`) and the plot must exist (`NoPlot` for non-owners). Field validation and occupancy are per plot. `HabitatPlacement.PlotIndex` is stored as nil for plot 1 (old saves unchanged) and 2 for plot 2. Restore is per plot and idempotent. |
| `src/server/MonetizationService.lua` | New `GamepassOwned` signal `(player, key)`; Player attribute `OwnsExtraPlot`. The old "placeholder" attribute and `ShopConfig.EXTRA_PLOT_PLACEHOLDER` are gone. |
| `src/server/TravelService.lua` / `TravelRemotes` | `RequestTravelToPlot(plotIndex?)`. The hub PlotGate still goes to plot 1. |
| `src/client/PlacementPreviewController.client.lua` | A "Plot 1 / Plot 2" card at the start of the build bar (only shown with 2 plots; key `5`, gamepad D-pad up). Switching reloads the build fields and travels there if far away. The place request carries the plot index. |
| `src/client/TravelUIController.client.lua` | A "Reef Plot 2" destination card (only with 2 plots). |
| `src/client/BreedingUIController.client.lua` | Watches the buildings folder of plot 2 as well, so Brood Pools there work. |
| `src/server/PickupSpawner.lua` | Glow Buoy deposit prompts are attached on both plots. |

## What works on plot 2 and what does not

- Income, breeding, upgrades, selling: yes (they read the whole habitat layout).
- Brood Pool limit (level based) counts both plots together.
- Raids: only plot 1 is attacked and only plot 1 towers defend. Plot 2 is a raid-free
  "safe" plot: `PlacementService.RequestPlace` rejects defense buildings (anything with
  `RaidConfig.TOWER_STATS`: AnglerfishTower, CoralBarrier, ElectricEelTrap) on plot 2 with
  Reason `DefenseOnMainPlot`, and the build bar shows "Plot 2 is a safe plot with no
  raids. Build towers on Plot 1!". Guardians and co-op raids also only use plot 1.
- Creature display and spore spawning: plot 1 only.

## Test plan (Studio)

1. Create the gamepass, or use the Studio-only simulated purchase in the shop.
2. Join: with the pass there are two plots side by side; `Player:GetAttribute("PlotCount") == 2`.
3. Build mode: pick Plot 2, place a building, rejoin: it is restored on plot 2.
4. Buy the pass mid-session: plot 2 appears at once, no rejoin needed.
5. Without the pass, fire `RequestPlaceBuilding` with plotIndex 2: expect `NoPlot`.
6. Leave while the join is still loading: no leftover plots in `Workspace.PlayerPlots`.
