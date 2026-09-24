--[[
	Abyssara – Deep Tide Tycoon
	Modul: ShopConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für das komplette
		Monetarisierungs-/Shop-Backend (GDD Abschnitt 5 "Monetarisierung" +
		Abschnitt 9, Punkt 9 "Monetarisierungs-Integration"): Gamepasses,
		Entwicklerprodukte und der Soft-Currency-Kosmetik-Katalog. Enthält
		bewusst KEINE Kauf-/Effekt-Logik selbst (die lebt in
		MonetizationService/ShopService) - nur Daten + kleine, reine
		Hilfsfunktionen darauf, identisches Prinzip wie GachaConfig/
		BreedingConfig/RaidConfig.

	Rojo-Einhängepunkt:
		src/shared/ShopConfig.lua -> ReplicatedStorage.ShopConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies NUR für Anzeige-Zwecke, z. B. Preise/Icons im Shop-UI, das
		ein anderer Agent auf Basis von ShopService/ShopRemotes baut. Die
		alleinige Autorität über Käufe/Effekte bleibt MonetizationService/
		ShopService auf dem Server.)

	=====================================================================
	WICHTIGER HINWEIS: Robux-Produkt-IDs sind Platzhalter (0)!
	=====================================================================
	JEDE Id unten ist absichtlich 0 - echte Gamepass-/Entwicklerprodukt-IDs
	existieren erst, nachdem die Spielbetreiberin sie auf roblox.com/create
	für DIESES Erlebnis anlegt (siehe docs/monetization-setup.md für die
	Schritt-für-Schritt-Anleitung). Der gesamte Code in diesem Projekt ist
	so geschrieben, dass Id == 0 IMMER sicher behandelt wird:
		- MarketplaceService wird NIE mit Id 0 aufgerufen (Prompt-Funktionen
		  in ShopService lehnen das defensiv ab, siehe dort).
		- Der Katalog (ShopService.GetCatalog) markiert jeden Eintrag mit
		  Id == 0 als `Purchasable = false`, damit ein UI-Agent den
		  Kauf-Button clientseitig deaktiviert darstellen kann - server-
		  seitig wird ein Kaufversuch mit Id == 0 UNABHÄNGIG davon zusätzlich
		  abgelehnt (kein Client-Trust).
		- Ein separater, streng von Live getrennter Studio-Testmodus
		  (RunService:IsStudio()) erlaubt es, Käufe OHNE echte IDs zu
		  simulieren, siehe MonetizationService/ShopService
		  (`RequestSimulateStudioPurchase`).

	Bezug: docs/game-design-doc.md, Abschnitt 5 ("Monetarisierung") und
	Abschnitt 10 ("MVP-Scope").

	ABWEICHUNG VOM GDD (Kosmetik-Shop): Das GDD (Abschnitt 5) beschreibt den
	rotierenden Kosmetik-Shop mit EINZELNEN Robux-Preisen (25-150 Robux je
	Item). Roblox verlangt dafür pro einzelnem Kosmetik-Artikel ein eigenes
	Entwicklerprodukt (keine "Katalog-Preisliste"-API für beliebig viele
	virtuelle Items) - bei geplant dutzenden Deko-/Farb-Varianten wäre das
	ein sehr hoher manueller Einrichtungsaufwand (jedes Item einzeln auf
	roblox.com anlegen) UND unpraktisch für einen Code-Agenten, der IDs
	nicht selbst erzeugen kann. Dieses Backend implementiert den Kosmetik-
	Shop daher stattdessen mit den bereits vorhandenen Soft-Währungen (Tide
	Coins/Abyssal Shards) - siehe COSMETIC_ITEMS unten. Siehe
	docs/monetization-setup.md für die Anleitung, einzelne Items später
	trotzdem auf echte Robux-Entwicklerprodukte umzustellen, falls gewünscht.
]]

local ShopConfig = {}

-- // Gamepasses (GDD Abschnitt 5, "Gamepasses (einmalig, Robux)") -------------

export type GamepassKey = "AutoCollector" | "DoubleCoins" | "ExtraPlot" | "VIPDiver" | "TrenchRunner"

export type GamepassDefinition = {
	Key: GamepassKey,
	Id: number, -- Platzhalter 0 - siehe Kopfkommentar
	Name: string,
	Description: string,
	PriceRobuxDisplay: number, -- NUR informativ (Anzeige, bevor MarketplaceService:GetProductInfo geladen ist); der tatsächlich berechnete Preis kommt immer von Roblox selbst
	IconAssetId: string, -- Platzhalter "rbxassetid://0" - von der 3D-/UI-Asset-Pipeline bzw. manuell zu ersetzen
	EffectKey: string, -- Schlüssel, unter dem MonetizationService den Effekt registriert/abfragt
}

ShopConfig.GAMEPASSES = {
	AutoCollector = {
		Key = "AutoCollector",
		Id = 0,
		Name = "Auto-Collector",
		Description = "Automatisches Einsammeln der Glow Spores ohne Klicken.",
		PriceRobuxDisplay = 149,
		IconAssetId = "rbxassetid://0",
		EffectKey = "AutoCollector",
	},
	DoubleCoins = {
		Key = "DoubleCoins",
		Id = 0,
		Name = "2x Tide Coins",
		Description = "Dauerhaft doppelte Tide-Coins-Einnahmen (Idle-Einkommen + Raid-Belohnungen).",
		PriceRobuxDisplay = 349,
		IconAssetId = "rbxassetid://0",
		EffectKey = "DoubleCoins",
	},
	ExtraPlot = {
		Key = "ExtraPlot",
		Id = 0,
		Name = "Extra Habitat-Plot",
		Description = "Zweites, eigenes Plot (mehr Baufläche).",
		PriceRobuxDisplay = 199,
		IconAssetId = "rbxassetid://0",
		EffectKey = "ExtraPlot",
	},
	VIPDiver = {
		Key = "VIPDiver",
		Id = 0,
		Name = "VIP-Taucher",
		Description = "Exklusiver Skin, tägliche Bonus-Truhe, 1,5x Zucht-Geschwindigkeit.",
		PriceRobuxDisplay = 449,
		IconAssetId = "rbxassetid://0",
		EffectKey = "VIPDiver",
	},
	TrenchRunner = {
		Key = "TrenchRunner",
		Id = 0,
		Name = "Trench Runner",
		Description = "Schnellere Bewegung/Tauchgeschwindigkeit.",
		PriceRobuxDisplay = 99,
		IconAssetId = "rbxassetid://0",
		EffectKey = "TrenchRunner",
	},
} :: { [GamepassKey]: GamepassDefinition }

--- Feste Anzeige-Reihenfolge (identisch zur GDD-Tabellenreihenfolge) -
--- `pairs()` über GAMEPASSES garantiert keine stabile Reihenfolge.
ShopConfig.GAMEPASS_ORDER = { "AutoCollector", "DoubleCoins", "ExtraPlot", "VIPDiver", "TrenchRunner" } :: { GamepassKey }

-- // Entwicklerprodukte (GDD Abschnitt 5, "Entwicklerprodukte (wiederholt
-- kaufbar, Robux)") -----------------------------------------------------------

export type DevProductKey = "Coins500" | "Coins3000" | "RescueToken" | "MysteryEgg" | "RaidSkip" | "InstantBreeding"

export type DevProductDefinition = {
	Key: DevProductKey,
	Id: number, -- Platzhalter 0 - siehe Kopfkommentar
	Name: string,
	Description: string,
	PriceRobuxDisplay: number,
	IconAssetId: string,
	EffectKey: string,
	-- Wird ausgezahlt, wenn der Kauf technisch erfolgreich verarbeitet
	-- wurde, der eigentliche Spiel-Effekt zum Zeitpunkt der Gutschrift aber
	-- inhaltlich nicht mehr sinnvoll anwendbar ist (z. B. Rettungs-Token
	-- ohne (mehr) entführte Kreatur, Instant-Complete ohne laufende Zucht,
	-- Raid-Skip ohne aktiven Raid). Verhindert, dass ein bezahlter Kauf
	-- spurlos verpufft oder unbegrenzt als "NotProcessedYet" retried wird,
	-- siehe MonetizationService-Kopfkommentar.
	FallbackCompensationTideCoins: number,
	-- NUR für EffectKey == "GrantCoins" gesetzt: die tatsächlich gutzu-
	-- schreibende Coin-Menge (bewusst getrennt von
	-- FallbackCompensationTideCoins, auch wenn beide Werte hier identisch
	-- sind - unterschiedliche Bedeutung, siehe MonetizationService.
	-- applyDevProductEffect).
	GrantAmount: number?,
	-- true, falls Roblox' "Paid Random Items"-Richtlinie greift (Mystery
	-- Egg) - siehe MonetizationService.PlayerMayPurchasePaidRandomItems.
	IsPaidRandomItem: boolean?,
	-- true, falls dieser Kauf einen serverseitig VORHER festgelegten
	-- Ziel-Kontext braucht (z. B. welche entführte Kreatur/welches
	-- Brutbecken), siehe MonetizationService.PendingPurchaseTarget-Konzept.
	RequiresTarget: boolean?,
}

ShopConfig.DEV_PRODUCTS = {
	Coins500 = {
		Key = "Coins500",
		Id = 0,
		Name = "500 Tide Coins",
		Description = "Direktwährung.",
		PriceRobuxDisplay = 79,
		IconAssetId = "rbxassetid://0",
		EffectKey = "GrantCoins",
		FallbackCompensationTideCoins = 500,
		GrantAmount = 500,
	},
	Coins3000 = {
		Key = "Coins3000",
		Id = 0,
		Name = "3.000 Tide Coins",
		Description = "Direktwährung (Bulk-Rabatt).",
		PriceRobuxDisplay = 399,
		IconAssetId = "rbxassetid://0",
		EffectKey = "GrantCoins",
		FallbackCompensationTideCoins = 3000,
		GrantAmount = 3000,
	},
	RescueToken = {
		Key = "RescueToken",
		Id = 0,
		Name = "Rettungs-Token",
		Description = "Entführte Kreatur sofort zurückholen - umgeht die Rettungsmission.",
		PriceRobuxDisplay = 49,
		IconAssetId = "rbxassetid://0",
		EffectKey = "RescueToken",
		FallbackCompensationTideCoins = 300,
		RequiresTarget = true,
	},
	MysteryEgg = {
		Key = "MysteryEgg",
		Id = 0,
		Name = "Mystery Egg",
		Description = "Zufällige Kreatur (Rarity-Chance, siehe Odds vor dem Kauf).",
		PriceRobuxDisplay = 89,
		IconAssetId = "rbxassetid://0",
		EffectKey = "MysteryEgg",
		FallbackCompensationTideCoins = 150,
		IsPaidRandomItem = true,
	},
	RaidSkip = {
		Key = "RaidSkip",
		Id = 0,
		Name = "Raid-Skip",
		Description = "Aktueller Raid wird automatisch \"gewonnen\" gewertet (1x/Tag).",
		PriceRobuxDisplay = 59,
		IconAssetId = "rbxassetid://0",
		EffectKey = "RaidSkip",
		FallbackCompensationTideCoins = 220,
	},
	-- GDD-ERGÄNZUNG (nicht Teil der ursprünglichen GDD-Tabelle Abschnitt 5,
	-- aber vom Auftrag explizit gefordert UND bereits als Platzhalter-
	-- Funktionssignatur in BreedingService.RequestInstantComplete
	-- vorbereitet, siehe Kopfkommentar dort: "Laut GDD Abschnitt 5 ist ein
	-- Developer Product für den sofortigen Abschluss zeitbasierter Vorgänge
	-- vorgesehen [...]; für Brutbecken ist ein analoges Produkt plausibel,
	-- aber NICHT Teil des MVP-Scopes"). Preis als plausibler Platzhalter
	-- gewählt (zwischen Rettungs-Token und Raid-Skip) - VOR Live-Schaltung
	-- von der Spielbetreiberin final festzulegen.
	InstantBreeding = {
		Key = "InstantBreeding",
		Id = 0,
		Name = "Zucht sofort abschließen",
		Description = "Schließt eine laufende Inkubation in einem Brutbecken sofort ab.",
		PriceRobuxDisplay = 39,
		IconAssetId = "rbxassetid://0",
		EffectKey = "InstantBreeding",
		FallbackCompensationTideCoins = 150,
		RequiresTarget = true,
	},
} :: { [DevProductKey]: DevProductDefinition }

ShopConfig.DEV_PRODUCT_ORDER = { "Coins500", "Coins3000", "RescueToken", "MysteryEgg", "RaidSkip", "InstantBreeding" } :: { DevProductKey }

-- // Gamepass-Effekt-Konstanten -------------------------------------------------
-- Zentrale Balancing-Werte für die Gamepass-Effekte (siehe
-- MonetizationService.PlayerOwnsGamepass-Konsumenten in BreedingService/
-- RaidService/IdleIncomeService).

ShopConfig.DOUBLE_COINS_MULTIPLIER = 2.0

--- ABWEICHUNG VOM GDD: "Auto-Collector" ist laut GDD Abschnitt 5 "Automatisches
--- Einsammeln der Glow Spores ohne Klicken". Das aktuelle Idle-Einkommen-
--- System (IdleIncomeService) schreibt Einkommen aber bereits IMMER
--- automatisch gut (Online-Tick-Loop + Offline-Progress) - es gibt gar
--- keine Klick-/manuelle-Sammel-Aktion, die der Pass abschaffen könnte
--- (siehe IdleIncomeService-Kopfkommentar). Damit der Pass trotzdem einen
--- spürbaren, ehrlichen Effekt hat, verdoppelt er stattdessen das
--- Offline-Einkommens-Zeitfenster (GDD-Cap 4h -> 8h für Besitzer) - passend
--- zum Pass-Namen ("auch wenn du nicht da bist, sammelt es für dich länger").
ShopConfig.AUTO_COLLECTOR_OFFLINE_CAP_SECONDS = 8 * 60 * 60

ShopConfig.VIP_BREEDING_SPEED_MULTIPLIER = 1.5 -- GDD: "1,5x Zucht-Geschwindigkeit"
ShopConfig.VIP_DAILY_CHEST_TIDE_COINS = 500
ShopConfig.VIP_CHAT_TAG = "VIP"

ShopConfig.TRENCH_RUNNER_WALKSPEED = 24 -- Standard-Humanoid-WalkSpeed ist 16 (Roblox-Default)
ShopConfig.DEFAULT_WALKSPEED = 16

--- ABWEICHUNG VOM GDD: "Extra Habitat-Plot" (GDD Abschnitt 5, 199 Robux)
--- setzt ein zweites, unabhängiges Plot je Spieler voraus. PlotRegistry
--- (src/server/PlotRegistry.lua) verwaltet aktuell GENAU EIN Plot je
--- UserId (`plotByUserId: { [number]: Model }`) - ein Mehrfach-Plot-System
--- (zweiter Welt-Slot, zweites Baufelder-Set, zweite Habitat-Basis) ist
--- eine grössere strukturelle Erweiterung von PlotRegistry/PlacementService/
--- RaidService (alle gehen aktuell von "ein Plot pro Spieler" aus) und
--- explizit NICHT Teil des Dateibesitzes dieses Auftrags. Der Gamepass ist
--- hier daher bewusst nur als PLATZHALTER verdrahtet: MonetizationService
--- erkennt den Besitz zuverlässig (PlayerOwnsGamepass("ExtraPlot")) und
--- setzt das Player-Attribut "OwnsExtraPlotGamepassPlaceholder" (siehe
--- MonetizationService.applyExtraPlotPlaceholder), löst aber KEINE zweite
--- Plot-Zuweisung aus. Siehe docs/monetization-setup.md
--- für den vollständigen Hinweis an die Spielbetreiberin.
ShopConfig.EXTRA_PLOT_PLACEHOLDER = true

-- // Kosmetik-Shop (Soft-Currency, siehe ABWEICHUNG VOM GDD im Kopfkommentar) ---

export type CosmeticSlot = "DiverSuitColor" | "CreatureGlowColor" | "Decoration"
export type CosmeticCurrency = "TideCoins" | "AbyssalShards"

export type CosmeticItemDefinition = {
	Id: string,
	Slot: CosmeticSlot,
	Name: string,
	Description: string,
	Currency: CosmeticCurrency,
	Price: number,
	IconAssetId: string,
	SwatchColor: Color3?, -- rein kosmetisch für die Anzeige (Taucheranzug-/Leuchtfarben), optional für Deko-Items
	InRotationPool: boolean, -- true = kann im täglich rotierenden "Angebote"-Bereich erscheinen
}

ShopConfig.COSMETIC_ITEMS = {
	-- Taucheranzug-Farben ------------------------------------------------------
	DiverSuit_Teal = {
		Id = "DiverSuit_Teal",
		Slot = "DiverSuitColor",
		Name = "Taucheranzug: Tiefsee-Türkis",
		Description = "Klassischer Türkis-Anzug.",
		Currency = "TideCoins",
		Price = 800,
		IconAssetId = "rbxassetid://0",
		SwatchColor = Color3.fromRGB(40, 200, 190),
		InRotationPool = true,
	},
	DiverSuit_Magenta = {
		Id = "DiverSuit_Magenta",
		Slot = "DiverSuitColor",
		Name = "Taucheranzug: Abyssal-Magenta",
		Description = "Kräftiges Magenta, gut sichtbar in der Tiefe.",
		Currency = "TideCoins",
		Price = 1200,
		IconAssetId = "rbxassetid://0",
		SwatchColor = Color3.fromRGB(220, 40, 180),
		InRotationPool = true,
	},
	DiverSuit_Gold = {
		Id = "DiverSuit_Gold",
		Slot = "DiverSuitColor",
		Name = "Taucheranzug: Bernstein-Gold",
		Description = "Seltener, edler Gold-Anzug.",
		Currency = "AbyssalShards",
		Price = 40,
		IconAssetId = "rbxassetid://0",
		SwatchColor = Color3.fromRGB(230, 180, 60),
		InRotationPool = true,
	},

	-- Kreaturen-Leuchtfarben -----------------------------------------------------
	CreatureGlow_Cyan = {
		Id = "CreatureGlow_Cyan",
		Slot = "CreatureGlowColor",
		Name = "Leuchtfarbe: Bio-Cyan",
		Description = "Kühles Cyan-Leuchten für deine Kreaturen.",
		Currency = "TideCoins",
		Price = 600,
		IconAssetId = "rbxassetid://0",
		SwatchColor = Color3.fromRGB(80, 230, 255),
		InRotationPool = true,
	},
	CreatureGlow_Ember = {
		Id = "CreatureGlow_Ember",
		Slot = "CreatureGlowColor",
		Name = "Leuchtfarbe: Glut-Orange",
		Description = "Warmes, seltenes Glühen.",
		Currency = "AbyssalShards",
		Price = 25,
		IconAssetId = "rbxassetid://0",
		SwatchColor = Color3.fromRGB(255, 130, 40),
		InRotationPool = true,
	},

	-- Deko ---------------------------------------------------------------------
	Decoration_KelpBundle = {
		Id = "Decoration_KelpBundle",
		Slot = "Decoration",
		Name = "Kelp-Bündel",
		Description = "Dekoratives Kelp-Bündel für dein Habitat.",
		Currency = "TideCoins",
		Price = 350,
		IconAssetId = "rbxassetid://0",
		InRotationPool = true,
	},
	Decoration_ShellLantern = {
		Id = "Decoration_ShellLantern",
		Slot = "Decoration",
		Name = "Muschel-Laterne",
		Description = "Stimmungsvolle Beleuchtung für dein Habitat.",
		Currency = "TideCoins",
		Price = 500,
		IconAssetId = "rbxassetid://0",
		InRotationPool = true,
	},
	Decoration_CrystalCluster = {
		Id = "Decoration_CrystalCluster",
		Slot = "Decoration",
		Name = "Kristall-Cluster",
		Description = "Seltenes, funkelndes Deko-Highlight.",
		Currency = "AbyssalShards",
		Price = 60,
		IconAssetId = "rbxassetid://0",
		InRotationPool = true,
	},
} :: { [string]: CosmeticItemDefinition }

--- Feste Anzeige-Reihenfolge aller Kosmetik-IDs (stabile `pairs()`-Alternative).
ShopConfig.COSMETIC_ITEM_ORDER = {
	"DiverSuit_Teal",
	"DiverSuit_Magenta",
	"DiverSuit_Gold",
	"CreatureGlow_Cyan",
	"CreatureGlow_Ember",
	"Decoration_KelpBundle",
	"Decoration_ShellLantern",
	"Decoration_CrystalCluster",
} :: { string }

--- Wie viele Artikel der tägliche "Angebote"-Bereich zeigt (ShopService.
--- GetDailyRotationOfferIds) - fester, kleiner Ausschnitt aus dem
--- InRotationPool, siehe dortige Seed-Erklärung.
ShopConfig.DAILY_ROTATION_OFFER_COUNT = 3

-- // Hilfsfunktionen --------------------------------------------------------

function ShopConfig.GetGamepass(key: string): GamepassDefinition?
	return ShopConfig.GAMEPASSES[key :: GamepassKey]
end

function ShopConfig.GetDevProduct(key: string): DevProductDefinition?
	return ShopConfig.DEV_PRODUCTS[key :: DevProductKey]
end

function ShopConfig.GetCosmeticItem(itemId: string): CosmeticItemDefinition?
	return ShopConfig.COSMETIC_ITEMS[itemId]
end

--- Liefert die GamepassDefinition zu einer Roblox-GamePassId, oder nil,
--- falls keine konfigurierte (nicht-Platzhalter) Id übereinstimmt. Wird von
--- MonetizationService.PromptGamePassPurchaseFinished genutzt, um von der
--- durch Roblox gemeldeten Id zurück auf unseren internen Key zu schliessen.
function ShopConfig.FindGamepassById(gamePassId: number): GamepassDefinition?
	for _, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local definition = ShopConfig.GAMEPASSES[key]
		if definition.Id ~= 0 and definition.Id == gamePassId then
			return definition
		end
	end
	return nil
end

--- Analog zu FindGamepassById, für Entwicklerprodukte (MonetizationService.
--- ProcessReceipt löst receiptInfo.ProductId hierüber auf).
function ShopConfig.FindDevProductById(productId: number): DevProductDefinition?
	for _, key in ipairs(ShopConfig.DEV_PRODUCT_ORDER) do
		local definition = ShopConfig.DEV_PRODUCTS[key]
		if definition.Id ~= 0 and definition.Id == productId then
			return definition
		end
	end
	return nil
end

return ShopConfig
