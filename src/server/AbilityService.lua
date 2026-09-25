--[[
	Abyssara – Deep Tide Tycoon
	Module: AbilityService
	Responsibility:
		Server-authoritative core logic for the 5 purchasable abilities/boosts
		added by this task (see docs/abilities.md for the full design +
		rationale of every decision below):

			1. Spore Shower   (Developer Product, 9 Robux)  - GrantSporeShower
			2. Tidal Surge    (Developer Product, 49 Robux) - ExtendTidalSurge,
			   GetIdleIncomeMultiplier, GetBreedingSpeedMultiplier
			3. Depth Charge   (Developer Product, 29 Robux) - GrantDepthCharges,
			   RequestDepthCharge
			4. Spore Magnet   (Gamepass, 199 Robux)         - runSporeMagnetTick
			5. Extra Buddy Slot (Gamepass, 149 Robux)       - see BuddyService
			   instead (that gamepass only gates an EXISTING system, it has no
			   dedicated logic here - see docs/abilities.md).

		Pure logic, no RemoteEvent wiring itself - that's AbilityServer.
		server.lua (identical thin-bootstrap pattern as RaidService/
		RaidServer.server.lua). The 3 Developer Product effects are called
		EXCLUSIVELY from MonetizationService.applyDevProductEffect AFTER a
		verified Robux purchase (idempotency/no-double-grant is entirely
		MonetizationService's job, see its ProcessReceipt Kopfkommentar - this
		module just applies the effect ONCE per call and returns
		(success, retryable), identical contract to BreedingService.
		RequestInstantComplete/RaidService.RequestRescueWithToken).

	Concurrency note (see task instructions): this is a NEW file, deliberately
	created instead of adding ability logic directly into RaidService/
	IdleIncomeService/BreedingService/PickupSpawner/GachaService, which other
	review agents are editing concurrently. Those files only got tiny,
	targeted additions (one new exported function each, or a single
	multiplier-lookup call at the exact point of use) - see
	PickupSpawner.SpawnBonusSpores, RaidService.ApplyDepthChargeDamage, and
	the single-line hooks in IdleIncomeService.computeIncomePerMinute /
	BreedingService.RequestStartBreeding.

	No load-time require cycles: MonetizationService calls INTO this module
	(Developer Product effects) AND this module calls INTO MonetizationService
	(gamepass ownership checks for Spore Magnet/Extra Buddy Slot) - a
	classic mutual dependency. Both sides therefore use a LAZY require
	(inside function bodies, not at module scope) for the other, identical
	principle to every other MonetizationService consumer in this project
	(see BreedingService.RequestStartBreeding's Kopfkommentar for the full
	explanation). RaidService/PickupSpawner/PlotRegistry are lazy-required
	here for the same reason (keeps this module safely requirable from
	anywhere without caring about require order).

	Rojo mount point:
		src/server/AbilityService.lua -> ServerScriptService.AbilityService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local AbilityConfig = require(ReplicatedStorage:WaitForChild("AbilityConfig"))
local AbilityRemotes = require(ReplicatedStorage:WaitForChild("AbilityRemotes"))
local HeldItemConfig = require(ReplicatedStorage:WaitForChild("HeldItemConfig"))

local AbilityService = {}

-- // Laufzeit-Zustand (In-Memory, NICHT persistent) -----------------------------

-- Depth Charge cooldown: intentionally session-only (os.clock(), NOT
-- persisted) - a raid + its Depth Charges only ever matter within a single
-- play session anyway (RaidService.CleanupPlayer already neutrally aborts an
-- active raid on disconnect), so a 10s cooldown surviving a rejoin would be
-- meaningless busywork to persist correctly across server changes.
local depthChargeCooldownByUserId: { [number]: number } = {}

-- // Kleine Hilfsfunktion -------------------------------------------------------

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- // Tidal Surge (Developer Product) --------------------------------------------

--- Extends (or starts) `player`'s Tidal Surge by AbilityConfig.TidalSurge.
--- DurationSeconds, capped so the TOTAL remaining time never exceeds
--- MaxRemainingSeconds (Auftrag: "cap total remaining at 3 hours"). Persists
--- an ABSOLUTE os.time() end timestamp (survives rejoin/server changes, see
--- PlayerDataService.SetTidalSurgeActiveUntil) - offline progress therefore
--- naturally only counts the portion of the offline window before this
--- timestamp, since every consumer (IdleIncomeService/BreedingService)
--- re-checks "is it still active RIGHT NOW" at the moment it actually grants
--- income/starts a breed, never at purchase time.
---
--- Called EXCLUSIVELY from MonetizationService.applyDevProductEffect after a
--- verified purchase. Returns (success, retryable) - identical contract to
--- every other Developer Product effect handler in this project.
function AbilityService.ExtendTidalSurge(player: Player): (boolean, boolean)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, true
	end

	local now = os.time()
	local currentEnd = PlayerDataService.GetTidalSurgeActiveUntil(player)
	local remainingNow = 0
	if type(currentEnd) == "number" and currentEnd > now then
		remainingNow = currentEnd - now
	end

	local newRemaining = math.min(remainingNow + AbilityConfig.TidalSurge.DurationSeconds, AbilityConfig.TidalSurge.MaxRemainingSeconds)
	local ok = PlayerDataService.SetTidalSurgeActiveUntil(player, now + newRemaining)
	if not ok then
		return false, true
	end

	AbilityService.PushStatus(player)
	return true, true
end

--- true if `player`'s Tidal Surge is currently active (persisted absolute
--- end timestamp is in the future). Safe to call for a player whose data
--- isn't loaded (returns false).
function AbilityService.IsTidalSurgeActive(player: Player): boolean
	local endAt = PlayerDataService.GetTidalSurgeActiveUntil(player)
	return type(endAt) == "number" and endAt > os.time()
end

--- Idle-income multiplier hook (Auftrag: "Hook multipliers at the point of
--- use with a single call into AbilityService"). Called from
--- IdleIncomeService.computeIncomePerMinute - see the single-line hook
--- there. Returns 1 (neutral) if inactive/not loaded.
function AbilityService.GetIdleIncomeMultiplier(player: Player): number
	if AbilityService.IsTidalSurgeActive(player) then
		return AbilityConfig.TidalSurge.IncomeMultiplier
	end
	return 1
end

--- Breeding-speed multiplier hook, same principle as GetIdleIncomeMultiplier
--- above - called from BreedingService.RequestStartBreeding. Multiplies
--- (like the existing VIP Diver gamepass bonus) rather than replaces, so it
--- stacks fairly with VIP Diver instead of overriding it.
function AbilityService.GetBreedingSpeedMultiplier(player: Player): number
	if AbilityService.IsTidalSurgeActive(player) then
		return AbilityConfig.TidalSurge.BreedingSpeedMultiplier
	end
	return 1
end

-- // Depth Charge (Developer Product + in-raid usage) ---------------------------

--- Grants AbilityConfig.DepthCharge.ChargesPerPurchase persisted charges.
--- Called EXCLUSIVELY from MonetizationService.applyDevProductEffect after a
--- verified purchase. Returns (success, retryable).
function AbilityService.GrantDepthCharges(player: Player): (boolean, boolean)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, true
	end

	local ok = PlayerDataService.AddDepthCharges(player, AbilityConfig.DepthCharge.ChargesPerPurchase)
	if not ok then
		return false, true
	end

	AbilityService.PushStatus(player)
	return true, true
end

export type DepthChargeFailureReason = "DataNotLoaded" | "NoCharges" | "OnCooldown" | "NoActiveRaid"

--- Validates + fires ONE Depth Charge for `player` against their OWN active
--- raid (server-validated: charge count > 0, 10s cooldown elapsed, AND an
--- actual active raid currently running on the player's plot - see
--- RaidService.ApplyDepthChargeDamage, which is the sole authority on
--- "is there really a raid here"). Consumes exactly one persisted charge on
--- success. Called from AbilityServer.server.lua in direct response to
--- AbilityRemotes.RequestDepthCharge - the client's request is pure intent,
--- every check below re-validates against server state.
function AbilityService.RequestDepthCharge(player: Player): (boolean, DepthChargeFailureReason?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded"
	end

	if PlayerDataService.GetDepthChargeCount(player) <= 0 then
		return false, "NoCharges"
	end

	local now = os.clock()
	local lastFired = depthChargeCooldownByUserId[player.UserId] or -math.huge
	if now - lastFired < AbilityConfig.DepthCharge.CooldownSeconds then
		return false, "OnCooldown"
	end

	-- Lazy require (see Kopfkommentar) - avoids a load-time cycle with
	-- RaidService, which itself never needs to know about AbilityService.
	local RaidService = require(script.Parent:WaitForChild("RaidService"))
	local ok, reason, centerPosition, enemiesHit =
		RaidService.ApplyDepthChargeDamage(player, AbilityConfig.DepthCharge.NonBossDamage, AbilityConfig.DepthCharge.BossDamageFractionOfMaxHP)

	if not ok then
		return false, (reason :: DepthChargeFailureReason?) or "NoActiveRaid"
	end

	depthChargeCooldownByUserId[player.UserId] = now
	PlayerDataService.AddDepthCharges(player, -1)

	GameEvents.Fire(GameEvents.Events.DepthChargeUsed, player, { EnemiesHit = enemiesHit or 0 })

	AbilityRemotes.DepthChargeFired:FireClient(player, {
		Success = true,
		CenterPosition = centerPosition,
		EnemiesHit = enemiesHit,
	})
	AbilityService.PushStatus(player)

	return true, nil
end

-- // Spore Shower (Developer Product) -------------------------------------------

--- Instantly spawns AbilityConfig.SporeShower.SporeCount Glow Spores
--- scattered on `player`'s OWN plot (see PickupSpawner.SpawnBonusSpores for
--- the exact "reachable, not inside buildings" scatter geometry + why it
--- deliberately bypasses the normal per-plot cap). Sends a toast: the exact
--- Auftrag-mandated wording "Your Spore Shower landed on your plot!" if the
--- player currently isn't standing on their own plot, otherwise a plain
--- success toast. Called EXCLUSIVELY from MonetizationService.
--- applyDevProductEffect after a verified purchase. Returns
--- (success, retryable) - a missing plot/template (buildscript never run in
--- Studio) is treated as NON-retryable (retrying forever would never
--- succeed), so MonetizationService's Fallback-Kompensation kicks in.
function AbilityService.GrantSporeShower(player: Player): (boolean, boolean)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, true
	end

	-- Lazy requires (see Kopfkommentar) - PickupSpawner/PlotRegistry never
	-- need to know about AbilityService.
	local PickupSpawner = require(script.Parent:WaitForChild("PickupSpawner"))
	local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))

	local spawnedCount = PickupSpawner.SpawnBonusSpores(player, AbilityConfig.SporeShower.SporeCount)
	if spawnedCount <= 0 then
		return false, false
	end

	local onOwnPlot = false
	local plot = PlotRegistry.GetPlot(player)
	if plot and plot.PrimaryPart then
		local root = getHumanoidRootPart(player)
		if root then
			onOwnPlot = (root.Position - plot.PrimaryPart.Position).Magnitude <= AbilityConfig.SporeShower.OnPlotDistanceStuds
		end
	end

	local message = if onOwnPlot
		then ("Spore Shower! %d Glow Spores are waiting for you."):format(spawnedCount)
		else "Your Spore Shower landed on your plot!"

	AbilityRemotes.SporeShowerToast:FireClient(player, { Message = message })
	return true, true
end

-- // Spore Magnet (Gamepass) -----------------------------------------------------
-- Chosen delivery behavior (Auftrag: "pick a consistent behavior [...] and
-- document it" - see docs/abilities.md for the full write-up): auto-deliver
-- bonus Tide Coins DIRECTLY, exactly as if the spore had been manually
-- picked up AND deposited at a Glow Buoy Station (see PickupSpawner.
-- onDepositTriggered) - no intermediate "held in hand" step. Justification:
-- HeldItemService only supports ONE held item at a time; a magnet that
-- "collects" spores into the player's hand one-by-one while walking past
-- several at once would either silently drop earlier ones or need entirely
-- new multi-item-carry plumbing, neither of which matches "convenience
-- auto-collect" - direct currency delivery is the simplest behavior that is
-- unambiguously identical in OUTCOME to the manual pickup+deposit loop.
-- Only affects plain Glow Spores/Toxic Spores (both spawned under the name
-- "GlowSporePickup" by PickupSpawner, see spawnGlowSporeForPlayer) - Frozen
-- Spores are deliberately EXCLUDED (they require a 3s hold "thaw" puzzle
-- interaction, which a passive magnet shouldn't skip) and Sunken Chests
-- aren't spores at all.

local SPORE_MAGNET_PICKUP_NAME = "GlowSporePickup"

local function collectSporeForMagnet(player: Player, model: Model)
	local multiplier = model:GetAttribute("TideCoinValueMultiplier")
	if type(multiplier) ~= "number" or multiplier <= 0 then
		multiplier = 1
	end
	local reward = math.floor(HeldItemConfig.Deposit.TideCoinsReward * multiplier + 0.5)

	model:Destroy()

	local ok = PlayerDataService.AddCurrency(player, "TideCoins", reward)
	if ok then
		-- Identical GameEvents-Einhängepunkt as the manual deposit path (see
		-- PickupSpawner.onDepositTriggered) - Quests/LiveEvent-Bilanz count
		-- a magnet-collected spore exactly like a manually delivered one.
		GameEvents.Fire(GameEvents.Events.SporeDelivered, player, { Amount = 1 })
	end
end

local function tickSporeMagnetForPlayer(player: Player)
	local root = getHumanoidRootPart(player)
	if not root then
		return
	end

	local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
	local plot = PlotRegistry.GetPlot(player)
	if not plot then
		return
	end
	local pickupsFolder = plot:FindFirstChild("Pickups")
	if not pickupsFolder then
		return
	end

	for _, child in ipairs(pickupsFolder:GetChildren()) do
		if child:IsA("Model") and child.Name == SPORE_MAGNET_PICKUP_NAME and child:GetAttribute("OwnerUserId") == player.UserId then
			local anchor = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			if anchor then
				local distance = (root.Position - anchor.Position).Magnitude
				if distance <= AbilityConfig.SporeMagnet.RadiusStuds then
					collectSporeForMagnet(player, child)
				end
			end
		end
	end
end

--- EIN gemeinsamer Loop für ALLE Online-Spore-Magnet-Besitzer (Performance-
--- Prinzip, identisch zu RaidService.runRaidTickLoop/IdleIncomeService.
--- runOnlineTickLoop - KEIN Loop pro Spieler).
local function runSporeMagnetTickLoop()
	while true do
		task.wait(AbilityConfig.SporeMagnet.TickIntervalSeconds)

		local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
		for _, player in ipairs(Players:GetPlayers()) do
			if PlayerDataService.IsDataLoaded(player) and MonetizationService.PlayerOwnsGamepass(player, "SporeMagnet") then
				task.spawn(tickSporeMagnetForPlayer, player)
			end
		end
	end
end

-- // HUD-Status (AbilityRemotes.GetAbilityStatus/AbilityStatusChanged) ---------

--- Builds the full ability status snapshot for `player` - see
--- AbilityRemotes Kopfkommentar for the exact payload shape.
function AbilityService.GetStatus(player: Player): { [string]: any }
	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	local RaidService = require(script.Parent:WaitForChild("RaidService"))

	local raidStatus = RaidService.GetStatus(player)

	return {
		TidalSurgeActiveUntil = if AbilityService.IsTidalSurgeActive(player) then PlayerDataService.GetTidalSurgeActiveUntil(player) else nil,
		DepthChargeCount = PlayerDataService.GetDepthChargeCount(player),
		InRaidOnOwnPlot = raidStatus.InRaid == true,
		HasSporeMagnet = MonetizationService.PlayerOwnsGamepass(player, "SporeMagnet"),
		HasExtraBuddySlot = MonetizationService.PlayerOwnsGamepass(player, "ExtraBuddySlot"),
	}
end

--- Pushes a fresh full status snapshot to `player` (see AbilityRemotes.
--- AbilityStatusChanged) - called after every server-side change relevant
--- to the ability HUD.
function AbilityService.PushStatus(player: Player)
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end
	AbilityRemotes.AbilityStatusChanged:FireClient(player, AbilityService.GetStatus(player))
end

-- // Aufräumen bei Verlassen (Auftrag: "cleanup on leave") ----------------------

function AbilityService.CleanupPlayer(player: Player)
	depthChargeCooldownByUserId[player.UserId] = nil
end

local function onPlayerRemoving(player: Player)
	AbilityService.CleanupPlayer(player)
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

-- // Bootstrap --------------------------------------------------------------------

task.spawn(runSporeMagnetTickLoop)

return AbilityService
