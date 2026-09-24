--[[
	Abyssara – Deep Tide Tycoon
	Skript: TravelServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünnes Bootstrap/Verdrahtung des Reise-/Teleport-Systems: verbindet
		die Remote-Kanäle aus TravelRemotes mit der reinen Logik in
		TravelService (identisches Muster zu BreedingService/BreedingServer.
		server.lua). Die ProximityPrompt-Verdrahtung an Hub-Objekten
		übernimmt TravelService selbst beim require() (siehe dortigen
		Bootstrap-Abschnitt) - dieses Skript deckt ausschließlich den
		Remote-Weg (z. B. für ein künftiges Hub-Schnellreise-UI-Panel) ab.

	Rojo-Einhängepunkt:
		src/server/TravelServer.server.lua -> ServerScriptService.TravelServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TravelService = require(script.Parent:WaitForChild("TravelService"))
local TravelRemotes = require(ReplicatedStorage:WaitForChild("TravelRemotes"))

TravelRemotes.RequestTravelToPlot.OnServerEvent:Connect(function(player: Player)
	TravelService.RequestTravelToPlot(player)
end)

TravelRemotes.RequestTravelToHub.OnServerEvent:Connect(function(player: Player)
	TravelService.RequestTravelToHub(player)
end)

TravelRemotes.RequestTravelToZone.OnServerEvent:Connect(function(player: Player, zoneId)
	TravelService.RequestTravelToZone(player, zoneId)
end)

print("[Abyssara] TravelServer ready (RequestTravelToPlot / RequestTravelToHub / RequestTravelToZone wired up).")
