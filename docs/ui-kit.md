# Abyssara UIKit – API-Doku für Menü-Umstellungen

Dieses Dokument richtet sich an den nächsten Agenten, der bestehende Menüs
(`HUDController`, `GachaOpenClient`, `GachaOddsUIController`,
`BreedingUIController`, `RaidUIController`, `PlacementPreviewController`,
...) auf das gemeinsame UIKit umstellt.

Quellcode: `src/shared/UIKit/` (Rojo-Mapping: `ReplicatedStorage.UIKit`).
Demo (nur zu Referenzzwecken, standardmäßig deaktiviert):
`src/client/UIKitDemo.client.lua`.

```lua
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))
```

## HARTE REGEL: Keine Buttons außerhalb der Factory

**Es darf im gesamten Projekt kein `TextButton`/`ImageButton` mehr direkt per
`Instance.new("TextButton")` gebaut werden, wenn es klickbar sein soll.**
Ausnahmslos `UIKit.Button.new({...})` verwenden. Nur so sind garantiert:

- Responsive Größe/Text (siehe Abschnitt "Responsivität" unten) auf JEDEM Gerät,
- Hover/Press/Ripple/Partikel/Sound-FX,
- Mindest-Touch-Zielgröße ~44px als echte Pixel-Untergrenze,
- Gamepad-Selektion (`Selectable` + sichtbares `SelectionImageObject`),
- Disabled-Zustand,
- Reduzierte-Effekte-Unterstützung.

Ein einzelner "nackter" Button umgeht alle diese Garantien und bricht die
Konsistenz. Beim Umstellen bestehender Menüs: bestehende `TextButton`-
Instanzen durch `UIKit.Button.new(...)` ersetzen, nicht nur stylen.

## Geräteklassen (`UIKit.Device`)

`Device.GetState()` liefert:

```lua
{
  Class = "Phone" | "Tablet" | "Console" | "PC",
  HasTouch: boolean, HasKeyboard: boolean, HasGamepad: boolean,
  IsTenFoot: boolean, Scale: number, ViewportSize: Vector2,
}
```

Erkennung: `UserInputService.TouchEnabled/KeyboardEnabled/GamepadEnabled`,
`GuiService:IsTenFootInterface()`, `Camera.ViewportSize` (Kurzseite
unterscheidet Phone/Tablet). `Device.Changed:Connect(fn)` feuert live bei
Rotation/Fenstergrößenänderung.

Wichtige Helfer:

- `Device.GetScale()` – zentraler Skalierungsfaktor (0.62–1.35), aus
  Viewport-Kurzseite berechnet, mit Touch-Boost.
- `Device.BindUIScale(uiScale, multiplier?)` – bindet ein `UIScale`-Objekt
  dauerhaft an den Skalierungsfaktor, gibt eine Unbind-Funktion zurück.
  `UIKit.Panel` macht das bereits automatisch für sein gesamtes Fenster –
  **eigene Menüs sollten EIN UIScale pro Screen/Panel binden, nicht pro
  Widget.**
- `Device.ApplySafeArea(screenGui)` – setzt `ScreenInsets = DeviceSafeInsets`
  (Notch/Punch-Hole) und liefert den `GuiService:GetGuiInset()`-Wert.
- `Device.ShouldShowKeyboardHints()` – nur true, wenn echte Tastatur da ist
  (für "[E] Interagieren"-Hinweise etc.).
- `Device.ShouldShowGamepadHints()` – true auf Konsole/reinem Gamepad-Input.
- `Device.ShouldUseFullscreenPanels()` – true auf Phone (Panels sollten dort
  Vollbild sein statt zentriertes Fenster).
- `Device.ClampTouchSize(px)` – klemmt eine gewünschte Pixelgröße auf
  mindestens `Device.MinTouchSize` (44), wenn Touch aktiv ist.

## Responsivität – bindende Regeln für alle Widgets

Diese Regeln gelten für **jedes** UIKit-Widget und für jeden Code, der neue
Menüs auf UIKit aufbaut:

1. **Nie feste Pixelgrößen ohne Skalierungsweg.** Breiten immer relativ
   (`UDim2.new(1, 0, 0, H)`), Höhen dürfen offset-basiert sein, weil sie über
   das vom Panel gebundene `UIScale` automatisch mitskalieren.
2. **Text immer `TextScaled = true` + `UITextSizeConstraint`** (Min/Max-
   Textgröße), nie eine feste `TextSize` ohne Constraint. `UIKit.Button`,
   `UIKit.Panel`-Titel, `UIKit.Toast`, `UIKit.RarityBadge` machen das bereits
   automatisch.
3. **Touch-Mindestgröße ist ein `UISizeConstraint` auf `AbsoluteSize`,
   kein Offset-Wert.** `UISizeConstraint.MinSize` wirkt auf die tatsächliche
   gerenderte Pixelgröße – unabhängig davon, was `UIScale`-Vorfahren tun.
   `UIKit.Button` setzt das automatisch und aktualisiert es live bei
   Geräteänderung (`Device.Changed`).
4. **Layout reagiert live auf Rotation/Fenstergröße.** Nutze
   `UIKit.Layout.ResponsiveRow(...)` für Button-Reihen (auf Phone: eine
   Spalte, volle Breite; auf Tablet/PC/Konsole: horizontale Reihe mit
   Umbruch) und `UIKit.Layout.FullscreenOrCentered(frame, sizing)` für
   Fenster (macht `UIKit.Panel` schon selbst).
5. **Gleiches Feedback, unterschiedlicher Auslöser.** `UIKit.Button` gibt
   Hover-Glow nur bei echtem Maus-Hover (`MouseEnter`/`MouseLeave`, wird auf
   Touch-Geräten übersprungen); Touch/Maus-Klick lösen stattdessen sofort
   den Press-Squash aus. Gamepad-Selektion (`SelectionGained`/`SelectionLost`)
   löst denselben Glow wie Hover aus und zeigt zusätzlich ein sichtbares
   `SelectionImageObject`.

## Farben (`UIKit.Theme`)

```lua
Theme.Background.{Deepest, Deep, Panel, PanelLight, Divider}
Theme.Neon.{Cyan, Magenta, ToxicGreen, Orange, Violet, Yellow}
Theme.Text.{Primary, Secondary, Muted, Stroke, OnNeon}
Theme.Semantic.{Primary, Secondary, Success, Danger, Warning, Info}
Theme.Rarity.{Common, Uncommon, Rare, Epic, Legendary, Mythic}  -- Color3
Theme.RarityLabel.{...} -- deutsche Anzeigenamen
Theme.RarityOrder -- { "Common", ..., "Mythic" }
Theme.Font.{Header, Body, BodyBold, Mono}
```

**`Theme.Rarity` MUSS farblich konsistent mit
`src/server/GachaConfig.lua` (`DROP_TABLE[*].Color`) und
`src/shared/BreedingConfig.lua` (`RARITY_DEFINITIONS`) bleiben** – die Werte
wurden 1:1 von dort übernommen. Ändert sich dort eine Farbe, hier
nachziehen (und umgekehrt).

Hilfsfunktionen: `Theme.ApplyStroke(obj, color?, thickness?)`,
`Theme.ApplyGradient(obj, {color3, ...}, rotation?)`,
`Theme.ApplyCorner(obj, radius?)`.

## Button (`UIKit.Button`)

```lua
local button = UIKit.Button.new({
    Parent = someFrame,
    Text = "Kaufen",
    Variant = "Primary", -- "Primary" | "Secondary" | "Success" | "Danger" | "Ghost"
    Size = UDim2.new(1, 0, 0, 48), -- optional, Default: volle Breite, 44px hoch
    Icon = "rbxassetid://...", -- optional
    Important = true, -- optional: Idle-Pulsieren (z. B. "Kaufen"-CTA)
    Disabled = false, -- optional
    LayoutOrder = 1,
})

button.Clicked:Connect(function()
    -- Klick-Logik. WICHTIG: Client-Klick ist nie Autorität – immer über
    -- RemoteEvent/RemoteFunction serverseitig validieren (Anti-Exploit).
end)

button:SetDisabled(true)
button:SetText("Ausverkauft")
button:Destroy() -- WICHTIG beim Schließen eines Menüs: räumt Connections/Tweens/Pulse-Threads auf
```

Jeder Button bekommt automatisch: Hover-Glow (nur Maus), Press-Squash,
Partikel-Burst (gepoolt), Ripple, Klick-Sound, optionales Idle-Pulsieren
(`Important = true`), Disabled-Visuals, Gamepad-Selektionsrahmen,
Touch-Mindestgröße, textbegrenztes `TextScaled`.

## Panel (`UIKit.Panel`)

```lua
local panel = UIKit.Panel.new({
    Title = "Brutbecken",
    Closable = true, -- Default true, baut automatisch einen X-Button (aus der Button-Factory)
    CenteredSize = UDim2.fromOffset(560, 420), -- Größe im Tablet/PC/Konsole-Modus
    OnClose = function() ... end,
})

panel:Open()  -- Einblend-Animation
panel:Close() -- Ausblend-Animation, feuert danach panel.Closed und OnClose
panel.Closed:Connect(function() ... end)
panel:Destroy() -- endgültig entfernen (Connections, UIScale-Binding, Layout-Binding sauber getrennt)

panel.Content -- Frame, hier eigene Widgets reinbauen
```

Panel bindet automatisch **ein** `UIScale` fürs ganze Fenster
(`Device.BindUIScale`) und positioniert sich via
`Layout.FullscreenOrCentered` (Vollbild auf Phone, zentriert sonst) sowie
`Device.ApplySafeArea` (Notch/Safe-Area).

## Tabs (`UIKit.Tabs`)

```lua
local tabs = UIKit.Tabs.new({
    Parent = panel.Content,
    Tabs = { { Id = "Overview", Label = "Übersicht" }, { Id = "Feed", Label = "Füttern" } },
    DefaultTabId = "Overview",
})
local overviewContent = tabs:GetContentFrame("Overview") -- ScrollingFrame mit eigenem UIListLayout, hier eigene Kinder reinbauen (KEIN zusätzliches UIListLayout hinzufügen)
tabs.Selected:Connect(function(id) ... end)
tabs:SelectTab("Feed")
tabs:Destroy()
```

## Toast (`UIKit.Toast`)

```lua
UIKit.Toast.Show({ Text = "500 Tide Coins erhalten!", Type = "Success", Duration = 3.5 })
-- Type: "Info" | "Success" | "Warning" | "Error"
```

Kein manuelles Init nötig (lazy). Position ist geräteabhängig (oben-rechts
auf PC/Konsole, unten-zentriert auf Phone/Tablet) und stapelt automatisch.

## CountUp (`UIKit.CountUp`)

```lua
UIKit.CountUp.Animate(label, currentValue, newValue, 0.8) -- tweent label.Text hoch/runter mit Tausenderpunkt-Format
```

## ProgressBar (`UIKit.ProgressBar`)

```lua
local bar = UIKit.ProgressBar.new({ Parent = frame, Size = UDim2.new(1,0,0,18), Colors = { UIKit.Theme.Neon.Cyan, UIKit.Theme.Neon.Violet } })
bar:SetProgress(0.42) -- animiert; bar:SetProgress(0.42, false) für sofortiges Setzen
```

## RarityBadge (`UIKit.RarityBadge`)

```lua
local badge = UIKit.RarityBadge.new({ Parent = frame, Rarity = "Legendary" })
badge:SetRarity("Mythic")
```

## ConfirmDialog (`UIKit.ConfirmDialog`)

```lua
UIKit.ConfirmDialog.Show({
    Title = "Wirklich verkaufen?",
    Message = "Diese Aktion kann nicht rückgängig gemacht werden.",
    Danger = true,
    ConfirmText = "Verkaufen", CancelText = "Abbrechen",
    OnConfirm = function() end,
    OnCancel = function() end,
})
```

Selbstständig (öffnet, baut Buttons, räumt sich nach Entscheidung selbst
auf – kein manuelles `:Destroy()` nötig).

## ScreenFX (`UIKit.ScreenFX`)

```lua
UIKit.ScreenFX.Flash({ Color = UIKit.Theme.Neon.ToxicGreen, Duration = 0.5 }) -- Level-Up
UIKit.ScreenFX.Shake(0.25, 0.4) -- magnitudeStuds, duration (additiver Kamera-Shake NACH Enum.RenderPriority.Camera, kein Ownership-Konflikt mit anderen Kamera-Skripten)
UIKit.ScreenFX.BigMoment(UIKit.Theme.Rarity.Mythic) -- Flash + Shake kombiniert, z. B. Mythic-Gacha-Drop
```

## Reduzierte Effekte (`UIKit.Settings`)

```lua
UIKit.Settings.SetReducedEffects(true) -- deaktiviert Partikel-Burst, Idle-Pulsieren, Screen-Shake/-Flash global
UIKit.Settings.GetReducedEffects()
UIKit.Settings.Changed:Connect(function(key, value) ... end)
```

Noch nicht an ein echtes Einstellungsmenü/DataStore angebunden – das ist
Aufgabe des Menü-Agenten (z. B. Toggle im Optionsmenü, Wert aus
Spieler-Profil laden).

## Sounds (`UIKit.SoundConfig`)

Alle Klick-/Feedback-Sounds sind zentral in `SoundConfig.lua` mit klar als
**PLATZHALTER** markierten `rbxassetid`-Werten hinterlegt. Vor Launch dort
final abgemischte Sounds eintragen – kein anderes Modul referenziert
Sound-IDs direkt.

## Demo

`src/client/UIKitDemo.client.lua` ist standardmäßig **deaktiviert**. Zum
Testen in Studio:

```lua
workspace:SetAttribute("UIKitDemoEnabled", true)
```

Zeigt alle Bausteine in einem Panel mit vier Tabs (Buttons, Widgets,
Rarity, Screen-FX) inkl. Live-Geräteinfo-Anzeige.
