--[[
	Abyssara – Deep Tide Tycoon
	Modul: RaidRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle (RemoteEvents/RemoteFunctions) für das Trench-Raid-System (GDD
		Abschnitt 9, Punkt 5) definiert werden. Sowohl Server
		(RaidServer.server.lua) als auch Client (RaidUIController.client.lua)
		requiren AUSSCHLIESSLICH dieses Modul statt Instance-Pfade doppelt zu
		hardcoden - identisches Bootstrap-Muster zu BreedingRemotes.lua/
		HabitatRemotes.lua (siehe dort für die ausführliche Begründung:
		Remotes als Kinder dieses ModuleScripts selbst, Server legt sie an,
		Client wartet nur per WaitForChild).

	Rojo-Einhängepunkt:
		src/shared/RaidRemotes.lua -> ReplicatedStorage.RaidRemotes

	Exportierte Kanäle:
		GetRaidStatus (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert den aktuellen Raid-Status des anfragenden
			Spielers (siehe RaidService.GetStatus): { NextRaidAt: number,
			InRaid: boolean, WaveIndex: number?, TotalWaves: number?,
			AbductedCreatures: {AbductedCreature} } - für den initialen
			HUD-Sync (Countdown, entführte Kreaturen) ohne Dauer-Polling.
		RaidStarted (RemoteEvent, Server -> Client)
			Ein Raid hat auf dem Plot des Spielers begonnen: { TotalWaves,
			WaveIndex, WaveEnemyCount, IsBossWave }.
		WaveAdvanced (RemoteEvent, Server -> Client)
			Die aktuelle Welle wurde vollständig besiegt, die nächste beginnt:
			{ WaveIndex, TotalWaves, WaveEnemyCount, IsBossWave }.
		EnemyHit (RemoteEvent, Server -> Client)
			Rein kosmetisch: ein Turm hat einen Gegner getroffen. Payload:
			{ TowerPosition: Vector3, EnemyPosition: Vector3 } - Client zeichnet
			daraus eine kurze Treffer-Visualisierung (Tracer/Funken). Trägt
			KEINE Spiel-Logik (Schaden ist bereits server-seitig angewendet).
		RaidResult (RemoteEvent, Server -> Client)
			Der Raid ist beendet: { Success: boolean, WavesCleared: number,
			RewardTideCoins: number?, RewardAbyssalShards: number?,
			AbductedCreature: { CreatureId, Rarity, RansomCost }?,
			NextRaidAt: number }.
		RequestRescueCreature (RemoteEvent, Client -> Server)
			Payload: (instanceId: string) - die angeblich eigene, entführte
			Kreatur, die der Spieler gegen Lösegeld freikaufen will. Reine
			Absichtserklärung - der Server validiert Eigentümerschaft
			(Lookup ausschließlich in der eigenen AbductedCreatures-Liste)
			und Kontostand komplett neu.
		RescueResult (RemoteEvent, Server -> Client)
			Antwort auf RequestRescueCreature: { Success: boolean,
			Reason: string?, InstanceId: string?, RansomCost: number?,
			NewBalance: number? }.
		RequestRescueWithToken (RemoteEvent, Client -> Server)
			PLATZHALTER-Kanal für das Robux-Entwicklerprodukt "Rettungs-Token"
			(GDD Abschnitt 5: "Rettungs-Token (entführte Kreatur sofort
			zurückholen), 49 Robux"). Aktuell antwortet der Server IMMER mit
			Reason = "NotImplemented" (siehe RaidService.RequestRescueWithToken)
			- kein MarketplaceService/ProcessReceipt-Handler existiert bisher
			im Projekt (identisches Platzhalter-Prinzip wie BreedingService.
			RequestInstantComplete).
		RescueWithTokenResult (RemoteEvent, Server -> Client)
			Antwort auf RequestRescueWithToken: { Success: boolean, Reason: string? }.
]]

local RunService = game:GetService("RunService")

local RaidRemotes = {}

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
	RaidRemotes.GetRaidStatus = getOrCreateRemoteFunction(script, "GetRaidStatus")
	RaidRemotes.RaidStarted = getOrCreateRemoteEvent(script, "RaidStarted")
	RaidRemotes.WaveAdvanced = getOrCreateRemoteEvent(script, "WaveAdvanced")
	RaidRemotes.EnemyHit = getOrCreateRemoteEvent(script, "EnemyHit")
	RaidRemotes.RaidResult = getOrCreateRemoteEvent(script, "RaidResult")
	RaidRemotes.RequestRescueCreature = getOrCreateRemoteEvent(script, "RequestRescueCreature")
	RaidRemotes.RescueResult = getOrCreateRemoteEvent(script, "RescueResult")
	RaidRemotes.RequestRescueWithToken = getOrCreateRemoteEvent(script, "RequestRescueWithToken")
	RaidRemotes.RescueWithTokenResult = getOrCreateRemoteEvent(script, "RescueWithTokenResult")
else
	RaidRemotes.GetRaidStatus = script:WaitForChild("GetRaidStatus") :: RemoteFunction
	RaidRemotes.RaidStarted = script:WaitForChild("RaidStarted") :: RemoteEvent
	RaidRemotes.WaveAdvanced = script:WaitForChild("WaveAdvanced") :: RemoteEvent
	RaidRemotes.EnemyHit = script:WaitForChild("EnemyHit") :: RemoteEvent
	RaidRemotes.RaidResult = script:WaitForChild("RaidResult") :: RemoteEvent
	RaidRemotes.RequestRescueCreature = script:WaitForChild("RequestRescueCreature") :: RemoteEvent
	RaidRemotes.RescueResult = script:WaitForChild("RescueResult") :: RemoteEvent
	RaidRemotes.RequestRescueWithToken = script:WaitForChild("RequestRescueWithToken") :: RemoteEvent
	RaidRemotes.RescueWithTokenResult = script:WaitForChild("RescueWithTokenResult") :: RemoteEvent
end

return RaidRemotes
