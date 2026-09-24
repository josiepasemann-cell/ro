--[[
	Abyssara – Deep Tide Tycoon
	Modul: LeaderboardRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für den Client<->Server-Kommunikationskanal
		des globalen Ranglisten-Systems (GDD Abschnitt 7 "Leaderboards" +
		Abschnitt 9, Punkt 10). Identisches Bootstrap-Muster zu
		RaidRemotes/QuestRemotes.

	Rojo-Einhängepunkt:
		src/shared/LeaderboardRemotes.lua -> ReplicatedStorage.LeaderboardRemotes

	Kategorien (siehe LeaderboardService.Category):
		"Level"            - GDD: "Tiefste erreichte Zone" (MVP-Proxy: Spieler-
		                     Level, siehe LeaderboardService-Kopfkommentar zur
		                     Begründung, solange das Zonen-System selbst noch
		                     nicht existiert).
		"TideCoins"        - GDD: "Gesamt verdiente Tide Coins" (Lifetime-Summe,
		                     NICHT der aktuelle Kontostand - siehe
		                     PlayerDataService.Stats.LifetimeTideCoinsEarned).
		"RarestCollection" - GDD: "Seltenste Kreaturensammlung" (Punktwert nach
		                     Rarity, siehe LeaderboardService.computeScores).

	Exportierte Kanäle:
		GetLeaderboard (RemoteFunction, Client -> Server -> Client)
			Payload: (category: string). Liefert die zuletzt gelesene Top-50-
			Momentaufnahme dieser Kategorie (periodisch aktualisiert, siehe
			LeaderboardService - KEIN Live-DataStore-Read pro Anfrage, um das
			OrderedDataStore-Lesebudget zu schonen):
				{ Category: string, Entries: { { Rank: number, UserId: number,
				  Name: string, Score: number } }, UpdatedAt: number } | nil
			(nil/leere Entries, falls die Kategorie unbekannt ist ODER seit
			Serverstart noch kein erfolgreicher Lesevorgang stattgefunden hat).
]]

local RunService = game:GetService("RunService")

local LeaderboardRemotes = {}

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

if RunService:IsServer() then
	LeaderboardRemotes.GetLeaderboard = getOrCreateRemoteFunction(script, "GetLeaderboard")
else
	LeaderboardRemotes.GetLeaderboard = script:WaitForChild("GetLeaderboard") :: RemoteFunction
end

return LeaderboardRemotes
