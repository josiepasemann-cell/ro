--[[
	Abyssara – Deep Tide Tycoon
	Modul: ProgressionService
	Zuständigkeit:
		Kernlogik des Progression-/Level-Systems (GDD Abschnitt 6
		"Fortschrittssystem" + Abschnitt 9, Punkt 7 "Progression-/Level-
		System"): einziger Ort, an dem XP tatsächlich vergeben und in
		Level-Ups umgerechnet wird. Nutzt für JEDE Persistenz-Operation
		ausschließlich die bestehende PlayerDataService-API (GetLevel,
		AddXP, SetLevel) - erfindet keine eigene Persistenz (siehe Auftrag:
		"Baue die Level-Kurve darauf auf, erfinde keine zweite Persistenz").

		Andere Systeme (PlacementService, BreedingService, RaidService,
		GachaService) rufen NACH einem erfolgreich abgeschlossenen Ereignis
		(nicht beim bloßen Request!) genau einen einzigen, klar benannten
		Einhängepunkt auf: ProgressionService.AwardXP(player, source). Dieses
		Modul kennt umgekehrt KEINEN dieser Aufrufer (kein require in diese
		Richtung) - reine Einbahnstraße, verhindert zirkuläre requires.

		Feuert bei jedem AwardXP-Aufruf einen HUD-Zustands-Push
		(HUDRemotes.HUDStateChanged) sowie - NUR bei tatsächlichem Level-Up -
		zusätzlich HUDRemotes.LevelUp mit den in diesem Levelbereich neu
		freigeschalteten Dingen (ProgressionConfig.UNLOCKS). Ein einzelner
		AwardXP-Aufruf kann dabei MEHRERE Level-Ups auf einmal auslösen (z. B.
		nach einem besonders großen XP-Batch) - alle dabei überschrittenen
		Unlock-Einträge werden gesammelt in EINEM Banner gemeldet statt
		mehrerer Popups hintereinander.

	Sicherheitsprinzip (kein Client-Trust):
		AwardXP nimmt niemals einen XP-Betrag vom Client entgegen - `source`
		ist ein server-intern gewählter, fester String (siehe
		ProgressionConfig.XP_REWARDS), niemals ein roher Zahlenwert aus einer
		Remote-Payload. Es gibt bewusst KEINEN Client->Server-Remote-Kanal,
		über den ein Spieler selbst AwardXP auslösen könnte.

	Rojo-Einhängepunkt:
		src/server/ProgressionService.lua -> ServerScriptService.ProgressionService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))

type ProgressionEventSource = ProgressionConfig.ProgressionEventSource

local ProgressionService = {}

--- Baut die HUD-relevanten Level-/XP-Felder für einen Spieler auf (Level,
--- All-Time-XP, XP innerhalb des aktuellen Levels, XP-Bedarf für den
--- nächsten Level-Up). Gemeinsam genutzt von AwardXP (Push) und
--- HUDServer.server.lua (initialer GetHUDState-Sync), damit beide Stellen
--- garantiert identisch rechnen.
function ProgressionService.GetLevelProgress(player: Player): { Level: number, XP: number, XPIntoLevel: number, XPToNextLevel: number }
	local level = PlayerDataService.GetLevel(player)
	local xp = PlayerDataService.GetXP(player)
	local xpIntoLevel, xpToNextLevel = ProgressionConfig.GetProgressWithinLevel(xp, level)
	return {
		Level = level,
		XP = xp,
		XPIntoLevel = xpIntoLevel,
		XPToNextLevel = xpToNextLevel,
	}
end

--- Sammelt alle ProgressionConfig.UNLOCKS-Einträge, deren Level irgendwo im
--- (exklusiven) Bereich `fromLevelExclusive + 1 .. toLevelInclusive` liegt -
--- also alle Freischaltungen, die durch einen (ggf. mehrstufigen) Level-Up
--- gerade neu erreicht wurden.
local function collectUnlocksInRange(fromLevelExclusive: number, toLevelInclusive: number): { ProgressionConfig.UnlockEntry }
	local unlocks = {}
	for _, entry in ipairs(ProgressionConfig.UNLOCKS) do
		if entry.Level > fromLevelExclusive and entry.Level <= toLevelInclusive then
			table.insert(unlocks, entry)
		end
	end
	return unlocks
end

--- Kernfunktion: vergibt die für `source` konfigurierte XP-Menge
--- (ProgressionConfig.XP_REWARDS) an `player`, verarbeitet dabei ggf.
--- mehrere Level-Ups auf einmal, und pusht das Ergebnis vollständig an den
--- Client (HUD-Zustand IMMER, Level-Up-Banner NUR bei tatsächlichem
--- Level-Up). Gibt true zurück, wenn XP vergeben wurde (false bei
--- ungeladenen Daten oder unbekanntem `source` - z. B. ein Tippfehler bei
--- einem künftigen Einhängepunkt).
function ProgressionService.AwardXP(player: Player, source: ProgressionEventSource): boolean
	if not PlayerDataService.IsDataLoaded(player) then
		return false
	end

	local reward = ProgressionConfig.XP_REWARDS[source]
	if not reward then
		warn(("[ProgressionService] Unbekannte XP-Quelle '%s' - keine XP vergeben."):format(tostring(source)))
		return false
	end

	local oldLevel = PlayerDataService.GetLevel(player)

	-- Oberhalb MAX_LEVEL wird weiterhin XP gutgeschrieben (Rohwert bleibt für
	-- ein künftiges Prestige-System erhalten, siehe ProgressionConfig-
	-- Kopfkommentar), aber es entstehen im MVP keine weiteren Level-Ups mehr
	-- - GetLevelForTotalXP deckelt intern bereits auf MAX_LEVEL.
	local totalXP = PlayerDataService.AddXP(player, reward)
	if totalXP == nil then
		return false
	end

	local newLevel = ProgressionConfig.GetLevelForTotalXP(totalXP)
	if newLevel > oldLevel then
		PlayerDataService.SetLevel(player, newLevel)
	end

	local progress = ProgressionService.GetLevelProgress(player)

	HUDRemotes.HUDStateChanged:FireClient(player, {
		Level = progress.Level,
		XP = progress.XP,
		XPIntoLevel = progress.XPIntoLevel,
		XPToNextLevel = progress.XPToNextLevel,
	})

	if newLevel > oldLevel then
		local unlocks = collectUnlocksInRange(oldLevel, newLevel)
		local unlockPayload = {}
		for _, entry in ipairs(unlocks) do
			table.insert(unlockPayload, { Label = entry.Label, Implemented = entry.Implemented })
		end

		HUDRemotes.LevelUp:FireClient(player, {
			NewLevel = newLevel,
			Unlocks = unlockPayload,
		})
	end

	return true
end

return ProgressionService
