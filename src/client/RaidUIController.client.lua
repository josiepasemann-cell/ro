--[[
	Abyssara – Deep Tide Tycoon
	Skript: RaidUIController (LocalScript)
	Zuständigkeit:
		Client-HUD für das Trench-Raid-System (GDD Abschnitt 3 + Abschnitt 9,
		Punkt 5): zeigt permanent
			- Countdown bis zum nächsten fälligen Raid (wenn kein Raid läuft),
			- Wellen-Anzeige (aktuelle/Gesamt-Welle, Boss-Kennzeichnung)
			  während ein Raid läuft,
			- ein kurzes Ergebnis-Popup (Sieg/Niederlage inkl. Belohnung bzw.
			  entführter Kreatur) nach Raid-Ende (auch für offline ausgewertete
			  Raids, direkt nach dem Login),
			- eine einfache Treffer-Visualisierung (kurzer Leucht-Beam
			  Turm->Gegner) bei jedem servergemeldeten Treffer,
		sowie ein separates, über einen Button erreichbares Panel zum
		Freikaufen entführter Kreaturen gegen Tide-Coins-Lösegeld.

		WICHTIG: Dies ist AUSSCHLIESSLICH Anzeige/Komfort. Die tatsächliche
		Autorität über Raid-Ablauf, Schaden, Sieg/Niederlage, Entführung und
		Lösegeld liegt einzig beim Server (RaidService) - dieses Skript zeigt
		nur, was der Server über RaidRemotes meldet, und schickt bei der
		Rettungs-Aktion lediglich eine Absichtserklärung (instanceId), die der
		Server komplett neu validiert.

	Rojo-Einhängepunkt:
		src/client/RaidUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.RaidUIController
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))

local player = Players.LocalPlayer

-- // Rarity-Farbschema (rein kosmetisch, unabhängig von BreedingConfig - siehe
-- Kopfkommentar: dieses Skript trifft keine Gameplay-Entscheidungen) -----------
local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(215, 250, 245),
	Uncommon = Color3.fromRGB(120, 235, 170),
	Rare = Color3.fromRGB(110, 180, 255),
	Epic = Color3.fromRGB(190, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 90),
	Mythic = Color3.fromRGB(255, 110, 180),
	Abyssal = Color3.fromRGB(255, 70, 70),
}
local function rarityColor(rarity: string): Color3
	return RARITY_COLORS[rarity] or Color3.fromRGB(210, 235, 240)
end

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return ("%02d:%02d"):format(minutes, seconds)
end

-- // Root-ScreenGui ---------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RaidHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- // Kompakte Status-Leiste (oben mittig: Countdown ODER Wellen-Anzeige) --------

local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.AnchorPoint = Vector2.new(0.5, 0)
statusBar.Position = UDim2.new(0.5, 0, 0, 16)
statusBar.Size = UDim2.fromOffset(360, 56)
statusBar.BackgroundColor3 = Color3.fromRGB(10, 22, 30)
statusBar.BackgroundTransparency = 0.15
statusBar.Parent = screenGui

local statusBarCorner = Instance.new("UICorner")
statusBarCorner.CornerRadius = UDim.new(0, 12)
statusBarCorner.Parent = statusBar

local statusBarStroke = Instance.new("UIStroke")
statusBarStroke.Color = Color3.fromRGB(70, 210, 235)
statusBarStroke.Thickness = 1.5
statusBarStroke.Parent = statusBar

local statusIcon = Instance.new("TextLabel")
statusIcon.Name = "Icon"
statusIcon.Size = UDim2.fromOffset(40, 40)
statusIcon.Position = UDim2.new(0, 8, 0.5, -20)
statusIcon.BackgroundTransparency = 1
statusIcon.Font = Enum.Font.GothamBold
statusIcon.TextSize = 26
statusIcon.Text = "🌊"
statusIcon.Parent = statusBar

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -56, 1, 0)
statusLabel.Position = UDim2.new(0, 52, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 16
statusLabel.TextColor3 = Color3.fromRGB(220, 240, 245)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextWrapped = true
statusLabel.Text = "Nächster Trench Raid: --:--"
statusLabel.Parent = statusBar

-- // Ergebnis-Popup (Sieg/Niederlage) -----------------------------------------

local resultPopup = Instance.new("Frame")
resultPopup.Name = "ResultPopup"
resultPopup.AnchorPoint = Vector2.new(0.5, 0.5)
resultPopup.Position = UDim2.fromScale(0.5, 0.42)
resultPopup.Size = UDim2.fromOffset(400, 190)
resultPopup.BackgroundColor3 = Color3.fromRGB(8, 18, 25)
resultPopup.BackgroundTransparency = 0.05
resultPopup.Visible = false
resultPopup.Parent = screenGui

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 16)
resultCorner.Parent = resultPopup

local resultStroke = Instance.new("UIStroke")
resultStroke.Thickness = 2
resultStroke.Parent = resultPopup

local resultTitle = Instance.new("TextLabel")
resultTitle.Name = "Title"
resultTitle.Size = UDim2.new(1, -20, 0, 40)
resultTitle.Position = UDim2.new(0, 10, 0, 12)
resultTitle.BackgroundTransparency = 1
resultTitle.Font = Enum.Font.GothamBold
resultTitle.TextSize = 24
resultTitle.Text = ""
resultTitle.Parent = resultPopup

local resultBody = Instance.new("TextLabel")
resultBody.Name = "Body"
resultBody.Size = UDim2.new(1, -24, 1, -110)
resultBody.Position = UDim2.new(0, 12, 0, 56)
resultBody.BackgroundTransparency = 1
resultBody.Font = Enum.Font.GothamMedium
resultBody.TextSize = 16
resultBody.TextWrapped = true
resultBody.TextYAlignment = Enum.TextYAlignment.Top
resultBody.TextColor3 = Color3.fromRGB(215, 235, 240)
resultBody.Text = ""
resultBody.Parent = resultPopup

local resultCloseButton = Instance.new("TextButton")
resultCloseButton.Name = "CloseButton"
resultCloseButton.Size = UDim2.new(1, -20, 0, 38)
resultCloseButton.Position = UDim2.new(0, 10, 1, -50)
resultCloseButton.BackgroundColor3 = Color3.fromRGB(70, 210, 235)
resultCloseButton.Font = Enum.Font.GothamBold
resultCloseButton.TextSize = 16
resultCloseButton.TextColor3 = Color3.fromRGB(8, 18, 25)
resultCloseButton.Text = "OK"
resultCloseButton.Parent = resultPopup

local resultCloseCorner = Instance.new("UICorner")
resultCloseCorner.CornerRadius = UDim.new(0, 10)
resultCloseCorner.Parent = resultCloseButton

local resultAutoHideThread: thread? = nil

local function hideResultPopup()
	resultPopup.Visible = false
end

resultCloseButton.MouseButton1Click:Connect(hideResultPopup)

local function showResultPopup(won: boolean, bodyText: string)
	if resultAutoHideThread then
		task.cancel(resultAutoHideThread)
		resultAutoHideThread = nil
	end

	resultTitle.Text = if won then "Raid erfolgreich abgewehrt!" else "Trench Raid verloren"
	local accent = if won then Color3.fromRGB(90, 235, 140) else Color3.fromRGB(235, 90, 90)
	resultTitle.TextColor3 = accent
	resultStroke.Color = accent
	resultBody.Text = bodyText
	resultPopup.Visible = true

	resultAutoHideThread = task.delay(9, function()
		resultAutoHideThread = nil
		hideResultPopup()
	end)
end

-- // Wellen-/Entführungs-Ergebnis-Text-Aufbau -----------------------------------

local function buildVictoryText(result: { [string]: any }): string
	local lines = {}
	if result.Offline then
		table.insert(lines, ("Während du weg warst: %d Raid(s) erfolgreich abgewehrt."):format(result.RaidsEvaluated or 1))
	else
		table.insert(lines, ("Alle %d Wellen überstanden!"):format(result.WavesCleared or 0))
	end
	if result.RewardTideCoins then
		table.insert(lines, ("+ %d Tide Coins"):format(result.RewardTideCoins))
	end
	if result.RewardAbyssalShards then
		table.insert(lines, ("+ %d Abyssal Shard(s)"):format(result.RewardAbyssalShards))
	end
	return table.concat(lines, "\n")
end

local function buildDefeatText(result: { [string]: any }): string
	local lines = {}
	if result.Offline then
		table.insert(lines, ("Während du weg warst: %d Raid(s) verloren."):format(result.RaidsEvaluated or 1))
		local abductedList = result.AbductedCreatures
		if type(abductedList) == "table" and #abductedList > 0 then
			for _, abducted in ipairs(abductedList) do
				table.insert(
					lines,
					("Entführt: %s (%s) - Lösegeld %d Tide Coins"):format(
						abducted.CreatureId,
						abducted.Rarity,
						abducted.RansomCost
					)
				)
			end
		end
	else
		table.insert(lines, ("Durchbrochen nach Welle %d."):format(result.WavesCleared or 0))
		local abducted = result.AbductedCreature
		if abducted then
			table.insert(
				lines,
				("Entführt: %s (%s) - Lösegeld %d Tide Coins"):format(
					abducted.CreatureId,
					abducted.Rarity,
					abducted.RansomCost
				)
			)
		else
			table.insert(lines, "Keine Kreatur im Inventar - keine Entführung.")
		end
	end
	table.insert(lines, "Öffne 'Entführte Kreaturen', um freizukaufen.")
	return table.concat(lines, "\n")
end

-- // Treffer-Visualisierung (einfacher, kurzlebiger Leucht-Beam) ----------------

local function spawnHitTracer(towerPosition: Vector3, enemyPosition: Vector3)
	local originPart = Instance.new("Part")
	originPart.Name = "RaidTracerOrigin"
	originPart.Anchored = true
	originPart.CanCollide = false
	originPart.CanQuery = false
	originPart.Transparency = 1
	originPart.Size = Vector3.new(0.2, 0.2, 0.2)
	originPart.CFrame = CFrame.new(towerPosition)
	originPart.Parent = Workspace

	local targetPart = Instance.new("Part")
	targetPart.Name = "RaidTracerTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	targetPart.CFrame = CFrame.new(enemyPosition)
	targetPart.Parent = Workspace

	local originAttachment = Instance.new("Attachment")
	originAttachment.Parent = originPart
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = targetPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = originAttachment
	beam.Attachment1 = targetAttachment
	beam.Width0 = 0.35
	beam.Width1 = 0.08
	beam.Color = ColorSequence.new(Color3.fromRGB(160, 90, 255))
	beam.Transparency = NumberSequence.new(0.1, 1)
	beam.FaceCamera = true
	beam.Parent = originPart

	Debris:AddItem(originPart, 0.18)
	Debris:AddItem(targetPart, 0.18)
end

-- // Entführte-Kreaturen-Panel (Freikauf gegen Lösegeld) -------------------------

local rescueButtonFrame = Instance.new("TextButton")
rescueButtonFrame.Name = "OpenRescuePanelButton"
rescueButtonFrame.AnchorPoint = Vector2.new(1, 0)
rescueButtonFrame.Position = UDim2.new(1, -16, 0, 16)
rescueButtonFrame.Size = UDim2.fromOffset(210, 40)
rescueButtonFrame.BackgroundColor3 = Color3.fromRGB(235, 90, 90)
rescueButtonFrame.Font = Enum.Font.GothamBold
rescueButtonFrame.TextSize = 15
rescueButtonFrame.TextColor3 = Color3.fromRGB(255, 255, 255)
rescueButtonFrame.Text = "Entführte Kreaturen (0)"
rescueButtonFrame.Visible = false
rescueButtonFrame.Parent = screenGui

local rescueButtonCorner = Instance.new("UICorner")
rescueButtonCorner.CornerRadius = UDim.new(0, 10)
rescueButtonCorner.Parent = rescueButtonFrame

local rescuePanel = Instance.new("Frame")
rescuePanel.Name = "RescuePanel"
rescuePanel.AnchorPoint = Vector2.new(1, 0)
rescuePanel.Position = UDim2.new(1, -16, 0, 64)
rescuePanel.Size = UDim2.fromOffset(320, 320)
rescuePanel.BackgroundColor3 = Color3.fromRGB(10, 22, 30)
rescuePanel.BackgroundTransparency = 0.05
rescuePanel.Visible = false
rescuePanel.Parent = screenGui

local rescuePanelCorner = Instance.new("UICorner")
rescuePanelCorner.CornerRadius = UDim.new(0, 14)
rescuePanelCorner.Parent = rescuePanel

local rescuePanelStroke = Instance.new("UIStroke")
rescuePanelStroke.Color = Color3.fromRGB(235, 90, 90)
rescuePanelStroke.Thickness = 1.5
rescuePanelStroke.Parent = rescuePanel

local rescuePanelTitle = Instance.new("TextLabel")
rescuePanelTitle.Size = UDim2.new(1, -20, 0, 30)
rescuePanelTitle.Position = UDim2.new(0, 10, 0, 8)
rescuePanelTitle.BackgroundTransparency = 1
rescuePanelTitle.Font = Enum.Font.GothamBold
rescuePanelTitle.TextSize = 18
rescuePanelTitle.TextColor3 = Color3.fromRGB(230, 245, 250)
rescuePanelTitle.TextXAlignment = Enum.TextXAlignment.Left
rescuePanelTitle.Text = "Entführte Kreaturen"
rescuePanelTitle.Parent = rescuePanel

local rescueCloseButton = Instance.new("TextButton")
rescueCloseButton.Size = UDim2.fromOffset(26, 26)
rescueCloseButton.Position = UDim2.new(1, -34, 0, 8)
rescueCloseButton.BackgroundColor3 = Color3.fromRGB(235, 90, 90)
rescueCloseButton.Font = Enum.Font.GothamBold
rescueCloseButton.Text = "X"
rescueCloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rescueCloseButton.Parent = rescuePanel

local rescueCloseCorner = Instance.new("UICorner")
rescueCloseCorner.CornerRadius = UDim.new(1, 0)
rescueCloseCorner.Parent = rescueCloseButton

local rescueScroll = Instance.new("ScrollingFrame")
rescueScroll.Size = UDim2.new(1, -16, 1, -50)
rescueScroll.Position = UDim2.new(0, 8, 0, 42)
rescueScroll.BackgroundTransparency = 1
rescueScroll.BorderSizePixel = 0
rescueScroll.ScrollBarThickness = 6
rescueScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rescueScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rescueScroll.Parent = rescuePanel

local rescueListLayout = Instance.new("UIListLayout")
rescueListLayout.Padding = UDim.new(0, 8)
rescueListLayout.SortOrder = Enum.SortOrder.LayoutOrder
rescueListLayout.Parent = rescueScroll

local rescueEmptyLabel = Instance.new("TextLabel")
rescueEmptyLabel.Name = "EmptyLabel"
rescueEmptyLabel.Size = UDim2.new(1, 0, 0, 40)
rescueEmptyLabel.BackgroundTransparency = 1
rescueEmptyLabel.Font = Enum.Font.GothamMedium
rescueEmptyLabel.TextSize = 14
rescueEmptyLabel.TextColor3 = Color3.fromRGB(190, 210, 215)
rescueEmptyLabel.Text = "Aktuell keine entführten Kreaturen."
rescueEmptyLabel.LayoutOrder = 0
rescueEmptyLabel.Parent = rescueScroll

local abductedCache: { [string]: { [string]: any } } = {}

local function toggleRescuePanel()
	rescuePanel.Visible = not rescuePanel.Visible
end

rescueButtonFrame.MouseButton1Click:Connect(toggleRescuePanel)
rescueCloseButton.MouseButton1Click:Connect(function()
	rescuePanel.Visible = false
end)

local function requestRescue(instanceId: string, button: TextButton)
	button.Active = false
	button.Text = "Wird angefragt ..."
	RaidRemotes.RequestRescueCreature:FireServer(instanceId)
end

local function rebuildRescuePanel()
	for _, child in ipairs(rescueScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local count = 0
	for _ in pairs(abductedCache) do
		count += 1
	end

	rescueButtonFrame.Text = ("Entführte Kreaturen (%d)"):format(count)
	rescueButtonFrame.Visible = count > 0
	rescueEmptyLabel.Visible = count == 0
	if count == 0 then
		rescuePanel.Visible = false
	end

	local order = 1
	for instanceId, abducted in pairs(abductedCache) do
		order += 1

		local row = Instance.new("Frame")
		row.Name = instanceId
		row.Size = UDim2.new(1, 0, 0, 74)
		row.BackgroundColor3 = Color3.fromRGB(16, 30, 40)
		row.LayoutOrder = order
		row.Parent = rescueScroll

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 22)
		nameLabel.Position = UDim2.new(0, 8, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = rarityColor(abducted.Rarity)
		nameLabel.Text = ("%s (%s)"):format(abducted.CreatureId, abducted.Rarity)
		nameLabel.Parent = row

		local costLabel = Instance.new("TextLabel")
		costLabel.Size = UDim2.new(1, -16, 0, 18)
		costLabel.Position = UDim2.new(0, 8, 0, 26)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Enum.Font.GothamMedium
		costLabel.TextSize = 13
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.TextColor3 = Color3.fromRGB(190, 210, 215)
		costLabel.Text = ("Lösegeld: %d Tide Coins"):format(abducted.RansomCost)
		costLabel.Parent = row

		local rescueButton = Instance.new("TextButton")
		rescueButton.Size = UDim2.new(1, -16, 0, 26)
		rescueButton.Position = UDim2.new(0, 8, 1, -32)
		rescueButton.BackgroundColor3 = Color3.fromRGB(90, 235, 140)
		rescueButton.Font = Enum.Font.GothamBold
		rescueButton.TextSize = 13
		rescueButton.TextColor3 = Color3.fromRGB(10, 20, 15)
		rescueButton.Text = ("Freikaufen (%d Tide Coins)"):format(abducted.RansomCost)
		rescueButton.Parent = row

		local rescueButtonCorner2 = Instance.new("UICorner")
		rescueButtonCorner2.CornerRadius = UDim.new(0, 6)
		rescueButtonCorner2.Parent = rescueButton

		rescueButton.MouseButton1Click:Connect(function()
			requestRescue(instanceId, rescueButton)
		end)

		-- Platzhalter-Hinweis auf das Robux-"Rettungs-Token" (GDD Abschnitt 5)
		-- - siehe RaidService.RequestRescueWithToken-Kopfkommentar: aktuell
		-- ohne Wirkung, da kein MarketplaceService-Kauf-Flow existiert.
		local tokenLabel = Instance.new("TextLabel")
		tokenLabel.Size = UDim2.new(1, -16, 0, 14)
		tokenLabel.Position = UDim2.new(0, 8, 1, -14)
		tokenLabel.BackgroundTransparency = 1
		tokenLabel.Font = Enum.Font.Gotham
		tokenLabel.TextSize = 10
		tokenLabel.TextColor3 = Color3.fromRGB(140, 160, 165)
		tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
		tokenLabel.Text = "Rettungs-Token (Robux) - bald verfügbar"
		tokenLabel.Parent = row
	end
end

-- // Countdown / Wellen-Status-Leiste (lokaler Anzeige-Zustand) -----------------

local nextRaidAt: number? = nil
local inRaid = false
local currentWaveIndex = 1
local totalWaves = 0 -- wird durch initialen Sync/Server-Events überschrieben
local currentWaveEnemyCount = 0
local currentWaveIsBoss = false

local function refreshStatusBar()
	if inRaid then
		statusIcon.Text = if currentWaveIsBoss then "☠" else "🌊"
		statusLabel.Text = ("Trench Raid läuft - Welle %d/%d%s (%d Gegner)"):format(
			currentWaveIndex,
			totalWaves,
			if currentWaveIsBoss then " (BOSS)" else "",
			currentWaveEnemyCount
		)
		statusBarStroke.Color = Color3.fromRGB(235, 90, 90)
	elseif nextRaidAt then
		local remaining = nextRaidAt - os.time()
		statusIcon.Text = "🌊"
		statusLabel.Text = ("Nächster Trench Raid: %s"):format(formatDuration(remaining))
		statusBarStroke.Color = Color3.fromRGB(70, 210, 235)
	end
end

-- // Server-Events ----------------------------------------------------------------

RaidRemotes.RaidStarted.OnClientEvent:Connect(function(payload)
	if not payload then
		return
	end
	inRaid = true
	currentWaveIndex = payload.WaveIndex or 1
	totalWaves = payload.TotalWaves or totalWaves
	currentWaveEnemyCount = payload.WaveEnemyCount or 0
	currentWaveIsBoss = payload.IsBossWave == true
	refreshStatusBar()
end)

RaidRemotes.WaveAdvanced.OnClientEvent:Connect(function(payload)
	if not payload then
		return
	end
	currentWaveIndex = payload.WaveIndex or currentWaveIndex
	totalWaves = payload.TotalWaves or totalWaves
	currentWaveEnemyCount = payload.WaveEnemyCount or 0
	currentWaveIsBoss = payload.IsBossWave == true
	refreshStatusBar()
end)

RaidRemotes.EnemyHit.OnClientEvent:Connect(function(payload)
	if payload and typeof(payload.TowerPosition) == "Vector3" and typeof(payload.EnemyPosition) == "Vector3" then
		spawnHitTracer(payload.TowerPosition, payload.EnemyPosition)
	end
end)

RaidRemotes.RaidResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end

	inRaid = false
	if result.NextRaidAt then
		nextRaidAt = result.NextRaidAt
	end
	refreshStatusBar()

	if result.Success then
		showResultPopup(true, buildVictoryText(result))
	else
		showResultPopup(false, buildDefeatText(result))
	end

	-- Entführte Kreaturen aus diesem Ergebnis sofort ins Panel übernehmen
	-- (zusätzlich zum vollständigen Re-Sync unten, für sofortige Reaktion).
	local singleAbducted = result.AbductedCreature
	if singleAbducted and singleAbducted.InstanceId then
		abductedCache[singleAbducted.InstanceId] = singleAbducted
	end
	local multiAbducted = result.AbductedCreatures
	if type(multiAbducted) == "table" then
		for _, abducted in ipairs(multiAbducted) do
			if abducted.InstanceId then
				abductedCache[abducted.InstanceId] = abducted
			end
		end
	end
	rebuildRescuePanel()
end)

RaidRemotes.RescueResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end
	if result.Success and result.InstanceId then
		abductedCache[result.InstanceId] = nil
		rebuildRescuePanel()
	else
		-- Fehlschlag: Panel neu aufbauen, damit der Button wieder aktiv/
		-- beschriftet ist (kein Sonder-Fehlertext im MVP nötig, Sync unten
		-- holt bei Bedarf ohnehin den korrekten Serverstand nach).
		rebuildRescuePanel()
	end
end)

-- // Initialer Status-Sync ---------------------------------------------------------

task.spawn(function()
	local ok, status = pcall(function()
		return RaidRemotes.GetRaidStatus:InvokeServer()
	end)
	if not ok or type(status) ~= "table" then
		warn("[RaidUIController] Initialer Raid-Status-Sync fehlgeschlagen.")
		return
	end

	nextRaidAt = status.NextRaidAt
	inRaid = status.InRaid == true
	totalWaves = status.TotalWaves or totalWaves
	currentWaveIndex = status.WaveIndex or 1

	if type(status.AbductedCreatures) == "table" then
		for _, abducted in ipairs(status.AbductedCreatures) do
			if abducted.InstanceId then
				abductedCache[abducted.InstanceId] = abducted
			end
		end
	end
	rebuildRescuePanel()
	refreshStatusBar()
end)

-- Lokaler, rein kosmetischer 1x/Sekunde-Countdown - keine Autorität, der
-- Server überschreibt `nextRaidAt` jederzeit korrekt über RaidResult.
task.spawn(function()
	while true do
		task.wait(1)
		if not inRaid then
			refreshStatusBar()
		end
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		screenGui:Destroy()
	end
end)
