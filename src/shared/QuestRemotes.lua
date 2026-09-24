--[[
	Abyssara – Deep Tide Tycoon
	Modul: QuestRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für die Client<->Server-Kommunikationskanäle
		des Tages-Quest-Systems UND der Tages-Login-Belohnung (GDD Abschnitt
		9, Punkt 11) - beide bewusst in EINER Datei gebündelt (siehe Auftrag:
		"falls sinnvoll gebündelt auch weniger Dateien"), da beide Systeme
		täglich um 00:00 UTC zurückgesetzt werden und typischerweise über
		dasselbe "Tages-Fortschritt"-UI-Panel bedient werden. Identisches
		Bootstrap-Muster zu RaidRemotes/BreedingRemotes/HUDRemotes (Remotes
		als Kinder dieses ModuleScripts selbst, Server legt sie an, Client
		wartet nur per WaitForChild).

	Rojo-Einhängepunkt:
		src/shared/QuestRemotes.lua -> ReplicatedStorage.QuestRemotes

	Exportierte Kanäle - Tages-Quests:
		GetQuestState (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert den vollständigen Tages-Quest-Zustand des
			anfragenden Spielers (initialer UI-Sync):
				{
					DateKey: string, -- "YYYY-MM-DD" (UTC) des aktuellen Quest-Sets
					Quests: {
						{
							TemplateId: string,
							Description: string, -- bereits mit Target formatiert
							Target: number,
							Progress: number,
							Completed: boolean, -- Progress >= Target
							Claimed: boolean,
							RewardTideCoins: number,
							RewardAbyssalShards: number,
							RewardXP: number,
						}
					}
				}
		QuestProgressUpdated (RemoteEvent, Server -> Client)
			Push bei JEDER Fortschrittsänderung EINER Quest: { TemplateId,
			Progress, Target, Completed }. Der Client merged dies additiv in
			seinen lokalen GetQuestState-Snapshot statt erneut anzufordern.
		RequestClaimQuestReward (RemoteEvent, Client -> Server)
			Payload: (templateId: string) - die angeblich abgeschlossene
			Quest, deren Belohnung abgeholt werden soll. Reine
			Absichtserklärung - der Server validiert Progress/Target/Claimed
			komplett neu gegen den eigenen, persistenten Quest-Zustand.
		ClaimQuestRewardResult (RemoteEvent, Server -> Client)
			Antwort auf RequestClaimQuestReward: { Success: boolean,
			Reason: string?, TemplateId: string?, RewardTideCoins: number?,
			RewardAbyssalShards: number?, RewardXP: number?,
			NewTideCoinBalance: number? }.

	Exportierte Kanäle - Tages-Login-Belohnung (Streak):
		GetDailyRewardState (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert:
				{
					CanClaim: boolean,
					PendingStreakDay: number, -- 1..7, der Tag, der als NÄCHSTES abgeholt werden kann
					PreviewTideCoins: number, -- bereits inkl. VIP-Bonus, falls zutreffend
					PreviewAbyssalShards: number,
					VipBonusActive: boolean,
					AlreadyClaimedToday: boolean,
				}
		RequestClaimDailyReward (RemoteEvent, Client -> Server)
			Payload: keine. Reine Absichtserklärung - der Server prüft
			`CanClaim` komplett neu, der Client kann hier nichts vortäuschen.
		DailyRewardClaimed (RemoteEvent, Server -> Client)
			Antwort auf RequestClaimDailyReward: { Success: boolean,
			Reason: string?, StreakDay: number?, RewardTideCoins: number?,
			RewardAbyssalShards: number?, NewTideCoinBalance: number? }.
]]

local RunService = game:GetService("RunService")

local QuestRemotes = {}

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

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
	QuestRemotes.GetQuestState = getOrCreateRemoteFunction(script, "GetQuestState")
	QuestRemotes.QuestProgressUpdated = getOrCreateRemoteEvent(script, "QuestProgressUpdated")
	QuestRemotes.RequestClaimQuestReward = getOrCreateRemoteEvent(script, "RequestClaimQuestReward")
	QuestRemotes.ClaimQuestRewardResult = getOrCreateRemoteEvent(script, "ClaimQuestRewardResult")

	QuestRemotes.GetDailyRewardState = getOrCreateRemoteFunction(script, "GetDailyRewardState")
	QuestRemotes.RequestClaimDailyReward = getOrCreateRemoteEvent(script, "RequestClaimDailyReward")
	QuestRemotes.DailyRewardClaimed = getOrCreateRemoteEvent(script, "DailyRewardClaimed")
else
	QuestRemotes.GetQuestState = script:WaitForChild("GetQuestState") :: RemoteFunction
	QuestRemotes.QuestProgressUpdated = script:WaitForChild("QuestProgressUpdated") :: RemoteEvent
	QuestRemotes.RequestClaimQuestReward = script:WaitForChild("RequestClaimQuestReward") :: RemoteEvent
	QuestRemotes.ClaimQuestRewardResult = script:WaitForChild("ClaimQuestRewardResult") :: RemoteEvent

	QuestRemotes.GetDailyRewardState = script:WaitForChild("GetDailyRewardState") :: RemoteFunction
	QuestRemotes.RequestClaimDailyReward = script:WaitForChild("RequestClaimDailyReward") :: RemoteEvent
	QuestRemotes.DailyRewardClaimed = script:WaitForChild("DailyRewardClaimed") :: RemoteEvent
end

return QuestRemotes
