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
	return {
		CreatureId = BuddyService.GetBuddyCreatureId(player),
		CreatureId2 = BuddyService.GetBuddyCreatureId2(player),
	}
end

BuddyRemotes.RequestSetBuddy.OnServerEvent:Connect(function(player: Player, creatureId: any)
	local ok, failure, finalCreatureId = BuddyService.SetBuddy(player, creatureId)
	BuddyRemotes.SetBuddyResult:FireClient(player, {
		Success = ok,
		Reason = failure,
		CreatureId = finalCreatureId,
	})
end)

-- Extra Buddy Slot Gamepass (Auftrag "purchasable abilities/boosts") -
-- identisches Verdrahtungsmuster wie RequestSetBuddy oben, für den ZWEITEN
-- Buddy-Slot (siehe BuddyService.SetBuddy2 für die Gamepass-Validierung).
BuddyRemotes.RequestSetBuddy2.OnServerEvent:Connect(function(player: Player, creatureId: any)
	local ok, failure, finalCreatureId = BuddyService.SetBuddy2(player, creatureId)
	BuddyRemotes.SetBuddy2Result:FireClient(player, {
		Success = ok,
		Reason = failure,
		CreatureId = finalCreatureId,
	})
end)

print("[Abyssara] BuddyServer ready (GetBuddyState / RequestSetBuddy / RequestSetBuddy2 wired up).")
