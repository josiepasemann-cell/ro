--[[
	Abyssara – Deep Tide Tycoon
	Modul: BreedingRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle (RemoteEvents/RemoteFunction) für das Zucht-/Ei-System (GDD
		Abschnitt 9, Punkt 4) definiert werden. Sowohl Server
		(BreedingServer.server.lua) als auch Client (BreedingUIController.
		client.lua) requiren AUSSCHLIESSLICH dieses Modul statt Instance-Pfade
		doppelt zu hardcoden - identisches Bootstrap-Muster zu
		src/shared/HabitatRemotes.lua/GachaRemotes.lua, siehe dort für die
		ausführliche Begründung (Remotes als Kinder dieses ModuleScripts
		selbst, Server legt sie an, Client wartet nur per WaitForChild).

	Rojo-Einhängepunkt:
		src/shared/BreedingRemotes.lua -> ReplicatedStorage.BreedingRemotes

	Exportierte Kanäle:
		RequestStartBreeding (RemoteEvent, Client -> Server)
			Payload: (placementId: string) - das angeklickte, dem Spieler
			gehörende BroodPool-Gebäude. Reine Absichtserklärung - der Server
			validiert Eigentümerschaft (Lookup ausschließlich im eigenen
			HabitatLayout des anfragenden Spielers), freien Slot, Level-
			Freischaltung und Kontostand komplett neu. Kein Wert wird
			ungeprüft übernommen, und das Zucht-ERGEBNIS wird niemals vom
			Client vorgegeben.
		StartBreedingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestStartBreeding: { Success: boolean,
			Reason: string?, PlacementId: string?, StartedAt: number?,
			ReadyAt: number?, FeedCost: number?, NewBalance: number? }.
			ABSICHTLICH OHNE CreatureId/Rarity - das Ergebnis bleibt bis zum
			Abholen verborgen (Ei-Schlüpfen-Mysterium, siehe BreedingConfig).
		RequestClaimBreeding (RemoteEvent, Client -> Server)
			Payload: (placementId: string). Server prüft erneut, ob die
			Inkubation an diesem Feld wirklich fertig ist (ReadyAt <=
			os.time()) - eine verfrühte Anfrage wird sauber abgelehnt statt
			irgendetwas vorzeitig zu gewähren.
		ClaimBreedingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestClaimBreeding: { Success: boolean,
			Reason: string?, PlacementId: string?, CreatureId: string?,
			CreatureName: string?, Rarity: string? }.
		RequestInstantCompleteBreeding (RemoteEvent, Client -> Server)
			PLATZHALTER-Kanal für ein künftiges Entwicklerprodukt ("Zucht
			sofort abschließen", Robux). Aktuell antwortet der Server IMMER
			mit Reason = "NotImplemented" (siehe BreedingService.
			RequestInstantComplete) - kein MarketplaceService/ProcessReceipt-
			Handler existiert bisher im Projekt. Der Kanal ist bereits jetzt
			verdrahtet, damit die Client-UI einen (aktuell deaktivierten)
			Button zeigen kann, ohne stillschweigend zu scheitern.
		InstantCompleteBreedingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestInstantCompleteBreeding: { Success: boolean,
			Reason: string? }.
		GetBreedingStatuses (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert eine Liste aller aktuellen Brutbecken-
			Status des anfragenden Spielers (siehe BreedingService.
			GetAllStatuses) - für den initialen UI-Sync beim Plot-Laden und
			nach jeder Start-/Abhol-Aktion, statt eines Dauer-Polling-Loops.
]]

local RunService = game:GetService("RunService")

local BreedingRemotes = {}

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
	BreedingRemotes.RequestStartBreeding = getOrCreateRemoteEvent(script, "RequestStartBreeding")
	BreedingRemotes.StartBreedingResult = getOrCreateRemoteEvent(script, "StartBreedingResult")
	BreedingRemotes.RequestClaimBreeding = getOrCreateRemoteEvent(script, "RequestClaimBreeding")
	BreedingRemotes.ClaimBreedingResult = getOrCreateRemoteEvent(script, "ClaimBreedingResult")
	BreedingRemotes.RequestInstantCompleteBreeding = getOrCreateRemoteEvent(script, "RequestInstantCompleteBreeding")
	BreedingRemotes.InstantCompleteBreedingResult = getOrCreateRemoteEvent(script, "InstantCompleteBreedingResult")
	BreedingRemotes.GetBreedingStatuses = getOrCreateRemoteFunction(script, "GetBreedingStatuses")
else
	BreedingRemotes.RequestStartBreeding = script:WaitForChild("RequestStartBreeding") :: RemoteEvent
	BreedingRemotes.StartBreedingResult = script:WaitForChild("StartBreedingResult") :: RemoteEvent
	BreedingRemotes.RequestClaimBreeding = script:WaitForChild("RequestClaimBreeding") :: RemoteEvent
	BreedingRemotes.ClaimBreedingResult = script:WaitForChild("ClaimBreedingResult") :: RemoteEvent
	BreedingRemotes.RequestInstantCompleteBreeding = script:WaitForChild("RequestInstantCompleteBreeding") :: RemoteEvent
	BreedingRemotes.InstantCompleteBreedingResult = script:WaitForChild("InstantCompleteBreedingResult") :: RemoteEvent
	BreedingRemotes.GetBreedingStatuses = script:WaitForChild("GetBreedingStatuses") :: RemoteFunction
end

return BreedingRemotes
