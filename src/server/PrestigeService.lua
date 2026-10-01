--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: PrestigeService
	Responsibility:
		Server logic of the prestige system "Resurface" (GDD sections 3 and
		6). Decides eligibility, computes the new permanent income
		multiplier from PrestigeConfig, calls PlayerDataService.ApplyAscend
		(which resets level/XP/coins/habitat/incubations/zone and keeps
		creatures, shards, codex, cosmetics, achievements, purchases),
		grants the one-time Abyssal Shards reward and the tier title, and
		then rebuilds everything the data reset leaves stale:
			- plot buildings (PlacementService.ClearPlayerBuildings destroys
			  the placed models on BOTH plots and clears the runtime
			  occupancy; the habitat data is already empty),
			- HUD (HUDServer listens to DataChanged "Ascend" and pushes level,
			  XP, coins, income, ascend count and multiplier),
			- daily quests that need a higher level (QuestService.
			  RefreshAfterPrestige swaps an open raid quest),
			- raid timer (ApplyAscend sets NextRaidAt; the result payload
			  carries it so RaidUIController can resync; raids stay paused
			  until level 8 again via RaidService.raidsAllowedFor),
			- the player's position (sent back to plot 1, since the zone
			  progress is reset).
		Finally ForceSave persists the new state.

		Two-step confirmation is enforced on the server too: ArmResurface
		(after the first confirm dialog) arms the player for
		PrestigeConfig.ARM_WINDOW_SECONDS, RequestResurface (second dialog)
		consumes it. All remotes are rate limited; the client never sends
		any value that the server would trust.

	Rojo mount point:
		src/server/PrestigeService.lua -> ServerScriptService.PrestigeService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlacementService = require(script.Parent:WaitForChild("PlacementService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local PrestigeConfig = require(ReplicatedStorage:WaitForChild("PrestigeConfig"))
local PrestigeRemotes = require(ReplicatedStorage:WaitForChild("PrestigeRemotes"))

export type BlockReason = "DataNotLoaded" | "NotEligible" | "InRaid" | "Cooldown" | "FinishedEggWaiting" | "Busy" | "NotArmed" | "RateLimited"

local PrestigeService = {}

local MIN_SECONDS_BETWEEN_CALLS = 0.5

local busyUsers: { [number]: boolean } = {}
local armedUntil: { [number]: number } = {} -- os.clock() deadline
local lastCallAt: { [number]: { [string]: number } } = {} -- os.clock() per bucket ("info" / "action")

-- // Checks ----------------------------------------------------------------------

--- true if the player reached the Hadal Depths in this run or is level 45+.
local function meetsRequirements(player: Player): boolean
	return PlayerDataService.GetDeepestZone(player) >= PrestigeConfig.REQUIRED_ZONE
		or PlayerDataService.GetLevel(player) >= PrestigeConfig.REQUIRED_LEVEL
end

local function hasFinishedEgg(player: Player): boolean
	local now = os.time()
	for _, incubation in ipairs(PlayerDataService.GetIncubations(player)) do
		if incubation.ReadyAt <= now then
			return true
		end
	end
	return false
end

local function isInRaid(player: Player): boolean
	-- Lazy require: RaidService is large and must not become a load-time
	-- dependency of this module (same principle as IdleIncomeService).
	local ok, status = pcall(function()
		local RaidService = require(script.Parent:WaitForChild("RaidService"))
		return RaidService.GetStatus(player)
	end)
	return ok and type(status) == "table" and status.InRaid == true
end

--- Why `player` can not resurface right now, or nil if they can.
local function getBlockReason(player: Player): BlockReason?
	if not PlayerDataService.IsDataLoaded(player) then
		return "DataNotLoaded"
	end
	if busyUsers[player.UserId] then
		return "Busy"
	end
	if not meetsRequirements(player) then
		return "NotEligible"
	end
	local lastAt = PlayerDataService.GetLastAscendAt(player)
	if lastAt and os.time() - lastAt < PrestigeConfig.COOLDOWN_SECONDS then
		return "Cooldown"
	end
	if isInRaid(player) then
		return "InRaid"
	end
	if hasFinishedEgg(player) then
		return "FinishedEggWaiting"
	end
	return nil
end

--- Simple per-player rate limit. Separate buckets so that panel refreshes
--- ("info") never block the confirm steps ("action").
function PrestigeService.CheckRate(player: Player, bucket: string): boolean
	local now = os.clock()
	local buckets = lastCallAt[player.UserId]
	if not buckets then
		buckets = {}
		lastCallAt[player.UserId] = buckets
	end
	local last = buckets[bucket]
	if last and now - last < MIN_SECONDS_BETWEEN_CALLS then
		return false
	end
	buckets[bucket] = now
	return true
end

-- // Public API --------------------------------------------------------------------

--- Data for the Prestige panel (see PrestigeRemotes.GetPrestigeInfo).
function PrestigeService.GetInfo(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Eligible = false, BlockReason = "DataNotLoaded" }
	end
	local count = PlayerDataService.GetAscendCount(player)
	local nextNumber = count + 1
	local nextTitle = PrestigeConfig.GetNextTitle(count)
	local reason = getBlockReason(player)
	return {
		AscendCount = count,
		IncomeMultiplier = PlayerDataService.GetIncomeMultiplier(player),
		NextIncomeMultiplier = PrestigeConfig.GetMultiplierForCount(nextNumber),
		NextBonusPercent = math.floor(PrestigeConfig.GetBonusForAscend(nextNumber) * 100 + 0.5),
		NextShardReward = PrestigeConfig.GetShardReward(nextNumber),
		NextTitle = nextTitle and nextTitle.Title or nil,
		NextTitleAtAscend = nextTitle and nextTitle.AtAscend or nil,
		Eligible = reason == nil,
		BlockReason = reason,
		Level = PlayerDataService.GetLevel(player),
		RequiredLevel = PrestigeConfig.REQUIRED_LEVEL,
		DeepestZone = PlayerDataService.GetDeepestZone(player),
		RequiredZone = PrestigeConfig.REQUIRED_ZONE,
	}
end

--- Step 1 of the two-step confirmation (after the first dialog).
function PrestigeService.ArmResurface(player: Player): { [string]: any }
	if not PrestigeService.CheckRate(player, "action") then
		return { Success = false, Reason = "RateLimited" }
	end
	local reason = getBlockReason(player)
	if reason then
		return { Success = false, Reason = reason }
	end
	armedUntil[player.UserId] = os.clock() + PrestigeConfig.ARM_WINDOW_SECONDS
	return { Success = true }
end

--- Runs one step and keeps going if it fails: the data reset has already
--- happened at that point, so the remaining cleanup must still run.
local function safeStep(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[PrestigeService] Cleanup step '%s' failed: %s"):format(label, tostring(err)))
	end
end

--- Step 2: performs the resurface. Always answers through
--- PrestigeRemotes.ResurfaceResult.
function PrestigeService.RequestResurface(player: Player)
	local function fail(reason: string)
		PrestigeRemotes.ResurfaceResult:FireClient(player, { Success = false, Reason = reason })
	end

	if not PrestigeService.CheckRate(player, "action") then
		fail("RateLimited")
		return
	end

	local userId = player.UserId
	local deadline = armedUntil[userId]
	armedUntil[userId] = nil -- consumed in every case
	if not deadline or os.clock() > deadline then
		fail("NotArmed")
		return
	end

	local reason = getBlockReason(player)
	if reason then
		fail(reason)
		return
	end

	-- From here until the end there is no yield except ForceSave, and
	-- busyUsers blocks a second resurface while the save is running.
	busyUsers[userId] = true

	local newCount = PlayerDataService.GetAscendCount(player) + 1
	local newMultiplier = PrestigeConfig.GetMultiplierForCount(newCount)

	if not PlayerDataService.ApplyAscend(player, newMultiplier) then
		busyUsers[userId] = nil
		fail("DataNotLoaded")
		return
	end

	-- Rewards (one-time per ascend number, derived from the new count).
	local shards = PrestigeConfig.GetShardReward(newCount)
	local title = PrestigeConfig.GetTitleForAscend(newCount)
	safeStep("shards", function()
		PlayerDataService.AddCurrency(player, "AbyssalShards", shards)
	end)
	if title then
		safeStep("title", function()
			PlayerDataService.AddUnlockedTitle(player, title)
		end)
	end

	-- Rebuild everything the data reset left stale.
	safeStep("buildings", function()
		PlacementService.ClearPlayerBuildings(player)
	end)
	safeStep("quests", function()
		local QuestService = require(script.Parent:WaitForChild("QuestService"))
		QuestService.RefreshAfterPrestige(player)
	end)
	safeStep("achievements", function()
		GameEvents.Fire(GameEvents.Events.Resurfaced, player, {
			AscendCount = newCount,
			IncomeMultiplier = newMultiplier,
		})
	end)
	safeStep("travel", function()
		-- Zone progress is reset: bring the player back to their first plot.
		local TravelService = require(script.Parent:WaitForChild("TravelService"))
		TravelService.RequestTravelToPlot(player, 1)
	end)

	PrestigeRemotes.ResurfaceResult:FireClient(player, {
		Success = true,
		AscendCount = newCount,
		IncomeMultiplier = newMultiplier,
		ShardsGranted = shards,
		TitleGranted = title,
		NextRaidAt = PlayerDataService.GetNextRaidAt(player),
	})

	-- Persist right away (a crash after a prestige must not roll it back).
	if Players:GetPlayerByUserId(userId) == player then
		local saved = PlayerDataService.ForceSave(player)
		if not saved then
			warn(("[PrestigeService] ForceSave after resurface failed for %s - the autosave will retry."):format(player.Name))
		end
	end

	busyUsers[userId] = nil
end

--- PlayerRemoving cleanup.
function PrestigeService.CleanupPlayer(player: Player)
	local userId = player.UserId
	busyUsers[userId] = nil
	armedUntil[userId] = nil
	lastCallAt[userId] = nil
end

return PrestigeService
