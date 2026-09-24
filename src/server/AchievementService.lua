--[[
	Abyssara – Deep Tide Tycoon
	Module: AchievementService
	Responsibility:
		Core logic of the Achievements system (assignment: "Achievements with
		rewards, titles and Roblox badges"): counts progress from GameEvents
		(see GameEvents header comment - listens exclusively there, does NOT
		scatter calls into BuildingPlaced/BreedingService/RaidService/
		GachaService/PickupSpawner), persists progress via PlayerDataService,
		unlocks achievements the instant their target is reached, lets
		players claim the reward once (server-validated), and grants a
		Roblox badge via BadgeService:AwardBadge for achievements that have a
		BadgeId configured. Also owns the "equipped title" flow (billboard
		above the player's head) and a one-time backfill so existing players
		aren't punished for having progressed before this system shipped.

		Listens ONLY to GameEvents (BuildingPlaced/BreedingCompleted/
		RaidWon/RaidLost/EggOpened/SporeDelivered/CoinsEarned) - identical
		one-way-street principle to QuestService/LeaderboardService/
		LiveEventService: this module knows none of the firing services, and
		none of them know this module. No circular requires.

	PROGRESS METRICS - see AchievementConfig header comment for the full
	"Counter" vs "Snapshot" explanation. In short: "Counter" achievements
	accumulate in AchievementState.Counters as GameEvents fire; "Snapshot"
	achievements are computed live from already-persisted player data
	(Level, creature inventory, codex zones, ...) every time they're
	evaluated - which makes them automatically backfilled for existing
	players without any special-case code (see runBackfill below, which only
	needs to handle the small number of Counter keys that have no equivalent
	persisted elsewhere).

	No-client-trust principle:
		RequestClaimReward/RequestEquipTitle take an achievementId/title from
		the client (a claimed intent, nothing more) - both are re-validated
		completely against this service's own persistent state before
		anything is granted/equipped. Progress itself is NEVER computed from
		client input - only from GameEvents payloads that are themselves
		already server-validated by their originating service.

	Roblox badges:
		BadgeService:AwardBadge is always wrapped in pcall and preceded by a
		UserHasBadgeAsync check (also pcall'd) - a badge-service outage or a
		missing/invalid BadgeId (0 = none, see AchievementConfig) NEVER
		blocks unlocking/claiming/gameplay, it's purely a best-effort side
		effect running in its own task.spawn.

	Rojo mount point:
		src/server/AchievementService.lua -> ServerScriptService.AchievementService
]]

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local CodexService = require(script.Parent:WaitForChild("CodexService"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("AchievementConfig"))
local AchievementRemotes = require(ReplicatedStorage:WaitForChild("AchievementRemotes"))

type AchievementState = PlayerDataService.AchievementState
type AchievementDefinition = AchievementConfig.AchievementDefinition

export type ClaimFailureReason = "DataNotLoaded" | "UnknownAchievement" | "NotUnlocked" | "AlreadyClaimed"
export type EquipTitleFailureReason = "DataNotLoaded" | "InvalidTitle" | "NotOwned"

local AchievementService = {}

local HIGH_RARITIES: { [string]: boolean } = { Legendary = true, Mythic = true }

-- // Title billboard (above the player's head) --------------------------------

local BILLBOARD_NAME = "AchievementTitleGui"
local TITLE_COLOR = Color3.fromRGB(120, 240, 255) -- neon cyan, readable at distance

local function ensureBillboard(head: BasePart): (BillboardGui, TextLabel)
	local existing = head:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		local label = existing:FindFirstChild("TitleLabel") :: TextLabel?
		if label then
			return existing, label
		end
		existing:Destroy()
	elseif existing then
		existing:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = BILLBOARD_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = head

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(4, 10, 14)
	stroke.Thickness = 1.5
	stroke.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "TitleLabel"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = TITLE_COLOR
	label.TextStrokeTransparency = 0.15
	label.TextStrokeColor3 = Color3.fromRGB(4, 10, 14)
	label.Text = ""
	label.Parent = gui

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 10
	constraint.MaxTextSize = 22
	constraint.Parent = label

	return gui, label
end

--- Refreshes (or removes) the billboard title above `player`'s head from
--- their currently persisted AchievementState.EquippedTitle. Safe to call
--- repeatedly (e.g. on every CharacterAdded) - idempotent no-op if the
--- title hasn't changed and the billboard already exists.
function AchievementService.RefreshTitleBillboard(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local state = PlayerDataService.GetAchievementState(player)
	local title = state.EquippedTitle

	if not title or title == "" then
		local existing = head:FindFirstChild(BILLBOARD_NAME)
		if existing then
			existing:Destroy()
		end
		return
	end

	local _, label = ensureBillboard(head)
	label.Text = title
end

-- // Snapshot providers (live-computed from already-persisted data) ----------

local function countUniqueCreatures(player: Player): number
	local seen: { [string]: boolean } = {}
	local count = 0
	for _, instance in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		if not seen[instance.CreatureId] then
			seen[instance.CreatureId] = true
			count += 1
		end
	end
	return count
end

local function countDistinctBuildingTypes(player: Player): number
	local seen: { [string]: boolean } = {}
	local count = 0
	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		if not seen[placement.BuildingId] then
			seen[placement.BuildingId] = true
			count += 1
		end
	end
	return count
end

local function countCompletedCodexZones(player: Player): number
	local count = 0
	for _, zone in ipairs(CodexService.KNOWN_ZONES) do
		if PlayerDataService.IsCodexZoneRewardClaimed(player, zone) then
			count += 1
		end
	end
	return count
end

local function countEventItemsOwned(player: Player): number
	local owned = PlayerDataService.GetLiveEventState(player).OwnedEventItems
	local count = 0
	for _ in pairs(owned) do
		count += 1
	end
	return count
end

local function hasMythicCreature(player: Player): boolean
	for _, instance in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		if instance.Rarity == "Mythic" then
			return true
		end
	end
	return false
end

local SNAPSHOT_PROVIDERS: { [string]: (Player) -> number } = {
	Level = function(player) return PlayerDataService.GetLevel(player) end,
	UniqueCreatures = countUniqueCreatures,
	DistinctBuildingTypes = countDistinctBuildingTypes,
	CodexZonesCompleted = countCompletedCodexZones,
	EventItemsOwned = countEventItemsOwned,
	TrueAbyssalFlag = function(player)
		return (PlayerDataService.GetLevel(player) >= 25 and hasMythicCreature(player)) and 1 or 0
	end,
}

local function computeProgress(player: Player, def: AchievementDefinition, state: AchievementState): number
	if def.Metric.Type == "Counter" then
		return state.Counters[def.Metric.Key] or 0
	end
	local provider = SNAPSHOT_PROVIDERS[def.Metric.Key]
	if not provider then
		warn(("[AchievementService] Unknown snapshot key '%s' for achievement '%s'."):format(def.Metric.Key, def.Id))
		return 0
	end
	local ok, value = pcall(provider, player)
	if not ok or type(value) ~= "number" then
		return 0
	end
	return value
end

-- // Counter helpers -----------------------------------------------------------

local function incrementCounter(player: Player, key: string, amount: number)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	local state = PlayerDataService.GetAchievementState(player)
	state.Counters[key] = (state.Counters[key] or 0) + amount
	PlayerDataService.SetAchievementState(player, state)
end

local function setCounterFlag(player: Player, key: string)
	local state = PlayerDataService.GetAchievementState(player)
	if (state.Counters[key] or 0) < 1 then
		state.Counters[key] = 1
		PlayerDataService.SetAchievementState(player, state)
	end
end

-- // Badge granting (best-effort, never blocks gameplay) ---------------------

local function awardBadgeIfConfigured(player: Player, def: AchievementDefinition)
	local badgeId = def.BadgeId
	if type(badgeId) ~= "number" or badgeId <= 0 then
		return
	end
	local userId = player.UserId
	task.spawn(function()
		local ok, hasBadge = pcall(function()
			return BadgeService:UserHasBadgeAsync(userId, badgeId)
		end)
		if ok and hasBadge then
			return
		end
		local awardOk, awardErr = pcall(function()
			BadgeService:AwardBadge(userId, badgeId)
		end)
		if not awardOk then
			warn(("[AchievementService] AwardBadge(%d, %d) failed: %s"):format(userId, badgeId, tostring(awardErr)))
		end
	end)
end

-- // Unlock / evaluation --------------------------------------------------------

local function fireUnlocked(player: Player, def: AchievementDefinition)
	AchievementRemotes.AchievementUnlocked:FireClient(player, {
		Id = def.Id,
		Name = def.Name,
		Icon = def.Icon,
		Category = def.Category,
		RewardTideCoins = def.Reward.TideCoins,
		RewardAbyssalShards = def.Reward.AbyssalShards,
		RewardTitle = def.Reward.Title,
	})
end

--- Checks ONE achievement definition against the player's current state and
--- unlocks it if its target has been reached. Idempotent (already-unlocked
--- achievements are skipped immediately) - safe to call from every relevant
--- GameEvents handler without extra bookkeeping.
local function checkAndUnlock(player: Player, def: AchievementDefinition)
	local state = PlayerDataService.GetAchievementState(player)
	if state.Unlocked[def.Id] then
		return
	end

	local progress = computeProgress(player, def, state)
	if progress < def.Target then
		AchievementRemotes.AchievementProgressUpdated:FireClient(player, {
			Id = def.Id,
			Progress = math.min(progress, def.Target),
			Target = def.Target,
		})
		return
	end

	state.Unlocked[def.Id] = true
	PlayerDataService.SetAchievementState(player, state)

	fireUnlocked(player, def)
	awardBadgeIfConfigured(player, def)
end

local function evaluateAll(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	for _, def in ipairs(AchievementConfig.LIST) do
		checkAndUnlock(player, def)
	end
end

-- // Secret "Night Owl" check (needs a wall-clock read, not a GameEvents
-- payload field - piggybacks on every tracked event as a cheap, broad tap) --

local function checkNightOwl(player: Player)
	local hour = tonumber(os.date("!%H"))
	if hour and hour >= 2 and hour < 4 then
		setCounterFlag(player, "NightOwlFlag")
	end
end

local function onAnyTrackedEvent(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	checkNightOwl(player)
end

-- // GameEvents subscriptions (ONE central set, see header comment) ---------

GameEvents.Connect(GameEvents.Events.BuildingPlaced, function(player: Player, _payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	incrementCounter(player, "BuildingsPlaced", 1)
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

GameEvents.Connect(GameEvents.Events.BreedingCompleted, function(player: Player, payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	incrementCounter(player, "BreedingCompleted", 1)
	if type(payload.Rarity) == "string" and HIGH_RARITIES[payload.Rarity] then
		incrementCounter(player, "BreedingLegendaryPlus", 1)
	end
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

GameEvents.Connect(GameEvents.Events.RaidWon, function(player: Player, _payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	incrementCounter(player, "RaidsWon", 1)
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

GameEvents.Connect(GameEvents.Events.RaidLost, function(player: Player, payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	if payload.AbductedInstanceId ~= nil then
		incrementCounter(player, "RaidsLostWithAbduction", 1)
	end
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

GameEvents.Connect(GameEvents.Events.EggOpened, function(player: Player, payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	incrementCounter(player, "EggsOpened", 1)
	if type(payload.Rarity) == "string" and HIGH_RARITIES[payload.Rarity] then
		incrementCounter(player, "EggsLegendaryPlus", 1)
	end
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

GameEvents.Connect(GameEvents.Events.SporeDelivered, function(player: Player, payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local amount = if type(payload.Amount) == "number" then payload.Amount else 1
	incrementCounter(player, "SporesDelivered", amount)
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

-- CoinsEarned fires on almost every rewarding action in the game (quests,
-- daily login, raids, spores, ...) - used here as a broad, cheap re-check
-- tick for Snapshot achievements (Level/Collection/Events) that have no
-- single dedicated GameEvents source of their own.
GameEvents.Connect(GameEvents.Events.CoinsEarned, function(player: Player, _payload: { [string]: any })
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	onAnyTrackedEvent(player)
	evaluateAll(player)
end)

-- // Backfill (assignment point 2: "derive already-met achievements from
-- existing data on first load, so older players aren't punished") ----------

--- Runs exactly once per player (guarded by AchievementState.BackfillCompleted)
--- and seeds the small number of Counter keys that have NO equivalent
--- persisted elsewhere with a plausible starting value derived from already-
--- existing player data. Snapshot achievements need NO special handling here
--- - they're always computed live, see computeProgress/evaluateAll.
local function runBackfill(player: Player)
	local state = PlayerDataService.GetAchievementState(player)
	if state.BackfillCompleted then
		return
	end

	if state.Counters.BuildingsPlaced == nil then
		state.Counters.BuildingsPlaced = #PlayerDataService.GetHabitatLayout(player)
	end
	if state.Counters.RaidsLostWithAbduction == nil and #PlayerDataService.GetAbductedCreatures(player) > 0 then
		state.Counters.RaidsLostWithAbduction = 1
	end

	state.BackfillCompleted = true
	PlayerDataService.SetAchievementState(player, state)
end

-- // Public API (consumed by AchievementServer.server.lua) -----------------

--- Builds the full client-facing achievement state (initial UI sync + used
--- after every claim/equip). Secret, not-yet-unlocked achievements have
--- their Name/Description replaced so the real content is never sent to the
--- client before unlocking.
function AchievementService.GetState(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Achievements = {}, EquippedTitle = nil, UnlockedTitles = {} }
	end

	local state = PlayerDataService.GetAchievementState(player)
	local achievements = {}

	for _, def in ipairs(AchievementConfig.LIST) do
		local unlocked = state.Unlocked[def.Id] == true
		local hideContent = def.Secret and not unlocked
		local progress = if hideContent then 0 else math.min(computeProgress(player, def, state), def.Target)

		table.insert(achievements, {
			Id = def.Id,
			Category = def.Category,
			Icon = def.Icon,
			Name = if hideContent then "???" else def.Name,
			Description = if hideContent then (def.SecretHint or "A secret achievement.") else def.Description,
			Secret = def.Secret,
			Unlocked = unlocked,
			Progress = progress,
			Target = def.Target,
			Claimed = state.Claimed[def.Id] == true,
			RewardTideCoins = def.Reward.TideCoins,
			RewardAbyssalShards = def.Reward.AbyssalShards,
			RewardTitle = def.Reward.Title,
		})
	end

	return {
		Achievements = achievements,
		EquippedTitle = state.EquippedTitle,
		UnlockedTitles = PlayerDataService.GetUnlockedTitles(player),
	}
end

--- Validates and fully completes claiming ONE achievement's reward
--- server-side. `achievementId` is an untrusted, alleged client value - it
--- gets re-checked completely against this service's own persistent state
--- before anything is granted.
function AchievementService.RequestClaim(player: Player, achievementId: any): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" :: ClaimFailureReason }
	end
	if type(achievementId) ~= "string" then
		return { Success = false, Reason = "UnknownAchievement" :: ClaimFailureReason }
	end

	local def = AchievementConfig.GetById(achievementId)
	if not def then
		return { Success = false, Reason = "UnknownAchievement" :: ClaimFailureReason }
	end

	local state = PlayerDataService.GetAchievementState(player)
	if not state.Unlocked[achievementId] then
		return { Success = false, Reason = "NotUnlocked" :: ClaimFailureReason }
	end
	if state.Claimed[achievementId] then
		return { Success = false, Reason = "AlreadyClaimed" :: ClaimFailureReason }
	end

	state.Claimed[achievementId] = true
	PlayerDataService.SetAchievementState(player, state)

	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", def.Reward.TideCoins)
	if def.Reward.AbyssalShards > 0 then
		PlayerDataService.AddCurrency(player, "AbyssalShards", def.Reward.AbyssalShards)
	end
	if def.Reward.Title then
		PlayerDataService.AddUnlockedTitle(player, def.Reward.Title)
	end

	return {
		Success = true,
		Id = achievementId,
		RewardTideCoins = def.Reward.TideCoins,
		RewardAbyssalShards = def.Reward.AbyssalShards,
		RewardTitle = def.Reward.Title,
		NewTideCoinBalance = newBalance,
	}
end

--- Validates and applies an equip/unequip title request. `title == nil`
--- unequips. `title` is an untrusted, alleged client value - re-checked
--- against PlayerDataService.GetUnlockedTitles (the shared title-ownership
--- pool, see that function's comment) before being persisted.
function AchievementService.RequestEquipTitle(player: Player, title: any): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" :: EquipTitleFailureReason }
	end

	if title == nil then
		local state = PlayerDataService.GetAchievementState(player)
		state.EquippedTitle = nil
		PlayerDataService.SetAchievementState(player, state)
		AchievementService.RefreshTitleBillboard(player)
		return { Success = true, Title = nil }
	end

	if type(title) ~= "string" or title == "" then
		return { Success = false, Reason = "InvalidTitle" :: EquipTitleFailureReason }
	end

	local owned = PlayerDataService.GetUnlockedTitles(player)
	if not table.find(owned, title) then
		return { Success = false, Reason = "NotOwned" :: EquipTitleFailureReason }
	end

	local state = PlayerDataService.GetAchievementState(player)
	state.EquippedTitle = title
	PlayerDataService.SetAchievementState(player, state)
	AchievementService.RefreshTitleBillboard(player)

	return { Success = true, Title = title }
end

-- // Bootstrap --------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Head", 5)
	AchievementService.RefreshTitleBillboard(player)
end

local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, 15)
	if not data then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end

	runBackfill(player)
	evaluateAll(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

return AchievementService
