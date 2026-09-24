--[[
	Abyssara – Deep Tide Tycoon
	Skript: LeaderboardServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünnes Bootstrap/Verdrahtung des Ranglisten-Systems: verbindet
		LeaderboardRemotes.GetLeaderboard mit der reinen Logik in
		LeaderboardService. Enthält selbst KEINE Ranglisten-Logik.

	Rojo-Einhängepunkt:
		src/server/LeaderboardServer.server.lua -> ServerScriptService.LeaderboardServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
local LeaderboardRemotes = require(ReplicatedStorage:WaitForChild("LeaderboardRemotes"))

LeaderboardRemotes.GetLeaderboard.OnServerInvoke = function(player: Player, category: any)
	return LeaderboardService.GetLeaderboard(category)
end

print("[Abyssara] LeaderboardServer bereit (GetLeaderboard verdrahtet).")
