--[[
	Abyssara – Deep Tide Tycoon
	Skript: QuestServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünnes Bootstrap/Verdrahtung des Tages-Quest-Systems: verbindet die
		Remote-Kanäle aus QuestRemotes mit der reinen Logik in QuestService.
		Enthält selbst KEINE Quest-Logik (identisches Muster zu
		BreedingService/BreedingServer.server.lua).

	Rojo-Einhängepunkt:
		src/server/QuestServer.server.lua -> ServerScriptService.QuestServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestService = require(script.Parent:WaitForChild("QuestService"))
local QuestRemotes = require(ReplicatedStorage:WaitForChild("QuestRemotes"))

QuestRemotes.GetQuestState.OnServerInvoke = function(player: Player)
	return QuestService.GetState(player)
end

QuestRemotes.RequestClaimQuestReward.OnServerEvent:Connect(function(player: Player, templateId)
	local result = QuestService.RequestClaim(player, templateId)
	QuestRemotes.ClaimQuestRewardResult:FireClient(player, result)
end)

print("[Abyssara] QuestServer bereit (GetQuestState / RequestClaimQuestReward verdrahtet).")
