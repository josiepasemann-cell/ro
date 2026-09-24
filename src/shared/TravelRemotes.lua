--[[
	Abyssara – Deep Tide Tycoon
	Modul: TravelRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für die Client<->Server-Kommunikationskanäle
		des Reise-/Teleport-Systems (Hub <-> eigener Plot <-> Zonen-Portale,
		GDD Abschnitt 4 "Hub-Welt Tidal Market" + Abschnitt 6 "Zonenportal
		Dämmerzone (Level 10)"). Identisches Bootstrap-Muster zu
		RaidRemotes/QuestRemotes/LeaderboardRemotes.

		WICHTIG: Die serverseitig bereits vorhandenen `ProximityPrompt`s an
		PlotGate/Portal_<Zone> (siehe TravelService) lösen dieselbe Logik OHNE
		diese Remotes aus (ProximityPrompt.Triggered liefert den Player
		bereits vertrauenswürdig von der Engine). Diese Remotes sind für ein
		künftiges UI-Panel gedacht (z. B. ein Hub-Kompass/Schnellreise-Menü),
		das denselben Teleport OHNE physische Nähe zum jeweiligen Objekt
		anstoßen können soll.

	Rojo-Einhängepunkt:
		src/shared/TravelRemotes.lua -> ReplicatedStorage.TravelRemotes

	Exportierte Kanäle:
		RequestTravelToPlot (RemoteEvent, Client -> Server)
			Payload: keine. Teleportiert den anfragenden Spieler zu seinem
			EIGENEN, bereits zugewiesenen Plot (PlotRegistry.GetPlot).
		RequestTravelToHub (RemoteEvent, Client -> Server)
			Payload: keine. Teleportiert zurück zur Hub-Welt "Tidal Market".
		RequestTravelToZone (RemoteEvent, Client -> Server)
			Payload: (zoneId: string) - einer von "SunZone" / "TwilightZone" /
			"MidnightZone" / "HadalDepths" (siehe TravelService.ZONE_IDS).
			Server validiert RequiredLevel serverseitig neu (nie Client-Trust).
		TravelResult (RemoteEvent, Server -> Client)
			Antwort auf JEDE der drei Anfragen oben: { Success: boolean,
			Reason: string?, -- "OnCooldown" | "NoPlot" | "UnknownZone" |
			                  -- "LevelTooLow" | "ZoneComingSoon" | "NoCharacter"
			Destination: string?, -- "Plot" | "Hub" | ZoneId
			RequiredLevel: number?, -- nur bei Reason == "LevelTooLow"
			CurrentLevel: number?, -- nur bei Reason == "LevelTooLow"
		}.
]]

local RunService = game:GetService("RunService")

local TravelRemotes = {}

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
	TravelRemotes.RequestTravelToPlot = getOrCreateRemoteEvent(script, "RequestTravelToPlot")
	TravelRemotes.RequestTravelToHub = getOrCreateRemoteEvent(script, "RequestTravelToHub")
	TravelRemotes.RequestTravelToZone = getOrCreateRemoteEvent(script, "RequestTravelToZone")
	TravelRemotes.TravelResult = getOrCreateRemoteEvent(script, "TravelResult")
else
	TravelRemotes.RequestTravelToPlot = script:WaitForChild("RequestTravelToPlot") :: RemoteEvent
	TravelRemotes.RequestTravelToHub = script:WaitForChild("RequestTravelToHub") :: RemoteEvent
	TravelRemotes.RequestTravelToZone = script:WaitForChild("RequestTravelToZone") :: RemoteEvent
	TravelRemotes.TravelResult = script:WaitForChild("TravelResult") :: RemoteEvent
end

return TravelRemotes
