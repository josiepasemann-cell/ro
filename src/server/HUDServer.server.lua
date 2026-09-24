--[[
	Abyssara – Deep Tide Tycoon
	Skript: HUDServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des zentralen HUDs auf Server-Seite (GDD
		Abschnitt 9, Punkt 13 "HUD (Währung, XP-Leiste)"):
			1. Beantwortet HUDRemotes.GetHUDState (RemoteFunction) mit dem
			   vollständigen, aktuellen HUD-Zustand eines Spielers - für den
			   initialen Sync beim Join/UI-Aufbau.
			2. Abonniert PlayerDataService.DataChanged (siehe dort, Auftrag
			   Punkt 5: "zentraler Weg, den Client bei jeder AddCurrency-
			   Änderung zu informieren") und leitet JEDE Währungsänderung
			   eines Spielers als partiellen HUDRemotes.HUDStateChanged-Push
			   an dessen Client weiter - inkl. frisch berechnetem
			   Einkommen/Minute (IdleIncomeService.GetIncomePerMinute), da
			   Bau-/Verkaufsaktionen (PlacementService) ebenfalls über
			   PlayerDataService.AddCurrency laufen und damit automatisch
			   dieses Signal auslösen. KEIN zusätzlicher Hook in
			   PlacementService nötig.

		Level-/XP-Änderungen laufen NICHT über diesen Pfad, sondern werden
		von ProgressionService.AwardXP direkt gepusht (siehe dort) - dieses
		Skript enthält daher bewusst KEINE Progression-Logik selbst.

	Rojo-Einhängepunkt:
		src/server/HUDServer.server.lua -> ServerScriptService.HUDServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		GetHUDState liefert AUSSCHLIESSLICH bereits serverseitig berechnete/
		persistente Werte des jeweils ANFRAGENDEN Spielers (`player` kommt
		unfälschbar aus RemoteFunction.OnServerInvoke) - es gibt keinerlei
		Client-Eingabe, die hier verarbeitet würde.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local IdleIncomeService = require(script.Parent:WaitForChild("IdleIncomeService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))

local JOIN_DATA_TIMEOUT_SECONDS = 15

--- Baut den vollständigen HUD-Zustand eines Spielers auf (GetHUDState-
--- Antwort). Voraussetzung: Spielerdaten bereits geladen - Aufrufer prüfen
--- das jeweils selbst (siehe unten).
local function buildFullState(player: Player)
	local progress = ProgressionService.GetLevelProgress(player)
	return {
		TideCoins = PlayerDataService.GetCurrency(player, "TideCoins"),
		AbyssalShards = PlayerDataService.GetCurrency(player, "AbyssalShards"),
		Level = progress.Level,
		XP = progress.XP,
		XPIntoLevel = progress.XPIntoLevel,
		XPToNextLevel = progress.XPToNextLevel,
		IncomePerMinute = IdleIncomeService.GetIncomePerMinute(player),
		MaxLevel = ProgressionConfig.MAX_LEVEL,
		OnboardingCompleted = PlayerDataService.GetOnboardingCompleted(player),
	}
end

HUDRemotes.MarkOnboardingCompleted.OnServerEvent:Connect(function(player: Player)
	PlayerDataService.SetOnboardingCompleted(player)
end)

HUDRemotes.GetHUDState.OnServerInvoke = function(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		-- Seltener Timing-Fall: Client fragt HUD-Zustand an, bevor das Laden
		-- abgeschlossen ist. Kurz auf das Laden warten statt einen leeren/
		-- inkonsistenten Zustand zurückzugeben.
		local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
		if not data then
			return nil
		end
	end
	return buildFullState(player)
end

--- Leitet jede Währungsänderung (PlayerDataService.DataChanged, "Currency")
--- als partiellen HUD-Push weiter, inkl. frisch berechnetem Einkommen/
--- Minute (kann sich durch die auslösende Aktion selbst geändert haben, z.
--- B. ein neu gebautes Produktionsgebäude - siehe Kopfkommentar).
PlayerDataService.DataChanged:Connect(function(player: Player, changeKind: string, payload: { [string]: any })
	if changeKind ~= "Currency" then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end

	local statePush: { [string]: any } = {
		IncomePerMinute = IdleIncomeService.GetIncomePerMinute(player),
	}
	statePush[payload.CurrencyType] = payload.NewBalance

	HUDRemotes.HUDStateChanged:FireClient(player, statePush)
end)

print("[Abyssara] HUDServer bereit (GetHUDState verdrahtet, DataChanged-Weiterleitung aktiv).")
