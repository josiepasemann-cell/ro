--[[
	Abyssara – Deep Tide Tycoon
	Skript: LiveEventServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünnes Bootstrap/Verdrahtung des rotierenden Live-Event-Systems:
		verbindet die Remote-Kanäle aus LiveEventRemotes mit der reinen
		Logik in LiveEventService. Enthält selbst KEINE Event-Logik
		(identisches Muster zu QuestServer/BreedingServer/RaidServer
		.server.lua). Das `require(LiveEventService)` hier stößt außerdem
		den einmaligen Modul-Bootstrap dort an (Lighting-Baseline-Anwendung,
		Slot-Scheduler-Loop, GameEvents-Abonnements) - identisches Prinzip
		zu PlayerDataService/IdleIncomeService.

	Rojo-Einhängepunkt:
		src/server/LiveEventServer.server.lua -> ServerScriptService.LiveEventServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))
local LiveEventRemotes = require(ReplicatedStorage:WaitForChild("LiveEventRemotes"))

LiveEventRemotes.GetEventState.OnServerInvoke = function(player: Player)
	return LiveEventService.GetState(player)
end

LiveEventRemotes.RequestPurchaseShopItem.OnServerEvent:Connect(function(player: Player, itemId)
	local result = LiveEventService.RequestPurchaseShopItem(player, itemId)
	LiveEventRemotes.ShopPurchaseResult:FireClient(player, result)
end)

LiveEventRemotes.RequestClaimEventQuest.OnServerEvent:Connect(function(player: Player)
	local result = LiveEventService.RequestClaimEventQuest(player)
	LiveEventRemotes.ClaimEventQuestResult:FireClient(player, result)
end)

print("[Abyssara] LiveEventServer bereit (GetEventState / RequestPurchaseShopItem / RequestClaimEventQuest verdrahtet).")
