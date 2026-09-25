--[[
	Abyssara – Deep Tide Tycoon
	Modul: BuddyRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für die Client<->Server-Kommunikationskanäle
		des Buddy-Systems (docs/buddy.md): ein frei wählbares, besessenes
		Kreaturen-Maskottchen, das dem Spieler sichtbar für ALLE Spieler
		durch die gesamte Welt folgt. Sowohl Server (BuddyServer.server.lua)
		als auch Client (BuddyClient.client.lua, CodexUIController.client.lua)
		requiren AUSSCHLIESSLICH dieses Modul - identisches Muster zu
		CodexRemotes.lua/GachaRemotes.lua.

	WICHTIG: Die tatsächliche Buddy-BEWEGUNG läuft NICHT über diese Remotes
		(siehe BuddyService-Kopfkommentar "Bewegungs-Architektur") - das
		Buddy-Modell selbst repliziert wie jede normale Workspace-Instanz
		(inkl. seiner Attribute `OwnerUserId`/`CreatureId`/`Rarity`), jeder
		Client berechnet seine Position rein lokal. Diese Remotes decken
		ausschließlich die Auswahl/Validierung ab.

	Rojo-Einhängepunkt:
		src/shared/BuddyRemotes.lua -> ReplicatedStorage.BuddyRemotes

	Exportierte Kanäle:
		RequestSetBuddy (RemoteEvent, Client -> Server)
			Payload: creatureId (string, gewünschte Buddy-Art) ODER nil, um
			den aktuellen Buddy zu entfernen. Server validiert vollständig
			neu (Besitz, siehe BuddyService.SetBuddy) - niemals ungeprüft
			übernehmen.
		SetBuddyResult (RemoteEvent, Server -> Client)
			Payload: { Success: boolean, Reason: string?, CreatureId: string? }
		GetBuddyState (RemoteFunction, Client -> Server -> Client)
			Liefert den Buddy-Zustand DES anfragenden Spielers (niemals
			eines anderen Spielers). Payload: { CreatureId: string?,
			CreatureId2: string? }
		RequestSetBuddy2 (RemoteEvent, Client -> Server)
			Auftrag "Extra Buddy Slot"-Gamepass (149 Robux): identisch zu
			RequestSetBuddy, aber für den ZWEITEN Buddy-Slot. Payload:
			creatureId (string) ODER nil. Server validiert vollständig neu
			(Besitz DER Kreatur UND Besitz des "Extra Buddy Slot"-Gamepasses,
			siehe BuddyService.SetBuddy2) - ein Kauf-Umgehungsversuch über
			diesen Kanal schlägt serverseitig fehl.
		SetBuddy2Result (RemoteEvent, Server -> Client)
			Payload: { Success: boolean, Reason: string?, CreatureId: string? }

	Zusätzlich exportiert dieses Modul `BuddyRemotes.BUDDY_TAG` - die
	`CollectionService`-Tag-Konstante, mit der BuddyService jedes
	Buddy-Modell markiert und BuddyClient alle sichtbaren Buddy-Modelle
	findet. EINZIGE Quelle der Wahrheit für diesen String, damit Server-
	und Client-Seite nicht auseinanderlaufen können.
]]

local RunService = game:GetService("RunService")

local BuddyRemotes = {}

BuddyRemotes.BUDDY_TAG = "PlayerBuddy"

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
	BuddyRemotes.RequestSetBuddy = getOrCreateRemoteEvent(script, "RequestSetBuddy")
	BuddyRemotes.SetBuddyResult = getOrCreateRemoteEvent(script, "SetBuddyResult")
	BuddyRemotes.GetBuddyState = getOrCreateRemoteFunction(script, "GetBuddyState")
	BuddyRemotes.RequestSetBuddy2 = getOrCreateRemoteEvent(script, "RequestSetBuddy2")
	BuddyRemotes.SetBuddy2Result = getOrCreateRemoteEvent(script, "SetBuddy2Result")
else
	BuddyRemotes.RequestSetBuddy = script:WaitForChild("RequestSetBuddy") :: RemoteEvent
	BuddyRemotes.SetBuddyResult = script:WaitForChild("SetBuddyResult") :: RemoteEvent
	BuddyRemotes.GetBuddyState = script:WaitForChild("GetBuddyState") :: RemoteFunction
	BuddyRemotes.RequestSetBuddy2 = script:WaitForChild("RequestSetBuddy2") :: RemoteEvent
	BuddyRemotes.SetBuddy2Result = script:WaitForChild("SetBuddy2Result") :: RemoteEvent
end

return BuddyRemotes
