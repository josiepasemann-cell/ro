--[[
	Abyssara – Deep Tide Tycoon
	Skript: BuddyServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Buddy-Systems auf Server-Seite: verbindet
		die RemoteEvent/RemoteFunction-Kanäle aus BuddyRemotes mit der
		reinen Logik in BuddyService. Enthält selbst KEINE Validierungs-
		logik - identisches, dünnes Bootstrap-Muster wie
		CodexServer.server.lua/GachaServer.server.lua.

	Rojo-Einhängepunkt:
		src/server/BuddyServer.server.lua -> ServerScriptService.BuddyServer

	Sicherheitsprinzip (kein Client-Trust):
		Jede Anfrage wird 1:1 an BuddyService durchgereicht, das JEDEN
		übergebenen Wert vollständig neu validiert (Besitz). Der einzige
		vertrauenswürdige Wert ist `player`, den die Roblox-Engine selbst
		liefert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuddyService = require(script.Parent:WaitForChild("BuddyService"))
local BuddyRemotes = require(ReplicatedStorage:WaitForChild("BuddyRemotes"))

BuddyRemotes.GetBuddyState.OnServerInvoke = function(player: Player)
	return { CreatureId = BuddyService.GetBuddyCreatureId(player) }
end

BuddyRemotes.RequestSetBuddy.OnServerEvent:Connect(function(player: Player, creatureId: any)
	local ok, failure, finalCreatureId = BuddyService.SetBuddy(player, creatureId)
	BuddyRemotes.SetBuddyResult:FireClient(player, {
		Success = ok,
		Reason = failure,
		CreatureId = finalCreatureId,
	})
end)

print("[Abyssara] BuddyServer ready (GetBuddyState / RequestSetBuddy wired up).")
