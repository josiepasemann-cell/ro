--[[
	Abyssara – Deep Tide Tycoon
	Modul: GameEvents
	Zuständigkeit:
		Zentraler, rein server-interner Ereignis-Hub (BindableEvent-Signal-
		Registry) für alle Gameplay-Systeme, die NACH einem bereits
		abgeschlossenen (nicht: angefragten) Spielereignis benachrichtigt
		werden wollen - insbesondere QuestService (Tagesquest-Fortschritt) und
		LeaderboardService (Rangliste-Dirty-Tracking), die beide NUR zuhören
		und selbst niemals ein Ereignis auslösen.

		Ersetzt das Streuen von Quest-/Leaderboard-Aufrufen in JEDEN einzelnen
		Gameplay-Service (GachaService, BreedingService, RaidService,
		PlacementService, PickupSpawner, PlayerDataService): diese Services
		feuern stattdessen an ihren bereits bestehenden Erfolgsstellen (dort,
		wo heute schon ProgressionService.AwardXP aufgerufen wird, plus dem
		Sporen-Abgabe-Erfolg in PickupSpawner und jeder positiven Währungs-
		gutschrift in PlayerDataService.AddCurrency) genau EIN generisches
		GameEvents.Fire(eventName, player, payload) - dieses Modul kennt selbst
		KEINEN einzigen Abonnenten (keine Requires in diese Richtung), reine
		Einbahnstraße/Entkopplung, identisches Prinzip zu
		PlayerDataService.DataChanged/MonetizationService.PurchaseGranted.

		KEINE zirkulären requires: GameEvents selbst requiret NICHTS aus
		diesem Projekt (keine Abhängigkeiten), kann daher von JEDEM anderen
		Server-Modul (auch PlayerDataService, das selbst von fast allen
		anderen Services benötigt wird) gefahrlos requiret werden.

	Definierte Ereignis-Namen (siehe Auftrag Punkt 1) - reine String-Konstanten,
	keine geschlossene Aufzählung (Aufrufer können theoretisch weitere Namen
	verwenden, die Konstanten unten sind nur Tippfehler-Schutz für die
	bekannten MVP-Ereignisse):
		BuildingPlaced   (player, { BuildingId: string, PlacementId: string })
		BuildingUpgraded (player, { BuildingId: string, PlacementId: string, NewStage: number })
		BreedingCompleted(player, { CreatureId: string, Rarity: string, PlacementId: string, Instant: boolean? })
		RaidWon          (player, { WavesCleared: number, RewardTideCoins: number?, Offline: boolean? })
		RaidLost         (player, { AbductedInstanceId: string?, Offline: boolean? })
		EggOpened        (player, { Rarity: string, CreatureId: string, ResultType: "New" | "Duplicate", Purchased: boolean })
		SporeDelivered   (player, { Amount: number })
		CoinsEarned      (player, { Amount: number, NewLifetimeTotal: number })

	Rojo-Einhängepunkt:
		src/server/GameEvents.lua -> ServerScriptService.GameEvents
]]

export type EventName =
	"BuildingPlaced"
	| "BuildingUpgraded"
	| "BreedingCompleted"
	| "RaidWon"
	| "RaidLost"
	| "EggOpened"
	| "SporeDelivered"
	| "CoinsEarned"

local GameEvents = {}

-- // Bekannte Ereignis-Namen (Tippfehler-Schutz für Aufrufer, siehe Kopfkommentar) --
GameEvents.Events = {
	BuildingPlaced = "BuildingPlaced" :: EventName,
	BuildingUpgraded = "BuildingUpgraded" :: EventName,
	BreedingCompleted = "BreedingCompleted" :: EventName,
	RaidWon = "RaidWon" :: EventName,
	RaidLost = "RaidLost" :: EventName,
	EggOpened = "EggOpened" :: EventName,
	SporeDelivered = "SporeDelivered" :: EventName,
	CoinsEarned = "CoinsEarned" :: EventName,
}

local registry: { [string]: BindableEvent } = {}

local function ensureSignal(eventName: string): BindableEvent
	local signal = registry[eventName]
	if not signal then
		signal = Instance.new("BindableEvent")
		registry[eventName] = signal
	end
	return signal
end

--- Feuert `eventName` für `player` mit einem beliebigen Payload-Table.
--- Abonnenten, die (noch) nicht existieren, verpassen das Ereignis einfach
--- (kein Buffering/Replay - alle aktuellen Abonnenten (QuestService,
--- LeaderboardService) verbinden sich bereits beim Server-Start, lange bevor
--- Spieler-Ereignisse eintreten können).
function GameEvents.Fire(eventName: EventName | string, player: Player, payload: { [string]: any }?)
	ensureSignal(eventName):Fire(player, payload or {})
end

--- Abonniert `eventName`. Gibt die RBXScriptConnection zurück (z. B. für
--- ein künftiges CleanupPlayer/Destroy-Muster, auch wenn die aktuellen
--- Abonnenten dauerhaft für die gesamte Server-Lebensdauer verbunden bleiben).
function GameEvents.Connect(eventName: EventName | string, handler: (player: Player, payload: { [string]: any }) -> ()): RBXScriptConnection
	return ensureSignal(eventName).Event:Connect(handler)
end

return GameEvents
