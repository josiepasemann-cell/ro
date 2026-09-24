--[[
	Abyssara – Deep Tide Tycoon
	Skript: DailyRewardServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünnes Bootstrap/Verdrahtung der Tages-Login-Belohnung: verbindet die
		Remote-Kanäle aus QuestRemotes (Daily-Reward-Kanäle sind dort mit den
		Quest-Kanälen gebündelt, siehe QuestRemotes-Kopfkommentar) mit der
		reinen Logik in DailyRewardService.

	Rojo-Einhängepunkt:
		src/server/DailyRewardServer.server.lua -> ServerScriptService.DailyRewardServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardService = require(script.Parent:WaitForChild("DailyRewardService"))
local QuestRemotes = require(ReplicatedStorage:WaitForChild("QuestRemotes"))

QuestRemotes.GetDailyRewardState.OnServerInvoke = function(player: Player)
	return DailyRewardService.GetState(player)
end

QuestRemotes.RequestClaimDailyReward.OnServerEvent:Connect(function(player: Player)
	local result = DailyRewardService.RequestClaim(player)
	QuestRemotes.DailyRewardClaimed:FireClient(player, result)
end)

print("[Abyssara] DailyRewardServer ready (GetDailyRewardState / RequestClaimDailyReward wired up).")
