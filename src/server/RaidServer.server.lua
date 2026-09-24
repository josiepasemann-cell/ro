--[[
	Abyssara – Deep Tide Tycoon
	Skript: RaidServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Trench-Raid-Systems auf Server-Seite:
		verbindet die RemoteEvent/RemoteFunction-Kanäle aus RaidRemotes mit der
		reinen Logik in RaidService, und orchestriert den Login-/Leave-Ablauf
		(Spielerdaten abwarten -> verpasste Offline-Raids auswerten, bzw. beim
		Verlassen: laufenden Raid neutral aufräumen). Enthält selbst KEINE
		Raid-/Kampf-/Persistenz-Logik - das bleibt vollständig in RaidService,
		damit dieses Skript austauschbar/dünn bleibt (identisches Muster zu
		BreedingService/BreedingServer.server.lua bzw. PlacementService/
		PlacementServer.server.lua).

		WICHTIG (Reihenfolge): RaidService.HandlePlayerLogin wertet verpasste
		Offline-Raids ausschließlich anhand des PERSISTENTEN HabitatLayouts
		aus (PlayerDataService.GetHabitatLayout, siehe RaidService.
		computeTowerDpsFromLayout) - NICHT anhand von Workspace-Modellen. Es
		ist daher UNKRITISCH, ob dieses Skript vor oder nach
		PlacementServer.server.lua/PlotRegistry.AssignPlot hochläuft; ein
		Live-Raid (Workspace-Modelle, siehe RaidService.startRaid) wird
		ohnehin erst durch den zeitgesteuerten Scheduler-Loop ausgelöst,
		lange nachdem der Plot beim Login längst wiederhergestellt ist.

	Rojo-Einhängepunkt:
		src/server/RaidServer.server.lua -> ServerScriptService.RaidServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestRescueCreature/RequestRescueWithToken werden hier 1:1 an
		RaidService durchgereicht - jeder einzelne Payload-Wert (instanceId)
		wird DORT vollständig neu gegen die eigene AbductedCreatures-Liste des
		anfragenden Spielers validiert. Der einzige vertrauenswürdige Wert aus
		dem Event ist `player`, den die Roblox-Engine selbst als ersten
		Parameter von OnServerEvent liefert (vom Client nicht fälschbar).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RaidService = require(script.Parent:WaitForChild("RaidService"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))

local JOIN_DATA_TIMEOUT_SECONDS = 15

RaidRemotes.GetRaidStatus.OnServerInvoke = function(player: Player)
	return RaidService.GetStatus(player)
end

RaidRemotes.RequestRescueCreature.OnServerEvent:Connect(function(player: Player, instanceId)
	local result = RaidService.RequestRescue(player, instanceId)
	RaidRemotes.RescueResult:FireClient(player, result)
end)

RaidRemotes.RequestRescueWithToken.OnServerEvent:Connect(function(player: Player, instanceId)
	local success, reason = RaidService.RequestRescueWithToken(player, instanceId)
	RaidRemotes.RescueWithTokenResult:FireClient(player, {
		Success = success,
		Reason = reason,
	})
end)

local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
	if not data then
		-- Laden fehlgeschlagen/Timeout: PlayerDataService kickt den Spieler
		-- in diesem Fall bereits selbst - hier nur sauber abbrechen.
		return
	end

	if not Players:GetPlayerByUserId(player.UserId) then
		-- Spieler während des Ladens bereits wieder disconnected.
		return
	end

	RaidService.HandlePlayerLogin(player)
end

local function onPlayerRemoving(player: Player)
	RaidService.CleanupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Falls dieses Skript erst nach PlayerAdded-Events hochläuft (z. B.
-- Studio-Playtest-Timing), bereits verbundene Spieler nachträglich
-- einbuchen - gleiche Absicherung wie PlayerDataService/PlacementServer.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

print("[Abyssara] RaidServer bereit (GetRaidStatus / RequestRescueCreature verdrahtet).")
