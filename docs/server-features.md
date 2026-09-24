# Server-Features für die Veröffentlichung – Abyssara – Deep Tide Tycoon

Stand: 2026-09-24. Bezug: `docs/game-design-doc.md` Abschnitt 3, 6, 7, 9
(Punkte 10, 11), 10; `docs/held-items.md`; `assets/models/README.md`
Abschnitt "hub".

Dieses Dokument beschreibt die vier neuen Server-Systeme (Tages-Quests +
Tages-Login-Belohnung, Ranglisten, Reisen/Teleports) sowie den zentralen
Ereignis-Hub, der sie mit den bereits bestehenden Gameplay-Services
verbindet. Für den nachfolgenden UI-Agenten: **alle Remotes unten sind
fertig verdrahtet und serverseitig validiert** - es muss ausschließlich
Client-UI darauf aufgesetzt werden, keine weitere Server-Logik.

## 1. Neue Dateien

| Datei | Rolle |
|---|---|
| `src/server/GameEvents.lua` | Zentraler, rein server-interner Ereignis-Hub (BindableEvent-Registry) |
| `src/shared/QuestConfig.lua` | Tages-Quest-Vorlagen-Pool |
| `src/shared/DailyRewardConfig.lua` | 7-Tage-Streak-Belohnungstabelle |
| `src/shared/QuestRemotes.lua` | Remotes für Tages-Quests UND Tages-Login-Belohnung (gebündelt) |
| `src/shared/LeaderboardRemotes.lua` | Remote für Ranglisten-Abfrage |
| `src/shared/TravelRemotes.lua` | Remotes für Hub/Plot/Zonen-Teleport |
| `src/server/QuestService.lua` + `QuestServer.server.lua` | Tages-Quest-Logik + Bootstrap |
| `src/server/DailyRewardService.lua` + `DailyRewardServer.server.lua` | Login-Streak-Logik + Bootstrap |
| `src/server/LeaderboardService.lua` + `LeaderboardServer.server.lua` | Ranglisten-Logik (OrderedDataStore) + Bootstrap |
| `src/server/TravelService.lua` + `TravelServer.server.lua` | Teleport-Logik (ProximityPrompts + Remotes) + Bootstrap |

Rojo-Mapping: unverändert, `default.project.json` bindet `src/server` bzw.
`src/shared` bereits vollständig/flach ein - keine Änderung nötig.

## 2. Zentraler Ereignis-Hub (`GameEvents`)

Statt Quest-/Leaderboard-Aufrufe in jeden Service zu streuen, feuern die
bestehenden Services an ihren bereits vorhandenen Erfolgsstellen (dieselben
Stellen, an denen heute schon `ProgressionService.AwardXP` aufgerufen wird)
genau ein `GameEvents.Fire(eventName, player, payload)`:

| Ereignis | Feuernde Stelle | Payload |
|---|---|---|
| `BuildingPlaced` | `PlacementService.RequestPlace` | `{ BuildingId, PlacementId }` |
| `BreedingCompleted` | `BreedingService.RequestClaimBreeding` / `RequestInstantComplete` | `{ CreatureId, Rarity, PlacementId, Instant? }` |
| `RaidWon` | `RaidService.finishRaid` (live) + `evaluateOfflineRaids` (offline) | `{ WavesCleared, RewardTideCoins?, Offline? }` |
| `RaidLost` | `RaidService.finishRaid` + `evaluateOfflineRaids` | `{ AbductedInstanceId?, Offline? }` |
| `EggOpened` | `GachaService.performRoll` (Gratis- und Robux-Pfad) | `{ Rarity, CreatureId, ResultType, Purchased }` |
| `SporeDelivered` | `PickupSpawner.onDepositTriggered` | `{ Amount }` |
| `CoinsEarned` | `PlayerDataService.AddCurrency` (zentral, nur TideCoins, nur positiver Zuwachs) | `{ Amount, NewLifetimeTotal }` |

`QuestService` und `LeaderboardService` sind die einzigen aktuellen
Abonnenten - keine zirkulären `require`s (GameEvents selbst hat keine
Abhängigkeiten).

## 3. Remote-API für den UI-Agenten

### 3.1 Tages-Quests (`ReplicatedStorage.QuestRemotes`)

- `GetQuestState` (RemoteFunction, keine Payload) →
  `{ DateKey, Quests: { { TemplateId, Description, Target, Progress, Completed, Claimed, RewardTideCoins, RewardAbyssalShards, RewardXP } } }`
- `QuestProgressUpdated` (Server→Client Push) →
  `{ TemplateId, Progress, Target, Completed }`
- `RequestClaimQuestReward` (Client→Server) → Payload `templateId: string`
- `ClaimQuestRewardResult` (Server→Client) →
  `{ Success, Reason?, TemplateId?, RewardTideCoins?, RewardAbyssalShards?, RewardXP?, NewTideCoinBalance? }`
  (`Reason`: `DataNotLoaded` | `UnknownQuest` | `NotCompleted` | `AlreadyClaimed`)

Täglich 3 zufällige Quest-Vorlagen aus einem 4er-Pool (Sporen abgeben,
Zucht abschließen, Raid gewinnen, Gebäude bauen), Reset um 00:00 UTC.

### 3.2 Tages-Login-Belohnung (ebenfalls `QuestRemotes`)

- `GetDailyRewardState` (RemoteFunction) →
  `{ CanClaim, PendingStreakDay, PreviewTideCoins, PreviewAbyssalShards, VipBonusActive, AlreadyClaimedToday }`
- `RequestClaimDailyReward` (Client→Server, keine Payload)
- `DailyRewardClaimed` (Server→Client) →
  `{ Success, Reason?, StreakDay?, RewardTideCoins?, RewardAbyssalShards?, NewTideCoinBalance? }`
  (`Reason`: `DataNotLoaded` | `AlreadyClaimedToday`)

Streak 1–7 steigend, bricht bei verpasstem Tag (zyklisch wieder ab 1).
VIP-Taucher-Gamepass gibt `+50%` auf die TideCoins-Auszahlung DIESES
Systems (`DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER`) - **komplett
unabhängig** von der bereits bestehenden `MonetizationService`-VIP-Truhe
(`Get/SetLastVipChestClaimedDate`), die unverändert weiterläuft. Keine
Datendopplung.

### 3.3 Ranglisten (`ReplicatedStorage.LeaderboardRemotes`)

- `GetLeaderboard` (RemoteFunction) → Payload `category: "Level" | "TideCoins" | "RarestCollection"`
  → `{ Category, Entries: { { Rank, UserId, Name, Score } }, UpdatedAt } | nil`

Kategorien: `Level` (MVP-Proxy für "Tiefste Zone", siehe Begründung im
Kopfkommentar von `LeaderboardService.lua` - ein echtes Zonen-Tiefen-Feld
existiert im MVP noch nicht), `TideCoins` (Lifetime-Summe, NICHT aktueller
Kontostand), `RarestCollection` (Summe der Rarity-Indizes über das
Kreaturen-Inventar). Zusätzlich befüllt der Server direkt eine
`SurfaceGui` am Hub-Objekt `LeaderboardBoard/DisplayPanel` (zyklisch alle
10s zwischen den 3 Kategorien wechselnd) - dafür ist kein Client-Code
nötig.

### 3.4 Reisen/Teleports (`ReplicatedStorage.TravelRemotes`)

- `RequestTravelToPlot` / `RequestTravelToHub` (Client→Server, keine Payload)
- `RequestTravelToZone` (Client→Server) → Payload `zoneId: "SunZone" | "TwilightZone" | "MidnightZone" | "HadalDepths"`
- `TravelResult` (Server→Client) →
  `{ Success, Reason?, Destination?, RequiredLevel?, CurrentLevel? }`
  (`Reason`: `OnCooldown` | `NoPlot` | `UnknownZone` | `LevelTooLow` | `ZoneComingSoon` | `NoCharacter` | `NoHub`)

Dieselbe Logik ist zusätzlich bereits über `ProximityPrompt`s am Hub nutzbar
(kein UI-Code nötig): `PlotGate` → eigener Plot, `Portal_<Zone>` → jeweilige
Zone (prüft `RequiredLevel`-Attribut serverseitig). Die Remotes sind für ein
optionales Schnellreise-UI-Panel gedacht. `SunZone`/`TwilightZone` sind im
MVP tatsächlich begehbar; `MidnightZone`/`HadalDepths` antworten aktuell mit
`Reason = "ZoneComingSoon"`, bis ihre Terrain-Chunks in der Welt platziert
sind (Assets existieren bereits, siehe `assets/models/README.md`).

## 4. Schema-Änderungen (`PlayerDataService`, SchemaVersion 2 → 3)

Rein additive Felder, keine Umbenennung/Aufspaltung - die bestehende
`fillMissing()`-Migration hebt alte Datensätze automatisch an, keine
dedizierte `MIGRATIONS[2]`-Funktion nötig (identisches Muster wie Version
1 → 2):

```lua
QuestState: { DateKey: string?, Quests: { { TemplateId, Target, Progress, Claimed } } }
DailyRewardState: { LastClaimedDate: string?, Streak: number }
Stats: { LifetimeTideCoinsEarned: number }
```

Neue `PlayerDataService`-API: `Get/SetQuestState`, `GetDailyRewardState`,
`SetDailyRewardClaimed`, `GetLifetimeTideCoinsEarned`.
`AddCurrency` schreibt `Stats.LifetimeTideCoinsEarned` bei jedem positiven
TideCoins-Zuwachs fort und feuert `GameEvents.CoinsEarned`.

**Zusätzliche minimale Änderung außerhalb der expliziten Dateiliste:**
`src/shared/ProgressionConfig.lua` bekam zwei neue, rein additive
`XP_REWARDS`-Einträge (`QuestCompleted = 20`, `DailyLoginClaimed = 10`) plus
die entsprechende Typ-Erweiterung - notwendig, damit `QuestService`/
`DailyRewardService` weiterhin ausschließlich über
`ProgressionService.AwardXP` (die einzige Quelle der Wahrheit für XP)
gehen, statt eine zweite XP-Vergabe-Logik zu erfinden.

## 5. Hand-Übergabe (`docs/held-items.md`, Abschnitt 7)

`GachaService.performRoll` und `BreedingService.RequestClaimBreeding` /
`RequestInstantComplete` rufen jetzt `HeldItemService.HoldItem(player,
"Creature", <Live-Kreaturen-Modell aus Workspace.Assets.Creatures>, {
DisplayName = ... })` auf. Automatisches Ablegen nach 6 Sekunden über einen
lokalen `task.delay` (mit Prüfung, ob der Spieler zwischenzeitlich bereits
ein anderes Item hält, um kein bereits neues Item versehentlich abzulegen) -
`HeldItemService.lua` selbst wurde dafür NICHT verändert (nicht Teil der
erlaubten Änderungen). Kein doppeltes Inventar-Buchen: `AddCreatureToInventory`
lief bereits vorher, der Hand-Übergabe-Aufruf bucht nichts erneut, er
verschiebt nur eine geklonte Anzeige-Instanz.

Der "gekauftes Egg wandert in die Hand"-Teilaspekt aus Punkt 5 ist bewusst
NICHT separat umgesetzt: `GachaService.OpenPurchasedEgg` löst intern
denselben `performRoll`-Pfad wie das Gratis-Öffnen aus (kein separater
"Kauf, dann später öffnen"-Zwischenschritt existiert im aktuellen Gacha-
Flow) - die geschlüpfte Kreatur wandert nach BEIDEN Wegen identisch in die
Hand.

## 6. Robustheit

Alle neuen DataStore-Zugriffe (`LeaderboardService`) laufen in `pcall` mit
Retry+Backoff (`withRetry`, analog zu `PlayerDataService`). Kein
`while true do wait() end` ohne `task.wait`. `PlayerRemoving`-Aufräumen in
allen vier neuen Services (Cooldown-/Dirty-Flag-Tabellen). Ranglisten-
Schreiben ist gedrosselt (Dirty-Flag + 90s-Intervall + Stagger zwischen
einzelnen `SetAsync`-Aufrufen), Lesen läuft nur alle 5 Minuten und cached
serverseitig - kein Live-Read pro Client-Anfrage.

## 7. Offene Punkte

- `LeaderboardService`-Kategorie "Level" ist ein dokumentierter MVP-Proxy
  für "Tiefste Zone" - sobald ein echtes Zonen-Tiefen-Feld existiert, muss
  nur `computeScores().Level` ersetzt werden.
- `TravelService` teleportiert nach `MidnightZone`/`HadalDepths` erst,
  sobald deren Terrain-Chunks tatsächlich in der Welt platziert sind
  (aktuell `"ZoneComingSoon"`).
- Kein dediziertes UI für Quests/Tages-Belohnung/Ranglisten/Reisen - alle
  Remotes sind bereit, das Panel-UI folgt im nächsten Schritt durch den
  UI-Agenten.
- Der VIP-Bonus in `DailyRewardService` und die bestehende VIP-Truhe in
  `MonetizationService` sind bewusst zwei getrennte, additive Boni (siehe
  Abschnitt 3.2) - falls das Game-Design das als "zu viel VIP" empfindet,
  wäre eine spätere Konsolidierung ein reiner Balancing-Eingriff, kein
  Architektur-Umbau.
