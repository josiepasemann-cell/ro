--[[
	Abyssara – Deep Tide Tycoon
	Modul: TravelService
	Zuständigkeit:
		Kernlogik des Reise-/Teleport-Systems (GDD Abschnitt 4 "Hub-Welt
		Tidal Market" + Abschnitt 6 "Zonenportal Dämmerzone Level 10" +
		Auftrag Punkt 4): Teleport zum eigenen Plot (ProximityPrompt am
		hub-seitigen "PlotGate" + Remote), zurück zum Hub (Remote), sowie zu
		den 4 Zonen-Portalen (ProximityPrompt an jedem "Portal_<Zone>" +
		Remote) mit serverseitiger RequiredLevel-Prüfung
		(PlayerDataService.GetLevel - siehe assets/models/README.md,
		Abschnitt "hub": jedes Portal trägt bereits `RequiredLevel` als
		Attribut, `1`/`10`/`25`/`45`).

		Zonen-Terrain-Chunks existieren im MVP-Scope nur für Sonnenzone und
		Dämmerzone im WELTATLAS als tatsächlich begehbare Geometrie (siehe
		docs/game-design-doc.md Abschnitt 10 "1 Hub-Welt + 2 Zonen"), aber
		ALLE 4 Terrain-Chunk-Buildscripts existieren bereits als Assets
		(assets/models/README.md, Abschnitt "terrain") - dieses Modul prüft
		daher bei JEDER Zonen-Anfrage live, ob der jeweilige Terrain-Chunk
		tatsächlich in der Welt steht (Workspace.Assets.Terrain.<Name>), und
		antwortet bei fehlendem Chunk klar mit Reason = "ZoneComingSoon"
		("Zone kommt bald") statt fehlzuschlagen oder ins Leere zu
		teleportieren.

		WICHTIG (Dateibesitz): Die Hub-/Zonen-/Plot-GEOMETRIE selbst
		(TidalMarketHub.lua, *TerrainChunk.lua, HabitatPlotBase.lua) wird
		NICHT verändert - dieses Modul hängt ProximityPrompts ausschließlich
		zur LAUFZEIT an bereits vorhandene Instanzen an (identisches Prinzip
		zu PickupSpawner.attachDepositPrompt an GlowBuoyStation-Gebäuden).

	Sicherheitsprinzip (kein Client-Trust):
		JEDE Teleport-Anfrage (ob per ProximityPrompt ODER per Remote) wird
		hier vollständig serverseitig neu validiert: Cooldown, Plot-Existenz
		(PlotRegistry - nur der EIGENE Plot ist erreichbar, `zoneId` gegen
		eine feste Whitelist, RequiredLevel gegen PlayerDataService.GetLevel.
		Character:PivotTo läuft ausschließlich hier, niemals clientseitig
		vorgegeben.

	Sichere Ziel-Position ("über dem Boden, nicht in der Wand"):
		findSafeLandingCFrame() castet einen Strahl von hoch über der
		angepeilten XZ-Position senkrecht nach unten und landet auf dem ersten
		getroffenen Teil + kleinem Sicherheitsabstand. Fällt auf die
		ursprüngliche Y-Koordinate + Sicherheitsabstand zurück, falls nichts
		getroffen wird (z. B. Chunk ohne durchgehenden Boden an dieser Stelle).

	Rojo-Einhängepunkt:
		src/server/TravelService.lua -> ServerScriptService.TravelService
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local TravelRemotes = require(ReplicatedStorage:WaitForChild("TravelRemotes"))

export type TravelFailureReason =
	"OnCooldown"
	| "NoPlot"
	| "UnknownZone"
	| "LevelTooLow"
	| "ZoneComingSoon"
	| "NoCharacter"
	| "NoHub"

export type ZoneId = "SunZone" | "TwilightZone" | "MidnightZone" | "HadalDepths"

local TravelService = {}

-- // Konfiguration -------------------------------------------------------------

local TRAVEL_COOLDOWN_SECONDS = 3
local LANDING_RAY_HEIGHT_STUDS = 60
local LANDING_RAY_DEPTH_STUDS = 250
local LANDING_SAFETY_OFFSET_STUDS = 3

TravelService.ZONE_IDS = { "SunZone", "TwilightZone", "MidnightZone", "HadalDepths" } :: { ZoneId }

local ZONE_TERRAIN_CHUNK_NAMES: { [ZoneId]: string } = {
	SunZone = "SunZoneTerrainChunk",
	TwilightZone = "TwilightZoneTerrainChunk",
	MidnightZone = "MidnightZoneTerrainChunk",
	HadalDepths = "HadalDepthsTerrainChunk",
}

-- Fallback-Werte, falls das Hub-Portal-Attribut aus irgendeinem Grund fehlt
-- (defensiv - siehe assets/models/README.md, sollte im Regelfall nie greifen,
-- da attachPortalPrompts das Attribut direkt vom Portal-Modell liest).
local ZONE_REQUIRED_LEVEL_FALLBACK: { [ZoneId]: number } = {
	SunZone = 1,
	TwilightZone = 10,
	MidnightZone = 25,
	HadalDepths = 45,
}

-- // Laufzeit-Zustand -----------------------------------------------------------

local lastTravelAt: { [number]: number } = {}
local zoneRequiredLevel: { [ZoneId]: number } = table.clone(ZONE_REQUIRED_LEVEL_FALLBACK)

-- // Hilfsfunktionen ------------------------------------------------------------

local function findHubModel(): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	local hubModel = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	if hubModel and hubModel:IsA("Model") then
		return hubModel
	end
	return nil
end

local function findZoneTerrainChunk(zoneId: ZoneId): Model?
	local chunkName = ZONE_TERRAIN_CHUNK_NAMES[zoneId]
	if not chunkName then
		return nil
	end
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local terrainFolder = assetsFolder and assetsFolder:FindFirstChild("Terrain")
	local chunk = terrainFolder and terrainFolder:FindFirstChild(chunkName)
	if chunk and chunk:IsA("Model") then
		return chunk
	end
	return nil
end

--- Castet einen Strahl senkrecht nach unten über `approxPosition` und liefert
--- eine sichere Landungs-CFrame (siehe Kopfkommentar). `lookAtPosition`
--- (optional) bestimmt die Blickrichtung nach der Landung.
local function findSafeLandingCFrame(approxPosition: Vector3, lookAtPosition: Vector3?): CFrame
	local rayOrigin = approxPosition + Vector3.new(0, LANDING_RAY_HEIGHT_STUDS, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("PlayerPlots") } :: { Instance }
	-- PlayerPlots wird bewusst ausgeschlossen: eine Landung "in einem fremden
	-- Habitat-Gebäude" wäre unerwünscht, wenn ein Plot-Slot zufällig unter
	-- einer Zonen-/Hub-Zielposition liegt (siehe PlotRegistry-Slot-Rasterung).

	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -LANDING_RAY_DEPTH_STUDS, 0), params)
	local landY = if result then result.Position.Y + LANDING_SAFETY_OFFSET_STUDS else approxPosition.Y + LANDING_SAFETY_OFFSET_STUDS

	local landing = Vector3.new(approxPosition.X, landY, approxPosition.Z)
	if lookAtPosition then
		return CFrame.new(landing, Vector3.new(lookAtPosition.X, landing.Y, lookAtPosition.Z))
	end
	return CFrame.new(landing)
end

local function checkCooldown(player: Player): boolean
	local now = os.clock()
	local last = lastTravelAt[player.UserId] or 0
	if now - last < TRAVEL_COOLDOWN_SECONDS then
		return false
	end
	lastTravelAt[player.UserId] = now
	return true
end

local function teleportCharacter(player: Player, cframe: CFrame): boolean
	local character = player.Character
	if not character or not character.PrimaryPart then
		return false
	end
	character:PivotTo(cframe)
	return true
end

local function fireResult(player: Player, payload: { [string]: any })
	TravelRemotes.TravelResult:FireClient(player, payload)
end

-- // Öffentliche API --------------------------------------------------------

--- Teleportiert `player` zu seinem EIGENEN, bereits zugewiesenen Plot.
function TravelService.RequestTravelToPlot(player: Player)
	if not checkCooldown(player) then
		fireResult(player, { Success = false, Reason = "OnCooldown", Destination = "Plot" })
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		fireResult(player, { Success = false, Reason = "NoPlot", Destination = "Plot" })
		return
	end

	local cframe = findSafeLandingCFrame(plot.PrimaryPart.Position)
	if not teleportCharacter(player, cframe) then
		fireResult(player, { Success = false, Reason = "NoCharacter", Destination = "Plot" })
		return
	end

	fireResult(player, { Success = true, Destination = "Plot" })
end

--- Teleportiert `player` zurück zur Hub-Welt "Tidal Market" (zufällige
--- vorhandene SpawnLocation, sonst Modell-Pivot als Fallback).
function TravelService.RequestTravelToHub(player: Player)
	if not checkCooldown(player) then
		fireResult(player, { Success = false, Reason = "OnCooldown", Destination = "Hub" })
		return
	end

	local hubModel = findHubModel()
	if not hubModel then
		fireResult(player, { Success = false, Reason = "NoHub", Destination = "Hub" })
		return
	end

	local spawnCandidates = {}
	for _, descendant in ipairs(hubModel:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then
			table.insert(spawnCandidates, descendant)
		end
	end

	local targetPosition: Vector3
	if #spawnCandidates > 0 then
		local chosen = spawnCandidates[Random.new():NextInteger(1, #spawnCandidates)]
		targetPosition = chosen.Position
	elseif hubModel.PrimaryPart then
		targetPosition = hubModel.PrimaryPart.Position
	else
		targetPosition = hubModel:GetPivot().Position
	end

	local cframe = findSafeLandingCFrame(targetPosition)
	if not teleportCharacter(player, cframe) then
		fireResult(player, { Success = false, Reason = "NoCharacter", Destination = "Hub" })
		return
	end

	fireResult(player, { Success = true, Destination = "Hub" })
end

--- Teleportiert `player` zu Zone `zoneId`, sofern serverseitig alle
--- Bedingungen erfüllt sind (bekannte Zone, RequiredLevel erreicht, Terrain-
--- Chunk existiert bereits in der Welt).
function TravelService.RequestTravelToZone(player: Player, zoneId: any)
	if not checkCooldown(player) then
		fireResult(player, { Success = false, Reason = "OnCooldown", Destination = zoneId })
		return
	end

	if type(zoneId) ~= "string" or not table.find(TravelService.ZONE_IDS, zoneId) then
		fireResult(player, { Success = false, Reason = "UnknownZone" })
		return
	end
	local zone = zoneId :: ZoneId

	local requiredLevel = zoneRequiredLevel[zone] or ZONE_REQUIRED_LEVEL_FALLBACK[zone]
	local currentLevel = PlayerDataService.GetLevel(player)
	if currentLevel < requiredLevel then
		fireResult(player, {
			Success = false,
			Reason = "LevelTooLow",
			Destination = zone,
			RequiredLevel = requiredLevel,
			CurrentLevel = currentLevel,
		})
		return
	end

	local chunk = findZoneTerrainChunk(zone)
	if not chunk or not chunk.PrimaryPart then
		-- Terrain-Chunk (noch) nicht in der Welt vorhanden - klare Meldung
		-- statt Fehlschlag/Absturz (siehe Kopfkommentar).
		fireResult(player, { Success = false, Reason = "ZoneComingSoon", Destination = zone })
		return
	end

	local cframe = findSafeLandingCFrame(chunk.PrimaryPart.Position)
	if not teleportCharacter(player, cframe) then
		fireResult(player, { Success = false, Reason = "NoCharacter", Destination = zone })
		return
	end

	fireResult(player, { Success = true, Destination = zone })
end

-- // ProximityPrompt-Setup (PlotGate + 4x Portal_<Zone>, siehe Kopfkommentar) --

local function attachPlotGatePrompt(hubModel: Model)
	local gate = hubModel:FindFirstChild("PlotGate", true)
	if not gate or not gate:IsA("Model") then
		return
	end
	local part = (gate :: Model).PrimaryPart or gate:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end
	if part:FindFirstChild("PlotGatePrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlotGatePrompt"
	prompt.ActionText = "To Your Plot"
	prompt.ObjectText = "Plot Gate"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		TravelService.RequestTravelToPlot(player)
	end)
end

local function attachZonePortalPrompts(hubModel: Model)
	for _, zoneId in ipairs(TravelService.ZONE_IDS) do
		local portal = hubModel:FindFirstChild("Portal_" .. zoneId, true)
		if portal and portal:IsA("Model") then
			local requiredLevelAttr = portal:GetAttribute("RequiredLevel")
			if type(requiredLevelAttr) == "number" then
				zoneRequiredLevel[zoneId] = requiredLevelAttr
			end

			local part = (portal :: Model).PrimaryPart or portal:FindFirstChildWhichIsA("BasePart", true)
			if part and not part:FindFirstChild("ZonePortalPrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "ZonePortalPrompt"
				prompt.ActionText = "Travel"
				prompt.ObjectText = zoneId
				prompt.HoldDuration = 0.5
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = part

				prompt.Triggered:Connect(function(player: Player)
					TravelService.RequestTravelToZone(player, zoneId)
				end)
			end
		end
	end
end

local function runHubPromptSetup()
	local waited = 0
	local hubModel: Model? = nil
	while waited < 30 do
		hubModel = findHubModel()
		if hubModel then
			break
		end
		task.wait(2)
		waited += 2
	end

	if not hubModel then
		warn(
			"[TravelService] Workspace.Assets.Hub.TidalMarketHub not found - PlotGate/zone portal "
				.. "ProximityPrompts skipped (see assets/models/hub/TidalMarketHub.lua)."
		)
		return
	end

	attachPlotGatePrompt(hubModel)
	attachZonePortalPrompts(hubModel)
	print("[Abyssara] TravelService: PlotGate-/Zonenportal-Prompts am Hub eingerichtet.")
end

-- // Aufräumen bei PlayerRemoving ----------------------------------------------

local function onPlayerRemoving(player: Player)
	lastTravelAt[player.UserId] = nil
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

task.spawn(runHubPromptSetup)

return TravelService
