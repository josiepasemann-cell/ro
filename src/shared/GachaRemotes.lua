--[[
	Abyssara – Deep Tide Tycoon
	Modul: GachaRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikationskanäle
		(RemoteEvent/RemoteFunction) für das Mystery-Egg-Gacha-System definiert
		werden. Sowohl Server (GachaServer.server.lua) als auch Client
		(GachaOpenClient.client.lua, GachaOddsUIController.client.lua)
		requiren AUSSCHLIESSLICH dieses Modul, statt Instance-Pfade doppelt
		zu hardcoden – so bleiben Namen/Struktur an genau einer Stelle änderbar.

	Rojo-Einhängepunkt:
		src/shared/  ->  ReplicatedStorage
		(diese Datei landet also unter game.ReplicatedStorage.GachaRemotes)

	Funktionsweise:
		Nur der Server (RunService:IsServer() == true) LEGT die Remote-
		Instanzen an. Sie werden bewusst direkt als Kinder dieses
		ModuleScripts selbst angelegt (Parent = script) statt in einem
		separaten Geschwister-Ordner - eine eigene "GachaRemotes"-Folder-
		Instanz neben dem gleichnamigen ModuleScript würde zu einer
		mehrdeutigen Namenskollision unter ReplicatedStorage führen
		(FindFirstChild/WaitForChild könnten dann sowohl das ModuleScript
		als auch den Ordner treffen). Der Client wartet beim ersten
		require() lediglich per WaitForChild darauf, dass der Server sie
		bereits erzeugt hat (Server-Skripte laufen vor den Client-Skripten
		hoch). So gibt es nur eine Quelle der Wahrheit für die Instanzen und
		keinen Race-Condition-Fall, in dem der Client versucht, sie selbst
		zu erzeugen.

	Exportierte Kanäle:
		RequestOpenEgg  (RemoteEvent, Client -> Server)
			Feuert OHNE Payload (oder rein kosmetische Zusatzdaten wie das
			angeklickte Ei-Modell werden bewusst NICHT gesendet/benutzt) –
			der Server entscheidet die komplette Roll-Logik selbst. Niemals
			Rarity/Ergebnis vom Client entgegennehmen (kein Client-Trust).
		OpenEggResult   (RemoteEvent, Server -> Client)
			Server sendet das Roll-Ergebnis an genau den anfragenden Spieler.
		GetGachaOdds    (RemoteFunction, Client -> Server -> Client)
			Client fragt die aktuelle, autoritative Odds-Tabelle ab (für die
			Anbindung von GachaOddsPanel). Liefert NUR öffentliche,
			compliance-relevante Felder (Rarity, Anzeigename, Prozentwert,
			Farbe) zurück – keine internen Balancing-Daten wie Pity-Schwellen
			oder Duplikat-Ausgleichswerte.
]]

local RunService = game:GetService("RunService")

local GachaRemotes = {}

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
	-- Server: Remotes idempotent direkt unter diesem ModuleScript anlegen
	-- (analog im Geiste zu den getOrCreateFolder()-Helfern der
	-- Asset-Buildscripts, nur ohne zusätzliche Ordner-Ebene).
	GachaRemotes.RequestOpenEgg = getOrCreateRemoteEvent(script, "RequestOpenEgg")
	GachaRemotes.OpenEggResult = getOrCreateRemoteEvent(script, "OpenEggResult")
	GachaRemotes.GetGachaOdds = getOrCreateRemoteFunction(script, "GetGachaOdds")
else
	-- Client: nur abwarten, niemals selbst erzeugen.
	GachaRemotes.RequestOpenEgg = script:WaitForChild("RequestOpenEgg") :: RemoteEvent
	GachaRemotes.OpenEggResult = script:WaitForChild("OpenEggResult") :: RemoteEvent
	GachaRemotes.GetGachaOdds = script:WaitForChild("GetGachaOdds") :: RemoteFunction
end

return GachaRemotes
