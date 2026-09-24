--[[
	Abyssara – Deep Tide Tycoon
	Skript: ShopServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des kompletten Monetarisierungs-/Shop-Backends
		auf Server-Seite: verbindet die RemoteEvent/RemoteFunction-Kanäle aus
		ShopRemotes mit der reinen Logik in ShopService/MonetizationService.
		Enthält selbst KEINE Kauf-/Katalog-/Effekt-Logik - das bleibt
		vollständig in den beiden Service-Modulen, damit dieses Skript
		austauschbar/dünn bleibt (identisches Muster wie GachaServer.
		server.lua/BreedingServer.server.lua/RaidServer.server.lua).

	Rojo-Einhängepunkt:
		src/server/ShopServer.server.lua -> ServerScriptService.ShopServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		Jeder Remote-Handler unten nimmt ausschließlich den von der Roblox-
		Engine gesetzten `player`-Parameter als vertrauenswürdig entgegen -
		alle weiteren Payload-Werte (ProductKey, ItemId, TargetId) sind roh/
		unvertraut und werden vollständig innerhalb von ShopService/
		MonetizationService validiert.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopService = require(script.Parent:WaitForChild("ShopService"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
local ShopRemotes = require(ReplicatedStorage:WaitForChild("ShopRemotes"))

--- Schickt dem betroffenen Spieler (falls noch online) einen frischen
--- Katalog-Snapshot - gemeinsamer Helfer für alle zustandsändernden Pfade
--- unten (Kosmetik-Kauf/Ausrüsten, Gamepass-Kaufabschluss,
--- Entwicklerprodukt-Gutschrift, Studio-Simulation).
local function pushShopState(player: Player)
	if not (Players:GetPlayerByUserId(player.UserId) == player) then
		return
	end
	ShopRemotes.ShopStateChanged:FireClient(player, ShopService.GetCatalog(player))
end

-- // Katalog --------------------------------------------------------------------

ShopRemotes.GetShopCatalog.OnServerInvoke = function(player: Player)
	return ShopService.GetCatalog(player)
end

-- // Robux-Prompts (Gamepass/Entwicklerprodukt) ---------------------------------

ShopRemotes.RequestPromptGamepassPurchase.OnServerEvent:Connect(function(player: Player, key: any)
	local ok, reason = ShopService.RequestPromptGamepassPurchase(player, key)
	if not ok then
		ShopRemotes.PurchasePromptRejected:FireClient(player, { Reason = reason, ProductKey = tostring(key) })
	end
	-- Bei Erfolg KEIN sofortiges ShopStateChanged - der eigentliche Besitz-
	-- Übergang passiert erst asynchron über PromptGamePassPurchaseFinished
	-- (siehe unten), der Prompt selbst ändert noch nichts am Katalog.
end)

ShopRemotes.RequestPromptDevProductPurchase.OnServerEvent:Connect(function(player: Player, key: any, targetId: any)
	local ok, reason = ShopService.RequestPromptDevProductPurchase(player, key, targetId)
	if not ok then
		ShopRemotes.PurchasePromptRejected:FireClient(player, { Reason = reason, ProductKey = tostring(key) })
	end
end)

-- Gamepass-Kauf ERFOLGREICH abgeschlossen (Roblox-Event) -> Katalog/Besitz-
-- Status hat sich geändert, MonetizationService hat den Cache/die Effekte
-- bereits aktualisiert (siehe dortiger Listener) - hier nur der Push zum
-- betroffenen Client.
game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player: Player, _gamePassId: number, wasPurchased: boolean)
	if wasPurchased then
		pushShopState(player)
	end
end)

-- Entwicklerprodukt-Kauf ERFOLGREICH verarbeitet (ProcessReceipt fertig) ->
-- siehe MonetizationService.PurchaseGranted-Kopfkommentar.
MonetizationService.PurchaseGranted:Connect(function(player: Player, _devProductKey: string)
	pushShopState(player)
end)

-- // Soft-Currency-Kosmetik -------------------------------------------------------

ShopRemotes.RequestPurchaseCosmetic.OnServerInvoke = function(player: Player, itemId: any)
	local result = ShopService.PurchaseCosmetic(player, itemId)
	if result.Success then
		pushShopState(player)
	end
	return result
end

ShopRemotes.RequestEquipCosmetic.OnServerInvoke = function(player: Player, itemId: any)
	local result = ShopService.EquipCosmetic(player, itemId)
	if result.Success then
		pushShopState(player)
	end
	return result
end

-- // Studio-Testmodus (siehe ShopConfig/ShopRemotes/MonetizationService-
-- Kopfkommentare - serverseitig HART auf RunService:IsStudio() begrenzt,
-- diese Verdrahtung hier fügt KEINE zusätzliche Live-Möglichkeit hinzu) -----

ShopRemotes.RequestSimulateStudioPurchase.OnServerEvent:Connect(function(player: Player, kind: any, key: any)
	local ok = ShopService.RequestSimulateStudioPurchase(player, kind, key)
	if ok then
		pushShopState(player)
	end
end)

print("[Abyssara] ShopServer ready (catalog/gamepass prompts/developer product prompts/cosmetics/Studio test mode wired up).")
