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
		RequestDeployGuardian (RemoteEvent, Client -> Server)
			No payload. Asks the server to deploy the player's SAVED guardian
			loadout (PlayerDataService.GetGuardianLoadout) into the raid they
			are currently in (their own, or a cluster mate's they joined). The
			client never sends creature ids here - the server re-validates
			ownership, abducted state and slot count itself. Once per raid.
		GetGuardianLoadout (RemoteFunction, Client -> Server -> Client)
			No payload. Returns { Slots, SlotUnlockLevels, Loadout: {instanceId},
			Candidates: { { InstanceId, CreatureId, Rarity, Damage, MaxHP,
			Eligible, Reason? } }, Deployed: boolean, InRaid: boolean }.
		RequestSetGuardianLoadout (RemoteEvent, Client -> Server)
			Payload: (ids: {string}). Pure intent; RaidService trims to the
			unlocked slot count, drops unowned/abducted ids and persists via
			PlayerDataService.SetGuardianLoadout. Answered by GuardianLoadoutChanged.
		GuardianDeployResult (RemoteEvent, Server -> Client)
			Answer to RequestDeployGuardian: { Success, Reason: string?, Count: number? }.
		GuardianLoadoutChanged (RemoteEvent, Server -> Client)
			{ Success: boolean, Reason: string?, Loadout: {string}, Slots: number }.
		GuardianStatus (RemoteEvent, Server -> Client)
			Raid HUD snapshot of all guardians in the viewer's raid (own and
			cluster mates'): { Guardians = { { OwnerUserId, InstanceId, CreatureId,
			Rarity, HP, MaxHP, KnockedOut } } }. Empty list when the raid ends.
		GuardianAttack (RemoteEvent, Server -> Client)
			Cosmetic: { From: Vector3, To: Vector3, Rarity: string }.
		CoopRaidInvite (RemoteEvent, Server -> Client)
			A cluster mate's plot is being raided: { OwnerUserId, OwnerName,
			ExpiresAt (os.time) }.
		RequestJoinCoopRaid (RemoteEvent, Client -> Server)
			Payload: (ownerUserId: number). Server checks that the owner has an
			active raid, that the sender is in the owner's Reef Cluster, capacity
			and cooldowns, then teleports the sender to the owner's plot.
		RequestLeaveCoopRaid (RemoteEvent, Client -> Server)
			No payload. A helper leaves the raid and returns to their own plot.
		CoopRaidJoined (RemoteEvent, Server -> Client)
			Answer to RequestJoinCoopRaid: { Success, Reason?, OwnerName?,
			WaveIndex?, TotalWaves?, WaveEnemyCount?, IsBossWave? }.
		CoopRaidLeft (RemoteEvent, Server -> Client)
			The helper is no longer part of a co-op raid: { Reason: string }.
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
	RaidRemotes.RequestDeployGuardian = getOrCreateRemoteEvent(script, "RequestDeployGuardian")
	RaidRemotes.RequestSetGuardianLoadout = getOrCreateRemoteEvent(script, "RequestSetGuardianLoadout")
	RaidRemotes.GuardianLoadoutChanged = getOrCreateRemoteEvent(script, "GuardianLoadoutChanged")
	RaidRemotes.GuardianDeployResult = getOrCreateRemoteEvent(script, "GuardianDeployResult")
	RaidRemotes.GuardianStatus = getOrCreateRemoteEvent(script, "GuardianStatus")
	RaidRemotes.GuardianAttack = getOrCreateRemoteEvent(script, "GuardianAttack")
	RaidRemotes.CoopRaidInvite = getOrCreateRemoteEvent(script, "CoopRaidInvite")
	RaidRemotes.RequestJoinCoopRaid = getOrCreateRemoteEvent(script, "RequestJoinCoopRaid")
	RaidRemotes.RequestLeaveCoopRaid = getOrCreateRemoteEvent(script, "RequestLeaveCoopRaid")
	RaidRemotes.CoopRaidJoined = getOrCreateRemoteEvent(script, "CoopRaidJoined")
	RaidRemotes.CoopRaidLeft = getOrCreateRemoteEvent(script, "CoopRaidLeft")
	RaidRemotes.GetGuardianLoadout = getOrCreateRemoteFunction(script, "GetGuardianLoadout")
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
	RaidRemotes.RequestDeployGuardian = script:WaitForChild("RequestDeployGuardian") :: RemoteEvent
	RaidRemotes.RequestSetGuardianLoadout = script:WaitForChild("RequestSetGuardianLoadout") :: RemoteEvent
	RaidRemotes.GuardianLoadoutChanged = script:WaitForChild("GuardianLoadoutChanged") :: RemoteEvent
	RaidRemotes.GuardianDeployResult = script:WaitForChild("GuardianDeployResult") :: RemoteEvent
	RaidRemotes.GuardianStatus = script:WaitForChild("GuardianStatus") :: RemoteEvent
	RaidRemotes.GuardianAttack = script:WaitForChild("GuardianAttack") :: RemoteEvent
	RaidRemotes.CoopRaidInvite = script:WaitForChild("CoopRaidInvite") :: RemoteEvent
	RaidRemotes.RequestJoinCoopRaid = script:WaitForChild("RequestJoinCoopRaid") :: RemoteEvent
	RaidRemotes.RequestLeaveCoopRaid = script:WaitForChild("RequestLeaveCoopRaid") :: RemoteEvent
	RaidRemotes.CoopRaidJoined = script:WaitForChild("CoopRaidJoined") :: RemoteEvent
	RaidRemotes.CoopRaidLeft = script:WaitForChild("CoopRaidLeft") :: RemoteEvent
	RaidRemotes.GetGuardianLoadout = script:WaitForChild("GetGuardianLoadout") :: RemoteFunction
end

return RaidRemotes
