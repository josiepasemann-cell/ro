--[[
	Abyssara – Deep Tide Tycoon
	Skript: GachaOddsUIController (LocalScript)
	Zuständigkeit:
		Befüllt das bereits bestehende, rein visuelle UI-Layout
		`GachaOddsUI` (assets/models/ui/GachaOddsPanel.lua, unter
		game.StarterGui -> beim Spieler-Join automatisch nach PlayerGui
		geklont) mit den ECHTEN, serverseitig autoritativen Odds-Werten aus
		GachaService.GetOddsTable() - abgefragt über den RemoteFunction-
		Kanal "GetGachaOdds" aus GachaRemotes.

		Wichtig: Es werden bewusst KEINE Prozentwerte auf Client-Seite
		hartkodiert. Alle Anzeigewerte kommen ausschließlich aus der
		Server-Antwort, damit UI und tatsächliche Drop-Tabelle niemals
		auseinanderlaufen können (Compliance-Anforderung aus
		expansion-concepts.md 1.7).

		Verdrahtet außerdem den bislang funktionslosen "CloseButton" und
		stellt einen einfachen Toggle bereit (Taste "P"), um das Panel vor
		einem Kauf einzublenden - Roblox verlangt, dass die Odds VOR dem
		Öffnen einsehbar sind.

	Rojo-Einhängepunkt:
		src/client/GachaOddsUIController.client.lua
			->  StarterPlayerScripts.GachaOddsUIController
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen)

	Voraussetzung:
		assets/models/ui/GachaOddsPanel.lua muss vorher einmal ausgeführt
		worden sein (baut game.StarterGui.GachaOddsUI auf, siehe
		assets/models/README.md). Dieses Skript verändert an der Struktur
		des Panels nichts, nur Text-/Attribut-Werte der bestehenden
		Instanzen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GachaRemotes = require(ReplicatedStorage:WaitForChild("GachaRemotes"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- GachaOddsPanel.lua klont "GachaOddsUI" nach game.StarterGui, wodurch es
-- beim Join automatisch mit in PlayerGui landet.
local oddsGui = playerGui:WaitForChild("GachaOddsUI", 10)
if not oddsGui then
	warn("[GachaOddsUIController] GachaOddsUI nicht gefunden - wurde assets/models/ui/GachaOddsPanel.lua ausgeführt?")
	return
end

local oddsPanel = oddsGui:WaitForChild("Dimmer"):WaitForChild("OddsPanel")
local rarityList = oddsPanel:WaitForChild("RarityList")
local closeButton = oddsPanel:WaitForChild("CloseButton") :: TextButton

--- Formatiert einen Prozentwert konsistent zu den bisherigen
--- Platzhalter-Strings ("45.0%") aus GachaOddsPanel.lua.
local function formatPercent(percent: number): string
	return string.format("%.1f%%", percent)
end

--- Fragt die autoritative Odds-Tabelle vom Server ab und schreibt sie in
--- die bestehenden RarityRow_<Tier>-Instanzen.
local function refreshOddsFromServer()
	local ok, oddsRows = pcall(function()
		return GachaRemotes.GetGachaOdds:InvokeServer()
	end)

	if not ok or type(oddsRows) ~= "table" then
		warn("[GachaOddsUIController] Konnte Odds-Tabelle nicht vom Server laden:", oddsRows)
		return
	end

	for _, row in ipairs(oddsRows) do
		local rowFrame = rarityList:FindFirstChild("RarityRow_" .. row.Tier)
		if rowFrame then
			local percentLabel = rowFrame:FindFirstChild("PercentLabel") :: TextLabel?
			local nameLabel = rowFrame:FindFirstChild("NameLabel") :: TextLabel?
			local swatch = rowFrame:FindFirstChild("ColorSwatch") :: Frame?

			if percentLabel then
				percentLabel.Text = formatPercent(row.Percent)
				-- Die Werte sind jetzt echt, nicht mehr nur Layout-Platzhalter.
				percentLabel:SetAttribute("PlaceholderOnly", false)
				percentLabel.TextColor3 = row.Color
			end
			if nameLabel then
				nameLabel.Text = row.Label
			end
			if swatch then
				swatch.BackgroundColor3 = row.Color
			end
		else
			warn("[GachaOddsUIController] Keine RarityRow für Tier '" .. tostring(row.Tier) .. "' im UI gefunden.")
		end
	end
end

refreshOddsFromServer()

-- // Panel-Ein-/Ausblenden ---------------------------------------------------

local function setPanelVisible(visible: boolean)
	oddsGui.Enabled = visible
	if visible then
		-- Odds bei jedem Öffnen frisch vom Server abfragen (z. B. falls sich
		-- die Drop-Tabelle durch ein Live-Update geändert hat).
		refreshOddsFromServer()
	end
end

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

-- Einfacher Toggle für Tests/MVP, solange es noch keinen dedizierten
-- "Kaufen"-Button mit Odds-Vorschau gibt: Taste "P" öffnet/schließt das
-- Odds-Panel. Ein künftiges Shop-/Kauf-UI kann stattdessen direkt
-- setPanelVisible(true) vor dem eigentlichen Kaufabschluss aufrufen.
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		setPanelVisible(not oddsGui.Enabled)
	end
end)
