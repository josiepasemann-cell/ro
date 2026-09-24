# Release-Checkliste: Abyssara – Deep Tide Tycoon

Stand: 2026-09-24. Der gesamte Code kompiliert (luau-compile) und wurde mit
luau-lsp gegen die Roblox-API geprüft sowie von drei Review-Durchgängen auf
Laufzeitfehler und Exploits durchgesehen. **Er ist aber noch nie in Roblox
Studio gelaufen.** Rechne beim ersten Start mit Fehlern im Output-Fenster.

## 1. Projekt in Studio bringen (Rojo)

1. Rojo installieren (z. B. über die VS-Code-Erweiterung "Rojo" oder `rokit add rojo-rbx/rojo`) und das Rojo-Plugin in Studio installieren.
2. Im Repo-Ordner `rojo serve` starten.
3. In Studio einen neuen, leeren Place öffnen, im Rojo-Plugin auf **Connect** klicken.
   `default.project.json` legt `src/shared` → ReplicatedStorage, `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts.

## 2. Studio-Einstellungen

- **Home → Game Settings → Security → "Enable Studio Access to API Services"** einschalten. Ohne das funktionieren Speichern (DataStore) und Ranglisten in Studio nicht.
- Place einmal veröffentlichen (File → Publish to Roblox), sonst gibt es keine DataStores.
- `Workspace.StreamingEnabled` einschalten (Handy-Performance, siehe `assets/models/README.md`).
- Avatar-Typ R15 (erzwingt `CharacterSetup.server.lua` ohnehin).

## 3. Modelle einmalig bauen

Die Modelle sind Buildscripts, keine fertigen Dateien. Jede Datei in Studio
**im Bearbeitungsmodus** in die Command Bar (View → Command Bar) kopieren
und ausführen. Die Skripte sind wiederholbar, doppeltes Ausführen ersetzt
nur das alte Modell.

1. `assets/models/terrain/HabitatPlotBase.lua` (Plot-Vorlage)
2. `assets/models/buildings/` alle 4 Dateien (Gebäude-Vorlagen)
3. `assets/models/enemies/ShadowKraken.lua` (Raid-Gegner)
4. `assets/models/pickups/GlowSporePickup.lua` (Glow Spore)
5. `assets/models/creatures/` alle 6 Dateien
6. `assets/models/gacha/` alle 7 Dateien (Eier + Öffnungs-Effekt)
7. `assets/models/terrain/` die 4 `*TerrainChunk.lua` (Zonen, bleiben in der Welt)
8. `assets/models/hub/TidalMarketHub.lua` (Hub mit Spawn, Shop-Stand, Portalen)

Danach **speichern bzw. veröffentlichen**. Beim Serverstart verschiebt
`AssetTemplateSetup.lua` die Vorlagen automatisch nach
`ReplicatedStorage.AssetTemplates`. Fehlt ein Modell, gibt es eine Warnung im
Output statt eines Absturzes; ohne Hub landen Spieler an einem Notfall-Spawn.

Beim Serverstart stellt `GachaServer` drei Schau-Eier (Common, Epic, Mythic)
auf die Mystery-Egg-Station im Hub; die übrigen Eier werden zu Vorlagen. Ein
Ei an der Station kostet 350 Tide Coins (`GachaConfig.EGG_COST_TIDE_COINS`).
Die 6 Kreaturen-Modelle bleiben dort stehen, wo ihr Buildscript sie baut
(bei z = 60 nahe dem ersten Plot). Wer sie woanders will, ändert vor dem
Ausführen `ORIGIN` oben in der jeweiligen Datei.

`assets/models/ui/GachaOddsPanel.lua` wird nicht mehr gebraucht (die Odds-UI
entsteht per Code).

## 4. Testen

- **Test → Play**: Output-Fenster (View → Output) auf rote Fehler prüfen. Jeder Fehler dort ist ein echter Bug.
- **Test → Clients and Servers** mit 2 Spielern: jeder bekommt einen eigenen Plot, niemand kann auf fremden Plots bauen, Ranglisten füllen sich.
- **Test → Device** (Geräte-Emulator): mindestens ein Handy hochkant und quer, ein Tablet, Konsole. Prüfen: Menüleiste scrollt, nichts überlappt, Bauen per Tippen, Buttons groß genug.
- Durchspielen: Tutorial → zum Plot reisen → bauen → Glow Spore aufheben und abgeben → Zucht starten und abholen → Mystery Egg → Raid abwarten (25 Min.; zum Testen `RaidConfig.RAID_INTERVAL_SECONDS` kurz stellen und vor dem Release zurücksetzen) → Level-Up → Quests abholen → Shop öffnen.
- Mehrmals rejoinen: Daten bleiben, Tutorial kommt nicht wieder, Tages-Belohnung nicht doppelt.
- Shop in Studio: "Studio: Testkauf"-Buttons simulieren Käufe (live unsichtbar).

## 5. Selbst eintragen

| Was | Wo | Anleitung |
|---|---|---|
| Gamepass- und Produkt-IDs | `src/shared/ShopConfig.lua` | `docs/monetization-setup.md` |
| Sounds (Klick, Toast, Level-Up, Mythic, Musik, Ambiente) | `src/shared/UIKit/SoundConfig.lua` | Eigene oder lizenzierte Sounds hochladen (Creator Dashboard → Audio), `rbxassetid://…` eintragen. Alle IDs sind leer; leere ID = Stille, kein Fehler. |
| Eigene Animationen (optional) | `src/shared/CharacterAnimation/AnimationConfig.lua` | `docs/animations.md` |
| Shop-Icons (optional) | `IconAssetId` in `ShopConfig.lua` | Aktuell zeigt der Shop Neon-Symbole statt Bildern. |

**Den Gamepass "Extra Habitat-Plot" NICHT anlegen**, solange die ID dort auf
0 steht: Das Spiel unterstützt nur einen Plot pro Spieler, Käufer bekämen
nichts.

## 6. Veröffentlichen (Creator Dashboard)

- Fragebogen zur Altersfreigabe / Inhalte ausfüllen (Pflicht für öffentliche Spiele).
- Name, Beschreibung, Icon (512×512), mindestens ein Thumbnail, Genre.
- Unterstützte Geräte: Computer, Handy, Tablet, Konsole. (Konsole nur anhaken, wenn mit Gamepad getestet.)
- Erst privat bzw. für Freunde testen, dann öffentlich schalten.

## 7. Bekannte Lücken

Nicht gebaut, obwohl im Konzept (`docs/game-design-doc.md`):

- **Handel zwischen Spielern**: Das Handelsdock im Hub ist nur Deko.
- **Wächter-Kreaturen im Raid**, weitere Turmtypen (Korallen-Barriere, Elektro-Aal), eigene Gegnermodelle (alle Gegner nutzen die Schattenkrake).
- **Zone 3 und 4** sind begehbar, haben aber noch keine eigenen Kreaturen oder stärkeren Raids.
- **Prestige, Koop-Modus, Season Pass** (Phase 2 laut Konzept).
- Rangliste "Tiefste Zone" nutzt vorerst das Level.
- Mehrere Plots pro Spieler.
