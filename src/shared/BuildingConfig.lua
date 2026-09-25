--[[
	Abyssara – Deep Tide Tycoon
	Modul: BuildingConfig
	Zuständigkeit:
		Statische Datentabelle der 6 platzierbaren Gebäude (GDD Abschnitt 8/9):
		BroodPool_Basic, GlowBuoyStation, FilterPlant, AnglerfishTower,
		CoralBarrier, ElectricEelTrap. Einzige Quelle der Wahrheit für
		Baukosten, Verkaufs-Rückerstattung, Freischalt-Level, Baufeld-Bedarf
		UND (seit dem Gebäude-Upgrade-System, siehe docs/building-upgrades.md)
		die Stufe-2/3-Ausbaukosten und -Effekte pro Gebäude - PlacementService
		(Server) UND die Client-Vorschau/-UI lesen ausschließlich aus diesem
		Modul, damit Zahlen nie an zwei Stellen auseinanderlaufen.

	Rojo-Einhängepunkt:
		src/shared/BuildingConfig.lua -> ReplicatedStorage.BuildingConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der
		Client liest dies NUR für Anzeige/Vorschau-Zwecke; die alleinige
		Autorität über Käufe/Platzierung/Upgrades bleibt PlacementService auf
		dem Server, siehe dort.)

	Preisgestaltung (WICHTIG - Design-Entscheidung, siehe Auftrag):
		Das GDD (Abschnitt 9, Punkt 2) nennt bewusst KEINE exakten
		Baukosten, nur eine Progression-Curve (Abschnitt 6: Level 1-10
		schnelle Freischaltungen/hohe Tutorial-Belohnungen, Level 10-25
		Kosten x1,15/Stufe, Level 25-45 x1,2/Stufe) sowie konkrete
		Level-Unlocks ("neues Baumodul" Level 3, "zweiter Brutbeckenslot"
		Level 6, "erster Verteidigungsturm" Level 8). Daraus pragmatisch
		abgeleitet:
			- GlowBuoyStation + BroodPool_Basic: ab Level 1 verfügbar
			  (Kern-Loop laut GDD Abschnitt 3 "Minute-zu-Minute" - Sammeln
			  UND Züchten sind von Anfang an Teil des Loops), günstig bis
			  mittel bepreist als früher Einstieg in die Wirtschaft.
			- FilterPlant: ab Level 3 ("neues Baumodul" laut GDD Abschnitt
			  6), spürbar teurer als die Level-1-Gebäude.
			- AnglerfishTower: ab Level 8 ("erster Verteidigungsturm" laut
			  GDD Abschnitt 6), teuerstes MVP-Gebäude (Verteidigung als
			  Premium-Nutzen kurz vor der Dämmerzonen-Freischaltung).
		SellRefundFraction (50 %) ist ebenfalls ein plausibler Platzhalter
		ohne GDD-Vorgabe: verhindert Kauf/Verkauf als Geld-Exploit, gibt
		aber einen spürbaren Teil der Investition zurück - inkl. bereits
		investierter Upgrade-Kosten, siehe PlacementService.RequestRemove.

	Produktionsraten (IncomeRate, ergänzt für das Idle-Einkommen-/
	Produktionssystem, GDD Abschnitt 3 "Minute-zu-Minute" + Abschnitt 9
	Punkt 3):
		Nur Gebäude, deren Rolle laut GDD Abschnitt 8 tatsächlich
		"Ressourcen-Produktionsgebäude" ist, produzieren passiv Tide
		Coins - GlowBuoyStation ("Sammelt passiv Glow Spores für
		Tide-Coin-Einkommen") und FilterPlant ("Ressourcen-
		Produktionsgebäude, veredelt Rohertrag"). BroodPool (Zucht-
		Timer-Gebäude) und die 3 Verteidigungstürme haben bewusst
		IncomeRate = 0 - sie gehören zu anderen Systemen statt zum
		Idle-Einkommen.

		Amortisationszeit (Cost / IncomeRate) ist bewusst gestaffelt, damit
		das günstigere Gebäude sich schneller amortisiert, aber absolut
		weniger produziert (spielerisch sinnvolle Kurve statt linearer
		Skalierung):
			- GlowBuoyStation: 150 Cost / 15 Coins/Min ≈ 10 Min. Amortisation.
			- FilterPlant: 450 Cost / 30 Coins/Min ≈ 15 Min. Amortisation,
			  aber doppelt so hoher Ertrag/Minute wie die Lichtboje - passt
			  zur höheren UnlockLevel-Stufe (3) und dem GDD-Bild eines
			  "veredelnden" Fortgeschrittenen-Produktionsgebäudes.
		IdleIncomeService (Server) ist die einzige Stelle, die IncomeRate
		(inkl. IncomeMultiplierByStage, siehe unten) tatsächlich in
		Tide-Coin-Gutschriften umsetzt.

	// --- Gebäude-Upgrade-System (Stufen 1->2->3, siehe docs/building-upgrades.md) ---
	GDD Abschnitt 8 nennt explizit "Brutbecken (3 Stufen: Basic, Advanced,
	Master)" und "Verteidigungsturm ... je 3 Upgrade-Stufen". Die 2
	Produktionsgebäude (GlowBuoyStation/FilterPlant) sind im GDD-Asset-
	Abschnitt nicht ausdrücklich als "3 Stufen" gelistet, werden hier aber
	AUS SYMMETRIE-/WIRTSCHAFTS-GRÜNDEN (ein einheitliches, für den Spieler
	vorhersagbares Upgrade-System über ALLE Gebäudetypen) ebenfalls mit
	MaxStage = 3 geführt - vollständig begründet in docs/building-upgrades.md.

	UpgradeCosts ist NACH ZIEL-STUFE indiziert (Schlüssel 2 und 3 - NICHT 1,
	Stufe 1 ist der reguläre Bau-Cost oben, kostet also nichts extra). Stufe
	3 kann zusätzlich AbyssalShards verlangen (siehe Auftrag) - aktuell nur
	beim BroodPool (Stufe 3 = "Master", schaltet HadalDepths-Kreaturen +
	CrystalLeviathan frei, siehe BreedingConfig.TIERS[3]/GetCreaturePool -
	ein Premium-Meilenstein verdient eine Premium-nahe Zweitwährung).

	IncomeMultiplierByStage gilt NUR für Produktionsgebäude (IncomeRate > 0);
	TowerStageBonus NUR für Verteidigungstürme (RaidConfig.TOWER_STATS kennt
	den BuildingId). BroodPool braucht KEINES von beiden - seine "Stufe" IST
	bereits die BreedingConfig-Zucht-Stufe (HabitatPlacement.Level wird 1:1
	als BreedingConfig.GetTier-Index verwendet, siehe BreedingService).

	LevelRequirement-Herleitung: Beim BroodPool bewusst auf die
	Zonen-Freischalt-Level abgestimmt (siehe docs/building-upgrades.md,
	Abschnitt "BroodPool"): Stufe 2 (Advanced, schaltet MidnightZone-
	Kreaturen in der Zucht frei) = Level 25, exakt die MidnightZone-
	Freischalt-Stufe (ZoneEconomyConfig/TravelService). Stufe 3 (Master,
	schaltet HadalDepths-Kreaturen + CrystalLeviathan frei) = Level 45,
	exakt die HadalDepths-Freischalt-Stufe. Das verhindert, dass ein
	Spieler weit VOR dem eigentlichen Zonen-Fortschritt bereits die
	seltensten Zonen-Kreaturen erzüchten kann (BreedingConfig.
	GetCreaturePool ist NICHT an den tatsächlichen Zonen-Unlock des
	Spielers gekoppelt, nur an die BroodPool-Stufe selbst - siehe
	docs/zones-and-raids.md Abschnitt 4). Die übrigen 5 Gebäude erhalten
	plausibel gestaffelte Level-Anforderungen zwischen ihrem UnlockLevel
	und Level 45 (siehe docs/building-upgrades.md für die volle Tabelle).
]]

export type BuildingId = "BroodPool" | "GlowBuoyStation" | "FilterPlant" | "AnglerfishTower" | "CoralBarrier" | "ElectricEelTrap"

export type BuildingUpgradeCost = {
	TideCoins: number,
	AbyssalShards: number?, -- nur Stufe 3, aktuell nur BroodPool (siehe Kopfkommentar)
	LevelRequirement: number, -- Spieler-Level (PlayerDataService.GetLevel), NICHT Gebäude-Stufe
}

--- Additive/multiplikative Kampfwert-Anpassung für Verteidigungstürme, auf
--- die jeweilige RaidConfig.TOWER_STATS-Basis angewendet (siehe
--- RaidService.collectTowerRuntimes/computeTowerDpsFromLayout) - NIEMALS in
--- RaidConfig zurückgeschrieben, identisches Prinzip wie
--- RaidConfig.ZONE_SCALING/GetScaledEnemy. Felder, die ein Turmtyp gar nicht
--- besitzt (z. B. BlockRadius bei AnglerfishTower), werden schlicht
--- ignoriert (siehe RaidService: `stats.BlockRadius and (...)"or nil`).
export type TowerStageBonus = {
	DamageMultiplier: number?,
	RangeBonus: number?,
	FireRateMultiplier: number?,
	BlockRadiusBonus: number?, -- nur CoralBarrier
	ChainCountBonus: number?, -- nur ElectricEelTrap
	ChainRadiusBonus: number?, -- nur ElectricEelTrap
}

export type BuildingDefinition = {
	Id: BuildingId,
	DisplayName: string,
	Description: string,
	Cost: number, -- Tide Coins
	SellRefundFraction: number, -- 0..1, Anteil von Cost (+ investierten Upgrade-Kosten) bei Verkauf/Entfernen
	GridFieldCount: number, -- benötigte Baufelder auf der Habitat-Plot-Basis (MVP: immer 1)
	UnlockLevel: number,
	TemplateName: string, -- Name unter ReplicatedStorage.AssetTemplates.Buildings (Stufe 1) - siehe AssetTemplateSetup
	IncomeRate: number, -- Tide Coins / Minute passives Idle-Einkommen bei Stufe 1; 0 = kein Produktionsgebäude
	MaxStage: number, -- höchste erreichbare Ausbaustufe == HabitatPlacement.Level (MVP: immer 3)
	UpgradeCosts: { [number]: BuildingUpgradeCost }, -- indiziert nach ZIEL-Stufe (2, 3)
	IncomeMultiplierByStage: { [number]: number }?, -- nur Produktionsgebäude; Stufe 1 impliziert 1.0
	TowerStageBonus: { [number]: TowerStageBonus }?, -- nur Verteidigungstürme, indiziert nach ZIEL-Stufe
}

local BuildingConfig = {}

local DEFINITIONS: { [string]: BuildingDefinition } = {
	GlowBuoyStation = {
		Id = "GlowBuoyStation",
		DisplayName = "Glow Buoy Station",
		Description = "Passively collects Glow Spores for Tide Coin income.",
		Cost = 150,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 1,
		TemplateName = "GlowBuoyStation",
		IncomeRate = 15,
		MaxStage = 3,
		-- ≈2.7x Basis-Cost über beide Stufen kumuliert, siehe
		-- docs/building-upgrades.md für die volle Amortisations-Rechnung.
		UpgradeCosts = {
			[2] = { TideCoins = 400, LevelRequirement = 10 },
			[3] = { TideCoins = 950, LevelRequirement = 25 },
		},
		IncomeMultiplierByStage = { [1] = 1.0, [2] = 1.6, [3] = 2.4 },
	},
	BroodPool = {
		Id = "BroodPool",
		DisplayName = "Brood Pool",
		Description = "Incubates creature eggs (basic stage 1/3).",
		Cost = 250,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 1,
		TemplateName = "BroodPool_Basic",
		IncomeRate = 0, -- kein Idle-Einkommen, siehe Zucht-/Ei-System (BreedingConfig/BreedingService)
		MaxStage = 3,
		-- LevelRequirement bewusst == Zonen-Freischalt-Level, siehe Kopfkommentar.
		UpgradeCosts = {
			[2] = { TideCoins = 700, LevelRequirement = 25 },
			[3] = { TideCoins = 1800, AbyssalShards = 5, LevelRequirement = 45 },
		},
		-- KEIN IncomeMultiplierByStage/TowerStageBonus - die "Stufe" IST bereits
		-- die BreedingConfig-Zucht-Stufe, siehe Kopfkommentar.
	},
	FilterPlant = {
		Id = "FilterPlant",
		DisplayName = "Filter Plant",
		Description = "Resource production building, refines raw yield.",
		Cost = 450,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 3,
		TemplateName = "FilterPlant",
		IncomeRate = 30,
		MaxStage = 3,
		UpgradeCosts = {
			[2] = { TideCoins = 1000, LevelRequirement = 15 },
			[3] = { TideCoins = 2200, LevelRequirement = 30 },
		},
		IncomeMultiplierByStage = { [1] = 1.0, [2] = 1.6, [3] = 2.4 },
	},
	AnglerfishTower = {
		Id = "AnglerfishTower",
		DisplayName = "Anglerfish Tower",
		Description = "Defense tower against Trench Raid waves.",
		Cost = 700,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 8,
		TemplateName = "AnglerfishTower",
		IncomeRate = 0, -- kein Idle-Einkommen, reiner Verteidigungsturm (GDD Abschnitt 9 Punkt 5)
		MaxStage = 3,
		UpgradeCosts = {
			[2] = { TideCoins = 1500, LevelRequirement = 20 },
			[3] = { TideCoins = 3200, LevelRequirement = 35 },
		},
		-- Basis (Stufe 1, RaidConfig.TOWER_STATS.AnglerfishTower): 18 Dmg *
		-- 1.5 FireRate = 27 DPS, Range 28. Stufe 2 -> 36.45 DPS/Range 32,
		-- Stufe 3 -> 48.6 DPS/Range 36 (siehe docs/building-upgrades.md).
		TowerStageBonus = {
			[2] = { DamageMultiplier = 1.35, RangeBonus = 4 },
			[3] = { DamageMultiplier = 1.8, RangeBonus = 8 },
		},
	},
	-- Content Update 1, Abschnitt 4.1: Flächen-Slow/Tank-Turm (siehe
	-- RaidConfig.TOWER_STATS.CoralBarrier für Basis-Kampfwerte).
	CoralBarrier = {
		Id = "CoralBarrier",
		DisplayName = "Coral Barrier",
		Description = "Slows enemies in a radius instead of killing them fast - an area tank.",
		Cost = 550,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 12,
		TemplateName = "CoralBarrier",
		IncomeRate = 0,
		MaxStage = 3,
		UpgradeCosts = {
			[2] = { TideCoins = 1200, LevelRequirement = 22 },
			[3] = { TideCoins = 2600, LevelRequirement = 38 },
		},
		-- Basis (Stufe 1): 8 Dmg * 2.5 FireRate = 20 DPS, BlockRadius 10.
		-- Stufe 2 -> 26 DPS/BlockRadius 12, Stufe 3 -> 34 DPS/BlockRadius 14.
		-- CORAL_BARRIER_SLOW_FRACTION (40%) bleibt bewusst stufenunabhängig
		-- (RaidConfig-weite Konstante, siehe dortiger Kopfkommentar) - der
		-- größere BlockRadius ist der volle Upgrade-Hebel dieses Turms.
		TowerStageBonus = {
			[2] = { DamageMultiplier = 1.3, BlockRadiusBonus = 2 },
			[3] = { DamageMultiplier = 1.7, BlockRadiusBonus = 4 },
		},
	},
	-- Content Update 1, Abschnitt 4.2: Ketten-Schaden-Turm (siehe
	-- RaidConfig.TOWER_STATS.ElectricEelTrap für Basis-Kampfwerte).
	ElectricEelTrap = {
		Id = "ElectricEelTrap",
		DisplayName = "Electric Eel Trap",
		Description = "Chain lightning hits the main target plus nearby enemies.",
		Cost = 900,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 18,
		TemplateName = "ElectricEelTrap",
		IncomeRate = 0,
		MaxStage = 3,
		UpgradeCosts = {
			[2] = { TideCoins = 1900, LevelRequirement = 28 },
			[3] = { TideCoins = 4000, LevelRequirement = 42 },
		},
		-- Basis (Stufe 1): 14 Dmg * 1.2 FireRate = 16.8 DPS am Hauptziel,
		-- ChainCount 2, ChainRadius 10. Stufe 2 -> 21.84 DPS, ChainCount 3,
		-- ChainRadius 12. Stufe 3 -> 28.56 DPS, ChainCount 4, ChainRadius 14.
		TowerStageBonus = {
			[2] = { DamageMultiplier = 1.3, ChainCountBonus = 1, ChainRadiusBonus = 2 },
			[3] = { DamageMultiplier = 1.7, ChainCountBonus = 2, ChainRadiusBonus = 4 },
		},
	},
}

--- Feste Anzeige-/Hotkey-Reihenfolge, da `pairs()` über DEFINITIONS keine
--- stabile Reihenfolge garantiert. Neue Türme (CoralBarrier/ElectricEelTrap)
--- bewusst ans Ende gehängt - Tastatur-Hotkeys 1-4 (siehe
--- PlacementPreviewController) bleiben dadurch für die 4 MVP-Gebäude
--- unverändert, die 2 neuen Türme sind nur über die Baukarten-Leiste/
--- Gamepad-DPad-Zyklus wählbar.
BuildingConfig.ORDER =
	{ "GlowBuoyStation", "BroodPool", "FilterPlant", "AnglerfishTower", "CoralBarrier", "ElectricEelTrap" } :: { BuildingId }

-- Seamless-Animation-System (docs/animation-system.md): wie lange a sold
-- building's model still exists in the Workspace AFTER PlacementService.
-- RequestRemove already granted the refund, purely so the client
-- (ModelAnimator.client.lua) can play a shrink-out instead of an instant
-- pop - identical grace-period principle to RaidConfig.DEATH_FX_SECONDS /
-- HeldItemConfig.CollectFxSeconds.
BuildingConfig.SELL_FX_SECONDS = 0.35

--- Liefert die Definition für `buildingId`, oder nil bei unbekannter Id.
--- Nimmt bewusst `string` (nicht `BuildingId`) entgegen, da Aufrufer
--- (insbesondere PlacementService bei Remote-Eingaben) einen ungeprüften
--- Client-Wert übergeben - die Prüfung "kennen wir diese Id?" passiert
--- genau hier.
function BuildingConfig.Get(buildingId: string): BuildingDefinition?
	return DEFINITIONS[buildingId]
end

function BuildingConfig.GetAll(): { [string]: BuildingDefinition }
	return DEFINITIONS
end

-- // Upgrade-System Hilfsfunktionen (siehe docs/building-upgrades.md) -----------

--- Liefert die Ausbaukosten für `buildingId`, um Stufe `targetStage` (2 oder
--- 3) zu erreichen, oder nil (unbekanntes Gebäude, `targetStage` <= 1, oder
--- `targetStage` > MaxStage).
function BuildingConfig.GetUpgradeCost(buildingId: string, targetStage: number): BuildingUpgradeCost?
	local definition = DEFINITIONS[buildingId]
	if not definition then
		return nil
	end
	return definition.UpgradeCosts[targetStage]
end

--- Liefert den Idle-Einkommens-Multiplikator für `buildingId` bei `stage`
--- (1..MaxStage). Liefert 1 (neutral) für Gebäude ohne
--- IncomeMultiplierByStage (Nicht-Produktionsgebäude) oder unbekannte
--- Stufen - NIEMALS nil, damit IdleIncomeService immer sicher multiplizieren
--- kann, ohne selbst auf nil zu prüfen.
function BuildingConfig.GetIncomeMultiplier(buildingId: string, stage: number): number
	local definition = DEFINITIONS[buildingId]
	if not definition or not definition.IncomeMultiplierByStage then
		return 1
	end
	return definition.IncomeMultiplierByStage[stage] or 1
end

--- Liefert den Kampfwert-Bonus für `buildingId` bei `stage` (2 oder 3), oder
--- nil (unbekanntes Gebäude, kein Verteidigungsturm, oder Stufe 1 - Stufe 1
--- hat definitionsgemäß keinen Bonus, siehe RaidConfig.TOWER_STATS als
--- Basiswert).
function BuildingConfig.GetTowerStageBonus(buildingId: string, stage: number): TowerStageBonus?
	local definition = DEFINITIONS[buildingId]
	if not definition or not definition.TowerStageBonus or stage <= 1 then
		return nil
	end
	return definition.TowerStageBonus[stage]
end

return BuildingConfig
