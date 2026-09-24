--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: LiveEventConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für das rotierende
		Live-Event-System (docs/content-update-1.md, Abschnitt 1): die feste
		Event-Reihenfolge, die 12h-UTC-Slot-Mathematik (deterministisch,
		serverübergreifend identisch - reine `os.time()`-Arithmetik, kein
		DataStore/keine Cross-Server-Nachricht nötig), sowie je Event die
		Lighting-/Partikel-Stimmung, Gameplay-Modifikatoren, Event-Währung,
		Shop-Katalog, Quest-Linie und die Event-exklusiven Kreaturen.

		Enthält bewusst KEINE Logik (keine Persistenz, keine Tweens, keine
		Zufalls-Rolls) - nur Daten + winzige, reine Lookup-/Zeit-
		Hilfsfunktionen, identisches Prinzip zu RaidConfig/BuildingConfig/
		BreedingConfig/QuestConfig.

	Fairness-Regel (Abschnitt 1.2, siehe LiveEventService):
		Jede Event-exklusive Kreatur ist AUSSCHLIESSLICH über ein Event-Ei
		erhältlich, das mit der KOSTENLOSEN, durch Spielen verdienten
		Event-Währung dieses Events gekauft wird - nie ein reiner Robux-Kauf.
		Die Event-Währung selbst setzt sich bei jedem Slot-Wechsel auf 0
		zurück (siehe LiveEventService.ensureCurrentSlotState) - da die
		6er-Reihenfolge alle 3 Tage wiederkehrt, ist nichts dauerhaft
		verpassbar.

	Rojo-Einhängepunkt:
		src/shared/LiveEventConfig.lua -> ReplicatedStorage.LiveEventConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies nur für Anzeige-Zwecke, die alleinige Autorität über
		Käufe/Fortschritt/Währung bleibt serverseitig in LiveEventService.)
]]

export type EventId = "ToxicTide" | "SpookyTide" | "BioluminescentBloom" | "FrozenCurrent" | "VolcanicVent" | "TreasureTide"

export type LightingProfile = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogEnd: number,
}

export type ParticleProfile = {
	Color1: Color3,
	Color2: Color3,
	Rate: number,
	Direction: "Up" | "Down" | "Horizontal",
}

export type ShopItemType = "CreatureEgg" | "Cosmetic" | "Currency"

export type ShopItem = {
	Id: string,
	DisplayName: string,
	Cost: number,
	Type: ShopItemType,
	CreatureId: string?, -- gesetzt, wenn Type == "CreatureEgg"
	CosmeticSlot: string?, -- gesetzt, wenn Type == "Cosmetic" (siehe ShopConfig.CosmeticSlot-Werte, bewusst nicht cross-requiret)
	ConvertsToTideCoins: number?, -- gesetzt, wenn Type == "Currency" ("Duplikat-Rückkauf")
}

export type QuestStep = {
	Id: string,
	Key: string, -- interner Fortschrittsschlüssel, siehe LiveEventService.AdvanceEventQuest
	Description: string,
	Target: number,
}

export type QuestLine = {
	Title: string,
	Steps: { QuestStep },
	RewardTideCoins: number,
	RewardTitle: string, -- CosmeticState-Titel-Id (Slot "Title"), siehe LiveEventService
}

export type EventCreature = {
	Id: string,
	DisplayName: string,
	Rarity: string,
}

export type EventDefinition = {
	Id: EventId,
	DisplayName: string,
	ColorPrimary: Color3,
	ColorSecondary: Color3,
	Lighting: LightingProfile,
	Particle: ParticleProfile,
	Modifiers: { [string]: any },
	CurrencyId: string,
	CurrencyDisplayName: string,
	CurrencyGlyph: string, -- Platzhalter-Icon-Glyphe, bis echte Icon-Assets (assets/models/ui/) existieren
	EarnPerGlowSpore: number,
	EarnPerRaidWave: number,
	EarnSpecial: { [string]: number }, -- z. B. GhostShipFound/VentPulse/SunkenChestOpened/BreedingCycle
	Creatures: { EventCreature },
	ShopItems: { ShopItem },
	QuestLine: QuestLine,
}

local LiveEventConfig = {}

-- // 1.1 Zeitplan (deterministisch, kein Ruhe-Abstand) -----------------------

LiveEventConfig.EVENT_ORDER = {
	"ToxicTide",
	"SpookyTide",
	"BioluminescentBloom",
	"FrozenCurrent",
	"VolcanicVent",
	"TreasureTide",
} :: { EventId }

LiveEventConfig.SLOT_SECONDS = 12 * 60 * 60 -- 43200

--- Reine Modulo-Arithmetik auf UTC-Epochensekunden (`os.time()` auf Roblox
--- ist bereits UTC) - jeder Server berechnet denselben `slotIndex`
--- unabhängig, ohne DataStore/Cross-Server-Sync. Siehe Abschnitt 1.1.
function LiveEventConfig.GetActiveEventId(unixTimeUtc: number): EventId
	local order = LiveEventConfig.EVENT_ORDER
	local slotIndex = math.floor(unixTimeUtc / LiveEventConfig.SLOT_SECONDS) % #order
	return order[slotIndex + 1]
end

--- Epoch-Sekunde, zu der der AKTUELLE 12h-Slot begann (Slot-Grenzen liegen
--- immer exakt auf 00:00/12:00 UTC, siehe Abschnitt 1.1 - keine
--- Zeitzonen-Mathematik nötig, da rein epoch-ausgerichtet).
function LiveEventConfig.GetSlotStart(unixTimeUtc: number): number
	return math.floor(unixTimeUtc / LiveEventConfig.SLOT_SECONDS) * LiveEventConfig.SLOT_SECONDS
end

--- Epoch-Sekunde, zu der der aktuelle Slot endet (== Start des nächsten
--- Slots, da es KEINE Ruhe-Lücke zwischen Events gibt, siehe Abschnitt 1.1).
function LiveEventConfig.GetSlotEnd(unixTimeUtc: number): number
	return LiveEventConfig.GetSlotStart(unixTimeUtc) + LiveEventConfig.SLOT_SECONDS
end

-- // 1.3 Event-Definitionen ---------------------------------------------------

local EVENTS: { [EventId]: EventDefinition } = {
	ToxicTide = {
		Id = "ToxicTide",
		DisplayName = "Toxic Tide",
		ColorPrimary = Color3.fromRGB(140, 220, 60),
		ColorSecondary = Color3.fromRGB(80, 140, 20),
		Lighting = {
			Ambient = Color3.fromRGB(35, 55, 25),
			OutdoorAmbient = Color3.fromRGB(45, 70, 20),
			FogColor = Color3.fromRGB(70, 110, 30),
			FogEnd = 220,
		},
		Particle = { Color1 = Color3.fromRGB(140, 220, 60), Color2 = Color3.fromRGB(80, 140, 20), Rate = 6, Direction = "Up" },
		Modifiers = {
			FilterPlantIncomeMultiplier = 1.5,
			RaidEnemyMoveSpeedMultiplier = 1.2, -- "Venom-Slick": +20% MoveSpeed
			RaidEnemyEyeColor = Color3.fromRGB(150, 255, 60),
			ToxicSporeChance = 0.15,
			ToxicSporeValueMultiplier = 3,
		},
		CurrencyId = "VenomPearls",
		CurrencyDisplayName = "Venom Pearls",
		CurrencyGlyph = "🟢",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 8,
		EarnSpecial = {},
		Creatures = { { Id = "ToxinPuffer", DisplayName = "Toxin Puffer", Rarity = "Rare" } },
		ShopItems = {
			{ Id = "ToxinPufferEgg", DisplayName = "ToxinPuffer Egg", Cost = 180, Type = "CreatureEgg", CreatureId = "ToxinPuffer" },
			{ Id = "VenomDrip", DisplayName = "Venom Drip (Deko)", Cost = 60, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "ToxicTideDiverDye", DisplayName = "Toxic Tide Taucheranzug-Farbe", Cost = 90, Type = "Cosmetic", CosmeticSlot = "DiverSuitColor" },
			{ Id = "ToxinPufferBuyback", DisplayName = "ToxinPuffer Dublette", Cost = 40, Type = "Currency", ConvertsToTideCoins = 150 },
		},
		QuestLine = {
			Title = "The Slick",
			Steps = {
				{ Id = "CollectPearls", Key = "CollectCurrency", Description = "Sammle 40 Venom Pearls", Target = 40 },
				{ Id = "SurviveRaid", Key = "SurviveRaid", Description = "Überstehe 1 Raid während Toxic Tide", Target = 1 },
				{ Id = "HatchEgg", Key = "HatchEgg", Description = "Schlüpfe ein ToxinPuffer Egg", Target = 1 },
			},
			RewardTideCoins = 300,
			RewardTitle = "Title_ToxinResistant",
		},
	},

	SpookyTide = {
		Id = "SpookyTide",
		DisplayName = "Spooky Tide",
		ColorPrimary = Color3.fromRGB(200, 220, 255),
		ColorSecondary = Color3.fromRGB(60, 50, 110),
		Lighting = {
			Ambient = Color3.fromRGB(20, 20, 35),
			OutdoorAmbient = Color3.fromRGB(20, 20, 35),
			FogColor = Color3.fromRGB(30, 25, 50),
			FogEnd = 160,
		},
		Particle = { Color1 = Color3.fromRGB(200, 220, 255), Color2 = Color3.fromRGB(140, 150, 210), Rate = 5, Direction = "Horizontal" },
		Modifiers = {
			BreedingRareOrBetterBonus = 0.05, -- +5% Chance auf Rare-oder-besser
			RaidEnemyTransparency = 0.35, -- "Wraith-Touched"
			RaidEnemyMaxHPMultiplier = 1.1,
		},
		CurrencyId = "SpiritMotes",
		CurrencyDisplayName = "Spirit Motes",
		CurrencyGlyph = "👻",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 10,
		EarnSpecial = { GhostShipFound = 25 },
		Creatures = { { Id = "PhantomJelly", DisplayName = "Phantom Jelly", Rarity = "Epic" } },
		ShopItems = {
			{ Id = "PhantomJellyEgg", DisplayName = "PhantomJelly Egg", Cost = 260, Type = "CreatureEgg", CreatureId = "PhantomJelly" },
			{ Id = "JackOCoral", DisplayName = "Jack-o-Coral (Deko)", Cost = 70, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "GhostTrailAura", DisplayName = "Ghost-Trail Swim-Partikel", Cost = 100, Type = "Cosmetic", CosmeticSlot = "CreatureGlowColor" },
			{ Id = "PhantomJellyBuyback", DisplayName = "PhantomJelly Dublette", Cost = 55, Type = "Currency", ConvertsToTideCoins = 400 },
		},
		QuestLine = {
			Title = "Things That Glow in the Dark",
			Steps = {
				{ Id = "FindGhostShip", Key = "GhostShipFound", Description = "Finde das Ghost Ship einmal", Target = 1 },
				{ Id = "CollectMotes", Key = "CollectCurrency", Description = "Sammle 60 Spirit Motes", Target = 60 },
				{ Id = "SurviveRaids", Key = "SurviveRaid", Description = "Überstehe 2 Raids während Spooky Tide", Target = 2 },
			},
			RewardTideCoins = 350,
			RewardTitle = "Title_GhostDiver",
		},
	},

	BioluminescentBloom = {
		Id = "BioluminescentBloom",
		DisplayName = "Bioluminescent Bloom",
		ColorPrimary = Color3.fromRGB(90, 220, 255),
		ColorSecondary = Color3.fromRGB(220, 90, 255),
		Lighting = {
			Ambient = Color3.fromRGB(20, 45, 55),
			OutdoorAmbient = Color3.fromRGB(20, 45, 55),
			FogColor = Color3.fromRGB(15, 60, 70),
			FogEnd = 260,
		},
		Particle = { Color1 = Color3.fromRGB(90, 220, 255), Color2 = Color3.fromRGB(220, 90, 255), Rate = 10, Direction = "Up" },
		Modifiers = {
			GlowBuoyStationIncomeMultiplier = 1.4,
			PulseGlowIntensityMultiplier = 1.5,
			BreedingIncubationTimeMultiplier = 0.8, -- -20%
		},
		CurrencyId = "BloomDust",
		CurrencyDisplayName = "Bloom Dust",
		CurrencyGlyph = "🌸",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 0,
		EarnSpecial = { BreedingCycle = 6 },
		Creatures = { { Id = "BloomMoth", DisplayName = "Bloom Moth", Rarity = "Uncommon" } },
		ShopItems = {
			{ Id = "BloomMothEgg", DisplayName = "BloomMoth Egg", Cost = 140, Type = "CreatureEgg", CreatureId = "BloomMoth" },
			{ Id = "CoralGardenSet", DisplayName = "Coral Garden Set (Deko)", Cost = 65, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "RainbowGlowUnlock", DisplayName = "Regenbogen-Leuchtfarbe", Cost = 120, Type = "Cosmetic", CosmeticSlot = "CreatureGlowColor" },
			{ Id = "BloomMothBuyback", DisplayName = "BloomMoth Dublette", Cost = 30, Type = "Currency", ConvertsToTideCoins = 100 },
		},
		QuestLine = {
			Title = "Full Bloom",
			Steps = {
				{ Id = "CollectDust", Key = "CollectCurrency", Description = "Sammle 50 Bloom Dust", Target = 50 },
				{ Id = "CompleteBreeding", Key = "BreedingCycle", Description = "Schließe 1 Zucht während des Events ab", Target = 1 },
				{ Id = "HatchEgg", Key = "HatchEgg", Description = "Schlüpfe ein BloomMoth Egg", Target = 1 },
			},
			RewardTideCoins = 250,
			RewardTitle = "Title_BloomKeeper",
		},
	},

	FrozenCurrent = {
		Id = "FrozenCurrent",
		DisplayName = "Frozen Current",
		ColorPrimary = Color3.fromRGB(180, 210, 230),
		ColorSecondary = Color3.fromRGB(90, 130, 170),
		Lighting = {
			Ambient = Color3.fromRGB(50, 65, 80),
			OutdoorAmbient = Color3.fromRGB(50, 65, 80),
			FogColor = Color3.fromRGB(180, 210, 230),
			FogEnd = 200,
		},
		Particle = { Color1 = Color3.fromRGB(210, 235, 250), Color2 = Color3.fromRGB(180, 210, 230), Rate = 6, Direction = "Down" },
		Modifiers = {
			BuildingIncomeMultiplier = 0.9, -- -10% auf ALLE Gebäude
			RaidEnemyMoveSpeedMultiplier = 0.75, -- -25%
			FrozenSporeChance = 0.10,
			FrozenSporeValueMultiplier = 4,
			FrozenSporeThawSeconds = 3,
		},
		CurrencyId = "FrostShards",
		CurrencyDisplayName = "Frost Shards",
		CurrencyGlyph = "❄️",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 12,
		EarnSpecial = { FrozenSporeThawed = 1 },
		Creatures = { { Id = "FrostAnglerPup", DisplayName = "Frost Angler Pup", Rarity = "Rare" } },
		ShopItems = {
			{ Id = "FrostAnglerPupEgg", DisplayName = "FrostAnglerPup Egg", Cost = 190, Type = "CreatureEgg", CreatureId = "FrostAnglerPup" },
			{ Id = "IceSpire", DisplayName = "Ice Spire (Deko)", Cost = 65, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "FrostBreathAura", DisplayName = "Frost-Atem-Partikel", Cost = 85, Type = "Cosmetic", CosmeticSlot = "CreatureGlowColor" },
			{ Id = "FrostAnglerPupBuyback", DisplayName = "FrostAnglerPup Dublette", Cost = 40, Type = "Currency", ConvertsToTideCoins = 150 },
		},
		QuestLine = {
			Title = "Thaw Watch",
			Steps = {
				{ Id = "ThawSpores", Key = "FrozenSporeThawed", Description = "Taue und sammle 10 Frozen Spores", Target = 10 },
				{ Id = "CollectShards", Key = "CollectCurrency", Description = "Sammle 50 Frost Shards", Target = 50 },
				{ Id = "SurviveRaids", Key = "SurviveRaid", Description = "Überstehe 2 Raids", Target = 2 },
			},
			RewardTideCoins = 300,
			RewardTitle = "Title_Frostwalker",
		},
	},

	VolcanicVent = {
		Id = "VolcanicVent",
		DisplayName = "Volcanic Vent",
		ColorPrimary = Color3.fromRGB(255, 120, 30),
		ColorSecondary = Color3.fromRGB(90, 30, 10),
		Lighting = {
			Ambient = Color3.fromRGB(60, 25, 15),
			OutdoorAmbient = Color3.fromRGB(60, 25, 15),
			FogColor = Color3.fromRGB(90, 30, 10),
			FogEnd = 180,
		},
		Particle = { Color1 = Color3.fromRGB(255, 120, 30), Color2 = Color3.fromRGB(255, 180, 60), Rate = 8, Direction = "Up" },
		Modifiers = {
			RaidIntervalMultiplier = 0.7, -- -30% Raid-Intervall
			RaidEnemyMaxHPMultiplier = 1.15, -- "Magma-Forged"
			RaidEnemyBodyColor = Color3.fromRGB(200, 70, 30),
			VentSurgeIncomeMultiplier = 1.25,
			VentPulseIntervalSeconds = 8 * 60, -- alle ~8 Minuten ein "Vent-Puls" (Server-Broadcast, siehe LiveEventService)
		},
		CurrencyId = "EmberShards",
		CurrencyDisplayName = "Ember Shards",
		CurrencyGlyph = "🔥",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 10,
		EarnSpecial = { VentPulse = 5 },
		Creatures = {
			{ Id = "EmberSlug", DisplayName = "Ember Slug", Rarity = "Uncommon" },
			{ Id = "VentDrake", DisplayName = "Vent Drake", Rarity = "Legendary" },
		},
		ShopItems = {
			{ Id = "EmberSlugEgg", DisplayName = "EmberSlug Egg", Cost = 130, Type = "CreatureEgg", CreatureId = "EmberSlug" },
			{ Id = "VentDrakeEgg", DisplayName = "VentDrake Egg", Cost = 420, Type = "CreatureEgg", CreatureId = "VentDrake" },
			{ Id = "MagmaVent", DisplayName = "Magma Vent (Deko)", Cost = 70, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "EmberSlugBuyback", DisplayName = "EmberSlug Dublette", Cost = 35, Type = "Currency", ConvertsToTideCoins = 120 },
			{ Id = "VentDrakeBuyback", DisplayName = "VentDrake Dublette", Cost = 110, Type = "Currency", ConvertsToTideCoins = 900 },
		},
		QuestLine = {
			Title = "Into the Vent",
			Steps = {
				{ Id = "WitnessPulses", Key = "VentPulse", Description = "Erlebe 5 Vent-Pulse", Target = 5 },
				{ Id = "SurviveRaids", Key = "SurviveRaid", Description = "Überstehe 3 Raids während Volcanic Vent", Target = 3 },
				{ Id = "CollectShards", Key = "CollectCurrency", Description = "Sammle 80 Ember Shards", Target = 80 },
			},
			RewardTideCoins = 400,
			RewardTitle = "Title_VentDiver",
		},
	},

	TreasureTide = {
		Id = "TreasureTide",
		DisplayName = "Treasure Tide",
		ColorPrimary = Color3.fromRGB(255, 220, 120),
		ColorSecondary = Color3.fromRGB(120, 105, 40),
		Lighting = {
			Ambient = Color3.fromRGB(55, 50, 25),
			OutdoorAmbient = Color3.fromRGB(55, 50, 25),
			FogColor = Color3.fromRGB(120, 105, 40),
			FogEnd = 260,
		},
		Particle = { Color1 = Color3.fromRGB(255, 220, 120), Color2 = Color3.fromRGB(255, 245, 200), Rate = 5, Direction = "Up" },
		Modifiers = {
			TideCoinIncomeMultiplier = 1.25, -- ALLE Gebäude
			RaidVictoryCoinMultiplier = 1.5,
			SunkenChestValueTideCoins = 150,
			SunkenChestSpawnIntervalSeconds = 60 * 60, -- einmal/Stunde je Plot
		},
		CurrencyId = "Doubloons",
		CurrencyDisplayName = "Doubloons",
		CurrencyGlyph = "🪙",
		EarnPerGlowSpore = 1,
		EarnPerRaidWave = 15,
		EarnSpecial = { SunkenChestOpened = 20 },
		Creatures = {
			{ Id = "GoldGuppy", DisplayName = "Gold Guppy", Rarity = "Rare" },
			{ Id = "TreasureTurtle", DisplayName = "Treasure Turtle", Rarity = "Epic" },
		},
		ShopItems = {
			{ Id = "GoldGuppyEgg", DisplayName = "GoldGuppy Egg", Cost = 170, Type = "CreatureEgg", CreatureId = "GoldGuppy" },
			{ Id = "TreasureTurtleEgg", DisplayName = "TreasureTurtle Egg", Cost = 310, Type = "CreatureEgg", CreatureId = "TreasureTurtle" },
			{ Id = "TreasurePile", DisplayName = "Treasure Pile (Deko)", Cost = 60, Type = "Cosmetic", CosmeticSlot = "Decoration" },
			{ Id = "GoldGuppyBuyback", DisplayName = "GoldGuppy Dublette", Cost = 35, Type = "Currency", ConvertsToTideCoins = 150 },
			{ Id = "TreasureTurtleBuyback", DisplayName = "TreasureTurtle Dublette", Cost = 70, Type = "Currency", ConvertsToTideCoins = 350 },
		},
		QuestLine = {
			Title = "X Marks the Spot",
			Steps = {
				{ Id = "OpenChests", Key = "SunkenChestOpened", Description = "Öffne 4 Sunken Chests", Target = 4 },
				{ Id = "CollectDoubloons", Key = "CollectCurrency", Description = "Sammle 60 Doubloons", Target = 60 },
				{ Id = "WinRaid", Key = "SurviveRaid", Description = "Gewinne 1 Raid während Treasure Tide", Target = 1 },
			},
			RewardTideCoins = 500,
			RewardTitle = "Title_TreasureHunter",
		},
	},
} :: { [EventId]: EventDefinition }

LiveEventConfig.EVENTS = EVENTS

--- Liefert die vollständige Definition eines Events, oder nil bei
--- unbekannter Id (defensiv - z. B. ältere/künftig entfernte Event-Ids in
--- gespeicherten Spielerdaten).
function LiveEventConfig.GetEvent(eventId: string): EventDefinition?
	return EVENTS[eventId :: EventId]
end

--- Liefert die Definition des GERADE aktiven Events für den übergebenen
--- Zeitpunkt (Default: `os.time()`).
function LiveEventConfig.GetActiveEvent(unixTimeUtc: number?): EventDefinition
	local now = unixTimeUtc or os.time()
	local eventId = LiveEventConfig.GetActiveEventId(now)
	return EVENTS[eventId]
end

--- Liefert eine Shop-Item-Definition eines Events, oder nil.
function LiveEventConfig.GetShopItem(eventId: string, itemId: string): ShopItem?
	local event = EVENTS[eventId :: EventId]
	if not event then
		return nil
	end
	for _, item in ipairs(event.ShopItems) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

--- Liefert eine Event-Kreatur-Definition (Id -> {DisplayName, Rarity}), oder
--- nil, falls `creatureId` keine Event-Kreatur DIESES Events ist.
function LiveEventConfig.GetEventCreature(eventId: string, creatureId: string): EventCreature?
	local event = EVENTS[eventId :: EventId]
	if not event then
		return nil
	end
	for _, creature in ipairs(event.Creatures) do
		if creature.Id == creatureId then
			return creature
		end
	end
	return nil
end

return LiveEventConfig
