--[[
	Abyssara – Deep Tide Tycoon
	Modul: BreedingConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für das Zucht-/Ei-System
		(GDD Abschnitt 3 "Füttert & züchtet Kreaturen in Brutbecken, Timer-
		basiert, wie Ei-Schlüpfen" + Abschnitt 9, Punkt 4 "Zucht-/Ei-System:
		Timer-basierte Inkubation, Genetik-/Rarity-Roll-Logik, Kreaturen-
		Kodex-Update"): Inkubationsdauer, Fütterungskosten und Rarity-
		Gewichtungstabelle je Brutbecken-Stufe. Enthält bewusst KEINE Zufalls-
		/Roll-Logik selbst (die lebt in BreedingService) - nur Daten + kleine,
		reine Hilfsfunktionen darauf. Gleiches Muster wie GachaConfig.lua für
		das Mystery-Egg-Gacha-System.

	Rojo-Einhängepunkt:
		src/shared/BreedingConfig.lua -> ReplicatedStorage.BreedingConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies NUR für Anzeige-Zwecke, z. B. Fütterungskosten/Timer/Odds
		im Brutbecken-UI. Die alleinige Autorität über Start/Abschluss einer
		Zucht bleibt BreedingService auf dem Server, siehe dort.)

	WICHTIGER UNTERSCHIED ZU GachaConfig (bewusste Design-Entscheidung):
		GachaConfig liegt bewusst NICHT unter ReplicatedStorage/src/shared,
		weil das Mystery-Egg-Gacha ein Robux-Kaufprodukt ist und laut Roblox-
		Compliance kontrolliert offengelegt werden soll (nur über den
		serverseitigen RemoteFunction-Kanal GetGachaOdds). Zucht ist dagegen
		laut GDD Abschnitt 5 explizit der KOSTENLOSE, "grindbare" Gegenpart
		zum Pay-Weg Gacha - volle Transparenz der Zucht-Odds direkt im Client
		(z. B. "Chance auf Selten: 7%") ist hier erwünschtes Spieldesign statt
		ein Compliance-Risiko, deshalb darf BreedingConfig als geteiltes Modul
		leben. Aus demselben Grund dupliziert dieses Modul den Kreaturen-Pool
		(CREATURE_POOL) lokal, statt GachaConfig zu requiren: GachaConfig
		liegt unter ServerScriptService und wäre für ein clientseitig
		lesbares Shared-Modul gar nicht erreichbar. Model-Namen bleiben
		trotzdem identisch zu GachaConfig.CREATURE_POOL (== assets/models/
		creatures/*.lua) - Zucht- und Gacha-Ergebnisse landen dadurch im
		selben CreatureInstance-Inventarformat (PlayerDataService.
		AddCreatureToInventory), ohne einen zweiten Kreaturen-Katalog zu
		erfinden.

	Design-Entscheidung: Zucht-Odds bewusst NIEDRIGER als Gacha-Odds:
		GDD Abschnitt 5 positioniert Mystery Egg (89 Robux, Gacha) und Zucht
		(gratis, Zeit+Tide-Coins) als zwei Wege zu denselben Kreaturen -
		Zucht muss langsamer/unwahrscheinlicher bei seltenen Ergebnissen
		bleiben, sonst hätte das Robux-Produkt keinen Mehrwert mehr
		("Pay-to-skip-the-grind" statt "Pay-to-win" ist das Ziel). Deshalb:
			- Rare/Epic/Legendary-Gewichte je Zucht-Stufe bleiben durchweg
			  UNTER den Gacha-Werten (GachaConfig.DROP_TABLE: Rare 16 %,
			  Epic 8 %, Legendary 3,5 %, Mythic 0,5 %).
			- Zucht kennt gar kein "Mythic"-Ergebnis (nur Common..Legendary) -
			  Mythic bleibt exklusiv dem Gacha-Pfad vorbehalten (bzw. hat
			  ohnehin noch kein eigenes Kreaturen-Asset, siehe GachaConfig).
			- Als Ausgleich: KEIN Echtgeld-Kosten, nur Zeit (Inkubation) +
			  Tide Coins (aus dem Idle-Einkommen erspielbar) - "der Grind
			  lohnt sich", ohne Gacha zu entwerten.

	Zucht-Stufen (BREEDING_TIERS, indiziert nach HabitatPlacement.Level des
	BroodPool-Gebäudes):
		Das MVP-Bauplatzierungs-System (siehe BuildingConfig.lua) platziert
		aktuell ausschließlich BroodPool_Basic mit Level = 1 - ein Gebäude-
		Upgrade-System (Advanced/Master, GDD Abschnitt 8: "Brutbecken, 3
		Stufen") existiert serverseitig noch nicht. Damit dieses Modul nicht
		neu geschrieben werden muss, sobald es das gibt, ist die Tabelle
		bereits für Level 1-3 vorbereitet: höhere Stufen inkubieren länger
		UND teurer, dafür mit spürbar besseren (aber weiterhin unter Gacha
		liegenden) Rarity-Chancen - "gestaffelt plausibel, kürzer für Common-
		lastige Stufen, länger für Stufen mit selteneren möglichen
		Ergebnissen" (siehe Auftrag). BreedingConfig.GetTier() klemmt
		unbekannte/zukünftige Level defensiv auf den höchsten definierten
		Eintrag.
]]

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityDefinition = {
	DisplayLabel: string,
	Color: Color3,
}

export type BreedingTier = {
	Level: number, -- HabitatPlacement.Level des BroodPool-Gebäudes (1 = Basic, 2 = Advanced, 3 = Master)
	DisplayName: string,
	IncubationMinutes: number,
	FeedCostTideCoins: number,
	RarityWeights: { [Rarity]: number }, -- Summe je Stufe == 100
}

local BreedingConfig = {}

-- // Rarity-Reihenfolge (Common = schwächste, Mythic = stärkste Zucht-
-- Stufe). "Mythic" wurde mit Content Update 1 ergänzt - AUSSCHLIESSLICH für
-- CrystalLeviathan (HadalDepths, siehe Abschnitt 6/CREATURE_POOL unten) und
-- AUSSCHLIESSLICH über TIERS[3].RarityWeights.Mythic erreichbar (Tier 1/2
-- haben keinen Mythic-Weight-Eintrag -> rollWeightedRarity kann dort nie
-- Mythic würfeln). Alle anderen Rarities bleiben wie zuvor klar unter den
-- Gacha-Odds (siehe Design-Entscheidung im Kopfkommentar).
BreedingConfig.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { Rarity }

BreedingConfig.RARITY_DEFINITIONS = {
	Common = { DisplayLabel = "Gewöhnlich", Color = Color3.fromRGB(215, 250, 245) },
	Uncommon = { DisplayLabel = "Ungewöhnlich", Color = Color3.fromRGB(120, 235, 205) },
	Rare = { DisplayLabel = "Selten", Color = Color3.fromRGB(70, 210, 235) },
	Epic = { DisplayLabel = "Episch", Color = Color3.fromRGB(170, 90, 255) },
	Legendary = { DisplayLabel = "Legendär", Color = Color3.fromRGB(150, 70, 255) },
	-- Farbe identisch zu GachaConfig.DROP_TABLE.Mythic.Color (siehe
	-- Content-Update-Dokument, Abschnitt 5.2: Codex-Karten müssen dieselbe
	-- Rarity-Farbkonvention wie GachaOddsPanel.lua verwenden).
	Mythic = { DisplayLabel = "Mythisch", Color = Color3.fromRGB(135, 60, 255) },
} :: { [Rarity]: RarityDefinition }

-- // Kreaturen-Pool je Rarity (Model-Namen identisch zu GachaConfig.
-- CREATURE_POOL / assets/models/creatures/*.lua, siehe Kopfkommentar). Dies
-- ist der Pool, der an JEDER Zucht-Stufe verfügbar ist (Tier 1-3) - die
-- Zonen-Pools unten (MIDNIGHT_ZONE_CREATURE_POOL/HADAL_DEPTHS_CREATURE_POOL)
-- kommen erst ab Tier 2 bzw. 3 zusätzlich dazu, siehe GetCreaturePool.
BreedingConfig.CREATURE_POOL = {
	Common = { "GlowJelly", "GlowShrimp" },
	Uncommon = { "GlowRay" },
	Rare = { "Anglerfish" },
	Epic = { "BioluminescentEel" },
	Legendary = { "CrystalKraken" },
	-- Content Update 1, Abschnitt 6 (HadalDepths): CrystalLeviathan ist die
	-- EINZIGE Zucht-Mythic-Möglichkeit, absichtlich NICHT zonen-gated wie
	-- die übrigen 8 (sie ist ohnehin nur über TIERS[3].RarityWeights.Mythic
	-- mit 0,5% erreichbar - siehe Kopfkommentar).
	Mythic = { "CrystalLeviathan" },
} :: { [Rarity]: { string } }

-- // Zonen-Kreaturen-Pools (Content Update 1, Abschnitt 2.1/2.2/6) -----------
-- Getrennt von CREATURE_POOL geführt, damit die Basis-6-Kreaturen-Pools an
-- JEDER Stufe unverändert bleiben (siehe Auftrag: "sie erscheinen NICHT in
-- den Zone-1/2-Pools, Odds-Tabellen für bestehende Zonen bleiben
-- unangetastet") - GetCreaturePool unten kombiniert sie erst zur Laufzeit,
-- abhängig von der BroodPool-Stufe.
local MIDNIGHT_ZONE_CREATURE_POOL: { [Rarity]: { string } } = {
	Uncommon = { "ObsidianCrab" },
	Rare = { "LanternWraith" },
	Epic = { "MagmaSquid" },
	Legendary = { "VoidHammerhead" },
}

local HADAL_DEPTHS_CREATURE_POOL: { [Rarity]: { string } } = {
	Uncommon = { "TrenchWisp" },
	Rare = { "AbyssalIsopod" },
	Epic = { "GhostFinTuna" },
	-- CrystalLeviathan (Mythic) läuft bewusst über CREATURE_POOL.Mythic
	-- oben, nicht über diesen Zonen-Pool (siehe dortiger Kommentar).
}

--- Liefert den tatsächlich für eine Zucht-Stufe (`tierLevel`, 1-3) UND
--- `rarity` gültigen Kreaturen-Pool: Basis-Pool (immer) + MidnightZone-Pool
--- (ab Tier 2) + HadalDepths-Pool (ab Tier 3) - Content Update 1, Abschnitt
--- 6: "BroodPool Level 2 ... ist die erste Stufe, deren RarityWeights eine
--- MidnightZone-Kreatur würfeln kann" / "Level 3 ... ist die einzige Stufe,
--- die eine HadalDepths-Kreatur würfeln kann". Liefert nie nil (ggf. leere
--- Tabelle), Aufrufer prüft selbst auf #pool == 0.
function BreedingConfig.GetCreaturePool(rarity: Rarity, tierLevel: number?): { string }
	local pool = {}
	for _, creatureId in ipairs(BreedingConfig.CREATURE_POOL[rarity] or {}) do
		table.insert(pool, creatureId)
	end

	local clampedTier = math.clamp(math.floor(tonumber(tierLevel) or BreedingConfig.MIN_TIER_LEVEL), BreedingConfig.MIN_TIER_LEVEL, BreedingConfig.MAX_TIER_LEVEL)

	if clampedTier >= 2 then
		for _, creatureId in ipairs(MIDNIGHT_ZONE_CREATURE_POOL[rarity] or {}) do
			table.insert(pool, creatureId)
		end
	end
	if clampedTier >= 3 then
		for _, creatureId in ipairs(HADAL_DEPTHS_CREATURE_POOL[rarity] or {}) do
			table.insert(pool, creatureId)
		end
	end

	return pool
end

-- // Anzeigenamen-Fallback je Kreatur (identisch zu GachaConfig.
-- CREATURE_DISPLAY_NAME_FALLBACK) --------------------------------------------
BreedingConfig.CREATURE_DISPLAY_NAME_FALLBACK = {
	GlowJelly = "Glühqualle",
	GlowShrimp = "Leuchtgarnele",
	GlowRay = "Leuchtrochen",
	Anglerfish = "Anglerfisch",
	BioluminescentEel = "Biolumineszenz-Aal",
	CrystalKraken = "Kristallkrake",
	-- Content Update 1, Abschnitt 2.1 (MidnightZone):
	LanternWraith = "Laternengeist",
	ObsidianCrab = "Obsidiankrabbe",
	MagmaSquid = "Magmakalmar",
	VoidHammerhead = "Leerenhammerhai",
	-- Content Update 1, Abschnitt 2.2 (HadalDepths):
	TrenchWisp = "Grabenwisp",
	AbyssalIsopod = "Abgrund-Assel",
	GhostFinTuna = "Geisterflossen-Thun",
	CrystalLeviathan = "Kristall-Leviathan",
} :: { [string]: string }

-- // Zucht-Stufen ---------------------------------------------------------
-- Vgl. GachaConfig.DROP_TABLE zum Vergleich (Rare 16 / Epic 8 / Legendary
-- 3,5 / Mythic 0,5): JEDE Zucht-Stufe bleibt bei Rare/Epic/Legendary klar
-- darunter - siehe Design-Entscheidung im Kopfkommentar.
BreedingConfig.TIERS = {
	[1] = {
		Level = 1,
		DisplayName = "Brutbecken (Basisstufe)",
		IncubationMinutes = 8, -- kurz: einzige aktuell tatsächlich baubare Stufe (BroodPool_Basic), Kern-Loop-freundlich
		FeedCostTideCoins = 100,
		RarityWeights = { Common = 70, Uncommon = 21, Rare = 7, Epic = 1.7, Legendary = 0.3 },
	},
	[2] = {
		-- Content Update 1, Abschnitt 6: erste Stufe, die eine
		-- MidnightZone-Kreatur würfeln kann (siehe GetCreaturePool).
		Level = 2,
		DisplayName = "Brutbecken (Fortgeschritten)",
		IncubationMinutes = 20,
		FeedCostTideCoins = 280,
		RarityWeights = { Common = 48, Uncommon = 30, Rare = 16, Epic = 5, Legendary = 1 },
	},
	[3] = {
		-- Content Update 1, Abschnitt 6: einzige Stufe, die eine
		-- HadalDepths-Kreatur würfeln kann (siehe GetCreaturePool),
		-- einschließlich eines kleinen (0,5%) Mythic-Anteils, der
		-- ausschließlich CrystalLeviathan trifft (CREATURE_POOL.Mythic hat
		-- nur diesen einen Eintrag) - "kleine Chance auf denselben
		-- Top-Tier-Reward wie der Gacha-Pfad", siehe Kopfkommentar.
		Level = 3,
		DisplayName = "Brutbecken (Meisterstufe)",
		IncubationMinutes = 45,
		FeedCostTideCoins = 650,
		RarityWeights = { Common = 30, Uncommon = 32, Rare = 25, Epic = 10, Legendary = 2.5, Mythic = 0.5 },
	},
} :: { [number]: BreedingTier }

BreedingConfig.MAX_TIER_LEVEL = 3
BreedingConfig.MIN_TIER_LEVEL = 1

-- // Hilfsfunktionen --------------------------------------------------------

--- Liefert die Zucht-Stufe für ein gegebenes BroodPool-`level` (z. B.
--- HabitatPlacement.Level). Klemmt defensiv auf [MIN_TIER_LEVEL,
--- MAX_TIER_LEVEL] - ein unbekannter/zukünftiger Level (z. B. durch ein noch
--- nicht existierendes Upgrade-System) führt NIE zu einem nil-Ergebnis,
--- sondern fällt auf die nächstgelegene definierte Stufe zurück.
function BreedingConfig.GetTier(level: number?): BreedingTier
	local clamped = math.clamp(math.floor(tonumber(level) or BreedingConfig.MIN_TIER_LEVEL), BreedingConfig.MIN_TIER_LEVEL, BreedingConfig.MAX_TIER_LEVEL)
	return BreedingConfig.TIERS[clamped] :: BreedingTier
end

--- Summe aller Rarity-Gewichte einer Stufe (praktisch immer 100, aber bewusst
--- nicht hart einprogrammiert, siehe GachaConfig.GetTotalWeight-Analogon).
function BreedingConfig.GetTotalWeight(tier: BreedingTier): number
	local total = 0
	for _, weight in pairs(tier.RarityWeights) do
		total += weight
	end
	return total
end

--- Liefert den 1-basierten Index einer Rarity in RARITY_ORDER.
function BreedingConfig.GetRarityIndex(rarity: Rarity): number
	local order = BreedingConfig.RARITY_ORDER
	for index = 1, #order do
		if order[index] == rarity then
			return index
		end
	end
	error(("[BreedingConfig] Unbekannte Rarity: %s"):format(tostring(rarity)))
end

return BreedingConfig
