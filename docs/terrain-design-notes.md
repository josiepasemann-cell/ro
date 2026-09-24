# Terrain-Design-Notizen: **Abyssara – Deep Tide Tycoon**

*Stand: 2026-09-24 · Ergänzung zu `game-design-doc.md` (Abschnitt 8) und
`expansion-concepts.md` (Abschnitt 1.1, 2.8) · Grundlage für die
Buildscripts unter `/home/user/ro/assets/models/terrain/`*

---

## 0. Zweck

Die ursprünglichen Terrain-Chunks für Sonnen- und Dämmerzone waren im
Wesentlichen flache Grundflächen mit ein paar verstreuten Deko-Objekten
("Dünen", "Boulder", "Kelp"). Dieses Dokument fasst die Recherche zusammen,
die vor dem Ausbau aller vier Zonen-Terrains durchgeführt wurde, und
beschreibt, wie jedes der resultierenden Prinzipien konkret in den vier
Buildscripts umgesetzt wurde.

## 1. Recherche: Kernprinzipien fesselnden 3D-Terrains

Recherchequellen (Auswahl, vollständige Liste am Dokumentende):
Roblox Developer Forum ("Map Design Guidelines", "Large-Scale Roblox
Terrain", "Tips for Beautiful Terrain"), Sandboxr ("Best Practices for Game
Map Layout"), Analysen zu Subnautica/Abzù-Leveldesign, sowie
Roblox-Performance-Threads zu Terrain vs. Parts.

### 1. Verticality / Höhenrhythmus
Höhenunterschiede erzeugen Blickpunkte, Deckung, Orientierungspunkte und
einen emotionalen Rhythmus (Enge vs. Weite). Eine durchgängig flache Fläche
ist die größte einzelne Schwäche des ursprünglichen Terrain-Sets.

### 2. Landmarks / Points of Interest
Eine sichtbare "Landmark-Kette" verhindert, dass sich Spieler verlaufen, und
gibt jeder Zone eine unverwechselbare Identität ("das ist die Zone mit dem
Felsbogen/Torbogen/Boss-Tor/Abgrund").

### 3. Sichtachsen / "Leading the Eye"
Gezielte Lichtsetzung, freigehaltene Sichtlinien und Formationen, die den
Blick lenken, wecken Neugier und weisen (ohne UI) den Weg – ein
Kernprinzip aus Subnautica/Abzù, wo Licht und leere Räume als "Atempausen"
gezielt zur Navigation genutzt werden.

### 4. Silhouetten-Lesbarkeit bei Low-Poly
Bei wenigen Polygonen zählt die Kontur: große, eindeutige Blockformen lesen
sich aus der Distanz besser als viele kleine Detailteile. Passt zum
bestehenden blocky Roblox-Stil des Projekts.

### 5. Farbpalette / Kontrast zwischen Zonen
Jede Zone braucht eine klar unterscheidbare Farbsignatur (Wert- und
Sättigungskontrast), damit "Tiefe" sich auch ohne UI-Levelanzeige anfühlt –
von hell/warm (Sonnenzone) bis fast schwarz mit einzelnen Neon-Akzenten
(Mitternachtszone, Hadal-Tiefe).

### 6. Deko-Dichte-Rhythmus (dicht vs. offen)
Gleichmäßig verteilte Deko wirkt schnell monoton und kostet Performance ohne
Mehrwert. Dichte "Taschen" rund um Landmarks, abgewechselt mit bewusst
ruhigen/leeren Flächen, erzeugen Spannungsrhythmus und lenken zusätzlich die
Aufmerksamkeit (Prinzip aus Roblox-Tycoon-/Dekorations-Analysen: dynamische
Setups schlagen statische, aber Überfüllung schadet Ladezeiten/Retention).

### 7. Wegführung durch Enge/Weite-Wechsel
Speziell für Höhlen-/Tiefsee-Level (Subnautica-Prinzip): schmale Passagen,
die sich in große Kavernen/Plätze öffnen, erzeugen Spannung und
Wiedererkennungspunkte im Streckenverlauf.

### 8. Performance-Grenzen (Roblox-spezifisch)
Roblox-Terrain (Smooth Terrain) ist ideal für sehr große, homogene Flächen;
für kontrollierte, deterministische Buildscripts mit klaren Landmarks sind
Parts + CSG (`UnionAsync`/`SubtractAsync`) die bessere Wahl, weil komplexe
Formen (Bögen, Höhlentore, Mulden) zu **einem** performanten Part
zusammengefasst werden, statt Dutzende Einzelteile zu benötigen. PartCount
pro Chunk wurde deshalb bewusst in einem niedrigen zwei- bis unterem
dreistelligen Bereich gehalten.

## 2. Umsetzung pro Zone

Alle vier Skripte teilen ein wiederkehrendes Kompositionsmuster: eine
**freigehaltene Sichtachse/Gasse** von der Hub-seitigen Kante zu einer
**Landmark am gegenüberliegenden Zonen-Ende**, flankiert von
**dichten Deko-Taschen an den Landmarks** und **ruhigeren Flächen dazwischen**
– dieses wiederkehrende Muster verbindet die vier sehr unterschiedlichen
Biome stilistisch, ohne sie gleich aussehen zu lassen.

### Sonnenzone (`SunZoneTerrainChunk.lua`, überarbeitet)
- **Verticality:** per CSG-`SubtractAsync` (NegateOperation) eine sanfte,
  runde Mulde ("Tidal Basin") in den Sandboden eingesenkt, plus zwei
  gestufte Dünenhügel mit hellerer "Sonnenkuppe" (Farbbänderung als
  billiger Tiefenhinweis).
- **Landmarks (2):** "Sonnentor"-Felsbogen (CSG-`UnionAsync` aus zwei
  Pfeilern + Sturz) nahe der Hub-Kante; gestrandetes Schiffswrack
  (blocky Rumpf/Bug/Heck/Rippen-Silhouette) tiefer in der Zone.
- **Sichtachse:** freigehaltene Hub-Gasse (`LANE_HALF_WIDTH`), gerahmt von
  zwei Dünenrücken.
- **Dichte-Rhythmus:** dichte Stein-/Korallen-Taschen um beide Landmarks,
  ruhige, offene Sandflächen dazwischen.
- **Palette:** warme Sand-/Korallentöne (Tutorial-Freundlichkeit).

### Dämmerzone (`TwilightZoneTerrainChunk.lua`, überarbeitet)
- **Verticality:** zwei aufragende Felsnadeln (CSG-`UnionAsync` gestapelter,
  leicht versetzter Blöcke) plus eine lang gezogene, per `SubtractAsync`
  eingeschnittene Felsspalte (Canyon-Charakter statt runder Mulde).
- **Landmark:** "Kelp-Torbogen" – zwei Kelp-Stämme, die sich **entlang einer
  echten Kurve** (nicht nur Rotations-Sway wie die übrigen Kelp-Halme)
  zueinander biegen und sich oben in einem leuchtenden Neon-Knoten treffen.
- **Sichtachse:** engere Hub-Gasse als in der Sonnenzone (bewusst
  klaustrophobischeres Zonengefühl), gesäumt von dichten Fels-/Kelp-Wänden.
- **Dichte-Rhythmus:** dichte Kelpwälder an den Rändern, klare Gasse in der
  Mitte.
- **Palette:** kühle, dunklere Grau-/Blautöne mit türkis-aqua Neon-Akzenten
  (starker Kontrast zur Sonnenzone).

### Mitternachtszone (`MidnightZoneTerrainChunk.lua`, neu)
- **Verticality/Enge-Rhythmus:** enge Einstiegs-Passage (dichte Wände +
  überhängende Deckenplatte) öffnet sich zu einer hohen Hauptkaverne mit
  Stalagmiten (CSG-`UnionAsync` gestapelter Tiers) und Stalaktiten.
- **Landmark:** Arena-Eingang "Der Tiefenfürst" – ein per `SubtractAsync`
  (NegateOperation) aus einem Felsblock herausgeschnittenes, rundes
  Höhlentor, flankiert von zwei lava-geäderten Felsnadeln, vor einer per
  `SubtractAsync` eingesenkten, lavaumrandeten Arena-Vorplatzfläche.
- **Licht als Wegführung:** da Silhouetten im Dunkeln kaum lesbar sind,
  übernehmen glühende Lavaspalten/-pools (`Enum.Material.Neon` +
  `PointLight`) die Rolle der Sichtachse aus der Sonnenzone und markieren
  den begehbaren Pfad vom Eingang bis zum Boss-Tor.
- **Dichte-Rhythmus:** dichte Passage, sparsame/monumentale Kaverne, dichte
  Deko direkt am Tor (Erwartungsspannung).
- **Palette:** fast schwarzes Basalt/Obsidian + heißes Orange-Rot als
  einzige warme Akzentfarbe.

### Hadal-Tiefe (`HadalDepthsTerrainChunk.lua`, neu)
- **Extremste Verticality:** das begehbare Plateau deckt bewusst nur einen
  Teil des Chunk-Footprints ab (`FLOOR_DEPTH < CHUNK_SIZE`) – jenseits der
  Abgrund-Kante existiert **kein Boden mehr**; winzige, weit unten
  verstreute "Deep Glints" verstärken den Eindruck von Bodenlosigkeit.
- **Landmark:** monumentales Kristallspitzen-Ensemble (zwei CSG-`UnionAsync`-
  Cluster aus je 5 Kristallschalen) direkt an der Kante, mit einer
  freischwebenden, aus der Kante herausragenden Glas-Aussichtsplattform
  ("Void-Tech"-Streben statt organischer Formen).
- **Sichtachse:** "Void-Gasse" (gleiche Hub-Achse wie Mitternachtszone)
  führt direkt auf die Aussichtsplattform zu; Kristallfelder werden zur
  Kante hin per Skalen-Crescendo größer (lenkt den Blick zusätzlich).
- **Silhouetten/Formsprache:** scharfkantige `WedgePart`-Kristallsplitter
  statt organischer Rundungen – bewusster stilistischer Bruch zu den drei
  organischeren Vorzonen.
- **Palette:** fast schwarzes Abgrund-Violett + Neon-Quartett (Cyan,
  Magenta, Violett, Teal) – stärkster Palettenkontrast aller vier Zonen.

## 3. Technische Umsetzungshinweise (für Wartung/Erweiterung)

- CSG-Technik "Mulde/Spalte": eine (ggf. gestreckte) `Enum.PartType.Ball`
  wird so positioniert, dass ihr Mittelpunkt exakt auf der Oberkante der
  Grundfläche liegt (`localY = BASE_TOP_Y`); `SubtractAsync` entfernt dann
  die untere Hemisphäre und erzeugt eine sanfte, runde Senke mit
  Tiefe = vertikaler Kugelradius. Gleiche Technik, unterschiedliche
  Seitenverhältnisse: runde Mulde (Sonnenzone/Mitternachtszone) vs.
  lang gezogener Canyon (Dämmerzone).
- CSG-Technik "Torbogen/Nadel": mehrere Parts werden überlappend/berührend
  angeordnet und per `UnionAsync` zu einem einzigen Part zusammengefasst
  (Pfeiler+Sturz = Bogen; gestapelte, leicht versetzte Tiers = Felsnadel/
  Stalagmit/Kristallcluster).
- Alle `ORIGIN`-CFrames in diesem Projekt sind reine Translationen (keine
  Rotation) – das vereinfacht Weltraum-/Lokalraum-Umrechnungen bei
  prozeduralen Kurven (z. B. Kelp-Torbogen) erheblich.
- Jedes Skript bleibt idempotent (vorhandenes Modell wird vor dem Neubau
  entfernt) und exportiert `PrimaryPart = "ChunkBase"` sowie das Attribut
  `Zone` – unverändert gegenüber dem ursprünglichen Muster.

## 4. Quellen (Recherche-Links)

- [Map Design Guidelines – Roblox DevForum](https://devforum.roblox.com/t/map-design-guidelines-make-your-maps-superior/1293781)
- [Tips for Building Beautiful Terrain – Medium/Developer Baseplate](https://medium.com/roblox-developer/tips-for-building-beautiful-terrain-6a13fd1ba314)
- [Large-Scale Roblox Terrain: The Ultimate Guide – Roblox DevForum](https://devforum.roblox.com/t/large-scale-roblox-terrain-the-ultimate-guide/405672)
- [Best Practices for Game Map Layout: Flow, Landmarks & Player Navigation – Sandboxr](https://sandboxr.com/best-practices-for-game-map-layout-flow-landmarks-player-navigation/)
- [How to Optimize Roblox Art for Better Performance (Low-Poly Tips) – Vasundhara](https://www.vasundhara.io/blogs/how-to-optimize-roblox-art-for-better-performance-low-poly-tips)
- [Roblox Prop Design Tips: 7 Steps to Clean, Performant Props – Nilo](https://nilo.io/articles/roblox-prop-design-tips)
- [Terrain vs Part Performance – Roblox DevForum](https://devforum.roblox.com/t/terrain-vs-part-performance-impact/1647950)
- [Roblox 'Part vs Terrain' Complete Guide – note.com/v_rangers](https://note.com/v_rangers/n/n68619fce16b2?hl=en)
- [Subnautica's Underwater World: A Masterclass in Level Design – YouTube](https://www.youtube.com/watch?v=2ivClz9ZIK8)
- [Too Afraid to Go Deeper: Pervasive Dread in Subnautica – Game Studies](https://gamestudies.org/2404/articles/evans)
- [Roblox Decorations: Behavioral Design and Engagement Strategies – Coohom](https://www.coohom.com/article/roblox-decorations-innovative-strategies-for-immersive-design)
