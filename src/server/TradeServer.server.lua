--[[
	Abyssara – Deep Tide Tycoon
	Script: TradeServer (Script, not a ModuleScript)
	Responsibility:
		Thin bootstrap for the creature trade: wires the TradeRemotes
		channels to TradeService. No trade logic lives here. The dock
		ProximityPrompt is created by TradeService itself on require().

	Rojo mount point:
		src/server/TradeServer.server.lua -> ServerScriptService.TradeServer
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeService = require(script.Parent:WaitForChild("TradeService"))
local TradeRemotes = require(ReplicatedStorage:WaitForChild("TradeRemotes"))

TradeRemotes.RequestTrade.OnServerEvent:Connect(function(player: Player, targetUserId)
	TradeService.RequestTrade(player, targetUserId)
end)

TradeRemotes.RespondTradeRequest.OnServerEvent:Connect(function(player: Player, requestId, accept)
	TradeService.RespondToRequest(player, requestId, accept)
end)

TradeRemotes.SetTradeOffer.OnServerEvent:Connect(function(player: Player, tradeId, instanceIds)
	TradeService.SetOffer(player, tradeId, instanceIds)
end)

TradeRemotes.SetTradeReady.OnServerEvent:Connect(function(player: Player, tradeId, ready, revision)
	TradeService.SetReady(player, tradeId, ready, revision)
end)

TradeRemotes.ConfirmTrade.OnServerEvent:Connect(function(player: Player, tradeId, revision)
	TradeService.Confirm(player, tradeId, revision)
end)

TradeRemotes.CancelTrade.OnServerEvent:Connect(function(player: Player, id)
	TradeService.Cancel(player, id)
end)

TradeRemotes.GetTradeInfo.OnServerInvoke = function(player: Player)
	return TradeService.GetInfo(player)
end

print("[Abyssara] TradeServer ready (creature trade remotes wired up).")
