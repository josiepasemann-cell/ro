# Abyssara UIKit – API docs for menu conversions

This document is aimed at the next agent converting existing menus
(`HUDController`, `GachaOpenClient`, `GachaOddsUIController`,
`BreedingUIController`, `RaidUIController`, `PlacementPreviewController`,
...) over to the shared UIKit.

Source: `src/shared/UIKit/` (Rojo mapping: `ReplicatedStorage.UIKit`).
Demo (reference only, disabled by default):
`src/client/UIKitDemo.client.lua`.

```lua
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))
```

## HARD RULE: No buttons outside the factory

**No `TextButton`/`ImageButton` may be built anywhere in the project
directly via `Instance.new("TextButton")` if it's meant to be clickable.**
Always use `UIKit.Button.new({...})`, no exceptions. Only this guarantees:

- Responsive size/text (see the "Responsiveness" section below) on EVERY device,
- Hover/press/ripple/particle/sound FX,
- A minimum touch target size of ~44px as a real pixel floor,
- Gamepad selection (`Selectable` + a visible `SelectionImageObject`),
- Disabled state,
- Reduced-effects support.

A single "bare" button bypasses all of these guarantees and breaks
consistency. When converting existing menus: replace existing `TextButton`
instances with `UIKit.Button.new(...)`, don't just style them.

## Device classes (`UIKit.Device`)

`Device.GetState()` returns:

```lua
{
  Class = "Phone" | "Tablet" | "Console" | "PC",
  HasTouch: boolean, HasKeyboard: boolean, HasGamepad: boolean,
  IsTenFoot: boolean, IsPortrait: boolean, Scale: number, ViewportSize: Vector2,
}
```

Detection: `UserInputService.TouchEnabled/KeyboardEnabled/GamepadEnabled`,
`GuiService:IsTenFootInterface()`, `Camera.ViewportSize` (short side
distinguishes Phone/Tablet). `Device.Changed:Connect(fn)` fires live on
rotation/window size changes.

Important helpers:

- `Device.GetScale()` – central scale factor per class: Phone
  `short side / 400` (0.9–1.15), Tablet 0.95–1.3, PC 0.8–1.5, Console /
  10-foot `short side / 720 * 1.15` (1.15–1.7).
- `Device.CreateScaledRoot(screenGui)` – **the only correct way to scale a
  ScreenGui.** Returns `(root, unbind)`: a full-screen frame whose size is
  `1 / Scale` with the `UIScale` as its child. Put ALL your widgets under
  `root`. A bare `UIScale` directly under a `ScreenGui` scales around the
  top-left corner, so centered/bottom/right-anchored elements land in the
  wrong place and "full width" frames end up too small or too large.
  `UIKit.Panel`, `UIKit.Toast` and every HUD controller use it.
  `Device.BindUIScale(uiScale)` still exists but is only for UIScales that
  are NOT directly under a ScreenGui.
- `Device.GetVirtualViewport()` – visible area in scaled ("virtual") pixels,
  i.e. the size a scaled root actually offers.
- `Device.IsPortrait()`, `Device.IsTouchPrimary()` (Phone/Tablet),
  `Device.GetMinTargetSize()` (44 touch, 52 console).
- `Device.GetBottomDockInsets()` – `(side, bottom)` in virtual px that
  bottom-docked UI must keep free on touch devices for Roblox's thumbstick
  and jump button (portrait: bottom, landscape: left/right).
- `Device.ApplySafeArea(screenGui, insets?)` – sets
  `ScreenInsets = CoreUISafeInsets` by default (clear of notch, home
  indicator, Roblox top bar and core buttons). Pass `Enum.ScreenInsets.None`
  for edge-to-edge overlays.
- `Device.ShouldShowKeyboardHints()` / `ShouldShowGamepadHints()` – follow
  the LAST used input (see `UIKit.InputMode`) instead of "has a keyboard".
- `Device.ShouldUseFullscreenPanels()` – true on Phone (panels fill the
  screen there instead of a centered window).
- `Device.ClampTouchSize(px)` – clamps a desired pixel size to at least
  `Device.MinTouchSize` (44) when touch is active.

## Last used input (`UIKit.InputMode`)

`InputMode.Get()` returns `"Touch" | "Gamepad" | "KeyboardMouse"` and
follows `UserInputService.LastInputTypeChanged` live (start value: console /
10-foot -> Gamepad, touch-only -> Touch, else keyboard/mouse).

- `InputMode.Changed:Connect(function(mode) end)`,
  `InputMode.Bind(fn)` (calls `fn` now and on every change).
- `InputMode.Pick(keyboard, gamepad, touch?)` – picks a value for the
  current mode (e.g. `"G to drop"` / `"B to drop"` / `"tap Drop"`).
- `InputMode.GetGlyph(Enum.KeyCode.ButtonB)` -> `"B"` (PlayStation:
  `"○"`), `Enum.KeyCode.Return` -> `"Enter"`.
- `InputMode.CreateHint({ Parent, Keyboard = "B", Gamepad = Enum.KeyCode.ButtonY, Label? })`
  – small key chip that is visible only in the matching mode (never on
  touch). Use it for "press X" hints instead of static text.

## Layout (`UIKit.Layout`)

- `Layout.FullscreenOrCentered(frame, sizing)` – used by `Panel`; clamps the
  centered window to the visible area and to `MaxWidth` (default 1100, so
  nothing stretches on ultrawide). `FullscreenOnPhone = false` keeps small
  dialogs centered on phones.
- `Layout.GetHudLayout()` – the **central position table** for the permanent
  on-screen elements (`Hud`, `Raid`, `Event`, `Menu`, `Ability`). Portrait
  stacks them from the top, landscape touch puts HUD/raid/event on the left
  and menu/ability on the right, desktop/console centers the HUD at the top
  and docks the menu at the bottom. Nothing permanent sits in the bottom
  corners on touch (thumbstick/jump). Read your position from here instead
  of hard-coding offsets.

## Responsiveness – binding rules for all widgets

These rules apply to **every** UIKit widget and to any code building new
menus on top of UIKit:

1. **Never use fixed pixel sizes without a scaling path.** Widths should
   always be relative (`UDim2.new(1, 0, 0, H)`), heights may be
   offset-based because they scale automatically via the panel's bound
   `UIScale`.
2. **Text always `TextScaled = true` + `UITextSizeConstraint`** (min/max
   text size), never a fixed `TextSize` without a constraint. `UIKit.Button`,
   `UIKit.Panel` titles, `UIKit.Toast`, `UIKit.RarityBadge` already do this
   automatically.
3. **The minimum touch size is a `UISizeConstraint` on `AbsoluteSize`,
   not an offset value.** `UISizeConstraint.MinSize` affects the actual
   rendered pixel size – regardless of what `UIScale` ancestors do.
   `UIKit.Button` sets this automatically and updates it live on device
   changes (`Device.Changed`).
4. **Layout reacts live to rotation/window size.** Use
   `UIKit.Layout.ResponsiveRow(...)` for button rows (on Phone: a single
   column, full width; on Tablet/PC/Console: a horizontal row with
   wrapping) and `UIKit.Layout.FullscreenOrCentered(frame, sizing)` for
   windows (`UIKit.Panel` already does this itself).
5. **Same feedback, different trigger.** `UIKit.Button` gives hover-glow
   only on a real mouse hover (`MouseEnter`/`MouseLeave`, skipped on touch
   devices); touch/mouse clicks instead immediately trigger the press
   squash. Gamepad selection (`SelectionGained`/`SelectionLost`) triggers
   the same glow as hover and additionally shows a visible
   `SelectionImageObject`.

## Colors (`UIKit.Theme`)

```lua
Theme.Background.{Deepest, Deep, Panel, PanelLight, Divider}
Theme.Neon.{Cyan, Magenta, ToxicGreen, Orange, Violet, Yellow}
Theme.Text.{Primary, Secondary, Muted, Stroke, OnNeon}
Theme.Semantic.{Primary, Secondary, Success, Danger, Warning, Info}
Theme.Rarity.{Common, Uncommon, Rare, Epic, Legendary, Mythic}  -- Color3
Theme.RarityLabel.{...} -- rarity display names
Theme.RarityOrder -- { "Common", ..., "Mythic" }
Theme.Font.{Header, Body, BodyBold, Mono}
```

**`Theme.Rarity` MUST stay color-consistent with
`src/server/GachaConfig.lua` (`DROP_TABLE[*].Color`) and
`src/shared/BreedingConfig.lua` (`RARITY_DEFINITIONS`)** – the values were
taken 1:1 from there. If a color changes there, update it here too (and
vice versa).

Helper functions: `Theme.ApplyStroke(obj, color?, thickness?)`,
`Theme.ApplyGradient(obj, {color3, ...}, rotation?)`,
`Theme.ApplyCorner(obj, radius?)`.

## Button (`UIKit.Button`)

```lua
local button = UIKit.Button.new({
    Parent = someFrame,
    Text = "Buy",
    Variant = "Primary", -- "Primary" | "Secondary" | "Success" | "Danger" | "Ghost"
    Size = UDim2.new(1, 0, 0, 48), -- optional, default: full width, 44px tall
    Icon = "rbxassetid://...", -- optional
    Important = true, -- optional: idle pulsing (e.g. a "Buy" CTA)
    Disabled = false, -- optional
    LayoutOrder = 1,
})

button.Clicked:Connect(function()
    -- Click logic. IMPORTANT: a client click is never authoritative –
    -- always validate server-side via RemoteEvent/RemoteFunction (anti-exploit).
end)

button:SetDisabled(true)
button:SetText("Sold Out")
button:Destroy() -- IMPORTANT when closing a menu: cleans up connections/tweens/pulse threads
```

Every button automatically gets: hover glow (mouse only), press squash,
particle burst (pooled), ripple, click sound, optional idle pulsing
(`Important = true`), disabled visuals, gamepad selection frame,
minimum touch size, text-constrained `TextScaled`.

## Panel (`UIKit.Panel`)

```lua
local panel = UIKit.Panel.new({
    Title = "Brood Pool",
    Closable = true, -- default true, automatically builds an X button (from the button factory)
    CenteredSize = UDim2.fromOffset(560, 420), -- size in Tablet/PC/Console mode
    OnClose = function() ... end,
})

panel:Open()  -- fade-in animation
panel:Close() -- fade-out animation, then fires panel.Closed and OnClose
panel.Closed:Connect(function() ... end)
panel:Destroy() -- removes it permanently (connections, UIScale binding, layout binding cleanly disconnected)

panel.Content -- Frame, build your own widgets in here
```

Panel automatically creates **one** scaled root for the whole window
(`Device.CreateScaledRoot`) and positions itself via
`Layout.FullscreenOrCentered` (fullscreen on Phone, centered otherwise) as
well as `Device.ApplySafeArea` (notch/top bar). Gamepad behaviour is built
in: the first usable button gets focus when the panel opens (or when the
player switches to a gamepad), focus is kept inside the topmost panel, the
previous selection is restored on close, and **B closes the topmost
panel** (a `B` hint chip appears next to the X). `panel:SetInitialFocus(obj)`
overrides the first-focus target. `UIKit.Panel.CloseAll()` /
`UIKit.Panel.IsAnyOpen()` let keyboard shortcuts toggle panels.

## Tabs (`UIKit.Tabs`)

```lua
local tabs = UIKit.Tabs.new({
    Parent = panel.Content,
    Tabs = { { Id = "Overview", Label = "Overview" }, { Id = "Feed", Label = "Feed" } },
    DefaultTabId = "Overview",
})
local overviewContent = tabs:GetContentFrame("Overview") -- ScrollingFrame with its own UIListLayout, build your own children in here (do NOT add another UIListLayout)
-- The tab header is always ONE horizontally scrollable row (swipe / mouse wheel);
-- gamepad: LB / RB switch tabs while the panel is on top.
tabs.Selected:Connect(function(id) ... end)
tabs:SelectTab("Feed")
tabs:Destroy()
```

## Toast (`UIKit.Toast`)

```lua
UIKit.Toast.Show({ Text = "Received 500 Tide Coins!", Type = "Success", Duration = 3.5 })
-- Type: "Info" | "Success" | "Warning" | "Error"
```

No manual init needed (lazy). Position is device-dependent (bottom-right
on PC/Console; bottom-centered on Phone/Tablet but outside the
thumbstick/jump zone) and stacks automatically. Toasts never take input.

## CountUp (`UIKit.CountUp`)

```lua
UIKit.CountUp.Animate(label, currentValue, newValue, 0.8) -- tweens label.Text up/down with thousands-separator formatting
```

## ProgressBar (`UIKit.ProgressBar`)

```lua
local bar = UIKit.ProgressBar.new({ Parent = frame, Size = UDim2.new(1,0,0,18), Colors = { UIKit.Theme.Neon.Cyan, UIKit.Theme.Neon.Violet } })
bar:SetProgress(0.42) -- animated; bar:SetProgress(0.42, false) for an instant set
```

## RarityBadge (`UIKit.RarityBadge`)

```lua
local badge = UIKit.RarityBadge.new({ Parent = frame, Rarity = "Legendary" })
badge:SetRarity("Mythic")
```

## ConfirmDialog (`UIKit.ConfirmDialog`)

```lua
UIKit.ConfirmDialog.Show({
    Title = "Really sell this?",
    Message = "This action cannot be undone.",
    Danger = true,
    ConfirmText = "Sell", CancelText = "Cancel",
    OnConfirm = function() end,
    OnCancel = function() end,
})
```

Self-contained (opens, builds buttons, cleans itself up after the decision
– no manual `:Destroy()` needed). Stays a small centered dialog on phones;
on a gamepad focus starts on Confirm (on Cancel when `Danger = true`) and B
cancels.

## ScreenFX (`UIKit.ScreenFX`)

```lua
UIKit.ScreenFX.Flash({ Color = UIKit.Theme.Neon.ToxicGreen, Duration = 0.5 }) -- level-up
UIKit.ScreenFX.Shake(0.25, 0.4) -- magnitudeStuds, duration (additive camera shake AFTER Enum.RenderPriority.Camera, no ownership conflict with other camera scripts)
UIKit.ScreenFX.BigMoment(UIKit.Theme.Rarity.Mythic) -- Flash + Shake combined, e.g. a Mythic gacha drop
```

## Reduced effects (`UIKit.Settings`)

```lua
UIKit.Settings.SetReducedEffects(true) -- globally disables particle burst, idle pulsing, screen shake/flash
UIKit.Settings.GetReducedEffects()
UIKit.Settings.Changed:Connect(function(key, value) ... end)
```

Not yet wired to a real settings menu/DataStore – that's the job of the
menu agent (e.g. a toggle in the options menu, loading the value from the
player profile).

## Sounds (`UIKit.SoundConfig`)

All click/feedback sounds are stored centrally in `SoundConfig.lua` with
`rbxassetid` values clearly marked as **PLACEHOLDERS**. Enter the final
mixed sounds there before launch – no other module references sound IDs
directly.

## Demo

`src/client/UIKitDemo.client.lua` is **disabled** by default. To test it in
Studio:

```lua
workspace:SetAttribute("UIKitDemoEnabled", true)
```

Shows all building blocks in a panel with four tabs (Buttons, Widgets,
Rarity, Screen FX) including a live device-info display.
