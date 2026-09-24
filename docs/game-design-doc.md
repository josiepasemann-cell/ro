# Game Design Document: **Abyssara – Deep Tide Tycoon**

*As of: 2026-09-24 · Version 1.0*

---

## 1. Title & Elevator Pitch

**Abyssara – Deep Tide Tycoon**

Build a bioluminescent underwater colony on the seafloor, breed glowing
deep-sea creatures for passive income, and defend your station against
nightly "Trench Raids" — hungry deep-sea monsters that want to steal your
most valuable creatures. Dive ever deeper into new, more dangerous
trenches to unlock rarer species and stronger defenses.

## 2. Target audience & comparable successful games

- **Primary audience:** ages 8–14, with a secondary group of 15–25
  (collector/idle fans). Mixed boys/girls, since collect/breed mechanics
  (like pet sims) appeal more broadly than a pure combat game.
- **Session length:** short active sessions (5–10 min. check-ins) + idle
  progress between sessions — fits the target audience's mobile/snack-play
  behavior.
- **Comparable hits (reference, not a copy):**
  - *Grow a Garden* – idle growth, genetics/mutations, trading hype.
  - *Steal a Brainrot* – raid/steal loop, base defense, high concurrent peaks.
  - *Pet Simulator 99* – collection progression, rarity tiers, zone unlocks.
  - *Theme Park Tycoon 2* – classic build-tycoon loop.
  - **Differentiation:** the underwater/deep-sea setting is strongly
    underrepresented on Roblox (a visual niche: bioluminescence instead of
    neon-brainrot aesthetics), PvE raid defense instead of pure
    player-vs-player stealing (more kid-friendly, less toxic), plus an
    optional asynchronous "Reef Raiding" against other players for meta
    depth without mandatory PvP.

## 3. Core gameplay loop

### Minute-to-minute
1. The player lands on their own Habitat Plot (a personal island/pit on
   the seafloor).
2. Collects "Glow Spores"/bioluminescence resources from placed creature
   stands (clicking/auto-collect via gamepass).
3. Feeds & breeds creatures in a Brood Pool (timer-based, like egg
   hatching).
4. Buys/places new buildings (filter plants, glow buoys, defense towers)
   with collected currency ("Tide Coins").
5. Sells surplus creatures at the trade dock or trades with friends.

### Session-to-session
- About every 20–30 minutes (real time, also counting offline with a
  cap), a **Trench Raid** starts: waves of deep-sea monsters attack the
  station. The player places defense towers beforehand (Anglerfish
  Towers, Coral Barriers) and can actively deploy creatures as "guardians"
  during the raid.
- Successful defense = bonus loot (rare eggs, Tide Coins). Failed defense
  = a random creature gets "abducted" (can later be recovered via a
  ransom/rescue mission — a soft loss instead of a hard loss, kid-friendly).
- Daily quests ("Catch 3 Anglerfish", "Survive 1 raid without a loss")
  with reward chests.

### Long-term progression
- **Trench Depth system:** the player descends from the "Sun Zone" (start)
  through the "Twilight Zone", "Midnight Zone", down to the "Hadal
  Depths". Each zone = a new map/biome, new creature pools, stronger raid
  enemies, new build parts.
- **Prestige system ("Ascend/Resurface"):** after reaching the deepest
  currently available zone, the player can "resurface" and restart in
  Zone 1 with a permanent multiplier (+X% income) and a cosmetic
  title/badge — a classic idle prestige curve.
- **Collection album:** a creature codex with rarity tiers (Common →
  Mythic → Abyssal). Complete sets grant permanent bonuses.

## 4. Game modes / maps / level structure

- **Main mode – Habitat Building (solo instance, but visible to friends):**
  every player has their own, persistent plot island (saved server-side
  like in tycoon games), reachable via a central hub world.
- **Hub world "Tidal Market":** a central lobby with a trade dock
  (trading), NPC merchants, leaderboard displays, portals to the trench
  zones.
- **4 core zones (MVP: 2 of them):**
  1. Sun Zone (tutorial/start, level 1–10)
  2. Twilight Zone (level 10–25)
  3. Midnight Zone (level 25–45, Phase 2)
  4. Hadal Depths (level 45+, Phase 3, endgame/prestige zone)
- **Raid instance:** a separate, private server instance per player (or
  party in co-op), where the Trench Raid wave takes place — procedurally
  assembled from the enemy pool of the current zone.
- **Co-op mode (Phase 2):** up to 4 players can connect their habitats into
  a "Reef Cluster" and jointly clear bigger raids (boss raids).

## 5. Monetization

**Gamepasses (one-time, Robux):**
| Gamepass | Price (Robux) | Effect |
|---|---|---|
| Auto-Collector | 149 | Automatically collects Glow Spores without clicking |
| 2x Tide Coins | 349 | Permanently doubled currency |
| Extra Habitat Plot | 199 | A second, own plot (more build space) |
| VIP Diver | 449 | Exclusive skin, daily bonus chest, 1.5x breeding speed |
| Trench Runner | 99 | Faster movement/dive speed |

**Developer products (repeatedly purchasable, Robux):**
| Product | Price (Robux) | Effect |
|---|---|---|
| 500 Tide Coins | 79 | Direct currency |
| 3,000 Tide Coins | 399 | Direct currency (bulk discount) |
| Rescue Token (instantly recover an abducted creature) | 49 | Bypasses the rescue mission |
| Mystery Egg (random creature, rarity chance) | 89 | Gacha-style collection element (with clearly communicated drop chances, see Roblox guidelines) |
| Raid Skip (the current raid is automatically counted as "won", 1x/day) | 59 | Time savings |

**Season Pass ("Tide Pass"):** 399 Robux per season (6 weeks), a
Battle-Pass-style free/premium track with cosmetic creature skins,
exclusive build-style sets, bonus coins. No gameplay advantage on premium
(cosmetics + small coin boosts only), to keep things fair.

**Cosmetic shop (rotating):** habitat decorations, diving suit skins, glow
color effects for creatures — 25–150 Robux per item.

## 6. Progression system

- **Player level:** rises via XP from quests, raid wins, breeding
  successes. Level unlocks build recipes and zone access.
- **Currencies:**
  - *Tide Coins* (main currency, from idle income/selling) – build costs,
    breeding costs.
  - *Abyssal Shards* (premium-adjacent, rare from raids/season pass) –
    rare creatures, cosmetics.
- **Progression curve (guideline, exponential with soft caps):**
  - Level 1–10: fast unlocks (every 5–10 min.), high tutorial rewards.
  - Level 10–25: costs x1.15 per level, income x1.12 — a slight gap,
    cushioned by gamepasses/season pass.
  - Level 25–45: costs x1.2, stronger grind, prestige becomes attractive.
  - Prestige multiplier: +10% income per ascend, cumulative, with
    diminishing returns starting at ascend 10 (soft-capped via
    diminishing returns, e.g. +10%/+10%/+8%/+8%…), to slow down inflation.
- **Unlocks per level (examples):** a new build module (level 3), a second
  Brood Pool slot (level 6), the first defense tower (level 8), the
  Twilight Zone portal (level 10).

## 7. Social / multiplayer features

- **Friends-list bonus:** visiting friends gives a small coin bonus
  (anti-bot measure: 20-min. cooldown per friend).
- **Trading system:** a secure 2-player trade dialog at the trade dock for
  creatures (with a confirmation screen, Robux trading excluded per
  Roblox guidelines).
- **Reef Cluster (teams, Phase 2):** groups of up to 4 players for co-op
  boss raids, a shared cluster leaderboard.
- **Leaderboards:** global rankings for "Deepest Zone Reached", "Most
  Ascends", "Rarest Creature Collection" — visible in the hub.
- **Asynchronous Reef Raiding (Phase 3, optional/PvE-leaning):** players
  can challenge the AI defense of a foreign, "visited" reef (no direct PvP
  damage to the target's actual progress, only copy/snapshot-based like
  Clash-of-Clans-style systems), to earn bonus resources.
- **Emotes/chat stickers:** themed underwater emotes (bubble wave, glow
  dance) as a small social layer, some shop items.

## 8. Required 3D assets (brief for the 3D artist agent)

**Environment / terrain:**
- Seabed terrain sets per zone (4x): Sun Zone (sandy, bright), Twilight
  Zone (rocks, kelp), Midnight Zone (dark caves, lava rifts), Hadal Depths
  (abyss, crystal formations).
- Modular Habitat Plot base (circular/hexagonal platform, approx. 60x60
  studs, divided into a build-field grid).
- Hub world "Tidal Market": central marketplace structure with trade
  dock, NPC stands, portal gates to the 4 zones.

**Buildings/build parts (modular, placeable):**
- Brood Pool (3 stages: Basic, Advanced, Master)
- Glow Buoy / glow-collector station
- Filter Plant (resource production building)
- Defense tower: Anglerfish Tower, Coral Barrier, Electric Eel Trap (3
  upgrade stages each)
- Decoration objects (kelp bundles, shell lanterns, crystal clusters) —
  for the cosmetic shop

**Creatures (core content, scalable by rarity):**
- MVP set: 6–8 creature models per zone (Common/Uncommon/Rare/Epic), e.g.
  Glow Jelly, Glow Shrimp, Anglerfish, Bioluminescent Eel, Crystal Kraken.
- Rig requirement: simple idle animation (float/pulse) + attack animation
  for guardian deployment in raids.
- Rarity marked visually via glow color/particle-effect slot (technically:
  an emission-material parameter for script control).

**Raid enemies:**
- 3–4 base monster types per zone (e.g. "Shadow Krakens", "Deep Worm",
  "Trench Warden" as boss) including simple walk/attack animation.

**Character/avatar accessories:**
- Diving suit skin set (several color variants for the cosmetic
  shop/VIP gamepass), breathing apparatus/helmet accessory.

**UI assets:**
- Icon set for the creature codex, rarity frames (Common to Abyssal, 5–6
  tiers), currency symbols (Tide Coin, Abyssal Shard).

**Technical notes for the asset agent:**
- All build parts as separate models with a clearly named PrimaryPart for
  placement logic (snap-to-grid).
- Creatures as a Model with a HumanoidRootPart equivalent (or a simple
  PrimaryPart) for server-side movement control.
- Scale consistent with standard Roblox character size (studs), zones
  should ship with clearly marked SpawnLocation markers.

## 9. Required scripts/systems (brief for the code agent)

**Core systems:**
1. **Plot/data persistence system** (DataStoreService or a ProfileService
   pattern): saves habitat layout, creature inventory, currencies, level,
   prestige state.
2. **Build placement system:** grid-based placement (snap, collision
   check, rotation), purchase/upgrade logic per building.
3. **Idle income/production system:** a server-side tick loop that
   computes resource production per placed building/creature, including
   offline-progress calculation (cap, e.g. max. 4h offline earnings).
4. **Breeding/egg system:** timer-based incubation, genetics/rarity-roll
   logic, creature codex update.
5. **Trench Raid system:** wave spawner (server-side, per player
   instance), enemy AI (simple pathfinding/attack logic), defense-tower
   damage logic, win/loss evaluation, "abduction" mechanic + rescue
   mission flow.
6. **Trading system:** secure 2-player trade with a confirmation dialog,
   server-side validation (anti-dupe/anti-scam), cooldowns.
7. **Progression/level system:** XP calculation, level unlocks, zone
   access unlocking.
8. **Prestige/ascend system:** reset logic with a permanent multiplier, a
   confirmation UI with a clear cost/benefit display.
9. **Monetization integration:** MarketplaceService hooks for gamepasses &
   developer products (including a ProcessReceipt handler, robust against
   double purchases), season-pass tracking system.
10. **Leaderboard system:** OrderedDataStore-based global rankings (zone
    depth, ascends, collection), periodic updates.
11. **Quest/daily system:** daily reset logic, quest-pool rotation, reward
    payout.
12. **Social features:** friend-visit bonus logic (with cooldown/anti-abuse),
    Reef Cluster team system (Phase 2).
13. **Client UI systems:** HUD (currency, XP bar), build menu, creature
    codex UI, raid HUD (wave indicator, HP bars), trade UI, shop UI,
    season-pass UI.
14. **Anti-exploit/server validation:** all purchases, placements, and
    rewards validated server-side (no client trust for currency/inventory).

## 10. MVP scope vs. later expansions

### MVP (Phase 1) – goal: a playable core in one zone, playtestable
- 1 hub world (small) + 2 zones: Sun Zone, Twilight Zone
- Build/placement system with approx. 6–8 building types
- 10–14 creatures (2 zones with 6–8 each, some overlapping by rarity)
- Idle income including offline progress
- Trench Raid system (solo, 3 enemy types, 1 boss)
- Basic trading (without an advanced anti-scam UI, but secure server-side)
- Level/XP system up to level 25
- 3 gamepasses (Auto-Collector, 2x Coins, VIP), 2 developer products
  (Coins, Rescue Token)
- Simple leaderboard (zone depth)
- Daily quests (3 quest types)

### Phase 2 – expansion after a successful soft launch
- Zone 3 (Midnight Zone)
- Prestige/ascend system
- Reef Cluster co-op mode (up to 4 players)
- Season Pass "Tide Pass" (first season)
- Full creature codex with set bonuses
- Expanded cosmetic rotation in the shop
- Mystery Egg developer product (gacha, with compliance check)

### Phase 3 – long-term content & retention
- Zone 4 (Hadal Depths, endgame)
- Asynchronous Reef Raiding between players
- Seasonal live events (e.g. a "Bioluminescence Festival" with
  time-limited creatures)
- Second Habitat Plot feature (gamepass expansion)
- Expanded anti-exploit/telemetry systems, A/B testing for monetization
- Cross-zone boss events (server-wide community goals)

---

*This document serves as the basis for the following agents: the 3D asset
agent (Section 8) and the Luau code agent (Section 9). Both sections are
kept concrete enough to be used directly as a work brief.*
