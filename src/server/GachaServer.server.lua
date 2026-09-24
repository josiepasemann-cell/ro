--[[
	Abyssara – Deep Tide Tycoon
	Skript: GachaServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Mystery-Egg-Gacha-Systems auf Server-Seite:
		verbindet die RemoteEvent/RemoteFunction-Kanäle aus GachaRemotes mit
		der reinen Logik in GachaService. Enthält selbst KEINE Gacha-Logik
		(Roll/Pity/Duplikat) - das bleibt vollständig in GachaService, damit
		dieses Skript austauschbar/dünn bleibt.

	Rojo-Einhängepunkt:
		src/server/GachaServer.server.lua  ->  ServerScriptService.GachaServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestOpenEgg wird ohne jegliche Payload vom Client entgegen-
		genommen. Der einzige vertrauenswürdige Wert aus dem Event ist der
		`player`, den die Roblox-Engine selbst als ersten Parameter von
		OnServerEvent liefert (vom Client nicht fälschbar). Alles andere
		(Rarity, Kreatur, Pity-Stand) wird ausschließlich von GachaService
		serverseitig bestimmt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GachaService = require(script.Parent:WaitForChild("GachaService"))
local GachaRemotes = require(ReplicatedStorage:WaitForChild("GachaRemotes"))

GachaRemotes.RequestOpenEgg.OnServerEvent:Connect(function(player: Player)
	local result, failure = GachaService.OpenEgg(player)

	if not result then
		-- z. B. "OnCooldown" bei zu schneller Wiederholungs-Anfrage
		-- (Anti-Spam-Schutz, siehe GachaConfig.MIN_SECONDS_BETWEEN_ROLLS).
		-- Kein hartes Kick/Ban hier - eine zu schnelle Doppel-Anfrage kann
		-- auch durch Netzwerk-Jitter/Doppelklick entstehen.
		GachaRemotes.OpenEggResult:FireClient(player, {
			Success = false,
			Failure = failure,
		})
		return
	end

	GachaRemotes.OpenEggResult:FireClient(player, {
		Success = true,
		Result = result,
	})
end)

GachaRemotes.GetGachaOdds.OnServerInvoke = function(_player: Player)
	return GachaService.GetOddsTable()
end

print("[Abyssara] GachaServer bereit (RequestOpenEgg / GetGachaOdds verdrahtet).")
