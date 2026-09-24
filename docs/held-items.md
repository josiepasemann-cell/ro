# Items in der Hand – Abyssara – Deep Tide Tycoon

Stand: 2026-09-24. Bezug: `docs/game-design-doc.md` Abschnitt 3 ("Glow Spores
einsammeln"), Abschnitt 8 (Gacha-Eier/Kreaturen-Modelle).

Dieses Dokument beschreibt das server-autoritative "Items in der Hand"-System
und - besonders wichtig für andere, bereits laufende Agenten-Arbeiten - **wo
genau `GachaService`/`BreedingService`/`PlacementService` später andocken
sollen**, ohne dass deren Dateien für dieses Feature selbst angefasst wurden.

## 1. Beteiligte Dateien

| Datei | Rolle |
|---|---|
| `src/shared/HeldItemConfig.lua` | Zentrale Stellschrauben: Trageposen, Halte-Skalierung/-Versatz je Item-Art, Pickup-/Abgabe-Tuning |
| `src/shared/HeldItemRemotes.lua` | `RequestDropHeld` (Client→Server), `HeldItemChanged` (Server→Client) |
| `src/server/HeldItemService.lua` | Autoritative Kern-API: `HoldItem`/`DropHeld`/`GetHeld`/`ConsumeHeld` |
| `src/server/PickupSpawner.lua` | Glow-Spore-Weltpickups je Plot, GlowBuoyStation-Abgabe, Aufräumen bei Drop |
| `src/server/HeldItemServer.server.lua` | Bootstrap/Verdrahtung (Remotes, Join/Leave) |
| `src/client/HeldItemClient.client.lua` | Minimales HUD, "Ablegen"-Aktion (G/Touch/Gamepad), Glow-Effekt |
| `assets/models/pickups/GlowSporePickup.lua` | Buildscript für das Glow-Spore-Weltmodell |

## 2. Öffentliche Server-API (`HeldItemService`)

```lua
local HeldItemService = require(ServerScriptService.HeldItemService)

-- Bringt ein Item sichtbar in die rechte Hand von `player`. Hält der
-- Spieler bereits etwas, wird das zuerst automatisch abgelegt (DropHeld).
local success, instance = HeldItemService.HoldItem(player, itemKind, templateOrModel, {
    CarryPose = nil,       -- optional Override, sonst HeldItemConfig.GetCarryPose(itemKind)
    DisplayName = nil,     -- optional Override, sonst HeldItemConfig.GetDisplayName(itemKind)
    HoldScale = nil,       -- optional Override, sonst HeldItemConfig.GetHoldScale(itemKind)
    GripOffset = nil,      -- optional CFrame-Override, sonst HeldItemConfig.GetGripOffset(itemKind)
    Reparent = false,      -- true = `templateOrModel` DIREKT verschieben statt zu klonen
    DestroyOnDrop = false, -- true = DropHeld zerstört das Item statt es als Welt-Pickup abzulegen
})

-- Legt das aktuell gehaltene Item ab (Spieler-Aktion oder Aufräumen).
-- Standard: Item wird vor dem Charakter in die Welt gelegt, `ItemDropped`
-- feuert (siehe unten).
HeldItemService.DropHeld(player)

-- Schreibgeschützte Momentaufnahme: { ItemKind, Model, DisplayName, CarryPose } | nil
HeldItemService.GetHeld(player)

-- Entfernt das gehaltene Item OHNE Welt-Drop (kein ItemDropped-Event) -
-- für "Verbrauchen" bei einer Abgabe/Turn-in-Aktion. Gibt (itemKind, model)
-- zurück - der AUFRUFER ist danach für `model` verantwortlich (i. d. R.
-- `model:Destroy()`, NACHDEM die Belohnung gewährt wurde).
local itemKind, model = HeldItemService.ConsumeHeld(player)

-- BindableEvent-Signal: (player, model, itemKind, dropWorldCFrame).
-- Feuert NUR bei DropHeld (nicht bei ConsumeHeld). PickupSpawner
-- abonniert dies bereits für "GlowSpore".
HeldItemService.ItemDropped:Connect(function(player, model, itemKind, dropCFrame) ... end)
```

Item-Identität in beiden Fällen (Klonen vs. `Reparent = true`):

- **Klonen (Default):** `templateOrModel` bleibt unangetastet (z. B. eine
  Vorlage aus `ReplicatedStorage.AssetTemplates.*` oder einem Gacha-/
  Zucht-Ergebnis-Modell) - `HoldItem` klont sie, das Original ist danach
  weiterhin für weitere Rolls/Spieler wiederverwendbar.
- **Reparent = true:** `templateOrModel` ist eine bereits existierende,
  einmalige Instanz (z. B. ein Welt-Pickup wie bei `PickupSpawner`), die
  direkt in die Hand wandert statt dupliziert zu werden.

## 3. `CarryPose`-Attribut (Animations-Kontrakt)

`HeldItemService` setzt bei jedem `HoldItem`/`DropHeld`/`ConsumeHeld`:

```lua
character:SetAttribute("CarryPose", "OneHand" | "TwoHand" | nil)
```

Das prozedurale Animationssystem
(`src/shared/CharacterAnimation/ProceduralAnimator.lua`) liest dieses
Attribut bereits selbst aus (`self.Character:GetAttribute("CarryPose")`) und
posiert die Arme entsprechend über `PoseLibrary.CarryOneHand()` /
`PoseLibrary.CarryTwoHand()`. Dieses System muss dafür nichts weiter tun -
reiner Attribut-Contract, keine direkte Kopplung zwischen den Modulen.

Default-Zuordnung (`HeldItemConfig`, per `opts.CarryPose` überschreibbar):

| ItemKind | CarryPose |
|---|---|
| `GlowSpore` | `OneHand` |
| `Egg` | `TwoHand` |
| `Creature` | `TwoHand` |

## 4. Anbringung am Charakter (technisch)

- Griffpunkt: `Attachment "RightGripAttachment"` auf `RightHand` (R15) bzw.
  `Right Arm` (R6-Fallback) - wird verwendet, falls vorhanden (Standard-
  Roblox-Rigs bringen das für Tool-Equip meist bereits mit), sonst
  automatisch angelegt.
- Verbindung: `RigidConstraint` zwischen `RightGripAttachment` (Hand) und
  einem neu angelegten `Attachment "ItemGripAttachment"` auf dem
  `PrimaryPart` des gehaltenen Items (Offset aus `HeldItemConfig.GetGripOffset`).
- Größe: `Model:ScaleTo(HeldItemConfig.GetHoldScale(itemKind))` - Skalierung
  passiert VOR dem Anbringen des `ItemGripAttachment`, die konfigurierten
  Offsets gelten also für die bereits skalierte Halte-Größe.
- Physik: alle `BasePart`s des Items werden `CanCollide = false`,
  `Massless = true`, `Anchored = false` gesetzt - beeinflusst weder die
  Spielerbewegung noch kollidiert es mit anderen Spielern/der Welt.
- `PrimaryPart`-Erkennung: nutzt `Model.PrimaryPart`, falls gesetzt, sonst
  Fallback über die Namenskonvention aus `assets/models/README.md`
  (`"Body"` bei Kreaturen, `"Shell"` bei Gacha-Eiern, `"Base"` bei
  Gebäuden/Pickups).

## 5. Glow-Spore-Weltpickups (`PickupSpawner`)

- Spawnt periodisch (`HeldItemConfig.Pickup.SpawnCheckIntervalSeconds`,
  Default 20s) bis zu `HeldItemConfig.Pickup.MaxPerPlot` (Default 3)
  Glow-Spore-Pickups zufällig verteilt auf der Habitat-Plot-Basis jedes
  Spielers (Performance: harte Obergrenze pro Plot, kein globales Cap
  nötig, da pro-Spieler begrenzt).
- Jedes Pickup trägt `ProximityPrompt "PickupPrompt"` (`HoldDuration` kurz,
  `RequiresLineOfSight = false`) - funktioniert identisch auf PC (Taste),
  Mobile (automatischer Touch-Button) und Konsole (Gamepad-Button), ohne
  plattformspezifischen Code.
- Server validiert bei Auslösung sowohl **Besitz** (`OwnerUserId`-Attribut
  muss dem auslösenden Spieler entsprechen - nur eigene Sporen) als auch
  **Distanz** (zusätzliche Server-Messung zur HumanoidRootPart, unabhängig
  von `ProximityPrompt.MaxActivationDistance`).
- Aufgehoben wird die Spore über `HeldItemService.HoldItem(player,
  "GlowSpore", pickupModel, { Reparent = true })`.
- Fallenlassen (`DropHeld`, z. B. "G"-Taste): `PickupSpawner` abonniert
  `HeldItemService.ItemDropped` und registriert das Item automatisch wieder
  als Welt-Pickup mit neuem `ProximityPrompt` auf dem Plot des Spielers.

## 6. GlowBuoyStation-Abgabe (Bonus-Tide-Coins)

- `PickupSpawner` beobachtet die platzierten Gebäude jedes Spielers
  (`PlotRegistry.GetBuildingsFolder`, KEIN Eingriff in `PlacementService`)
  und bringt an jeder Instanz mit `GetAttribute("BuildingId") ==
  "GlowBuoyStation"` ein `ProximityPrompt "DepositPrompt"` an.
- Auslösen mit gehaltener `GlowSpore` im Gepäck: Server validiert erneut
  Distanz, ruft `HeldItemService.ConsumeHeld(player)`, zerstört das
  konsumierte Modell und gewährt
  `PlayerDataService.AddCurrency(player, "TideCoins",
  HeldItemConfig.Deposit.TideCoinsReward)` (Default 25).
- `PlayerDataService` wird dabei ausschließlich über seine bestehende,
  öffentliche API gelesen/aufgerufen - die Datei selbst wurde nicht
  verändert.

## 7. Künftige Aufrufer (für die parallel arbeitenden Agenten)

Dieses System stellt bewusst eine generische API bereit. Die folgenden
Anknüpfpunkte sind vorbereitet (`HeldItemConfig` kennt bereits `Egg` und
`Creature` als `ItemKind`), aber **nicht selbst implementiert**, da die
zugehörigen Dateien laut Auftrag nicht angefasst werden dürfen:

- **`GachaService.OpenEgg`** (`src/server/GachaService.lua`): Nachdem ein
  Mystery-Egg gewürfelt wurde und der Spieler es "aufnimmt"/anzeigt, könnte
  dort ergänzt werden:
  ```lua
  local HeldItemService = require(ServerScriptService.HeldItemService)
  local eggTemplate = -- passende Vorlage aus ReplicatedStorage.AssetTemplates
  HeldItemService.HoldItem(player, "Egg", eggTemplate)
  ```
  Hinweis: Die Mystery-Egg-Modelle (`assets/models/gacha/MysteryEgg_*.lua`)
  sind laut `assets/models/README.md` aktuell noch reine
  Buildscript-Ergebnisse ohne ReplicatedStorage-Vorlagen-Promotion (wie
  `AssetTemplateSetup` es für Terrain/Buildings/Enemies macht) - eine
  analoge Promotion für `gacha/` wäre die Voraussetzung, bevor
  `GachaService` ein wiederverwendbares Vorlagen-Modell referenzieren kann.
- **`BreedingService.RequestClaimBreeding`**
  (`src/server/BreedingService.lua`): Nach erfolgreichem Abholen einer
  fertig geschlüpften Kreatur (`CreatureId`/`Rarity` bereits bekannt, siehe
  `BreedingIncubation`-Typ in `PlayerDataService`):
  ```lua
  local HeldItemService = require(ServerScriptService.HeldItemService)
  local creatureTemplate = -- passende Kreaturen-Vorlage (siehe assets/models/creatures/*.lua)
  HeldItemService.HoldItem(player, "Creature", creatureTemplate, {
      DisplayName = creatureData.CreatureName,
  })
  ```
- **`PlacementService`** benötigt keine Anbindung - Gebäude werden nicht
  "gehalten", sondern direkt platziert.

In allen Fällen gilt: `HoldItem` klont die übergebene Vorlage automatisch
(kein `Reparent`), das Original bleibt unangetastet und wiederverwendbar für
weitere Spieler/Rolls.

## 8. Client-Feedback (`HeldItemClient`)

- Minimales, isoliertes HUD (kein Abhängigkeit vom parallel entstehenden
  `src/shared/UIKit`) zeigt `"Hältst: <Name> (G zum Ablegen)"`, sobald
  `HeldItemRemotes.HeldItemChanged` `Holding = true` meldet.
- "Ablegen"-Aktion über `ContextActionService:BindAction(..., true,
  Enum.KeyCode.G, Enum.KeyCode.ButtonX)` - der dritte Parameter
  (`createTouchButton = true`) erzeugt automatisch einen Touch-Button auf
  Mobile-Geräten, kein zusätzlicher Code nötig.
- Glow-Effekt (`PointLight` + `ParticleEmitter`) wird über den
  `CollectionService`-Tag `"HeldItem"` an JEDEM sichtbar gehaltenen Item
  angebracht (auch bei anderen Spielern), unabhängig vom HUD/der
  Ablegen-Aktion (die nur für den lokalen Spieler gelten).

## 9. Sicherheit (kein Client-Trust)

- `HeldItemService` ist reine server-interne API (kein `RemoteFunction`
  für den Client) - der Client kann ausschließlich `RequestDropHeld` für
  seinen EIGENEN Charakter auslösen.
- `PickupSpawner` validiert bei jeder `ProximityPrompt.Triggered`-Auslösung
  erneut Besitz (`OwnerUserId`) und Distanz server-seitig, unabhängig von
  den clientseitig sichtbaren Prompt-Parametern.
- Alle Währungsgutschriften laufen ausschließlich über die bestehende,
  geprüfte `PlayerDataService.AddCurrency`-API.
