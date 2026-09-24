--[[
	Abyssara – Deep Tide Tycoon
	Modul: QuestService
	Zuständigkeit:
		Kernlogik des Tages-Quest-Systems (GDD Abschnitt 3 "Tägliche Quests"
		+ Abschnitt 9, Punkt 11 + Abschnitt 10 MVP-Scope "3 Quest-Typen"):
		täglich 3 zufällige Quest-Vorlagen aus QuestConfig.QUEST_TEMPLATES pro
		Spieler (Reset um 00:00 UTC, siehe PlayerDataService.GetUtcDateString
		- identisches Datums-Prinzip wie die bereits bestehenden
		MonetizationState-Tagesbegrenzungen), Fortschritts-Tracking rein
		ereignisgetrieben über GameEvents (KEIN Polling), sowie serverseitig
		validiertes Abholen der Belohnung.

		Hört AUSSCHLIESSLICH auf GameEvents (siehe GameEvents-Kopfkommentar,
		"Ereignis-Hub") - kennt selbst KEINEN der feuernden Services
		(GachaService/BreedingService/RaidService/PlacementService/
		PickupSpawner) und wird umgekehrt auch von keinem davon requiret:
		reine Einbahnstraße, keine zirkulären requires.

	Sicherheitsprinzip (kein Client-Trust):
		Fortschritt wird AUSSCHLIESSLICH aus serverseitig bereits validierten
		GameEvents-Payloads berechnet (der Client liefert dafür nichts ein).
		RequestClaimQuestReward nimmt eine `templateId` vom Client entgegen,
		validiert sie aber komplett neu gegen den eigenen, persistenten
		QuestState (Progress >= Target, noch nicht Claimed), bevor irgendeine
		Belohnung gewährt wird.

	Rojo-Einhängepunkt:
		src/server/QuestService.lua -> ServerScriptService.QuestService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local QuestConfig = require(ReplicatedStorage:WaitForChild("QuestConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local QuestRemotes = require(ReplicatedStorage:WaitForChild("QuestRemotes"))

type QuestProgress = PlayerDataService.QuestProgress
type QuestState = PlayerDataService.QuestState

export type ClaimFailureReason = "DataNotLoaded" | "UnknownQuest" | "NotCompleted" | "AlreadyClaimed"

local QuestService = {}

local rng = Random.new()

-- // Hilfsfunktionen ------------------------------------------------------

--- Fisher-Yates-Teilshuffle: liefert `count` EINDEUTIGE Vorlagen aus
--- QuestConfig.QUEST_TEMPLATES (kein Duplikat am selben Tag). Bricht defensiv
--- ab, falls der Pool kleiner als `count` ist (aktuell 4 Vorlagen > 3, siehe
--- QuestConfig.QUESTS_PER_DAY).
local function pickRandomTemplates(count: number): { QuestConfig.QuestTemplate }
	local pool = table.clone(QuestConfig.QUEST_TEMPLATES)
	local picked = {}
	local n = math.min(count, #pool)
	for _ = 1, n do
		local index = rng:NextInteger(1, #pool)
		local template = table.remove(pool, index) :: QuestConfig.QuestTemplate
		table.insert(picked, template)
	end
	return picked
end

--- Würfelt EIN frisches 3er-Quest-Set für den heutigen Tag und persistiert es
--- sofort. Wird sowohl beim Login als auch defensiv vor jeder
--- Fortschritts-/Claim-Verarbeitung aufgerufen (siehe ensureTodayQuests), da
--- ein Spieler theoretisch über einen UTC-Tageswechsel hinweg online bleiben
--- kann.
local function assignDailyQuests(player: Player, today: string)
	local templates = pickRandomTemplates(QuestConfig.QUESTS_PER_DAY)
	local quests: { QuestProgress } = {}
	for _, template in ipairs(templates) do
		local target = rng:NextInteger(template.TargetMin, template.TargetMax)
		table.insert(quests, { TemplateId = template.Id, Target = target, Progress = 0, Claimed = false })
	end

	PlayerDataService.SetQuestState(player, { DateKey = today, Quests = quests })
end

--- Stellt sicher, dass der QuestState von `player` zum HEUTIGEN UTC-Tag
--- gehört - würfelt bei Abweichung (neuer Tag ODER erster Login überhaupt)
--- ein frisches Set. Günstige, rein string-vergleichende Prüfung - sicher,
--- oft aufzurufen (siehe alle Call-Sites unten).
local function ensureTodayQuests(player: Player): string
	local today = PlayerDataService.GetUtcDateString()
	local state = PlayerDataService.GetQuestState(player)
	if state.DateKey ~= today then
		assignDailyQuests(player, today)
	end
	return today
end

local function findQuestProgress(state: QuestState, templateId: string): QuestProgress?
	for _, quest in ipairs(state.Quests) do
		if quest.TemplateId == templateId then
			return quest
		end
	end
	return nil
end

local function buildClientQuestEntry(quest: QuestProgress): { [string]: any }?
	local template = QuestConfig.GetTemplate(quest.TemplateId)
	if not template then
		-- Vorlage wurde aus QuestConfig entfernt (z. B. Balancing-Update) -
		-- defensiv überspringen statt mit nil-Werten an den Client zu senden.
		return nil
	end
	return {
		TemplateId = quest.TemplateId,
		Description = QuestConfig.FormatDescription(template, quest.Target),
		Target = quest.Target,
		Progress = quest.Progress,
		Completed = quest.Progress >= quest.Target,
		Claimed = quest.Claimed,
		RewardTideCoins = template.RewardTideCoins,
		RewardAbyssalShards = template.RewardAbyssalShards,
		RewardXP = ProgressionConfig.XP_REWARDS.QuestCompleted,
	}
end

-- // Fortschritts-Verarbeitung (GameEvents-Abonnent) -----------------------

--- Erhöht den Fortschritt ALLER aktiven, noch nicht abgeschlossenen Quests
--- von `player`, deren EventName zu `eventName` passt, um `amount` (geklemmt
--- auf das jeweilige Target - kein "Overflow" über das Ziel hinaus). Pusht
--- QuestProgressUpdated je tatsächlich veränderter Quest.
local function advanceProgress(player: Player, eventName: string, amount: number)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local today = ensureTodayQuests(player)
	local state = PlayerDataService.GetQuestState(player)
	if state.DateKey ~= today then
		-- Sollte nach ensureTodayQuests nicht mehr eintreten - defensiv.
		return
	end

	local changed = false
	for _, quest in ipairs(state.Quests) do
		if not quest.Claimed then
			local template = QuestConfig.GetTemplate(quest.TemplateId)
			if template and template.EventName == eventName and quest.Progress < quest.Target then
				quest.Progress = math.min(quest.Target, quest.Progress + amount)
				changed = true

				QuestRemotes.QuestProgressUpdated:FireClient(player, {
					TemplateId = quest.TemplateId,
					Progress = quest.Progress,
					Target = quest.Target,
					Completed = quest.Progress >= quest.Target,
				})
			end
		end
	end

	if changed then
		PlayerDataService.SetQuestState(player, state)
	end
end

local function onGameEvent(eventName: string, defaultAmountKey: string?)
	GameEvents.Connect(eventName, function(player: Player, payload: { [string]: any })
		local amount = 1
		if defaultAmountKey and type(payload[defaultAmountKey]) == "number" then
			amount = payload[defaultAmountKey]
		end
		advanceProgress(player, eventName, amount)
	end)
end

-- Jedes Ereignis zählt standardmäßig als "+1" pro Auftreten (ein Gebäude
-- platziert = +1, eine Zucht abgeschlossen = +1, ein Raid gewonnen = +1) -
-- NUR "SporeDelivered" trägt ein variables `Amount`-Feld im Payload (siehe
-- GameEvents-Kopfkommentar), das hier statt der festen 1 verwendet wird.
onGameEvent(GameEvents.Events.SporeDelivered, "Amount")
onGameEvent(GameEvents.Events.BreedingCompleted, nil)
onGameEvent(GameEvents.Events.RaidWon, nil)
onGameEvent(GameEvents.Events.BuildingPlaced, nil)

-- // Öffentliche API --------------------------------------------------------

--- Liefert den vollständigen Client-Zustand für den initialen UI-Sync (siehe
--- QuestRemotes.GetQuestState).
function QuestService.GetState(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { DateKey = PlayerDataService.GetUtcDateString(), Quests = {} }
	end

	local today = ensureTodayQuests(player)
	local state = PlayerDataService.GetQuestState(player)

	local quests = {}
	for _, quest in ipairs(state.Quests) do
		local entry = buildClientQuestEntry(quest)
		if entry then
			table.insert(quests, entry)
		end
	end

	return { DateKey = today, Quests = quests }
end

--- Validiert und schließt das Abholen EINER Quest-Belohnung vollständig
--- serverseitig ab. `templateId` ist ein unvertrauter, angeblicher
--- Client-Wert - wird komplett neu gegen den eigenen, persistenten QuestState
--- geprüft.
function QuestService.RequestClaim(player: Player, templateId: any): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if type(templateId) ~= "string" then
		return { Success = false, Reason = "UnknownQuest" }
	end

	ensureTodayQuests(player)
	local state = PlayerDataService.GetQuestState(player)

	local quest = findQuestProgress(state, templateId)
	local template = quest and QuestConfig.GetTemplate(templateId)
	if not quest or not template then
		return { Success = false, Reason = "UnknownQuest" }
	end
	if quest.Claimed then
		return { Success = false, Reason = "AlreadyClaimed" }
	end
	if quest.Progress < quest.Target then
		return { Success = false, Reason = "NotCompleted" }
	end

	quest.Claimed = true
	PlayerDataService.SetQuestState(player, state)

	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", template.RewardTideCoins)
	if template.RewardAbyssalShards > 0 then
		PlayerDataService.AddCurrency(player, "AbyssalShards", template.RewardAbyssalShards)
	end
	ProgressionService.AwardXP(player, "QuestCompleted")

	return {
		Success = true,
		TemplateId = templateId,
		RewardTideCoins = template.RewardTideCoins,
		RewardAbyssalShards = template.RewardAbyssalShards,
		RewardXP = ProgressionConfig.XP_REWARDS.QuestCompleted,
		NewTideCoinBalance = newBalance,
	}
end

-- // Login-Hook (stellt sicher, dass ein Spieler bei Bedarf sofort ein
-- frisches Set hat, statt erst beim ersten GetQuestState-Aufruf) ------------

local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, 15)
	if not data then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end
	ensureTodayQuests(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

return QuestService
