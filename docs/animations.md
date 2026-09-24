# Charakter-Animationen – Abyssara: Deep Tide Tycoon

Dieses Dokument beschreibt das Animationssystem für Spielercharaktere:
Gehen, Rennen, Springen/Fallen/Landen, Idle sowie Trage-Posen.

## Warum prozedural statt hochgeladener Animationen?

Klassische Roblox-Animationen benötigen eine im Studio **hochgeladene**
Animation-Asset-ID. Aus reinem Code heraus lässt sich keine live nutzbare
Animation-ID erzeugen – `KeyframeSequenceProvider:RegisterKeyframeSequence`
liefert nur eine temporäre ID, die im veröffentlichten Spiel **nicht**
funktioniert. Deshalb nutzt dieses System standardmäßig **prozedurale
Animation**: Jeder Client setzt pro Frame direkt die `Motor6D.C0`-Werte der
Gelenke jedes sichtbaren Charakters, basierend auf replizierten Daten
(Humanoid-Zustand, Geschwindigkeit, Position). `Motor6D.Transform`/`C0`
repliziert nicht übers Netzwerk – daher animiert **jeder Client selbst jeden
Charakter, den er sieht** (inkl. sich selbst). Das Ergebnis sieht für alle
Spieler nahezu identisch aus, da es auf denselben replizierten
Bewegungsdaten basiert.

## Dateien

- `src/shared/CharacterAnimation/` → `ReplicatedStorage.CharacterAnimation`
  - `AnimationConfig.lua` – alle Stellschrauben (Geschwindigkeiten, Amplituden,
    LOD-Distanzen, FX, Override-Tabelle)
  - `Spring.lua` – generische kritisch gedämpfte Feder für weiches Blending
  - `PoseLibrary.lua` – reine Pose-Funktionen (Idle, Locomotion, Jump/Fall/Land, Carry)
  - `RigJoints.lua` – findet Motor6Ds für R15 (voll) und R6 (vereinfacht)
  - `ProceduralAnimator.lua` – eine Instanz pro Charakter, wendet Posen pro Frame an
  - `EffectsPool.lua` – gepoolte Staub-Partikel für Schritte/Landungen
- `src/client/CharacterAnimator.client.lua` → `StarterPlayer.StarterPlayerScripts`
  Orchestriert Animator-Instanzen, LOD, Sprint-Eingabe (Tastatur/Touch/Gamepad)
- `src/server/CharacterSetup.server.lua` → `ServerScriptService`
  Erzwingt R15, entfernt das Standard-`Animate`-Script, validiert Sprint
  serverseitig (WalkSpeed wird **nur** vom Server gesetzt)

## Eigene, echte Animationen einbinden (optional)

Falls die Nutzerin später handgemachte oder gekaufte Animationen statt der
prozeduralen Bewegung nutzen möchte:

1. Animation im **Roblox Animation Editor** (Studio: Avatar → Animation
   Editor) am R15-Rig erstellen oder eine gekaufte/Marketplace-Animation
   verwenden.
2. Im Editor auf **Publish** klicken → Roblox vergibt eine echte,
   dauerhafte Asset-ID (Format `123456789`).
3. In `src/shared/CharacterAnimation/AnimationConfig.lua` bei
   `AnimationOverrides` den passenden Slot eintragen, z.B.:

   ```lua
   AnimationConfig.AnimationOverrides = {
       Idle = "rbxassetid://123456789",
       Walk = "rbxassetid://234567890",
       Run = "",   -- leer = weiterhin prozedural
       Jump = "",
       Fall = "",
       Land = "",
   }
   ```

4. Speichern, Rojo-Sync/Play testen. Für jeden gesetzten Slot lädt
   `ProceduralAnimator` automatisch einen `AnimationTrack` über
   `Animator:LoadAnimation()` und spielt ihn im passenden Zustand ab; die
   prozedurale Pose für genau diesen Slot wird deaktiviert. Nicht gesetzte
   Slots bleiben prozedural.

**Hinweis/Grenze:** Wenn nur einzelne Slots überschrieben werden (z.B. nur
`Walk`), kann es an Übergängen zu anderen (noch prozeduralen) Zuständen zu
leicht sichtbaren Sprüngen kommen, da beide Systeme dieselben Gelenke
ansteuern. Für ein einheitliches Bild empfiehlt es sich, entweder **alle**
sechs Slots zu überschreiben oder **keinen**.

## Rig-Unterstützung

- **R15 (Hauptziel):** volle Animation mit Schulter/Ellbogen/Handgelenk und
  Hüfte/Knie/Fußgelenk – natürlicher Beinschwung, Armpendel, Hüftrotation.
- **R6:** vereinfachte Version (nur Schulter/Hüfte, da R6 keine
  Ellbogen/Knie-Gelenke besitzt). `CharacterSetup.server.lua` ruft
  `Players:SetDefaultRigType(Enum.HumanoidRigType.R15)` auf, um neu
  geladene Avatare nach Möglichkeit auf R15 zu zwingen. Schlägt das fehl
  (z.B. API in der genutzten Studio-Version nicht vorhanden), erkennt
  `RigJoints.lua` automatisch R6 und der Client nutzt die vereinfachte
  Version – kein Absturz, nur weniger Detail.

## Sprint-Eingabe

- **PC:** Linke/Rechte Umschalttaste (Shift) halten
- **Mobile:** automatisch erzeugter Touch-Button (über
  `ContextActionService:BindAction(..., true, ...)`)
- **Gamepad:** L3 (linker Stick-Klick)

Der Client sendet nur ein **Boolean** (`true`/`false`) über `SprintRemote`.
Die tatsächliche `WalkSpeed` wird ausschließlich serverseitig in
`CharacterSetup.server.lua` gesetzt und auf `34` gedeckelt – der Client kann
keine beliebige Geschwindigkeit erzwingen. Zusätzlich gibt es eine
Anfrage-Drosselung (Cooldown), um Remote-Spam zu verhindern.

## Trage-Posen (CarryPose)

Ein externes Halte-/Inventarsystem kann das Charakter-Attribut `CarryPose`
setzen:

- `"OneHand"` – rechter Arm hält ein Item vor dem Körper
- `"TwoHand"` – beide Arme halten ein Item vor dem Körper
- `nil` / nicht gesetzt – normale Armanimation

```lua
character:SetAttribute("CarryPose", "OneHand")
```

Die Beine animieren in jedem Fall normal weiter (Gehen/Rennen/Springen);
nur die Arme werden weich (über eine Feder, kein hartes Umschalten) auf die
Trage-Pose geblendet.

## Unterwasser-Flair

`AnimationConfig.UnderwaterFlairEnabled` (Standard: `true`) fügt Idle und
Bewegung ein dezentes Schweben sowie einen leichten "Drag"-Faktor
(`UnderwaterDragFactor`) hinzu, passend zum Deep-Tide-Setting. Auf `false`
setzen, um komplett "trockene" Standardbewegung zu erhalten.

## Performance-Maßnahmen

- **Distanz-LOD** (`CharacterAnimator.client.lua`, alle 0,25s neu berechnet):
  - `Full` (≤ 45 Studs zur Kamera): alle Gelenke, volle Detailtiefe, FX aktiv
  - `Reduced` (≤ 110 Studs): nur Hauptgelenke (Schulter/Hüfte/Wirbelsäule/
    Kopf), Ellbogen/Knie/Handgelenk/Fußgelenk werden übersprungen, keine FX
  - `Off` (weiter entfernt): keine Motor6D-Updates (Charakter bleibt in
    letzter Pose stehen, kostet praktisch nichts)
- **Phasenkopplung an zurückgelegte Distanz statt feste Frequenz** –
  verhindert Moonwalk/Rutschen unabhängig von Framerate-Schwankungen.
- **Gepooltes FX-System** (`EffectsPool.lua`): feste Anzahl (`FXPoolSize`,
  Standard 28) wiederverwendeter Partikel-Emitter statt `Instance.new` pro
  Effekt – wichtig für Mobile.
- **Physiksynchrones `RunService.PreSimulation`** statt `RenderStepped`,
  damit Motor6D-Updates konsistent vor der nächsten Simulation/Renderframe
  angewendet werden, ohne den Standard-Animator zu blockieren.
- Alle Verbindungen (`Connections`) werden bei Charakter-Entfernung/Respawn
  sauber getrennt (`cleanupCharacter` in `CharacterAnimator.client.lua`,
  `ProceduralAnimator:Destroy()`), um Speicher-/Verbindungs-Leaks zu
  vermeiden.

## Platzhalter, die die Nutzerin ggf. anpassen möchte

- `EffectsPool.lua`: `emitter.Texture` nutzt aktuell eine eingebaute
  Roblox-Partikeltextur (`rbxasset://textures/particles/smoke_main.dds`)
  als generischen Sand-/Staub-Look. Für einen individuelleren Look kann
  hier eine eigene hochgeladene Textur-ID eingetragen werden.
- `AnimationConfig.AnimationOverrides`: siehe Abschnitt "Eigene, echte
  Animationen einbinden" oben.
