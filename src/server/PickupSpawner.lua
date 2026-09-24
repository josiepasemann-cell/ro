--[[
	Abyssara – Deep Tide Tycoon
	Modul: PickupSpawner
	Zuständigkeit:
		Lässt auf jedem Spieler-Plot periodisch begrenzt viele, leuchtende
		"Glow Spore"-Pickups spawnen (GDD Abschnitt 3: "Sammelt 'Glow Spores'
		/ Bioluminiszenz-Ressourcen ..."), macht sie über ein
		`ProximityPrompt` aufhebbar (funktioniert plattformübergreifend ohne
		Zusatzcode: PC-Taste, automatischer Touch-Button auf Mobile,
		Gamepad-Button - siehe Roblox-Engine-Verhalten von ProximityPrompt)
		und bringt aufgehobene Sporen über HeldItemService.HoldItem sichtbar
		in die Hand des Spielers.

		Bringt außerdem ein Abgabe-`ProximityPrompt` an jeder platzierten
		GlowBuoyStation eines Spielers an (siehe PlacementService/
		BuildingConfig - NICHT von diesem Modul selbst platziert, nur
		beobachtet): Abgeben einer gehaltenen Glow Spore dort gewährt einen
		Bonus über PlayerDataService.AddCurrency("TideCoins", ...).

		Validiert serverseitig sowohl die Distanz (Prompt-Reichweite PLUS
		erneuter Server-Check) als auch das Eigentum (nur die eigenen Sporen
		des jeweiligen Plot-Eigentümers lassen sich aufheben) - siehe
		Sicherheitsprinzip unten.

		Wird eine gehaltene Glow Spore fallen gelassen (HeldItemService.
		DropHeld, z. B. über die "G"-Taste im Client), abonniert dieses
		Modul `HeldItemService.ItemDropped` und registriert sie automatisch
		wieder als aufhebbares Welt-Pickup auf dem Plot des Spielers.

	Sicherheitsprinzip (kein Client-Trust):
		ProximityPrompt.Triggered liefert als ersten Parameter den
		auslösenden `Player` direkt von der Roblox-Engine (nicht vom Client
		fälschbar). Trotzdem wird JEDE Aktion hier zusätzlich serverseitig
		geprüft: Eigentümer-Attribut (`OwnerUserId`) gegen `player.UserId`,
		erneute Distanzmessung server-seitig (HumanoidRootPart <-> Pickup/
		Station), und beim Aufheben ein sofortiges `prompt.Enabled = false`
		gegen doppeltes Auslösen während des Übergangs.

	Eigene, in sich geschlossene Asset-Vorlagen-Beschaffung:
		Analog zu AssetTemplateSetup.lua (das dieses Modul bewusst NICHT
		anfasst/erweitert, siehe Dateibesitz-Vorgabe), promotet dieses Modul
		selbst das einmalig in Studio ausgeführte Buildscript-Ergebnis
		`Workspace.Assets.Pickups.GlowSporePickup` (siehe
		assets/models/pickups/GlowSporePickup.lua) zu einer wiederverwendbaren
		Vorlage unter `ReplicatedStorage.AssetTemplates.Pickups`.

	Rojo-Einhängepunkt:
		src/server/PickupSpawner.lua -> ServerScriptService.PickupSpawner
		(reines Logik-Modul, analog zum PlacementService/PlacementServer-
		Muster - die Remote-/Join-/Leave-Verdrahtung übernimmt
		HeldItemServer.server.lua über PickupSpawner.OnPlayerAdded/
		OnPlayerRemoving.)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local HeldItemService = require(script.Parent:WaitForChild("HeldItemService"))
local HeldItemConfig = require(ReplicatedStorage:WaitForChild("HeldItemConfig"))

local PickupSpawner = {}

local GLOW_SPORE_KIND = "GlowSpore"
local PLOT_WAIT_TIMEOUT_SECONDS = 15

local rng = Random.new()

-- // Eigene Asset-Vorlagen-Beschaffung (Pickups) ------------------------------

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Folder
end

local pickupTemplatesFolder = getOrCreateFolder(getOrCreateFolder(ReplicatedStorage, "AssetTemplates"), "Pickups")

local function promotePickupTemplate(name: string)
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local pickupsSource = assetsFolder and assetsFolder:FindFirstChild("Pickups")
	local source = pickupsSource and pickupsSource:FindFirstChild(name)

	if not source or not source:IsA("Model") then
		if not pickupTemplatesFolder:FindFirstChild(name) then
			warn(
				("[PickupSpawner] '%s' fehlt unter Workspace.Assets.Pickups - bitte assets/models/pickups/%s.lua einmal in Studio ausführen (siehe assets/models/README.md)."):format(
					name,
					name
				)
			)
		end
		return
	end

	local clone = source:Clone()
	clone.Name = name

	local existingTemplate = pickupTemplatesFolder:FindFirstChild(name)
	if existingTemplate then
		existingTemplate:Destroy()
	end
	clone.Parent = pickupTemplatesFolder

	source:Destroy()
	print(("[PickupSpawner] Template '%s' bereit unter %s."):format(name, pickupTemplatesFolder:GetFullName()))
end

promotePickupTemplate("GlowSporePickup")

local function getGlowSporeTemplate(): Model?
	local model = pickupTemplatesFolder:FindFirstChild("GlowSporePickup")
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- // Pro-Spieler-Laufzeitzustand ----------------------------------------------

local activeUsers: { [number]: boolean } = {}
local livePickupsByUser: { [number]: { Model } } = {}

local function countLivePickups(userId: number): number
	local list = livePickupsByUser[userId]
	if not list then
		return 0
	end
	for index = #list, 1, -1 do
		local model = list[index]
		if not model or not model.Parent then
			table.remove(list, index)
		end
	end
	return #list
end

-- // Glow-Spore-Pickups: Aufheben --------------------------------------------

local function onPickupTriggered(player: Player, pickup: Model, prompt: ProximityPrompt)
	if not pickup.Parent or not prompt.Enabled then
		return
	end

	local ownerUserId = pickup:GetAttribute("OwnerUserId")
	if ownerUserId ~= player.UserId then
		-- Besitz-Validierung: nur die eigenen Sporen des Plot-Eigentümers
		-- lassen sich aufheben (siehe Auftrag).
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local anchorPart = pickup.PrimaryPart or pickup:FindFirstChildWhichIsA("BasePart")
	if not rootPart or not anchorPart then
		return
	end

	-- Zusätzliche Server-Distanzprüfung (Verteidigung in der Tiefe on top
	-- von ProximityPrompt.MaxActivationDistance selbst, siehe Auftrag).
	local distance = (rootPart.Position - anchorPart.Position).Magnitude
	if distance > HeldItemConfig.Pickup.PromptMaxActivationDistance + 3 then
		return
	end

	prompt.Enabled = false -- verhindert doppeltes Auslösen während des Übergangs

	local success = HeldItemService.HoldItem(player, GLOW_SPORE_KIND, pickup, {
		Reparent = true,
	})

	if not success then
		prompt.Enabled = true
		return
	end

	-- Das Modell wandert per Reparent direkt in die Hand des Spielers - der
	-- Prompt selbst (bislang Kind desselben Parts) wird nicht mehr gebraucht
	-- und würde sonst sichtbar am gehaltenen Item mitreisen.
	task.defer(function()
		if prompt then
			prompt:Destroy()
		end
	end)
end

local function attachPickupPrompt(pickup: Model)
	local part = pickup.PrimaryPart or pickup:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	if part:FindFirstChild("PickupPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = "Glow Spore"
	prompt.HoldDuration = HeldItemConfig.Pickup.PromptHoldDurationSeconds
	prompt.MaxActivationDistance = HeldItemConfig.Pickup.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		onPickupTriggered(player, pickup, prompt)
	end)
end

-- // Glow-Spore-Pickups: Spawnen ----------------------------------------------

local function getOrCreatePickupsFolder(plot: Model): Folder
	return getOrCreateFolder(plot, "Pickups")
end

local function spawnGlowSporeForPlayer(player: Player, plot: Model)
	local userId = player.UserId
	local list = livePickupsByUser[userId]
	if not list then
		list = {}
		livePickupsByUser[userId] = list
	end

	if countLivePickups(userId) >= HeldItemConfig.Pickup.MaxPerPlot then
		return
	end

	local template = getGlowSporeTemplate()
	if not template then
		return
	end

	local platform = plot.PrimaryPart
	if not platform then
		return
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)

	local angle = rng:NextNumber() * math.pi * 2
	local radius = rng:NextNumber(HeldItemConfig.Pickup.MinSpawnRadiusStuds, HeldItemConfig.Pickup.SpawnRadiusStuds)
	local localOffset = Vector3.new(math.cos(angle) * radius, platform.Size.Y / 2 + 1.5, math.sin(angle) * radius)

	local spore = template:Clone()
	spore.Name = "GlowSporePickup"
	spore:SetAttribute("OwnerUserId", userId)
	spore.Parent = pickupsFolder
	spore:PivotTo(platform.CFrame * CFrame.new(localOffset))

	attachPickupPrompt(spore)

	table.insert(list, spore)
end

-- // GlowBuoyStation: Abgabe --------------------------------------------------

local function onDepositTriggered(player: Player, station: Model)
	local held = HeldItemService.GetHeld(player)
	if not held or held.ItemKind ~= GLOW_SPORE_KIND then
		-- Nichts (Passendes) zum Abgeben - keine Aktion, kein Fehlerzustand.
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local stationPart = station.PrimaryPart
	if not rootPart or not stationPart then
		return
	end

	local distance = (rootPart.Position - stationPart.Position).Magnitude
	if distance > HeldItemConfig.Deposit.PromptMaxActivationDistance + 3 then
		return
	end

	local consumedKind, consumedModel = HeldItemService.ConsumeHeld(player)
	if not consumedKind then
		return
	end
	if consumedModel then
		consumedModel:Destroy()
	end

	local ok = PlayerDataService.AddCurrency(player, "TideCoins", HeldItemConfig.Deposit.TideCoinsReward)
	if not ok then
		warn(("[PickupSpawner] AddCurrency für %s (GlowSpore-Abgabe) fehlgeschlagen."):format(player.Name))
	end
end

local function attachDepositPrompt(station: Model)
	local part = station.PrimaryPart or station:FindFirstChild("MainOrb") or station:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	if part:FindFirstChild("DepositPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ActionText = "Abgeben"
	prompt.ObjectText = "Lichtboje"
	prompt.HoldDuration = HeldItemConfig.Deposit.PromptHoldDurationSeconds
	prompt.MaxActivationDistance = HeldItemConfig.Deposit.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		onDepositTriggered(player, station)
	end)
end

--- Durchsucht die platzierten Gebäude von `player` (PlotRegistry/
--- PlacementService - hier NICHT selbst platziert, nur beobachtet) nach
--- GlowBuoyStation-Instanzen und bringt dort - idempotent - ein
--- Abgabe-Prompt an. Wird pro Spawn-Tick erneut aufgerufen statt nur einmal
--- per ChildAdded, um jede mögliche Reihenfolge-Race zwischen diesem Modul
--- und PlacementServer.server.lua beim Join sicher abzudecken.
local function ensureDepositPrompts(player: Player)
	local buildingsFolder = PlotRegistry.GetBuildingsFolder(player)
	if not buildingsFolder then
		return
	end
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("BuildingId") == "GlowBuoyStation" then
			attachDepositPrompt(child)
		end
	end
end

-- // Fallenlassen: gedropptes Item wird wieder zum Pickup ---------------------

HeldItemService.ItemDropped:Connect(function(player: Player, model: Model, itemKind: string, _dropCFrame: CFrame)
	if itemKind ~= GLOW_SPORE_KIND then
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot then
		-- Kein Plot (mehr) vorhanden (z. B. Spieler verlässt gerade) - das
		-- Item wurde von HeldItemService bereits sichtbar in die Welt
		-- gelegt, ohne Plot-Zuordnung aber nicht sinnvoll nachverfolgbar.
		model:Destroy()
		return
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)
	model.Name = "GlowSporePickup"
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = pickupsFolder

	attachPickupPrompt(model)

	local list = livePickupsByUser[player.UserId]
	if not list then
		list = {}
		livePickupsByUser[player.UserId] = list
	end
	table.insert(list, model)
end)

-- // Pro-Spieler-Spawn-Loop ----------------------------------------------------

local function waitForPlot(player: Player): Model?
	local waited = 0
	while activeUsers[player.UserId] do
		local plot = PlotRegistry.GetPlot(player)
		if plot then
			return plot
		end
		if waited >= PLOT_WAIT_TIMEOUT_SECONDS then
			return nil
		end
		task.wait(1)
		waited += 1
	end
	return nil
end

local function plotSpawnLoop(player: Player)
	local plot = waitForPlot(player)
	if not plot then
		return
	end

	while activeUsers[player.UserId] and plot.Parent do
		ensureDepositPrompts(player)
		spawnGlowSporeForPlayer(player, plot)
		task.wait(HeldItemConfig.Pickup.SpawnCheckIntervalSeconds)
	end
end

-- // Öffentliche API (Join-/Leave-Verdrahtung durch HeldItemServer.server.lua) -

function PickupSpawner.OnPlayerAdded(player: Player)
	activeUsers[player.UserId] = true
	livePickupsByUser[player.UserId] = {}
	task.spawn(plotSpawnLoop, player)
end

function PickupSpawner.OnPlayerRemoving(player: Player)
	activeUsers[player.UserId] = nil
	-- Die Pickup-Instanzen selbst liegen unter `plot.Pickups` und werden
	-- automatisch mit dem gesamten Plot zerstört, sobald PlotRegistry.
	-- ReleasePlot(player) läuft (siehe PlacementServer.server.lua) - hier
	-- nur die reine Laufzeit-Buchführung aufräumen.
	livePickupsByUser[player.UserId] = nil
end

-- Kein eigenständiges PlayerAdded/PlayerRemoving-Binding hier (anders als
-- z. B. PlayerDataService) - die Join-/Leave-Verdrahtung inkl. bereits
-- verbundener Spieler übernimmt bewusst zentral HeldItemServer.server.lua
-- (gleiches Aufteilungsmuster wie PlacementService/PlacementServer.server.lua).

return PickupSpawner
