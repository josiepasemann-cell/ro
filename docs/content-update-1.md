# Content Update 1: **Abyssara – Deep Tide Tycoon**

*Status: 2026-09-24 · Design document for the next content update, building on
`docs/game-design-doc.md` (v1.0) and closing the gaps listed in
`docs/release-checklist.md` section 7 ("Bekannte Lücken"): Zone 3/4 content,
real raid enemy models, missing tower types, and (new) a rotating live-event
system. This document is written for two downstream agents: a 3D-model agent
(sections 2–4, 7a) and a Luau code agent (sections 1–6, 7b). Be literal about
names and numbers — they are contracts, not suggestions.*

---

## 0. Research note: how live events rotate in comparable Roblox games

*Grow a Garden* cycles **weather events** every 5–10 minutes, server-synced,
mostly randomized from a weighted pool (a few are admin-only or
summon-triggered); the appeal is a short, frequent "something is different
right now" moment that buffs everyone on the server equally
([TechWiser](https://techwiser.com/roblox-grow-a-garden-weather-events-and-how-they-work/),
[Droid Gamers](https://www.droidgamers.com/guides/grow-a-garden-weather-events-guide/)).
*Pet Simulator 99* instead runs **long thematic events** (roughly two to
three weeks each) with their own exclusive pets and a distinct event
currency/shop, then rotates to the next theme
([allthings.how](https://allthings.how/pet-simulator-99-events-schedule/),
[eloboost24](https://eloboost24.eu/blog/pet-simulator-99-complete-guide-to-updates-pets-zones)).
Abyssara's 12-hour slot length sits deliberately between these two: long
enough to build a themed shop/quest line and let event-exclusive creatures
feel special (Pet Sim 99-style), short enough that a player who logs in once
or twice a day will *always* see an active event rather than "nothing
happening" (Grow a Garden's server-synced immediacy). Both references
confirm the important shared property this document adopts: **the event
clock must be server-synced/deterministic**, not a per-server random pick,
or players compare notes and feel cheated.

---

## 1. Rotating events

### 1.1 Schedule (deterministic, no calm gap)

Events run in **fixed 12-hour UTC slots**, continuously, with **no calm gap**
between them. Reasoning: this is an idle/tycoon game aimed at 8–14-year-olds
who check in briefly a few times a day — a gap where "nothing is happening"
is a wasted login and (per the *Grow a Garden* research above) the games
that retain best always have *something* currently active. A calm gap would
only save development effort, not add player value, so it is cut.

```
EVENT_ORDER = { "ToxicTide", "SpookyTide", "BioluminescentBloom",
                "FrozenCurrent", "VolcanicVent", "TreasureTide" }
SLOT_SECONDS = 12 * 60 * 60 -- 43200

function GetActiveEventId(unixTimeUtc: number): string
    local slotIndex = math.floor(unixTimeUtc / SLOT_SECONDS) % #EVENT_ORDER
    return EVENT_ORDER[slotIndex + 1]
end
```

This is pure math on UTC epoch seconds (`os.time()` on Roblox is already
UTC) — every server computes the same `slotIndex` independently, no
DataStore or cross-server messaging needed, and there is nothing to desync.
The 6-event order repeats every 3 days (6 × 12h). Because the order is fixed
(not randomized per slot), players can predict "Volcanic Vent is always 2
slots after Toxic Tide," which is intentional — predictability lets kids
plan around a favorite event instead of feeling punished by RNG.

`EVENT_ORDER` lives in a new `src/shared/LiveEventConfig.lua` (see section
7b). Slot boundaries are always at `00:00 / 12:00 UTC` of a reference day
(epoch-aligned, so no timezone math is needed anywhere).

### 1.2 Fairness rule (applies to all events below)

Every event-exclusive creature is obtainable **only** via an **event egg**
bought with that event's free, play-earned currency — never a Robux-only
purchase. Because the event order repeats every 3 days, a missed creature
returns within days, not months: nothing is permanently missable. Event
currency **does not carry over** between different occurrences of the same
event (resets to 0 when the event ends) — this avoids currency hoarding
across cycles and keeps each 12h window a self-contained loop kids can
finish.

### 1.3 Event definitions

Each event applies a **global lighting/fog override** (via a single
`Lighting`/`Atmosphere` tween, consistent with the existing
`ColorCorrectionEffect` pattern in `WorldSetup.server.lua`) and a set of
**gameplay modifiers** active for all players for the duration of the slot.

---

#### Event 1 — Toxic Tide

- **Look:** `Lighting.Ambient = Color3.fromRGB(35, 55, 25)`,
  `Lighting.OutdoorAmbient = Color3.fromRGB(45, 70, 20)`,
  `Lighting.FogColor = Color3.fromRGB(70, 110, 30)`, `Lighting.FogEnd = 220`.
  Particle mood: sickly green-yellow bubble/spore drift
  (`ParticleEmitter.Color` sequence `Color3.fromRGB(140, 220, 60)` →
  `Color3.fromRGB(80, 140, 20)`), slow upward rise, `Rate = 6`.
- **Modifiers:** FilterPlant income ×1.5 (toxins = extra "filtering" work);
  raid enemy variant "Venom-Slick" (all enemies this slot get +20% MoveSpeed,
  green `EyeColor` override `Color3.fromRGB(150, 255, 60)`); Glow Spore
  pickups have a 15% chance to spawn as a larger "Toxic Spore" worth 3×
  normal value.
- **Event currency:** **Venom Pearls** — earned 1 per Glow Spore collected
  during the event, 8 per raid wave survived.
- **Event-exclusive creature:** **ToxinPuffer** (Rare) — see section 2.
- **Event shop (Venom Pearls):**
  | Item | Cost | Type |
  |---|---|---|
  | ToxinPuffer Egg | 180 Pearls | Creature egg |
  | "Venom Drip" plot decoration (dripping green crystal spike, 4×4×6 studs) | 60 Pearls | Cosmetic |
  | Toxic Tide diver-suit dye (sickly green) | 90 Pearls | Cosmetic |
  | Duplicate ToxinPuffer buy-back | 40 Pearls | Currency (converts to 150 Tide Coins) |
- **Quest line ("The Slick," 3 steps):** 1) Collect 40 Venom Pearls. 2)
  Survive 1 raid while Toxic Tide is active. 3) Hatch a ToxinPuffer Egg.
  Reward: 300 Tide Coins + a 24h "Toxin Resistant" title.

#### Event 2 — Spooky Tide (Ghost Tide)

- **Look:** `Lighting.Ambient = Color3.fromRGB(20, 20, 35)`,
  `Lighting.FogColor = Color3.fromRGB(30, 25, 50)`, `Lighting.FogEnd = 160`
  (denser fog than normal — spooky = low visibility). Particle mood: pale
  blue-white wisp trails (`Color3.fromRGB(200, 220, 255)`), slow horizontal
  drift, occasional flare via `PointLight.Brightness` pulse.
- **Modifiers:** Breeding odds shift +5% toward Rare-or-better (a "haunted
  incubation" flavor bonus, applied as a temporary override in
  `BreedingConfig`-consuming `BreedingService`, not a config file edit);
  raid enemy variant "Wraith-Touched" (all enemies gain a translucent
  `Transparency = 0.35` and +10% MaxHP); a rare "Ghost Ship" landmark event
  spawns near the Sun Zone Shipwreck landmark once per slot (visual only,
  triggers a 60s bonus-currency window).
- **Event currency:** **Spirit Motes** — 1 per Glow Spore, 10 per raid wave
  survived, 25 for finding the Ghost Ship.
- **Event-exclusive creature:** **PhantomJelly** (Epic) — see section 2.
- **Event shop (Spirit Motes):**
  | Item | Cost | Type |
  |---|---|---|
  | PhantomJelly Egg | 260 Motes | Creature egg |
  | "Jack-o-Coral" decoration (carved glowing coral head, 3×3×3 studs) | 70 Motes | Cosmetic |
  | Ghost-trail swim particle (cosmetic aura for any owned creature) | 100 Motes | Cosmetic |
  | Duplicate PhantomJelly buy-back | 55 Motes | Currency (converts to 400 Tide Coins) |
- **Quest line ("Things That Glow in the Dark," 3 steps):** 1) Find the
  Ghost Ship once. 2) Collect 60 Spirit Motes. 3) Survive 2 raids during
  Spooky Tide. Reward: 350 Tide Coins + "Ghost Diver" title.

#### Event 3 — Bioluminescent Bloom

- **Look:** `Lighting.Ambient = Color3.fromRGB(20, 45, 55)`,
  `Lighting.FogColor = Color3.fromRGB(15, 60, 70)`, `Lighting.FogEnd = 260`
  (brightest/most colorful event — a "celebration" tone). Particle mood:
  dense multicolor bioluminescent motes (`ColorSequence` cycling cyan →
  magenta → lime, `Rate = 10`), gentle upward spiral.
- **Modifiers:** GlowBuoyStation income ×1.4; all owned creatures'
  `PulseAttachment` idle-glow intensity +50% (pure visual delight, no
  balance impact); breeding incubation time −20% (bloom = fast growth).
- **Event currency:** **Bloom Dust** — 1 per Glow Spore, 6 per completed
  breeding cycle during the event.
- **Event-exclusive creature:** **BloomMoth** (Uncommon) — see section 2.
- **Event shop (Bloom Dust):**
  | Item | Cost | Type |
  |---|---|---|
  | BloomMoth Egg | 140 Dust | Creature egg |
  | "Coral Garden" decoration set (3 small glowing coral clusters) | 65 Dust | Cosmetic |
  | Rainbow glow-color unlock for any 1 owned creature | 120 Dust | Cosmetic |
  | Duplicate BloomMoth buy-back | 30 Dust | Currency (converts to 100 Tide Coins) |
- **Quest line ("Full Bloom," 3 steps):** 1) Collect 50 Bloom Dust. 2)
  Complete 1 breeding cycle during the event. 3) Hatch a BloomMoth Egg.
  Reward: 250 Tide Coins + "Bloom Keeper" title.

#### Event 4 — Frozen Current

- **Look:** `Lighting.Ambient = Color3.fromRGB(50, 65, 80)`,
  `Lighting.FogColor = Color3.fromRGB(180, 210, 230)`, `Lighting.FogEnd =
  200`. Particle mood: slow-falling pale ice motes
  (`Color3.fromRGB(210, 235, 250)`), downward drift (only event with
  downward-moving ambient particles, for contrast).
- **Modifiers:** all buildings' `IncomeRate` −10% (currents slow things
  down) but raid enemy `MoveSpeed` −25% (easier raids as a fair trade-off,
  good for younger/newer players); Glow Spores have a 10% chance to spawn as
  "Frozen Spore" (must be "thawed" by standing near it 3s before collecting,
  worth 4× value — a light, kid-friendly puzzle beat).
- **Event currency:** **Frost Shards** — 1 per Glow Spore, 12 per raid wave
  survived (compensates the harder economy with easier raids).
- **Event-exclusive creature:** **FrostAnglerPup** (Rare) — see section 2.
- **Event shop (Frost Shards):**
  | Item | Cost | Type |
  |---|---|---|
  | FrostAnglerPup Egg | 190 Shards | Creature egg |
  | "Ice Spire" decoration (translucent blue crystal spike cluster) | 65 Shards | Cosmetic |
  | Frost-breath particle for owned creatures (cosmetic) | 85 Shards | Cosmetic |
  | Duplicate FrostAnglerPup buy-back | 40 Shards | Currency (converts to 150 Tide Coins) |
- **Quest line ("Thaw Watch," 3 steps):** 1) Thaw and collect 10 Frozen
  Spores. 2) Collect 50 Frost Shards. 3) Survive 2 raids. Reward: 300 Tide
  Coins + "Frostwalker" title.

#### Event 5 — Volcanic Vent

- **Look:** `Lighting.Ambient = Color3.fromRGB(60, 25, 15)`,
  `Lighting.FogColor = Color3.fromRGB(90, 30, 10)`, `Lighting.FogEnd = 180`.
  Particle mood: rising orange embers (`Color3.fromRGB(255, 120, 30)`),
  occasional `PointLight` flare bursts synced to a "vent pulse" every ~8s.
- **Modifiers:** raid frequency modifier: raid interval −30% during this
  slot (more frequent raids = more action, matches the "danger" theme);
  raid enemy variant "Magma-Forged" (BodyColor override toward orange-red,
  +15% ContactDamage-equivalent threat via +15% MaxHP); FilterPlant and
  GlowBuoyStation both get a one-time +25% "vent surge" income tick every
  time a vent pulse fires (visual + small bonus, purely additive so it
  never punishes players who are offline).
- **Event currency:** **Ember Shards** — 1 per Glow Spore, 10 per raid wave
  survived, 5 per vent pulse witnessed (rewards active play without
  penalizing idle play).
- **Event-exclusive creatures:** **EmberSlug** (Uncommon) and **VentDrake**
  (Legendary) — see section 2. (Two creatures for this event since it doubles
  as the "hardest" event and deserves a headline reward.)
- **Event shop (Ember Shards):**
  | Item | Cost | Type |
  |---|---|---|
  | EmberSlug Egg | 130 Shards | Creature egg |
  | VentDrake Egg | 420 Shards | Creature egg |
  | "Magma Vent" decoration (glowing crack + rising embers, 4×2×4 studs) | 70 Shards | Cosmetic |
  | Duplicate buy-back (either creature) | 35 / 110 Shards | Currency |
- **Quest line ("Into the Vent," 3 steps):** 1) Witness 5 vent pulses. 2)
  Survive 3 raids during Volcanic Vent. 3) Collect 80 Ember Shards. Reward:
  400 Tide Coins + "Vent Diver" title.

#### Event 6 — Treasure Tide

- **Look:** `Lighting.Ambient = Color3.fromRGB(55, 50, 25)`,
  `Lighting.FogColor = Color3.fromRGB(120, 105, 40)`, `Lighting.FogEnd =
  260`. Particle mood: golden glint sparkles (`Color3.fromRGB(255, 220,
  120)`), short-lived flash-style `ParticleEmitter` bursts near build sites.
- **Modifiers:** Tide Coin income from all buildings ×1.25; a "Sunken
  Chest" pickup (reuses `GlowSporePickup` model, gold-recolored) spawns on
  each player's plot once per hour of the event, worth a flat 150 Tide
  Coins + guaranteed event currency; raid victory Tide Coin reward
  (`RaidConfig.VICTORY_REWARD_TIDE_COINS`) ×1.5 for this slot only.
- **Event currency:** **Doubloons** — 1 per Glow Spore, 15 per raid wave
  survived, 20 per Sunken Chest opened.
- **Event-exclusive creatures:** **GoldGuppy** (Rare) and **TreasureTurtle**
  (Epic) — see section 2. (Two creatures — this is the "economy" event, so
  it doubles as a reward-density peak.)
- **Event shop (Doubloons):**
  | Item | Cost | Type |
  |---|---|---|
  | GoldGuppy Egg | 170 Doubloons | Creature egg |
  | TreasureTurtle Egg | 310 Doubloons | Creature egg |
  | "Treasure Pile" decoration (gold coin/chest cluster) | 60 Doubloons | Cosmetic |
  | Duplicate buy-back (either creature) | 35 / 70 Doubloons | Currency |
- **Quest line ("X Marks the Spot," 3 steps):** 1) Open 4 Sunken Chests. 2)
  Collect 60 Doubloons. 3) Win 1 raid during Treasure Tide. Reward: 500 Tide
  Coins + "Treasure Hunter" title.

---

## 2. New creatures

Visual language follows the existing convention (`assets/models/README.md`):
`PrimaryPart` = `"Body"`, `Attachment "PulseAttachment"` on `PrimaryPart`,
attributes `Rarity`, `Zone` (or `Event`), `CreatureName`. Scale: 1 stud ≈
0.28 m, low-poly/blocky, Neon material for glow parts.

### 2.1 MidnightZone (4 creatures)

| Id | Display Name | Rarity | Visual description | Size | Idle motion |
|---|---|---|---|---|---|
| `LanternWraith` | Lantern Wraith | Rare | Slender ghost-anglerfish silhouette: flattened dark-purple `Part` body (`Color3.fromRGB(35, 20, 45)`), one curved bioluminescent lure-stalk (Neon `Color3.fromRGB(180, 255, 210)`) arcing forward from the head, two thin translucent fins (Glass material, `Transparency = 0.5`). ~4×2×5 studs. | 4×2×5 studs | Slow horizontal drift with the lure bobbing on a slight delay (2s sine offset from body). |
| `ObsidianCrab` | Obsidian Crab | Uncommon | Blocky low crab body, matte black `Slate` material with 2 oversized angular claws, 4 short stub legs, 2 small glowing eye-dots (Neon `Color3.fromRGB(255, 80, 60)`). ~3×1.5×3 studs. | 3×1.5×3 studs | Idle: slow claw-open/close cycle (no locomotion — sits on cave floor). |
| `MagmaSquid` | Magma Squid | Epic | Bulbous dark-red mantle (`Color3.fromRGB(60, 15, 20)`) with 6 tentacles that each carry a thin glowing orange vein-line (Neon `Color3.fromRGB(255, 100, 30)`), single large glowing eye. ~5×5×6 studs. | 5×5×6 studs | Tentacles ripple in a staggered wave (each tentacle offset 0.3s), mantle pulses on 3s cycle. |
| `VoidHammerhead` | Void Hammerhead | Legendary | Angular hammerhead-shark silhouette, near-black body (`Color3.fromRGB(15, 15, 25)`) with a glowing violet stripe (Neon `Color3.fromRGB(160, 60, 255)`) running head to tail, glowing violet eyes on the hammer ends. ~7×2×3 studs. | 7×2×3 studs | Slow S-curve swim path, stripe brightness pulses with swim speed. |

### 2.2 HadalDepths (4 creatures)

| Id | Display Name | Rarity | Visual description | Size | Idle motion |
|---|---|---|---|---|---|
| `TrenchWisp` | Trench Wisp | Uncommon | Small teardrop body, near-translucent (Glass, `Transparency = 0.4`), pale cyan inner glow (Neon core part `Color3.fromRGB(150, 255, 240)`), no visible fins — reads as a drifting light. ~1.5×1.5×2 studs. | 1.5×1.5×2 studs | Slow random-walk float, brightness flickers ±20% every 1.5s. |
| `AbyssalIsopod` | Abyssal Isopod | Rare | Segmented oval body (3–4 stacked slightly-offset blocky segments), pale gray-violet (`Color3.fromRGB(90, 80, 110)`), small glowing underside seam (Neon `Color3.fromRGB(120, 200, 255)`). ~3×2×4 studs. | 3×2×4 studs | Idle curl/uncurl (segments rotate slightly inward and back) on 4s cycle. |
| `GhostFinTuna` | Ghost-Fin Tuna | Epic | Streamlined torpedo body, pale blue-white (`Color3.fromRGB(200, 220, 235)`) with semi-transparent fins (Glass), faint trailing particle wake. ~6×2×2 studs. | 6×2×2 studs | Fast idle glide-loop around a fixed radius (visually "always swimming," unlike most other creatures which hover in place). |
| `CrystalLeviathan` | Crystal Leviathan | Mythic | The zone's signature creature and the game's first Mythic creature asset (fills the gap noted in `GachaConfig.CREATURE_POOL.Mythic = {}`). Elongated eel-like body built from angular faceted "crystal" segments (WedgePart mix), deep violet-black base (`Color3.fromRGB(30, 15, 45)`) with bright multi-Neon seams (`Color3.fromRGB(190, 80, 255)` and `Color3.fromRGB(90, 220, 255)` alternating per segment), small crystalline fin-spikes along the spine. ~10×3×3 studs — the largest creature model in the game. | 10×3×3 studs | Slow, heavy sine-wave swim (long wavelength), each segment's Neon seam brightens in sequence head-to-tail like a light chase. |

*(`CrystalLeviathan` should also be added to `GachaConfig.CREATURE_POOL.Mythic` and `GachaConfig.CREATURE_DISPLAY_NAME_FALLBACK` once built — see section 7b.)*

### 2.3 Event-exclusive creatures (8, from section 1)

| Id | Display Name | Rarity | Event | Visual description | Size | Idle motion |
|---|---|---|---|---|---|---|
| `ToxinPuffer` | Toxin Puffer | Rare | Toxic Tide | Round inflated body, sickly yellow-green (`Color3.fromRGB(170, 210, 60)`), small dark spines poking outward, glowing green belly seam (Neon `Color3.fromRGB(150, 255, 60)`). ~3×3×3 studs. | 3×3×3 studs | Idle "breathe" pulse: scales 1.0→1.15→1.0 on 2.5s cycle (puffing). |
| `PhantomJelly` | Phantom Jelly | Epic | Spooky Tide | Classic jelly-bell shape but fully translucent (Glass, `Transparency = 0.6`), pale blue-white inner glow (Neon `Color3.fromRGB(190, 210, 255)`), 5 thin trailing tentacle strands that fade toward the tip (`Transparency` gradient via multiple segments). ~3×3×4 studs. | 3×3×4 studs | Slow upward float with tentacles trailing behind on a lag/delay, flickers briefly (Transparency spike) every ~6s like it's phasing. |
| `BloomMoth` | Bloom Moth | Uncommon | Bioluminescent Bloom | Small winged sea-slug/moth hybrid, pastel body (`Color3.fromRGB(255, 200, 230)`) with two large fin-wings carrying a rainbow Neon edge (`ColorSequence` cyan→magenta→lime). ~2×1×2 studs. | 2×1×2 studs | Wings flap slowly (rotate ±25° on 1s cycle), gentle up-down bob. |
| `FrostAnglerPup` | Frost Angler Pup | Rare | Frozen Current | Small, rounder juvenile version of the Anglerfish silhouette, pale icy-blue body (`Color3.fromRGB(180, 220, 240)`), tiny glowing lure-tip (Neon `Color3.fromRGB(210, 245, 255)`), faint frost-crystal texture accents (small white WedgeParts on the back). ~2.5×1.5×3 studs. | 2.5×1.5×3 studs | Idle shiver (tiny fast side-to-side jitter, 0.2s period) between slow hover-drifts. |
| `EmberSlug` | Ember Slug | Uncommon | Volcanic Vent | Squat sea-slug body, dark charcoal (`Color3.fromRGB(40, 30, 30)`) with glowing orange ridge-line down the back (Neon `Color3.fromRGB(255, 130, 30)`). ~2.5×1.5×3.5 studs. | 2.5×1.5×3.5 studs | Idle pulse along the ridge-line (glow travels tail-to-head on 3s loop), otherwise stationary. |
| `VentDrake` | Vent Drake | Legendary | Volcanic Vent | Serpentine sea-dragon silhouette with 2 small fin-wings, dark red-black scaled body (`Color3.fromRGB(70, 20, 15)`), glowing orange spine-spikes (Neon `Color3.fromRGB(255, 110, 20)`), small horn cluster on the head. ~6×2×5 studs. | 6×2×5 studs | Slow serpentine swim with spine-spikes flaring brighter on each undulation peak. |
| `GoldGuppy` | Gold Guppy | Rare | Treasure Tide | Small classic fish silhouette, metallic gold body (`Color3.fromRGB(230, 190, 70)`, `Material = Enum.Material.Metal`), single glowing tail-fin edge (Neon `Color3.fromRGB(255, 230, 130)`). ~1.5×1×2 studs. | 1.5×1×2 studs | Quick darting idle movement (short bursts every 2–3s, otherwise still) — reads as "flighty/valuable." |
| `TreasureTurtle` | Treasure Turtle | Epic | Treasure Tide | Turtle silhouette with a shell built from a CSG-union gold-and-teal "chest lid" pattern (`Color3.fromRGB(210, 170, 60)` base with `Color3.fromRGB(50, 140, 130)` inlay stripes), small glowing keyhole detail (Neon `Color3.fromRGB(255, 220, 120)`) on the shell center. ~4×2.5×5 studs. | 4×2.5×5 studs | Slow, heavy idle sway (turtle-paddle motion, legs rotate ±15° alternating), shell keyhole glints (brief Neon flash) every ~5s. |

---

## 3. New raid enemies

Closes the gap noted in `docs/release-checklist.md`: "eigene Gegnermodelle
(alle Gegner nutzen die Schattenkrake)". Each model replaces `ShadowKraken`
as the `TemplateName` for its `RaidConfig.EnemyId`; `ShadowKraken.lua`
itself is kept as-is (still referenced by nothing after this update, safe to
leave in place or archive). All new enemy models follow the existing
enemy-model contract: `PrimaryPart = "Body"`, `Attachment "PulseAttachment"`,
attributes `EnemyTier`, `Zone`.

| RaidConfig `EnemyId` | New model Id | Visual description | Size | Notes |
|---|---|---|---|---|
| `Drifter` | `SpineDrifter` | Lean, spindly eel-like body, dark slate-blue (`Color3.fromRGB(40, 60, 70)`, matches existing `BodyColor`), thin dorsal spines along the back, glowing red eye-slits (Neon `Color3.fromRGB(255, 60, 80)`, matches existing `EyeColor`). ~3×1.5×4 studs base scale (before `ScaleMultiplier`). | 3×1.5×4 studs | Fast, low-HP "skirmisher" read — thin silhouette communicates fragility. |
| `Swarmer` | `ThornSwarmer` | Small, spiky urchin-fish hybrid, teal-dark body (`Color3.fromRGB(30, 90, 95)`), radiating short thorn-spikes, orange glow eyes (`Color3.fromRGB(255, 150, 60)`). ~2×2×2.5 studs base. | 2×2×2.5 studs | Compact/round silhouette reads "numerous and annoying," fitting its swarm role. |
| `Brute` | `IronMawBrute` | Heavy, hunched body with an oversized jaw, dark purple-gray (`Color3.fromRGB(55, 35, 70)`), visible armor-plate chest (CSG-union angular plates), red glow eyes (`Color3.fromRGB(255, 40, 60)`). ~5×3×5 studs base. | 5×3×5 studs | Bulky silhouette communicates high HP/slow "tank" role. |
| `TrenchWarden` (boss) | `TrenchWardenBoss` | The signature boss model: towering kraken-lord silhouette, near-black body (`Color3.fromRGB(15, 10, 15)`), 8 tentacles (longer/thicker than the old ShadowKraken placeholder), glowing red crown-spike cluster on the head, largest glow eyes in the game (`Color3.fromRGB(255, 20, 30)`, `PointLight` attached for dramatic raid-arena lighting). ~9×6×9 studs base. | 9×6×9 studs | Reused as the "Der Tiefenfürst" arena's narrative payoff (see `MidnightZoneTerrainChunk.lua` landmark) — should visually read as what waits behind that cave-tor landmark. |

### 3.1 Zone scaling (Midnight/Hadal raids)

`RaidConfig` currently has no per-zone scaling (`ENEMIES` table is global).
Add zone multipliers applied when a raid is generated for a player whose
current zone is `MidnightZone` or `HadalDepths`:

| Zone | MaxHP ×  | MoveSpeed × | ScaleMultiplier × |
|---|---|---|---|
| SunZone / TwilightZone (unchanged) | 1.0 | 1.0 | 1.0 |
| MidnightZone | 1.6 | 1.1 | 1.1 |
| HadalDepths | 2.4 | 1.2 | 1.2 |

Applied multiplicatively to the base `EnemyDefinition` values at raid-wave
generation time (not stored back into `RaidConfig.ENEMIES`, which stays the
single base-truth table). `ContactDamage` (currently always `1`,
i.e. a breach counter) is **not** scaled — `RaidConfig.DEFEAT_ENEMY_REACH_COUNT`
stays the difficulty lever for breach tolerance instead, keeping the "3
breaches = defeat" rule consistent across zones.

---

## 4. New towers

Both towers are already named in the GDD (section 8) but have no stats or
models yet (release-checklist gap: "weitere Turmtypen"). Added to
`BuildingConfig.DEFINITIONS` and `RaidConfig.TOWER_STATS`.

### 4.1 Coral Barrier

- **Role:** area-denial/tank tower — high HP-equivalent "block" rather than
  high damage (unlike the single-target Anglerfish Tower).
- **BuildingConfig entry:**
  `Cost = 550`, `SellRefundFraction = 0.5`, `GridFieldCount = 1`,
  `UnlockLevel = 12`, `TemplateName = "CoralBarrier"`, `IncomeRate = 0`.
- **RaidConfig.TOWER_STATS entry:**
  `Range = 14` (short — it's a wall, not a sniper), `Damage = 8`,
  `FireRate = 2.5` (→ 20 DPS, lower per-tower DPS than Anglerfish's 27, but
  see below), plus new field `BlockRadius = 10` (studs) — enemies inside
  `BlockRadius` get `MoveSpeed` reduced by 40% while in range (a slow
  effect, distinct mechanic from pure damage — gives the code agent a
  reason this tower isn't strictly worse than Anglerfish).
- **Visual description:** a ring/arc of fused coral spikes on a rounded
  base (CSG-union, matching the `BroodPool_Basic` ring-CSG technique),
  warm pink-orange coral color (`Color3.fromRGB(255, 140, 120)`) with a
  Neon-teal glowing tip on each spike (`Color3.fromRGB(80, 230, 210)`,
  the tower's "muzzle"/effect point). ~5×4×5 studs. `PrimaryPart = "Base"`,
  `LureOrb`-equivalent part named `SlowPulseCore` (matches the
  `AnglerfishTower.LureOrb` naming convention for consistency, marks the
  slow-pulse VFX origin).

### 4.2 Electric Eel Trap

- **Role:** chain-damage tower — hits the primary target plus nearby
  enemies (small AoE via a "chain," distinct from Coral Barrier's slow and
  Anglerfish's single-target burst).
- **BuildingConfig entry:**
  `Cost = 900`, `SellRefundFraction = 0.5`, `GridFieldCount = 1`,
  `UnlockLevel = 18`, `TemplateName = "ElectricEelTrap"`, `IncomeRate = 0`.
- **RaidConfig.TOWER_STATS entry:**
  `Range = 22`, `Damage = 14`, `FireRate = 1.2` (→ ~16.8 DPS to primary
  target), plus new field `ChainCount = 2` (hits up to 2 additional nearby
  enemies per shot at 50% damage) and `ChainRadius = 10` studs.
- **Visual description:** a coiled eel-body wrapped around a rock anchor,
  dark blue-black body (`Color3.fromRGB(20, 30, 55)`) with a bright yellow
  Neon stripe running the body length (`Color3.fromRGB(255, 230, 80)`),
  small sparking-arc particle emitter at the head (attack origin). ~2×2×6
  studs coiled footprint. `PrimaryPart = "Base"`, attack-origin part named
  `EelHead` with a `MuzzlePoint` attachment (matches `AnglerfishTower`
  convention).

---

## 5. Creature display + codex

The single highest-value improvement for this update: right now owned
creatures are invisible inventory rows. Making them visible and collectible
as a *book* is what turns "I own 14 creatures" into something a kid actually
wants to show a friend.

### 5.1 Plot display (creatures visibly swim around the owner's plot)

- **Count:** up to **6 creatures visible at once per plot** (hard cap,
  applies even to players who own more). Chosen for mobile performance —
  6 lightweight low-poly creature models with idle animation is a small,
  predictable addition on top of the existing plot budget (buildings +
  ambient FX, see `assets/models/README.md`'s "Handy-Performance" section
  which already targets ~220 parts for the whole hub; 6 creatures at
  2–15 parts each keeps a plot's creature budget under ~60 parts).
- **Selection rule:** by default, the game auto-picks the player's **6
  rarest owned creatures** (ties broken by most-recently-obtained). Players
  can override this via a "Favorites" toggle in the codex UI (section 5.2)
  to hand-pick up to 6 specific creatures instead — the auto-pick is a
  sensible default, not a restriction.
- **Movement:** each displayed creature gets a small random-waypoint
  wander loop confined to a radius around the plot center (radius scales
  with plot size, ~20 studs for the existing 60-stud hex plot), using the
  same `PulseAttachment`-driven idle animation pattern already established
  for all creature models — no new animation system needed, just a
  position-wander wrapper around the existing idle pulse.
- **Performance limits for phones:** creature wander AI runs server-side at
  a shared, throttled tick (reuse the `RaidConfig.RAID_TICK_SECONDS = 0.1`
  pattern — one `Heartbeat`-bound loop iterating all displayed creatures
  across all plots, not one loop per creature). Client-side, displayed
  creatures respect `Workspace.StreamingEnabled` (already recommended in
  `assets/models/README.md`) so off-screen/far plots' creatures don't
  render. On `UserInputService.TouchEnabled` clients (phones/tablets), the
  ambient glow `PointLight`s on displayed creatures default to
  `Shadows = false` (same rule already applied hub-wide) and Neon-only
  emission is used instead of live particle emitters per creature (particle
  budget stays reserved for the existing plot/hub ambient FX system).

### 5.2 Collection book UI ("Codex")

- **Access:** a new "Codex" button in the main HUD (alongside existing
  Shop/Quests buttons).
- **Layout:** grid of creature entry cards grouped by zone/event (SunZone,
  TwilightZone, MidnightZone, HadalDepths, then one group per event name).
  Each card shows the creature's rarity-colored frame (reuses the existing
  `GachaOddsPanel.lua` rarity color convention — same `Color3` values as
  `GachaConfig.DROP_TABLE[rarity].Color`).
- **Missing creatures:** shown as a **flat dark silhouette** (single
  `ImageLabel` with a generic silhouette icon + `ImageColor3 =
  Color3.fromRGB(25, 25, 30)`) instead of the real icon/model thumbnail —
  visible enough to say "there's something here you haven't found," not
  detailed enough to spoil the design.
- **Per-zone completion %:** a progress header per zone group ("Midnight
  Zone: 3/4 — 75%"), computed client-side from the player's inventory
  against `BreedingConfig`/zone creature lists synced from the server.
- **Completion reward:** completing a zone's full creature set (all
  rarities owned at least once) grants a **one-time** reward: 1000 Tide
  Coins + a unique cosmetic title (`"<Zone> Cataloguer"`) + a small
  permanent +2% income boost for buildings placed in that zone (stacks
  across zones, small enough to stay a nice-to-have rather than mandatory
  power creep — 4 zones fully catalogued = +8% total, comparable in scale
  to a single early Prestige tier from the base GDD).
- **Event creature entries:** always visible in the codex (not hidden
  until the event is active) so players know what to look forward to /
  what they're missing, with a small badge showing which event unlocks
  them and reminding players the event returns every 3 days.

---

## 6. Zone content (MidnightZone & HadalDepths)

Both zones are currently walkable but empty of unique content (release
checklist gap). This update gives each a reason to visit beyond the portal:

### MidnightZone
- **Unique creatures:** the 4 creatures from section 2.1 (`LanternWraith`,
  `ObsidianCrab`, `MagmaSquid`, `VoidHammerhead`) are added to
  `BreedingConfig.CREATURE_POOL` and `GachaConfig.CREATURE_POOL` for a new
  Level-2 BroodPool-only unlock path (see 7b) — they do **not** appear in
  the Zone-1/2 pools, so breeding/gacha odds tables for existing zones are
  untouched.
- **Zone-specific spore bonus:** Glow Spores collected while standing in
  MidnightZone have a flat +20% Tide Coin value (a simple "deeper zones pay
  better" incentive, consistent with the GDD's zone-depth progression
  theme), read from a new `ZoneEconomyConfig.lua` multiplier table (see
  7b) rather than hardcoded in `IdleIncomeService`.
- **Raid difficulty:** uses the zone scaling multipliers from section 3.1
  (HP ×1.6, MoveSpeed ×1.1) and unlocks the `TrenchWardenBoss` model as the
  visual payoff for the "Der Tiefenfürst" arena landmark already built in
  `MidnightZoneTerrainChunk.lua`.
- **Breeding:** BroodPool Level 2 ("Fortgeschritten," already defined in
  `BreedingConfig.TIERS[2]`) is the first tier whose `RarityWeights` can
  roll a MidnightZone creature — tying the existing but currently-unused
  Level 2/3 BroodPool tiers to an actual visible reward for the first time.

### HadalDepths
- **Unique creatures:** the 4 creatures from section 2.2, including the
  game's first Mythic creature (`CrystalLeviathan`) — fills the
  `GachaConfig.CREATURE_POOL.Mythic = {}` gap explicitly flagged in that
  file's own comments.
- **Zone-specific spore bonus:** +35% Tide Coin value (deepest zone, best
  multiplier, same `ZoneEconomyConfig.lua` table).
- **Raid difficulty:** HP ×2.4, MoveSpeed ×1.2 (section 3.1) — the
  hardest raids in the game, appropriate for the endgame zone.
- **Breeding:** BroodPool Level 3 ("Meisterstufe") is the only tier that
  can roll a HadalDepths creature, including a small (0.5%) chance at
  `CrystalLeviathan` even though it's primarily a Gacha-pool creature —
  gives the free/grind path a (very) small shot at the same top-tier
  reward as the paid Gacha path, consistent with the existing
  Gacha-vs-Breeding fairness philosophy documented in
  `BreedingConfig.lua`'s header comment.

---

## 7. Build list

### 7a. 3D models to build

All follow the existing conventions in `assets/models/README.md`
(`PrimaryPart` naming, `PulseAttachment`, attribute contract). Paths are
relative to `/home/user/ro/`.

**Creatures — `assets/models/creatures/`**
- `MidnightZone_LanternWraith.lua` → build as `assets/models/creatures/LanternWraith.lua`
- `assets/models/creatures/ObsidianCrab.lua`
- `assets/models/creatures/MagmaSquid.lua`
- `assets/models/creatures/VoidHammerhead.lua`
- `assets/models/creatures/TrenchWisp.lua`
- `assets/models/creatures/AbyssalIsopod.lua`
- `assets/models/creatures/GhostFinTuna.lua`
- `assets/models/creatures/CrystalLeviathan.lua`
- `assets/models/creatures/ToxinPuffer.lua`
- `assets/models/creatures/PhantomJelly.lua`
- `assets/models/creatures/BloomMoth.lua`
- `assets/models/creatures/FrostAnglerPup.lua`
- `assets/models/creatures/EmberSlug.lua`
- `assets/models/creatures/VentDrake.lua`
- `assets/models/creatures/GoldGuppy.lua`
- `assets/models/creatures/TreasureTurtle.lua`

(16 new creature models total: 8 zone + 8 event.)

**Raid enemies — `assets/models/enemies/`**
- `assets/models/enemies/SpineDrifter.lua`
- `assets/models/enemies/ThornSwarmer.lua`
- `assets/models/enemies/IronMawBrute.lua`
- `assets/models/enemies/TrenchWardenBoss.lua`

(4 new enemy models, replacing `ShadowKraken` as the shared placeholder for
all four `RaidConfig.EnemyId`s.)

**Towers — `assets/models/buildings/`**
- `assets/models/buildings/CoralBarrier.lua`
- `assets/models/buildings/ElectricEelTrap.lua`

**Event cosmetic decorations — `assets/models/decorations/`** (new folder)
- `assets/models/decorations/VenomDrip.lua` (Toxic Tide)
- `assets/models/decorations/JackOCoral.lua` (Spooky Tide)
- `assets/models/decorations/CoralGardenSet.lua` (Bioluminescent Bloom)
- `assets/models/decorations/IceSpire.lua` (Frozen Current)
- `assets/models/decorations/MagmaVent.lua` (Volcanic Vent)
- `assets/models/decorations/TreasurePile.lua` (Treasure Tide)

**Pickups — `assets/models/pickups/`**
- `assets/models/pickups/SunkenChest.lua` (gold recolor of
  `GlowSporePickup`, Treasure Tide only)
- `assets/models/pickups/FrozenSpore.lua` (Frozen Current only, needs a
  "thaw" visual state toggle: icy shell → cracked → open)

**UI icon sets — `assets/models/ui/`**
- Rarity-consistent icon set for the 16 new creatures (reuse existing
  `GachaOddsPanel.lua` icon conventions).
- Silhouette placeholder icon for codex "missing creature" cards (section 5.2).
- 6 event currency icons (Venom Pearl, Spirit Mote, Bloom Dust, Frost
  Shard, Ember Shard, Doubloon).

**Total new 3D models: 22 gameplay models (16 creatures + 4 enemies + 2
towers) + 8 decoration/pickup models + supporting UI icon assets.**

### 7b. Code systems to change or add

**New files:**
- `src/shared/LiveEventConfig.lua` — `EVENT_ORDER`, `SLOT_SECONDS`,
  `GetActiveEventId(unixTimeUtc)`, per-event lighting/fog/modifier tables,
  event currency names, event shop item tables, event creature pool
  mappings. Mirrors the existing `RaidConfig.lua`/`BuildingConfig.lua`
  "data only, no logic" pattern.
- `src/server/LiveEventService.lua` — reads `LiveEventConfig`, applies
  `Lighting`/`Atmosphere` overrides on slot change (server-driven, synced to
  clients via a `RemoteEvent "EventChanged"`), tracks per-player event
  currency balances (resets on slot change per the fairness rule in 1.2),
  handles event shop purchases (server-validated, same pattern as
  `PlacementService`), applies raid/income modifiers by reading the active
  event and adjusting `RaidService`/`IdleIncomeService` calculations at the
  point of use (not by mutating `RaidConfig`/`BuildingConfig` directly —
  those stay pure base-truth tables).
- `src/shared/ZoneEconomyConfig.lua` — per-zone Glow Spore value
  multipliers (SunZone/TwilightZone 1.0, MidnightZone 1.2, HadalDepths
  1.35), read by `IdleIncomeService`/collection logic.
- `src/server/CreatureDisplayService.lua` — picks up to 6 displayed
  creatures per plot (rarest-first default, favorites override), spawns/
  despawns their models on the plot, runs the shared throttled wander-tick
  loop (reusing the `RaidConfig.RAID_TICK_SECONDS`-style shared-Heartbeat
  pattern).
- `src/client/CodexUI` (new UI module tree) — codex grid, per-zone
  completion %, silhouette-for-missing rendering, completion reward claim
  flow, favorites picker feeding `CreatureDisplayService`.
- `src/client/EventUI` (new UI module tree) — active event banner/timer
  (countdown to next 12h slot boundary), event shop panel, event quest
  tracker panel.

**Existing files to change:**
- `src/shared/RaidConfig.lua`:
  - Add `TemplateName` overrides: `Drifter → "SpineDrifter"`, `Swarmer →
    "ThornSwarmer"`, `Brute → "IronMawBrute"`, `TrenchWarden →
    "TrenchWardenBoss"`.
  - Add `TOWER_STATS.CoralBarrier` and `TOWER_STATS.ElectricEelTrap`
    (including the new `BlockRadius`/`ChainCount`/`ChainRadius` fields —
    extend the `TowerCombatStats` type).
  - Add a `ZONE_SCALING` table (`MidnightZone`/`HadalDepths` HP/MoveSpeed/
    ScaleMultiplier factors from section 3.1) and a
    `RaidConfig.GetScaledEnemy(enemyId, zone)` helper.
- `src/shared/BuildingConfig.lua`: add `CoralBarrier` and
  `ElectricEelTrap` entries (costs/unlock levels from section 4); add
  both to `BuildingConfig.ORDER`.
- `src/shared/BreedingConfig.lua`: add the 8 MidnightZone/HadalDepths
  creatures to `CREATURE_POOL` gated by `BroodPool` tier (Level 2 unlocks
  MidnightZone creatures, Level 3 unlocks HadalDepths creatures + the small
  `CrystalLeviathan` chance per section 6); extend `RARITY_ORDER`/
  `RARITY_DEFINITIONS` to include `"Mythic"` (currently stops at
  Legendary, per the header comment's documented reason — this update
  removes that limitation for `CrystalLeviathan` specifically) and add
  `CREATURE_DISPLAY_NAME_FALLBACK` entries for all 8.
- `src/server/GachaConfig.lua`: add `CrystalLeviathan` to
  `CREATURE_POOL.Mythic` (closing the explicitly-flagged empty-pool gap)
  and its `CREATURE_DISPLAY_NAME_FALLBACK` entry.
- `src/server/RaidService.lua`: read `RaidConfig.ZONE_SCALING` when
  generating a wave for a player in MidnightZone/HadalDepths; read active
  `LiveEventService` state for enemy-visual/raid-interval/reward modifiers
  (Toxic/Spooky/Volcanic/Treasure Tide effects from section 1.3).
- `src/server/IdleIncomeService.lua`: read `ZoneEconomyConfig` per-zone
  multiplier and `LiveEventService` active-event building multipliers
  (FilterPlant/GlowBuoyStation boosts from section 1.3) when computing
  tick income.
- `src/server/BreedingService.lua`: read `LiveEventService` active-event
  breeding modifiers (Spooky Tide rarity shift, Bioluminescent Bloom
  incubation-time reduction) at roll/timer-start time.
- `src/server/AssetTemplateSetup.lua`: extend the template-copy list to
  include the new `decorations/` and updated `enemies/`/`buildings/`
  folders.
- `src/client/PlotUI` (or wherever the main HUD lives): add "Codex" button
  wiring to `CodexUI`, add event banner/timer wiring to `EventUI`.
- `docs/release-checklist.md`: once built, remove the now-closed items
  from section 7 ("Wächter-Kreaturen im Raid, weitere Turmtypen, eigene
  Gegnermodelle," "Zone 3 und 4 ... noch keine eigenen Kreaturen") and add
  a new "Selbst eintragen" row if any event needs manual asset IDs (event
  currency icons, if not using in-house `ImageLabel` colors).

---

*This document is scoped to be actionable without further clarification:
the 3D-model agent can build directly from sections 2–4 and 7a; the code
agent can build directly from sections 1, 3.1, 5–6, and 7b. No season pass
is included in this update per existing project decision — event rotation
(section 1) is the sole live-content mechanism.*
