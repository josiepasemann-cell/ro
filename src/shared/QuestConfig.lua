--[[
	Abyssara – Deep Tide Tycoon
	Modul: QuestConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für das Tages-Quest-
		System (GDD Abschnitt 3 "Tägliche Quests" + Abschnitt 9, Punkt 11 +
		Abschnitt 10 MVP-Scope "Tägliche Quests (3 Quest-Typen)"): der Pool
		möglicher Quest-Vorlagen, deren Fortschritts-Ereignisquelle (siehe
		GameEvents), Ziel-Spannen und Belohnungen. Enthält bewusst KEINE
		Zufalls-/Persistenz-/Fortschritts-Logik selbst (die lebt in
		QuestService) - nur Daten + kleine, reine Hilfsfunktionen, identisches
		Prinzip zu GachaConfig/BreedingConfig/RaidConfig.

		MVP-Scope-Entscheidung: das GDD nennt "3 Quest-Typen" ohne sie exakt
		festzulegen, der Auftrag nennt als Beispiele "Sporen abgeben, Zucht
		abschließen, Raid überleben/gewinnen, Gebäude bauen" - also vier
		mögliche Kandidaten. Dieser Pool führt alle vier als Vorlagen, damit
		QuestService täglich 3 DAVON zufällig auswählt (siehe
		QuestService.assignDailyQuests) - das erfüllt "3 Quest-Typen im MVP"
		pro Tag, mit Abwechslung über mehrere Tage hinweg statt einer
		statischen Dreierliste.

	Rojo-Einhängepunkt:
		src/shared/QuestConfig.lua -> ReplicatedStorage.QuestConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies NUR für Anzeige-Zwecke (Beschreibung/Ziel/Belohnung), die
		alleinige Autorität über Fortschritt/Claim bleibt serverseitig in
		QuestService.)
]]

export type QuestTemplate = {
	Id: string,
	EventName: string, -- GameEvents.Events-Name, dessen Fortschritt gezählt wird
	DescriptionFormat: string, -- enthält genau ein "%d" für den gewürfelten Target-Wert
	TargetMin: number,
	TargetMax: number,
	RewardTideCoins: number,
	RewardAbyssalShards: number,
	-- KEIN eigenes RewardXP-Feld hier: der XP-Bonus fürs Abschließen EINER
	-- Quest ist bewusst EIN fester, ereignis-KLASSEN-weiter Wert
	-- (ProgressionConfig.XP_REWARDS.QuestCompleted), damit ProgressionService
	-- weiterhin die einzige Quelle der Wahrheit für tatsächlich vergebene XP
	-- bleibt - QuestService liest diesen Wert nur lesend für den Claim-
	-- Result-Payload/die Anzeige aus.
}

local QuestConfig = {}

QuestConfig.QUESTS_PER_DAY = 3

-- // Quest-Vorlagen-Pool (siehe MVP-Scope-Entscheidung im Kopfkommentar) -----
QuestConfig.QUEST_TEMPLATES = {
	{
		Id = "DeliverSpores",
		EventName = "SporeDelivered",
		DescriptionFormat = "Liefere %d Glow Spores an einer Lichtboje ab",
		TargetMin = 5,
		TargetMax = 12,
		RewardTideCoins = 80,
		RewardAbyssalShards = 0,
	},
	{
		Id = "CompleteBreeding",
		EventName = "BreedingCompleted",
		DescriptionFormat = "Schließe %d Zucht(en) im Brutbecken ab",
		TargetMin = 1,
		TargetMax = 2,
		RewardTideCoins = 150,
		RewardAbyssalShards = 1,
	},
	{
		Id = "WinRaid",
		EventName = "RaidWon",
		DescriptionFormat = "Überstehe %d Trench Raid(s) erfolgreich",
		TargetMin = 1,
		TargetMax = 1,
		RewardTideCoins = 200,
		RewardAbyssalShards = 2,
	},
	{
		Id = "PlaceBuilding",
		EventName = "BuildingPlaced",
		DescriptionFormat = "Platziere %d Gebäude auf deinem Habitat",
		TargetMin = 1,
		TargetMax = 3,
		RewardTideCoins = 60,
		RewardAbyssalShards = 0,
	},
} :: { QuestTemplate }

--- Liefert die Quest-Vorlage für `id`, oder nil, falls unbekannt (z. B. ein
--- älterer, mittlerweile aus dem Pool entfernter Eintrag in gespeicherten
--- Spielerdaten - QuestService behandelt das defensiv, siehe dort).
function QuestConfig.GetTemplate(id: string): QuestTemplate?
	for _, template in ipairs(QuestConfig.QUEST_TEMPLATES) do
		if template.Id == id then
			return template
		end
	end
	return nil
end

--- Rendert die Beschreibung einer Quest-Vorlage mit dem tatsächlich
--- gewürfelten Ziel-Wert (siehe QuestService.assignDailyQuests).
function QuestConfig.FormatDescription(template: QuestTemplate, target: number): string
	return template.DescriptionFormat:format(target)
end

return QuestConfig
