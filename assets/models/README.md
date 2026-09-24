# Abyssara – Deep Tide Tycoon: 3D-Assets (MVP-Scope)

Diese Buildscripts erzeugen die 3D-Geometrie für den MVP-Scope (Sonnenzone +
Dämmerzone) von **Abyssara – Deep Tide Tycoon**, gemäß Abschnitt 8 und
Abschnitt 10 des Game Design Documents (`/home/user/ro/docs/game-design-doc.md`).

Es handelt sich ausschließlich um **reine Geometrie-Erzeugung** (Luau,
`Instance.new`/`CFrame`/CSG-Union-Operationen). Es ist **keine Gameplay-Logik**
enthalten (keine Steuerung, keine Ökonomie, keine Kollisions-/Raid-Logik) –
diese kommt bewusst erst in einem späteren Schritt durch den Code-Agenten.

## Asset-Übersicht

### `terrain/` – Umgebung
| Datei | Asset | Beschreibung |
|---|---|---|
| `HabitatPlotBase.lua` | Modulare Habitat-Plot-Basis | Sechseckige Plattform (~60 Studs flat-to-flat), CSG-Sechseck, 6 sichtbar markierte Baufelder (Neon-Sektorlinien + Slot-Marker) |
| `SunZoneTerrainChunk.lua` | Meeresboden-Terrain Sonnenzone | Heller, sandiger Low-Poly-Boden mit Dünen, hellen Steinen, Korallen-Akzenten |
| `TwilightZoneTerrainChunk.lua` | Meeresboden-Terrain Dämmerzone | Dunkler, felsiger Low-Poly-Boden mit Gesteinsbrocken und Kelp-Bündeln (Glow-Spitzen) |

### `buildings/` – Gebäude (je Basisstufe)
| Datei | Asset | Beschreibung |
|---|---|---|
| `BroodPool_Basic.lua` | Brutbecken (Stufe 1/3) | Rundes Becken (CSG-Subtraktion), leuchtendes Wasser, 3 Ei-Platzhalter |
| `GlowBuoyStation.lua` | Lichtboje / Glow-Sammler-Station | Mast mit Haupt-Glow-Orb + 3 Satelliten-Orbs |
| `FilterPlant.lua` | Filteranlage | Haupttank + 2 Nebentanks, Rohre, Status-Leuchtlicht |
| `AnglerfishTower.lua` | Verteidigungsturm: Anglerfisch-Turm | Verjüngter Turmschaft, gebogenes Illicium mit Köder-Orb (Ziel-/Schusspunkt) |

### `creatures/` – Kreaturen (MVP-Set, 6 Modelle)
| Datei | Asset | Rarity (Platzhalter) | Zone |
|---|---|---|---|
| `GlowJelly.lua` | Glühqualle | Common | SunZone |
| `GlowShrimp.lua` | Leuchtgarnele | Common | SunZone |
| `GlowRay.lua` | Leuchtrochen (freie 6. Wahl) | Uncommon | SunZone |
| `Anglerfish.lua` | Anglerfisch | Rare | TwilightZone |
| `BioluminescentEel.lua` | Biolumineszenz-Aal | Epic | TwilightZone |
| `CrystalKraken.lua` | Kristallkrake | Legendary | TwilightZone |

### `enemies/` – Raid-Gegner
| Datei | Asset | Beschreibung |
|---|---|---|
| `ShadowKraken.lua` | Schattenkrake (Platzhalter-Raid-Gegner) | Größerer, bedrohlicher Kraken mit 8 Tentakeln, rote Glow-Augen, `EnemyTier`-Attribut |

### `gacha/` – Mystery Egg Gacha (Erweiterungskonzept 1.7, Compliance-konform)
Reine Geometrie-/Effekt-Rig-Assets für das im GDD/Erweiterungskonzept
beschriebene Gacha-System. **Enthalten keinerlei Zufalls-Roll-, Pity- oder
Kauf-Logik** (`GachaService` & Co. kommen bewusst erst später durch den
Code-Agenten).

| Datei | Asset | EggTier (Platzhalter) | Beschreibung |
|---|---|---|---|
| `MysteryEgg_Common.lua` | Mysterium-Ei (Gewöhnlich) | `Common` | Glatte Eiform, mattes SmoothPlastic, 1 dünner Neon-Nahtring |
| `MysteryEgg_Uncommon.lua` | Mysterium-Ei (Ungewöhnlich) | `Uncommon` | Satteres Türkis, 2 Nahtringe, gesprenkeltes Punktmuster |
| `MysteryEgg_Rare.lua` | Mysterium-Ei (Selten) | `Rare` | Glas-Schale (CSG-Union mit Facetten-Höckern), 2 Nahtringe + Punktmuster |
| `MysteryEgg_Epic.lua` | Mysterium-Ei (Episch) | `Epic` | Violett-neon kristalline Schale (CSG-Union mit Kristallschüben), 4 Ader-Linien, Leucht-Spitze |
| `MysteryEgg_Legendary.lua` | Mysterium-Ei (Legendär) | `Legendary` | Zweifarbige Kristallschale, Dornenkrone (5 Spitzen), freischwebender Runenring (CSG-Subtraktion), `PointLight` |
| `MysteryEgg_Mythic.lua` | Mysterium-Ei (Mythisch) | `Mythic` | Aufwendigste Stufe: Kristallschale mit Glow-Kern, 7er-Dornenkrone, 2 versetzt geneigte Runenringe, 3 Kristallsplitter-Satelliten, hellstes `PointLight` |
| `GachaEggOpenVFX.lua` | Öffnungs-VFX-Rig | – | Wiederverwendbares Effekt-Modell: `ParticleEmitter`s (Schalenriss + Lichtexplosion), `PointLight`-Blitz, rarity-farbiger `Beam`. Alle standardmäßig `Enabled = false` |

### `ui/` – UI-Layout-Grundgerüste
Reine `ScreenGui`/`Frame`-Layouts ohne Funktions-Logik (kein `LocalScript`
lädt Daten oder verarbeitet Klicks – das kommt bewusst erst später).

| Datei | Asset | Beschreibung |
|---|---|---|
| `GachaOddsPanel.lua` | Odds-Display-UI-Panel | `ScreenGui "GachaOddsUI"` mit Titel, 6 Rarity-Zeilen (Common–Mythic) mit Platzhalter-Prozentwerten, Schließen-Button (ohne Click-Verbindung) |

## Wie man die Skripte in Roblox Studio ausführt

**Option A – Command Bar (empfohlen für Einzeltests):**
1. Roblox Studio öffnen, das gewünschte Place laden.
2. Menü **View → Command Bar** öffnen.
3. Den Inhalt der `.lua`-Datei hineinkopieren und mit Enter ausführen.
4. Das Modell erscheint unter `Workspace.Assets.<Kategorie>.<AssetName>`
   (bei den `ui/`-Skripten stattdessen unter `game.StarterGui.<ScreenGuiName>`).

**Option B – Temporäres Script:**
1. In `ServerScriptService` (oder `ServerStorage`) ein neues `Script` einfügen.
2. Den Inhalt der `.lua`-Datei hineinkopieren.
3. Play-Test starten (oder in Studio einmal über einen Trigger/Command laufen
   lassen) – das Skript baut die Geometrie einmalig auf.
4. Das temporäre Script danach wieder löschen (es enthält keine laufende
   Gameplay-Logik, wird also nicht mehr benötigt).

Alle Skripte sind **idempotent**: Ein vorhandenes Modell mit gleichem Namen im
Zielordner wird vor dem Neubau automatisch entfernt, mehrfaches Ausführen ist
also gefahrlos möglich.

Jedes Skript hat oben einen Konfigurationsblock (`ORIGIN`, ggf. `RARITY`,
`ZONE`, Zufalls-Seed etc.) – vor dem Ausführen ggf. die Zielposition
(`CFrame`) anpassen, damit sich Assets beim gemeinsamen Testen nicht
überlappen.

## Namenskonventionen für den späteren Code-Agenten

- **PrimaryPart:**
  - Kreaturen & Raid-Gegner: `PrimaryPart` heißt immer **`"Body"`** –
    Ansatzpunkt für serverseitige Bewegungssteuerung (Äquivalent zu
    `HumanoidRootPart`).
  - Gebäude & Terrain: `PrimaryPart` heißt immer **`"Base"`**
    (Terrain-Chunks: `"ChunkBase"`) – Ansatzpunkt für Platzierungslogik /
    Snap-to-Grid.
  - Die Habitat-Plot-Basis: `PrimaryPart` ist das Sechseck-Part
    **`"PlatformBase"`**.

- **Idle-Puls-Attachment:**
  - Jede Kreatur und der Raid-Gegner besitzen ein `Attachment`-Objekt namens
    **`"PulseAttachment"`**, das direkt am `PrimaryPart` hängt. Der
    Code-Agent kann darüber die Idle-Schwebe-/Pulsier-Animation (z. B.
    periodisches Scale/Bobbing) ansetzen, ohne die Geometrie selbst
    modifizieren zu müssen.

- **Rarity-Attribut (Kreaturen):**
  - Jedes Kreaturen-Modell trägt `model:SetAttribute("Rarity", "<Wert>")`
    als Platzhalter (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary` im
    aktuellen MVP-Set). Die vollständige Skala laut GDD (Abschnitt 3) ist
    `Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal` – der
    Code-Agent kann darüber später Glow-Farbe/Emission/Partikel-Intensität
    steuern.
  - Zusätzlich gesetzt: `Zone` (Herkunfts-Zone) und `CreatureName`
    (Anzeigename) als Attribute.

- **Weitere Attribute:**
  - Gebäude: `BuildingType` (String) und `Stage` (Number, aktuell immer `1`
    für die Basisstufe) als Platzhalter für spätere Upgrade-Logik.
  - Terrain-Chunks: `Zone` (`"SunZone"` / `"TwilightZone"`).
  - Raid-Gegner: `EnemyTier` (Platzhalter, aktuell `"Elite"`) und `Zone`.

- **Sonstige benannte Hooks:**
  - `HabitatPlotBase`: 6 Attachments `BuildField1` .. `BuildField6` an
    `PlatformBase` markieren die Zentren der Baufelder (für
    Snap-to-Grid-Placement).
  - `AnglerfishTower` / `Anglerfish` (Kreatur): Part `LureOrb` +
    Attachment `MuzzlePoint` (nur Turm) markieren den Köder-/Schusspunkt für
    spätere Angriffs-VFX.
  - `BroodPool_Basic`: Attachments `EggSlot1` .. `EggSlot3` markieren
    Ei-Positionen für die spätere Zucht-/Inkubationslogik.

- **Mystery-Egg-Modelle (`gacha/MysteryEgg_*.lua`):**
  - `PrimaryPart` heißt immer **`"Shell"`** (statt `"Body"` wie bei
    Kreaturen) – Ansatzpunkt für die Öffnungs-Animation und zum Andocken des
    Öffnungs-VFX-Rigs.
  - Jedes Ei trägt `model:SetAttribute("EggTier", "<Wert>")` als
    Platzhalter (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic`
    im aktuellen Gacha-Set – Teilmenge der vollen GDD-Rarity-Skala
    `Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal`).
    Der Code-Agent verknüpft dieses Attribut später mit der echten
    Drop-Tabelle/`GachaService`; es steuert selbst keine Zufalls-Logik.
  - Zusätzlich gesetzt: `EggName` (Anzeigename, Platzhalter).
  - Jedes Ei besitzt ebenfalls ein `Attachment "PulseAttachment"` an
    `Shell`, analog zu den Kreaturen – gleicher Ansatzpunkt für eine
    Idle-Schwebe-/Puls-Animation.
  - `MysteryEgg_Legendary` / `MysteryEgg_Mythic`: zusätzliches
    `PointLight "ShineLight"` an `Shell` als rein dekorativer Glanz-Akzent.
  - `MysteryEgg_Mythic`: zusätzlich 3 Parts `Satellite1`..`Satellite3` als
    Ansatzpunkte für eine spätere Orbit-/Rotationsanimation (rein
    geometrisch platziert, keine Bewegung im Buildscript).

- **Öffnungs-VFX-Rig (`gacha/GachaEggOpenVFX.lua`):**
  - `PrimaryPart` heißt **`"EffectCore"`** (unsichtbarer, zentraler
    Anker-Part) – Ansatzpunkt zum Positionieren/Andocken des gesamten Rigs
    an ein sich öffnendes Ei.
  - `ParticleEmitter "ShellCrackEmitter"` (an Attachment
    `"ShellCrackPoint"`) und `ParticleEmitter "LightExplosionEmitter"` (an
    Attachment `"LightBurstPoint"`) sowie `PointLight "ShineBurst"` und
    `Beam "RarityBeam"` (zwischen den Attachments `"BeamBase"` /
    `"BeamTop"` auf den Parts `BeamAnchorBottom` / `BeamAnchorTop`) sind
    **alle standardmäßig `Enabled = false`** – der Code-Agent schaltet sie
    gezielt für die Öffnungs-Zeremonie an/aus und setzt `RarityBeam.Color`
    passend zur gerollten Rarity. Das Rig selbst spielt nichts automatisch
    ab und enthält keine Zufalls-/Gacha-Logik.

- **Odds-Display-UI-Panel (`ui/GachaOddsPanel.lua`):**
  - Wird unter `game.StarterGui` als `ScreenGui "GachaOddsUI"` angelegt
    (Start: `Enabled = false`), mit Hauptpanel `Frame "OddsPanel"`.
  - Rarity-Zeilen heißen `RarityRow_<Tier>` (`Tier` = derselbe Wortlaut wie
    `EggTier` bei den Ei-Modellen), je mit `Frame "ColorSwatch"`,
    `TextLabel "NameLabel"` (trägt zusätzlich `SetAttribute("EggTier", ...)`)
    und `TextLabel "PercentLabel"`.
  - `PercentLabel` trägt `SetAttribute("PlaceholderOnly", true)` – der
    angezeigte Text ist nur ein Layout-Platzhalter und **nicht** an eine
    echte Drop-Tabelle gebunden; der Code-Agent ersetzt diesen Wert später
    durch serverseitig synchrone Compliance-Odds-Daten.
  - `TextButton "CloseButton"` besitzt bewusst keine
    `MouseButton1Click`-Verbindung – reines visuelles Grundgerüst.

## Technische Hinweise

- Maßstab: 1 Stud ≈ 0,28 m, konsistent zur Standard-Roblox-Charaktergröße.
- Stil: Low-Poly/Blocky, Roblox-typisch, PartCount pro Modell bewusst niedrig
  gehalten.
- Materialien: `Enum.Material.Neon` für Biolumineszenz-/Glow-Effekte,
  `Enum.Material.Glass` für transluzente Körperteile, `Slate`/`Rock`/`Metal`
  für Gebäude/Terrain, `Sand` für die Sonnenzone.
- CSG (`UnionAsync`/`SubtractAsync`/`IntersectAsync`) wird gezielt für
  einfache Formen eingesetzt (z. B. Sechseck-Plattform, Becken-Ring,
  Rochenkörper), um PartCount niedrig zu halten.
- Alle Modell-Skripte legen ihre Modelle unter `game.Workspace.Assets.<Kategorie>`
  ab (`Terrain`, `Buildings`, `Creatures`, `Enemies`, `Gacha`), damit sie
  leicht auffindbar und vom Code-Agenten programmatisch ansprechbar sind.
  Die `ui/`-Skripte weichen davon ab und legen ihre `ScreenGui`s stattdessen
  unter `game.StarterGui` ab, da es sich um UI und keine Workspace-Geometrie
  handelt.
