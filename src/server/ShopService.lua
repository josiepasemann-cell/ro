--[[
	Abyssara – Deep Tide Tycoon
	Modul: ShopService
	Zuständigkeit:
		Katalog-Aufbau + Soft-Currency-Kosmetik-Logik des Shop-Backends (GDD
		Abschnitt 5 "Monetarisierung" + Abschnitt 9, Punkt 9): liefert dem
		Client einen vollständigen, personalisierten Shop-Katalog (Gamepasses/
		Entwicklerprodukte inkl. Besitz-/Kaufbarkeits-Status + Mystery-Egg-
		Odds, Kosmetik-Artikel inkl. Besitz/Ausrüstung, tägliche Angebote-
		Rotation), validiert + verarbeitet Soft-Currency-Käufe (Tide Coins/
		Abyssal Shards) für Kosmetik, und delegiert alle Robux-Prompt-
		Anfragen (Gamepass/Entwicklerprodukt) sowie den Studio-Testmodus an
		MonetizationService (Single Source of Truth für MarketplaceService).

		Reine Logik, keine Remote-Verdrahtung - die übernimmt
		ShopServer.server.lua (identisches Muster wie GachaService/
		GachaServer.server.lua).

	Sicherheitsprinzip (kein Client-Trust):
		Jede Kosmetik-Kauf-/Ausrüsten-Anfrage nimmt ausschließlich eine rohe,
		unvertraute `itemId` entgegen - Preis, Währung, Slot und Besitzstatus
		werden IMMER serverseitig aus ShopConfig/PlayerDataService neu
		bestimmt, niemals vom Client übernommen.

	Rojo-Einhängepunkt:
		src/server/ShopService.lua -> ServerScriptService.ShopService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GachaService = require(script.Parent:WaitForChild("GachaService"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

type CosmeticItemDefinition = ShopConfig.CosmeticItemDefinition

local ShopService = {}

-- // Katalog -------------------------------------------------------------------

local function buildGamepassCatalog(player: Player): { { [string]: any } }
	local rows = {}
	for _, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local definition = ShopConfig.GAMEPASSES[key]
		local owned = MonetizationService.PlayerOwnsGamepass(player, key)
		table.insert(rows, {
			Key = definition.Key,
			Name = definition.Name,
			Description = definition.Description,
			PriceRobuxDisplay = definition.PriceRobuxDisplay,
			IconAssetId = definition.IconAssetId,
			Owned = owned,
			-- Nur kaufbar, wenn eine echte Id konfiguriert ist UND der
			-- Spieler ihn nicht bereits besitzt - siehe ShopConfig-
			-- Kopfkommentar "Code muss mit ID 0 sicher sein".
			Purchasable = definition.Id ~= 0 and not owned,
		})
	end
	return rows
end

local function buildDevProductCatalog(player: Player): { { [string]: any } }
	local rows = {}
	for _, key in ipairs(ShopConfig.DEV_PRODUCT_ORDER) do
		local definition = ShopConfig.DEV_PRODUCTS[key]

		local purchasable = definition.Id ~= 0
		local disabledReason: string? = if definition.Id == 0 then "NotConfigured" else nil

		if purchasable and definition.IsPaidRandomItem and not MonetizationService.PlayerMayPurchasePaidRandomItems(player) then
			purchasable = false
			disabledReason = "PaidRandomItemsRestricted"
		end

		if purchasable and definition.Key == "RaidSkip" then
			local today = PlayerDataService.GetUtcDateString()
			if PlayerDataService.GetLastRaidSkipDate(player) == today then
				purchasable = false
				disabledReason = "AlreadyUsedToday"
			end
		end

		local row: { [string]: any } = {
			Key = definition.Key,
			Name = definition.Name,
			Description = definition.Description,
			PriceRobuxDisplay = definition.PriceRobuxDisplay,
			IconAssetId = definition.IconAssetId,
			RequiresTarget = definition.RequiresTarget == true,
			Purchasable = purchasable,
			DisabledReason = disabledReason,
		}

		-- Roblox-Compliance (Auftrag Punkt 6): Mystery-Egg-Odds müssen VOR
		-- dem Kauf sichtbar sein - identische, autoritative Tabelle wie beim
		-- Gratis-Gacha-Weg (GachaService.GetOddsTable), niemals eine
		-- separat gepflegte Kopie.
		if definition.Key == "MysteryEgg" then
			row.Odds = GachaService.GetOddsTable()
		end

		table.insert(rows, row)
	end
	return rows
end

--- Fester Tages-Seed (UTC-Kalendertag) - JEDER Server berechnet daraus
--- deterministisch dieselbe Auswahl, ohne dass Server sich untereinander
--- abstimmen müssten (Auftrag Punkt 5: "damit alle Server gleich
--- rotieren"). `os.date("!*t")` liefert u. a. `yday` (Tag im Jahr,
--- 1..366) - Kombination aus Jahr + yday ist über Jahresgrenzen hinweg
--- eindeutig, im Gegensatz zu `yday` allein.
local function computeDailySeed(): number
	local utcDate = os.date("!*t", os.time()) :: { year: number, yday: number }
	return utcDate.year * 1000 + utcDate.yday
end

--- Liefert die heutigen Kosmetik-"Angebote" (feste Anzahl, siehe
--- ShopConfig.DAILY_ROTATION_OFFER_COUNT), deterministisch aus dem
--- InRotationPool gezogen. Nutzt Random.new(seed) statt math.randomseed -
--- ein dedizierter Random-Stream beeinflusst keine andere Zufallsquelle im
--- Spiel (GachaService/BreedingService/RaidService haben je ihre eigene
--- Random.new()-Instanz).
function ShopService.GetDailyRotationOfferIds(): { string }
	local pool: { string } = {}
	for _, itemId in ipairs(ShopConfig.COSMETIC_ITEM_ORDER) do
		local definition = ShopConfig.COSMETIC_ITEMS[itemId]
		if definition.InRotationPool then
			table.insert(pool, itemId)
		end
	end

	if #pool == 0 then
		return {}
	end

	local rng = Random.new(computeDailySeed())

	-- Fisher-Yates-Teilshuffle auf einer KOPIE des Pools (deterministisch je
	-- Seed, unabhängig von Tabellen-Iterationsreihenfolge, da `pool` bereits
	-- über die feste COSMETIC_ITEM_ORDER aufgebaut wurde).
	local count = math.min(ShopConfig.DAILY_ROTATION_OFFER_COUNT, #pool)
	for i = 1, count do
		local j = rng:NextInteger(i, #pool)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local selected = {}
	for i = 1, count do
		table.insert(selected, pool[i])
	end
	return selected
end

local function buildCosmeticCatalog(player: Player): { { [string]: any } }
	local owned = PlayerDataService.GetOwnedCosmetics(player)
	local equipped = PlayerDataService.GetEquippedCosmetics(player)

	local rows = {}
	for _, itemId in ipairs(ShopConfig.COSMETIC_ITEM_ORDER) do
		local definition = ShopConfig.COSMETIC_ITEMS[itemId]
		table.insert(rows, {
			Id = definition.Id,
			Slot = definition.Slot,
			Name = definition.Name,
			Description = definition.Description,
			Currency = definition.Currency,
			Price = definition.Price,
			IconAssetId = definition.IconAssetId,
			SwatchColor = definition.SwatchColor,
			Owned = owned[itemId] == true,
			Equipped = equipped[definition.Slot] == itemId,
		})
	end
	return rows
end

--- Baut den vollständigen, personalisierten Shop-Katalog für `player` auf -
--- einzige Rückgabestruktur für ShopRemotes.GetShopCatalog UND
--- ShopRemotes.ShopStateChanged (siehe ShopServer.server.lua), damit der
--- UI-Agent nie zwei unterschiedliche Formen desselben Katalogs behandeln
--- muss.
function ShopService.GetCatalog(player: Player): { [string]: any }
	return {
		Gamepasses = buildGamepassCatalog(player),
		DevProducts = buildDevProductCatalog(player),
		Cosmetics = buildCosmeticCatalog(player),
		DailyOfferItemIds = ShopService.GetDailyRotationOfferIds(),
		Currencies = {
			TideCoins = PlayerDataService.GetCurrency(player, "TideCoins"),
			AbyssalShards = PlayerDataService.GetCurrency(player, "AbyssalShards"),
		},
	}
end

-- // Soft-Currency-Kosmetik-Käufe -----------------------------------------------

export type CosmeticPurchaseResult = { Success: boolean, Reason: string?, NewBalance: number? }
export type CosmeticEquipResult = { Success: boolean, Reason: string?, Slot: string? }

--- Kauft `itemId` mit der in ShopConfig hinterlegten Soft-Währung. Validiert
--- vollständig neu (Existenz, Nicht-Doppelbesitz, ausreichendes Guthaben) -
--- der Client liefert ausschließlich die rohe Item-Id.
function ShopService.PurchaseCosmetic(player: Player, itemId: any): CosmeticPurchaseResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if type(itemId) ~= "string" then
		return { Success = false, Reason = "InvalidItem" }
	end

	local definition = ShopConfig.GetCosmeticItem(itemId)
	if not definition then
		return { Success = false, Reason = "UnknownItem" }
	end

	if PlayerDataService.OwnsCosmetic(player, itemId) then
		return { Success = false, Reason = "AlreadyOwned" }
	end

	local balance = PlayerDataService.GetCurrency(player, definition.Currency)
	if balance < definition.Price then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	local chargeOk, newBalance = PlayerDataService.AddCurrency(player, definition.Currency, -definition.Price)
	if not chargeOk then
		return { Success = false, Reason = "ChargeFailed" }
	end

	local granted = PlayerDataService.AddOwnedCosmetic(player, itemId)
	if not granted then
		-- Persistenz fehlgeschlagen (z. B. Daten zwischen Prüfung und
		-- Schreiben entladen) - bereits abgezogene Kosten zurückerstatten.
		PlayerDataService.AddCurrency(player, definition.Currency, definition.Price)
		return { Success = false, Reason = "PersistenceFailed" }
	end

	return { Success = true, NewBalance = newBalance }
end

--- Rüstet einen BEREITS besessenen Kosmetik-Artikel im zugehörigen Slot aus
--- (ersetzt einen evtl. vorher dort ausgerüsteten Artikel).
function ShopService.EquipCosmetic(player: Player, itemId: any): CosmeticEquipResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if type(itemId) ~= "string" then
		return { Success = false, Reason = "InvalidItem" }
	end

	local definition = ShopConfig.GetCosmeticItem(itemId)
	if not definition then
		return { Success = false, Reason = "UnknownItem" }
	end

	if not PlayerDataService.OwnsCosmetic(player, itemId) then
		return { Success = false, Reason = "NotOwned" }
	end

	local ok = PlayerDataService.SetEquippedCosmetic(player, definition.Slot, itemId)
	if not ok then
		return { Success = false, Reason = "PersistenceFailed" }
	end

	return { Success = true, Slot = definition.Slot }
end

-- // Robux-Prompt-Delegation (Single Source of Truth: MonetizationService) ----
-- Dünne Weiterleitung, damit der komplette MarketplaceService-Kontakt an
-- EINER Stelle (MonetizationService) bleibt - ShopService fügt hier bewusst
-- KEINE eigene Validierung hinzu, die von der dort bereits vorhandenen
-- abweichen könnte.

function ShopService.RequestPromptGamepassPurchase(player: Player, key: any): (boolean, string?)
	return MonetizationService.RequestPromptGamepassPurchase(player, key)
end

function ShopService.RequestPromptDevProductPurchase(player: Player, key: any, targetId: any): (boolean, string?)
	return MonetizationService.RequestPromptDevProductPurchase(player, key, targetId)
end

function ShopService.RequestSimulateStudioPurchase(player: Player, kind: any, key: any): (boolean, string?)
	return MonetizationService.RequestSimulateStudioPurchase(player, kind, key)
end

return ShopService
