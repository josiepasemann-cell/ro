--[[
	Abyssara – Deep Tide Tycoon
	Modul: CodexRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für die Client<->Server-Kommunikationskanäle
		des Kreaturen-Kodex-Systems (docs/content-update-1.md, Abschnitt 5.2)
		und der Plot-Anzeige-Favoriten (Abschnitt 5.1). Sowohl Server
		(CodexServer.server.lua) als auch Client (CodexUIController.client.lua)
		requiren AUSSCHLIESSLICH dieses Modul - identisches Muster zu
		GachaRemotes.lua/BreedingRemotes.lua/RaidRemotes.lua.

	Rojo-Einhängepunkt:
		src/shared/CodexRemotes.lua -> ReplicatedStorage.CodexRemotes

	Exportierte Kanäle:
		GetCodexCatalog (RemoteFunction, Client -> Server -> Client)
			Liefert den vollständigen, geräteunabhängigen Katalog aller
			aktuell existierenden Kreaturen (siehe CodexService.GetCatalog) -
			KEINE Besitz-/Favoriten-Info, das liefert GetCodexState separat,
			damit der reine Katalog clientseitig gecacht werden kann, ohne
			bei jedem Öffnen neu übertragen werden zu müssen (auch wenn
			CodexUIController ihn aktuell bei jedem Öffnen frisch abfragt,
			siehe dortigen Kopfkommentar zur bewussten Vereinfachung).
		GetCodexState (RemoteFunction, Client -> Server -> Client)
			Liefert den Besitz-/Favoriten-/Belohnungs-Zustand DES
			anfragenden Spielers (niemals eines anderen Spielers - der
			Server liest ausschließlich das `player`-Argument aus
			OnServerInvoke, niemals eine vom Client übergebene UserId).
		RequestSetFavorites (RemoteEvent, Client -> Server)
			Payload: { string } (CreatureId-Liste, gewünschte Anzeige-
			Reihenfolge). Server validiert vollständig neu (Besitz, max. 6,
			siehe CodexService.SetFavorites) - niemals ungeprüft übernehmen.
		SetFavoritesResult (RemoteEvent, Server -> Client)
			Payload: { Success: boolean, Reason: string?, Favorites: {string} }
		RequestClaimZoneReward (RemoteEvent, Client -> Server)
			Payload: zoneId (string)
		ClaimZoneRewardResult (RemoteEvent, Server -> Client)
			Payload: { Success: boolean, Reason: string?, Zone: string?,
				RewardTideCoins: number?, RewardTitle: string?,
				NewIncomeBonusPercent: number? }
]]

local RunService = game:GetService("RunService")

local CodexRemotes = {}

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
	CodexRemotes.GetCodexCatalog = getOrCreateRemoteFunction(script, "GetCodexCatalog")
	CodexRemotes.GetCodexState = getOrCreateRemoteFunction(script, "GetCodexState")
	CodexRemotes.RequestSetFavorites = getOrCreateRemoteEvent(script, "RequestSetFavorites")
	CodexRemotes.SetFavoritesResult = getOrCreateRemoteEvent(script, "SetFavoritesResult")
	CodexRemotes.RequestClaimZoneReward = getOrCreateRemoteEvent(script, "RequestClaimZoneReward")
	CodexRemotes.ClaimZoneRewardResult = getOrCreateRemoteEvent(script, "ClaimZoneRewardResult")
else
	CodexRemotes.GetCodexCatalog = script:WaitForChild("GetCodexCatalog") :: RemoteFunction
	CodexRemotes.GetCodexState = script:WaitForChild("GetCodexState") :: RemoteFunction
	CodexRemotes.RequestSetFavorites = script:WaitForChild("RequestSetFavorites") :: RemoteEvent
	CodexRemotes.SetFavoritesResult = script:WaitForChild("SetFavoritesResult") :: RemoteEvent
	CodexRemotes.RequestClaimZoneReward = script:WaitForChild("RequestClaimZoneReward") :: RemoteEvent
	CodexRemotes.ClaimZoneRewardResult = script:WaitForChild("ClaimZoneRewardResult") :: RemoteEvent
end

return CodexRemotes
