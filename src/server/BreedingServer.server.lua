--[[
	Abyssara – Deep Tide Tycoon
	Skript: BreedingServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Zucht-/Ei-Systems auf Server-Seite:
		verbindet die RemoteEvent/RemoteFunction-Kanäle aus BreedingRemotes
		mit der reinen Logik in BreedingService. Enthält selbst KEINE Zucht-
		Logik (Kosten/Timer/Rarity-Roll) - das bleibt vollständig in
		BreedingService, damit dieses Skript austauschbar/dünn bleibt
		(identisches Muster zu GachaService/GachaServer.server.lua bzw.
		PlacementService/PlacementServer.server.lua).

	Rojo-Einhängepunkt:
		src/server/BreedingServer.server.lua -> ServerScriptService.BreedingServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestStartBreeding/RequestClaimBreeding/RequestInstantComplete-
		Breeding werden hier 1:1 an BreedingService durchgereicht - jeder
		einzelne Payload-Wert (placementId) wird DORT vollständig neu gegen
		das eigene HabitatLayout des anfragenden Spielers validiert. Der
		einzige vertrauenswürdige Wert aus dem Event ist `player`, den die
		Roblox-Engine selbst als ersten Parameter von OnServerEvent liefert
		(vom Client nicht fälschbar).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreedingService = require(script.Parent:WaitForChild("BreedingService"))
local BreedingRemotes = require(ReplicatedStorage:WaitForChild("BreedingRemotes"))

BreedingRemotes.RequestStartBreeding.OnServerEvent:Connect(function(player: Player, placementId)
	local result = BreedingService.RequestStartBreeding(player, placementId)
	BreedingRemotes.StartBreedingResult:FireClient(player, result)
end)

BreedingRemotes.RequestClaimBreeding.OnServerEvent:Connect(function(player: Player, placementId)
	local result = BreedingService.RequestClaimBreeding(player, placementId)
	BreedingRemotes.ClaimBreedingResult:FireClient(player, result)
end)

BreedingRemotes.RequestInstantCompleteBreeding.OnServerEvent:Connect(function(player: Player, placementId)
	local success, reason = BreedingService.RequestInstantComplete(player, placementId)
	BreedingRemotes.InstantCompleteBreedingResult:FireClient(player, {
		Success = success,
		Reason = reason,
	})
end)

BreedingRemotes.GetBreedingStatuses.OnServerInvoke = function(player: Player)
	return BreedingService.GetAllStatuses(player)
end

print("[Abyssara] BreedingServer bereit (RequestStartBreeding / RequestClaimBreeding / GetBreedingStatuses verdrahtet).")
