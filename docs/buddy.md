# Buddy-System (frei wählbares Kreaturen-Maskottchen)

Implementiert das "Buddy"-Feature: jeder Spieler kann EINE besessene
Kreaturen-ART wählen, die ihm sichtbar für ALLE Spieler durch die gesamte
Welt folgt (Hub, eigener Plot, Zonen) - Schlüsselmotivation in
Sammelspielen ("seltene Kreaturen zeigen können").

## Übersicht der neuen Dateien

| Datei | Zuständigkeit |
|---|---|
| `src/shared/BuddyRemotes.lua` | RemoteEvent/RemoteFunction-Kanäle + einzige Quelle der Wahrheit für den `CollectionService`-Tag `"PlayerBuddy"` |
| `src/server/BuddyService.lua` | Besitz-Validierung, Persistenz, Buddy-Modell-Lebenszyklus (Erstellen/Zerstören/Respawn-Reset) |
| `src/server/BuddyServer.server.lua` | Dünnes Bootstrap-Skript, verdrahtet BuddyRemotes <-> BuddyService |
| `src/client/BuddyClient.client.lua` | Rein kosmetischer Renderer: Follow-Bewegung, Bob, Blickrichtung, Rarity-Flair, Nameplate |

Additiv erweitert (kein bestehendes Verhalten verändert):

- `src/server/PlayerDataService.lua`: neues `BuddyState` (`CreatureId: string?`)
  + `GetBuddyCreatureId`/`SetBuddyCreatureId`. `SCHEMA_VERSION` 5 -> 6 (reine
  Feld-Ergänzung, identisches Migrations-Muster wie `CodexState`).
- `src/client/CodexUIController.client.lua`: neuer "🐾"-Button auf jeder
  besessenen Kreaturen-Karte ("Set as buddy" / entfernen bei erneutem
  Klick), spiegelbildlich zum bestehenden Favoriten-Stern-Button.

## Bewegungs-Architektur: bewusst KOMPLETT CLIENT-GETRIEBEN

Das ist die zentrale Design-Entscheidung dieses Systems und unterscheidet
sich bewusst von `CreatureDisplayService` (Plot-Kreaturen), das
server-seitig tickt und die Positionen an alle Clients repliziert.

**Warum hier NICHT dasselbe Muster?**

Eine frei wandernde Plot-Kreatur hat kein reales "Bewegungsvorbild" - ihre
Zielpunkte sind zufällig gewählt, es gibt nichts, worauf ein Client seine
eigene Position lokal stützen könnte, ohne den serverseitigen RNG/Zeitablauf
exakt nachzubilden (siehe `CreatureDisplayService`-Kopfkommentar für die
ausführliche Begründung dort). Ein Buddy hingegen folgt IMMER einem
Charakter - und die `HumanoidRootPart`-CFrame dieses Charakters repliziert
bereits **kostenlos** über das normale Roblox-Netzwerk-Replikationssystem
(für die eigentliche Spielerbewegung, die ohnehin für jeden anderen Client
sichtbar sein muss). Ein zusätzlicher Server-Tick-Loop, der eine
Buddy-Position berechnet UND repliziert, wäre also reine Redundanz zu
Daten, die bereits da sind.

**Konkret:**

- Server (`BuddyService`) erstellt/zerstört nur das Buddy-`Model` (Anchored,
  nicht kollidierend, mit `OwnerUserId`/`CreatureId`-Attributen + dem
  `"PlayerBuddy"`-Tag) und setzt es einmalig auf eine sinnvolle
  Startposition (bei Erstellung UND bei jedem Charakter-Respawn, damit es
  nicht an der Stelle des vorherigen toten Charakters "hängen bleibt"). Der
  Server bewegt das Modell danach **nie wieder** selbst.
- Client (`BuddyClient`) findet über `CollectionService`-Tag JEDES
  sichtbare Buddy-Modell (eigenes UND fremde), liest `OwnerUserId`, holt
  sich darüber den Besitzer-`Player`/dessen `Character.HumanoidRootPart`
  (ganz normal repliziert) und berechnet daraus JEDEN Frame (bzw.
  gedrosselt per LOD) lokal eine Zielposition hinter/neben der Schulter,
  nähert sich ihr exponentiell an (schneller bei großem Abstand, sofortiger
  Snap bei SEHR großem Abstand - z. B. direkt nach einem
  `TravelService.PivotTo`-Teleport) und ruft NUR lokal `Model:PivotTo(...)`
  auf.

  Das ist exakt dasselbe Prinzip wie `ProceduralAnimator`
  (`src/shared/CharacterAnimation/`): `Motor6D.C0` wird dort auch nur lokal
  gesetzt, niemals repliziert - "jeder Client animiert/positioniert, was er
  sieht".

**Ergebnis / Kosten-Nutzen:**

- **Netzwerk:** null zusätzlicher Positions-Traffic (im Gegensatz zu
  CreatureDisplayService's CFrame-Deltas, dort aber gerechtfertigt mangels
  Bewegungsvorbild). Nur die einmalige Modell-Erstellung + seltene
  Attribut-/Respawn-Resets replizieren.
- **Glätte:** jeder Client interpoliert mit seiner eigenen Frame-Rate
  (60 FPS auf PC, ggf. weniger auf Handy) statt an eine fixe Server-Tick-
  Rate gebunden zu sein - kein sichtbares "Ruckeln" zwischen Server-Ticks.
- **Phone-Freundlichkeit:** kein zusätzlicher Server-Tick-Loop pro
  Online-Spieler; die Client-Kosten selbst sind trivial (Vektor-Arithmetik)
  und werden durch das LOD-System (siehe unten) für weit entfernte Buddys
  weiter gedrosselt.
- **Trade-off:** unterschiedliche Clients sehen die exakte Buddy-Position
  minimal unterschiedlich (Sub-Frame-Abweichung durch unterschiedliche
  Netzwerk-Latenz/Frame-Rate der Character-Replikation). Das ist bewusst
  akzeptiert, weil ein Buddy rein kosmetisch ist und NULL Gameplay-Wirkung
  hat (kein Hitbox/Treffer/Sammel-Interaktion) - identisches Akzeptanz-
  Prinzip wie bei der prozeduralen Charakter-Animation selbst.

**Sicherheit:** Da die Positionierung rein kosmetisch/lokal ist, bräuchte
sie ohnehin keine Server-Autorität (Projekt-Grundsatz "kein Client-Trust"
gilt für Dinge mit Gameplay-Konsequenz, z. B. Charakterposition/Teleports
in `TravelService`, NICHT für rein dekorative Darstellung wie hier oder bei
`ProceduralAnimator`). Was WEITERHIN serverseitig validiert wird: die
Buddy-AUSWAHL selbst (`BuddyService.SetBuddy` prüft Besitz gegen
`PlayerDataService.CreatureInventory`, identisch zu
`CodexService.SetFavorites`).

## Follow-Verhalten (Client)

- Zielpunkt: `FOLLOW_OFFSET_LOCAL` relativ zur `HumanoidRootPart`-CFrame des
  Besitzers (rechts + leicht erhöht + hinten - "hinter/neben der
  Schulter").
- Sanftes "Aufholen": exponentielle Annäherung, deren Rate mit dem
  aktuellen Abstand skaliert (`CATCHUP_REFERENCE_DISTANCE_STUDS`/
  `MAX_CATCHUP_MULTIPLIER`) - bei kleinem Abstand butterweich, bei großem
  Abstand (z. B. Besitzer ist gesprintet) zügiges Aufholen.
- Teleport-Snap: jenseits `SNAP_DISTANCE_STUDS` wird sofort geschnappt statt
  über mehrere Sekunden "hinterherzufliegen" (Teleports via TravelService
  sind ein harter `Character:PivotTo`-Sprung, kein Tween).
- Blickrichtung: der Buddy dreht sich in seine EIGENE Bewegungsrichtung
  (aus dem Bewegungsdelta pro Frame, nicht zwingend identisch zur
  Blickrichtung des Besitzers) - identisches Prinzip zu
  `CreatureDisplayService.tickSlot`s `LastYaw`-Berechnung.
- Bob: einfache Sinus-Schwingung on top, individuelle Phase/Geschwindigkeit
  je Buddy (kein Sync-Pumpen zwischen mehreren gleichzeitig sichtbaren
  Buddys).

## LOD (Distanz-gedrosselte Updates)

Identisches Prinzip zu `CharacterAnimator.client.lua`s Rig-LOD: Kamera-Nähe
(`LOD_FULL_DISTANCE_STUDS`) aktualisiert jeden Frame, mittlere Distanz
(`LOD_REDUCED_DISTANCE_STUDS`) gedrosselt (~8 Hz), sehr weit entfernte kaum
noch (~1.7 Hz) - hält die Kosten selbst bei vielen gleichzeitig sichtbaren
Spielern (+ deren Buddys) klein genug fürs Handy. Die LOD-Klasse selbst wird
nur alle `LOD_RECOMPUTE_INTERVAL` Sekunden neu bestimmt (Kamera-Abstands-
Berechnung ist billig, aber nicht kostenlos).

## Rarity-Flair (Legendary/Mythic)

- **Trail:** zwei `Attachment`s am `PrimaryPart` + ein `Trail` dazwischen -
  praktisch kostenlos (vom Engine-Renderer aus der Attachment-
  Positionshistorie erzeugt, kein Pro-Frame-Skriptaufwand).
- **Sparkle-Burst:** gepooltes Partikelsystem (fester `Part`+
  `ParticleEmitter`-Pool, round-robin wiederverwendet statt pro Emit neu
  erzeugt/zerstört - identisches Grundprinzip zu
  `src/shared/CharacterAnimation/EffectsPool.lua`, hier bewusst
  eigenständig implementiert statt jenes Moduls requiret, da dessen
  eigener Kopfkommentar es exklusiv für `CharacterAnimator.client.lua`
  reserviert). Feuert selten (`SPARKLE_EMIT_INTERVAL_SECONDS`), nur bei
  `LOD == "Full"`.
- Beide respektieren `UIKit.Settings.GetReducedEffects()` (live über
  `Settings.Changed` nachgezogen für den Trail, geprüft bei jedem Emit für
  den Sparkle-Burst).

## Nameplate

Kleines `BillboardGui` mit dem Kreaturen-Namen (Attribut `CreatureName` vom
Buildscript-Template, Fallback `CreatureId`/Modellname) in Rarity-Farbe
(`UIKit.Theme.Rarity`). `BillboardGui.MaxDistance` begrenzt die Render-
Kosten zusätzlich zum LOD-System.

**Toggle:** Tastenkürzel **V** (`ContextActionService`, erzeugt automatisch
auch einen Touch-Button auf Mobile - identisches Muster zu
`CharacterAnimator`s Sprint-Taste). BEWUSSTE VEREINFACHUNG statt eines
Toggles im Optionsmenü: `MainMenuController.client.lua` (inkl. seines
`buildSettingsPanel`) gehört nicht zu diesem Auftrag, und ein eigenes
Options-Panel nur für diesen einen Toggle wäre unverhältnismäßig. Der
Touch-Button-Titel ("Buddy Names") ist spielerseitig sichtbar und daher
bewusst Englisch (siehe Abschnitt "Sprache" unten).

## Zwei-Hand-Trage-Konflikt (`HeldItemService.CarryPose`)

Der Buddy folgt HINTER/NEBEN der Schulter, die Zwei-Hand-Trage-Pose
(`PoseLibrary.CarryTwoHand`) bewegt die Arme nach VORNE - beide
Bewegungsbereiche überschneiden sich in der Praxis nicht. Der Buddy wird
deshalb **nicht ausgeblendet** (Auftrag: "only if it visually clips -
otherwise keep it"). Als günstige Sicherheitsmarge für ungewöhnlich breite,
künftige Trage-Items wird der Folge-Abstand während `CarryPose == "TwoHand"`
minimal vergrößert (`TWO_HAND_EXTRA_BACK_OFFSET`), ohne den Buddy jemals zu
verstecken.

## Persistenz + Besitz-Validierung

- `PlayerDataService.BuddyState.CreatureId` speichert (wie
  `CodexState.Favorites`) eine Kreaturen-**ART**, keine einzelne
  `CreatureInstance.InstanceId` - identische Begründung: eine Raid-
  Entführung EINER Instanz soll den Buddy nicht invalidieren, solange noch
  eine andere Instanz derselben Art besessen wird.
- `BuddyService.SetBuddy` validiert JEDE Anfrage serverseitig neu (Besitz
  gegen `PlayerDataService.CreatureInventory`) - der Client liefert nur
  eine Absichtserklärung (`BuddyRemotes.RequestSetBuddy`).
- `BuddyService.RefreshForPlayer` revalidiert die persistierte Wahl bei
  Join, nach `GameEvents.RaidLost` (Entführung kann die letzte Instanz
  einer Buddy-Art wegnehmen) und zusätzlich alle 25s als günstiges
  Sicherheitsnetz (identisches Prinzip zu `CreatureDisplayService`s
  `SAFETY_RESYNC_INTERVAL_SECONDS`) - wird die Art nicht mehr besessen,
  wird der Buddy automatisch gelöscht (Modell UND persistierter Wert).

## Cleanup-Lebenszyklus

- **Tod/Respawn:** `BuddyService.ResetPositionForRespawn` setzt das
  Buddy-Modell bei `CharacterAdded` neben den neuen Charakter zurück (der
  Client zieht die echte Zielposition ohnehin sofort selbst nach, siehe
  Bewegungs-Architektur oben) - reine Bequemlichkeit gegen einen unnötig
  langen sichtbaren Anlaufweg direkt nach dem Respawn.
- **Verlassen:** `BuddyService.CleanupPlayer` (an `Players.PlayerRemoving`)
  zerstört das Modell; die persistierte Wahl bleibt erhalten und wird beim
  nächsten Join wiederhergestellt (`RefreshForPlayer`).
- **Client-seitig:** `BuddyClient` hängt sich an `Model.AncestryChanged`,
  um seinen lokalen Zustand (Billboard-Referenz, Follow-Zustand)
  aufzuräumen, sobald das Modell (durch obige Server-Events ODER
  `Workspace.StreamingEnabled`-Streaming-Out) den Workspace verlässt -
  Billboard/Trail/Attachments sind Kinder des Modells und werden mit ihm
  automatisch zerstört.

## Sprache (Player-visible Strings)

Alle NEU hinzugefügten, spielerseitig sichtbaren Texte dieses Systems
(Button-Beschriftungen "🐾"/"🐾 Buddy" auf den Kodex-Karten, die
Buddy-Toast-Meldungen, der Touch-Button-Titel "Buddy Names") sind bewusst
**Englisch**, gemäß aktueller Projektvorgabe. Das bestehende, umgebende
Kodex-Panel (`CodexUIController.client.lua`) ist weiterhin größtenteils
Deutsch - dessen Übersetzung ist NICHT Teil dieses Auftrags (separater
Übersetzungs-Durchgang folgt laut Auftrag). Code-Kommentare/Dev-Doku
(dieses Dokument) bleiben konsistent zum restlichen Projekt auf Deutsch.

## Nicht in diesem Auftrag enthalten

- Ein eigenes Options-Panel-Toggle für Nameplates (siehe Abschnitt
  "Nameplate" - bewusste Tastenkürzel-Vereinfachung stattdessen).
- Echte Sparkle-/Trail-Textur-Assets (Platzhalter-`rbxasset://`-Texturen,
  identische Konvention wie `EffectsPool.lua`) - finale Textur-Asset-IDs
  sind Aufgabe eines künftigen 3D-/VFX-Asset-Agenten.
- Mehrere gleichzeitige Buddys pro Spieler (Auftrag: "one owned creature").
