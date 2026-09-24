--[[
	Abyssara – Deep Tide Tycoon
	Skript: PlacementServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Bauplatzierungs-Systems auf Server-Seite:
		verbindet die RemoteEvent-Kanäle aus HabitatRemotes mit der reinen
		Logik in PlacementService, und orchestriert den Join-/Leave-Ablauf
		(Plot zuweisen -> Spielerdaten abwarten -> Layout rekonstruieren,
		bzw. beim Verlassen: Laufzeit-Zustand aufräumen -> Plot freigeben).
		Enthält selbst KEINE Platzierungs-/Persistenz-Logik - das bleibt
		vollständig in PlacementService, damit dieses Skript austauschbar/
		dünn bleibt (identisches Muster zu GachaService/GachaServer.
		server.lua).

	Rojo-Einhängepunkt:
		src/server/PlacementServer.server.lua -> ServerScriptService.PlacementServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestPlaceBuilding/RequestRemoveBuilding werden hier 1:1 an
		PlacementService.RequestPlace/RequestRemove durchgereicht - jeder
		einzelne Payload-Wert (BuildingId, FieldIndex, RotationY,
		PlacementId) wird DORT vollständig neu validiert. Der einzige
		vertrauenswürdige Wert aus dem Event ist `player`, den die Roblox-
		Engine selbst als ersten Parameter von OnServerEvent liefert (vom
		Client nicht fälschbar).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local PlacementService = require(script.Parent:WaitForChild("PlacementService"))
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))

HabitatRemotes.RequestPlaceBuilding.OnServerEvent:Connect(function(player: Player, buildingId, fieldIndex, rotationY)
	local result = PlacementService.RequestPlace(player, buildingId, fieldIndex, rotationY)
	HabitatRemotes.PlaceBuildingResult:FireClient(player, result)
end)

HabitatRemotes.RequestRemoveBuilding.OnServerEvent:Connect(function(player: Player, placementId)
	local result = PlacementService.RequestRemove(player, placementId)
	HabitatRemotes.RemoveBuildingResult:FireClient(player, result)
end)

local JOIN_DATA_TIMEOUT_SECONDS = 15

local function onPlayerAdded(player: Player)
	PlotRegistry.AssignPlot(player)

	local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
	if not data then
		-- Laden fehlgeschlagen/Timeout: PlayerDataService kickt den
		-- Spieler in diesem Fall bereits selbst mit einer eigenen
		-- Fehlermeldung - hier nur sauber abbrechen, keine doppelte
		-- Fehlerbehandlung/kein doppeltes Kick.
		PlotRegistry.ReleasePlot(player)
		return
	end

	if not Players:GetPlayerByUserId(player.UserId) then
		-- Spieler während des Ladens bereits wieder disconnected.
		PlotRegistry.ReleasePlot(player)
		return
	end

	PlacementService.RestorePlayerLayout(player)
end

local function onPlayerRemoving(player: Player)
	PlacementService.CleanupPlayer(player)
	PlotRegistry.ReleasePlot(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Falls dieses Skript erst nach PlayerAdded-Events hochläuft (z. B.
-- Studio-Playtest-Timing), bereits verbundene Spieler nachträglich
-- einbuchen - gleiche Absicherung wie in PlayerDataService.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

print("[Abyssara] PlacementServer bereit (RequestPlaceBuilding / RequestRemoveBuilding verdrahtet).")
