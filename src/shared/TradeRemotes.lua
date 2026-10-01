--[[
	Abyssara – Deep Tide Tycoon
	Module: TradeRemotes
	Responsibility:
		Single place for all client<->server channels of the creature trade
		(see TradeService, docs/trading.md). Same bootstrap pattern as
		TravelRemotes/BuddyRemotes. The server validates EVERYTHING again;
		the client only sends intent.

	Rojo mount point:
		src/shared/TradeRemotes.lua -> ReplicatedStorage.TradeRemotes

	Client -> Server (RemoteEvent):
		RequestTrade (targetUserId: number)
		RespondTradeRequest (requestId: string, accept: boolean)
		SetTradeOffer (tradeId: string, instanceIds: { string })   -- replaces the whole offer
		SetTradeReady (tradeId: string, ready: boolean, revision: number)
		ConfirmTrade (tradeId: string, revision: number)
		CancelTrade (tradeId: string)

	Client -> Server (RemoteFunction):
		GetTradeInfo () -> { MinLevel, MaxOffer, CooldownRemaining, Players = {...}, Inventory = {...} }

	Server -> Client (RemoteEvent):
		OpenTradePicker ()                          -- dock prompt: open the player picker
		TradeRequestReceived { RequestId, FromUserId, FromName, ExpiresIn }
		TradeRequestClosed { RequestId }            -- expired/cancelled/answered
		TradeState { snapshot }                     -- full trade snapshot for the receiving player
		TradeClosed { TradeId, Completed: boolean, Reason: string?, Text: string }
		TradeNotice { Text: string, Kind: "Info" | "Warning" | "Success" }
]]

local RunService = game:GetService("RunService")

local TradeRemotes = {}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local EVENTS = {
	"RequestTrade",
	"RespondTradeRequest",
	"SetTradeOffer",
	"SetTradeReady",
	"ConfirmTrade",
	"CancelTrade",
	"OpenTradePicker",
	"TradeRequestReceived",
	"TradeRequestClosed",
	"TradeState",
	"TradeClosed",
	"TradeNotice",
}

if RunService:IsServer() then
	for _, name in ipairs(EVENTS) do
		TradeRemotes[name] = getOrCreate(script, "RemoteEvent", name)
	end
	TradeRemotes.GetTradeInfo = getOrCreate(script, "RemoteFunction", "GetTradeInfo")
else
	for _, name in ipairs(EVENTS) do
		TradeRemotes[name] = script:WaitForChild(name)
	end
	TradeRemotes.GetTradeInfo = script:WaitForChild("GetTradeInfo")
end

return TradeRemotes
