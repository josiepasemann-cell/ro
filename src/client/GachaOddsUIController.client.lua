--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: GachaOddsUIController (LocalScript)
	Zuständigkeit:
		Baut das Mystery-Egg-Odds-Panel vollständig zur Laufzeit über das
		UIKit (UIKit.Panel + UIKit.RarityBadge), befüllt es mit den ECHTEN,
		serverseitig autoritativen Odds-Werten aus GachaService.
		GetOddsTable() - abgefragt über den RemoteFunction-Kanal
		"GetGachaOdds" aus GachaRemotes.

		Wichtig: Es werden bewusst KEINE Prozentwerte auf Client-Seite
		hartkodiert. Alle Anzeigewerte kommen ausschließlich aus der
		Server-Antwort, damit UI und tatsächliche Drop-Tabelle niemals
		auseinanderlaufen können (Compliance-Anforderung aus
		expansion-concepts.md 1.7).

		GEÄNDERT (UIKit-Umstellung): Hing vorher an einer per Buildscript
		erzeugten, manuell in Studio gebauten ScreenGui
		(assets/models/ui/GachaOddsPanel.lua -> game.StarterGui.GachaOddsUI).
		Das ist jetzt entfernt - das Panel entsteht komplett per Code über
		UIKit.Panel, ist dadurch responsiv (Phone Vollbild, Tablet/PC/
		Konsole zentriert) und hängt an keinem manuell gebauten
		Studio-Objekt mehr. assets/models/ui/GachaOddsPanel.lua wird von
		diesem Skript nicht mehr referenziert (kann als Altlast im
		Buildscript-Ordner verbleiben, baut aber ohnehin nur noch ein
		totes StarterGui-Objekt, das kein Skript mehr ausliest).

		Öffnen des Panels:
			- Taste "P" (Debug/MVP-Shortcut, wie vorher),
			- MainMenuController-Button "Mystery Egg" (über die
			  Bridge-BindableEvent "OpenMysteryEgg", siehe
			  MainMenuController.client.lua Kopfkommentar).

	Rojo-Einhängepunkt:
		src/client/GachaOddsUIController.client.lua
			->  StarterPlayerScripts.GachaOddsUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GachaRemotes = require(ReplicatedStorage:WaitForChild("GachaRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = require(ReplicatedStorage:WaitForChild("UIKit"):WaitForChild("Theme"))
local Panel = UIKit.Panel
local RarityBadge = UIKit.RarityBadge

local localPlayer = Players.LocalPlayer

-- // Bridge (siehe MainMenuController.client.lua Kopfkommentar) ----------------
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

local openMysteryEggEvent = getOrCreateBridgeEvent("OpenMysteryEgg")

--- Formatiert einen Prozentwert konsistent zu den bisherigen
--- Platzhalter-Strings ("45.0%").
local function formatPercent(percent: number): string
	return string.format("%.1f%%", percent)
end

-- // Panel per UIKit bauen (einmalig, danach wiederverwendet) ------------------

local panel = Panel.new({
	Title = "Mystery Egg - Drop Odds",
	Closable = true,
	CenteredSize = UDim2.fromOffset(460, 480),
})

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Size = UDim2.new(1, 0, 0, 22)
subtitle.Font = Theme.Font.Body
subtitle.TextColor3 = Theme.Text.Secondary
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextScaled = true
subtitle.Text = "Revealed probabilities per opening"
subtitle.Parent = panel.Content
local subtitleConstraint = Instance.new("UITextSizeConstraint")
subtitleConstraint.MinTextSize = 12
subtitleConstraint.MaxTextSize = 16
subtitleConstraint.Parent = subtitle

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "RarityScroll"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(0, 30)
scroll.Size = UDim2.new(1, 0, 1, -70)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Theme.Neon.Cyan
scroll.Parent = panel.Content

local scrollList = Instance.new("UIListLayout")
scrollList.SortOrder = Enum.SortOrder.LayoutOrder
scrollList.Padding = UDim.new(0, 8)
scrollList.Parent = scroll

local footerNote = Instance.new("TextLabel")
footerNote.Name = "FooterNote"
footerNote.BackgroundTransparency = 1
footerNote.Position = UDim2.new(0, 0, 1, -36)
footerNote.Size = UDim2.new(1, 0, 0, 30)
footerNote.Font = Theme.Font.Body
footerNote.TextColor3 = Theme.Text.Muted
footerNote.TextWrapped = true
footerNote.TextScaled = true
footerNote.Text = "Odds apply per individual egg opening. No purchase necessary."
footerNote.Parent = panel.Content
local footerConstraint = Instance.new("UITextSizeConstraint")
footerConstraint.MinTextSize = 10
footerConstraint.MaxTextSize = 13
footerConstraint.Parent = footerNote

local rowHandles: { any } = {}

local function clearRows()
	for _, handle in rowHandles do
		handle:Destroy()
	end
	table.clear(rowHandles)
end

--- Fragt die autoritative Odds-Tabelle vom Server ab und baut die Zeilen im
--- UIKit-Panel neu auf.
local function refreshOddsFromServer()
	local ok, oddsRows = pcall(function()
		return GachaRemotes.GetGachaOdds:InvokeServer()
	end)

	if not ok or type(oddsRows) ~= "table" then
		warn("[GachaOddsUIController] Could not load odds table from server:", oddsRows)
		return
	end

	clearRows()

	for order, row in ipairs(oddsRows) do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "RarityRow_" .. tostring(row.Tier)
		rowFrame.BackgroundColor3 = Theme.Background.PanelLight
		rowFrame.Size = UDim2.new(1, 0, 0, 48)
		rowFrame.LayoutOrder = order
		rowFrame.Parent = scroll
		Theme.ApplyCorner(rowFrame, UDim.new(0, 10))

		local rarityKey = (row.Tier :: any) :: Theme.Rarity
		local badgeOk = table.find(Theme.RarityOrder, rarityKey) ~= nil

		local badge = RarityBadge.new({
			Parent = rowFrame,
			Rarity = if badgeOk then rarityKey else "Common",
			Size = UDim2.fromOffset(120, 30),
			Position = UDim2.new(0, 10, 0.5, -15),
		})

		local percentLabel = Instance.new("TextLabel")
		percentLabel.Name = "PercentLabel"
		percentLabel.BackgroundTransparency = 1
		percentLabel.AnchorPoint = Vector2.new(1, 0.5)
		percentLabel.Position = UDim2.new(1, -10, 0.5, 0)
		percentLabel.Size = UDim2.new(0, 100, 0, 30)
		percentLabel.Font = Theme.Font.BodyBold
		percentLabel.TextColor3 = row.Color or (if badgeOk then Theme.Rarity[rarityKey] else Theme.Text.Primary)
		percentLabel.TextScaled = true
		percentLabel.Text = formatPercent(row.Percent)
		percentLabel.Parent = rowFrame
		local percentConstraint = Instance.new("UITextSizeConstraint")
		percentConstraint.MinTextSize = 14
		percentConstraint.MaxTextSize = 22
		percentConstraint.Parent = percentLabel

		table.insert(rowHandles, {
			Destroy = function(_self)
				badge:Destroy()
				rowFrame:Destroy()
			end,
		})
	end
end

refreshOddsFromServer()

-- // Panel-Ein-/Ausblenden ---------------------------------------------------

local function setPanelVisible(visible: boolean)
	if visible then
		refreshOddsFromServer()
		panel:Open()
	else
		panel:Close()
	end
end

-- Einfacher Toggle für Tests/MVP: Taste "P" öffnet/schließt das Odds-Panel,
-- genau wie der "Mystery Egg"-Button in der Menüleiste.
local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		setPanelVisible(not panel.ScreenGui.Enabled)
	end
end)

local bridgeConnection = openMysteryEggEvent.Event:Connect(function()
	setPanelVisible(true)
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	inputConnection:Disconnect()
	bridgeConnection:Disconnect()
	clearRows()
	panel:Destroy()
end)
