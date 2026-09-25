--[[
	Abyssara – Deep Tide Tycoon
	Module: AbilityConfig
	Responsibility:
		Single source of truth for the BALANCING constants of the 5
		purchasable abilities/boosts added by this task (Spore Shower/Tidal
		Surge/Depth Charge Developer Products + Spore Magnet/Extra Buddy Slot
		Gamepasses). Pure data + a few tiny pure helpers, NO purchase/effect
		logic itself (that lives in AbilityService/MonetizationService/
		BuddyService) - identical split principle to ShopConfig/RaidConfig/
		BreedingConfig.

		Deliberately a SEPARATE module from ShopConfig: ShopConfig only holds
		what the shop UI/catalog needs (price, name, description, id) - the
		numbers below are pure gameplay balancing that only AbilityService
		(and a few lazy-required consumers, e.g. IdleIncomeService/
		BreedingService/RaidService/PickupSpawner-adjacent code) ever read.
		Keeping them here avoids growing ShopConfig into a second, unrelated
		"ability balancing" module and keeps ShopConfig's existing owners
		(other in-flight review agents) untouched.

	Rojo mount point:
		src/shared/AbilityConfig.lua -> ReplicatedStorage.AbilityConfig
]]

local AbilityConfig = {}

-- // Spore Shower (Developer Product, 9 Robux) ---------------------------------

AbilityConfig.SporeShower = {
	SporeCount = 10,
	-- Reuses the exact same scatter geometry as the regular Glow Spore spawn
	-- (see PickupSpawner.spawnGlowSporeForPlayer) for a consistent, reachable,
	-- "not inside buildings" placement - see PickupSpawner.SpawnBonusSpores.
	MinSpawnRadiusStuds = 6,
	SpawnRadiusStuds = 20,
	-- Distance from the plot's center beyond which a player is considered
	-- "not on their plot" (plot platforms are ~60 studs flat-to-flat, see
	-- PlotRegistry-Kommentar) - used only to decide which toast to show.
	OnPlotDistanceStuds = 45,
}

-- // Tidal Surge (Developer Product, 49 Robux) ---------------------------------

AbilityConfig.TidalSurge = {
	IncomeMultiplier = 2.0,
	BreedingSpeedMultiplier = 2.0,
	DurationSeconds = 30 * 60,
	MaxRemainingSeconds = 3 * 60 * 60, -- repeat purchases extend, capped at 3h total remaining
}

-- // Depth Charge (Developer Product, 29 Robux for 3 charges) ------------------

AbilityConfig.DepthCharge = {
	ChargesPerPurchase = 3,
	CooldownSeconds = 10,
	-- Regular (non-boss) enemies: a flat, very large damage value that always
	-- defeats them outright ("heavy damage to all enemies").
	NonBossDamage = 999999,
	-- Bosses take REDUCED damage so a single charge never trivializes them:
	-- capped at this fraction of their OWN max HP (not their current HP), so
	-- repeated Depth Charges during the same boss fight still add up fairly
	-- instead of instantly re-capping already-dealt damage.
	BossDamageFractionOfMaxHP = 0.4,
}

-- // Spore Magnet (Gamepass, 199 Robux) -----------------------------------------

AbilityConfig.SporeMagnet = {
	RadiusStuds = 25,
	-- How often the server re-scans nearby spores for Spore Magnet owners.
	-- Cheap (small per-player pickup list, see AbilityService), so a fairly
	-- tight tick is fine without a per-player loop (one shared loop for all
	-- online Spore Magnet owners, same "one loop, not N" principle as
	-- RaidService's tick loop).
	TickIntervalSeconds = 0.5,
}

-- // Extra Buddy Slot (Gamepass, 149 Robux) -------------------------------------

AbilityConfig.ExtraBuddySlot = {
	-- Mirrors BuddyClient.FOLLOW_OFFSET_LOCAL (X=2.6 right) onto the OTHER
	-- side (negative X) for the second buddy - see docs/abilities.md.
	FollowOffsetLocal = Vector3.new(-2.6, 1.0, 3.0),
}

return AbilityConfig
