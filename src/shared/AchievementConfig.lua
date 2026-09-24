--[[
	Abyssara – Deep Tide Tycoon
	Module: AchievementConfig
	Responsibility:
		Single, easily-editable source of truth for the Achievements system
		(assignment: "Achievements with rewards, titles and Roblox badges"):
		the list of all achievements (category, display text, progress
		metric, target, reward, optional Roblox badge id). Contains
		deliberately NO random/persistence/progress logic itself (that lives
		in AchievementService) - only data + small, pure helper functions,
		identical principle to QuestConfig/GachaConfig/BuildingConfig.

	PROGRESS METRICS (Metric.Type):
		"Counter"  - AchievementService counts events from GameEvents itself
		             (PlayerDataService.AchievementState.Counters[Metric.Key]),
		             e.g. "how many times has 'RaidWon' fired". These
		             counters have NO historical backstory (they start at 0),
		             EXCEPT for a few keys where AchievementService.
		             runBackfill (see there) derives a plausible starting
		             value from already-existing player data on first login
		             after this system ships (e.g. building count from the
		             current habitat layout).
		"Snapshot" - AchievementService computes the current value LIVE from
		             already-existing, persistent player data (level,
		             creature inventory, codex zones, ...) - this
		             automatically makes it retroactively correct for
		             existing players, without needing a separate backfill
		             special case (see assignment point 2, "Backfill").
		In BOTH cases: once unlocked, an achievement STAYS unlocked forever,
		even if the underlying snapshot value later drops again (e.g. a
		sold/abducted creature) - see AchievementService.checkAndUnlock.

	SECRET ACHIEVEMENTS:
		`Secret = true` - name/description are replaced client-side by "???"/
		`SecretHint` until the achievement is unlocked (see
		AchievementService.GetState) - the client never receives the real
		text before unlocking (no spoilers via network sniffing).

	ROBLOX BADGES (`BadgeId`):
		0 = no badge. For selected milestone achievements (see
		docs/achievements.md, section "Recommended Badges") the developer
		should create a badge on create.roblox.com/dashboard/creations under
		the experience entry -> Badges, and enter its real numeric id here
		(see docs/achievements.md for the exact instructions) - placeholders
		deliberately stay at 0 until real ids have been entered.

	Rojo mount point:
		src/shared/AchievementConfig.lua -> ReplicatedStorage.AchievementConfig
		(pure data module, safe to read from server AND client - the client
		only reads this for display purposes, the sole authority over
		progress/unlocking/claiming/badge-granting stays server-side in
		AchievementService.)
]]

export type Category =
	"Building"
	| "Breeding"
	| "Raids"
	| "Collection"
	| "Eggs"
	| "Spores"
	| "Levels"
	| "Events"
	| "Secret"

export type MetricType = "Counter" | "Snapshot"

export type Metric = {
	Type: MetricType,
	Key: string,
}

export type AchievementReward = {
	TideCoins: number,
	AbyssalShards: number,
	Title: string?,
}

export type AchievementDefinition = {
	Id: string,
	Category: Category,
	Icon: string,
	Name: string,
	Description: string,
	Secret: boolean,
	SecretHint: string?, -- only relevant if Secret == true
	Metric: Metric,
	Target: number,
	Reward: AchievementReward,
	BadgeId: number, -- 0 = no Roblox badge, see header comment
}

local AchievementConfig = {}

-- // Category display (tab order/labels in the Achievements panel) ---------
AchievementConfig.CATEGORY_ORDER = {
	"Building",
	"Breeding",
	"Raids",
	"Collection",
	"Eggs",
	"Spores",
	"Levels",
	"Events",
	"Secret",
} :: { Category }

AchievementConfig.CATEGORY_LABELS = {
	Building = "Building",
	Breeding = "Breeding",
	Raids = "Trench Raids",
	Collection = "Collection",
	Eggs = "Mystery Eggs",
	Spores = "Glow Spores",
	Levels = "Levels",
	Events = "Live Events",
	Secret = "Secret",
} :: { [Category]: string }

-- // Achievement list ---------------------------------------------------------
-- BadgeId is deliberately left at 0 (placeholder) everywhere - see header
-- comment + docs/achievements.md for instructions on creating real badge
-- ids on create.roblox.com and entering them here.
AchievementConfig.LIST = {
	-- // Building -----------------------------------------------------------
	{
		Id = "Building_First",
		Category = "Building",
		Icon = "🏗️",
		Name = "First Foundations",
		Description = "Place your first building on your habitat.",
		Secret = false,
		Metric = { Type = "Counter", Key = "BuildingsPlaced" },
		Target = 1,
		Reward = { TideCoins = 100, AbyssalShards = 0, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Building_Architect",
		Category = "Building",
		Icon = "🏛️",
		Name = "Habitat Architect",
		Description = "Place a total of 25 buildings on your habitat.",
		Secret = false,
		Metric = { Type = "Counter", Key = "BuildingsPlaced" },
		Target = 25,
		Reward = { TideCoins = 400, AbyssalShards = 2, Title = "Habitat Architect" },
		BadgeId = 0,
	},
	{
		Id = "Building_MasterBuilder",
		Category = "Building",
		Icon = "🧱",
		Name = "Master Builder",
		Description = "Place at least one of every building type (6 total).",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "DistinctBuildingTypes" },
		Target = 6,
		Reward = { TideCoins = 600, AbyssalShards = 3, Title = "Master Builder" },
		BadgeId = 0, -- Recommended: create a badge, see docs/achievements.md
	},

	-- // Breeding -----------------------------------------------------------
	{
		Id = "Breeding_First",
		Category = "Breeding",
		Icon = "🥚",
		Name = "First Clutch",
		Description = "Complete your first breeding at the Brood Pool.",
		Secret = false,
		Metric = { Type = "Counter", Key = "BreedingCompleted" },
		Target = 1,
		Reward = { TideCoins = 120, AbyssalShards = 1, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Breeding_Broodkeeper",
		Category = "Breeding",
		Icon = "🐣",
		Name = "Broodkeeper",
		Description = "Complete a total of 25 breedings at the Brood Pool.",
		Secret = false,
		Metric = { Type = "Counter", Key = "BreedingCompleted" },
		Target = 25,
		Reward = { TideCoins = 500, AbyssalShards = 3, Title = "Broodkeeper" },
		BadgeId = 0,
	},
	{
		Id = "Breeding_RareBloodline",
		Category = "Breeding",
		Icon = "🧬",
		Name = "Rare Bloodline",
		Description = "Breed a Legendary or Mythic creature.",
		Secret = false,
		Metric = { Type = "Counter", Key = "BreedingLegendaryPlus" },
		Target = 1,
		Reward = { TideCoins = 350, AbyssalShards = 5, Title = "Bloodline Keeper" },
		BadgeId = 0,
	},

	-- // Trench Raids -------------------------------------------------------
	{
		Id = "Raids_Tier1",
		Category = "Raids",
		Icon = "⚔️",
		Name = "Trench Defender I",
		Description = "Win your first Trench Raid.",
		Secret = false,
		Metric = { Type = "Counter", Key = "RaidsWon" },
		Target = 1,
		Reward = { TideCoins = 150, AbyssalShards = 1, Title = "Trench Defender" },
		BadgeId = 0,
	},
	{
		Id = "Raids_Tier2",
		Category = "Raids",
		Icon = "🛡️",
		Name = "Trench Defender II",
		Description = "Win a total of 10 Trench Raids.",
		Secret = false,
		Metric = { Type = "Counter", Key = "RaidsWon" },
		Target = 10,
		Reward = { TideCoins = 600, AbyssalShards = 4, Title = "Trench Guardian" },
		BadgeId = 0,
	},
	{
		Id = "Raids_Tier3",
		Category = "Raids",
		Icon = "👑",
		Name = "Trench Defender III",
		Description = "Win a total of 50 Trench Raids.",
		Secret = false,
		Metric = { Type = "Counter", Key = "RaidsWon" },
		Target = 50,
		Reward = { TideCoins = 2000, AbyssalShards = 10, Title = "Trench Legend" },
		BadgeId = 0, -- Recommended: create a badge, see docs/achievements.md
	},

	-- // Collection (Creature Codex) ------------------------------------------
	{
		Id = "Collection_Budding",
		Category = "Collection",
		Icon = "📖",
		Name = "Budding Collector",
		Description = "Own 10 different creature species.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "UniqueCreatures" },
		Target = 10,
		Reward = { TideCoins = 300, AbyssalShards = 2, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Collection_Cataloguer",
		Category = "Collection",
		Icon = "📚",
		Name = "Abyssal Cataloguer",
		Description = "Own 25 different creature species.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "UniqueCreatures" },
		Target = 25,
		Reward = { TideCoins = 800, AbyssalShards = 5, Title = "Cataloguer" },
		BadgeId = 0,
	},
	{
		Id = "Collection_ZoneCompletionist",
		Category = "Collection",
		Icon = "🗺️",
		Name = "Zone Completionist",
		Description = "Fully complete the codex for all 4 zones.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "CodexZonesCompleted" },
		Target = 4,
		Reward = { TideCoins = 1000, AbyssalShards = 6, Title = "Zone Master" },
		BadgeId = 0,
	},

	-- // Mystery Eggs ---------------------------------------------------------
	{
		Id = "Eggs_First",
		Category = "Eggs",
		Icon = "🎁",
		Name = "Cracked Open",
		Description = "Open your first Mystery Egg.",
		Secret = false,
		Metric = { Type = "Counter", Key = "EggsOpened" },
		Target = 1,
		Reward = { TideCoins = 80, AbyssalShards = 0, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Eggs_Enthusiast",
		Category = "Eggs",
		Icon = "🎉",
		Name = "Egg Enthusiast",
		Description = "Open a total of 50 Mystery Eggs.",
		Secret = false,
		Metric = { Type = "Counter", Key = "EggsOpened" },
		Target = 50,
		Reward = { TideCoins = 500, AbyssalShards = 3, Title = "Egg Enthusiast" },
		BadgeId = 0,
	},
	{
		Id = "Eggs_LegendaryLuck",
		Category = "Eggs",
		Icon = "✨",
		Name = "Legendary Luck",
		Description = "Hatch a Legendary or Mythic creature from a Mystery Egg.",
		Secret = false,
		Metric = { Type = "Counter", Key = "EggsLegendaryPlus" },
		Target = 1,
		Reward = { TideCoins = 400, AbyssalShards = 5, Title = "Egg Whisperer" },
		BadgeId = 0,
	},

	-- // Glow Spores -----------------------------------------------------------
	{
		Id = "Spores_Gatherer",
		Category = "Spores",
		Icon = "🌟",
		Name = "Spore Gatherer",
		Description = "Deliver a total of 100 Glow Spores.",
		Secret = false,
		Metric = { Type = "Counter", Key = "SporesDelivered" },
		Target = 100,
		Reward = { TideCoins = 200, AbyssalShards = 1, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Spores_Tycoon",
		Category = "Spores",
		Icon = "💎",
		Name = "Spore Tycoon",
		Description = "Deliver a total of 1000 Glow Spores.",
		Secret = false,
		Metric = { Type = "Counter", Key = "SporesDelivered" },
		Target = 1000,
		Reward = { TideCoins = 900, AbyssalShards = 4, Title = "Spore Tycoon" },
		BadgeId = 0,
	},

	-- // Levels --------------------------------------------------------------
	{
		Id = "Levels_Rising",
		Category = "Levels",
		Icon = "⭐",
		Name = "Rising Diver",
		Description = "Reach level 5.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "Level" },
		Target = 5,
		Reward = { TideCoins = 150, AbyssalShards = 0, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Levels_Deep",
		Category = "Levels",
		Icon = "🌊",
		Name = "Deep Diver",
		Description = "Reach level 15.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "Level" },
		Target = 15,
		Reward = { TideCoins = 500, AbyssalShards = 3, Title = "Deep Diver" },
		BadgeId = 0,
	},
	{
		Id = "Levels_AbyssalMaster",
		Category = "Levels",
		Icon = "🏔️",
		Name = "Abyssal Master",
		Description = "Reach the maximum level, 25.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "Level" },
		Target = 25,
		Reward = { TideCoins = 1500, AbyssalShards = 8, Title = "Abyssal Master" },
		BadgeId = 0, -- Recommended: create a badge, see docs/achievements.md
	},

	-- // Live Events -----------------------------------------------------------
	{
		Id = "Events_TideRider",
		Category = "Events",
		Icon = "🌊",
		Name = "Tide Rider",
		Description = "Acquire your first Live Event shop item.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "EventItemsOwned" },
		Target = 1,
		Reward = { TideCoins = 150, AbyssalShards = 0, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Events_StormChaser",
		Category = "Events",
		Icon = "🌪️",
		Name = "Storm Chaser",
		Description = "Acquire a total of 5 different Live Event shop items.",
		Secret = false,
		Metric = { Type = "Snapshot", Key = "EventItemsOwned" },
		Target = 5,
		Reward = { TideCoins = 600, AbyssalShards = 3, Title = "Storm Chaser" },
		BadgeId = 0,
	},

	-- // Secret achievements ---------------------------------------------------
	{
		Id = "Secret_NightOwl",
		Category = "Secret",
		Icon = "🌙",
		Name = "Night Owl",
		Description = "Play something between 2:00 AM and 4:00 AM (server time, UTC).",
		Secret = true,
		SecretHint = "Some deep-sea dwellers are only active at night...",
		Metric = { Type = "Counter", Key = "NightOwlFlag" },
		Target = 1,
		Reward = { TideCoins = 250, AbyssalShards = 1, Title = "Night Owl" },
		BadgeId = 0,
	},
	{
		Id = "Secret_UnluckyDive",
		Category = "Secret",
		Icon = "🆘",
		Name = "Unlucky Dive",
		Description = "Lose a Trench Raid and have a creature abducted in the process.",
		Secret = true,
		SecretHint = "Not every dive goes well...",
		Metric = { Type = "Counter", Key = "RaidsLostWithAbduction" },
		Target = 1,
		Reward = { TideCoins = 200, AbyssalShards = 1, Title = nil },
		BadgeId = 0,
	},
	{
		Id = "Secret_TrueAbyssal",
		Category = "Secret",
		Icon = "🐙",
		Name = "True Abyssal",
		Description = "Reach level 25 AND own at least one Mythic creature.",
		Secret = true,
		SecretHint = "Only the very best reach the true abyss...",
		Metric = { Type = "Snapshot", Key = "TrueAbyssalFlag" },
		Target = 1,
		Reward = { TideCoins = 2500, AbyssalShards = 12, Title = "True Abyssal" },
		BadgeId = 0, -- Recommended: create a badge, see docs/achievements.md
	},
} :: { AchievementDefinition }

--- Returns the achievement definition for `id`, or nil if unknown (e.g. an
--- older entry removed from this list, still present in saved player data -
--- AchievementService handles this defensively, see there).
function AchievementConfig.GetById(id: string): AchievementDefinition?
	for _, def in ipairs(AchievementConfig.LIST) do
		if def.Id == id then
			return def
		end
	end
	return nil
end

return AchievementConfig
