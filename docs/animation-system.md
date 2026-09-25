# 3D Model Animation System – Abyssara: Deep Tide Tycoon

This document describes how *non-player* 3D models (plot display
creatures, raid enemies, raid towers, buddies) move and animate smoothly.
For **player character** procedural animation (walking, jumping, carry
poses) see `docs/animations.md` instead — that system is unrelated and was
already working correctly.

## The problem this system solves

Two server systems moved fully `Anchored` models every tick via
`Model:PivotTo()`:

- `CreatureDisplayService` moved plot display creatures every
  `WANDER_TICK_SECONDS` (0.2s / 5 Hz).
- `RaidService` moved raid enemies every `RaidConfig.RAID_TICK_SECONDS`
  (0.1s / 10 Hz).

Roblox does **not** interpolate `CFrame` changes of anchored parts on the
client — every replicated `PivotTo()` produced a visible "teleport" step,
so both systems looked like they were stuttering/ticking instead of
smoothly moving.

## Architecture: server stays authoritative, client renders

The server remains the single source of truth for *game logic*:

- Which creatures are displayed on a plot, and their wander target
  selection/arrival timing (`CreatureDisplayService`).
- Enemy path progress, HP, tower targeting/damage, breach detection, wave
  progression, win/loss (`RaidService`).

What changed: the server **no longer calls `Model:PivotTo()` on a
recurring tick**. Instead it publishes its authoritative *logical*
position as a `Vector3` **attribute** on the model:

```
Model:SetAttribute("TargetPosition", <Vector3>)
```

(see `src/shared/ModelAnimation/ModelAnimationTags.lua` for the exact tag/
attribute name constants shared between server and client).

Every client runs **one** shared `RunService.PreSimulation` loop
(`src/client/ModelAnimator.client.lua`) that discovers tagged models via
`CollectionService` and *chases* `TargetPosition` every frame with
exponential smoothing (`1 - exp(-rate * dt)`, identical pattern to the
already-battle-tested `BuddyClient.client.lua` follow logic) plus a hard
snap once the gap exceeds `SNAP_DISTANCE_STUDS` (covers respawns/large
server corrections). This is dead-reckoning-by-continuous-chase rather
than fixed-duration tweening — it self-corrects every time a new
`TargetPosition` arrives (every 0.1–0.2s) without needing exact
interpolation-window math, and multiple clients watching the same model
(e.g. another player's plot) all chase the same server value, so they stay
visually consistent with each other.

Idle motion (bob, gentle roll, fin/tentacle/wing sway) is layered on top
*entirely client-side* via `src/shared/ModelAnimation/IdleSway.lua` — it
never needs to be synchronized across clients since it's purely cosmetic.

### Why this is not a client-trust violation

Display creatures and raid enemy *positions* have no gameplay weight of
their own — no collision, no proximity prompts, no server-side hit
detection reads the client's rendered position. The server still decides
every value that matters (which creature, HP, damage, wave state, win/
loss) and only ever publishes attributes; the client cannot influence
`TargetPosition` (attributes are set server-side only, `SetAttribute` from
an untrusted client on a server-owned instance has no effect on server
logic since nothing server-side reads it back).

For raid combat, **all server-side distance/targeting math uses the
server's own logical position**, not the model's actual (now mostly
static) `CFrame`: `RaidService`'s `EnemyRuntime.Position: Vector3` field is
the one and only source of truth for tower targeting range checks,
CoralBarrier slow-zone checks, and center-reach (breach) detection.
`Model:GetPivot()` is intentionally no longer read anywhere in that hot
path.

## Per-system breakdown

### Display creatures (`CreatureDisplayService` + `ModelAnimator`)

- Server still owns wander target selection at `WANDER_TICK_SECONDS`
  cadence — on arrival it picks a new random point in the plot's wander
  radius (unchanged logic), but now just writes `TargetPosition`
  (base position, no bob baked in) instead of moving the model.
- Client chases `TargetPosition`, derives facing (yaw) from its own chase
  velocity, and layers `IdleSway` bob + named-part sway (`TailFin`,
  `DorsalFin`, `SideFin`, `Wing`, `Tentacle1..N`, `SpineSpike`, `Horn`,
  etc. — matched by name prefix, see `IdleSway.lua`) on top.
- Tag: `ModelAnimationTags.DISPLAY_CREATURE` ("DisplayCreatureWander").

### Raid enemies (`RaidService` + `ModelAnimator`)

- `EnemyRuntime.Position` is updated every combat tick (unchanged 10 Hz
  cadence/logic for the actual movement math) and published as
  `TargetPosition`; the client chases it at a **faster** catch-up rate
  than display creatures (combat needs tighter positional fidelity).
- Spawn: `ATTR_SPAWNED_AT` (server time via `Workspace:GetServerTimeNow()`)
  drives a short client-side fade-in (`RaidConfig.SPAWN_FX_SECONDS`)
  instead of an instant pop-in.
- Death/breach: instead of destroying the model the instant `CurrentHP<=0`
  or the enemy reaches the plot center (both gameplay events still fire
  immediately, unchanged), the server now calls `scheduleDeathDestroy()`
  which sets `ATTR_DYING_AT` and delays the actual `:Destroy()` by
  `RaidConfig.DEATH_FX_SECONDS`. The client fades + shrinks the model
  during that grace window (dissolve instead of pop).
- CoralBarrier slow zones set `ATTR_SLOWED = true` while a speed
  multiplier `< 1` applies — the client plays a visibly slower/heavier
  idle wobble while that attribute is set (movement itself was already
  slower server-side; this only affects the cosmetic layer).
- Bosses (existing `IsBoss` attribute) get a heavier bob amplitude.
- Tag: `ModelAnimationTags.RAID_ENEMY` ("RaidEnemyMotion").

### Raid towers

- `RaidService.collectTowerRuntimes` tags every player-owned tower with
  `ModelAnimationTags.RAID_TOWER` ("RaidTower") — idempotent, re-applied
  every raid start.
- `ModelAnimator` gives every tagged tower a continuous, cheap idle
  `PointLight` brightness pulse (found via the `MuzzlePoint` attachment
  documented in `assets/models/README.md`, with the historical
  `LureOrb`/`SlowPulseCore`/`EelHead` part names as fallback — mirrors
  `RaidService.getTowerOriginPosition`'s own fallback order).
- `RaidRemotes.EnemyHit` now also carries a `Tower: Model` field (Instance
  references replicate fine through `RemoteEvent:FireClient`). On receipt,
  `ModelAnimator` triggers a short muzzle recoil (small local offset) +
  brightness flash on that specific tower — purely additive to the
  existing payload, `RaidUIController`'s existing `EnemyHit` handler
  (tracer beam) is unaffected.
- `ElectricEelTrap`'s existing server-side `flashChargeCore` (a plain
  property set + `task.delay`, not a `TweenService` tween) was left as-is
  — it is cheap and already correct; only the *movement* stutter was worth
  moving off the server in this pass.

### Buddies

`BuddyClient.client.lua` was already fully client-driven and smooth
(exponential chase + snap, identical pattern this system now reuses
elsewhere) — left untouched. `IdleSway` is written so a future pass can
plug it into `BuddyClient` for fin/tentacle sway consistency without
touching the follow logic; not done in this pass to avoid destabilizing
an already-solid, tested system.

## Files

- `src/shared/ModelAnimation/ModelAnimationTags.lua` — tag/attribute name
  constants shared by every publisher and the renderer.
- `src/shared/ModelAnimation/IdleSway.lua` — reusable idle bob/roll/part-
  sway module (pure function API, no internal loop).
- `src/client/ModelAnimator.client.lua` — the single render loop: chase/
  lerp for display creatures + raid enemies, spawn/death FX, tower idle
  pulse + muzzle flash/recoil. Respects `UIKit.Settings.ShouldSkipFX()`
  and uses distance-based LOD (Full/Reduced/Off update throttling,
  `RunService.PreSimulation`).
- `src/server/CreatureDisplayService.lua` — publishes `TargetPosition`
  instead of calling `PivotTo` in its wander tick.
- `src/server/RaidService.lua` — publishes `TargetPosition`/
  `SpawnedAt`/`DyingAt`/`Slowed`, tags enemies + towers, tracks
  `EnemyRuntime.Position` as the sole logical-position source for combat
  math.
- `src/shared/RaidConfig.lua` — added `DEATH_FX_SECONDS`,
  `SPAWN_FX_SECONDS` (shared constants, server sets the timestamps, client
  reads the durations).

## Known remaining limits (not covered by this pass)

- Pickups (Glow Spores, Sunken Chest, Frozen Spore thaw), building
  placement/upgrade/sell pop animations, and mystery-egg idle wobble at
  the hub were **not** converted in this pass — they still use their
  previous (already server-file-owned) spawn/despawn behavior. They are
  good candidates for a follow-up pass using the same `IdleSway` module
  and the same tag-discovery pattern established here.
- Held-item weld/CarryPose follow was verified conceptually via
  `CharacterAnimator`/`PoseLibrary` but not re-tested end-to-end in this
  pass.
- `IdleSway` is not yet wired into `BuddyClient.client.lua` (see above).
