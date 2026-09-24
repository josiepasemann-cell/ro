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
		RequestUpgradeBuilding (RemoteEvent, Client -> Server)
			Payload: (placementId: string). Gebäude-Upgrade-System (siehe
			docs/building-upgrades.md) - reine Absichtserklärung, der
			Server (PlacementService.RequestUpgrade) validiert Stufe,
			Level-Anforderung, laufende Inkubation (BroodPool) und
			Kontostand komplett neu, identisches Sicherheitsprinzip wie
			RequestPlaceBuilding.
		UpgradeBuildingResult (RemoteEvent, Server -> Client)
			Antwort auf RequestUpgradeBuilding: { Success: boolean,
			Reason: string?, PlacementId: string?, NewStage: number?,
			NewBalance: number?, NewAbyssalShardBalance: number? }.
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
	HabitatRemotes.RequestUpgradeBuilding = getOrCreateRemoteEvent(script, "RequestUpgradeBuilding")
	HabitatRemotes.UpgradeBuildingResult = getOrCreateRemoteEvent(script, "UpgradeBuildingResult")
else
	HabitatRemotes.RequestPlaceBuilding = script:WaitForChild("RequestPlaceBuilding") :: RemoteEvent
	HabitatRemotes.PlaceBuildingResult = script:WaitForChild("PlaceBuildingResult") :: RemoteEvent
	HabitatRemotes.RequestRemoveBuilding = script:WaitForChild("RequestRemoveBuilding") :: RemoteEvent
	HabitatRemotes.RemoveBuildingResult = script:WaitForChild("RemoveBuildingResult") :: RemoteEvent
	HabitatRemotes.RequestUpgradeBuilding = script:WaitForChild("RequestUpgradeBuilding") :: RemoteEvent
	HabitatRemotes.UpgradeBuildingResult = script:WaitForChild("UpgradeBuildingResult") :: RemoteEvent
end

return HabitatRemotes
