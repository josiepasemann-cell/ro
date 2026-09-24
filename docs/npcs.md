# Tidal Market Hub NPCs

Five stylized, non-humanoid sea-folk characters bring the "Tidal Market" hub
to life. Their 3D models are pure-geometry buildscripts
(`assets/models/npcs/*.lua`, same Command-Bar-runnable pattern as every other
asset in `assets/models/`), and a single small client script
(`src/client/NpcAmbientController.client.lua`) gives them cheap procedural
idle animation and speech bubbles. No `Humanoid`, no animation assets, no
server script required.

## Who stands where

| File | NpcId | Display name | Character | Stands at (`Interactable`) | Personality |
|---|---|---|---|---|---|
| `Shopkeeper.lua` | `Shopkeeper` | Shelly | Hermit crab merchant | `Shop` (ShopStand) | Cheerful, sales-y, points out deals |
| `EggKeeper.lua` | `EggKeeper` | Inky | Old glowing octopus | `Gacha` (GachaStation) | Wise, mysterious, hints at rare drops |
| `QuestGiver.lua` | `QuestGiver` | Captain Finn | Seahorse captain | `Quests` (QuestBoard) | Encouraging, captain-y, mission-focused |
| `Trader.lua` | `Trader` | Splash | Clownfish | `Trade` (TradeDock) | Friendly, reassures players trades are fair |
| `Guide.lua` | `Guide` | Bubbles | Jellyfish | Near spawn (`HubSpawn1`), `StandInteractable = "Spawn"` (marker only) | Welcoming, explains the basics |

All five build under `Workspace.Assets.Npcs.<NpcId>` and are idempotent
(re-running a script removes and rebuilds only that NPC).

## How placement works

Each buildscript finds its stand in `Workspace.Assets.Hub.TidalMarketHub` by
the stand's `Interactable` attribute (see `assets/models/README.md` "hub"
section and `assets/models/hub/TidalMarketHub.lua`), reads that stand's
`InteractionPoint` Attachment (the spot a `ProximityPrompt` fires from - see
`src/client/ShopUIController.client.lua` / `QuestUIController.client.lua`,
which attach their own prompts there and are **not** duplicated by these
scripts), and places the NPC a few studs to the side of that point (computed
in the attachment's own local space, so it's robust to future hub rotation
changes) so the NPC never blocks the prompt. Bubbles (no shop-style stand)
instead anchors off the hub's `HubSpawn1` `SpawnLocation`, pulled a few studs
inward toward the landmark.

If `TidalMarketHub` hasn't been built yet, every script falls back to a
fixed, documented offset from the hub's landmark origin
(`CFrame.new(-500, 2, -500)`, matching `TidalMarketHub.lua`'s
`ORIGIN`/`PLAZA_TOP_Y`) - see the "STAND ANCHOR LOGIC" header comment in
each `assets/models/npcs/*.lua` file for the exact numbers. Build the hub
first if you want NPCs perfectly aligned with the real stand geometry;
either way, re-running the NPC scripts after building the hub snaps them to
the correct spot.

## Model naming convention

- `Model.PrimaryPart = "Body"`.
- Attributes: `NpcId` (string, matches the table above), `DisplayName`
  (string, shown in the speech bubble), `StandInteractable` (string, matches
  the stand's `Interactable` value, or `"Spawn"` for Bubbles),
  `SpeechHeight` (number, studs above ground for the speech bubble).
- Movable named parts (direct children of the model, siblings of `Body`,
  **not** nested under `Head`): `Head`, `ArmL`, `ArmR` (claws/fins/tentacles
  depending on the character), `Eye1`, `Eye2`. `NpcAmbientController`
  captures each one's rest offset relative to the model's pivot once at
  registration time, then re-derives their live CFrame from that offset
  every frame - it never assumes a specific rig/parenting beyond "these five
  names exist directly under the model".
- Every other part (legs, extra tentacles, fins, hats, shell markings, etc.)
  is purely decorative and un-named for animation purposes; it still moves
  correctly because the whole-model bob/sway is applied rigidly via
  `Model:PivotTo`, which moves every descendant together.
- `CollectionService` tag `"NpcAmbient"` (added by every buildscript) is how
  the controller discovers NPCs - no hardcoded path, works from any folder.

## What the ambient controller does

`src/client/NpcAmbientController.client.lua` is a single `LocalScript`
(`StarterPlayer.StarterPlayerScripts`) that, per NPC:

1. **Bob + sway** - gentle whole-model float/rock via `Model:PivotTo` (cheap:
   one CFrame multiply, moves every part rigidly, no need to touch parts
   individually).
2. **Head turn** - blends `Head`'s yaw toward the nearest player within 20
   studs (clamped to a believable cone), back to neutral otherwise. Kept
   active even under reduced effects since it's cheap and helps readability.
3. **Arm/fin/tentacle wave** - subtle continuous idle sway on `ArmL`/`ArmR`,
   plus a bigger one-shot "wave" gesture triggered the moment a player walks
   into range (and occasionally at random even with nobody around).
4. **Blink** - `Eye1`/`Eye2` flicker to `Transparency = 1` briefly on a
   randomized interval (~3-7s).
5. **Speech bubbles** - a `BillboardGui` above each NPC (height from the
   `SpeechHeight` attribute) cycles through 4-6 short English lines every
   ~4.5s. Lines live in the `SPEECH_LINES` table inside the controller,
   keyed by `NpcId`.
6. **Distance LOD** - beyond 120 studs from the camera, an NPC's animation
   and speech bubble freeze entirely (re-checked every 0.5s) until the
   camera comes back into range.
7. **Reduced effects** (`UIKit.Settings.GetReducedEffects()`, see
   `docs/ui-kit.md`) - when enabled, bob/sway/blink/spontaneous-wave are
   skipped (the "idle pulsing"-style motion). Head-turn and speech bubble
   text cycling keep running since they're informational/cheap, not a
   flashy effect.

## Speech lines

All player-facing text is English per the game's current language.

- **Bubbles (Guide):** "Welcome to Tidal Market! I'll show you around." /
  "Check out the Shop for cool gear and daily deals!" / "The Quest Board has
  fresh tasks every day!" / "Portals lead to four wild zones. Level up to
  dive deeper!" / "Lost? I'm always floating right here." / "Have fun
  exploring Abyssara!"
- **Shelly (Shopkeeper):** "Welcome to my stand! Take a look around." /
  "Fresh decorations and gamepasses, just for you!" / "New deals every day,
  so come back often!" / "Psst... the Best Value card is totally worth it!"
  / "Earn Tide Coins by collecting Glow Spores!"
- **Inky (Egg Keeper):** "Mystery Eggs hide rare creatures inside..." /
  "I've guarded these eggs for many, many tides." / "The odds are always
  shown before you open one. Fair and square!" / "Some eggs glow brighter
  than others... wonder why?" / "Legendary creatures are rare, but not
  impossible!"
- **Captain Finn (Quest Giver):** "Ahoy, diver! I've got three tasks for you
  today." / "Finish quests to earn Tide Coins, Shards, and XP!" / "Fresh
  quests appear every day at midnight." / "Don't forget to claim your daily
  reward!" / "Together we can finish any mission, sailor's honor!"
- **Splash (Trader):** "Welcome to the Trade Dock! Trade safely with
  friends." / "Both sides must confirm, no funny business here!" / "Show off
  your rarest creatures and let's trade!" / "I make sure every trade is fair
  for both divers." / "Bring a friend and let's swap some creatures!"

## How to add a new NPC

1. Copy an existing `assets/models/npcs/*.lua` file as a starting point (it
   already has the stand-anchor lookup + fallback boilerplate).
2. Change `NPC_ID`, `DISPLAY_NAME`, `STAND_INTERACTABLE` (or write a
   spawn-based resolver like `Guide.lua` if it isn't tied to a stand),
   the side/forward offsets, and the fallback offset (compute it from
   `TidalMarketHub.lua`'s `STAND_RING_RADIUS`/stand position comment, or
   just eyeball a reasonable spot near the hub landmark).
3. Build the character out of plain, low-poly `Part`/`WedgePart` instances
   (no CSG needed - keep part counts phone-friendly, ~10-15 parts). Name the
   parts the animator should move `Head`, `ArmL`, `ArmR`, `Eye1`, `Eye2` and
   parent them directly to the model (siblings of `Body`), not nested under
   `Head`.
3. Set `model.PrimaryPart = Body`, the four attributes
   (`NpcId`/`DisplayName`/`StandInteractable`/`SpeechHeight`), and
   `CollectionService:AddTag(model, "NpcAmbient")`.
4. Run the script once (Studio Command Bar) - it builds under
   `Workspace.Assets.Npcs.<NpcId>`.
5. Add a `SPEECH_LINES` entry for the new `NpcId` in
   `src/client/NpcAmbientController.client.lua` (4-6 short English lines).
   No other code changes needed - the controller auto-discovers any model
   tagged `"NpcAmbient"`.
