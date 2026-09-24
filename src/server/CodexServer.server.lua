--[[
	Abyssara – Deep Tide Tycoon
	Skript: CodexServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Kreaturen-Kodex-Systems auf Server-Seite:
		verbindet die RemoteEvent/RemoteFunction-Kanäle aus CodexRemotes mit
		der reinen Logik in CodexService. Enthält selbst KEINE Katalog-/
		Validierungslogik - identisches, dünnes Bootstrap-Muster wie
		GachaServer.server.lua/RaidServer.server.lua.

	Rojo-Einhängepunkt:
		src/server/CodexServer.server.lua -> ServerScriptService.CodexServer

	Sicherheitsprinzip (kein Client-Trust):
		Jede Anfrage wird 1:1 an CodexService durchgereicht, das JEDEN
		übergebenen Wert vollständig neu validiert (Besitz, Vollständigkeit,
		Einmaligkeit). Der einzige vertrauenswürdige Wert ist `player`, den
		die Roblox-Engine selbst liefert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodexService = require(script.Parent:WaitForChild("CodexService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local CodexRemotes = require(ReplicatedStorage:WaitForChild("CodexRemotes"))

CodexRemotes.GetCodexCatalog.OnServerInvoke = function(_player: Player)
	return CodexService.GetCatalog()
end

CodexRemotes.GetCodexState.OnServerInvoke = function(player: Player)
	return CodexService.GetPlayerState(player)
end

CodexRemotes.RequestSetFavorites.OnServerEvent:Connect(function(player: Player, requestedCreatureIds: { any })
	local ok, failure, finalFavorites = CodexService.SetFavorites(player, requestedCreatureIds)
	CodexRemotes.SetFavoritesResult:FireClient(player, {
		Success = ok,
		Reason = failure,
		Favorites = finalFavorites or PlayerDataService.GetCodexFavorites(player),
	})
end)

CodexRemotes.RequestClaimZoneReward.OnServerEvent:Connect(function(player: Player, zone: any)
	local ok, failure, result = CodexService.ClaimZoneReward(player, zone)
	CodexRemotes.ClaimZoneRewardResult:FireClient(player, {
		Success = ok,
		Reason = failure,
		Zone = result and result.Zone or (typeof(zone) == "string" and zone or nil),
		RewardTideCoins = result and result.RewardTideCoins or nil,
		RewardTitle = result and result.RewardTitle or nil,
		NewIncomeBonusPercent = result and result.NewIncomeBonusPercent or nil,
	})
end)

print("[Abyssara] CodexServer ready (GetCodexCatalog / GetCodexState / RequestSetFavorites / RequestClaimZoneReward wired up).")
