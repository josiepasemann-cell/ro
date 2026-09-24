# Character Animations – Abyssara: Deep Tide Tycoon

This document describes the animation system for player characters:
walking, running, jumping/falling/landing, idle, and carry poses.

## Why procedural instead of uploaded animations?

Classic Roblox animations need an animation asset ID **uploaded** in
Studio. Pure code cannot generate a live-usable animation ID —
`KeyframeSequenceProvider:RegisterKeyframeSequence` only returns a temporary
ID that does **not** work in a published game. That's why this system uses
**procedural animation** by default: each client sets the `Motor6D.C0`
values of every visible character's joints directly, per frame, based on
replicated data (Humanoid state, velocity, position). `Motor6D.Transform`/
`C0` doesn't replicate over the network — so **every client animates every
character it sees itself** (including itself). The result looks nearly
identical for all players, since it's based on the same replicated movement
data.

## Files

- `src/shared/CharacterAnimation/` → `ReplicatedStorage.CharacterAnimation`
  - `AnimationConfig.lua` – all the tunables (speeds, amplitudes,
    LOD distances, FX, override table)
  - `Spring.lua` – generic critically-damped spring for smooth blending
  - `PoseLibrary.lua` – pure pose functions (idle, locomotion, jump/fall/land, carry)
  - `RigJoints.lua` – finds Motor6Ds for R15 (full) and R6 (simplified)
  - `ProceduralAnimator.lua` – one instance per character, applies poses per frame
  - `EffectsPool.lua` – pooled dust particles for footsteps/landings
- `src/client/CharacterAnimator.client.lua` → `StarterPlayer.StarterPlayerScripts`
  Orchestrates animator instances, LOD, sprint input (keyboard/touch/gamepad)
- `src/server/CharacterSetup.server.lua` → `ServerScriptService`
  Enforces R15, removes the default `Animate` script, validates sprint
  server-side (WalkSpeed is set **only** by the server)

## Adding your own real animations (optional)

If you later want to use hand-made or purchased animations instead of the
procedural movement:

1. Create the animation in the **Roblox Animation Editor** (Studio: Avatar →
   Animation Editor) on the R15 rig, or use a purchased/marketplace
   animation.
2. Click **Publish** in the editor → Roblox assigns a real, permanent asset
   ID (format `123456789`).
3. In `src/shared/CharacterAnimation/AnimationConfig.lua`, enter it in the
   matching slot under `AnimationOverrides`, e.g.:

   ```lua
   AnimationConfig.AnimationOverrides = {
       Idle = "rbxassetid://123456789",
       Walk = "rbxassetid://234567890",
       Run = "",   -- empty = stays procedural
       Jump = "",
       Fall = "",
       Land = "",
   }
   ```

4. Save, test via Rojo sync/Play. For every slot that's set,
   `ProceduralAnimator` automatically loads an `AnimationTrack` via
   `Animator:LoadAnimation()` and plays it in the matching state; the
   procedural pose for exactly that slot is disabled. Unset slots stay
   procedural.

**Note/limitation:** if only individual slots are overridden (e.g. only
`Walk`), transitions to other (still procedural) states can show slightly
visible jumps, since both systems drive the same joints. For a consistent
look, it's recommended to override either **all** six slots or **none**.

## Rig support

- **R15 (main target):** full animation with shoulder/elbow/wrist and
  hip/knee/ankle — natural leg swing, arm swing, hip rotation.
- **R6:** simplified version (shoulder/hip only, since R6 has no
  elbow/knee joints). `CharacterSetup.server.lua` calls
  `Players:SetDefaultRigType(Enum.HumanoidRigType.R15)` to force newly
  loaded avatars to R15 where possible. If that fails (e.g. the API isn't
  available in the Studio version in use), `RigJoints.lua` automatically
  detects R6 and the client uses the simplified version — no crash, just
  less detail.

## Sprint input

- **PC:** hold left/right Shift
- **Mobile:** automatically generated touch button (via
  `ContextActionService:BindAction(..., true, ...)`)
- **Gamepad:** L3 (left stick click)

The client only sends a **boolean** (`true`/`false`) over `SprintRemote`.
The actual `WalkSpeed` is set exclusively server-side in
`CharacterSetup.server.lua` and capped at `34` — the client cannot force an
arbitrary speed. There is also request throttling (cooldown) to prevent
remote spam.

## Carry poses (CarryPose)

An external holding/inventory system can set the character attribute
`CarryPose`:

- `"OneHand"` – right arm holds an item in front of the body
- `"TwoHand"` – both arms hold an item in front of the body
- `nil` / not set – normal arm animation

```lua
character:SetAttribute("CarryPose", "OneHand")
```

The legs keep animating normally in every case (walking/running/jumping);
only the arms blend smoothly (via a spring, no hard switch) into the carry
pose.

## Underwater flair

`AnimationConfig.UnderwaterFlairEnabled` (default: `true`) adds a subtle
float to idle and movement, plus a slight "drag" factor
(`UnderwaterDragFactor`), matching the Deep Tide setting. Set it to `false`
to get completely "dry" standard movement.

## Performance measures

- **Distance LOD** (`CharacterAnimator.client.lua`, recalculated every
  0.25s):
  - `Full` (≤ 45 studs from camera): all joints, full level of detail, FX active
  - `Reduced` (≤ 110 studs): only main joints (shoulder/hip/spine/
    head), elbow/knee/wrist/ankle are skipped, no FX
  - `Off` (further away): no Motor6D updates (character stays in its
    last pose, costs practically nothing)
- **Phase locked to distance traveled instead of a fixed frequency** —
  prevents moonwalking/sliding regardless of framerate fluctuations.
- **Pooled FX system** (`EffectsPool.lua`): a fixed number (`FXPoolSize`,
  default 28) of reused particle emitters instead of `Instance.new` per
  effect — important for mobile.
- **Physics-synced `RunService.PreSimulation`** instead of `RenderStepped`,
  so Motor6D updates are applied consistently before the next
  simulation/render frame, without blocking the default Animator.
- All connections (`Connections`) are cleanly disconnected on character
  removal/respawn (`cleanupCharacter` in `CharacterAnimator.client.lua`,
  `ProceduralAnimator:Destroy()`), to avoid memory/connection leaks.

## Placeholders you may want to customize

- `EffectsPool.lua`: `emitter.Texture` currently uses a built-in Roblox
  particle texture (`rbxasset://textures/particles/smoke_main.dds`) as a
  generic sand/dust look. For a more custom look, you can enter your own
  uploaded texture ID here.
- `AnimationConfig.AnimationOverrides`: see the "Adding your own real
  animations" section above.
