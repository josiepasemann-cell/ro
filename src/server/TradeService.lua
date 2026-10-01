--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: TradeService
	Responsibility:
		Secure 2-player creature trade (GDD section 7 "Trading system").
		Everything is server-authoritative: the client only sends intent
		(request / offer / ready / confirm / cancel), the server re-validates
		each step and is the only place that moves creatures
		(PlayerDataService.ExecuteCreatureTrade).

	Flow:
		1. Request   - player A asks nearby player B (dock ProximityPrompt or
		               the Trade menu entry). B accepts/declines (30 s timeout).
		2. Editing   - each side offers up to TradeConfig.MAX_OFFER creatures.
		               ANY change to an offer bumps `Revision` and clears both
		               Ready flags.
		3. Confirm   - both pressed Ready -> phase "Confirm". Confirm unlocks
		               after CONFIRM_COUNTDOWN_SECONDS so nobody can be
		               scammed by a last-second swap. Ready/Confirm carry the
		               revision the client saw; a stale revision is rejected,
		               so a swap right before the click can never be confirmed.
		4. Execute   - both confirmed -> everything is validated once more and
		               swapped atomically, both players are ForceSaved, buddy
		               and plot display are refreshed.

	Rules enforced here: both players loaded + in this server + level >=
	MIN_LEVEL + not in a raid, one trade/request per player, per-player
	cooldown (persisted TradeState.LastTradeAt), cancel on leave / distance /
	death. Creatures only - no Robux, no currencies.

	Locked creatures (see docs/trading.md for the reasoning):
		- Buddy: BuddyService stores the buddy by SPECIES (CreatureId), so a
		  creature is locked when the offer would leave the player without any
		  instance of a buddy species. Duplicates of that species can be traded.
		- Incubating: BreedingState only holds pre-rolled RESULTS, never an
		  inventory instance, so nothing in the inventory can be "incubating".
		- Displayed: CreatureDisplayService derives its display set from the
		  inventory (rarest 6 / codex favorites) and re-syncs after the trade.
		  Locking it would block the best creatures, so it is refreshed instead.
		- Abducted: moved out of CreatureInventory into RaidState by
		  PlayerDataService; checked defensively anyway.
		- Guardian loadout: PlayerDataService removes traded creatures from it.

	Rojo mount point:
		src/server/TradeService.lua -> ServerScriptService.TradeService
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local TradeConfig = require(ReplicatedStorage:WaitForChild("TradeConfig"))
local TradeRemotes = require(ReplicatedStorage:WaitForChild("TradeRemotes"))

type Phase = "Editing" | "Confirm"

type Trade = {
	Id: string,
	A: Player,
	B: Player,
	Offers: { [number]: { string } },
	Ready: { [number]: boolean },
	Confirmed: { [number]: boolean },
	Revision: number,
	Phase: Phase,
	ConfirmUnlockAt: number, -- os.clock(); 0 while editing
	LastActivity: number, -- os.clock()
	Closed: boolean,
}

type Request = {
	Id: string,
	From: Player,
	To: Player,
	Closed: boolean,
}

local TradeService = {}

-- // Runtime state ----------------------------------------------------------------

local tradeById: { [string]: Trade } = {}
local tradeByUser: { [number]: Trade } = {}
local requestById: { [string]: Request } = {}
local requestByFrom: { [number]: Request } = {}
local requestByTo: { [number]: Request } = {}
local lastRequestAt: { [number]: number } = {}
local declinedUntil: { [string]: number } = {} -- "fromUserId:toUserId" -> os.clock()
local lastCallAt: { [number]: { [string]: number } } = {}

local MAX_ID_LENGTH = 64

local TARGET_REASON: { [string]: string } = {
	NotLoaded = "TargetNotLoaded",
	LevelTooLow = "TargetLevelTooLow",
	Cooldown = "TargetCooldown",
	InRaid = "TargetInRaid",
}

-- // Small helpers ------------------------------------------------------------------

local function formatReason(reason: string, arg: number?): string
	local text = TradeConfig.REASON_TEXT[reason] or "The trade could not be completed."
	if string.find(text, "%d", 1, true) then
		text = string.format(text, arg or 0)
	end
	return text
end

local function notice(player: Player, text: string, kind: string?)
	if player.Parent then
		TradeRemotes.TradeNotice:FireClient(player, { Text = text, Kind = kind or "Warning" })
	end
end

local function noticeReason(player: Player, reason: string, arg: number?)
	notice(player, formatReason(reason, arg), "Warning")
end

--- true when the call should be dropped (same key called again within `interval`).
local function rateLimited(player: Player, key: string, interval: number): boolean
	local perPlayer = lastCallAt[player.UserId]
	if not perPlayer then
		perPlayer = {}
		lastCallAt[player.UserId] = perPlayer
	end
	local now = os.clock()
	local last = (perPlayer :: { [string]: number })[key]
	if last and now - last < interval then
		return true
	end
	(perPlayer :: { [string]: number })[key] = now
	return false
end

local function isStillInGame(player: Player): boolean
	return player.Parent == Players
end

local function isInRaid(player: Player): boolean
	local raidModule = script.Parent:FindFirstChild("RaidService")
	if not raidModule then
		return false
	end
	local ok, inRaid = pcall(function()
		local RaidService = require(raidModule :: ModuleScript) :: any
		return RaidService.GetStatus(player).InRaid
	end)
	return ok and inRaid == true
end

--- Returns the character root and whether the character is dead/missing.
local function getAliveRoot(player: Player): (BasePart?, boolean)
	local character = player.Character
	if not character then
		return nil, true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, true
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, true
	end
	return root, false
end

local function distanceBetween(a: Player, b: Player): number?
	local rootA = getAliveRoot(a)
	local rootB = getAliveRoot(b)
	if not rootA or not rootB then
		return nil
	end
	return (rootA.Position - rootB.Position).Magnitude
end

local function cooldownRemaining(player: Player): number
	local state = PlayerDataService.GetTradeState(player)
	if not state or state.LastTradeAt <= 0 then
		return 0
	end
	return math.max(0, state.LastTradeAt + TradeConfig.COOLDOWN_SECONDS - os.time())
end

--- Generic eligibility (data, level, cooldown, raid). Returns (reason, arg) or nil.
local function eligibilityReason(player: Player): (string?, number?)
	if not isStillInGame(player) or not PlayerDataService.IsDataLoaded(player) then
		return "NotLoaded", nil
	end
	if PlayerDataService.GetLevel(player) < TradeConfig.MIN_LEVEL then
		return "LevelTooLow", TradeConfig.MIN_LEVEL
	end
	local remaining = cooldownRemaining(player)
	if remaining > 0 then
		return "Cooldown", remaining
	end
	if isInRaid(player) then
		return "InRaid", nil
	end
	return nil, nil
end

local function isBusy(player: Player): boolean
	local userId = player.UserId
	return tradeByUser[userId] ~= nil or requestByFrom[userId] ~= nil or requestByTo[userId] ~= nil
end

-- // Creature locking ------------------------------------------------------------------

local function abductedIds(player: Player): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		set[abducted.InstanceId] = true
	end
	return set
end

local function ownedSpeciesCounts(player: Player): { [string]: number }
	local counts: { [string]: number } = {}
	for _, creature in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		counts[creature.CreatureId] = (counts[creature.CreatureId] or 0) + 1
	end
	return counts
end

local function buddySpecies(player: Player): { string }
	local list: { string } = {}
	local first = PlayerDataService.GetBuddyCreatureId(player)
	if first then
		table.insert(list, first)
	end
	local second = PlayerDataService.GetBuddyCreatureId2(player)
	if second and second ~= first then
		table.insert(list, second)
	end
	return list
end

--- Validates a whole offer list for `player`. Returns (ok, reasonKey).
local function validateOffer(player: Player, ids: any): (boolean, string?)
	if type(ids) ~= "table" then
		return false, "InvalidOffer"
	end
	if #ids > TradeConfig.MAX_OFFER then
		return false, "TooManyCreatures"
	end
	local seen: { [string]: boolean } = {}
	local abducted = abductedIds(player)
	local offeredPerSpecies: { [string]: number } = {}
	for _, id in ipairs(ids) do
		if type(id) ~= "string" or #id == 0 or #id > MAX_ID_LENGTH or seen[id] then
			return false, "InvalidOffer"
		end
		seen[id] = true
		local instance = PlayerDataService.GetCreatureInstance(player, id)
		if not instance then
			return false, "InvalidOffer"
		end
		if abducted[id] then
			return false, "CreatureLocked"
		end
		offeredPerSpecies[instance.CreatureId] = (offeredPerSpecies[instance.CreatureId] or 0) + 1
	end
	if next(offeredPerSpecies) ~= nil then
		local owned = ownedSpeciesCounts(player)
		for _, species in ipairs(buddySpecies(player)) do
			local offered = offeredPerSpecies[species]
			if offered and offered >= (owned[species] or 0) then
				return false, "BuddyLocked"
			end
		end
	end
	return true, nil
end

local function sameIdSet(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local set: { [string]: boolean } = {}
	for _, id in ipairs(a) do
		set[id] = true
	end
	for _, id in ipairs(b) do
		if not set[id] then
			return false
		end
	end
	return true
end

-- // Snapshots -------------------------------------------------------------------------

local function describeOffer(owner: Player, ids: { string }): { { [string]: any } }
	local list = {}
	for _, id in ipairs(ids) do
		local instance = PlayerDataService.GetCreatureInstance(owner, id)
		if instance then
			table.insert(list, { InstanceId = id, CreatureId = instance.CreatureId, Rarity = instance.Rarity })
		end
	end
	return list
end

local function otherPlayer(trade: Trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

local function buildSnapshot(trade: Trade, viewer: Player): { [string]: any }
	local partner = otherPlayer(trade, viewer)
	local unlockIn = 0
	if trade.Phase == "Confirm" then
		unlockIn = math.max(0, trade.ConfirmUnlockAt - os.clock())
	end
	return {
		TradeId = trade.Id,
		Revision = trade.Revision,
		Phase = trade.Phase,
		PartnerUserId = partner.UserId,
		PartnerName = partner.DisplayName,
		MyOffer = describeOffer(viewer, trade.Offers[viewer.UserId]),
		PartnerOffer = describeOffer(partner, trade.Offers[partner.UserId]),
		MyReady = trade.Ready[viewer.UserId] == true,
		PartnerReady = trade.Ready[partner.UserId] == true,
		MyConfirmed = trade.Confirmed[viewer.UserId] == true,
		PartnerConfirmed = trade.Confirmed[partner.UserId] == true,
		ConfirmUnlockIn = unlockIn,
		MaxOffer = TradeConfig.MAX_OFFER,
	}
end

local function pushState(trade: Trade)
	if trade.Closed then
		return
	end
	for _, player in ipairs({ trade.A, trade.B }) do
		if player.Parent then
			TradeRemotes.TradeState:FireClient(player, buildSnapshot(trade, player))
		end
	end
end

local function touch(trade: Trade)
	trade.LastActivity = os.clock()
end

-- // Monitor loop (distance / death / idle / offer drift) ----------------------------------

local monitorRunning = false
local monitorTick: () -> ()

local function ensureMonitor()
	if monitorRunning then
		return
	end
	monitorRunning = true
	task.spawn(function()
		while next(tradeById) ~= nil do
			task.wait(TradeConfig.MONITOR_INTERVAL_SECONDS)
			monitorTick()
		end
		monitorRunning = false
	end)
end

-- // Closing -----------------------------------------------------------------------------

local function removeTradeMaps(trade: Trade)
	tradeById[trade.Id] = nil
	if tradeByUser[trade.A.UserId] == trade then
		tradeByUser[trade.A.UserId] = nil
	end
	if tradeByUser[trade.B.UserId] == trade then
		tradeByUser[trade.B.UserId] = nil
	end
end

--- Closes `trade` (idempotent). `initiator` is the player who caused a plain
--- cancel; the other side then gets "CancelledByPartner" instead of "Cancelled".
local function closeTrade(trade: Trade, reason: string, completed: boolean, initiator: Player?)
	if trade.Closed then
		return
	end
	trade.Closed = true
	removeTradeMaps(trade)
	for _, player in ipairs({ trade.A, trade.B }) do
		if player.Parent then
			local shownReason = reason
			if reason == "Cancelled" and initiator and initiator ~= player then
				shownReason = "CancelledByPartner"
			end
			TradeRemotes.TradeClosed:FireClient(player, {
				TradeId = trade.Id,
				Completed = completed,
				Reason = shownReason,
				Text = formatReason(shownReason),
			})
		end
	end
end

local function closeRequest(request: Request, notifyTarget: boolean)
	if request.Closed then
		return
	end
	request.Closed = true
	requestById[request.Id] = nil
	if requestByFrom[request.From.UserId] == request then
		requestByFrom[request.From.UserId] = nil
	end
	if requestByTo[request.To.UserId] == request then
		requestByTo[request.To.UserId] = nil
	end
	if notifyTarget and request.To.Parent then
		TradeRemotes.TradeRequestClosed:FireClient(request.To, { RequestId = request.Id })
	end
end

-- // Execution ---------------------------------------------------------------------------------

local function refreshAfterTrade(player: Player)
	-- BuddyService/CreatureDisplayService look at the inventory; re-sync them
	-- (lazy FindFirstChild + pcall: a refresh problem must never undo a trade).
	for _, moduleName in ipairs({ "BuddyService", "CreatureDisplayService" }) do
		local moduleScript = script.Parent:FindFirstChild(moduleName)
		if moduleScript then
			task.defer(function()
				local ok, err = pcall(function()
					local service = require(moduleScript :: ModuleScript) :: any
					service.RefreshForPlayer(player)
				end)
				if not ok then
					warn(("[TradeService] %s.RefreshForPlayer failed: %s"):format(moduleName, tostring(err)))
				end
			end)
		end
	end
end

local function describeForLog(player: Player, ids: { string }): string
	local parts = {}
	for _, entry in ipairs(describeOffer(player, ids)) do
		table.insert(parts, ("%s(%s,%s)"):format(entry.CreatureId, entry.Rarity, string.sub(entry.InstanceId, 1, 8)))
	end
	return if #parts > 0 then table.concat(parts, ", ") else "nothing"
end

local function saveBoth(trade: Trade, a: Player, b: Player)
	task.spawn(function()
		local results: { [number]: boolean } = {}
		local pending = 2
		for index, player in ipairs({ a, b }) do
			task.spawn(function()
				local ok, saved = pcall(PlayerDataService.ForceSave, player)
				results[index] = ok and saved == true
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
		if results[1] and results[2] then
			print(("[Trade] %s saved for both players."):format(trade.Id))
		else
			warn(
				("[Trade] %s: ForceSave incomplete (A=%s, B=%s). The regular autosave/PlayerRemoving save will retry."):format(
					trade.Id,
					tostring(results[1]),
					tostring(results[2])
				)
			)
		end
	end)
end

--- Final validation + swap. No yields between the last check and
--- ExecuteCreatureTrade, so nothing can change in between.
local function executeTrade(trade: Trade)
	local a, b = trade.A, trade.B
	if trade.Closed then
		return
	end
	local idsA = trade.Offers[a.UserId]
	local idsB = trade.Offers[b.UserId]

	local failure: string? = nil
	if not isStillInGame(a) or not isStillInGame(b) then
		failure = "PartnerLeft"
	elseif not PlayerDataService.IsDataLoaded(a) or not PlayerDataService.IsDataLoaded(b) then
		failure = "TradeFailed"
	elseif
		PlayerDataService.GetLevel(a) < TradeConfig.MIN_LEVEL
		or PlayerDataService.GetLevel(b) < TradeConfig.MIN_LEVEL
	then
		failure = "TradeFailed"
	elseif isInRaid(a) or isInRaid(b) then
		failure = "InRaid"
	else
		local distance = distanceBetween(a, b)
		if not distance then
			failure = "Died"
		elseif distance > TradeConfig.MAX_DISTANCE_STUDS then
			failure = "MovedAway"
		end
	end
	if not failure then
		local okA = validateOffer(a, idsA)
		local okB = validateOffer(b, idsB)
		if not okA or not okB or (#idsA + #idsB) == 0 then
			failure = "OfferChanged"
		end
	end
	if failure then
		closeTrade(trade, failure, false, nil)
		return
	end

	local logA = describeForLog(a, idsA)
	local logB = describeForLog(b, idsB)
	local executed = PlayerDataService.ExecuteCreatureTrade(a, idsA, b, idsB)
	if not executed then
		warn(("[Trade] %s: ExecuteCreatureTrade refused (%s <-> %s)."):format(trade.Id, a.Name, b.Name))
		closeTrade(trade, "TradeFailed", false, nil)
		return
	end

	print(
		("[Trade] %s COMPLETED: %s (%d) gave [%s] <-> %s (%d) gave [%s]"):format(
			trade.Id,
			a.Name,
			a.UserId,
			logA,
			b.Name,
			b.UserId,
			logB
		)
	)

	closeTrade(trade, "Completed", true, nil)
	saveBoth(trade, a, b)
	refreshAfterTrade(a)
	refreshAfterTrade(b)

	-- Hook for achievements/quests/leaderboards (see GameEvents header comment).
	GameEvents.Fire("TradeCompleted", a, { TradeId = trade.Id, PartnerUserId = b.UserId, Gave = #idsA, Received = #idsB })
	GameEvents.Fire("TradeCompleted", b, { TradeId = trade.Id, PartnerUserId = a.UserId, Gave = #idsB, Received = #idsA })
end

-- // Trade creation ---------------------------------------------------------------------------

local function createTrade(a: Player, b: Player)
	local trade: Trade = {
		Id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		A = a,
		B = b,
		Offers = { [a.UserId] = {}, [b.UserId] = {} },
		Ready = {},
		Confirmed = {},
		Revision = 1,
		Phase = "Editing",
		ConfirmUnlockAt = 0,
		LastActivity = os.clock(),
		Closed = false,
	}
	tradeById[trade.Id] = trade
	tradeByUser[a.UserId] = trade
	tradeByUser[b.UserId] = trade
	print(("[Trade] %s opened: %s (%d) <-> %s (%d)"):format(trade.Id, a.Name, a.UserId, b.Name, b.UserId))
	pushState(trade)
	ensureMonitor()
end

monitorTick = function()
	local now = os.clock()
	for _, trade in pairs(table.clone(tradeById)) do
		if trade.Closed then
			continue
		end
		local rootA, deadA = getAliveRoot(trade.A)
		local rootB, deadB = getAliveRoot(trade.B)
		if deadA or deadB or not rootA or not rootB then
			closeTrade(trade, "Died", false, nil)
		elseif (rootA.Position - rootB.Position).Magnitude > TradeConfig.MAX_DISTANCE_STUDS then
			closeTrade(trade, "MovedAway", false, nil)
		elseif now - trade.LastActivity > TradeConfig.TRADE_IDLE_TIMEOUT_SECONDS then
			closeTrade(trade, "IdleTimeout", false, nil)
		else
			-- Offer drift: a creature vanished meanwhile (e.g. abducted by a raid).
			local drifted = false
			for _, player in ipairs({ trade.A, trade.B }) do
				local ids = trade.Offers[player.UserId]
				local ok = validateOffer(player, ids)
				if not ok then
					local kept = {}
					for _, id in ipairs(ids) do
						if validateOffer(player, { id }) then
							table.insert(kept, id)
						end
					end
					if validateOffer(player, kept) then
						trade.Offers[player.UserId] = kept
					else
						trade.Offers[player.UserId] = {}
					end
					drifted = true
				end
			end
			if drifted then
				trade.Revision += 1
				trade.Ready = {}
				trade.Confirmed = {}
				trade.Phase = "Editing"
				trade.ConfirmUnlockAt = 0
				touch(trade)
				notice(trade.A, formatReason("OfferChanged"), "Warning")
				notice(trade.B, formatReason("OfferChanged"), "Warning")
				pushState(trade)
			end
		end
	end
end

-- // Requests -------------------------------------------------------------------------------------

--- A asks B for a trade. `targetUserId` is untrusted.
function TradeService.RequestTrade(from: Player, targetUserId: any)
	if rateLimited(from, "RequestTrade", 0.5) then
		return
	end
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or not isStillInGame(target) then
		return noticeReason(from, "UnknownPlayer")
	end
	if target == from then
		return noticeReason(from, "Self")
	end

	local reason, arg = eligibilityReason(from)
	if reason then
		return noticeReason(from, reason, arg)
	end
	local targetReason = eligibilityReason(target)
	if targetReason then
		return noticeReason(from, TARGET_REASON[targetReason] or "TradeFailed", TradeConfig.MIN_LEVEL)
	end
	if isBusy(from) then
		return noticeReason(from, "Busy")
	end
	if isBusy(target) then
		return noticeReason(from, "TargetBusy")
	end

	local now = os.clock()
	if now - (lastRequestAt[from.UserId] or -math.huge) < TradeConfig.REQUEST_SEND_COOLDOWN_SECONDS then
		return noticeReason(from, "RequestCooldown")
	end
	if (declinedUntil[from.UserId .. ":" .. target.UserId] or 0) > now then
		return noticeReason(from, "DeclinedRecently")
	end

	local distance = distanceBetween(from, target)
	if not distance then
		return noticeReason(from, "NoCharacter")
	end
	if distance > TradeConfig.START_DISTANCE_STUDS then
		return noticeReason(from, "TooFar")
	end

	lastRequestAt[from.UserId] = now
	local request: Request = {
		Id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		From = from,
		To = target,
		Closed = false,
	}
	requestById[request.Id] = request
	requestByFrom[from.UserId] = request
	requestByTo[target.UserId] = request

	TradeRemotes.TradeRequestReceived:FireClient(target, {
		RequestId = request.Id,
		FromUserId = from.UserId,
		FromName = from.DisplayName,
		ExpiresIn = TradeConfig.REQUEST_TIMEOUT_SECONDS,
	})
	notice(from, ("Trade request sent to %s."):format(target.DisplayName), "Info")

	task.delay(TradeConfig.REQUEST_TIMEOUT_SECONDS, function()
		if request.Closed then
			return
		end
		closeRequest(request, true)
		declinedUntil[request.From.UserId .. ":" .. request.To.UserId] = os.clock()
			+ TradeConfig.REQUEST_DECLINE_COOLDOWN_SECONDS
		noticeReason(request.From, "RequestTimeout")
	end)
end

--- B answers a request. `requestId`/`accept` are untrusted.
function TradeService.RespondToRequest(player: Player, requestId: any, accept: any)
	if rateLimited(player, "Respond", 0.3) then
		return
	end
	if type(requestId) ~= "string" or type(accept) ~= "boolean" then
		return
	end
	local request = requestById[requestId]
	if not request or request.Closed or request.To ~= player then
		return noticeReason(player, "RequestExpired")
	end
	local from = request.From
	closeRequest(request, false)

	if not accept then
		declinedUntil[from.UserId .. ":" .. player.UserId] = os.clock() + TradeConfig.REQUEST_DECLINE_COOLDOWN_SECONDS
		if from.Parent then
			notice(from, ("%s declined your trade request."):format(player.DisplayName), "Warning")
		end
		return
	end

	if not isStillInGame(from) then
		return noticeReason(player, "PartnerLeft")
	end
	-- Re-validate: a lot can change during the 30 s the request was open.
	for _, participant in ipairs({ from, player }) do
		local reason, arg = eligibilityReason(participant)
		if reason then
			noticeReason(participant, reason, arg)
			local other = if participant == from then player else from
			if other ~= participant then
				notice(other, "The trade could not start.", "Warning")
			end
			return
		end
		if tradeByUser[participant.UserId] then
			return noticeReason(player, "Busy")
		end
	end
	local distance = distanceBetween(from, player)
	if not distance or distance > TradeConfig.START_DISTANCE_STUDS then
		noticeReason(player, "TooFar")
		noticeReason(from, "TooFar")
		return
	end
	createTrade(from, player)
end

-- // Trade actions (all untrusted input) ---------------------------------------------------------

local function getTradeFor(player: Player, tradeId: any): Trade?
	if type(tradeId) ~= "string" then
		return nil
	end
	local trade = tradeById[tradeId]
	if not trade or trade.Closed or (trade.A ~= player and trade.B ~= player) then
		return nil
	end
	return trade
end

local function resetAgreement(trade: Trade)
	trade.Ready = {}
	trade.Confirmed = {}
	trade.Phase = "Editing"
	trade.ConfirmUnlockAt = 0
end

function TradeService.SetOffer(player: Player, tradeId: any, ids: any)
	if rateLimited(player, "SetOffer", 0.15) then
		return
	end
	local trade = getTradeFor(player, tradeId)
	if not trade then
		return noticeReason(player, "NoTrade")
	end
	local ok, reason = validateOffer(player, ids)
	if not ok then
		noticeReason(player, reason or "InvalidOffer", TradeConfig.MAX_OFFER)
		pushState(trade) -- put the client back in sync with the real offer
		return
	end
	local clean: { string } = {}
	for _, id in ipairs(ids :: { string }) do
		table.insert(clean, id)
	end
	if sameIdSet(clean, trade.Offers[player.UserId]) then
		return
	end
	trade.Offers[player.UserId] = clean
	trade.Revision += 1
	resetAgreement(trade)
	touch(trade)
	pushState(trade)
end

function TradeService.SetReady(player: Player, tradeId: any, ready: any, revision: any)
	if rateLimited(player, "SetReady", 0.15) then
		return
	end
	local trade = getTradeFor(player, tradeId)
	if not trade then
		return noticeReason(player, "NoTrade")
	end
	if type(ready) ~= "boolean" or type(revision) ~= "number" then
		return
	end
	if revision ~= trade.Revision then
		noticeReason(player, "OfferChanged")
		pushState(trade)
		return
	end

	local userId = player.UserId
	if ready then
		if #trade.Offers[trade.A.UserId] + #trade.Offers[trade.B.UserId] == 0 then
			return notice(player, "Add at least one creature first.", "Warning")
		end
		trade.Ready[userId] = true
		if trade.Ready[trade.A.UserId] and trade.Ready[trade.B.UserId] then
			trade.Phase = "Confirm"
			trade.Confirmed = {}
			trade.ConfirmUnlockAt = os.clock() + TradeConfig.CONFIRM_COUNTDOWN_SECONDS
		end
	else
		-- Un-ready also sends everybody back from the confirm step.
		trade.Ready[userId] = false
		trade.Confirmed = {}
		trade.Phase = "Editing"
		trade.ConfirmUnlockAt = 0
	end
	touch(trade)
	pushState(trade)
end

function TradeService.Confirm(player: Player, tradeId: any, revision: any)
	if rateLimited(player, "Confirm", 0.3) then
		return
	end
	local trade = getTradeFor(player, tradeId)
	if not trade then
		return noticeReason(player, "NoTrade")
	end
	if type(revision) ~= "number" then
		return
	end
	if revision ~= trade.Revision then
		noticeReason(player, "OfferChanged")
		pushState(trade)
		return
	end
	if
		trade.Phase ~= "Confirm"
		or not trade.Ready[trade.A.UserId]
		or not trade.Ready[trade.B.UserId]
	then
		return noticeReason(player, "NotReady")
	end
	-- 0.2 s grace for network latency of the countdown the client saw.
	if os.clock() < trade.ConfirmUnlockAt - 0.2 then
		return noticeReason(player, "ConfirmLocked")
	end

	trade.Confirmed[player.UserId] = true
	touch(trade)
	if trade.Confirmed[trade.A.UserId] and trade.Confirmed[trade.B.UserId] then
		executeTrade(trade)
	else
		pushState(trade)
	end
end

--- Cancels an open trade, or (sender side) a pending request (`id` = "request"
--- or the request id). `id` is untrusted.
function TradeService.Cancel(player: Player, id: any)
	if rateLimited(player, "Cancel", 0.15) then
		return
	end
	if type(id) ~= "string" then
		return
	end
	if id == "request" then
		-- Sender cancels their own pending request (the client does not know its id).
		local outgoing = requestByFrom[player.UserId]
		if outgoing then
			closeRequest(outgoing, true)
		end
		return
	end
	local request = requestById[id]
	if request and request.From == player then
		closeRequest(request, true)
		return
	end
	local trade = getTradeFor(player, id)
	if trade then
		closeTrade(trade, "Cancelled", false, player)
	end
end

-- // Info for the picker UI --------------------------------------------------------------------------

function TradeService.GetInfo(player: Player): { [string]: any }?
	if rateLimited(player, "GetInfo", 0.5) then
		return nil
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return nil
	end

	local reason, arg = eligibilityReason(player)
	local info: { [string]: any } = {
		MinLevel = TradeConfig.MIN_LEVEL,
		MaxOffer = TradeConfig.MAX_OFFER,
		Level = PlayerDataService.GetLevel(player),
		CooldownRemaining = cooldownRemaining(player),
		BlockedText = if reason then formatReason(reason, arg) else nil,
		Players = {},
		Inventory = {},
	}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and PlayerDataService.IsDataLoaded(other) then
			local distance = distanceBetween(player, other)
			local nearby = distance ~= nil and distance <= TradeConfig.START_DISTANCE_STUDS
			local text: string? = nil
			local otherReason = eligibilityReason(other)
			if otherReason then
				text = formatReason(TARGET_REASON[otherReason] or "TradeFailed", TradeConfig.MIN_LEVEL)
			elseif isBusy(other) then
				text = formatReason("TargetBusy")
			elseif not nearby then
				text = formatReason("TooFar")
			end
			table.insert(info.Players, {
				UserId = other.UserId,
				Name = other.DisplayName,
				Level = PlayerDataService.GetLevel(other),
				Nearby = nearby,
				Available = text == nil,
				Text = text,
			})
		end
	end
	table.sort(info.Players, function(x, y)
		if x.Available ~= y.Available then
			return x.Available
		end
		return x.Name:lower() < y.Name:lower()
	end)

	local abducted = abductedIds(player)
	local owned = ownedSpeciesCounts(player)
	local buddyLocked: { [string]: boolean } = {}
	for _, species in ipairs(buddySpecies(player)) do
		if (owned[species] or 0) <= 1 then
			buddyLocked[species] = true
		end
	end
	local guardians: { [string]: boolean } = {}
	for _, id in ipairs(PlayerDataService.GetGuardianLoadout(player)) do
		guardians[id] = true
	end
	for _, creature in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		local lockedText: string? = nil
		if abducted[creature.InstanceId] then
			lockedText = formatReason("CreatureLocked")
		elseif buddyLocked[creature.CreatureId] then
			lockedText = formatReason("BuddyLocked")
		end
		table.insert(info.Inventory, {
			InstanceId = creature.InstanceId,
			CreatureId = creature.CreatureId,
			Rarity = creature.Rarity,
			Locked = lockedText,
			Guardian = guardians[creature.InstanceId] == true,
		})
	end
	return info
end

-- // Dock prompt (created at runtime, hub buildscript untouched) --------------------------------------

local function findHubModel(): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	local hubModel = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	if hubModel and hubModel:IsA("Model") then
		return hubModel
	end
	return nil
end

--- Opens the picker for `player` if they are allowed to trade at all.
function TradeService.OpenPickerFor(player: Player)
	if rateLimited(player, "OpenPicker", 1) then
		return
	end
	local reason, arg = eligibilityReason(player)
	if reason and reason ~= "Cooldown" then
		return noticeReason(player, reason, arg)
	end
	TradeRemotes.OpenTradePicker:FireClient(player)
end

local function attachDockPrompt(hubModel: Model): boolean
	local dock = hubModel:FindFirstChild(TradeConfig.DOCK_MODEL_NAME, true)
	if not dock then
		return false
	end
	-- Prefer the "InteractionPoint" attachment, then the PrimaryPart, then any part.
	local host: Instance? = dock:FindFirstChild("InteractionPoint", true)
	if not host and dock:IsA("Model") then
		host = dock.PrimaryPart
	end
	if not host then
		host = dock:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host and dock:IsA("BasePart") then
		host = dock
	end
	if not host then
		return false
	end
	if host:FindFirstChild(TradeConfig.DOCK_PROMPT_NAME) then
		return true
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TradeConfig.DOCK_PROMPT_NAME
	prompt.ActionText = "Trade"
	prompt.ObjectText = "Trade Dock"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	prompt.Triggered:Connect(function(player: Player)
		TradeService.OpenPickerFor(player)
	end)
	return true
end

local function runDockPromptSetup()
	local waited = 0
	local hubModel: Model? = nil
	while waited < 30 do
		hubModel = findHubModel()
		if hubModel then
			break
		end
		task.wait(2)
		waited += 2
	end
	if not hubModel then
		warn(
			"[TradeService] Workspace.Assets.Hub.TidalMarketHub not found - dock prompt skipped. "
				.. "Trading is still available from the Trade menu entry."
		)
		return
	end
	if attachDockPrompt(hubModel) then
		print("[Abyssara] TradeService: trade dock prompt set up at the hub.")
	else
		warn(
			("[TradeService] '%s' not found in the hub - dock prompt skipped. "
				.. "Trading is still available from the Trade menu entry."):format(TradeConfig.DOCK_MODEL_NAME)
		)
	end
end

-- // Player leaving ----------------------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	local trade = tradeByUser[userId]
	if trade then
		closeTrade(trade, "PartnerLeft", false, player)
	end
	local outgoing = requestByFrom[userId]
	if outgoing then
		closeRequest(outgoing, true)
	end
	local incoming = requestByTo[userId]
	if incoming then
		closeRequest(incoming, false)
		noticeReason(incoming.From, "PartnerLeft")
	end
	lastRequestAt[userId] = nil
	lastCallAt[userId] = nil
	for key in pairs(declinedUntil) do
		local fromId, toId = string.match(key, "^(%d+):(%d+)$")
		if tonumber(fromId) == userId or tonumber(toId) == userId then
			declinedUntil[key] = nil
		end
	end
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

task.spawn(runDockPromptSetup)

return TradeService
