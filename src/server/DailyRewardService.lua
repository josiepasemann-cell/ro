--[[
	Abyssara – Deep Tide Tycoon
	Modul: DailyRewardService
	Zuständigkeit:
		Kernlogik der Tages-Login-Belohnung mit 7-Tage-Streak (GDD Abschnitt 3
		+ Auftrag Punkt 2): leitet aus `DailyRewardState.LastClaimedDate` (vs.
		dem heutigen UTC-Datum) her, ob eine Belohnung abholbar ist und welcher
		Streak-Tag als nächstes drankommt (Streak bricht bei verpasstem Tag,
		zyklisch 1..7 danach wieder von vorn). Wendet den VIP-Taucher-
		Gamepass-Bonus (DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER) an,
		OHNE die bereits bestehende, separate VIP-Bonus-Truhe in
		MonetizationService zu duplizieren (siehe DailyRewardConfig-
		Kopfkommentar "Abgrenzung").

	Sicherheitsprinzip (kein Client-Trust):
		RequestClaimDailyReward nimmt keinerlei Payload vom Client entgegen -
		"welcher Tag"/"ob überhaupt abholbar" wird JEDES Mal komplett neu aus
		dem persistenten DailyRewardState + dem aktuellen Serverdatum
		hergeleitet, niemals aus einem Client-Wert übernommen.

	Rojo-Einhängepunkt:
		src/server/DailyRewardService.lua -> ServerScriptService.DailyRewardService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local DailyRewardConfig = require(ReplicatedStorage:WaitForChild("DailyRewardConfig"))

export type ClaimFailureReason = "DataNotLoaded" | "AlreadyClaimedToday"

local DailyRewardService = {}

-- // Hilfsfunktionen ------------------------------------------------------

--- Sekunden-genaue Differenz zweier "YYYY-MM-DD"-Datumsstrings (UTC), robust
--- gegen Kalendermonatsgrenzen (nutzt os.time() über geparste Y/M/D-Werte
--- statt naiver String-Subtraktion). Gibt die Anzahl VOLLER Tage zwischen
--- `fromDate` und `toDate` zurück (positiv, wenn toDate später liegt).
local function daysBetween(fromDate: string, toDate: string): number
	local fy, fm, fd = fromDate:match("(%d+)-(%d+)-(%d+)")
	local ty, tm, td = toDate:match("(%d+)-(%d+)-(%d+)")
	if not (fy and ty) then
		return math.huge -- unparsebar (sollte nie eintreten) - sicherheitshalber "Streak gebrochen"
	end

	-- os.time() mit UTC-Komponenten (isdst egal, wir arbeiten ausschließlich
	-- in Tagesauflösung) - Mittag statt Mitternacht als Ankerzeit, um
	-- DST-/Rundungs-Randfälle in der zugrundeliegenden C-Bibliothek zu
	-- vermeiden (spielt für eine reine Tagesdifferenz keine Rolle).
	local fromTime = os.time({ year = tonumber(fy), month = tonumber(fm), day = tonumber(fd), hour = 12 })
	local toTime = os.time({ year = tonumber(ty), month = tonumber(tm), day = tonumber(td), hour = 12 })
	return math.floor((toTime - fromTime) / (24 * 60 * 60) + 0.5)
end

--- Leitet (canClaim, pendingStreakDay, alreadyClaimedToday) aus dem
--- persistenten DailyRewardState + dem heutigen UTC-Datum her - reine,
--- deterministische Logik ohne Nebenwirkungen (wird sowohl fürs
--- GetDailyRewardState-Panel als auch VOR dem eigentlichen Claim aufgerufen).
local function computePendingClaim(player: Player): (boolean, number, boolean)
	local state = PlayerDataService.GetDailyRewardState(player)
	local today = PlayerDataService.GetUtcDateString()

	if state.LastClaimedDate == today then
		return false, math.clamp(state.Streak, 1, DailyRewardConfig.MAX_STREAK_DAY), true
	end

	if not state.LastClaimedDate then
		-- Nie zuvor abgeholt: Tag 1.
		return true, 1, false
	end

	local gap = daysBetween(state.LastClaimedDate, today)
	if gap == 1 then
		-- Nahtlos am Folgetag: Streak geht weiter, zyklisch nach Tag 7 wieder auf 1.
		local nextDay = if state.Streak >= DailyRewardConfig.MAX_STREAK_DAY then 1 else state.Streak + 1
		return true, nextDay, false
	end

	-- gap <= 0 sollte praktisch nie vorkommen (Client-Uhr o. ä. hat hier
	-- keinen Einfluss, LastClaimedDate kommt ausschließlich vom Server) -
	-- gap > 1 bedeutet mindestens ein verpasster Tag: Streak bricht, Tag 1.
	return true, 1, false
end

-- // Öffentliche API --------------------------------------------------------

--- Liefert den vollständigen Client-Zustand für den initialen UI-Sync (siehe
--- QuestRemotes.GetDailyRewardState).
function DailyRewardService.GetState(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return {
			CanClaim = false,
			PendingStreakDay = 1,
			PreviewTideCoins = 0,
			PreviewAbyssalShards = 0,
			VipBonusActive = false,
			AlreadyClaimedToday = false,
		}
	end

	local canClaim, pendingDay, alreadyClaimedToday = computePendingClaim(player)
	local reward = DailyRewardConfig.GetReward(pendingDay)

	-- BEWUSST ein LAZY require() von MonetizationService (Funktionskörper
	-- statt Modul-Kopf) - identische Begründung wie in BreedingService.
	-- RequestStartBreeding/RaidService.applyDoubleCoinsGamepass: vermeidet
	-- einen potenziellen zirkulären require-Zyklus.
	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	local vipActive = MonetizationService.PlayerOwnsGamepass(player, "VIPDiver")
	local previewTideCoins = reward.TideCoins
	if vipActive then
		previewTideCoins = math.floor(previewTideCoins * DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER + 0.5)
	end

	return {
		CanClaim = canClaim,
		PendingStreakDay = pendingDay,
		PreviewTideCoins = previewTideCoins,
		PreviewAbyssalShards = reward.AbyssalShards,
		VipBonusActive = vipActive,
		AlreadyClaimedToday = alreadyClaimedToday,
	}
end

--- Validiert und schließt das Abholen der heutigen Streak-Belohnung
--- vollständig serverseitig ab.
function DailyRewardService.RequestClaim(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	local canClaim, pendingDay = computePendingClaim(player)
	if not canClaim then
		return { Success = false, Reason = "AlreadyClaimedToday" }
	end

	-- Sofort SYNCHRON (vor jedem potenziell nachgebenden/"yield"-fähigen
	-- Aufruf, z. B. dem Gamepass-Besitz-Check unten, der bei einem
	-- Cache-Miss `MarketplaceService:UserOwnsGamePassAsync` aufruft und
	-- damit den aufrufenden Coroutine yielden kann) als abgeholt markieren -
	-- verhindert einen Doppel-Claim, falls der Client RequestClaimDailyReward
	-- (RemoteEvent, kein Ack) während dieses Yields ein zweites Mal feuert:
	-- der zweite Aufruf sieht dann bereits LastClaimedDate == today.
	local today = PlayerDataService.GetUtcDateString()
	local marked = PlayerDataService.SetDailyRewardClaimed(player, today, pendingDay)
	if not marked then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	local reward = DailyRewardConfig.GetReward(pendingDay)

	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	local vipActive = MonetizationService.PlayerOwnsGamepass(player, "VIPDiver")
	local tideCoinsAmount = reward.TideCoins
	if vipActive then
		tideCoinsAmount = math.floor(tideCoinsAmount * DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER + 0.5)
	end

	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", tideCoinsAmount)
	if reward.AbyssalShards > 0 then
		PlayerDataService.AddCurrency(player, "AbyssalShards", reward.AbyssalShards)
	end
	ProgressionService.AwardXP(player, "DailyLoginClaimed")

	return {
		Success = true,
		StreakDay = pendingDay,
		RewardTideCoins = tideCoinsAmount,
		RewardAbyssalShards = reward.AbyssalShards,
		NewTideCoinBalance = newBalance,
	}
end

return DailyRewardService
