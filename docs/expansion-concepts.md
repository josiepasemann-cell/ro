# Erweiterungskonzepte: **Abyssara – Deep Tide Tycoon**

*Stand: 2026-09-24 · Version 1.0 · Ergänzung zum Game Design Document (`game-design-doc.md`)*

---

## 0. Zweck & Überblick

Dieses Dokument vertieft die in Abschnitt 10 des Haupt-GDD grob skizzierten Erweiterungen (Phase 2 & Phase 3) zu vollständigen, umsetzbaren Konzepten – jeweils mit Begründung, Gameplay-Mechanik, 3D-Asset-Auftrag und Code-Auftrag, analog zur Detailtiefe von Abschnitt 8/9 des Haupt-GDD. Zusätzlich enthält Abschnitt 3 ("Phase 4 / Zusatzideen") drei neue, bisher nicht erwähnte Erweiterungsvorschläge.

**Referenzierte Kernsysteme des MVP** (siehe Haupt-GDD Abschnitt 9): Plot-/Datenpersistenz, Bauplatzierung, Idle-Einkommen, Zucht-/Ei-System, Trench-Raid-System, Trading, Progression/Level, Monetarisierungs-Integration, Leaderboards, Quest-System, Social-Features, Client-UI, Anti-Exploit. Alle unten stehenden Erweiterungen bauen auf diesen Systemen auf.

### Überblickstabelle

| # | Erweiterung | Phase | Aufwand | Kernnutzen | Hauptabhängigkeiten |
|---|---|---|---|---|---|
| 1 | Mitternachtszone (Zone 3) | 2 | groß | Content/Progression | Zonen-/Raid-System |
| 2 | Prestige-/Ascend-System | 2 | mittel | Retention (Idle-Loop) | Mitternachtszone, Persistenz |
| 3 | Reef Cluster Koop | 2 | groß | Social/Retention | Raid-System, Social |
| 4 | Season Pass "Tide Pass" | 2 | mittel–groß | Monetarisierung (wiederkehrend) | Quest-System, Shop |
| 5 | Kreaturen-Kodex mit Set-Boni | 2 | klein–mittel | Engagement (Completionism) | Kodex, Zucht, Trading |
| 6 | Erweiterte Kosmetik-Rotation | 2 | klein | Monetarisierung, Wiederkehr | Shop-System |
| 7 | Mystery Egg Gacha | 2 | klein–mittel | Monetarisierung | Monetarisierung, Kodex |
| 8 | Hadal-Tiefe (Zone 4, Endgame) | 3 | groß | Endgame-Retention, Whale-Monetarisierung | Prestige, Zone 3, Raid |
| 9 | Asynchrones Reef Raiding | 3 | groß | Engagement, PvP-lite ohne Toxizität | Raid-System, Leaderboard |
| 10 | Saisonale Live-Events | 3 | mittel/Event | Wiederkehr, Marketing | Quest-/Shop-System, Hub |
| 11 | Zweites Habitat-Plot (Ausbau) | 3 | mittel | Monetarisierungs-Leiter | Plot-/Placement-System |
| 12 | Anti-Exploit/Telemetrie/A-B-Testing | 3 | mittel–groß | Wirtschaftsschutz, datenbasierte Optimierung | alle Systeme |
| 13 | Cross-Zone-Boss-Events | 3 | groß | Community/Concurrent-Spikes | Raid, Leaderboard, MessagingService |
| 14 | Symbiose-Fusion-Labor | 4 (neu) | mittel–groß | Engagement, Dupe-Sink, Monetarisierung | Zucht, Kodex |
| 15 | Tiefsee-Aquarium (Schauvitrine) | 4 (neu) | mittel | Social/UGC, virales Marketing | Bau-System, Kodex, Hub |
| 16 | Gezeiten-Allianz (Cross-Promo-Event) | 4 (neu) | mittel (einmalig)/klein (Wdh.) | PR/Discovery, CSR, Neuspieler | Live-Event-Framework, Hub |

---

## 1. Phase 2 – Ausbau nach erfolgreichem Soft-Launch

### 1.1 Mitternachtszone (Zone 3)

**Beschreibung:** Dritte Kern-Zone (Level 25–45), dunkles Höhlen-/Lavaspalten-Biom mit eigenem Kreaturen-Pool, stärkeren Raid-Gegnern und neuen Bauteilen. Bildet den Übergang vom "leichten" MVP-Fortschritt zum mittelschweren Grind, der Prestige attraktiv macht.

**Warum das Spiel bereichert:**
- **Retention:** Neue Zone = klassischer Content-Update-Spike (Wiederkehr ehemaliger Spieler, PR-Anlass für Roblox-Feed/Discovery-Algorithmus).
- **Monetarisierung:** Gate für neue Gamepasses (z. B. "Druckschutz-Ausrüstung") und Kosmetik-Sets; motiviert Robux-Kauf, um den steileren Grind (Kostenkurve x1,2, siehe Haupt-GDD Abschnitt 6) abzufedern.
- **Engagement:** Neue Umweltmechanik hält die Bauplatzierung strategisch relevant statt reiner Wiederholung.

**Mechanik-Details:**
- Neue Ressource **"Druck-Kristalle"**, ausschließlich in Zone 3 abbaubar, Grundzutat für Zone-3-Baurezepte.
- Umweltgefahr **Pressure Damage**: ohne gebauten "Druckstabilisator" verlieren platzierte Kreaturen schrittweise Produktivität (Debuff-Timer) – schafft neuen Baupflicht-Anreiz statt reinem Deko-Ausbau.
- Elite-Modifikatoren bei Raid-Gegnerwellen (z. B. "Panzerung +30%", "Gift-Aura") als Vorstufe zu echten Boss-Mechaniken.
- Zonen-Boss **"Der Tiefenfürst"** als Meilenstein-Encounter (mehrstufiger Kampf, schaltet Zone-3-Abschluss-Truhe frei).

**Neue 3D-Assets (Auftrag 3D-Artist-Agent):**
- Terrain-Set Mitternachtszone: dunkle Höhlenformationen, Lavaspalten-Texturvarianten, spärliche Lichtquellen-Platzierungspunkte.
- Portal-Tor-Modell (Übergang Hub → Zone 3, konsistent mit bestehenden Zonen-Portalen).
- 6–8 neue Kreaturen-Modelle (Rare/Epic/Mythic-Schwerpunkt) inkl. Idle-/Angriffsanimation.
- 3 neue Bauteile: Druckstabilisator (3 Stufen), Lava-Filteranlage, verstärkter Verteidigungsturm-Skin.
- Boss-Modell "Der Tiefenfürst" inkl. mehrphasiger Angriffsanimationen (Vorbereitung, Wutphase, Finisher).
- Partikeleffekte: Dunkelheits-/Biolumineszenz-Kontrast-Beleuchtung, Druckwellen-VFX.

**Neue Skripte/Systeme (Auftrag Code-Agent):**
- Erweiterung Zonen-Freischaltungslogik um Zone 3 (Level-Gate 25, Voraussetzungsprüfung).
- Pressure-Damage-System (Debuff-Tick-Loop pro Gebäude ohne Stabilisator im Radius).
- Neue Gegner-KI-Pattern für Elite-Modifikatoren (Datentabellen-getriebene Modifikator-Zuweisung).
- Boss-Encounter-Skript (State Machine: Phasenwechsel, Angriffsmuster, Loot-Ausschüttung).
- Integration "Druck-Kristalle" in bestehendes Economy-/Bau-Rezept-System.

**Aufwand:** groß. **Abhängigkeiten:** MVP Zonen-/Bauplatzierungs-/Raid-System.

---

### 1.2 Prestige-/Ascend-System ("Resurface")

**Beschreibung:** Nach Erreichen der tiefsten freigeschalteten Zone (initial Mitternachtszone) kann der Spieler "auftauchen": Reset von Level, Coins und Zonenfortschritt gegen einen permanenten Einkommens-Multiplikator plus kosmetische Titel/Abzeichen. Klassische Idle-Prestige-Kurve, die die Progression über den MVP-Horizont hinaus verlängert.

**Warum das Spiel bereichert:**
- **Retention:** Idle-Genre lebt von "einer Ebene höher spielen" – Prestige verhindert Progressions-Stillstand und liefert einen neuen Langzeit-Loop ohne neue Content-Kosten.
- **Engagement:** Skill-Tree-artige Multiplikator-Verteilung gibt strategische Entscheidungen (welcher Boost zuerst?).
- **Monetarisierung (indirekt):** Spieler kaufen eher Zeit-/Boost-Produkte, um schneller zum nächsten Ascend zu kommen ("Raid-Skip", "2x Coins"-Gamepass gewinnen an Wert).

**Mechanik-Details:**
- Neue Prestige-Währung **"Tide Essence"**, ausgezahlt proportional zur erreichten Zonentiefe/Level beim Ascend.
- Permanenter Einkommens-Multiplikator: +10 %/Ascend, mit Diminishing Returns ab Ascend 10 (wie in Haupt-GDD Abschnitt 6 spezifiziert).
- Prestige-Skill-Tree (Nodes: Einkommens-Multiplikator, Zucht-Geschwindigkeit, Raid-Verteidigungsstärke) – Tide Essence wird frei verteilt, respec gegen kleine Coin-Gebühr möglich.
- Kosmetische Ascend-Titel/Abzeichen-Stufen (z. B. "Gezeitenwanderer" ab Ascend 1, "Abgrundmeister" ab Ascend 10) sichtbar im Hub über dem Spieler-Avatar.
- Bestätigungs-UI mit klarer Kosten/Nutzen-Vorschau vor dem Reset (verhindert versehentlichen Verlust).

**Neue 3D-Assets:**
- "Resurfacing"-Übergangseffekt (Bildschirm-VFX: Aufstieg durch Wassersäule, Lichtstrahl-Partikel).
- Ascend-Abzeichen-Icon-Set (5–6 Stufen, konsistent mit bestehendem Rarity-Rahmen-Stil).
- Kosmetische Aura/Trail-Partikeleffekte pro Meilenstein (an Avatar koppelbar).

**Neue Skripte/Systeme:**
- `PrestigeManager`: Reset-Logik (welche Daten bleiben erhalten: Kodex, Kosmetik, Freunde – welche werden zurückgesetzt: Level, Coins, Zonenfortschritt).
- Skill-Tree-Datenstruktur & Persistenz (Node-Zustände, Tide-Essence-Ledger).
- Prestige-Tree-UI (Client) mit Server-Validierung jeder Node-Aktivierung.
- Erweiterung Leaderboard-System um "Meiste Ascends" (bereits als Statistik in Haupt-GDD Abschnitt 7 vorgesehen).
- Anti-Exploit-Prüfung gegen Reset-Abuse (z. B. Cooldown zwischen Ascends, Mindestfortschritt-Gate).

**Aufwand:** mittel. **Abhängigkeiten:** Mitternachtszone (1.1) als Trigger-Punkt, MVP-Datenpersistenz.

---

### 1.3 Reef Cluster Koop-Modus

**Beschreibung:** Bis zu 4 Spieler schließen sich zu einem "Reef Cluster" zusammen, bestreiten gemeinsam größere Boss-Raids, tragen zu einem gemeinsamen Cluster-Projekt-Ressourcenpool bei und teilen sich ein Cluster-Leaderboard.

**Warum das Spiel bereichert:**
- **Social/Retention:** Gruppenverbindlichkeit ("meine Freunde spielen mit") ist einer der stärksten Retention-Hebel in Sammel-/Tycoon-Spielen; senkt Churn, weil Verlassen des Spiels auch die Gruppe im Stich lässt.
- **Engagement:** Cluster-Boss-Raids erfordern Koordination (Verteidigungstürme + Wächter-Zuweisung mehrerer Spieler), erhöht Sessionlänge.
- **Monetarisierung:** Cluster-exklusive Kosmetik (Banner, Founder-Gamepass) und höhere Investitionsbereitschaft durch sozialen Druck ("meine Gruppe braucht bessere Verteidigung").

**Mechanik-Details:**
- Cluster-Erstellung/Beitritt über Hub-UI (Einladungscode oder Freundesliste-Filter), max. 4 Mitglieder, ein "Cluster-Anführer" mit Verwaltungsrechten.
- **Cluster-Projekte:** Gemeinsamer Beitragspool (Tide Coins/Materialien), der bei Erreichen von Schwellenwerten permanente Cluster-Buffs freischaltet (z. B. "+5 % Raid-Verteidigung für alle Mitglieder").
- **Cluster-Boss-Raid** (wöchentlich, terminiert): Instanz mit skaliertem Gegner-Roster proportional zur Clustergröße; jedes Mitglied bringt eigene Verteidigungstürme/Wächter-Kreaturen ein.
- Cluster-Ränge/-Tiers basierend auf kumulativem Beitrag, sichtbar im Cluster-Leaderboard.
- Cluster-Chat-Kanal (moderiert über Roblox TextService-Filter).

**Neue 3D-Assets:**
- Cluster-Hub-Instanz: visuelle Zusammenführung der 4 Plots (oder dedizierte "Cluster-Insel") mit gemeinsamer Infrastruktur (Cluster-Rathaus-Gebäude für Projekt-Beiträge).
- Cluster-Boss-Modell: großer, mehrphasiger Gegner mit Gruppen-Angriffsmustern (AoE-Angriffe, die Koordination erfordern).
- Cluster-Banner/Emblem-Customization-Set (platzierbar am Cluster-Rathaus).
- UI-Icons: Cluster-Rang-Abzeichen, Beitrags-Fortschrittsbalken.

**Neue Skripte/Systeme:**
- `ClusterService`: Datenpersistenz für Gruppenzugehörigkeit, Einladung/Beitritt/Verlassen, Anführer-Rechteverwaltung.
- Matchmaking-/Einladungssystem (Code-basiert + Freundesliste-Integration).
- Cluster-Boss-Encounter-System: Multiplayer-Wellen-Spawner (Erweiterung des bestehenden Trench-Raid-Systems auf mehrere gleichzeitige Spieler-Instanzen in einer Session).
- Cluster-Beitrags-Ledger (serverseitig validierte Ressourcenübertragung, Anti-Dupe).
- Cluster-Leaderboard (OrderedDataStore-Erweiterung).
- Anti-Abuse: Kick-Funktion, Beitragsübertragung bei Anführerwechsel, Schutz vor Cluster-Hopping zur Ressourcenausbeutung.

**Aufwand:** groß. **Abhängigkeiten:** MVP Trench-Raid-System, Social-/Trading-Infrastruktur, Datenpersistenz.

---

### 1.4 Season Pass "Tide Pass" – Season 1

**Beschreibung:** Battle-Pass-artiges System mit Free- und Premium-Track (399 Robux/Season, 6 Wochen Laufzeit), rein kosmetischer Premium-Vorteil (keine Gameplay-Power) plus kleine Coin-Boosts.

**Warum das Spiel bereichert:**
- **Monetarisierung:** Vorhersehbare, wiederkehrende Einnahmequelle (alle 6 Wochen neue Season) mit branchenüblich hoher Konversionsrate bei fairer (nicht Pay-to-Win) Gestaltung.
- **Engagement:** Season-XP-Track motiviert tägliche/wöchentliche Rückkehr unabhängig vom Hauptlevel-Fortschritt.
- **Retention:** Thematische Rotation (neue Kreaturen-Skins, Baustile pro Season) hält den visuellen Content frisch, ohne neue Zonen bauen zu müssen.

**Mechanik-Details:**
- Season-XP als separater Fortschrittsbalken (Quelle: Season-spezifische Dailies/Weeklies, zusätzlich zu regulären Quests).
- 30–50 Tier-Stufen mit Free-Belohnungen (Coins, Standard-Kosmetik) und Premium-Belohnungen (exklusive Kreaturen-Skins, Habitat-Baustil-Sets, Bonus-Coins, Season-exklusiver Titel).
- Catch-up-Mechanik für Späteinsteiger: käufliche XP-Booster (Developer Product), damit auch spät gekaufte Season-Pässe realistisch komplettierbar sind.
- Season-Ende-Zeremonie (kleine UI-Sequenz) mit Zusammenfassung der erspielten Items; exklusive Items werden transparent als "diese Season" gekennzeichnet, keine dauerhafte Fear-of-missing-out-Täuschung.
- Season-Theming-Beispiel Season 1: **"Bioluminiszenz-Erwachen"**.

**Neue 3D-Assets:**
- Season-Pass-UI-Track-Visualisierung (Tier-Leiste, Belohnungs-Icons).
- Exklusives Kosmetik-Set pro Season: 4–6 Kreaturen-Skins + 3–4 Habitat-Deko-Objekte im Season-Theme.
- Season-Banner-/Icon-Art für Hub-Ankündigungstafel.

**Neue Skripte/Systeme:**
- `SeasonPassManager`: Tier-Tracking, Premium-Kaufstatus-Flag, Belohnungsausgabe-Logik.
- Season-Quest-Pool-Rotation (wöchentlich neue Quest-Sets, die Season-XP geben).
- MarketplaceService-Hook für Premium-Pass-Kauf (ProcessReceipt-Erweiterung, robust gegen Doppelkäufe).
- Season-Reset-/Rollover-Logik (Ende Season X → Start Season X+1, nicht-eingelöste Free-Rewards verfallen mit Warnhinweis).
- Analytics-Hook zur Tracking der Pass-Konversionsrate (Grundlage für spätere A/B-Tests, siehe 3.12/2.12).

**Aufwand:** mittel–groß (Erststruktur), danach klein pro weitere Season (v. a. Content-Austausch). **Abhängigkeiten:** MVP Quest-System, Monetarisierungs-Integration.

---

### 1.5 Vollständiger Kreaturen-Kodex mit Set-Boni

**Beschreibung:** Ausbau des MVP-Kodex (reine Sammel-Übersicht) um Familien-/Biom-Sets, deren Vervollständigung permanente passive Boni gewährt (z. B. "+5 % Einkommen in Dämmerzone" bei komplettem Dämmerzonen-Set).

**Warum das Spiel bereichert:**
- **Engagement:** Verstärkt den Kern-Completionism-Loop des Genres (vgl. Pet Simulator 99) – Spieler jagen gezielt fehlende Kreaturen statt zufällig zu sammeln.
- **Monetarisierung:** Treibt Mystery-Egg-Käufe (1.7) an, wenn Spieler gezielt die letzten 1–2 fehlenden Set-Teile jagen ("nur noch 1 fehlt"-Effekt).
- **Retention:** Set-Boni sind permanente, spürbare Fortschrittsziele über den reinen Level-Grind hinaus.

**Mechanik-Details:**
- Set-Definitionen als Datentabelle (Kreaturen gruppiert nach Zone/Familie, z. B. "Dämmerzonen-Fauna", "Aal-Familie").
- Passive Bonus-Anwendung direkt in der Idle-Einkommens-Berechnungspipeline (multiplikativ, gestackt mit Prestige-Multiplikator).
- Kodex-Meilensteine bei 25 %/50 %/75 %/100 % Gesamtvervollständigung schalten Abyssal Shards und ein Sammler-Titel frei.
- "Fehlende Teile"-Hinweis-UI: zeigt an, welche Kreatur noch fehlt und – falls ein Freund sie besitzt – bietet einen Trade-Schnellzugriff (Verknüpfung mit Trading-System).

**Neue 3D-Assets:**
- Erweiterung Kodex-UI-Rahmen um Set-Gruppen-Ansicht (visuelle Gruppierung, Fortschrittsbalken pro Set).
- Set-Completion-Abzeichen-Icons (pro Set-Thema eigenes Icon).
- Optionales Vitrinen-Deko-Objekt ("Kodex-Trophäenregal") als platzierbares Habitat-Item bei 100 %-Abschluss eines Sets.

**Neue Skripte/Systeme:**
- `CodexSetManager`: Set-Zugehörigkeits-Check, Bonus-Berechnung, Persistenz des Vervollständigungsstatus.
- Integration in Einkommens-Berechnung (Erweiterung des Idle-Produktionssystems aus MVP).
- "Fehlendes Teil"-Erkennungslogik + Trade-Hinweis-UI-Anbindung.
- Meilenstein-Trigger-System (Abyssal-Shard-Ausschüttung bei Schwellenwerten).

**Aufwand:** klein–mittel. **Abhängigkeiten:** MVP Kodex-Grundstruktur, Zucht-System, Trading-System.

---

### 1.6 Erweiterte Kosmetik-Rotation

**Beschreibung:** Wöchentlich rotierender Kosmetik-Shop-Bereich mit zeitlich begrenzten Featured-Items, Wishlist-Funktion und Bundle-Rabatten – Ausbau des im MVP bereits vorhandenen statischen Kosmetik-Shops.

**Warum das Spiel bereichert:**
- **Retention:** Konstanter, sanfter Grund zur Rückkehr ("was ist diese Woche neu") ohne aggressives FOMO.
- **Monetarisierung:** Inkrementelle Robux-Umsätze durch Impulskäufe; Wishlist erlaubt kindgerechtes Sparen ("wenn ich Taschengeld/Robux bekomme").
- **Engagement:** Testfeld für Kosmetik-Trends, dessen Daten später ins A/B-Testing-Framework (2.12) einfließen.

**Mechanik-Details:**
- Wöchentlicher Rotationszyklus mit gewichteter Zufallsauswahl aus Item-Pool (verhindert zu häufige Wiederholung gleicher Items).
- Featured-Slot (1–2 Items pro Woche, prominent im Shop-UI hervorgehoben, ggf. leichter Rabatt).
- Wishlist-Funktion: Spieler markieren Wunsch-Items, erhalten Erinnerung bei erneuter Rotation.
- Bundle-Angebote (z. B. 3 zusammengehörige Deko-Items im Paket-Rabatt).

**Neue 3D-Assets:**
- Rotations-Vorlage/-Slot-System (definiert, wie viele Kategorie-Slots pro Woche befüllt werden).
- Startbatch von 20–30 zusätzlichen Kosmetik-Items (Habitat-Deko, Taucheranzug-Skins, Kreaturen-Leuchtfarben) über mehrere Kategorien verteilt.

**Neue Skripte/Systeme:**
- `ShopRotationService`: Zeitplan (wöchentlicher Reset), gewichtete Item-Pool-Auswahl, Wiederholungs-Vermeidung.
- Wishlist-Persistenz (pro Spieler gespeicherte Item-IDs).
- Purchase-Analytics-Hook (welche rotierenden Items konvertieren am besten).

**Aufwand:** klein (System), laufender kleiner Content-Aufwand pro Rotation. **Abhängigkeiten:** MVP Shop-Basis.

---

### 1.7 Mystery Egg Gacha (Compliance-konform)

**Beschreibung:** Vollausbau des im MVP als einfaches Developer Product angelegten Mystery Eggs zu einem regelkonformen Gacha-System mit transparenter Drop-Tabelle, Pity-Mechanik und Duplikatsschutz gemäß Roblox-Richtlinien für Zufallsobjekte.

**Warum das Spiel bereichert:**
- **Monetarisierung:** Stärkster Einzel-Umsatzhebel für Sammler-Zielgruppe – muss aber fair gestaltet sein, um Vertrauen (und damit Langzeit-LTV) nicht zu gefährden.
- **Engagement:** Pity-System sorgt dafür, dass sich auch "Pech-Serien" nie komplett verloren anfühlen, was Frustrations-Churn reduziert.
- **Compliance/Vertrauen:** Roblox verlangt offengelegte Wahrscheinlichkeiten bei virtuellen Zufallsgütern – korrekte Umsetzung schützt vor Plattform-Sanktionen.

**Mechanik-Details:**
- Gewichteter Zufalls-Roll basierend auf veröffentlichter Drop-Tabelle (Rarity-Wahrscheinlichkeiten sichtbar vor Kauf).
- Pity-Counter: garantierter Epic-oder-besser-Drop nach X erfolglosen Eiern (persistiert pro Spieler).
- Duplikatsschutz: doppelte Kreaturen werden automatisch in Tide Coins/Fusions-Katalysatoren (vgl. 3.14) konvertiert statt wertlos zu verpuffen.
- Ei-Öffnungs-Zeremonie (kurze Animation: Schale knackt, Licht-Enthüllung der Kreatur) als kleiner Dopamin-Moment.

**Neue 3D-Assets:**
- Ei-Modell-Varianten je Rarity-Erwartungsstufe (visuelles Schalen-Design unterscheidet sich leicht).
- Öffnungs-VFX (Schalenriss-Partikel, Lichtexplosion, Rarity-farbiger Strahl).
- Odds-Display-UI-Panel (Drop-Tabelle-Anzeige vor Kauf).

**Neue Skripte/Systeme:**
- `GachaService`: gewichteter Roll-Algorithmus, Pity-Tracking, Duplikat-Konvertierungslogik.
- Compliance-Odds-UI-Datenbindung (Anzeige exakt synchron zur Server-Wahrscheinlichkeitstabelle).
- Erweiterung ProcessReceipt-Handler um Gacha-Kauf-Pfad.
- Kauf-/Roll-Historie-Logging (Audit-Fähigkeit bei Support-Anfragen).

**Aufwand:** klein–mittel. **Abhängigkeiten:** MVP Monetarisierungs-Integration, Kreaturen-Kodex (1.5).

---

## 2. Phase 3 – Langzeit-Content & Retention

### 2.8 Hadal-Tiefe (Zone 4, Endgame)

**Beschreibung:** Vierte und tiefste Zone als reines Endgame-Ziel für Spieler mit mehreren Ascends. Kein weiteres Zonen-Level danach – stattdessen wiederholbarer Endgame-Content ("Abyssal Trials") mit eigener Mythic/Abyssal-Kreaturen-Stufe und Endgame-Währung.

**Warum das Spiel bereichert:**
- **Retention (Top-Spieler):** Committed Player brauchen langfristige Ziele jenseits der letzten regulären Zone, sonst churnen gerade die wertvollsten (aktivsten, zahlungsbereitesten) Spieler zuerst.
- **Monetarisierung:** Endgame-Chase-Items sind der klassische Whale-Hebel (hochpreisige, seltene Kosmetik/Boosts für die investierteste Spielerschicht).
- **Marketing:** Visuell beeindruckendstes Biom eignet sich für Trailer/Store-Screenshots und Discovery-Feed.

**Mechanik-Details:**
- Zonenfreischaltung erfordert Mindestanzahl Ascends (z. B. 3+) statt reinem Level – verknüpft Prestige-System direkt mit Endgame-Zugang.
- **Abyssal Trials:** wöchentlich rotierender Modifikator-Raid (z. B. "doppelte Gegnerdichte, +50 % Loot") mit saisonalem Leaderboard-Reset.
- Neue Top-Rarity-Stufen "Mythic" und "Abyssal" exklusiv aus Hadal-Content.
- Neue Endgame-Währung **"Void Pearls"** für exklusiven Void-Tech-Shop (Baustil, Kreaturen-Fütterungs-Boosts).

**Neue 3D-Assets:**
- Hadal-Terrain: Abgrund-Formationen, Kristallcluster, extreme Tiefen-Beleuchtung (bereits in Haupt-GDD Abschnitt 8 grob vorgesehen, hier vollständiger Detailauftrag).
- 3–4 einzigartige Raid-Bosse mit mehrphasigen Angriffsmustern (State-Machine-taugliche Rig-Struktur).
- 8–10 Mythic-/Abyssal-Kreaturen-Modelle mit aufwendigeren Partikel-/Emission-Effekten.
- Endgame-Bauteil-Set im "Void-Tech"-Look (futuristisch/kristallin, abgegrenzt vom organischen Stil früherer Zonen).
- Void-Pearl-Währungssymbol.

**Neue Skripte/Systeme:**
- Zone-4-Freischaltungs-Gate (Ascend-Zähler-Prüfung statt reinem Level-Check).
- `AbyssalTrialsService`: wöchentliches Modifikator-Rotationssystem, saisonales Leaderboard mit Reset-Job.
- Void-Pearl-Economy (Gewinn-/Ausgabe-Logik, Shop-Anbindung).
- Boss-Encounter-Skripte (Mehrphasen-State-Machine, wiederverwendbar aus 1.1-Bossmuster, aber komplexer).

**Aufwand:** groß. **Abhängigkeiten:** Prestige-System (1.2), Mitternachtszone (1.1), Trench-Raid-System.

---

### 2.9 Asynchrones Reef Raiding

**Beschreibung:** Spieler können die KI-gesteuerte Verteidigungs-Kopie ("Snapshot") eines fremden, bereits besuchten Reefs herausfordern, um Bonusressourcen zu erbeuten – ohne echten, permanenten Schaden am Zielspieler (kein direkter PvP-Verlust, Clash-of-Clans-artiges Prinzip, aber kinderfreundlich entschärft).

**Warum das Spiel bereichert:**
- **Engagement:** Gibt investierten Verteidigungstürmen einen dauerhaften Zweck über die eigenen Raids hinaus; "Energie"-Mechanik (begrenzte tägliche Angriffe) schafft mehrfache Rückkehr-Anlässe pro Tag.
- **Kein Toxizitäts-Risiko:** Da nur ein Snapshot angegriffen wird (kein Echtzeit-Verlust beim Ziel), bleibt die Zielgruppe 8–14 geschützt vor Frustration/Mobbing-Dynamiken.
- **Monetarisierung:** Energie-Auffüll-Produkt (Robux) für Vielspieler, die mehr Angriffe pro Tag wollen.

**Mechanik-Details:**
- **Snapshot-Erzeugung:** Server erfasst periodisch (z. B. alle 30 Min.) den Verteidigungs-Loadout eines Spielers (Turmplatzierung, zugewiesene Wächter-Kreaturen) als angreifbaren Zustand.
- **Angriffs-Simulation:** deterministische, serverseitige Kampfberechnung (Angreifer-Wächter vs. Snapshot-Verteidigung), Ergebnis als kurze Replay-Sequenz dargestellt (Wiederverwendung bestehender Raid-Modelle/-Animationen).
- **Energie-System:** begrenzte tägliche Angriffsversuche (regeneriert über Zeit oder per Developer Product sofort auffüllbar).
- **Schutz-Schild:** nach erfolgreichem Angriff auf ein Ziel erhält dieses temporären Schutz vor erneuten Angriffen (Anti-Farming).
- Belohnungsskalierung nach Zonentiefe/Level des Ziels (fairere Matchmaking-Brackets).

**Neue 3D-Assets:**
- Ziel-Auswahl-UI (Karten-/Listen-Ansicht angreifbarer Reefs).
- Schutz-Schild-Sichteffekt (Visueller Indikator am Plot, wenn frisch angegriffen/geschützt).
- Rang-/Trophäen-Abzeichen-Icons für Reef-Raiding-Erfolge.

**Neue Skripte/Systeme:**
- `SnapshotService`: periodische Erfassung des Verteidigungszustands pro Spieler.
- `AsyncRaidEngine`: deterministische Kampfsimulation server-seitig (fair, nicht client-manipulierbar).
- Matchmaking-Logik (Ziel-Vorschläge nach Level-/Zonentiefe-Bracket).
- Energie-Regenerations-System + Developer-Product-Anbindung für Sofort-Auffüllung.
- Schutz-Timer/Schild-Logik, Revenge-Queue (Option, zuletzt erfolgreiche Angreifer zurückzufordern).
- Anti-Abuse: Verhinderung von wiederholtem Farmen desselben schwachen Ziels (Cooldown pro Zielpaar).

**Aufwand:** groß. **Abhängigkeiten:** MVP Trench-Raid-System, Zonen-Tiefe-Leaderboard, Datenpersistenz.

---

### 2.10 Saisonale Live-Events

**Beschreibung:** Zeitlich begrenzte Themen-Events (Beispiel: "Bioluminiszenz-Festival") mit exklusiven Kreaturen, Event-Währung, Quest-Kette und Hub-Reskin – wiederverwendbares Event-Framework für beliebig viele zukünftige Events.

**Warum das Spiel bereichert:**
- **Wiederkehr/Marketing:** Regelmäßige, ankündigungsfähige Anlässe (Social-Media-Posts, Roblox-Event-Feed) ohne die Kosten einer neuen Dauerzone.
- **Monetarisierung:** Event-exklusiver Mini-Shop und optionaler Event-Pass erzeugen zusätzliche, zeitlich fokussierte Kaufanreize.
- **Engagement:** Frischt das Spielgefühl regelmäßig auf, ohne Kernsysteme zu verändern – ideal, um Spieler zwischen großen Content-Updates bei Laune zu halten.

**Mechanik-Details:**
- `EventScheduler` aktiviert/deaktiviert einen definierten Content-Pack (Dauer i. d. R. 2–3 Wochen): Event-Währung, Event-Shop, Event-Quest-Kette, Hub-Dekoration.
- Event-exklusive Kreaturen nur während des Zeitfensters erhältlich (spätere faire "Vault"-Wiederveröffentlichung möglich, um harte FOMO-Kritik zu vermeiden – ethische Kommunikation empfohlen).
- Optionaler kompakter Event-Pass (Mini-Season-Pass-Variante, wiederverwendet Season-Pass-Infrastruktur aus 1.4).
- Hub-Welt erhält temporäres visuelles Reskin (Banner, Lichterketten, thematische Deko) für Event-Atmosphäre.

**Neue 3D-Assets:**
- Event-Deko-Set für Hub (Banner, Laternen, thematische Overlay-Objekte) – pro Event neu, aber wiederverwendbares Platzierungsraster.
- 2–3 Event-exklusive Kreaturen-Modelle pro Event.
- Event-Währungssymbol, Event-Quest-UI-Skin.

**Neue Skripte/Systeme:**
- `EventScheduler`: Start-/End-Zeitpunkte, Feature-Toggles, automatisches Hub-Reskin-Laden.
- Event-Währungs-Ledger (separat von Hauptwährungen, verfällt oder konvertiert nach Event-Ende gemäß Design-Entscheidung).
- Event-Quest-Ketten-System (Wiederverwendung Quest-Engine aus MVP, erweitert um Event-Flag).
- Event-Shop (temporär eingeblendeter Shop-Bereich).
- Telemetrie zur Event-Teilnahmequote (Grundlage für künftige Event-Optimierung).

**Aufwand:** mittel für Framework-Erstaufbau, danach klein pro einzelnem Event. **Abhängigkeiten:** MVP Quest-/Shop-System, Hub-Welt.

---

### 2.11 Zweites Habitat-Plot (Ausbau)

**Beschreibung:** Vertiefung des bereits im MVP als Gamepass angelegten zweiten Plots: eigenes Spezial-Biom (z. B. "Kelp-Garten") mit einzigartigen Zucht-/Produktionsboni, Plot-Wechsel-UI und Ressourcentransport zwischen Plots – als Grundlage für eine erweiterbare Plot-Monetarisierungsleiter (Plot 2, 3, 4 …).

**Warum das Spiel bereichert:**
- **Monetarisierungsleiter:** Jedes weitere Plot ist ein eigenständiger, wiederholbarer Robux-Kaufanreiz analog zu Grundstücks-Erweiterungen in anderen Tycoon-Spielen.
- **Progressions-Frische:** Verhindert Stillstand, sobald Plot 1 "vollgebaut" ist – klassisches Endgame-Problem in Bau-/Tycoon-Spielen.
- **Retention:** Spezial-Biome mit eigenen Boni motivieren strategische Neuplanung statt reiner Kopie des ersten Plots.

**Mechanik-Details:**
- Plot-Auswahl-/Wechsel-UI (Teleport zwischen eigenen Plots, keine Ladepause dank Instanz-Vorab-Laden).
- Plot 2 als eigenständiges Biom mit spezifischem Kreaturen-/Produktions-Bonus (z. B. Zucht-Geschwindigkeit +X % für bestimmte Kreaturenfamilien).
- Inter-Plot-Ressourcentransfer (mit kleiner Gebühr oder Transportzeit, um Plots als komplementär statt redundant zu positionieren).
- Skalierbare Gamepass-Struktur für weitere Plots (Plot 3, 4 als spätere, teurere Stufen – Grundlage bereits mitgebaut).

**Neue 3D-Assets:**
- Neue Plot-Terrain-Variante (z. B. Kelp-Garten-Biom, abweichend von Standard-Habitat-Plattform).
- Plot-Teleport-Portal-Modell (am Hauptplot platziert).
- UI-Icons für Plot-Wechsel-Menü.

**Neue Skripte/Systeme:**
- `MultiPlotDataManager`: Erweiterung des Persistenz-Schemas von einem auf N Plots pro Spieler.
- Plot-Wechsel-/Teleport-Logik (Server-seitige Instanzverwaltung).
- Inter-Plot-Transfersystem (Ressourcenbuchung, Anti-Dupe-Absicherung).
- Gamepass-Hooks für zusätzliche Plot-Stufen (erweiterbar über Konfigurationstabelle statt Hardcoding).

**Aufwand:** mittel. **Abhängigkeiten:** MVP Plot-/Bauplatzierungs-System, Datenpersistenz.

---

### 2.12 Erweiterte Anti-Exploit-/Telemetrie-Systeme, A/B-Testing

**Beschreibung:** Ausbau der MVP-Basisvalidierung um systematische Wirtschafts-Anomalieerkennung, ein A/B-Testing-Framework für Monetarisierungs-/Onboarding-Varianten sowie eine Analytics-Pipeline für datenbasierte Balancing-Entscheidungen.

**Warum das Spiel bereichert:**
- **Wirtschaftsschutz:** Idle-/Sammelspiele sind besonders anfällig für Dupe-Exploits, die bei unentdeckter Ausbreitung die gesamte Wirtschaft (und damit Kaufanreiz) zerstören.
- **Monetarisierung (datenbasiert):** A/B-Tests zu Preispunkten, Angebotsplatzierung und Onboarding-Flow erhöhen die Conversion-Rate messbar, statt auf Bauchgefühl zu vertrauen.
- **Retention:** Frühwarnsystem für Balance-Probleme (z. B. plötzlicher Progression-Stillstand nach einem Update) verhindert stillen Spieler-Abfluss.

**Mechanik-Details:**
- Serverseitige Anomalieerkennung: Vergleich von Ressourcenzuwachsraten gegen erwartete Obergrenzen (Flag statt Auto-Ban, Review-Queue für Moderatoren).
- A/B-Testing-Framework: variantenbasierte Zuteilung pro Spieler (sticky bucketing), z. B. für Preisschilder, Tutorial-Reihenfolge, Shop-Layout.
- Analytics-Event-Pipeline (strukturierte Events für Käufe, Level-Ups, Raid-Ausgänge, Churn-relevante Aktionen).
- Admin-/Balancing-Dashboard (extern oder In-Game-Tool) zur Auswertung.

**Neue 3D-Assets:** minimal – ggf. Icon-Set für internes Admin-Dashboard (kein spielerseitiger Content).

**Neue Skripte/Systeme:**
- `AnomalyDetectionService`: Regelbasierte Erkennung ungewöhnlicher Ressourcen-/Käufer-Muster.
- `ABTestingFramework`: Varianten-Zuteilung, persistente Bucket-Zuordnung pro Spieler, Ergebnis-Tracking.
- Analytics-Event-Pipeline (HttpService-Anbindung an externes Analytics-Backend oder Roblox-eigene Analytics-API).
- Review-/Flag-Queue-Tooling für manuelle Moderationsentscheidungen.
- Dokumentierte Event-Taxonomie (damit alle Systeme konsistent loggen).

**Aufwand:** mittel–groß (durchzieht alle Systeme). **Abhängigkeiten:** praktisch alle bisherigen Systeme (misst/schützt sie).

---

### 2.13 Cross-Zone-Boss-Events (serverweite Community-Ziele)

**Beschreibung:** Ein server-/community-weiter "Weltboss" erscheint nach Ankündigung; alle gleichzeitig aktiven Spieler (unabhängig von ihrer aktuellen Zone) tragen anteilig Schaden bei. Bei Sieg innerhalb des Zeitlimits erhalten alle Teilnehmer gestaffelte Belohnungen plus einen serverweiten Bonus für alle Spieler.

**Warum das Spiel bereichert:**
- **Community/Discovery:** Konzentrierte Spieleraktivität zu angekündigten Zeitpunkten erhöht Concurrent-Player-Zahlen – ein Schlüsselsignal für Roblox' Discovery-Algorithmus (mehr organische Sichtbarkeit).
- **Engagement:** Gemeinschaftliches Erfolgserlebnis ("wir haben es gemeinsam geschafft") stärkt emotionale Bindung stärker als Solo-Content.
- **Marketing:** Livestream-/Screenshot-taugliches Spektakel-Event, gut für Community-Posts und Influencer-Kooperationen.

**Mechanik-Details:**
- Geplanter Boss-Spawn (z. B. wöchentlich, vorab über Hub-Ankündigungstafel + externe Social-Kanäle kommuniziert).
- Globale HP-Leiste, sichtbar für alle Spieler, gespeist aus Schadensbeiträgen unabhängig von Zonen-Zugehörigkeit (Schaden wird nach individueller Spielerstärke skaliert, damit Anfänger nicht wirkungslos sind).
- Bei serverübergreifender Spielerbasis (mehrere parallele Server-Instanzen): Aggregation der Bosswerte über `MessagingService`/DataStore, damit alle Server gemeinsam an einem globalen Ziel arbeiten.
- Belohnungsstaffelung: individueller Beitrag bestimmt persönliche Loot-Stufe, zusätzlicher "Serversieg-Bonus" geht an alle Teilnehmer, auch bei geringem Einzelbeitrag (inklusiv statt exklusiv).

**Neue 3D-Assets:**
- Massiver, einzigartiger Boss pro "Event-Saison" (mehrphasig, deutlich größer als Standard-Raid-Gegner).
- Globale HP-Leisten-UI-Overlay (serverweit sichtbar, dramatische Gestaltung).
- Server-Ankündigungstafel-Modell (Hub-Objekt für Countdown/Status).
- Sieges-Kinematik/VFX (Boss-Niederlage-Sequenz).

**Neue Skripte/Systeme:**
- `WorldBossService`: Spawn-Zeitplan, Zustandsverwaltung, Zeitlimit-Überwachung.
- Beitrags-Tracking-Ledger pro Spieler (serverseitig validiert).
- Cross-Server-Synchronisation der Boss-HP via `MessagingService` (technisch anspruchsvollster Teil – erfordert eigene Architektur-Betrachtung für Konsistenz bei hoher Serveranzahl).
- Gestaffelte Belohnungsausschüttung (individuell + Server-weiter Bonus-Pool).
- Ankündigungs-/Countdown-System (In-Game + Vorbereitung für externe Kommunikation).

**Aufwand:** groß (insbesondere Cross-Server-Synchronisation ist technisch komplex). **Abhängigkeiten:** Trench-Raid-System, Leaderboard-Infrastruktur, Hub-Welt, idealerweise nach Hadal-Tiefe (2.8) für sinnvolle Power-Skalierung der Top-Spieler.

---

## 3. Phase 4 / Zusatzideen (neu, eigene Vorschläge)

Diese drei Konzepte sind im Haupt-GDD noch nicht erwähnt, ergänzen aber die bestehenden Kernsysteme sinnvoll: eine neue Sammel-/Crafting-Mechanik, ein Social-/UGC-Feature und ein Cross-Promotion-/Community-Event-Format.

### 3.14 Symbiose-Fusion-Labor

**Beschreibung:** Ein neues Gebäude ("Fusionskammer") erlaubt das gezielte Verschmelzen zweier Kreaturen zu einer visuell und statistisch einzigartigen **Hybrid-Kreatur** (z. B. Glühqualle + Anglerfisch → "Anglerqualle"), oberhalb der Mythic-Stufe angesiedelt.

**Warum das Spiel bereichert:**
- **Engagement:** Ergänzt den reinen Zufalls-Loop (Zucht, Gacha) um eine strategische, planbare Sammel-Dimension – Spieler können gezielt auf ein Wunsch-Hybrid hinarbeiten statt nur auf Glück zu hoffen.
- **Dupe-Sink:** Gibt doppelten Kreaturen aus Gacha/Zucht (die sonst reinen Verkaufswert haben) einen sinnvollen Verwendungszweck als Fusionsmaterial – reduziert "wertloses Overflow-Gefühl" im Inventar.
- **Monetarisierung:** Fusions-Katalysatoren (Developer Product) sowie ein "Fusion-Slot-Boost"-Gamepass (mehrere gleichzeitige Fusionen) erschließen einen neuen Kaufanreiz für engagierte Sammler.

**Mechanik-Details:**
- Fusion benötigt 2 Basis-Kreaturen + Fusions-Katalysator (Drop aus Raids oder Shop-Kauf) + Inkubationszeit (analog Brutbecken-Timer).
- Erfolgswahrscheinlichkeit abhängig von der Rarity-Kombination der Ausgangskreaturen, mit Pity-Mechanik nach wiederholten Fehlversuchen (verhindert Frustrations-Sackgassen).
- Hybrid-Kreaturen erhalten eine eigene Kodex-Sektion ("Fusions-Register"), separat trackbar von regulären Sets.
- Manche Fusions-Rezepte sind fest definiert (bekannte Kombination = bekanntes Ergebnis), andere teilweise zufällig innerhalb einer Ergebnis-Bandbreite (Überraschungsfaktor bleibt erhalten).

**Neue 3D-Assets:**
- Fusionskammer-Gebäudemodell (3 Ausbaustufen, analog Brutbecken-Progression).
- Fusions-VFX (Licht-Verschmelzungseffekt beim Abschluss).
- 10–15 Hybrid-Kreaturen-Modelle mit visuell kombinierten Merkmalen (eigenes Idle-/Angriffs-Rig, Rarity-Farbe oberhalb Mythic).
- Fusions-Katalysator-Icon/Item-Modell.

**Neue Skripte/Systeme:**
- `FusionService`: Kombinationslogik, Erfolgschance-Berechnung, Pity-Counter-Persistenz.
- Fusion-Rezept-Datenbank (feste + teilzufällige Kombinationen).
- Fusion-UI (Auswahl-Dialog für Ausgangskreaturen, Fortschritts-/Erfolgsanzeige).
- Integration in Kodex-System (Fusions-Register als neue Kategorie).
- MarketplaceService-Hook für Katalysator-Kauf (Developer Product).

**Aufwand:** mittel–groß. **Abhängigkeiten:** MVP Zucht-System, Kreaturen-Kodex mit Sets (1.5), optional Mystery Egg (1.7) als Dupe-Quelle.

---

### 3.15 Tiefsee-Aquarium – Öffentliche Schauvitrine

**Beschreibung:** Ein dedizierter Ausstellungsbereich auf dem eigenen Plot, in dem Spieler ihre seltensten Kreaturen kuratiert präsentieren können. Andere Spieler können vorbeischauen, per "Like"/Bubble-Reaktion Anerkennung zeigen und das Aquarium fotografieren.

**Warum das Spiel bereichert:**
- **Social/UGC:** Verwandelt seltene Kreaturen von reinen Statwerten in Status-Symbole – stärkt indirekt die Attraktivität von Gacha-/Fusions-Käufen ("damit ich es zeigen kann").
- **Virales Marketing:** Screenshot-/Foto-Modus-Funktion senkt die Hürde, dass Spieler ihr Aquarium außerhalb von Roblox teilen (Social Media, Freundeskreis) – organische Reichweite ohne Werbebudget.
- **Retention/Sessionlänge:** Ein Besuchs-Browser im Hub gibt einen neuen, entspannten Grund zum Verweilen (Browsing statt Grinden), erhöht durchschnittliche Sessiondauer.

**Mechanik-Details:**
- Separater Aquarium-Baumodus (eigenes Deko-Raster am Plot); ausgestellte Kreaturen sind rein dekorativ (kein Idle-Produktionseffekt), um Exploits/Doppelnutzung zu vermeiden.
- "Besuchen"-Browser im Hub: Filter nach "meist geliked diese Woche", "neu", "Freunde".
- Like-Mechanik mit Cooldown pro Ziel/Tag (Anti-Bot-Schutz, verhindert Like-Farming).
- Wöchentliches Feature "Aquarium der Woche" mit Bonus-Belohnung für den Ersteller und Sichtbarkeits-Boost.
- Integrierter In-Game-Foto-Modus (freie Kamera, kurzzeitiges Ausblenden von UI für saubere Screenshots).

**Neue 3D-Assets:**
- Aquarium-Plot-Erweiterung/Deko-Rahmen (Glaswand-Module, Beleuchtungs-Rigs, Podeste).
- Deko-Requisiten-Set (Spotlight-Strahler, Themen-Hintergründe für Showcase-Bereiche).
- Like-/Herz-VFX und UI-Icon.
- Kamera-Tool-UI (Foto-Modus-Steuerung).
- "Featured"-Abzeichen-Icon für ausgezeichnete Aquarien.

**Neue Skripte/Systeme:**
- `AquariumBuildService`: separates Placement-System, wiederverwendet Grundlogik des MVP-Bauplatzierungs-Systems.
- Visit-Browser-Service: Serverabfrage populärer/zufälliger Aquarien (OrderedDataStore-basiertes Like-Ranking).
- Like-System mit Cooldown- und Anti-Bot-Validierung (serverseitig).
- Featured-Rotation-Job (wöchentliche automatische Auswahl nach Like-Zahl/Zufallsgewichtung).
- In-Game-Screenshot-/Kamera-Tool-Skript (Client-seitig, UI-Ausblendung).

**Aufwand:** mittel. **Abhängigkeiten:** MVP Bauplatzierungs-System, Kreaturen-Kodex, Hub-Welt, bestehende Leaderboard-Infrastruktur (für Like-Ranking).

---

### 3.16 Gezeiten-Allianz – Cross-Promotion & Meeresschutz-Event

**Beschreibung:** Jährliches (oder halbjährliches) Themen-Event rund um den Welttag der Ozeane (8. Juni), das drei Elemente kombiniert: (1) ein Lern-/Aufräum-Minispiel im Riff, (2) Cross-Promotion-Codes mit anderen Roblox-Erlebnissen und (3) ein optionales, transparent kommuniziertes Charity-Kosmetik-Paket zugunsten einer Meeresschutzorganisation.

**Warum das Spiel bereichert:**
- **PR/Discovery:** Bietet einen natürlichen Presse-/Community-Aufhänger ("Kinderspiel vermittelt Meeresschutz-Bewusstsein"), erhöht Chancen auf redaktionelle Roblox-Feature-Platzierung.
- **Neuspieler-Akquise ohne Werbebudget:** Cross-Promotion-Codes mit thematisch verwandten Roblox-Erlebnissen erzeugen gegenseitigen Spieler-Traffic – deutlich günstiger als klassische Werbung.
- **Vertrauen/CSR:** Ein transparenter Charity-Anteil stärkt das Vertrauen der (oft mitentscheidenden) Eltern der Zielgruppe 8–14 und positioniert Abyssara positiv gegenüber austauschbaren Konkurrenzspielen.
- **Community-Bindung:** Ein globales, gemeinsames Fortschrittsziel (server- und plattformübergreifend) erzeugt kollektives Zugehörigkeitsgefühl.

**Mechanik-Details:**
- Event-Zeitfenster von 2–3 Wochen mit thematischem Hub-Reskin ("Riff-Reinigung"): sammelbare Müll-Objekte als Mini-Quest-Linie, begleitet von kurzen, altersgerechten Fakten-Popups über Meeresschutz.
- Cross-Promo-Code-System: Spieler, die ein Partner-Roblox-Erlebnis besuchen, erhalten einen Code für ein exklusives Item in Abyssara – und umgekehrt (gegenseitige Traffic-Vereinbarung).
- Charity-Kosmetik-Bundle (z. B. 150 Robux, transparent deklarierter Spendenanteil an Partnerorganisation).
- Globaler Community-Fortschrittsbalken: alle Spieler weltweit sammeln gemeinsam auf ein Serverziel hin (z. B. "1 Million Müll-Stücke") – bei Erreichen wird ein permanentes kosmetisches "sauberes Riff"-Update im Hub für alle freigeschaltet.

**Neue 3D-Assets:**
- Event-Hub-Reskin-Deko: Müll-Objekte als sammelbare Props, "Vorher/Nachher"-Riff-Varianten (verschmutzt → sauber).
- Partner-Item-Modelle (austauschbarer Platzhalter-Slot, abhängig vom jeweiligen Cross-Promo-Partner).
- Charity-Kosmetik-Set (2–3 Items, z. B. "Schildkröten-Freund"-Anhänger, Riff-Schutz-Taucheranzug-Skin).
- Community-Fortschrittsbalken-UI (serverweite/globale Anzeige).
- Informative Fakten-Popup-UI-Rahmen (altersgerechtes, kurzes Bildungsformat).

**Neue Skripte/Systeme:**
- Erweiterung des `EventScheduler` aus 2.10 (wiederverwendete Event-Framework-Infrastruktur).
- Cross-Promo-Code-Redemption-System (externe Code-Validierung, Anti-Abuse gegen Code-Missbrauch).
- Community-Goal-Tracker: globaler, serverübergreifender Zähler (wiederverwendet `MessagingService`-Technik aus Cross-Zone-Boss-Events, 2.13).
- Charity-Kauf-Tracking (transparentes Reporting, ggf. Anbindung an externe Spendenabwicklung/-Reporting-Seite).
- Bildungs-Popup-Trigger-System (zeitgesteuerte, nicht-aufdringliche Einblendung).

**Aufwand:** mittel (Ersteinrichtung inkl. Cross-Promo-Partnerklärung), danach klein pro jährlicher Wiederholung. **Abhängigkeiten:** Saisonales Live-Event-Framework (2.10), Hub-Welt, Cross-Zone-Boss-Events-Infrastruktur (2.13, für globalen Zähler).

---

## 4. Priorisierungsempfehlung (Kurzfazit)

Für den größten Retention-/Monetarisierungs-Hebel pro Aufwand empfiehlt sich innerhalb Phase 2 die Reihenfolge: **1.5 Kodex-Sets → 1.7 Mystery Egg → 1.2 Prestige → 1.1 Mitternachtszone → 1.4 Season Pass → 1.3 Reef Cluster → 1.6 Kosmetik-Rotation** (kleine/mittlere Systeme zuerst, die groß angelegte Content-Zone zuletzt, wenn die Kernschleife bereits durch Prestige und Kodex vertieft ist). In Phase 3 sollte **2.12 Anti-Exploit/Telemetrie** parallel zu allen anderen Punkten mitlaufen, da sie alle übrigen Systeme absichert. Aus Phase 4 eignet sich **3.15 Tiefsee-Aquarium** als vergleichsweise günstiger, hoher Social-Impact-Baustein für einen frühen Zusatz-Sprint.

---

*Dieses Dokument ergänzt `game-design-doc.md` und ist wie dieses direkt als Arbeitsauftrag für den 3D-Asset-Agenten und den Luau-Code-Agenten nutzbar – pro Erweiterung unabhängig vom Rest umsetzbar, sofern die jeweils genannten Abhängigkeiten erfüllt sind.*
