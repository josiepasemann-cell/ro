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

require(script.Parent:WaitForChild("WorldBuild")).Ensure() -- builds the world on first start if the place has none (see WorldBuild.lua)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
local LeaderboardRemotes = require(ReplicatedStorage:WaitForChild("LeaderboardRemotes"))

LeaderboardRemotes.GetLeaderboard.OnServerInvoke = function(player: Player, category: any)
	return LeaderboardService.GetLeaderboard(category)
end

print("[Abyssara] LeaderboardServer ready (GetLeaderboard wired up).")
