--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: PrestigeConfig
	Responsibility:
		Single source of truth for the prestige system "Resurface" (GDD
		section 3 "Prestige system" + section 6 "Prestige multiplier"):
		eligibility, the income multiplier curve, the cosmetic titles and
		the one-time Abyssal Shards reward per ascend. Pure data + small
		pure helpers, no persistence (PrestigeService does that through
		PlayerDataService.ApplyAscend).

	INCOME MULTIPLIER (cumulative, additive, diminishing returns from ascend 10):
		Each ascend adds a bonus to the permanent multiplier, which starts
		at 1.0 (see PlayerData.Prestige.IncomeMultiplier):
			ascend  1 -  9: +10% each   -> x1.90 after ascend 9
			ascend 10 - 19: +8% each    -> x2.70 after ascend 19
			ascend 20 - 29: +6% each    -> x3.30 after ascend 29
			ascend 30+    : +4% each
		The multiplier is always DERIVED from the ascend count
		(GetMultiplierForCount), never "old multiplier + bonus", so it can
		not drift or be re-applied twice.
		It scales passive idle income only (IdleIncomeService), exactly
		like the codex income bonus. Flat rewards (raid loot, quest
		rewards) are not scaled.

	Rojo mount point:
		src/shared/PrestigeConfig.lua -> ReplicatedStorage.PrestigeConfig
		(read by server and client; the client only uses it for display)
]]

local PrestigeConfig = {}

-- // Eligibility ----------------------------------------------------------------

--- A player may resurface when they reached the Hadal Depths in the current
--- run (PlayerDataService.GetDeepestZone >= 4) OR are at least this level.
PrestigeConfig.REQUIRED_ZONE = 4
PrestigeConfig.REQUIRED_LEVEL = 45

--- Minimum seconds between two ascends (safety net next to the eligibility
--- rules, which already force a fresh run).
PrestigeConfig.COOLDOWN_SECONDS = 60

--- How long the server-side "armed" state from the first confirm step stays
--- valid (see PrestigeService.ArmResurface).
PrestigeConfig.ARM_WINDOW_SECONDS = 45

-- // Multiplier curve -------------------------------------------------------------

export type BonusTier = {
	FromAscend: number, -- first ascend number this bonus applies to
	Bonus: number, -- added to the multiplier per ascend, e.g. 0.10 == +10%
}

--- Must stay sorted by FromAscend ascending.
PrestigeConfig.BONUS_TIERS = {
	{ FromAscend = 1, Bonus = 0.10 },
	{ FromAscend = 10, Bonus = 0.08 },
	{ FromAscend = 20, Bonus = 0.06 },
	{ FromAscend = 30, Bonus = 0.04 },
} :: { BonusTier }

--- Bonus (fraction) that ascend number `ascendNumber` (1-based) adds.
function PrestigeConfig.GetBonusForAscend(ascendNumber: number): number
	local bonus = 0
	for _, tier in ipairs(PrestigeConfig.BONUS_TIERS) do
		if ascendNumber >= tier.FromAscend then
			bonus = tier.Bonus
		end
	end
	return bonus
end

--- Total permanent income multiplier after `ascendCount` ascends
--- (0 -> 1.0, 1 -> 1.1, 9 -> 1.9, 10 -> 1.98, ...), rounded to 3 decimals.
function PrestigeConfig.GetMultiplierForCount(ascendCount: number): number
	local total = 1
	for ascendNumber = 1, math.max(0, math.floor(ascendCount)) do
		total += PrestigeConfig.GetBonusForAscend(ascendNumber)
	end
	return math.floor(total * 1000 + 0.5) / 1000
end

-- // Titles (cosmetic) --------------------------------------------------------------

--- Title granted when the ascend count REACHES `AtAscend` (stored through
--- PlayerDataService.AddUnlockedTitle, shown by the existing title/codex UI).
PrestigeConfig.TITLES = {
	{ AtAscend = 1, Title = "Resurfaced" },
	{ AtAscend = 3, Title = "Tide Turner" },
	{ AtAscend = 5, Title = "Abyss Walker" },
	{ AtAscend = 10, Title = "Trench Veteran" },
	{ AtAscend = 20, Title = "Leviathan's Friend" },
	{ AtAscend = 30, Title = "Master of the Deep" },
} :: { { AtAscend: number, Title: string } }

--- Title for exactly this ascend number, or nil if it is not a title tier.
function PrestigeConfig.GetTitleForAscend(ascendNumber: number): string?
	for _, entry in ipairs(PrestigeConfig.TITLES) do
		if entry.AtAscend == ascendNumber then
			return entry.Title
		end
	end
	return nil
end

--- The next title the player can still earn (for the panel), or nil.
function PrestigeConfig.GetNextTitle(ascendCount: number): { AtAscend: number, Title: string }?
	for _, entry in ipairs(PrestigeConfig.TITLES) do
		if entry.AtAscend > ascendCount then
			return entry
		end
	end
	return nil
end

-- // Abyssal Shards reward (one-time per ascend) ------------------------------------

PrestigeConfig.SHARDS_BASE = 5 -- ascend 1
PrestigeConfig.SHARDS_PER_ASCEND = 1 -- +1 per further ascend
PrestigeConfig.SHARDS_CAP = 15 -- plain reward never exceeds this
PrestigeConfig.SHARDS_TITLE_BONUS = 10 -- extra on ascends that also unlock a title

--- Abyssal Shards granted once for ascend number `ascendNumber`.
function PrestigeConfig.GetShardReward(ascendNumber: number): number
	local plain = math.min(
		PrestigeConfig.SHARDS_CAP,
		PrestigeConfig.SHARDS_BASE + PrestigeConfig.SHARDS_PER_ASCEND * (math.max(1, ascendNumber) - 1)
	)
	if PrestigeConfig.GetTitleForAscend(ascendNumber) then
		plain += PrestigeConfig.SHARDS_TITLE_BONUS
	end
	return plain
end

-- // What is kept / reset (shown in the panel, kept here so UI and docs match) ------

PrestigeConfig.KEPT = {
	"Your creatures",
	"Abyssal Shards",
	"Codex progress and codex bonuses",
	"Cosmetics, titles and achievements",
	"Gamepasses and purchases",
}

PrestigeConfig.RESET = {
	"Your level and XP (back to level 1)",
	"Your Tide Coins (back to starter coins)",
	"All buildings on your plots",
	"Running Brood Pool eggs",
	"Your zone progress (back to the Sun Zone)",
}

return PrestigeConfig
