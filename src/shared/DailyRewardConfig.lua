--[[
	Abyssara – Deep Tide Tycoon
	Modul: DailyRewardConfig
	Zuständigkeit:
		Einzige Quelle der Wahrheit für die Tages-Login-Belohnung mit
		steigendem 7-Tage-Streak (GDD Abschnitt 3 "Tägliche Quests ... mit
		Belohnungstruhen" + Auftrag Punkt 2 "Tages-Login-Belohnung mit Streak
		(Tag 1-7 steigend, Streak bricht bei verpasstem Tag)"). Reine Daten,
		keine Persistenz-/Datums-Logik (die lebt in DailyRewardService).

		ABGRENZUNG zur bereits bestehenden VIP-Bonus-Truhe
		(MonetizationService.applyVipEffect + PlayerDataService.
		Get/SetLastVipChestClaimedDate): DIESES System ist eine EIGENE,
		streak-basierte Belohnung für ALLE Spieler (nicht nur VIP-Taucher-
		Gamepass-Besitzer). Der Auftrag verlangt zusätzlich, den VIP-Bonus zu
		"berücksichtigen, nicht doppelt bauen" - das wird hier NICHT über eine
		zweite Truhe gelöst, sondern über einen einfachen Multiplikator
		(VIP_BONUS_TIDE_COINS_MULTIPLIER) auf die Tide-Coins-Auszahlung DIESES
		Streak-Systems, wenn der Spieler den VIP-Taucher-Gamepass besitzt
		(siehe DailyRewardService). Die bereits bestehende, separate
		MonetizationService-Truhe bleibt unverändert und läuft komplett
		unabhängig weiter - kein Datenfeld/keine Logik wird hier dupliziert.

	Rojo-Einhängepunkt:
		src/shared/DailyRewardConfig.lua -> ReplicatedStorage.DailyRewardConfig
]]

export type DailyRewardEntry = {
	Day: number, -- 1..MAX_STREAK_DAY
	TideCoins: number,
	AbyssalShards: number,
}

local DailyRewardConfig = {}

DailyRewardConfig.MAX_STREAK_DAY = 7

-- // Steigende Belohnungstabelle Tag 1 -> 7 (GDD: "steigend") ----------------
DailyRewardConfig.REWARDS_BY_DAY = {
	[1] = { Day = 1, TideCoins = 50, AbyssalShards = 0 },
	[2] = { Day = 2, TideCoins = 75, AbyssalShards = 0 },
	[3] = { Day = 3, TideCoins = 100, AbyssalShards = 1 },
	[4] = { Day = 4, TideCoins = 125, AbyssalShards = 1 },
	[5] = { Day = 5, TideCoins = 150, AbyssalShards = 1 },
	[6] = { Day = 6, TideCoins = 200, AbyssalShards = 2 },
	[7] = { Day = 7, TideCoins = 300, AbyssalShards = 3 },
} :: { [number]: DailyRewardEntry }

-- // VIP-Taucher-Gamepass-Bonus (siehe Abgrenzung im Kopfkommentar) ----------
DailyRewardConfig.VIP_BONUS_TIDE_COINS_MULTIPLIER = 1.5

--- Liefert den Belohnungs-Eintrag für `day`, geklemmt auf [1, MAX_STREAK_DAY].
function DailyRewardConfig.GetReward(day: number): DailyRewardEntry
	local clamped = math.clamp(math.floor(day), 1, DailyRewardConfig.MAX_STREAK_DAY)
	return DailyRewardConfig.REWARDS_BY_DAY[clamped]
end

return DailyRewardConfig
