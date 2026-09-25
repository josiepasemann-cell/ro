# Monetization Setup – Abyssara: Deep Tide Tycoon

This guide is aimed at the game operator (not developers) and describes,
step by step, how to create the real Robux product IDs on roblox.com and
enter them into the project. The full code already works BEFORE this (all
IDs currently sit as placeholder `0` in `src/shared/ShopConfig.lua`) —
purchase buttons stay server-side disabled until the real IDs are entered;
there is no crash.

## 1. Prerequisites

- The game must be published at least once (a "For me"/private publish is
  enough) so that gamepasses/developer products can be created on
  roblox.com/create for the matching **Universe/Place ID**.
- Access to the Roblox account that owns the game (or Creator Hub access
  for a group).

## 2. Create gamepasses

For each of the following 7 gamepasses:

1. On [create.roblox.com](https://create.roblox.com) → open your game →
   "Monetization" → "Passes" → "Create a Pass".
2. Upload a name, description, and icon image (see the table below for the
   suggested name/price — icons are currently `rbxassetid://0` placeholders
   everywhere in the code and can be chosen freely, ideally matching the
   game's 3D/UI asset style).
3. Set the price in Robux (see table).
4. After saving, Roblox shows a **Pass ID** (a number) — enter it in
   `src/shared/ShopConfig.lua` in the matching entry under `Id = 0`
   (replace the `0` with the real number).

| ShopConfig key | Name | Price (Robux) | GDD effect |
|---|---|---|---|
| `AutoCollector` | Auto-Collector | 149 | Extended offline income cap (see deviation below) |
| `DoubleCoins` | 2x Tide Coins | 349 | Permanent double Tide Coins (idle income + raid rewards) |
| `ExtraPlot` | Extra Habitat Plot | 199 | **Placeholder only, see deviation below** |
| `VIPDiver` | VIP Diver | 449 | Daily bonus chest, 1.5x breeding speed, chat tag |
| `TrenchRunner` | Trench Runner | 99 | +Movement speed (WalkSpeed) |
| `SporeMagnet` | Spore Magnet | 199 | Nearby Glow Spores auto-collect (see `docs/abilities.md`) |
| `ExtraBuddySlot` | Extra Buddy Slot | 149 | A second buddy follows on your other side |

## 3. Create developer products

For each of the following 9 developer products:

1. "Monetization" → "Developer Products" → "New Developer Product".
2. Set name, description, price (see table), and icon.
3. Enter the **Product ID** shown by the Roblox assistant in
   `src/shared/ShopConfig.lua` for the matching entry (replace `Id = 0`).

| ShopConfig key | Name | Price (Robux) | Note |
|---|---|---|---|
| `Coins500` | 500 Tide Coins | 79 | Direct currency |
| `Coins3000` | 3,000 Tide Coins | 399 | Direct currency (bulk discount) |
| `RescueToken` | Rescue Token | 49 | Instantly recover an abducted creature |
| `MysteryEgg` | Mystery Egg | 89 | **Gacha – see compliance note below** |
| `RaidSkip` | Raid Skip | 59 | Instantly win the current raid (1x/day) |
| `InstantBreeding` | Instant Breeding Complete | 39 (suggested) | **Not in the GDD, see deviation below** |
| `SporeShower` | Spore Shower | 9 | Instantly spawns 10 Glow Spores on your plot (see `docs/abilities.md`) |
| `TidalSurge` | Tidal Surge | 49 | 30 min 2x idle income/breeding speed, stacks up to 3h |
| `DepthCharge` | Depth Charge | 29 | Grants 3 in-raid "Depth Charge" defense charges |

After entering all IDs: run `default.project.json`/Rojo sync or Studio
publish again so `ShopConfig.lua` goes live with the real values.

## 4. Important compliance note: Mystery Egg ("Paid Random Items")

Roblox requires the following for paid random items ("Paid Random Items"):

- **Drop chances must be visible before purchase.** This is already
  implemented: `ShopService.GetCatalog` returns an `Odds` field for the
  `MysteryEgg` product with the exact same probabilities as the free gacha
  path (`GachaService.GetOddsTable`).
- **In some countries (e.g. Belgium, the Netherlands), Robux purchases of
  random items are legally restricted.** The code checks this
  automatically via `PolicyService:GetPolicyInfoForPlayerAsync`
  (`ArePaidRandomItemsRestricted`) and locks the purchase button for
  affected players (`DisabledReason = "PaidRandomItemsRestricted"` in the
  catalog). **No further action** is needed from you here — this runs
  fully automatically.
- If Roblox introduces additional age-rating or storefront requirements
  for this product in the future, please check/enable them in the
  developer product settings on roblox.com.

## 5. What you do NOT need to do

- **No Robux trading between players:** there is no path in the code that
  lets players send each other Robux/gamepasses/developer products (GDD
  Section 7 — the trading system only trades creatures, no Robux values).
- **No item-for-item Robux product per cosmetic item:** see the deviation
  below.

## 6. Deviations from the GDD (Section 5) – please read

### 6.1 The cosmetic shop runs on Tide Coins/Abyssal Shards, not Robux

The GDD describes the rotating cosmetic shop with individual prices of
25–150 Robux per item. This would require a **separate** developer product
on roblox.com for **every single** virtual cosmetic item — with several
dozen planned decoration/color variants, that's a very high manual setup
effort, and no code agent can create IDs on its own. The cosmetic shop
(`src/shared/ShopConfig.lua`, `COSMETIC_ITEMS`) therefore uses the soft
currencies already in place (Tide Coins/Abyssal Shards).

**If you later want to offer individual items as real Robux purchases
after all:** create a developer product for the desired item (as in
Section 3 above), assign it a new `ShopConfig.DevProductKey` (analogous to
the existing entries, `EffectKey` e.g. `"GrantCosmetic"`), and add a case
in `MonetizationService.applyDevProductEffect` that calls
`PlayerDataService.AddOwnedCosmetic`. The full idempotency/fallback
mechanism then applies automatically.

### 6.2 Auto-Collector gamepass: different effect than the GDD wording

Per the GDD: "automatically collects Glow Spores without clicking." The
existing idle income system (`IdleIncomeService`) already credits income
**automatically at all times** — there is no click/collect action for this
pass to remove. So the pass still has a real, noticeable effect, it
instead extends the offline income window from 4 to 8 hours
(`ShopConfig.AUTO_COLLECTOR_OFFLINE_CAP_SECONDS`). This fits the pass name
thematically ("your habitat keeps collecting even while you're away
longer").

### 6.3 Extra Habitat Plot gamepass: placeholder only, no gameplay effect

`PlotRegistry` (an existing module, not part of this task) currently
manages **exactly one** plot per player. A second, independent plot would
need a larger structural expansion (second world slot, second build-field
set, changes in `PlacementService`/`RaidService`, which currently assume
"one plot per player" everywhere). The gamepass is reliably detected
(`MonetizationService.PlayerOwnsGamepass(player, "ExtraPlot")`, attribute
`OwnsExtraPlotGamepassPlaceholder` on the Player), but deliberately does
**not** trigger a second plot assignment — no crash, just no effect yet.
If a multi-plot system is built in the future, the ownership check is
already ready to integrate.

### 6.4 "Instant Breeding Complete" is an addition to the GDD

This developer product is not literally in the GDD table (Section 5), but
was explicitly requested for this backend and was already prepared as a
placeholder function signature in `BreedingService.
RequestInstantComplete` (see the comment there: "an analogous product is
plausible for the Brood Pool"). The suggested price (39 Robux) is a
placeholder — please finalize it yourself before going live (Step 3
above).

### 6.5 Purchasable abilities/boosts (Spore Shower/Tidal Surge/Depth Charge/Spore Magnet/Extra Buddy Slot)

These 5 products are a later addition on top of the GDD's Section 5 list
(explicitly requested, not a deviation from anything). Full design,
balancing constants, and the Spore Magnet "auto-deliver coins directly"
delivery-behavior decision are documented in `docs/abilities.md` — please
read that before finalizing prices/wording. The suggested prices in the
tables above (9/49/29/199/149 Robux) are placeholders like everywhere else
in this project — finalize them yourself before going live (Step 2/3 above).

## 7. Studio test mode (no Robux needed)

As long as no real product IDs are entered (or even afterward, for quick
testing), a purchase can be simulated in Roblox Studio (NOT in the live
game — this is hard-enforced server-side via `RunService:IsStudio()`) via
`ShopRemotes.RequestSimulateStudioPurchase` (`kind =
"Gamepass"|"DevProduct"`, `key` = e.g. `"VIPDiver"`). This triggers the
same effect code as a real purchase, without contacting
MarketplaceService/Robux. A UI agent can, for example, build a "Studio:
Test Purchase" button in the shop panel on top of this, visible only when
`RunService:IsStudio()` returns `true` on the client (in addition to the
server-side safeguard).

## 8. Remote API for the UI agent (quick reference)

All channels live under `ReplicatedStorage.ShopRemotes`
(`src/shared/ShopRemotes.lua`) — the detailed payload documentation is in
the header comment of that file.

- `GetShopCatalog` (RemoteFunction) – full catalog snapshot.
- `RequestPromptGamepassPurchase(gamepassKey)` (RemoteEvent).
- `RequestPromptDevProductPurchase(productKey, targetId?)` (RemoteEvent).
- `PurchasePromptRejected` (RemoteEvent, Server → Client) – rejection
  reason BEFORE the actual Roblox purchase dialog.
- `RequestPurchaseCosmetic(itemId)` / `RequestEquipCosmetic(itemId)`
  (RemoteFunctions).
- `RequestSimulateStudioPurchase(kind, key)` (RemoteEvent, Studio only).
- `ShopStateChanged` (RemoteEvent, Server → Client) – automatic catalog
  push after every state change.
