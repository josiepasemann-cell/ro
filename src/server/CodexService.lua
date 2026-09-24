--[[
	Abyssara – Deep Tide Tycoon
	Modul: CodexService
	Zuständigkeit:
		Serverseitige Kernlogik des Kreaturen-Kodex ("Sammelbuch",
		docs/content-update-1.md Abschnitt 5.2): baut den Katalog ALLER
		aktuell existierenden Kreaturen, wertet Besitz/Vollständigkeit pro
		Zone aus, validiert Favoriten-Auswahl (für die Plot-Anzeige, siehe
		CreatureDisplayService/Abschnitt 5.1) und Zonen-Sammel-Belohnungen.

	WICHTIGSTE DESIGN-ENTSCHEIDUNG (kein hartkodierter Kreaturen-Katalog):
		Der Katalog wird bei JEDEM GetCatalog()-Aufruf frisch aus
		Workspace.Assets.Creatures gelesen (identisches "live vom Modell
		lesen"-Prinzip wie GachaService.getCreatureDisplayName/
		BreedingService) statt einer festen Liste im Code. So tauchen alle
		16 neuen Kreaturen aus Content-Update 1 (8 Zonen- + 8 Event-
		Kreaturen, siehe assets/models/README.md) automatisch auf, sobald
		ihr Buildscript einmal in Studio ausgeführt wurde - ohne dass dieses
		Modul angefasst werden muss. Jedes Kreaturen-Modell trägt bereits
		die Attribute Rarity/Zone/CreatureName (+ optional Event bei
		Event-exklusiven Kreaturen, Zone dann literal "Global") - siehe
		assets/models/README.md, Abschnitt "Namenskonventionen".

		ZUSATZ-FALLBACK (GachaConfig/BreedingConfig.CREATURE_POOL): Ein
		Spieler kann eine Kreatur bereits BESITZEN, bevor ihr Buildscript
		in Studio ausgeführt wurde (GachaService/BreedingService würfeln
		rein aus den Pool-Tabellen, unabhängig davon, ob ein Workspace-
		Modell existiert - siehe GachaService.pickCreatureForRarity). Damit
		so ein Fall im Kodex nicht spurlos verschwindet (kaputte
		Vollständigkeits-Prozente), werden Pool-CreatureIds OHNE Live-Modell
		zusätzlich als Katalog-Eintrag mit Zone = ZONE_UNASSIGNED
		aufgenommen. Sobald das zugehörige Buildscript ausgeführt wird,
		"wandert" der Eintrag beim nächsten GetCatalog()-Aufruf automatisch
		in seine echte Zone/Event-Gruppe - keine manuelle Pflege nötig.

	Rojo-Einhängepunkt:
		src/server/CodexService.lua -> ServerScriptService.CodexService
		(reines Server-Modul; wird von CodexServer.server.lua verdrahtet und
		von CreatureDisplayService NICHT benötigt, siehe dessen
		Kopfkommentar - beide Systeme sind bewusst entkoppelt: die
		Plot-Anzeige braucht nur PlayerDataService.CreatureInventory +
		GachaConfig.GetRarityIndex, keinen vollen Katalog.)

	Sicherheitsprinzip (kein Client-Trust):
		SetFavorites/ClaimZoneReward validieren JEDEN Wert serverseitig neu
		(Besitz, max. 6 Favoriten, Zonen-Vollständigkeit, Einmaligkeit der
		Belohnung) - der Client liefert nur eine Absichtserklärung
		(gewünschte CreatureId-Liste bzw. Zonen-Id), niemals ein fertiges
		Ergebnis.

	Integrations-Hook für andere Systeme (nicht Teil dieses Auftrags):
		Der permanente +2%-Einkommens-Bonus je katalogisierter Zone
		(Abschnitt 5.2: "4 Zonen = +8% gesamt") wird HIER granted/persistiert
		(PlayerDataService.SetCodexZoneRewardClaimed), aber NICHT hier auf
		die tatsächliche Einkommensberechnung angewendet - das ist bewusst
		Aufgabe von IdleIncomeService (nicht Teil dieses Auftrags, siehe
		docs/content-update-1.md 7b), das den fertigen Multiplikator einfach
		über PlayerDataService.GetCodexIncomeMultiplier(player) abfragen
		kann, sobald es selbst erweitert wird.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GachaConfig = require(script.Parent:WaitForChild("GachaConfig"))
local BreedingConfig = require(ReplicatedStorage:WaitForChild("BreedingConfig"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))

export type CatalogEntry = {
	CreatureId: string,
	DisplayName: string,
	Rarity: string,
	Zone: string, -- "SunZone" | "TwilightZone" | "MidnightZone" | "HadalDepths" | ZONE_UNASSIGNED | "Global" (nur bei Event-Kreaturen)
	Event: string?, -- nur gesetzt bei Event-exklusiven Kreaturen (siehe Kopfkommentar)
}

export type Catalog = {
	ZoneOrder: { string }, -- bekannte Zonen-Tabs in fester Reihenfolge, gefolgt von evtl. dynamisch entdeckten weiteren Zonen
	Entries: { CatalogEntry },
}

export type ZoneCompletion = {
	Owned: number,
	Total: number,
	Percent: number,
	RewardClaimed: boolean,
	RewardClaimable: boolean, -- Owned >= Total AND Total > 0 AND NOT RewardClaimed
}

export type CodexPlayerState = {
	OwnedCreatureIds: { [string]: boolean },
	Favorites: { string },
	ClaimedZoneRewards: { [string]: boolean },
	ZoneCompletion: { [string]: ZoneCompletion }, -- nur für KNOWN_ZONES (siehe unten)
	IncomeBonusPercent: number, -- Anzeige-Wert (z. B. 4 == "+4%"), aus PlayerDataService.GetCodexIncomeMultiplier abgeleitet
}

local CodexService = {}

-- // Bekannte Zonen (docs/content-update-1.md 5.2: feste Reihenfolge SunZone
-- -> TwilightZone -> MidnightZone -> HadalDepths) - NUR diese 4 zählen für
-- Vollständigkeits-%/Sammel-Belohnung. Bewusst als kleine, stabile
-- Struktur-Konstante hier hinterlegt (keine Kreaturen-Namen!) - neue Zonen
-- sind ein seltenes strukturelles Ereignis, kein pro-Kreatur-Wartungsfall,
-- und tauchen dank ZoneOrder/GetCatalog trotzdem automatisch in der UI auf,
-- auch falls diese Liste mal hinterherhinkt (siehe resolveZoneOrder unten).
local KNOWN_ZONES = { "SunZone", "TwilightZone", "MidnightZone", "HadalDepths" }
local KNOWN_ZONE_DISPLAY_NAMES: { [string]: string } = {
	SunZone = "Sun Zone",
	TwilightZone = "Twilight Zone",
	MidnightZone = "Midnight Zone",
	HadalDepths = "Hadal Depths",
}

-- Sammelbecken für Kreaturen, deren Zonen-Zugehörigkeit (noch) nicht bekannt
-- ist (siehe Kopfkommentar, Pool-Fallback ohne Live-Modell). Bewusst NICHT
-- "Global" (das ist für Event-Kreaturen reserviert, siehe ToxinPuffer.lua
-- Konvention ZONE = "Global").
local ZONE_UNASSIGNED = "Unassigned"
CodexService.ZONE_UNASSIGNED = ZONE_UNASSIGNED
CodexService.KNOWN_ZONES = KNOWN_ZONES

-- // Zonen-Sammel-Belohnung (Abschnitt 5.2) -----------------------------------
CodexService.ZONE_REWARD_TIDE_COINS = 1000
CodexService.ZONE_INCOME_BONUS_PERCENT = 2 -- muss zu PlayerDataService.CODEX_ZONE_INCOME_BONUS_PER_ZONE (0.02) passen

local MAX_FAVORITES = 6

-- // Katalog-Aufbau ------------------------------------------------------------

--- Liest den Anzeigenamen/Rarity live vom Workspace-Modell, falls
--- vorhanden - sonst Fallback aus GachaConfig/BreedingConfig (identisches
--- Prinzip zu GachaService.getCreatureDisplayName).
local function fallbackDisplayName(creatureId: string): string
	return GachaConfig.CREATURE_DISPLAY_NAME_FALLBACK[creatureId]
		or BreedingConfig.CREATURE_DISPLAY_NAME_FALLBACK[creatureId]
		or creatureId
end

--- Baut den vollständigen Katalog frisch auf (siehe Kopfkommentar - bewusst
--- kein Caching, Kosten sind trivial: ein Folder-Scan über ~20-40 Modelle,
--- nur bei Kodex-Panel-Öffnen/Reward-Claim aufgerufen, kein Hot-Path).
function CodexService.GetCatalog(): Catalog
	local entries: { CatalogEntry } = {}
	local seenCreatureIds: { [string]: boolean } = {}
	local discoveredZones: { [string]: boolean } = {}

	local assetsFolder = Workspace:FindFirstChild("Assets")
	local creaturesFolder = assetsFolder and assetsFolder:FindFirstChild("Creatures")

	if creaturesFolder then
		for _, child in ipairs(creaturesFolder:GetChildren()) do
			if child:IsA("Model") then
				local rarity = child:GetAttribute("Rarity")
				if typeof(rarity) == "string" and rarity ~= "" then
					local creatureId = child.Name
					local zone = child:GetAttribute("Zone")
					local event = child:GetAttribute("Event")
					local displayName = child:GetAttribute("CreatureName")

					local entry: CatalogEntry = {
						CreatureId = creatureId,
						DisplayName = (typeof(displayName) == "string" and displayName ~= "") and displayName
							or fallbackDisplayName(creatureId),
						Rarity = rarity,
						Zone = (typeof(zone) == "string" and zone ~= "") and zone or ZONE_UNASSIGNED,
						Event = (typeof(event) == "string" and event ~= "") and event or nil,
					}

					table.insert(entries, entry)
					seenCreatureIds[creatureId] = true
					if not entry.Event then
						discoveredZones[entry.Zone] = true
					end
				end
			end
		end
	end

	-- Pool-Fallback (siehe Kopfkommentar): jede CreatureId aus den
	-- Zucht-/Gacha-Pools, die noch KEIN Live-Modell hat, damit besessene
	-- "unsichtbare" Kreaturen nicht aus der Vollständigkeits-Zählung fallen.
	local function addPoolFallback(pool: { [string]: { string } })
		for rarity, creatureIds in pairs(pool) do
			for _, creatureId in ipairs(creatureIds) do
				if not seenCreatureIds[creatureId] then
					seenCreatureIds[creatureId] = true
					table.insert(entries, {
						CreatureId = creatureId,
						DisplayName = fallbackDisplayName(creatureId),
						Rarity = rarity,
						Zone = ZONE_UNASSIGNED,
						Event = nil,
					})
				end
			end
		end
	end
	addPoolFallback(GachaConfig.CREATURE_POOL :: any)
	addPoolFallback(BreedingConfig.CREATURE_POOL :: any)

	-- ZoneOrder: bekannte Zonen zuerst (feste Reihenfolge), danach jede
	-- weitere, tatsächlich im Katalog entdeckte Zone (z. B. eine künftige
	-- 5. Zone) alphabetisch, danach ZONE_UNASSIGNED nur falls nicht leer -
	-- Events bekommen client-seitig einen eigenen, festen "Events"-Tab
	-- (siehe CodexUIController), tauchen hier bewusst NICHT als Zone auf.
	local zoneOrder: { string } = {}
	local addedZones: { [string]: boolean } = {}
	for _, zone in ipairs(KNOWN_ZONES) do
		table.insert(zoneOrder, zone)
		addedZones[zone] = true
	end
	local extraZones: { string } = {}
	for zone in pairs(discoveredZones) do
		if not addedZones[zone] and zone ~= ZONE_UNASSIGNED then
			table.insert(extraZones, zone)
		end
	end
	table.sort(extraZones)
	for _, zone in ipairs(extraZones) do
		table.insert(zoneOrder, zone)
		addedZones[zone] = true
	end
	for _, entry in ipairs(entries) do
		if not entry.Event and entry.Zone == ZONE_UNASSIGNED then
			table.insert(zoneOrder, ZONE_UNASSIGNED)
			break
		end
	end

	return { ZoneOrder = zoneOrder, Entries = entries }
end

--- Anzeigename einer Zone für Belohnungs-Titel ("<Zone> Cataloguer").
local function zoneDisplayName(zone: string): string
	return KNOWN_ZONE_DISPLAY_NAMES[zone] or zone
end

-- // Besitz/Vollständigkeit ---------------------------------------------------

local function getOwnedCreatureIdSet(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for _, instance in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		owned[instance.CreatureId] = true
	end
	return owned
end

--- Liefert den vollständigen Kodex-Zustand für `player` (Besitz, Favoriten,
--- abgeholte Zonen-Belohnungen, Vollständigkeits-% je bekannter Zone).
function CodexService.GetPlayerState(player: Player): CodexPlayerState
	local catalog = CodexService.GetCatalog()
	local owned = getOwnedCreatureIdSet(player)

	local totalsByZone: { [string]: number } = {}
	local ownedByZone: { [string]: number } = {}
	for _, entry in ipairs(catalog.Entries) do
		if not entry.Event then
			totalsByZone[entry.Zone] = (totalsByZone[entry.Zone] or 0) + 1
			if owned[entry.CreatureId] then
				ownedByZone[entry.Zone] = (ownedByZone[entry.Zone] or 0) + 1
			end
		end
	end

	local zoneCompletion: { [string]: ZoneCompletion } = {}
	for _, zone in ipairs(KNOWN_ZONES) do
		local total = totalsByZone[zone] or 0
		local ownedCount = ownedByZone[zone] or 0
		local claimed = PlayerDataService.IsCodexZoneRewardClaimed(player, zone)
		zoneCompletion[zone] = {
			Owned = ownedCount,
			Total = total,
			Percent = total > 0 and math.floor((ownedCount / total) * 100 + 0.5) or 0,
			RewardClaimed = claimed,
			RewardClaimable = total > 0 and ownedCount >= total and not claimed,
		}
	end

	local claimedZoneRewards: { [string]: boolean } = {}
	for _, zone in ipairs(KNOWN_ZONES) do
		claimedZoneRewards[zone] = PlayerDataService.IsCodexZoneRewardClaimed(player, zone)
	end

	local incomeMultiplier = PlayerDataService.GetCodexIncomeMultiplier(player)

	return {
		OwnedCreatureIds = owned,
		Favorites = PlayerDataService.GetCodexFavorites(player),
		ClaimedZoneRewards = claimedZoneRewards,
		ZoneCompletion = zoneCompletion,
		IncomeBonusPercent = math.floor((incomeMultiplier - 1) * 100 + 0.5),
	}
end

-- // Favoriten (Plot-Anzeige-Override, Abschnitt 5.1) -------------------------

export type SetFavoritesFailure = "DataNotLoaded" | "TooMany" | "NotOwned" | "InvalidPayload"

--- Validiert + persistiert eine neue Favoriten-Liste. `requestedCreatureIds`
--- kommt vom Client (Absichtserklärung, siehe Kopfkommentar) - JEDER Eintrag
--- wird gegen das tatsächliche Inventar geprüft, Duplikate werden entfernt,
--- die Liste wird auf MAX_FAVORITES gekappt. Gibt (ok, failure?, finalList)
--- zurück; feuert bei Erfolg "CodexFavoritesChanged" über GameEvents, damit
--- CreatureDisplayService die Plot-Anzeige sofort neu aufbaut.
function CodexService.SetFavorites(
	player: Player,
	requestedCreatureIds: { any }
): (boolean, SetFavoritesFailure?, { string }?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded", nil
	end

	if typeof(requestedCreatureIds) ~= "table" then
		return false, "InvalidPayload", nil
	end

	if #requestedCreatureIds > MAX_FAVORITES then
		return false, "TooMany", nil
	end

	local owned = getOwnedCreatureIdSet(player)
	local final: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, rawId in ipairs(requestedCreatureIds) do
		if typeof(rawId) ~= "string" then
			return false, "InvalidPayload", nil
		end
		if not owned[rawId] then
			return false, "NotOwned", nil
		end
		if not seen[rawId] then
			seen[rawId] = true
			table.insert(final, rawId)
		end
	end

	PlayerDataService.SetCodexFavorites(player, final)
	GameEvents.Fire("CodexFavoritesChanged", player, { Favorites = final })

	return true, nil, final
end

-- // Zonen-Sammel-Belohnung (Abschnitt 5.2) -----------------------------------

export type ClaimZoneRewardResult = {
	Zone: string,
	RewardTideCoins: number,
	RewardTitle: string,
	NewIncomeBonusPercent: number,
}

export type ClaimZoneRewardFailure = "DataNotLoaded" | "UnknownZone" | "Incomplete" | "AlreadyClaimed"

--- Validiert + gewährt die einmalige Zonen-Sammel-Belohnung (1000 Tide
--- Coins + Titel + permanenter +2%-Einkommens-Bonus, additiv über Zonen).
--- Gibt (ok, failure?, result?) zurück.
function CodexService.ClaimZoneReward(
	player: Player,
	zone: any
): (boolean, ClaimZoneRewardFailure?, ClaimZoneRewardResult?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded", nil
	end

	if typeof(zone) ~= "string" or not table.find(KNOWN_ZONES, zone) then
		return false, "UnknownZone", nil
	end

	if PlayerDataService.IsCodexZoneRewardClaimed(player, zone) then
		return false, "AlreadyClaimed", nil
	end

	local state = CodexService.GetPlayerState(player)
	local completion = state.ZoneCompletion[zone]
	if not completion or not completion.RewardClaimable then
		return false, "Incomplete", nil
	end

	local title = ("%s Cataloguer"):format(zoneDisplayName(zone))
	local granted = PlayerDataService.SetCodexZoneRewardClaimed(player, zone, title)
	if not granted then
		-- Race Condition (z. B. Doppel-Klick-Anfrage kurz hintereinander):
		-- der Setter selbst ist die letzte Verteidigungslinie, siehe dort.
		return false, "AlreadyClaimed", nil
	end

	PlayerDataService.AddCurrency(player, "TideCoins", CodexService.ZONE_REWARD_TIDE_COINS)

	local newMultiplier = PlayerDataService.GetCodexIncomeMultiplier(player)
	local newBonusPercent = math.floor((newMultiplier - 1) * 100 + 0.5)

	GameEvents.Fire("CodexZoneRewardClaimed", player, {
		Zone = zone,
		RewardTideCoins = CodexService.ZONE_REWARD_TIDE_COINS,
		RewardTitle = title,
	})

	return true,
		nil,
		{
			Zone = zone,
			RewardTideCoins = CodexService.ZONE_REWARD_TIDE_COINS,
			RewardTitle = title,
			NewIncomeBonusPercent = newBonusPercent,
		}
end

return CodexService
