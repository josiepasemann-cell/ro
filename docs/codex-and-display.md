# Kreaturen-Plot-Anzeige + Kodex (Content Update 1, Abschnitt 5)

Implementiert docs/content-update-1.md, Abschnitt 5 ("Creature display +
codex") und die dazugehörigen Abschnitte 7b. Macht besessene Kreaturen zum
ersten Mal sichtbar (Plot-Anzeige) und sammelbar (Kodex-UI) statt reiner,
unsichtbarer Inventar-Zeilen.

## Übersicht der neuen Dateien

| Datei | Zuständigkeit |
|---|---|
| `src/shared/CodexRemotes.lua` | RemoteEvent/RemoteFunction-Kanäle für das Kodex-System |
| `src/server/CodexService.lua` | Katalog-Aufbau, Besitz-/Vollständigkeits-Auswertung, Favoriten-Validierung, Zonen-Belohnung |
| `src/server/CodexServer.server.lua` | Dünnes Bootstrap-Skript, verdrahtet CodexRemotes <-> CodexService |
| `src/server/CreatureDisplayService.lua` | Wählt bis zu 6 Kreaturen je Plot aus, spawnt/despawnt sie, gemeinsamer gedrosselter Wander-/Bob-Loop |
| `src/client/CodexUIController.client.lua` | Kodex-Panel (Tabs je Zone + Events, Karten-Raster, Favoriten-Stern, Belohnungs-Abholung) |

Zusätzlich additiv erweitert (kein bestehendes Verhalten verändert):

- `src/server/PlayerDataService.lua`: neues `CodexState` (`Favorites`,
  `ClaimedZoneRewards`, `UnlockedTitles`) + Getter/Setter +
  `GetCodexIncomeMultiplier(player)`. `SCHEMA_VERSION` 3 -> 4 (reine
  Feld-Ergänzung, siehe bestehendes Migrations-Muster im Kopfkommentar).
- `src/client/MainMenuController.client.lua`: neuer "Kodex"-Button
  (Bridge-Event `OpenCodex`, Tastenkürzel `C`).

## 5.1 Plot-Anzeige (`CreatureDisplayService`)

- **Auswahl:** ohne gesetzte Favoriten automatisch die 6 seltensten
  besessenen Kreaturen-INSTANZEN (Gleichstand -> zuletzt erhalten zuerst).
  Mit gesetzten Favoriten (Kodex-UI, max. 6 `CreatureId`-Werte) ERSETZT die
  Favoritenliste die Auto-Auswahl komplett (kein Auffüllen) - je
  favorisierter Art wird die zuletzt erhaltene besessene Instanz gezeigt.
- **Vereinfachung:** Favoriten sind Kreaturen-ARTEN (`CreatureId`), keine
  einzelnen `InstanceId`-Werte - vermeidet Invalidierung bei Entführung/
  Freikauf derselben Instanz und hält `PlayerDataService.CodexState`
  klein. Dokumentiert im Kopfkommentar von `PlayerDataService.CodexState`
  und `CreatureDisplayService`.
- **Bewegung:** EIN gemeinsamer, gedrosselter Loop (`WANDER_TICK_SECONDS =
  0.2`, 5 Hz - bewusst langsamer als `RaidConfig.RAID_TICK_SECONDS`
  0.1s/10 Hz, da reine Ambiente-Bewegung keine Kampf-Präzision braucht)
  bewegt ALLE angezeigten Kreaturen aller Plots in einem Radius von 20
  Studs um den Plot-Mittelpunkt (`PlotRegistry`-Plot, `PrimaryPart
  "PlatformBase"`). Modelle sind vollständig `Anchored` (siehe
  Kreaturen-Buildscripts) und werden rein per `Model:PivotTo()` bewegt -
  keine Physik/Kollision.
- **Server- statt client-getriebene Bewegung (bewusste Entscheidung):**
  Positionen bleiben serverseitige Autorität (Projekt-Grundsatz "kein
  Client-Trust"). Das Budget ist klein (<=6 Kreaturen a 2-15 Parts je
  sichtbarem Plot, 5 Hz Tick), die CPU-Last ist trigonometrisch trivial,
  die Netzwerk-Replikation ist dank `Workspace.StreamingEnabled` auf
  tatsächlich nahe/gestreamte Plots begrenzt und kleiner als die
  Gebäude-Platzierungs-Replikation, die es bereits gibt. Ein Umstieg auf
  client-seitige Interpolation wäre nur bei deutlich höherer Kreaturenzahl/
  -frequenz gerechtfertigt (siehe Kopfkommentar der Datei für die
  ausführliche Begründung).
- **PulseAttachment:** Da `Model:PivotTo()` das gesamte Modell (inkl.
  `Body`/`PulseAttachment`) bewegt, "bobt" das bereits von den
  Buildscripts vorgesehene `PulseAttachment` automatisch mit - kein
  zweiter Animationskanal nötig. Der Bob-Offset selbst ist eine simple
  Sinus-Schwingung (`BOB_AMPLITUDE_STUDS = 0.6`, individuelle Phase/
  Geschwindigkeit je Kreatur, damit sie nicht synchron "pumpen").
- **Handy-Härtung:** jedes `PointLight`/`SpotLight` unter einem geklonten
  Kreaturen-Modell bekommt `Shadows = false` (identische Regel wie
  hub-/terrainweit). Aktuelle Kreaturen-Buildscripts setzen noch keine
  Lichter - reine Zukunftssicherung für künftige Modelle.
- **Aktualisierung bei Änderungen:** reagiert auf `GameEvents`
  (`EggOpened`, `BreedingCompleted`, `RaidLost` fürs Entführungs-Szenario,
  plus das neue, selbst gefeuerte `CodexFavoritesChanged`-Signal aus
  `CodexService`) UND läuft zusätzlich alle 20s ein günstiges
  Sicherheitsnetz-Resync (fängt z. B. Kreaturen-Rettung ab, die aktuell
  kein eigenes `GameEvents`-Signal feuert, ohne `RaidService` anfassen zu
  müssen). `rebuildDisplay` ist ein Diff (nur geänderte Slots werden neu
  gespawnt), kein teurer Full-Respawn.
- **Entkopplung von `CodexService`:** braucht keinen vollen Katalog, nur
  `PlayerDataService.CreatureInventory` (Rarity/AcquiredAt bereits pro
  Instanz vorhanden) + `GachaConfig.RARITY_ORDER`. Kommunikation mit
  `CodexService` läuft ausschließlich über das `GameEvents`-Signal, kein
  gegenseitiges `require`.
- **Lebenszyklus:** `PlotRegistry.AssignPlot` wird idempotent auch von
  diesem Modul selbst aufgerufen (unabhängig von `PlacementServer`s
  eigenem Aufruf - Skript-Ladereihenfolge zwischen Server-Scripts ist in
  Roblox nicht garantiert). Aufräumen bei `Players.PlayerRemoving` über
  `CreatureDisplayService.CleanupPlayer`.

## 5.2 Kodex (`CodexService` + `CodexUIController`)

- **Kein hartkodierter Kreaturen-Katalog:** `CodexService.GetCatalog()`
  liest bei JEDEM Aufruf frisch `Workspace.Assets.Creatures` (Attribute
  `Rarity`/`Zone`/`CreatureName`/optional `Event`, siehe
  `assets/models/README.md`) - neue Kreaturen (die 16 aus Content Update 1,
  von zwei parallelen Agenten gebaut) tauchen automatisch auf, sobald ihr
  Buildscript einmal in Studio ausgeführt wurde. Zusätzlicher Fallback:
  `GachaConfig.CREATURE_POOL`/`BreedingConfig.CREATURE_POOL`-Einträge OHNE
  Live-Modell werden als Katalog-Eintrag mit `Zone = "Unassigned"`
  aufgenommen, damit eine bereits besessene, aber noch nicht gebaute
  Kreatur nicht aus der Vollständigkeits-Zählung fällt - sobald das
  Buildscript läuft, "wandert" der Eintrag automatisch in seine echte
  Zone/Event-Gruppe.
- **Tabs:** SunZone/TwilightZone/MidnightZone/HadalDepths (+ evtl.
  dynamisch entdeckte weitere Zonen, alphabetisch, + `Unassigned` nur
  falls nicht leer) plus EIN fester "Events"-Tab für alle Event-markierten
  Kreaturen (Auftrag: "Event creatures belong in their own codex tab" -
  ein einzelner Tab statt eines Tabs pro Event-Name, einfacher als die
  wörtliche Lesart von content-update-1.md 5.2 und dort ausdrücklich als
  zulässige Vereinfachung benannt).
- **Silhouetten:** kein echtes Icon-Asset nötig - nicht besessene Karten
  zeigen einen dunklen Platzhalter (`Color3.fromRGB(25,25,30)`-Fläche +
  "???"-Text) statt eines `ImageLabel` mit Silhouetten-Icon (das gehört
  zum noch ausstehenden `assets/models/ui/`-Icon-Set eines 3D-/UI-Agenten
  und kann später per einfachem `Image`-Property-Swap ergänzt werden).
- **Karten statt `ViewportFrame`:** rarity-farbige Karten mit
  Namen/Glyphe statt echter 3D-Live-Vorschauen - vermeidet teure
  `WorldModel`/Kamera-Instanzen bei potenziell 30+ gleichzeitig sichtbaren
  Karten (genau die Art Handy-Unfreundlichkeit, die Abschnitt 5.1 explizit
  vermeiden will) und eine noch nicht existierende, garantiert
  kamerafreundliche Vorschau-Pose je Modell.
- **Vollständigkeits-%/Belohnung:** nur für die 4 bekannten Zonen (nicht
  für den Events-Tab). 1000 Tide Coins + Titel `"<Zone> Cataloguer"`
  (persistiert in `CodexState.UnlockedTitles`) + permanenter +2%
  Einkommens-Bonus je Zone (additiv, 4 Zonen = +8%), server-validiert,
  einmal abholbar (`PlayerDataService.IsCodexZoneRewardClaimed`/
  `SetCodexZoneRewardClaimed`).
- **Favoriten:** `CodexService.SetFavorites` validiert Besitz + max. 6 +
  Duplikate serverseitig neu, persistiert über
  `PlayerDataService.SetCodexFavorites`, feuert `GameEvents.Fire(
  "CodexFavoritesChanged", player, {...})` für `CreatureDisplayService`.
- **"Neu laden statt Live-Abo" (bewusste Vereinfachung):** Katalog + Status
  werden bei jedem Öffnen des Panels frisch per `RemoteFunction`
  abgefragt statt über einen dauerhaften Push-Kanal aktuell gehalten zu
  werden - identisches Prinzip zu `RaidUIController`s "Entführte
  Kreaturen"-Panel. Nach erfolgreicher Favoriten-/Belohnungs-Aktion wird
  bei weiterhin offenem Panel automatisch neu aufgebaut.

## Integrations-Hook für andere Systeme (nicht Teil dieses Auftrags)

`PlayerDataService.GetCodexIncomeMultiplier(player)` liefert den fertigen
Multiplikator (`1.0`..`1.08`) aus abgeholten Zonen-Belohnungen. Wird HIER
granted/persistiert, aber NICHT auf die tatsächliche Einkommensberechnung
angewendet - das ist Aufgabe von `IdleIncomeService` (siehe
docs/content-update-1.md 7b, nicht Teil dieses Auftrags), das den Wert
einfach abfragen kann, sobald es selbst erweitert wird.

## Nicht in diesem Auftrag enthalten

- Echte Icon-Assets für Kreaturen-Karten/Silhouetten
  (`assets/models/ui/`, 3D-/UI-Asset-Agent).
- Anwendung von `GetCodexIncomeMultiplier` in `IdleIncomeService`.
- Eine dedizierte Titel-Auswahl-/Anzeige-UI für `UnlockedTitles` (aktuell
  nur Datenhaltung + Toast-Benachrichtigung beim Freischalten).
