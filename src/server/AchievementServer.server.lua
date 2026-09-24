--[[
	Abyssara – Deep Tide Tycoon
	Script: AchievementServer (Script, not a ModuleScript)
	Responsibility:
		Thin bootstrap/wiring for the Achievements system: connects the
		remote channels from AchievementRemotes to the pure logic in
		AchievementService. Contains NO achievement logic itself (identical
		pattern to QuestServer.server.lua/BreedingServer.server.lua).

	Rojo mount point:
		src/server/AchievementServer.server.lua -> ServerScriptService.AchievementServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementService = require(script.Parent:WaitForChild("AchievementService"))
local AchievementRemotes = require(ReplicatedStorage:WaitForChild("AchievementRemotes"))

AchievementRemotes.GetState.OnServerInvoke = function(player: Player)
	return AchievementService.GetState(player)
end

AchievementRemotes.RequestClaimReward.OnServerEvent:Connect(function(player: Player, achievementId)
	local result = AchievementService.RequestClaim(player, achievementId)
	AchievementRemotes.ClaimRewardResult:FireClient(player, result)
end)

AchievementRemotes.RequestEquipTitle.OnServerEvent:Connect(function(player: Player, title)
	local result = AchievementService.RequestEquipTitle(player, title)
	AchievementRemotes.EquipTitleResult:FireClient(player, result)
end)

print("[Abyssara] AchievementServer ready (GetState / RequestClaimReward / RequestEquipTitle wired).")
