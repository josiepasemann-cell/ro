# Game Design Document: **Abyssara – Deep Tide Tycoon**

*Stand: 2026-09-24 · Version 1.0*

---

## 1. Titel & Elevator Pitch

**Abyssara – Deep Tide Tycoon**

Baue eine bioluminiszente Unterwasser-Kolonie am Meeresgrund, züchte glühende Tiefsee-Kreaturen für passives Einkommen und verteidige deine Station gegen nächtliche "Trench Raids" – hungrige Tiefseemonster, die deine wertvollsten Kreaturen stehlen wollen. Tauche immer tiefer in neue, gefährlichere Gräben vor, um seltenere Arten und stärkere Verteidigungen freizuschalten.

## 2. Zielgruppe & vergleichbare erfolgreiche Spiele

- **Primäre Zielgruppe:** 8–14 Jahre, mit sekundärer Gruppe 15–25 (Sammler/Idle-Fans). Gemischt Jungen/Mädchen, da Sammel-/Zucht-Mechanik (wie Pet-Sim) breiter anspricht als reines Kampfspiel.
- **Sessionlänge:** kurze aktive Sessions (5–10 Min. Check-in) + Idle-Fortschritt zwischen Sessions – passt zum Mobile/Snack-Play-Verhalten der Zielgruppe.
- **Vergleichbare Hits (Referenz, keine Kopie):**
  - *Grow a Garden* – Idle-Wachstum, Genetik/Mutationen, Trading-Hype.
  - *Steal a Brainrot* – Raid-/Steal-Loop, Basisverteidigung, hohe Concurrent-Peaks.
  - *Pet Simulator 99* – Sammel-Progression, Seltenheitsstufen, Zonen-Freischaltung.
  - *Theme Park Tycoon 2* – klassischer Build-Tycoon-Loop.
  - **Differenzierung:** Unterwasser/Tiefsee-Setting ist auf Roblox stark unterrepräsentiert (visuelle Nische: Biolumineszenz statt Neon-Brainrot-Ästhetik), PvE-Raid-Verteidigung statt reinem Spieler-gegen-Spieler-Diebstahl (kinderfreundlicher, weniger toxisch), plus optionales asynchrones "Reef Raiding" bei anderen Spielern für Meta-Tiefe ohne Pflicht-PvP.

## 3. Kern-Gameplay-Loop

### Minute-zu-Minute
1. Spieler landet auf eigener Habitat-Plattform (persönliche Insel/Grube am Meeresgrund).
2. Sammelt "Glow Spores" / Bioluminiszenz-Ressourcen von platzierten Kreaturen-Ständen (Klicken/Auto-Collect via Gamepass).
3. Füttert & züchtet Kreaturen in Brutbecken (Timer-basiert, wie Ei-Schlüpfen).
4. Kauft/platziert neue Gebäude (Filteranlagen, Lichtbojen, Verteidigungstürme) mit gesammelter Währung ("Tide Coins").
5. Verkauft überschüssige Kreaturen am Handelsdock oder tauscht mit Freunden.

### Session-zu-Session
- Alle ~20–30 Minuten (Echtzeit, auch offline zählend mit Cap) startet ein **Trench Raid**: Wellen von Tiefseemonstern greifen die Station an. Spieler platziert vorher Verteidigungstürme (Anglerfisch-Türme, Korallen-Barrieren) und kann während des Raids aktiv Kreaturen als "Wächter" einsetzen.
- Erfolgreiche Verteidigung = Bonus-Loot (seltene Eier, Tide Coins). Fehlgeschlagene Verteidigung = eine zufällige Kreatur wird "entführt" (kann später gegen Lösegeld/Rettungsmission zurückgeholt werden – Soft-Loss statt Hard-Loss, kinderfreundlich).
- Tägliche Quests ("Fange 3 Anglerfische", "Überlebe 1 Raid ohne Verlust") mit Belohnungstruhen.

### Langzeit-Progression
- **Gräben-System (Trench Depth):** Spieler steigt von "Sonnenzone" (Start) über "Dämmerzone", "Mitternachtszone" bis zur "Hadal-Tiefe" ab. Jede Zone = neue Karte/Biom, neue Kreaturen-Pools, stärkere Raid-Gegner, neue Bauteile.
- **Prestige-System ("Ascend/Resurface"):** Nach Erreichen der tiefsten aktuellen Zone kann der Spieler "auftauchen" und mit einem permanenten Multiplikator (+X% Einkommen) sowie einem kosmetischen Titel/Abzeichen neu in Zone 1 starten – klassische Idle-Prestige-Kurve.
- **Sammelalbum:** Kreaturen-Kodex mit Seltenheitsstufen (Common → Mythic → Abyssal). Vollständige Sets geben permanente Boni.

## 4. Spielmodi / Maps / Level-Struktur

- **Hauptmodus – Habitat-Building (Solo-Instanz, aber sichtbar für Freunde):** Jeder Spieler hat eine eigene, persistente Plot-Insel (server-seitig gespeichert wie bei Tycoon-Spielen), erreichbar über eine zentrale Hub-Welt.
- **Hub-Welt "Tidal Market":** Zentrale Lobby mit Handelsdock (Trading), NPC-Händlern, Leaderboard-Anzeigen, Portalen zu den Trench-Zonen.
- **4 Kern-Zonen (MVP: 2 davon):**
  1. Sonnenzone (Tutorial/Start, Level 1–10)
  2. Dämmerzone (Level 10–25)
  3. Mitternachtszone (Level 25–45, Phase 2)
  4. Hadal-Tiefe (Level 45+, Phase 3, Endgame/Prestige-Zone)
- **Raid-Instanz:** separate, private Server-Instanz pro Spieler (oder Party bei Koop), in der die Trench-Raid-Welle stattfindet – prozedural aus Gegner-Pool der aktuellen Zone zusammengesetzt.
- **Koop-Modus (Phase 2):** Bis zu 4 Spieler können ihre Habitate zu einem "Reef Cluster" verbinden und gemeinsam größere Raids (Boss-Raids) bestehen.

## 5. Monetarisierung

**Gamepasses (einmalig, Robux):**
| Gamepass | Preis (Robux) | Effekt |
|---|---|---|
| Auto-Collector | 149 | Automatisches Einsammeln der Glow Spores ohne Klicken |
| 2x Tide Coins | 349 | Dauerhaft doppelte Währung |
| Extra Habitat-Plot | 199 | Zweites, eigenes Plot (mehr Baufläche) |
| VIP-Taucher | 449 | Exklusiver Skin, tägliche Bonus-Truhe, 1,5x Zucht-Geschwindigkeit |
| Trench Runner | 99 | Schnellere Bewegung/Tauchgeschwindigkeit |

**Entwicklerprodukte (wiederholt kaufbar, Robux):**
| Produkt | Preis (Robux) | Effekt |
|---|---|---|
| 500 Tide Coins | 79 | Direktwährung |
| 3.000 Tide Coins | 399 | Direktwährung (Bulk-Rabatt) |
| Rettungs-Token (entführte Kreatur sofort zurückholen) | 49 | Umgeht Rettungsmission |
| Mystery Egg (zufällige Kreatur, Rarity-Chance) | 89 | Gacha-artiges Sammelelement (mit klar kommunizierten Drop-Chancen, s. Roblox-Richtlinien) |
| Raid-Skip (aktueller Raid wird automatisch "gewonnen" gewertet, 1x/Tag) | 59 | Zeitersparnis |

**Season Pass ("Tide Pass"):** 399 Robux pro Season (6 Wochen), Battle-Pass-artige Free/Premium-Track mit kosmetischen Kreaturen-Skins, exklusiven Baustil-Sets, Bonus-Coins. Kein Gameplay-Vorteil in Premium (nur Kosmetik + kleine Coin-Boosts), um Fairness zu wahren.

**Kosmetik-Shop (rotierend):** Habitat-Deko, Taucheranzug-Skins, Leuchteffekt-Farben für Kreaturen – 25–150 Robux je Item.

## 6. Fortschrittssystem

- **Spieler-Level:** steigt durch XP aus Quests, Raid-Siegen, Zuchterfolgen. Level schaltet Baurezepte und Zonenzugang frei.
- **Währungen:**
  - *Tide Coins* (Hauptwährung, durch Idle-Einkommen/Verkauf) – Baukosten, Zuchtkosten.
  - *Abyssal Shards* (Premium-nah, selten aus Raids/Season Pass) – seltene Kreaturen, Kosmetik.
- **Progression Curve (Richtwert, exponentiell mit Soft-Caps):**
  - Level 1–10: schnelle Freischaltungen (alle 5–10 Min.), Tutorial-Belohnungen hoch.
  - Level 10–25: Kosten x1,15 pro Stufe, Einkommen x1,12 – leichtes Gap, durch Gamepasses/Season Pass abfederbar.
  - Level 25–45: Kosten x1,2, stärkerer Grind, Prestige wird attraktiv.
  - Prestige-Multiplikator: +10% Einkommen pro Ascend, kumulativ, mit sinkendem Grenznutzen ab Ascend 10 (Soft-Cap via Diminishing Returns, z. B. +10%/+10%/+8%/+8%…), um Inflation zu bremsen.
- **Unlocks pro Level (Beispiele):** neues Baumodul (Level 3), zweiter Brutbeckenslot (Level 6), erster Verteidigungsturm (Level 8), Zonenportal Dämmerzone (Level 10).

## 7. Social / Multiplayer-Features

- **Freundesliste-Bonus:** Besuch bei Freunden gibt kleinen Coin-Bonus (Anti-Bot-Maßnahme: Cooldown 20 Min./Freund).
- **Trading-System:** sicherer 2-Spieler-Trade-Dialog am Handelsdock für Kreaturen (mit Bestätigungs-Screen, Robux-Handel ausgeschlossen gemäß Roblox-Richtlinien).
- **Reef Cluster (Teams, Phase 2):** Gruppen von bis zu 4 Spielern für Koop-Boss-Raids, gemeinsames Cluster-Leaderboard.
- **Leaderboards:** globale Bestenlisten für "Tiefste erreichte Zone", "Meiste Ascends", "Seltenste Kreaturensammlung" – sichtbar im Hub.
- **Asynchrones Reef Raiding (Phase 3, optional/PvE-lastig):** Spieler können die KI-Verteidigung eines fremden, "besuchten" Reefs herausfordern (kein direkter PvP-Schaden am Fortschritt des Ziels, nur Kopie/Snapshot-basiert wie bei Clash-of-Clans-artigen Systemen), um Bonusressourcen zu gewinnen.
- **Emotes/Chat-Sticker:** thematische Unterwasser-Emotes (Bubble-Wave, Glow-Dance) als kleine Social-Layer, teils Shop-Items.

## 8. Benötigte 3D-Assets (Auftrag für 3D-Artist-Agent)

**Umgebung / Terrain:**
- Meeresboden-Terrain-Sets pro Zone (4x): Sonnenzone (sandig, hell), Dämmerzone (Felsen, Kelp), Mitternachtszone (dunkle Höhlen, Lavaspalten), Hadal-Tiefe (Abgrund, Kristallformationen).
- Modulare Habitat-Plot-Basis (kreisrunde/sechseckige Plattform, ca. 60x60 Studs, unterteilt in Baufelder-Raster).
- Hub-Welt "Tidal Market": zentrale Marktplatz-Struktur mit Handelsdock, NPC-Ständen, Portal-Toren zu den 4 Zonen.

**Gebäude/Bauteile (modular, platzierbar):**
- Brutbecken (3 Stufen: Basic, Advanced, Master)
- Lichtboje / Glow-Sammler-Station
- Filteranlage (Ressourcen-Produktionsgebäude)
- Verteidigungsturm: Anglerfisch-Turm, Korallen-Barriere, Elektro-Aal-Falle (je 3 Upgrade-Stufen)
- Dekorationsobjekte (Kelp-Bündel, Muschel-Laternen, Kristall-Cluster) – für Kosmetik-Shop

**Kreaturen (Kern-Content, skalierbar nach Seltenheit):**
- MVP-Set: je Zone 6–8 Kreaturen-Modelle (Common/Uncommon/Rare/Epic), z. B. Glühqualle, Leuchtgarnele, Anglerfisch, Biolumineszenz-Aal, Kristallkrake.
- Rig-Anforderung: einfache Idle-Animation (Schweben/Pulsieren) + Angriffsanimation für Wächter-Einsatz im Raid.
- Rarity-Kennzeichnung visuell über Glow-Farbe/Partikeleffekt-Slot (technisch: Emission-Material-Parameter für Skript-Steuerung).

**Raid-Gegner:**
- 3–4 Basis-Monster-Typen pro Zone (z. B. "Schattenkraken", "Tiefenwurm", "Trench-Wächter" als Boss) inkl. simpler Lauf-/Angriffsanimation.

**Charakter/Avatar-Zubehör:**
- Taucheranzug-Skin-Set (mehrere Farbvarianten für Kosmetik-Shop/VIP-Gamepass), Atemgerät/Helm-Accessoire.

**UI-Assets:**
- Icon-Set für Kreaturen-Kodex, Rarity-Rahmen (Common bis Abyssal, 5–6 Stufen), Währungssymbole (Tide Coin, Abyssal Shard).

**Technische Hinweise für den Asset-Agent:**
- Alle Bauteile als separate Modelle mit klar benanntem PrimaryPart für Platzierungslogik (Snap-to-Grid).
- Kreaturen als Model mit HumanoidRootPart-Äquivalent (oder einfaches PrimaryPart) für serverseitige Bewegungssteuerung.
- Skalierung konsistent zu Standard-Roblox-Charaktergröße (Studs), Zonen mit klar abgegrenzten SpawnLocation-Markern liefern.

## 9. Benötigte Skripte/Systeme (Auftrag für Code-Agent)

**Core-Systeme:**
1. **Plot-/Datenpersistenz-System** (DataStoreService oder ProfileService-Pattern): Speichert Habitat-Layout, Kreaturen-Inventar, Währungen, Level, Prestige-Stand.
2. **Bauplatzierungs-System:** Grid-basiertes Placement (Snap, Kollisionsprüfung, Rotation), Kauf-/Upgrade-Logik pro Gebäude.
3. **Idle-Einkommen-/Produktionssystem:** Serverseitiger Tick-Loop, der Ressourcenproduktion pro platziertem Gebäude/Kreatur berechnet, inkl. Offline-Progress-Berechnung (Cap, z. B. max. 4h Offline-Gewinn).
4. **Zucht-/Ei-System:** Timer-basierte Inkubation, Genetik-/Rarity-Roll-Logik, Kreaturen-Kodex-Update.
5. **Trench-Raid-System:** Wellen-Spawner (serverseitig, pro Spieler-Instanz), Gegner-KI (einfache Pathfinding-/Angriffslogik), Verteidigungsturm-Schadenslogik, Erfolg/Niederlage-Auswertung, "Entführungs"-Mechanik + Rettungsmission-Flow.
6. **Trading-System:** Sicherer 2-Spieler-Trade mit Bestätigungsdialog, Server-seitige Validierung (Anti-Dupe/Anti-Scam), Cooldowns.
7. **Progression-/Level-System:** XP-Berechnung, Level-Unlocks, Zonen-Zugangsfreischaltung.
8. **Prestige-/Ascend-System:** Reset-Logik mit permanentem Multiplikator, Bestätigungs-UI mit klarer Kosten/Nutzen-Anzeige.
9. **Monetarisierungs-Integration:** MarketplaceService-Hooks für Gamepasses & Developer Products (inkl. ProcessReceipt-Handler, Robustheit gegen Doppelkäufe), Season-Pass-Tracking-System.
10. **Leaderboard-System:** OrderedDataStore-basierte globale Ranglisten (Zonen-Tiefe, Ascends, Sammlung), periodisches Update.
11. **Quest-/Daily-System:** Tages-Reset-Logik, Quest-Pool-Rotation, Belohnungsausgabe.
12. **Social-Features:** Freundesbesuch-Bonus-Logik (mit Cooldown/Anti-Abuse), Reef-Cluster-Team-System (Phase 2).
13. **Client-UI-Systeme:** HUD (Währung, XP-Leiste), Bau-Menü, Kreaturen-Kodex-UI, Raid-HUD (Wellen-Anzeige, HP-Balken), Trade-UI, Shop-UI, Season-Pass-UI.
14. **Anti-Exploit/Server-Validierung:** Alle Käufe, Platzierungen und Belohnungen serverseitig validiert (kein Client-Trust bei Währung/Inventar).

## 10. MVP-Scope vs. spätere Erweiterungen

### MVP (Phase 1) – Ziel: spielbarer Kern in einer Zone, Playtestable
- 1 Hub-Welt (klein) + 2 Zonen: Sonnenzone, Dämmerzone
- Bau-/Placement-System mit ca. 6–8 Gebäudetypen
- 10–14 Kreaturen (2 Zonen à 6–8, teils überlappend nach Rarity)
- Idle-Einkommen inkl. Offline-Progress
- Trench-Raid-System (Solo, 3 Gegnertypen, 1 Boss)
- Basis-Trading (ohne erweiterte Anti-Scam-UI, aber sicher serverseitig)
- Level-/XP-System bis Level 25
- 3 Gamepasses (Auto-Collector, 2x Coins, VIP), 2 Developer Products (Coins, Rettungs-Token)
- Einfaches Leaderboard (Zonen-Tiefe)
- Tägliche Quests (3 Quest-Typen)

### Phase 2 – Ausbau nach erfolgreichem Soft-Launch
- Zone 3 (Mitternachtszone)
- Prestige-/Ascend-System
- Reef Cluster Koop-Modus (bis 4 Spieler)
- Season Pass "Tide Pass" (erste Season)
- Vollständiger Kreaturen-Kodex mit Set-Boni
- Erweiterte Kosmetik-Rotation im Shop
- Mystery Egg Developer Product (Gacha, mit Compliance-Check)

### Phase 3 – Langzeit-Content & Retention
- Zone 4 (Hadal-Tiefe, Endgame)
- Asynchrones Reef Raiding zwischen Spielern
- Saisonale Live-Events (z. B. "Bioluminiszenz-Festival" mit Zeitlimit-Kreaturen)
- Zweites Habitat-Plot-Feature (Gamepass-Ausbau)
- Erweiterte Anti-Exploit-/Telemetrie-Systeme, A/B-Testing für Monetarisierung
- Cross-Zone-Boss-Events (Server-weite Community-Ziele)

---

*Dieses Dokument dient als Grundlage für die nachfolgenden Agenten: den 3D-Asset-Agent (Abschnitt 8) und den Luau-Code-Agent (Abschnitt 9). Beide Abschnitte sind so konkret gehalten, dass sie direkt als Arbeitsauftrag verwendet werden können.*
