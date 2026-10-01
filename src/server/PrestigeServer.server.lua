--[[
	Abyssara – Deep Tide Tycoon
	Script: PrestigeServer (Script, not a ModuleScript)
	Responsibility:
		Thin bootstrap that wires the PrestigeRemotes channels to
		PrestigeService (same pattern as PlacementServer/GachaServer). All
		validation, rate limiting and the actual prestige logic live in
		PrestigeService; no client value is trusted here.

	Rojo mount point:
		src/server/PrestigeServer.server.lua -> ServerScriptService.PrestigeServer
]]

require(script.Parent:WaitForChild("WorldBuild")).Ensure() -- builds the world on first start if the place has none (see WorldBuild.lua)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PrestigeService = require(script.Parent:WaitForChild("PrestigeService"))
local PrestigeRemotes = require(ReplicatedStorage:WaitForChild("PrestigeRemotes"))

PrestigeRemotes.GetPrestigeInfo.OnServerInvoke = function(player: Player)
	if not PrestigeService.CheckRate(player, "info") then
		return { Eligible = false, BlockReason = "RateLimited" }
	end
	return PrestigeService.GetInfo(player)
end

PrestigeRemotes.ArmResurface.OnServerInvoke = function(player: Player)
	return PrestigeService.ArmResurface(player)
end

PrestigeRemotes.RequestResurface.OnServerEvent:Connect(function(player: Player)
	PrestigeService.RequestResurface(player)
end)

Players.PlayerRemoving:Connect(PrestigeService.CleanupPlayer)

print("[Abyssara] PrestigeServer ready (GetPrestigeInfo / ArmResurface / RequestResurface wired up).")
