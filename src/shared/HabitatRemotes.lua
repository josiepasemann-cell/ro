--[[
	Abyssara – Deep Tide Tycoon
	Modul: HabitatRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle (RemoteEvents) für das Bauplatzierungs-System definiert
		werden. Server (PlacementServer.server.lua) und Client
		(PlacementPreviewController.client.lua) requiren AUSSCHLIESSLICH
		dieses Modul statt Instance-Pfade doppelt zu hardcoden - identisches
		Muster zu src/shared/GachaRemotes.lua, siehe dort für die
		ausführliche Begründung des Bootstrap-Musters (Remotes als Kinder
		dieses ModuleScripts selbst, Server legt sie an, Client wartet nur).

	Rojo-Einhängepunkt:
		src/shared/HabitatRemotes.lua -> ReplicatedStorage.HabitatRemotes

	Exportierte Kanäle:
		RequestPlaceBuilding (RemoteEvent, Client -> Server)
			Payload: (buildingId: string, fieldIndex: number, rotationY: number).
			Reine Absichtserklärung - der Server validiert jeden einzelnen
			Wert komplett neu (Existenz der BuildingId, Belegung des
			Feldes, Level-Freischaltung, Kontostand, Rotation-Snap). Kein
			Wert aus diesem Event wird ungeprüft übernommen.
		PlaceBuildingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestPlaceBuilding: { Success: boolean,
			Reason: string?, Placement: HabitatPlacement?, FieldIndex:
			number?, NewBalance: number? }.
		RequestRemoveBuilding (RemoteEvent, Client -> Server)
			Payload: (placementId: string). Server prüft Eigentümerschaft
			implizit (PlacementId wird nur im Server-seitigen Pro-Spieler-
			Zustand von PlacementService nachgeschlagen - ein Spieler kann
			technisch keine fremde PlacementId "erraten" und etwas
			entfernen, da der Lookup ausschließlich in seinem eigenen
			Zustand passiert).
		RemoveBuildingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestRemoveBuilding: { Success: boolean,
			Reason: string?, PlacementId: string?, RefundAmount: number?,
			NewBalance: number? }.
]]

local RunService = game:GetService("RunService")

local HabitatRemotes = {}

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

if RunService:IsServer() then
	HabitatRemotes.RequestPlaceBuilding = getOrCreateRemoteEvent(script, "RequestPlaceBuilding")
	HabitatRemotes.PlaceBuildingResult = getOrCreateRemoteEvent(script, "PlaceBuildingResult")
	HabitatRemotes.RequestRemoveBuilding = getOrCreateRemoteEvent(script, "RequestRemoveBuilding")
	HabitatRemotes.RemoveBuildingResult = getOrCreateRemoteEvent(script, "RemoveBuildingResult")
else
	HabitatRemotes.RequestPlaceBuilding = script:WaitForChild("RequestPlaceBuilding") :: RemoteEvent
	HabitatRemotes.PlaceBuildingResult = script:WaitForChild("PlaceBuildingResult") :: RemoteEvent
	HabitatRemotes.RequestRemoveBuilding = script:WaitForChild("RequestRemoveBuilding") :: RemoteEvent
	HabitatRemotes.RemoveBuildingResult = script:WaitForChild("RemoveBuildingResult") :: RemoteEvent
end

return HabitatRemotes
