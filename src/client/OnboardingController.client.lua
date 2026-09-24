--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: OnboardingController (LocalScript)
	Zuständigkeit:
		Kurzes, überspringbares Einstiegs-Tutorial für neue Spieler:innen
		(Zielgruppe 8-14, kurze/kindgerechte Sätze). 6 Schritte:
			1. Willkommen
			2. Zu deinem eigenen Riff-Plot reisen (zeigt auf "Reisen")
			3. Erstes Gebäude bauen (zeigt auf "Bauen")
			4. Glow Spore aufheben und abgeben (Welt-Hinweis, kein festes
			   UI-Ziel - Spores spawnen dynamisch auf dem eigenen Plot)
			5. Brutbecken & Mystery Egg (zeigt auf "Brutbecken")
			6. Shop kurz zeigen (zeigt auf "Shop")

		HERVORHEBUNG/PFEIL: Für Schritte mit einem UI-Ziel (Menüleisten-
		Button) wird der Bildschirm rund um das Ziel NICHT einfach nur
		gedimmt, sondern per 4-Rechtecke-Maske (oben/unten/links/rechts vom
		Ziel) ein echtes "Ausgeschnitten"-Spotlight erzeugt (das Ziel selbst
		bleibt hell), zusätzlich ein pulsierender Neon-Ring + ein Pfeil, der
		vom Erklär-Kärtchen zum Ziel zeigt (Rotation wird aus dem
		Richtungsvektor berechnet). Für den Welt-Schritt (Glow Spore) gibt es
		keinen exakt lokalisierbaren Zielpunkt (Spores spawnen serverseitig
		zur Laufzeit ohne eigenes Remote zum Abfragen der Position) - dort
		erscheint stattdessen nur das Erklär-Kärtchen mit einem "schau dich
		um"-Hinweis, das ist bewusst dokumentiert, kein Bug.

		NEU-SPIELER-ERKENNUNG (pragmatisch, siehe Auftrag): Es gibt aktuell
		KEIN persistentes `PlayerDataService`-Feld wie "OnboardingSeen"
		(außerhalb der erlaubten Dateien für diesen Auftrag nicht anlegbar -
		siehe Zusammenfassung/Server-Bug-Hinweis an den nächsten Agenten).
		Heuristik hier: `HUDRemotes.GetHUDState` liefert `Level`/`XP` - ein
		Spieler mit `Level <= 1` UND `XP <= 0` gilt als neu. Das kann in
		seltenen Fällen falsch-positiv sein (z. B. ein Spieler, der exakt bei
		0 XP auf Level 1 relogged, ohne wirklich neu zu sein) - das
		Tutorial ist aber jederzeit sofort überspringbar, der Schaden eines
		Fehlalarms ist also gering. Läuft nur EINMAL pro Server-Session
		(LocalScript-Ausführung), kein wiederholtes Zeigen innerhalb
		derselben Sitzung.

		Wartet zunächst kurz auf `QuestUIController`s Bridge-Event
		"DailyRewardPopupClosed" (mit Timeout), damit sich das automatische
		Tages-Login-Popup und dieses Tutorial nicht überlappen.

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder Button ausschließlich über
		UIKit.Button.new(...).

	Rojo-Einhängepunkt:
		src/client/OnboardingController.client.lua ->
		StarterPlayer.StarterPlayerScripts.OnboardingController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Button = UIKit.Button
local Settings = UIKit.Settings
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // Bridge ------------------------------------------------------------------------

local function getOrCreateBridgeEvent(eventName: string): BindableEvent
	local bridge = ReplicatedStorage:FindFirstChild("AbyssaraUIBridge")
	if not bridge then
		bridge = Instance.new("Folder")
		bridge.Name = "AbyssaraUIBridge"
		bridge.Parent = ReplicatedStorage
	end
	local event = bridge:FindFirstChild(eventName)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = eventName
		event.Parent = bridge
	end
	return event :: BindableEvent
end

local dailyRewardPopupClosedEvent = getOrCreateBridgeEvent("DailyRewardPopupClosed")

-- // Neu-Spieler-Erkennung (siehe Kopfkommentar) -------------------------------------

local function isLikelyNewPlayer(): boolean
	local ok, hudState = pcall(function()
		return HUDRemotes.GetHUDState:InvokeServer()
	end)
	if not ok or type(hudState) ~= "table" then
		return false
	end
	local level = (hudState.Level :: number?) or 1
	local xp = (hudState.XP :: number?) or 0
	return level <= 1 and xp <= 0
end

-- // Ziel-Finder: sucht Menüleisten-Buttons anhand ihres sichtbaren Texts ------------
-- (rein lesend über bereits vorhandene, öffentliche GuiObjects unter
-- PlayerGui - keine Änderung an MainMenuController nötig, funktioniert
-- unabhängig von der Button-Reihenfolge/Position in der Leiste.)

local function findButtonByLabelText(keyword: string): GuiObject?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == "UIKitButton" and descendant:IsA("TextButton") then
			local label = descendant:FindFirstChild("Label")
			if label and label:IsA("TextLabel") and string.find(label.Text, keyword, 1, true) then
				return descendant
			end
		end
	end
	return nil
end

-- // Overlay-Grundgerüst --------------------------------------------------------

local overlayGui: ScreenGui? = nil
local maskTop: Frame? = nil
local maskBottom: Frame? = nil
local maskLeft: Frame? = nil
local maskRight: Frame? = nil
local ring: Frame? = nil
local ringStroke: UIStroke? = nil
local arrow: TextLabel? = nil
local card: Frame? = nil
local cardTitle: TextLabel? = nil
local cardBody: TextLabel? = nil
local dotsHost: Frame? = nil
local nextButton: any = nil
local skipButton: any = nil

local pulseThread: thread? = nil
local arrowBounceThread: thread? = nil
local trackConnection: RBXScriptConnection? = nil

local function ensureOverlay()
	if overlayGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OnboardingOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 70
	gui.Parent = playerGui
	overlayGui = gui

	local function makeMask(name: string): Frame
		local mask = Instance.new("Frame")
		mask.Name = name
		mask.BackgroundColor3 = Color3.new(0, 0, 0)
		mask.BackgroundTransparency = 0.5
		mask.BorderSizePixel = 0
		mask.ZIndex = 1
		mask.Parent = gui
		return mask
	end
	maskTop = makeMask("MaskTop")
	maskBottom = makeMask("MaskBottom")
	maskLeft = makeMask("MaskLeft")
	maskRight = makeMask("MaskRight")

	local ringFrame = Instance.new("Frame")
	ringFrame.Name = "Ring"
	ringFrame.BackgroundTransparency = 1
	ringFrame.ZIndex = 3
	ringFrame.Visible = false
	Theme.ApplyCorner(ringFrame, UDim.new(0, 16))
	local stroke = Theme.ApplyStroke(ringFrame, Theme.Neon.Yellow, 3)
	stroke.Transparency = 0
	ringFrame.Parent = gui
	ring = ringFrame
	ringStroke = stroke

	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Name = "Arrow"
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Size = UDim2.fromOffset(40, 40)
	arrowLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowLabel.Font = Theme.Font.Header
	arrowLabel.Text = "➤"
	arrowLabel.TextColor3 = Theme.Neon.Yellow
	arrowLabel.TextScaled = true
	arrowLabel.ZIndex = 3
	arrowLabel.Visible = false
	arrowLabel.Parent = gui
	local arrowConstraint = Instance.new("UITextSizeConstraint")
	arrowConstraint.MinTextSize = 20
	arrowConstraint.MaxTextSize = 34
	arrowConstraint.Parent = arrowLabel
	Theme.ApplyStroke(arrowLabel, Theme.Text.Stroke, 1.5)
	arrow = arrowLabel

	-- // Erklär-Kärtchen ----------------------------------------------------------
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = "Card"
	cardFrame.BackgroundColor3 = Theme.Background.Panel
	cardFrame.BackgroundTransparency = 0.03
	cardFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	cardFrame.Size = UDim2.new(0, 420, 0, 0)
	cardFrame.AutomaticSize = Enum.AutomaticSize.Y
	cardFrame.ZIndex = 4
	Theme.ApplyCorner(cardFrame, UDim.new(0, 18))
	local cardStroke = Theme.ApplyStroke(cardFrame, Theme.Neon.Cyan, 2)
	cardStroke.Transparency = 0.15
	Theme.ApplyGradient(cardFrame, { Theme.Background.Panel, Theme.Background.Deepest }, 90)
	cardFrame.Parent = gui
	card = cardFrame

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	Device.BindUIScale(uiScale)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = cardFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Theme.Font.Header
	title.TextColor3 = Theme.Neon.Cyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.ZIndex = 4
	title.Parent = cardFrame
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 18
	titleConstraint.MaxTextSize = 26
	titleConstraint.Parent = title
	cardTitle = title

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 34)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Font = Theme.Font.Body
	body.TextColor3 = Theme.Text.Primary
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextWrapped = true
	body.TextScaled = true
	body.ZIndex = 4
	body.Parent = cardFrame
	local bodyConstraint = Instance.new("UITextSizeConstraint")
	bodyConstraint.MinTextSize = 13
	bodyConstraint.MaxTextSize = 18
	bodyConstraint.Parent = body
	cardBody = body

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.Position = UDim2.fromOffset(0, 90)
	dots.Size = UDim2.new(1, 0, 0, 14)
	dots.ZIndex = 4
	dots.Parent = cardFrame
	local dotsList = Instance.new("UIListLayout")
	dotsList.FillDirection = Enum.FillDirection.Horizontal
	dotsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	dotsList.Padding = UDim.new(0, 6)
	dotsList.Parent = dots
	dotsHost = dots

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.BackgroundTransparency = 1
	buttonRow.Position = UDim2.fromOffset(0, 114)
	buttonRow.Size = UDim2.new(1, 0, 0, 44)
	buttonRow.ZIndex = 4
	buttonRow.Parent = cardFrame

	skipButton = Button.new({
		Parent = buttonRow,
		Text = "Überspringen",
		Variant = "Ghost",
		Size = UDim2.new(0.42, -6, 1, 0),
		LayoutOrder = 1,
	})

	nextButton = Button.new({
		Parent = buttonRow,
		Text = "Weiter",
		Variant = "Primary",
		Important = true,
		Size = UDim2.new(0.58, -6, 1, 0),
		LayoutOrder = 2,
	})
	nextButton.Instance.AnchorPoint = Vector2.new(1, 0)
	nextButton.Instance.Position = UDim2.new(1, 0, 0, 0)
end

-- // Spotlight-Maske aktualisieren (4-Rechtecke-Cutout um ein Ziel) ------------------

local function setFullDim()
	if not maskTop or not maskBottom or not maskLeft or not maskRight then
		return
	end
	local top, bottom, left, right = maskTop, maskBottom, maskLeft, maskRight
	local viewport = Device.GetState().ViewportSize
	top.Position = UDim2.fromOffset(0, 0)
	top.Size = UDim2.fromOffset(viewport.X, viewport.Y)
	bottom.Size = UDim2.fromOffset(0, 0)
	left.Size = UDim2.fromOffset(0, 0)
	right.Size = UDim2.fromOffset(0, 0)
	if ring then
		ring.Visible = false
	end
	if arrow then
		arrow.Visible = false
	end
end

local function setSpotlight(target: GuiObject)
	if not maskTop or not maskBottom or not maskLeft or not maskRight or not ring or not arrow then
		return
	end
	local top, bottom, left, right, ringFrame, arrowLabel = maskTop, maskBottom, maskLeft, maskRight, ring, arrow

	local padding = 10
	local pos = target.AbsolutePosition - Vector2.new(padding, padding)
	local size = target.AbsoluteSize + Vector2.new(padding * 2, padding * 2)
	local viewport = Device.GetState().ViewportSize

	top.Position = UDim2.fromOffset(0, 0)
	top.Size = UDim2.fromOffset(viewport.X, math.max(pos.Y, 0))

	bottom.Position = UDim2.fromOffset(0, pos.Y + size.Y)
	bottom.Size = UDim2.fromOffset(viewport.X, math.max(viewport.Y - (pos.Y + size.Y), 0))

	left.Position = UDim2.fromOffset(0, pos.Y)
	left.Size = UDim2.fromOffset(math.max(pos.X, 0), size.Y)

	right.Position = UDim2.fromOffset(pos.X + size.X, pos.Y)
	right.Size = UDim2.fromOffset(math.max(viewport.X - (pos.X + size.X), 0), size.Y)

	ringFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
	ringFrame.Size = UDim2.fromOffset(size.X, size.Y)
	ringFrame.Visible = true

	-- Pfeil vom Kärtchen zum Ziel: Richtung aus Kärtchen-Mittelpunkt ->
	-- Ziel-Mittelpunkt, Position knapp außerhalb des Rings in dieselbe
	-- Richtung, Rotation aus dem Winkel berechnet ("➤" zeigt bei 0° nach
	-- rechts).
	if card then
		local cardFrame = card
		local cardCenter = cardFrame.AbsolutePosition + cardFrame.AbsoluteSize / 2
		local targetCenter = pos + size / 2
		local direction = targetCenter - cardCenter
		if direction.Magnitude > 1 then
			direction = direction.Unit
			local ringHalfDiagonal = (size.Magnitude / 2) + 26
			local arrowPos = targetCenter - direction * ringHalfDiagonal
			arrowLabel.Position = UDim2.fromOffset(arrowPos.X, arrowPos.Y)
			arrowLabel.Rotation = math.deg(math.atan2(direction.Y, direction.X))
			arrowLabel.Visible = true
		else
			arrowLabel.Visible = false
		end
	end
end

local function stopPulseInternal()
	if pulseThread then
		task.cancel(pulseThread)
		pulseThread = nil
	end
end

local function startPulse()
	stopPulseInternal()
	if Settings.ShouldSkipFX() or not ringStroke then
		return
	end
	pulseThread = task.spawn(function()
		while true do
			TweenService:Create(ringStroke :: UIStroke, TweenInfo.new(0.55), { Thickness = 5 }):Play()
			task.wait(0.55)
			TweenService:Create(ringStroke :: UIStroke, TweenInfo.new(0.55), { Thickness = 3 }):Play()
			task.wait(0.55)
		end
	end)
end

local function stopArrowBounce()
	if arrowBounceThread then
		task.cancel(arrowBounceThread)
		arrowBounceThread = nil
	end
end

local function startArrowBounce()
	stopArrowBounce()
	if Settings.ShouldSkipFX() or not arrow then
		return
	end
	local baseSize = 40
	arrowBounceThread = task.spawn(function()
		while true do
			TweenService:Create(arrow :: TextLabel, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromOffset(baseSize + 8, baseSize + 8),
			}):Play()
			task.wait(0.4)
			TweenService:Create(arrow :: TextLabel, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromOffset(baseSize, baseSize),
			}):Play()
			task.wait(0.4)
		end
	end)
end

local function stopTracking()
	if trackConnection then
		trackConnection:Disconnect()
		trackConnection = nil
	end
end

-- // Kärtchen-Position (vermeidet Überlappung mit HUD oben / Menüleiste unten) ------

local function positionCard(target: GuiObject?)
	if not card then
		return
	end
	local cardWidth = if Device.IsPhone() then 320 else 420
	card.Size = UDim2.new(0, cardWidth, 0, 0)
	if not target then
		card.Position = UDim2.fromScale(0.5, 0.5)
		return
	end
	local viewport = Device.GetState().ViewportSize
	local targetCenterY = target.AbsolutePosition.Y + target.AbsoluteSize.Y / 2
	if targetCenterY > viewport.Y * 0.5 then
		-- Ziel liegt unten (Menüleiste) -> Kärtchen weiter oben zeigen.
		local upperY = if Device.IsPhone() then 0.3 else 0.35
		card.Position = UDim2.fromScale(0.5, upperY)
	else
		card.Position = UDim2.fromScale(0.5, 0.72)
	end
end

-- // Schritte -----------------------------------------------------------------------

type Step = {
	Title: string,
	Body: string,
	FindTarget: (() -> GuiObject?)?,
}

local STEPS: { Step } = {
	{
		Title = "Willkommen bei Abyssara! 🌊",
		Body = "Tauche tief hinab, baue dein eigenes Riff und züchte leuchtende Kreaturen! Lass uns kurz zeigen, wie alles funktioniert.",
	},
	{
		Title = "Reise zu deinem Riff-Plot 🧭",
		Body = "Hier öffnest du das Reisen-Menü. Damit kommst du jederzeit sofort zu deinem eigenen Riff-Plot!",
		FindTarget = function()
			return findButtonByLabelText("Reisen")
		end,
	},
	{
		Title = "Baue dein erstes Gebäude 🛠️",
		Body = "Mit diesem Knopf startest du den Baumodus. Platziere dein erstes Gebäude auf deinem Plot, um Tide Coins zu verdienen!",
		FindTarget = function()
			return findButtonByLabelText("Bauen")
		end,
	},
	{
		Title = "Glow Spores einsammeln! ✨",
		Body = "Schau dich auf deinem Plot um: Dort leuchten Glow Spores! Sammle sie ein und bring sie zur Abgabestation für Tide Coins.",
	},
	{
		Title = "Brutbecken & Mystery Eggs 🥚",
		Body = "Hier siehst du dein Brutbecken und kannst süße neue Kreaturen aus Mystery Eggs schlüpfen lassen!",
		FindTarget = function()
			return findButtonByLabelText("Brutbecken")
		end,
	},
	{
		Title = "Der Shop 🛒",
		Body = "Im Shop findest du coole Kosmetik und praktische Boosts. Viel Spaß tief unten im Ozean!",
		FindTarget = function()
			return findButtonByLabelText("Shop")
		end,
	},
}

local currentStepIndex = 1
-- Mischung aus nativen RBXScriptConnection (Device.Changed) und
-- UIKit.Signal-Connections (Button.Clicked) - beide erfüllen dasselbe
-- strukturelle Interface (:Disconnect()), daher bewusst `any` statt eines
-- einzelnen konkreten Typs.
local stepConnections: { any } = {}

local function teardown()
	stopPulseInternal()
	stopArrowBounce()
	stopTracking()
	for _, connection in stepConnections do
		connection:Disconnect()
	end
	table.clear(stepConnections)
	if overlayGui then
		overlayGui:Destroy()
		overlayGui = nil
	end
end

local function refreshDots()
	if not dotsHost then
		return
	end
	for _, child in ipairs(dotsHost:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index = 1, #STEPS do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = if index == currentStepIndex then Theme.Neon.Cyan else Theme.Background.Divider
		Theme.ApplyCorner(dot, UDim.new(1, 0))
		dot.LayoutOrder = index
		dot.Parent = dotsHost
	end
end

local function showStep(index: number)
	local step = STEPS[index]
	if not step or not cardTitle or not cardBody or not nextButton then
		return
	end
	currentStepIndex = index
	cardTitle.Text = step.Title
	cardBody.Text = step.Body
	refreshDots()
	nextButton:SetText(if index == #STEPS then "Los geht's!" else "Weiter")

	stopTracking()
	local target = step.FindTarget and step.FindTarget() or nil
	positionCard(target)

	if target then
		setSpotlight(target)
		startPulse()
		startArrowBounce()
		-- Ziel kann sich (Gerätewechsel/Rotation/Scroll) bewegen - Spotlight
		-- pro Frame nachziehen, solange dieser Schritt sichtbar ist.
		trackConnection = game:GetService("RunService").RenderStepped:Connect(function()
			if target and target.Parent then
				setSpotlight(target)
			end
		end)
	else
		setFullDim()
		stopPulseInternal()
		stopArrowBounce()
	end
end

local function advanceStep()
	if currentStepIndex >= #STEPS then
		ScreenFX.BigMoment(Theme.Neon.ToxicGreen)
		teardown()
		return
	end
	showStep(currentStepIndex + 1)
end

local function skipOnboarding()
	teardown()
end

local function runOnboarding()
	ensureOverlay()
	if not nextButton or not skipButton then
		return
	end
	table.insert(stepConnections, nextButton.Clicked:Connect(advanceStep))
	table.insert(stepConnections, skipButton.Clicked:Connect(skipOnboarding))
	table.insert(
		stepConnections,
		Device.Changed:Connect(function()
			showStep(currentStepIndex)
		end)
	)
	showStep(1)
end

-- // Start -----------------------------------------------------------------------

task.spawn(function()
	if not isLikelyNewPlayer() then
		return
	end

	-- Kurz auf das automatische Tages-Login-Popup warten (siehe
	-- Kopfkommentar), damit sich beide Panels nicht überlappen. Timeout,
	-- falls QuestUIController aus irgendeinem Grund nie feuert.
	local dailyResolved = false
	local resolveConnection: RBXScriptConnection
	resolveConnection = dailyRewardPopupClosedEvent.Event:Connect(function()
		dailyResolved = true
	end)

	local waited = 0
	while not dailyResolved and waited < 8 do
		task.wait(0.25)
		waited += 0.25
	end
	resolveConnection:Disconnect()

	task.wait(0.5)
	runOnboarding()
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	teardown()
end)
