--[[
	Abyssara – Deep Tide Tycoon
	Modul: HUDRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle für das zentrale HUD (GDD Abschnitt 9, Punkt 13: "HUD
		(Währung, XP-Leiste)") sowie das Progression-/Level-System (Abschnitt
		9, Punkt 7) definiert werden. Sowohl Server (HUDServer.server.lua,
		ProgressionService) als auch Client (HUDController.client.lua)
		requiren AUSSCHLIESSLICH dieses Modul - identisches Bootstrap-Muster
		zu BreedingRemotes/GachaRemotes/IdleIncomeRemotes/RaidRemotes (siehe
		dort für die ausführliche Begründung: Remotes als Kinder dieses
		ModuleScripts selbst, Server legt sie an, Client wartet nur per
		WaitForChild).

	Rojo-Einhängepunkt:
		src/shared/HUDRemotes.lua -> ReplicatedStorage.HUDRemotes

	Exportierte Kanäle:
		GetHUDState (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert den VOLLSTÄNDIGEN aktuellen HUD-Zustand
			des anfragenden Spielers für den initialen Sync beim Join/UI-
			Aufbau: { TideCoins: number, AbyssalShards: number, Level: number,
			XP: number, XPIntoLevel: number, XPToNextLevel: number,
			IncomePerMinute: number, MaxLevel: number,
			OnboardingCompleted: boolean }. Danach hält
			HUDStateChanged den Client aktuell - kein Polling nötig.
		HUDStateChanged (RemoteEvent, Server -> Client)
			Server-Push bei JEDER Änderung eines HUD-relevanten Werts
			(Währung, Level, XP, Einkommen/Minute). Payload ist bewusst
			PARTIELL (nur die Felder, die sich tatsächlich geändert haben,
			als Teilmenge derselben Struktur wie GetHUDState) - der Client
			merged sie additiv in seinen lokalen Anzeige-Zustand statt bei
			jedem Push alles neu anzufordern.
		LevelUp (RemoteEvent, Server -> Client)
			Feuert NUR bei einem tatsächlichen Level-Up (siehe
			ProgressionService.AwardXP): { NewLevel: number, Unlocks:
			{ { Label: string, Implemented: boolean } } } - für das kurze
			Level-Up-Banner mit freigeschalteten Dingen.
		MarkOnboardingCompleted (RemoteEvent, Client -> Server)
			Payload: keine. Merkt dauerhaft, dass der Spieler das Tutorial
			beendet oder übersprungen hat. Kann nur auf true setzen.
]]

local RunService = game:GetService("RunService")

local HUDRemotes = {}

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
	HUDRemotes.GetHUDState = getOrCreateRemoteFunction(script, "GetHUDState")
	HUDRemotes.HUDStateChanged = getOrCreateRemoteEvent(script, "HUDStateChanged")
	HUDRemotes.LevelUp = getOrCreateRemoteEvent(script, "LevelUp")
	HUDRemotes.MarkOnboardingCompleted = getOrCreateRemoteEvent(script, "MarkOnboardingCompleted")
else
	HUDRemotes.GetHUDState = script:WaitForChild("GetHUDState") :: RemoteFunction
	HUDRemotes.HUDStateChanged = script:WaitForChild("HUDStateChanged") :: RemoteEvent
	HUDRemotes.LevelUp = script:WaitForChild("LevelUp") :: RemoteEvent
	HUDRemotes.MarkOnboardingCompleted = script:WaitForChild("MarkOnboardingCompleted") :: RemoteEvent
end

return HUDRemotes
