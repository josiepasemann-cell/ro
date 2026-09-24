--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: RaidUIController (LocalScript)
	Zuständigkeit:
		Client-HUD für das Trench-Raid-System (GDD Abschnitt 3 + Abschnitt 9,
		Punkt 5): zeigt permanent
			- Countdown bis zum nächsten fälligen Raid (wenn kein Raid läuft),
			- Wellen-Anzeige (aktuelle/Gesamt-Welle, Boss-Kennzeichnung)
			  während ein Raid läuft,
			- ein UIKit-Panel-Ergebnis (Sieg/Niederlage inkl. Belohnung bzw.
			  entführter Kreatur) nach Raid-Ende (auch für offline ausgewertete
			  Raids, direkt nach dem Login) - inkl. UIKit.ScreenFX.BigMoment
			  bei Sieg bzw. Flash+Shake bei Niederlage,
			- eine einfache Treffer-Visualisierung (kurzer Leucht-Beam
			  Turm->Gegner) bei jedem servergemeldeten Treffer,
		sowie ein UIKit-Panel zum Freikaufen entführter Kreaturen gegen
		Tide-Coins-Lösegeld, erreichbar über die MainMenuController-
		Menüleiste ("Entführt"-Button, Bridge-BindableEvent
		"OpenAbductedCreatures" - der frühere Standalone-Button oben rechts
		entfällt, um Überlappungen mit anderen HUD-Elementen zu vermeiden).

		WICHTIG: Dies ist AUSSCHLIESSLICH Anzeige/Komfort. Die tatsächliche
		Autorität über Raid-Ablauf, Schaden, Sieg/Niederlage, Entführung und
		Lösegeld liegt einzig beim Server (RaidService) - dieses Skript zeigt
		nur, was der Server über RaidRemotes meldet, und schickt bei der
		Rettungs-Aktion lediglich eine Absichtserklärung (instanceId), die der
		Server komplett neu validiert.

		Layout: Die Status-Leiste dockt oben MITTIG an (auf Phone als volle
		Breite direkt unter der HUD-Leiste, siehe HUDController.client.lua
		Kopfkommentar für das Gesamt-Layout).

	Rojo-Einhängepunkt:
		src/client/RaidUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.RaidUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer

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

local openAbductedEvent = getOrCreateBridgeEvent("OpenAbductedCreatures")

-- // Rarity-Farbschema (Theme + Sonderfall "Abyssal", das nicht Teil des
-- regulären Gacha/Breeding-Rarity-Sets ist) -------------------------------------
local EXTRA_RARITY_COLORS: { [string]: Color3 } = {
	Abyssal = Color3.fromRGB(255, 70, 70),
}
local function rarityColor(rarity: string): Color3
	local key = (rarity :: any) :: Theme.Rarity
	if table.find(Theme.RarityOrder, key) then
		return Theme.Rarity[key]
	end
	return EXTRA_RARITY_COLORS[rarity] or Theme.Text.Secondary
end

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return ("%02d:%02d"):format(minutes, seconds)
end

-- // Root-ScreenGui (nur für die permanente Status-Leiste + Hit-Tracer) --------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RaidHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 15
Device.ApplySafeArea(screenGui)
screenGui.Parent = player:WaitForChild("PlayerGui")

local hudUiScale = Instance.new("UIScale")
hudUiScale.Parent = screenGui
local unbindHudScale = Device.BindUIScale(hudUiScale)

-- // Kompakte Status-Leiste (oben mittig: Countdown ODER Wellen-Anzeige) --------

local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.AnchorPoint = Vector2.new(0.5, 0)
statusBar.BackgroundColor3 = Theme.Background.Panel
statusBar.BackgroundTransparency = 0.15
statusBar.Parent = screenGui
Theme.ApplyCorner(statusBar, UDim.new(0, 12))
local statusBarStroke = Theme.ApplyStroke(statusBar, Theme.Neon.Cyan, 1.5)

local statusIcon = Instance.new("TextLabel")
statusIcon.Name = "Icon"
statusIcon.Size = UDim2.fromOffset(40, 40)
statusIcon.Position = UDim2.new(0, 8, 0.5, -20)
statusIcon.BackgroundTransparency = 1
statusIcon.Font = Theme.Font.BodyBold
statusIcon.TextScaled = true
statusIcon.Text = "🌊"
statusIcon.Parent = statusBar

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -56, 1, 0)
statusLabel.Position = UDim2.new(0, 52, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Theme.Font.Body
statusLabel.TextColor3 = Theme.Text.Primary
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextWrapped = true
statusLabel.TextScaled = true
statusLabel.Text = "Nächster Trench Raid: --:--"
statusLabel.Parent = statusBar
local statusLabelConstraint = Instance.new("UITextSizeConstraint")
statusLabelConstraint.MinTextSize = 12
statusLabelConstraint.MaxTextSize = 17
statusLabelConstraint.Parent = statusLabel

-- Geräteabhängiges Andocken: auf Phone volle Breite direkt unter der
-- HUD-Leiste (siehe HUDController.client.lua, dort reserviert die HUD-Leiste
-- auf Phone den obersten Streifen), sonst oben mittig als kompakte Box.
local function applyStatusBarLayout()
	if Device.ShouldUseFullscreenPanels() then
		statusBar.Position = UDim2.new(0.5, 0, 0, 104)
		statusBar.Size = UDim2.new(1, -16, 0, 52)
	else
		statusBar.Position = UDim2.new(0.5, 0, 0, 16)
		statusBar.Size = UDim2.fromOffset(360, 56)
	end
end
applyStatusBarLayout()
local statusLayoutConnection = Device.Changed:Connect(applyStatusBarLayout)

-- // Ergebnis-Panel (Sieg/Niederlage), UIKit.Panel + UIKit.Button --------------

-- HINWEIS (UIKit-Lücke): UIKit.Panel bietet keine API, um den Titel nach
-- panel.new() noch zu ändern (kein handle:SetTitle()). Deshalb bleibt der
-- Panel-Titel statisch "Raid-Ergebnis" und Sieg/Niederlage wird stattdessen
-- über ein eigenes, farbcodiertes Label im Content dargestellt.
local resultPanel = Panel.new({
	Title = "Raid-Ergebnis",
	Closable = true,
	CenteredSize = UDim2.fromOffset(420, 320),
})

local resultTitle = Instance.new("TextLabel")
resultTitle.Name = "ResultTitle"
resultTitle.BackgroundTransparency = 1
resultTitle.Size = UDim2.new(1, 0, 0, 32)
resultTitle.Font = Theme.Font.Header
resultTitle.TextScaled = true
resultTitle.TextXAlignment = Enum.TextXAlignment.Left
resultTitle.Text = ""
resultTitle.Parent = resultPanel.Content
local resultTitleConstraint = Instance.new("UITextSizeConstraint")
resultTitleConstraint.MinTextSize = 16
resultTitleConstraint.MaxTextSize = 24
resultTitleConstraint.Parent = resultTitle

local resultBody = Instance.new("TextLabel")
resultBody.Name = "Body"
resultBody.BackgroundTransparency = 1
resultBody.Position = UDim2.new(0, 0, 0, 40)
resultBody.Size = UDim2.new(1, 0, 1, -100)
resultBody.Font = Theme.Font.Body
resultBody.TextWrapped = true
resultBody.TextYAlignment = Enum.TextYAlignment.Top
resultBody.TextColor3 = Theme.Text.Secondary
resultBody.TextScaled = true
resultBody.Text = ""
resultBody.Parent = resultPanel.Content
local resultBodyConstraint = Instance.new("UITextSizeConstraint")
resultBodyConstraint.MinTextSize = 13
resultBodyConstraint.MaxTextSize = 18
resultBodyConstraint.Parent = resultBody

local resultCloseButton = Button.new({
	Parent = resultPanel.Content,
	Text = "OK",
	Variant = "Primary",
	Important = true,
	Size = UDim2.new(1, 0, 0, 48),
})
resultCloseButton.Instance.Position = UDim2.new(0, 0, 1, -48)
resultCloseButton.Clicked:Connect(function()
	resultPanel:Close()
end)

local resultAutoHideThread: thread? = nil

local function showResultPopup(won: boolean, bodyText: string)
	if resultAutoHideThread then
		task.cancel(resultAutoHideThread)
		resultAutoHideThread = nil
	end

	resultTitle.Text = if won then "Raid erfolgreich abgewehrt!" else "Trench Raid verloren"
	resultTitle.TextColor3 = if won then Theme.Semantic.Success else Theme.Semantic.Danger

	resultBody.Text = bodyText
	resultPanel:Open()

	if won then
		ScreenFX.BigMoment(Theme.Semantic.Success)
	else
		ScreenFX.Flash({ Color = Theme.Semantic.Danger, Duration = 0.5, MaxTransparency = 0.2 })
		ScreenFX.Shake(0.35, 0.5)
	end

	resultAutoHideThread = task.delay(9, function()
		resultAutoHideThread = nil
		resultPanel:Close()
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
	table.insert(lines, "Öffne 'Entführt' im Menü, um freizukaufen.")
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
	beam.Color = ColorSequence.new(Theme.Neon.Violet)
	beam.Transparency = NumberSequence.new(0.1, 1)
	beam.FaceCamera = true
	beam.Parent = originPart

	Debris:AddItem(originPart, 0.18)
	Debris:AddItem(targetPart, 0.18)
end

-- // Entführte-Kreaturen-Panel (Freikauf gegen Lösegeld), UIKit.Panel ----------

local rescuePanel = Panel.new({
	Title = "Entführte Kreaturen",
	Closable = true,
	CenteredSize = UDim2.fromOffset(380, 420),
})

local rescueScroll = Instance.new("ScrollingFrame")
rescueScroll.Name = "RescueScroll"
rescueScroll.BackgroundTransparency = 1
rescueScroll.BorderSizePixel = 0
rescueScroll.Size = UDim2.fromScale(1, 1)
rescueScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rescueScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rescueScroll.ScrollBarThickness = 6
rescueScroll.ScrollBarImageColor3 = Theme.Neon.Cyan
rescueScroll.Parent = rescuePanel.Content

local rescueListLayout = Instance.new("UIListLayout")
rescueListLayout.Padding = UDim.new(0, 8)
rescueListLayout.SortOrder = Enum.SortOrder.LayoutOrder
rescueListLayout.Parent = rescueScroll

local rescueEmptyLabel = Instance.new("TextLabel")
rescueEmptyLabel.Name = "EmptyLabel"
rescueEmptyLabel.Size = UDim2.new(1, 0, 0, 40)
rescueEmptyLabel.BackgroundTransparency = 1
rescueEmptyLabel.Font = Theme.Font.Body
rescueEmptyLabel.TextColor3 = Theme.Text.Muted
rescueEmptyLabel.TextScaled = true
rescueEmptyLabel.Text = "Aktuell keine entführten Kreaturen."
rescueEmptyLabel.LayoutOrder = 0
rescueEmptyLabel.Parent = rescueScroll

local abductedCache: { [string]: { [string]: any } } = {}
local rescueRowHandles: { [string]: { Frame: Frame, Button: any } } = {}

local function requestRescue(instanceId: string, button: any)
	button:SetDisabled(true)
	button:SetText("Wird angefragt ...")
	RaidRemotes.RequestRescueCreature:FireServer(instanceId)
end

local function rebuildRescuePanel()
	for _, entry in rescueRowHandles do
		entry.Button:Destroy()
		entry.Frame:Destroy()
	end
	table.clear(rescueRowHandles)

	local count = 0
	for _ in pairs(abductedCache) do
		count += 1
	end
	rescueEmptyLabel.Visible = count == 0

	local order = 1
	for instanceId, abducted in pairs(abductedCache) do
		order += 1

		local row = Instance.new("Frame")
		row.Name = instanceId
		row.Size = UDim2.new(1, 0, 0, 96)
		row.BackgroundColor3 = Theme.Background.PanelLight
		row.LayoutOrder = order
		row.Parent = rescueScroll
		Theme.ApplyCorner(row, UDim.new(0, 8))

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 22)
		nameLabel.Position = UDim2.new(0, 8, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.Font.BodyBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = rarityColor(abducted.Rarity)
		nameLabel.Text = ("%s (%s)"):format(abducted.CreatureId, abducted.Rarity)
		nameLabel.Parent = row

		local costLabel = Instance.new("TextLabel")
		costLabel.Size = UDim2.new(1, -16, 0, 18)
		costLabel.Position = UDim2.new(0, 8, 0, 28)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Theme.Font.Body
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.TextScaled = true
		costLabel.TextColor3 = Theme.Text.Secondary
		costLabel.Text = ("Lösegeld: %d Tide Coins"):format(abducted.RansomCost)
		costLabel.Parent = row

		local rescueButton = Button.new({
			Parent = row,
			Text = ("Freikaufen (%d Tide Coins)"):format(abducted.RansomCost),
			Variant = "Success",
			Size = UDim2.new(1, -16, 0, 34),
		})
		rescueButton.Instance.Position = UDim2.new(0, 8, 0, 50)
		rescueButton.Clicked:Connect(function()
			requestRescue(instanceId, rescueButton)
		end)

		-- Platzhalter-Hinweis auf das Robux-"Rettungs-Token" (GDD Abschnitt 5)
		-- - aktuell ohne Wirkung, da kein MarketplaceService-Kauf-Flow existiert.
		local tokenLabel = Instance.new("TextLabel")
		tokenLabel.Size = UDim2.new(1, -16, 0, 14)
		tokenLabel.Position = UDim2.new(0, 8, 1, -16)
		tokenLabel.BackgroundTransparency = 1
		tokenLabel.Font = Theme.Font.Body
		tokenLabel.TextScaled = true
		tokenLabel.TextColor3 = Theme.Text.Muted
		tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
		tokenLabel.Text = "Rettungs-Token (Robux) - bald verfügbar"
		tokenLabel.Parent = row

		rescueRowHandles[instanceId] = { Frame = row, Button = rescueButton }
	end
end

local rescueBridgeConnection = openAbductedEvent.Event:Connect(function()
	rebuildRescuePanel()
	rescuePanel:Open()
end)

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
		statusLabel.Text = ("Raid läuft - Welle %d/%d%s (%d Gegner)"):format(
			currentWaveIndex,
			totalWaves,
			if currentWaveIsBoss then " (BOSS)" else "",
			currentWaveEnemyCount
		)
		statusBarStroke.Color = Theme.Semantic.Danger
	elseif nextRaidAt then
		local remaining = nextRaidAt - os.time()
		statusIcon.Text = "🌊"
		statusLabel.Text = ("Nächster Raid: %s"):format(formatDuration(remaining))
		statusBarStroke.Color = Theme.Neon.Cyan
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

	if not result.Success and (singleAbducted or (type(multiAbducted) == "table" and #multiAbducted > 0)) then
		Toast.Show({
			Text = "Kreatur(en) entführt! Öffne 'Entführt' im Menü zum Freikaufen.",
			Type = "Warning",
			Duration = 5,
		})
	end
end)

RaidRemotes.RescueResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end
	if result.Success and result.InstanceId then
		abductedCache[result.InstanceId] = nil
		rebuildRescuePanel()
		Toast.Show({ Text = "Kreatur freigekauft!", Type = "Success" })
	else
		-- Fehlschlag: Panel neu aufbauen, damit der Button wieder aktiv/
		-- beschriftet ist (kein Sonder-Fehlertext im MVP nötig, Sync unten
		-- holt bei Bedarf ohnehin den korrekten Serverstand nach).
		rebuildRescuePanel()
		Toast.Show({ Text = "Freikauf fehlgeschlagen.", Type = "Error" })
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
local countdownThread = task.spawn(function()
	while true do
		task.wait(1)
		if not inRaid then
			refreshStatusBar()
		end
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	statusLayoutConnection:Disconnect()
	rescueBridgeConnection:Disconnect()
	task.cancel(countdownThread)
	unbindHudScale()
	resultPanel:Destroy()
	rescuePanel:Destroy()
	screenGui:Destroy()
end)
