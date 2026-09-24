# Monetarisierungs-Setup – Abyssara: Deep Tide Tycoon

Diese Anleitung richtet sich an die Spielbetreiberin (nicht an Entwickler:innen)
und beschreibt Schritt für Schritt, wie die echten Robux-Produkt-IDs auf
roblox.com angelegt und ins Projekt eingetragen werden. Der komplette
Code funktioniert bereits VORHER (alle IDs stehen aktuell als Platzhalter
`0` in `src/shared/ShopConfig.lua`) – Kauf-Buttons bleiben bis zum Eintragen
der echten IDs serverseitig deaktiviert, es gibt keinen Absturz.

## 1. Voraussetzungen

- Das Spiel muss mindestens einmal veröffentlicht sein (auch als "Nur für
  mich"/Privat reicht), damit auf roblox.com/create Gamepasses/Entwickler-
  produkte für die passende **Universe/Place-ID** angelegt werden können.
- Zugriff auf das Roblox-Konto, dem das Spiel gehört (bzw. Creator-Hub-
  Zugriff bei einer Gruppe).

## 2. Gamepasses anlegen

Für jeden der folgenden 5 Gamepasses:

1. Auf [create.roblox.com](https://create.roblox.com) → dein Spiel öffnen →
   "Monetarisierung" → "Passes" → "Pass erstellen".
2. Name, Beschreibung und ein Icon-Bild hochladen (siehe Tabelle unten für
   den vorgeschlagenen Namen/Preis – Icons sind aktuell überall
   `rbxassetid://0`-Platzhalter im Code und können frei gewählt werden,
   idealerweise passend zum 3D-/UI-Asset-Stil des Spiels).
3. Preis in Robux setzen (siehe Tabelle).
4. Nach dem Speichern zeigt Roblox eine **Pass-ID** (eine Zahl) an – diese
   in `src/shared/ShopConfig.lua` im jeweiligen Eintrag unter `Id = 0`
   eintragen (die `0` durch die echte Zahl ersetzen).

| ShopConfig-Key | Name | Preis (Robux) | GDD-Effekt |
|---|---|---|---|
| `AutoCollector` | Auto-Collector | 149 | Verlängertes Offline-Einkommens-Cap (siehe Abweichung unten) |
| `DoubleCoins` | 2x Tide Coins | 349 | Dauerhaft doppelte Tide Coins (Idle + Raid-Belohnung) |
| `ExtraPlot` | Extra Habitat-Plot | 199 | **Nur Platzhalter, siehe Abweichung unten** |
| `VIPDiver` | VIP-Taucher | 449 | Tägliche Bonus-Truhe, 1,5x Zucht-Geschwindigkeit, Chat-Tag |
| `TrenchRunner` | Trench Runner | 99 | +Bewegungstempo (WalkSpeed) |

## 3. Entwicklerprodukte anlegen

Für jedes der folgenden 6 Entwicklerprodukte:

1. "Monetarisierung" → "Entwicklerprodukte" → "Neues Entwicklerprodukt".
2. Name, Beschreibung, Preis (siehe Tabelle) und Icon festlegen.
3. Die vom Roblox-Assistenten angezeigte **Produkt-ID** in
   `src/shared/ShopConfig.lua` beim jeweiligen Eintrag eintragen (`Id = 0`
   ersetzen).

| ShopConfig-Key | Name | Preis (Robux) | Hinweis |
|---|---|---|---|
| `Coins500` | 500 Tide Coins | 79 | Direktwährung |
| `Coins3000` | 3.000 Tide Coins | 399 | Direktwährung (Bulk-Rabatt) |
| `RescueToken` | Rettungs-Token | 49 | Entführte Kreatur sofort zurückholen |
| `MysteryEgg` | Mystery Egg | 89 | **Gacha – siehe Compliance-Hinweis unten** |
| `RaidSkip` | Raid-Skip | 59 | Aktuellen Raid sofort gewinnen (1x/Tag) |
| `InstantBreeding` | Zucht sofort abschließen | 39 (Vorschlag) | **Nicht im GDD, siehe Abweichung unten** |

Nach dem Eintragen aller IDs: `default.project.json`/Rojo-Sync bzw. Studio-
Publish erneut ausführen, damit `ShopConfig.lua` mit den echten Werten
live geht.

## 4. Wichtiger Compliance-Hinweis: Mystery Egg ("Paid Random Items")

Roblox verlangt für Zufalls-Items gegen Echtgeld ("Paid Random Items"):

- **Die Drop-Chancen müssen vor dem Kauf sichtbar sein.** Das ist bereits
  umgesetzt: `ShopService.GetCatalog` liefert für das `MysteryEgg`-Produkt
  ein `Odds`-Feld mit den exakt gleichen Wahrscheinlichkeiten wie beim
  Gratis-Gacha-Weg (`GachaService.GetOddsTable`).
- **In manchen Ländern (z. B. Belgien, Niederlande) ist der Robux-Kauf von
  Zufalls-Items rechtlich eingeschränkt.** Der Code prüft das automatisch
  über `PolicyService:GetPolicyInfoForPlayerAsync` (`ArePaidRandomItemsRestricted`)
  und sperrt den Kauf-Button für betroffene Spieler (`DisabledReason =
  "PaidRandomItemsRestricted"` im Katalog). Hier ist **keine weitere
  Aktion** von dir nötig – das läuft vollautomatisch.
- Falls Roblox künftig zusätzliche Alterskennzeichnungs- oder
  Store-Vorgaben für dieses Produkt einführt, bitte in den Entwicklerprodukt-
  Einstellungen auf roblox.com prüfen/aktivieren.

## 5. Was du NICHT tun musst

- **Kein Robux-Handel zwischen Spielern:** Es gibt im Code keinen Pfad, über
  den Spieler sich gegenseitig Robux/Gamepässe/Entwicklerprodukte zusenden
  können (GDD Abschnitt 7 – das Trading-System handelt ausschließlich
  Kreaturen, keine Robux-Werte).
- **Kein Item-für-Item-Robux-Produkt je Kosmetik-Artikel:** siehe Abweichung
  unten.

## 6. Abweichungen vom GDD (Abschnitt 5) – bitte lesen

### 6.1 Kosmetik-Shop läuft über Tide Coins/Abyssal Shards, nicht über Robux

Das GDD beschreibt den rotierenden Kosmetik-Shop mit Einzelpreisen von
25–150 Robux pro Artikel. Für **jeden einzelnen** virtuellen Kosmetik-Artikel
wäre dafür ein **eigenes** Entwicklerprodukt auf roblox.com nötig – bei
mehreren Dutzend geplanten Deko-/Farbvarianten ein sehr hoher manueller
Einrichtungsaufwand, und IDs kann kein Code-Agent selbst erzeugen. Der
Kosmetik-Shop (`src/shared/ShopConfig.lua`, `COSMETIC_ITEMS`) verwendet
deshalb die bereits vorhandenen Soft-Währungen (Tide Coins/Abyssal Shards).

**Falls du später doch einzelne Artikel als echte Robux-Käufe anbieten
möchtest:** Lege für den gewünschten Artikel ein Entwicklerprodukt an (wie
in Abschnitt 3 oben), vergib ihm einen neuen `ShopConfig.DevProductKey`
(analog zu den bestehenden Einträgen, `EffectKey` z. B. `"GrantCosmetic"`)
und ergänze in `MonetizationService.applyDevProductEffect` einen Fall, der
`PlayerDataService.AddOwnedCosmetic` aufruft. Der komplette Idempotenz-/
Fallback-Mechanismus greift dann automatisch mit.

### 6.2 Auto-Collector-Gamepass: anderer Effekt als im GDD-Wortlaut

Laut GDD "automatisches Einsammeln der Glow Spores ohne Klicken". Das
bereits bestehende Idle-Einkommen-System (`IdleIncomeService`) schreibt
Einkommen aber **immer schon automatisch** gut – es gibt gar keine
Klick-/Sammel-Aktion, die dieser Pass abschaffen könnte. Damit der Pass
trotzdem einen echten, spürbaren Effekt hat, verlängert er stattdessen das
Offline-Einkommens-Zeitfenster von 4 auf 8 Stunden
(`ShopConfig.AUTO_COLLECTOR_OFFLINE_CAP_SECONDS`). Passt inhaltlich zum
Pass-Namen ("dein Habitat sammelt auch ein, wenn du länger weg bist").

### 6.3 Extra-Habitat-Plot-Gamepass: nur Platzhalter, kein Gameplay-Effekt

`PlotRegistry` (bestehendes Modul, nicht Teil dieses Auftrags) verwaltet
aktuell **genau ein** Plot je Spieler. Ein zweites, unabhängiges Plot
bräuchte eine größere strukturelle Erweiterung (zweiter Welt-Slot, zweites
Baufelder-Set, Anpassungen in `PlacementService`/`RaidService`, die aktuell
überall "ein Plot pro Spieler" annehmen). Der Gamepass wird zuverlässig
erkannt (`MonetizationService.PlayerOwnsGamepass(player, "ExtraPlot")`,
Attribut `OwnsExtraPlotGamepassPlaceholder` am Player), löst aber bewusst
**keine** zweite Plot-Zuweisung aus – kein Absturz, einfach noch kein
Effekt. Sollte künftig ein Mehrfach-Plot-System gebaut werden, ist die
Besitzprüfung bereits fertig integrierbar.

### 6.4 "Zucht sofort abschließen" ist eine Ergänzung zum GDD

Dieses Entwicklerprodukt steht nicht wörtlich in der GDD-Tabelle
(Abschnitt 5), wurde aber explizit für dieses Backend gefordert und war
bereits als Platzhalter-Funktionssignatur in `BreedingService.
RequestInstantComplete` vorbereitet (siehe Kommentar dort:
"für Brutbecken ist ein analoges Produkt plausibel"). Der vorgeschlagene
Preis (39 Robux) ist ein Platzhalter – bitte vor Live-Schaltung selbst
final festlegen (Schritt 3 oben).

## 7. Studio-Testmodus (kein Robux nötig)

Solange keine echten Produkt-IDs eingetragen sind (oder auch danach, zum
schnellen Testen), kann in Roblox Studio (NICHT im Live-Spiel – das ist
serverseitig hart über `RunService:IsStudio()` abgesichert) ein Kauf über
`ShopRemotes.RequestSimulateStudioPurchase` simuliert werden (`kind =
"Gamepass"|"DevProduct"`, `key` = z. B. `"VIPDiver"`). Das löst denselben
Effekt-Code wie ein echter Kauf aus, ohne MarketplaceService/Robux zu
kontaktieren. Ein UI-Agent kann darauf z. B. einen "Studio: Testkauf"-Button
im Shop-Panel aufbauen, der nur sichtbar ist, wenn `RunService:IsStudio()`
auf dem Client `true` liefert (zusätzlich zur serverseitigen Absicherung).

## 8. Remote-API für den UI-Agenten (Kurzreferenz)

Alle Kanäle liegen unter `ReplicatedStorage.ShopRemotes`
(`src/shared/ShopRemotes.lua`) – die ausführliche Payload-Dokumentation
steht direkt im Kopfkommentar dieser Datei.

- `GetShopCatalog` (RemoteFunction) – kompletter Katalog-Snapshot.
- `RequestPromptGamepassPurchase(gamepassKey)` (RemoteEvent).
- `RequestPromptDevProductPurchase(productKey, targetId?)` (RemoteEvent).
- `PurchasePromptRejected` (RemoteEvent, Server → Client) – Ablehnungsgrund
  VOR dem eigentlichen Roblox-Kaufdialog.
- `RequestPurchaseCosmetic(itemId)` / `RequestEquipCosmetic(itemId)`
  (RemoteFunctions).
- `RequestSimulateStudioPurchase(kind, key)` (RemoteEvent, nur Studio).
- `ShopStateChanged` (RemoteEvent, Server → Client) – automatischer
  Katalog-Push nach jeder Zustandsänderung.
