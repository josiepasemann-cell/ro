# Device support: phone, tablet, PC, console

Status: **reviewed and changed by reading the code; nothing has run in
Studio yet.** Every changed file was compiled with `luau-compile`; the
`src/client` + `src/shared/UIKit` tree was type-checked with `luau-lsp` before
and after with an identical diagnostic set (49 pre-existing notes, no new
ones). Everything below marked "verified" means "verified in code", not "seen
on a device". The Studio test plan at the end is the real acceptance test.

## 1. What was wrong (audit result)

| # | Problem | Where | Effect |
|---|---------|-------|--------|
| 1 | A `UIScale` placed directly under a `ScreenGui` scales around the top-left corner. | every HUD / panel / toast | Centered or bottom/right-anchored elements land off-position, "full width" frames are 62 % wide on phones and overflow on big screens, the modal dim did not cover the screen. |
| 2 | Phone scale floor 0.62 | `Device` | A 14 px label rendered at about 9 px on a 360x640 phone. |
| 3 | 12 buttons in one scrolling row, docked at the bottom | `MainMenuController` | Unusable on phones and under Roblox's thumbstick / jump button. |
| 4 | `GuiService.SelectedObject` set to the first menu button at start | `MainMenuController` | A console player could not walk until the selection was cleared. |
| 5 | HUD, raid bar, event banner and ability panel each hard-coded their own position | 4 controllers | Event banner overlapped the raid bar; HUD overlapped the default chat window on PC. |
| 6 | Gamepad cursor overwritten every frame by the mouse position | `PlacementPreviewController` | L1 / R1 field cycling never worked on console. |
| 7 | Touch taps used `ViewportPointToRay` with a touch position | `PlacementPreviewController` | Build target was off by the top bar height. |
| 8 | Build bar (cards + 5 actions in a column) 300 px tall | `PlacementPreviewController` | Covered a landscape phone completely, sat on the thumbstick. |
| 9 | Tab header = `ResponsiveRow` (column on phone) inside a fixed 44 px header | `UIKit.Tabs` | Tabs overflowed out of the header on phones (Shop has 5 tabs). |
| 10 | `ClickDetector` was the only way to open Brood Pool / upgrade panels | Breeding, Placement | Not usable with a gamepad. |
| 11 | Gamepad focus: no focus on panel open, no way to leave a panel, focus could wander into the menu behind a dialog | `UIKit.Panel` | Console players got stuck. |
| 12 | Touch targets below 44 px inside cards (claim buttons 30 px, Codex stars 30 px, +/- 32 px) overlapped the next element once the 44 px minimum kicked in | Quest, Achievement, Codex, Settings, Raid, Event, Shop | Overlapping buttons. |
| 13 | Min text sizes of 8 to 11 px | many | Unreadable on phones. |
| 14 | Onboarding spotlight used a `UIScale` on masks given in absolute pixels; target lookup could pick a hidden button | `OnboardingController` | Spotlight misplaced, wrong target. |
| 15 | Two German player-facing strings ("(Du)", "Quest-Linie") | Leaderboard, Event | Language rule. |

## 2. What changed

### UIKit (central)

| File | Change |
|------|--------|
| `src/shared/UIKit/InputMode.lua` (new) | Last-used input (`Touch` / `Gamepad` / `KeyboardMouse`) with a change signal, `Pick`, `GetGlyph` (A/B/X/Y, PlayStation symbols), `CreateHint` key chips. |
| `src/shared/UIKit/Device.lua` | Per-class scale (phone 0.9-1.15, tablet 0.95-1.3, PC 0.8-1.5, console 1.15-1.7), `CreateScaledRoot`, `IsPortrait`, `IsTouchPrimary`, `GetVirtualViewport`, `GetBottomDockInsets`, `GetMinTargetSize`; safe area now `CoreUISafeInsets`. |
| `src/shared/UIKit/Layout.lua` | `FullscreenOrCentered` clamps to the visible area and `MaxWidth`; new `GetHudLayout()` central position table. |
| `src/shared/UIKit/Panel.lua` | Scaled root, safe area, modal stack, first-focus, focus trap, restore selection, B closes, `B` hint chip, `SetInitialFocus`, `CloseAll`, 44 px close button, close/open race fixed. |
| `src/shared/UIKit/Tabs.lua` | One horizontally scrolling header, selected tab scrolled into view, LB / RB switch tabs, focus moves to the tab when its content is hidden. |
| `src/shared/UIKit/Toast.lua` | Scaled root; touch: above the thumbstick / jump zone; PC / console: bottom right; never takes input. |
| `src/shared/UIKit/ConfirmDialog.lua` | Small centered dialog on phones, buttons always side by side, gamepad focus on Confirm (Cancel for `Danger`). |
| `src/shared/UIKit/Button.lua` | Minimum target 44 px (touch) / 52 px (console), hover FX follow `InputMode`. |

### Controllers

| Controller | Change |
|------------|--------|
| `MainMenuController` | **New menu structure** (below). Y / View focus, B back, shortcut toggle, `AutoSelectGuiEnabled = false`, no forced focus at start, settings panel: 44 px +/- buttons and an input-aware controls help line. |
| `HUDController`, `RaidUIController`, `AbilityHUDController`, `EventUIController` | Scaled root + position from `Layout.GetHudLayout()`; level-up banner sized to the viewport and moved below the HUD stack; Depth Charge now also on key `F` / gamepad RT (bound only during a raid on the own plot) with a hint chip. |
| `HeldItemClient`, `IdleIncomeClient` | Scaled root; popups sit above the menu (desktop) or above the thumbstick / jump zone (touch); drop on gamepad moved from X to **B** (X belongs to ProximityPrompts); hint text follows the input (`G` / `B` / "tap Drop"). |
| `PlacementPreviewController` | Rewritten build bar (info row, scrolling cards, one row of 5 two-line action buttons), touch tap uses `ScreenPointToRay`, mouse aiming only in keyboard / mouse mode, gamepad actions X build / Y rotate / B done bound only in build mode, key chips, `ProximityPrompt` for the upgrade panel (gamepad only). |
| `BreedingUIController` | Gamepad-only `ProximityPrompt` per Brood Pool (the `ClickDetector` stays for mouse / touch), 44 px overview buttons. |
| `OnboardingController` | Mask / ring / arrow unscaled in absolute pixels, card on a scaled root, only visible targets (falls back to "More"), ring and masks block clicks, gamepad focus on Next. |
| `TravelUIController` | Narrow card layout (smaller button, less reserved width), 48 px buttons, min text 12. |
| `QuestUIController`, `AchievementUIController`, `CodexUIController`, `ShopUIController`, `LeaderboardUIController` | 44 px action buttons and taller cards where needed, Daily Streak as 4 + 3 pills on narrow screens, Codex grid fills the row (2 columns on a phone) with bigger icon area on touch, Shop grid divides by the scale factor, score column widened. |
| `GachaOpenClient`, `ShopUIController` prompts | Explicit `E` / `ButtonX` key codes. |
| `BuddyClient` | "Buddy names" toggle also on R3. |
| all client files | `MinTextSize` / `MinSize` below 12 raised to 12 (HUD currency 14). |

## 3. New menu structure

Before: 12 buttons in one scrolling row. Now: **4 primary buttons + More**.

```
Always visible:   [Build B] [Shop Z] [Quests Q (badge)] [Travel T] [More H (badge)]
More drawer:      Brood Pool U | Mystery Egg M | Abducted N | Leaderboard L
                  Codex C | Achievements K (badge) | Event J | Settings Y
```

| Device | Where the bar sits | Where the drawer opens |
|--------|--------------------|------------------------|
| Phone / tablet portrait | Under the HUD, full width, 5 equal tiles | Below the bar, 3 columns |
| Phone / tablet landscape | Top right (320 px) | Below the bar, right aligned, 4 columns |
| PC / console | Bottom center | Above the bar, 4 columns |

The bottom corners stay free on touch (thumbstick / jump). Tapping outside
the drawer, pressing `H`, pressing "More" again, or `B` on a gamepad closes
it. The "More" button shows the badge of the Achievements entry.

Keyboard: the key chip appears on each button while the last input was
keyboard / mouse; pressing the same key again closes the panel it opened,
a different key replaces it. Gamepad: **Y** (or View / Select) moves focus
into the bar, D-pad / stick choose, **A** confirms, **B** returns control to
the character (or closes the drawer). Free on purpose: `E` (interact), `I` /
`O` (Roblox camera zoom), `G` (drop), `F` (Depth Charge), `V` (buddy names),
`R` / `X` / `1`-`4` / `Enter` (build mode).

## 4. Per-device checklist

Legend: **V** = verified in code, **C** = changed, **S** = needs a Studio /
device test (see section 5).

### Phone portrait (360x640, 390x844)

- [x] **C/V** Scale about 0.9 (virtual width 400); text min 12-14 px, about 11 px on screen.
- [x] **C/V** HUD, menu, raid bar, event banner and ability panel stack from the top (about 0-290 px) and never touch the bottom 190 px.
- [x] **C/V** Panels are fullscreen with a 12 px margin, scroll when too tall, 44 px close button, content scrolls in a `ScrollingFrame`.
- [x] **C/V** Tabs scroll horizontally; Daily Streak 4 + 3; Codex 2 columns; Shop 1 column.
- [x] **C/V** Build bar full width above the thumbstick / jump zone, 5 action buttons in one row.
- [x] **C/V** Toasts / held-item hint / income popups above the thumbstick / jump zone.
- [x] **C** Sprint, Drop and Buddy-names are `ContextActionService` touch buttons; Depth Charge is an on-screen button.
- [ ] **S** Notch / home indicator margins (`CoreUISafeInsets`), top bar overlap, Roblox chat window over the HUD.
- [ ] **S** Position of the CAS touch buttons (sprint at 0.75 / 0.35, buddy at 0.75 / 0.55) against the top-right areas.

### Phone landscape (640x360, 844x390)

- [x] **C/V** HUD top left, raid + event bars below it, menu top right, ability panel below the menu.
- [x] **C/V** Build bar sits between the thumbstick and jump zones (min 320 px wide, 168 px tall).
- [x] **C/V** Drawer opens downward with 4 columns and is limited to the visible height.
- [ ] **S** Landscape on a 640x360 screen is the tightest case: check the drawer, build bar and level-up banner heights.

### Tablet (768x1024 portrait, 1024x768 landscape)

- [x] **C/V** Same layouts as phone (touch primary), scale 0.95-1.3, centered panels with margin.
- [x] **C/V** Panels are clamped to the visible area (the Shop's 1040 px window shrinks in portrait).
- [ ] **S** Drawer / build bar proportions on 4:3.

### PC (mouse + keyboard, 1280x720 up to 3440x1440)

- [x] **C/V** HUD top center, ability top right, menu bottom center, toasts bottom right.
- [x] **C/V** Panels never wider than 1100 px; the HUD is centered, so nothing stretches on ultrawide.
- [x] **C/V** Shortcuts with key chips; shortcut toggles panels; Roblox default keys left alone (`E`, `I`, `O`).
- [x] **C/V** Mouse aiming for build mode only in keyboard / mouse mode.
- [ ] **S** HUD against the default chat window and the player list.

### Console / gamepad (TV, 10-foot)

- [x] **C/V** Scale 1.15-1.7 (`IsTenFootInterface`), 52 px minimum target size, key hints as A / B / X / Y (PlayStation symbols on PS4 / PS5).
- [x] **C/V** Panels: focus on open, focus kept inside, B closes, selection restored, `B` chip.
- [x] **C/V** Menu: Y / View, B back; no focus is taken at start any more, and `AutoSelectGuiEnabled` is off, so the stick always walks.
- [x] **C/V** Build mode without UI focus: L1 / R1 field, D-pad card, X build, Y rotate, B done; upgrade panel via `ProximityPrompt`.
- [x] **C/V** Brood Pool, Mystery Egg, Shop stand, upgrade: `ProximityPrompt`s (`E` / X); drop = B; sprint = L3; Depth Charge = RT; buddy names = R3.
- [x] **C/V** Tabs: LB / RB.
- [ ] **S** Focus trap (`SelectedObject` guard) and selection restore on real hardware.
- [ ] **S** Scrolling long lists that contain no buttons (odds, raid result text): they scroll with the selected buttons only, there is no right-stick scrolling. Check whether this is acceptable.
- [ ] **S** Safe area on a real TV (overscan).

### ProximityPrompts

- Server prompts (Pick Up 0.3 s, Deposit 0.5 s, plot gate 0.3 s, zone portals 0.5 s) all have `RequiresLineOfSight = false`; hold times are fine on touch. Thaw (3 s by design) is a gameplay delay, not an input problem.
- Client prompts (Mystery Egg 0.3 s, Shop stand 0 s, Brood Pool 0 s, upgrade 0 s) set `KeyboardKeyCode = E` and `GamepadKeyCode = ButtonX` explicitly; Brood Pool / upgrade prompts are enabled only in gamepad mode so they do not clutter mouse / touch play.

## 5. Studio test plan (Device Emulator)

Open the game in Studio, **Test > Device** (the emulator toolbar over the
viewport). For every device below start a play session (F5), because
`Device` / `InputMode` read the real `UserInputService` state. If a phone
emulation reports class `PC`, run
`print(require(game.ReplicatedStorage.UIKit).Device.GetState().Class)` in the
client command bar: classification needs `TouchEnabled` and no keyboard.

| Device (emulator) | Orientation | What to click / check |
|-------------------|-------------|-----------------------|
| iPhone SE (375x667) or Generic phone 360x640 | Portrait | 1. HUD / menu / raid / event stack at the top, nothing at the bottom corners. 2. Tap **More**: drawer shows 3 columns, tap outside closes it. 3. Open Shop: fullscreen, tabs scroll sideways, 5 tabs reachable, grid 1 column. 4. Open Quests: streak shows 4 + 3 pills, claim buttons not overlapping. 5. Codex: 2 columns, star / buddy buttons not overlapping. 6. **Build**: bar above the jump / thumbstick zone, tap a field, press Build. 7. Pick up a spore: "Holding" hint and Drop button; toast stays clear of the thumbstick / jump. 8. Rotate the emulator: layout switches live. |
| iPhone 14 (844x390) | Landscape | 1. HUD top left, menu top right, bottom corners free. 2. **More**: 4 columns, fits the height. 3. Build bar between the zones; all 5 buttons readable. 4. Level-up banner (use the server command or `HUDRemotes.LevelUp` in Studio): width fits, not under the menu. 5. Onboarding (reset `OnboardingCompleted`): spotlight sits exactly on the target; Brood Pool step points at **More**. 6. Check the CAS buttons (Sprint, Buddy names) against the ability panel. |
| iPad (768x1024) | Portrait + landscape | Panels centered with margin (Shop smaller than 1040), drawer proportions, build bar, 44 px targets. |
| Desktop 1280x720 and 1920x1080 | Windowed | Shortcut chips visible; press `Q`, then `Q` again (closes), then `Q` and `T` (replaces). Open the Shop and drag the window narrower: panel clamps, no overflow. Build mode: mouse aims the preview, `R`, `Enter`, `X`, `Esc`. Check the HUD against the default chat. |
| Ultrawide (resize the window to about 3440x1440) | Windowed | HUD centered, panels at most 1100 px wide, menu bottom center, nothing stretched. |
| Xbox / console emulator (Console, with a gamepad or the Studio emulator gamepad) | Landscape | 1. At start the stick walks the character (no UI focus). 2. Press **Y**: focus on **Build**, D-pad right to **More**, **A** opens the drawer, focus on the first cell, **B** closes it, **B** again returns control. 3. Open Shop through the drawer or the hub stand (`X` on the prompt): focus lands on the first button, LB / RB change tabs, **B** closes, focus returns. 4. Open Mystery Egg via the prompt: the confirm dialog focuses **Open**, **B** cancels. 5. Build mode via Y > Build: L1 / R1 move the preview, D-pad changes the building, **X** builds, **Y** rotates, **B** leaves. 6. With a panel open try to navigate out of it: focus must stay inside. 7. Check text sizes from a TV distance (scale about 1.5 at 1080p). 8. Hint chips show A / B / X / Y; switch to keyboard (`LastInputType`) and check they change to key names. |

Also check once, on any device: leave a Shop confirmation open and press the
menu key (`Z`): the dialog is cancelled and the panel toggles without
leaving a dim layer behind.

## 6. Open points that need a human or a device

1. `ScreenInsets = CoreUISafeInsets` behaviour on notched phones and the real
   top bar height (all top-docked elements start at 8-16 px below it).
2. Default Roblox **chat window** (top left): desktop HUD is centered, but
   landscape touch keeps the HUD at the top left; if the chat window covers it,
   move `Hud` / `Raid` / `Event` in `Layout.GetHudLayout()` (one place).
3. `ContextActionService` touch-button positions (`SetPosition(0.75, ...)`) are
   relative to Roblox's own button frame; verify they do not collide with the
   top-right ability panel on a small landscape phone.
4. Focus trap and selection restore (`GuiService.SelectedObject` guard in
   `Panel`) on real gamepads; right-stick scrolling of button-free lists is not
   implemented.
5. Touch laptops (touch + keyboard) classify as PC: they get the PC layout
   but 44 px minimum targets; the preview follows the mouse until the first
   touch input switches `InputMode`.
6. PlayStation glyph mapping uses `UserInputService:GetPlatform()`; Xbox names
   are used everywhere else.
7. Audio is still silent (existing review item), so no feedback beyond visuals
   on any device.
