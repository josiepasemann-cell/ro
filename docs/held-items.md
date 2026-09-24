# Held Items – Abyssara – Deep Tide Tycoon

As of: 2026-09-24. Reference: `docs/game-design-doc.md` Section 3 ("collecting
Glow Spores"), Section 8 (gacha eggs/creature models).

This document describes the server-authoritative "held item" system and —
especially important for other, already-running agent work — **exactly
where `GachaService`/`BreedingService`/`PlacementService` should hook in
later**, without their files having been touched for this feature itself.

## 1. Files involved

| File | Role |
|---|---|
| `src/shared/HeldItemConfig.lua` | Central tunables: carry poses, hold scale/offset per item kind, pickup/deposit tuning |
| `src/shared/HeldItemRemotes.lua` | `RequestDropHeld` (Client→Server), `HeldItemChanged` (Server→Client) |
| `src/server/HeldItemService.lua` | Authoritative core API: `HoldItem`/`DropHeld`/`GetHeld`/`ConsumeHeld` |
| `src/server/PickupSpawner.lua` | Glow Spore world pickups per plot, GlowBuoyStation deposit, cleanup on drop |
| `src/server/HeldItemServer.server.lua` | Bootstrap/wiring (remotes, join/leave) |
| `src/client/HeldItemClient.client.lua` | Minimal HUD, "Drop" action (G/touch/gamepad), glow effect |
| `assets/models/pickups/GlowSporePickup.lua` | Buildscript for the Glow Spore world model |

## 2. Public server API (`HeldItemService`)

```lua
local HeldItemService = require(ServerScriptService.HeldItemService)

-- Visibly brings an item into `player`'s right hand. If the player is
-- already holding something, it's automatically dropped first (DropHeld).
local success, instance = HeldItemService.HoldItem(player, itemKind, templateOrModel, {
    CarryPose = nil,       -- optional override, otherwise HeldItemConfig.GetCarryPose(itemKind)
    DisplayName = nil,     -- optional override, otherwise HeldItemConfig.GetDisplayName(itemKind)
    HoldScale = nil,       -- optional override, otherwise HeldItemConfig.GetHoldScale(itemKind)
    GripOffset = nil,      -- optional CFrame override, otherwise HeldItemConfig.GetGripOffset(itemKind)
    Reparent = false,      -- true = move `templateOrModel` DIRECTLY instead of cloning it
    DestroyOnDrop = false, -- true = DropHeld destroys the item instead of dropping it as a world pickup
})

-- Drops the currently held item (player action or cleanup).
-- Default: the item is placed in the world in front of the character,
-- `ItemDropped` fires (see below).
HeldItemService.DropHeld(player)

-- Read-only snapshot: { ItemKind, Model, DisplayName, CarryPose } | nil
HeldItemService.GetHeld(player)

-- Removes the held item WITHOUT a world drop (no ItemDropped event) -
-- for "consuming" it on a deposit/turn-in action. Returns (itemKind, model)
-- - the CALLER is then responsible for `model` (usually
-- `model:Destroy()`, AFTER the reward has been granted).
local itemKind, model = HeldItemService.ConsumeHeld(player)

-- BindableEvent signal: (player, model, itemKind, dropWorldCFrame).
-- Fires ONLY on DropHeld (not on ConsumeHeld). PickupSpawner already
-- subscribes to this for "GlowSpore".
HeldItemService.ItemDropped:Connect(function(player, model, itemKind, dropCFrame) ... end)
```

Item identity in both cases (cloning vs. `Reparent = true`):

- **Cloning (default):** `templateOrModel` stays untouched (e.g. a template
  from `ReplicatedStorage.AssetTemplates.*` or a gacha/breeding result
  model) - `HoldItem` clones it, the original stays reusable for further
  rolls/players afterward.
- **Reparent = true:** `templateOrModel` is an already-existing, one-off
  instance (e.g. a world pickup like in `PickupSpawner`), which moves
  directly into the hand instead of being duplicated.

## 3. `CarryPose` attribute (animation contract)

`HeldItemService` sets this on every `HoldItem`/`DropHeld`/`ConsumeHeld`:

```lua
character:SetAttribute("CarryPose", "OneHand" | "TwoHand" | nil)
```

The procedural animation system
(`src/shared/CharacterAnimation/ProceduralAnimator.lua`) already reads this
attribute itself (`self.Character:GetAttribute("CarryPose")`) and poses the
arms accordingly via `PoseLibrary.CarryOneHand()` /
`PoseLibrary.CarryTwoHand()`. This system doesn't need to do anything
further for that - a pure attribute contract, no direct coupling between
the modules.

Default mapping (`HeldItemConfig`, overridable via `opts.CarryPose`):

| ItemKind | CarryPose |
|---|---|
| `GlowSpore` | `OneHand` |
| `Egg` | `TwoHand` |
| `Creature` | `TwoHand` |

## 4. Attachment to the character (technical)

- Grip point: `Attachment "RightGripAttachment"` on `RightHand` (R15) or
  `Right Arm` (R6 fallback) - used if present (standard Roblox rigs mostly
  already come with this for tool equip), otherwise created automatically.
- Connection: `RigidConstraint` between `RightGripAttachment` (hand) and a
  newly created `Attachment "ItemGripAttachment"` on the `PrimaryPart` of
  the held item (offset from `HeldItemConfig.GetGripOffset`).
- Size: `Model:ScaleTo(HeldItemConfig.GetHoldScale(itemKind))` - scaling
  happens BEFORE attaching the `ItemGripAttachment`, so the configured
  offsets apply to the already-scaled hold size.
- Physics: all `BasePart`s of the item are set to `CanCollide = false`,
  `Massless = true`, `Anchored = false` - it affects neither player
  movement nor collides with other players/the world.
- `PrimaryPart` detection: uses `Model.PrimaryPart` if set, otherwise falls
  back to the naming convention from `assets/models/README.md`
  (`"Body"` for creatures, `"Shell"` for gacha eggs, `"Base"` for
  buildings/pickups).

## 5. Glow Spore world pickups (`PickupSpawner`)

- Periodically spawns (`HeldItemConfig.Pickup.SpawnCheckIntervalSeconds`,
  default 20s) up to `HeldItemConfig.Pickup.MaxPerPlot` (default 3) Glow
  Spore pickups, randomly distributed on each player's Habitat Plot base
  (performance: a hard per-plot cap, no global cap needed since it's
  bounded per player).
- Every pickup carries a `ProximityPrompt "PickupPrompt"` (`HoldDuration`
  short, `RequiresLineOfSight = false`) - works identically on PC (key),
  mobile (automatic touch button), and console (gamepad button), with no
  platform-specific code.
- The server validates both **ownership** (the `OwnerUserId` attribute must
  match the triggering player - only your own spores) and **distance**
  (an additional server-side measurement to the HumanoidRootPart,
  independent of `ProximityPrompt.MaxActivationDistance`) on trigger.
- The spore is picked up via `HeldItemService.HoldItem(player,
  "GlowSpore", pickupModel, { Reparent = true })`.
- Dropping it (`DropHeld`, e.g. the "G" key): `PickupSpawner` subscribes to
  `HeldItemService.ItemDropped` and automatically re-registers the item as
  a world pickup with a new `ProximityPrompt` on the player's plot.

## 6. GlowBuoyStation deposit (bonus Tide Coins)

- `PickupSpawner` watches each player's placed buildings
  (`PlotRegistry.GetBuildingsFolder`, NO changes to `PlacementService`) and
  attaches a `ProximityPrompt "DepositPrompt"` to every instance with
  `GetAttribute("BuildingId") == "GlowBuoyStation"`.
- Triggering it while holding a `GlowSpore`: the server re-validates
  distance, calls `HeldItemService.ConsumeHeld(player)`, destroys the
  consumed model, and grants
  `PlayerDataService.AddCurrency(player, "TideCoins",
  HeldItemConfig.Deposit.TideCoinsReward)` (default 25).
- `PlayerDataService` is read/called exclusively through its existing,
  public API here - the file itself was not modified.

## 7. Future callers (for the agents working in parallel)

This system deliberately provides a generic API. The following hook points
are prepared (`HeldItemConfig` already knows `Egg` and `Creature` as
`ItemKind`), but **not implemented themselves**, since the corresponding
files must not be touched per the task brief:

- **`GachaService.OpenEgg`** (`src/server/GachaService.lua`): after a
  Mystery Egg has been rolled and the player "picks up"/views it, this
  could be added there:
  ```lua
  local HeldItemService = require(ServerScriptService.HeldItemService)
  local eggTemplate = -- matching template from ReplicatedStorage.AssetTemplates
  HeldItemService.HoldItem(player, "Egg", eggTemplate)
  ```
  Note: per `assets/models/README.md`, the Mystery Egg models
  (`assets/models/gacha/MysteryEgg_*.lua`) are currently still pure
  buildscript outputs without ReplicatedStorage template promotion (the way
  `AssetTemplateSetup` does it for Terrain/Buildings/Enemies) - an
  analogous promotion for `gacha/` would be the prerequisite before
  `GachaService` can reference a reusable template model.
- **`BreedingService.RequestClaimBreeding`**
  (`src/server/BreedingService.lua`): after successfully claiming a
  fully hatched creature (`CreatureId`/`Rarity` already known, see the
  `BreedingIncubation` type in `PlayerDataService`):
  ```lua
  local HeldItemService = require(ServerScriptService.HeldItemService)
  local creatureTemplate = -- matching creature template (see assets/models/creatures/*.lua)
  HeldItemService.HoldItem(player, "Creature", creatureTemplate, {
      DisplayName = creatureData.CreatureName,
  })
  ```
- **`PlacementService`** needs no hookup - buildings aren't "held", they're
  placed directly.

In all cases: `HoldItem` automatically clones the given template (no
`Reparent`), the original stays untouched and reusable for further
players/rolls.

## 8. Client feedback (`HeldItemClient`)

- A minimal, isolated HUD (no dependency on the parallel-in-progress
  `src/shared/UIKit`) shows `"Holding: <Name> (G to drop)"` as soon as
  `HeldItemRemotes.HeldItemChanged` reports `Holding = true`.
- "Drop" action via `ContextActionService:BindAction(..., true,
  Enum.KeyCode.G, Enum.KeyCode.ButtonX)` - the third parameter
  (`createTouchButton = true`) automatically creates a touch button on
  mobile devices, no extra code needed.
- A glow effect (`PointLight` + `ParticleEmitter`) is attached via the
  `CollectionService` tag `"HeldItem"` to EVERY visibly held item (including
  other players'), independent of the HUD/drop action (which only apply to
  the local player).

## 9. Security (no client trust)

- `HeldItemService` is a purely server-internal API (no `RemoteFunction`
  for the client) - the client can only trigger `RequestDropHeld` for its
  OWN character.
- `PickupSpawner` re-validates ownership (`OwnerUserId`) and distance
  server-side on every `ProximityPrompt.Triggered` trigger, independent of
  the client-visible prompt parameters.
- All currency grants run exclusively through the existing, vetted
  `PlayerDataService.AddCurrency` API.
