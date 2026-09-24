# Live-Event-System

*Umsetzung von `docs/content-update-1.md`, Abschnitt 1 ("Rotating events")
+ 7b. Betrifft alle sechs 12h-Events: Toxic Tide, Spooky Tide, Bioluminescent
Bloom, Frozen Current, Volcanic Vent, Treasure Tide.*

## Wie es funktioniert

**Zeitplan.** `src/shared/LiveEventConfig.lua` definiert `EVENT_ORDER` (6
Events) und `SLOT_SECONDS = 43200` (12h). `GetActiveEventId(unixTimeUtc)`
ist reine, deterministische Modulo-Arithmetik auf `os.time()`
(Epoch-Sekunden, bereits UTC) - jeder Server der Welt berechnet unabhängig
denselben Slot, ohne DataStore oder Cross-Server-Nachrichten. Es gibt
**keine Ruhe-Lücke**: der nächste Slot beginnt exakt, wenn der vorherige
endet.

**Server-Autorität.** `src/server/LiveEventService.lua` ist die einzige
Instanz, die den aktuellen Slot anwendet:
- Tweent `Lighting.Ambient/OutdoorAmbient/FogColor/FogEnd` beim Wechsel
  (4s, `TweenService`), aktualisiert eine Partikel-Stimmung am Hub.
- Verwaltet je Spieler die Event-Währungsbilanz (`PlayerDataService.
  LiveEventState.Currency`) und den 3-Schritte-Quest-Fortschritt
  (`LiveEventState.Quest`) - **beide setzen sich bei jedem Slot-Wechsel
  automatisch auf 0/leer zurück** (Fairness-Regel: Event-Ids UND der
  Slot-Start-Zeitstempel werden verglichen, sodass auch dieselbe Event-Art 3
  Tage später wieder bei 0 startet).
- Validiert Event-Shop-Käufe (`RequestPurchaseShopItem`) und Quest-Claims
  (`RequestClaimEventQuest`) komplett serverseitig - der Client kann nur
  Absichten äußern, nie Preise/Fortschritt vortäuschen.
- Verdient Event-Währung ausschließlich über die bestehenden `GameEvents`-
  Hooks (`SporeDelivered`, `RaidWon`, `BreedingCompleted`) - kein
  gestreuter Aufruf in anderen Services nötig.

**Modifikatoren.** Andere Services fragen den aktiven Event-Zustand an der
Stelle ab, wo sie ihn brauchen (nie wird `RaidConfig`/`BuildingConfig`/
`BreedingConfig` selbst verändert):
- `LiveEventService.GetModifier(key, default)` - roher Zugriff auf
  `EVENTS[aktivesEvent].Modifiers[key]`.
- `LiveEventService.GetBuildingIncomeMultiplier(buildingId)` - kombiniert
  globale + gebäudespezifische Einkommens-Modifikatoren, genutzt von
  `IdleIncomeService.computeIncomePerMinute`.
- `BreedingService.RequestStartBreeding` liest `BreedingRareOrBetterBonus`
  (Spooky Tide) und `BreedingIncubationTimeMultiplier` (Bloom).
- `RaidService` liest `RaidIntervalMultiplier`/`RaidVictoryCoinMultiplier`
  (Volcanic Vent/Treasure Tide) sowie
  `RaidEnemyMoveSpeedMultiplier`/`RaidEnemyMaxHPMultiplier`/
  `RaidEnemyTransparency`/`RaidEnemyBodyColor` (Gegner-Varianten) - jeweils
  als einzelne, minimale Getter-Aufrufe, siehe Kommentare dort.
- `PickupSpawner` liest `ToxicSporeChance`/`ToxicSporeValueMultiplier`,
  `FrozenSporeChance`/`FrozenSporeValueMultiplier`/`FrozenSporeThawSeconds`
  und `SunkenChestValueTideCoins`/`SunkenChestSpawnIntervalSeconds`.

**Client.** `src/client/EventUIController.client.lua` zeigt ein permanentes
Banner (Name + Farbe + Countdown bis zum nächsten Slot) und ein Panel (Shop/
Quest-Linie/Info), erreichbar über den "Event"-Eintrag in
`MainMenuController` (Taste `E`). Ein "großer Moment" (`ScreenFX.BigMoment`
+ Toast) läuft bei jedem ECHTEN Slot-Wechsel, nicht beim ersten Laden.

## Ein neues Event hinzufügen

1. In `src/shared/LiveEventConfig.lua`: neue `EventId` zu `EVENT_ORDER`
   hinzufügen (Reihenfolge bestimmt die Rotation) und einen kompletten
   Eintrag in `EVENTS` anlegen (`Lighting`, `Particle`, `Modifiers`,
   `CurrencyId`/`CurrencyDisplayName`/`CurrencyGlyph`,
   `EarnPerGlowSpore`/`EarnPerRaidWave`/`EarnSpecial`, `Creatures`,
   `ShopItems`, `QuestLine`).
2. Für Shop-Items vom Typ `"CreatureEgg"`: `CreatureId` muss in `Creatures`
   auftauchen (liefert die `Rarity` für `PlayerDataService.
   AddCreatureToInventory`). Die Kreatur muss nach der Fairness-Regel
   (Abschnitt 1.2) IMMER über ein Event-Ei mit der freien Event-Währung
   erhältlich sein, nie Robux-only.
3. Für Modifikatoren, die ein anderer Service (IdleIncomeService/
   BreedingService/RaidService/PickupSpawner) auswerten soll: Schlüsselname
   in `Modifiers` wählen und an der jeweiligen Verbrauchsstelle per
   `LiveEventService.GetModifier("DeinSchlüssel", default)` abfragen -
   NICHT die Basis-Configs selbst verändern.
4. Falls das Event einen server-getakteten Spezial-Effekt braucht (wie
   Volcanic Vents Vent-Puls oder Spooky Tides Ghost Ship): einen Fall in
   `LiveEventService.startSpecialLoop` ergänzen.
5. 3D-Modelle/Deko/Pickups gemäß `assets/models/README.md` bauen lassen -
   `LiveEventService`/`PickupSpawner` warnen (statt zu crashen), falls ein
   Modell fehlt, und fallen defensiv auf einen neutralen Zustand zurück
   (z. B. normale Glow Spore statt Event-Variante).

## Studio-Testschalter

**Nur in Studio-Playtests** (`RunService:IsStudio() == true` - in einem
veröffentlichten Spiel ist das immer `false` und das Attribut wird komplett
ignoriert) kann ein Event erzwungen werden, ohne 12h zu warten:

```lua
-- In der Studio-Command-Bar oder einem Test-Script:
workspace:SetAttribute("ForceEvent", "VolcanicVent") -- einer der 6 EventId-Strings
-- Zum Zurücksetzen auf den normalen, deterministischen Zeitplan:
workspace:SetAttribute("ForceEvent", nil)
```

`LiveEventService` prüft das Attribut alle 5s (`EVENT_CHECK_INTERVAL_SECONDS`)
und wechselt bei Bedarf sofort (getweent) auf das erzwungene Event -
Währung/Quest-Fortschritt setzen sich dabei wie bei einem echten
Slot-Wechsel zurück (siehe Fairness-Regel oben).
