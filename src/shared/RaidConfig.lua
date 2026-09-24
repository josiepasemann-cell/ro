--[[
	Abyssara – Deep Tide Tycoon
	Modul: RaidConfig
	Zuständigkeit:
		Einzige Datentabelle des Trench-Raid-Systems (GDD Abschnitt 3
		"Session-zu-Session" + Abschnitt 9, Punkt 5 + Abschnitt 10 MVP-Scope
		"Trench-Raid-System (Solo, 3 Gegnertypen, 1 Boss)"): Gegnertypen (HP/
		Tempo/Schaden/visuelle Skalierung), Wellen-Zusammensetzung, Turmwerte
		(Reichweite/Schaden/Feuerrate), Raid-Intervall, Offline-Cap sowie
		Belohnungs-/Lösegeld-Konstanten. RaidService (Server) UND die
		Client-HUD lesen ausschließlich aus diesem Modul, damit Zahlen nie an
		zwei Stellen auseinanderlaufen (identisches Prinzip wie BuildingConfig/
		BreedingConfig).

		Enthält bewusst KEINE Logik (keine Zufalls-Rolls, kein Kampf-/
		Bewegungscode) - nur Daten + winzige, reine Lookup-Hilfsfunktionen
		darauf. Die eigentliche Kampf-/Wellen-/Offline-Auswertungslogik lebt
		vollständig in RaidService.

	BEWUSSTE MVP-VEREINFACHUNG (siehe Auftrag):
		Es existiert bislang nur EIN Raid-Gegner-3D-Modell
		(assets/models/enemies/ShadowKraken.lua, Workspace.Assets.Enemies ->
		ReplicatedStorage.AssetTemplates.Enemies via AssetTemplateSetup).
		Statt 4 separate Modelle zu fordern, nutzt dieses Modul dasselbe
		Modell für ALLE 3 Gegnertypen + den Boss und unterscheidet sie rein
		über Gameplay-Daten (HP/Tempo/Schaden) sowie eine rein visuelle
		Skalierung (`ScaleMultiplier`, via Model:ScaleTo) und Einfärbung
		(`BodyColor`/`EyeColor`, auf Body/Mantle/Eye-Parts angewendet) - siehe
		RaidService.applyEnemyVisual. Das erfüllt den MVP-Scope-Wortlaut "3
		Gegnertypen, 1 Boss" spielerisch (unterschiedliches Verhalten/
		Bedrohung), ohne einen zweiten 3D-Asset-Auftrag zu benötigen. Eine
		spätere Erweiterung um echte Einzelmodelle bräuchte nur je Eintrag
		unten ein eigenes `TemplateName` zu setzen (Default: "ShadowKraken").

		Ebenso bewusst vereinfacht: nur EIN Turmtyp (AnglerfishTower) hat
		Kampfwerte, da laut BuildingConfig aktuell nur dieser eine
		Verteidigungsturm existiert (Korallen-Barriere/Elektro-Aal-Falle aus
		dem GDD sind Post-MVP, siehe BuildingConfig-Kopfkommentar). TOWER_STATS
		ist trotzdem bereits als Tabelle (nicht als Einzelwert) angelegt, damit
		künftige Turmtypen ohne Strukturänderung ergänzt werden können.

	Rojo-Einhängepunkt:
		src/shared/RaidConfig.lua -> ReplicatedStorage.RaidConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies NUR für HUD-Anzeige/Vorschau; die alleinige Autorität über
		Raid-Ablauf/Schaden/Belohnung bleibt RaidService auf dem Server.)
]]

export type EnemyId = "Drifter" | "Swarmer" | "Brute" | "TrenchWarden"

export type EnemyDefinition = {
	Id: EnemyId,
	DisplayName: string,
	MaxHP: number,
	MoveSpeed: number, -- Studs/Sekunde, lineare Bewegung Richtung Plot-Zentrum
	ContactDamage: number, -- Wie viele "Zentrum-Erreicht"-Zähler dieser Gegner beim Durchbruch zählt (MVP: immer 1)
	ScaleMultiplier: number, -- Model:ScaleTo(), rein visuell (siehe MVP-Vereinfachung oben)
	BodyColor: Color3,
	EyeColor: Color3,
	IsBoss: boolean,
	TemplateName: string, -- ReplicatedStorage.AssetTemplates.Enemies.<Name>, aktuell immer "ShadowKraken"
}

export type WaveEnemySpawn = {
	EnemyId: EnemyId,
	Count: number,
}

export type WaveDefinition = {
	Enemies: { WaveEnemySpawn },
	IsBossWave: boolean,
}

export type TowerCombatStats = {
	Range: number, -- Studs, gemessen vom LureOrb-Part des Turms
	Damage: number, -- Schaden pro Treffer
	FireRate: number, -- Schüsse/Sekunde
}

local RaidConfig = {}

-- // Gegnertypen ---------------------------------------------------------------

local ENEMIES: { [EnemyId]: EnemyDefinition } = {
	Drifter = {
		Id = "Drifter",
		DisplayName = "Trench-Drifter",
		MaxHP = 40,
		MoveSpeed = 6,
		ContactDamage = 1,
		ScaleMultiplier = 0.55,
		BodyColor = Color3.fromRGB(40, 60, 70),
		EyeColor = Color3.fromRGB(255, 60, 80),
		IsBoss = false,
		TemplateName = "ShadowKraken",
	},
	Swarmer = {
		Id = "Swarmer",
		DisplayName = "Trench-Schwärmer",
		MaxHP = 25,
		MoveSpeed = 9,
		ContactDamage = 1,
		ScaleMultiplier = 0.4,
		BodyColor = Color3.fromRGB(30, 90, 95),
		EyeColor = Color3.fromRGB(255, 150, 60),
		IsBoss = false,
		TemplateName = "ShadowKraken",
	},
	Brute = {
		Id = "Brute",
		DisplayName = "Trench-Brute",
		MaxHP = 90,
		MoveSpeed = 4.5,
		ContactDamage = 1,
		ScaleMultiplier = 0.85,
		BodyColor = Color3.fromRGB(55, 35, 70),
		EyeColor = Color3.fromRGB(255, 40, 60),
		IsBoss = false,
		TemplateName = "ShadowKraken",
	},
	TrenchWarden = {
		Id = "TrenchWarden",
		DisplayName = "Trench-Wächter (Boss)",
		MaxHP = 500,
		MoveSpeed = 3.5,
		ContactDamage = 1,
		ScaleMultiplier = 1.8,
		BodyColor = Color3.fromRGB(15, 10, 15),
		EyeColor = Color3.fromRGB(255, 20, 30),
		IsBoss = true,
		TemplateName = "ShadowKraken",
	},
}

RaidConfig.ENEMIES = ENEMIES

--- Feste Reihenfolge, in der neue Gegnertypen künftig angezeigt/ergänzt
--- werden können (z. B. Kodex-artige Übersicht) - `pairs()` über ENEMIES
--- garantiert keine stabile Reihenfolge.
RaidConfig.ENEMY_ORDER = { "Drifter", "Swarmer", "Brute", "TrenchWarden" } :: { EnemyId }

--- Liefert die Gegner-Definition zu `enemyId`, oder nil bei unbekannter Id.
function RaidConfig.GetEnemy(enemyId: string): EnemyDefinition?
	return ENEMIES[enemyId :: EnemyId]
end

-- // Wellen-Zusammensetzung -----------------------------------------------------
-- MVP-Scope (GDD Abschnitt 10): "3 Gegnertypen, 1 Boss" - 3 reguläre Wellen
-- (je unterschiedliche Mischung der 3 Trash-Typen) + 1 abschließende
-- Boss-Welle (TrenchWarden + kleine Eskorte).

local WAVES: { WaveDefinition } = {
	{
		Enemies = { { EnemyId = "Drifter", Count = 4 } },
		IsBossWave = false,
	},
	{
		Enemies = { { EnemyId = "Drifter", Count = 3 }, { EnemyId = "Swarmer", Count = 4 } },
		IsBossWave = false,
	},
	{
		Enemies = { { EnemyId = "Brute", Count = 3 }, { EnemyId = "Swarmer", Count = 3 } },
		IsBossWave = false,
	},
	{
		Enemies = { { EnemyId = "TrenchWarden", Count = 1 }, { EnemyId = "Drifter", Count = 2 } },
		IsBossWave = true,
	},
}

RaidConfig.WAVES = WAVES

--- Summiert die Gesamt-HP aller Gegner über ALLE Wellen (für die deterministische
--- Offline-Auswertung in RaidService, siehe dort).
function RaidConfig.GetTotalEnemyHP(): number
	local total = 0
	for _, wave in ipairs(WAVES) do
		for _, spawn in ipairs(wave.Enemies) do
			local definition = ENEMIES[spawn.EnemyId]
			if definition then
				total += definition.MaxHP * spawn.Count
			end
		end
	end
	return total
end

-- // Turmwerte -------------------------------------------------------------------

local TOWER_STATS: { [string]: TowerCombatStats } = {
	AnglerfishTower = {
		Range = 28,
		Damage = 18,
		FireRate = 1.5, -- Schüsse/Sekunde -> 27 DPS pro Turm
	},
}

RaidConfig.TOWER_STATS = TOWER_STATS

--- Liefert die Kampfwerte für einen platzierten Turm-`buildingId`, oder nil,
--- falls dieser BuildingId keine Kampfrolle hat (z. B. Produktionsgebäude).
function RaidConfig.GetTowerStats(buildingId: string): TowerCombatStats?
	return TOWER_STATS[buildingId]
end

-- // Raid-Timing -------------------------------------------------------------------

--- GDD Abschnitt 3: "Alle ~20-30 Minuten (Echtzeit, auch offline zählend mit
--- Cap)". 25 Minuten als Mittelwert der GDD-Spanne.
RaidConfig.RAID_INTERVAL_SECONDS = 25 * 60

--- Konsistent zu IdleIncomeService.OFFLINE_INCOME_CAP_SECONDS (GDD-weite
--- 4h-Offline-Konvention) - begrenzt, wie weit in die Vergangenheit verpasste
--- Raids überhaupt berücksichtigt werden.
RaidConfig.OFFLINE_CAP_SECONDS = 4 * 60 * 60

--- Zusätzliche, EXPLIZITE Deckelung (siehe Auftrag "gedeckelt"): selbst wenn
--- OFFLINE_CAP_SECONDS rechnerisch mehr erlauben würde, werden beim Login
--- höchstens so viele verpasste Raids ausgewertet - verhindert, dass ein
--- sehr lange abwesender Spieler auf einen Schlag viele Belohnungen ODER
--- viele entführte Kreaturen gleichzeitig kassiert (Soft-Loss-Prinzip bliebe
--- sonst unangenehm hart). Bewusste MVP-Vereinfachung, siehe RaidService.
RaidConfig.MAX_OFFLINE_RAIDS_EVALUATED = 3

--- Wie viele Gegner insgesamt das Plot-Zentrum erreichen müssen, damit ein
--- LIVE-Raid als Niederlage gilt (siehe RaidService.tickRaid) - toleriert
--- einzelne Durchbrüche, ohne dass der Raid sofort verloren ist.
RaidConfig.DEFEAT_ENEMY_REACH_COUNT = 3

--- Serverseitiger Kampf-Tick (siehe RaidService) - ein gemeinsamer Loop für
--- ALLE aktiven Raids/Gegner statt eines Loops pro Gegner (Performance,
--- siehe Auftrag). 10x/Sekunde ist für lineare Bewegung + einfaches
--- Tower-Targeting mehr als ausreichend fein.
RaidConfig.RAID_TICK_SECONDS = 0.1

--- Radius um das Plot-Zentrum, ab dem Gegner als "im Zentrum angekommen"
--- gelten (Studs).
RaidConfig.CENTER_REACH_RADIUS = 3

--- Radius, auf dem Gegner am Rand der (~60 Studs flat-to-flat großen)
--- Habitat-Plot-Basis spawnen (siehe HabitatPlotBase.lua/PlotRegistry).
RaidConfig.SPAWN_RING_RADIUS = 34

--- Spawn-Höhe relativ zum Plot-PrimaryPart (Studs über der Plattform).
RaidConfig.SPAWN_HEIGHT_OFFSET = 3

-- // Offline-Auswertung (deterministische Formel, siehe RaidService) -------------
-- Kein Zufall: verpasste Raids werden rein anhand der Turmstärke des
-- Spielers gegen die volle Gegner-HP-Summe (GetTotalEnemyHP) entschieden.
-- Siehe RaidService.evaluateOfflineRaidWin für die genaue Formel.

--- Angenommenes Zeitbudget (Sekunden), das ein Spieler laut Annahme in einem
--- LIVE-Raid gehabt hätte, um seine Türme feuern zu lassen - Grundlage für
--- den Offline-DPS-Vergleich. Bewusst grob (kein echtes Zeit-Tracking nötig,
--- siehe Formel-Dokumentation in RaidService).
RaidConfig.OFFLINE_ASSUMED_RAID_SECONDS = 70

--- Schwierigkeits-Multiplikator auf die Gesamt-Gegner-HP für die
--- Offline-Formel (>1 = schwerer als live, <1 = leichter). 1.0 = neutral.
RaidConfig.OFFLINE_DIFFICULTY_MULTIPLIER = 1.0

-- // Belohnungen (Sieg) -----------------------------------------------------------

RaidConfig.VICTORY_REWARD_TIDE_COINS = 220
RaidConfig.VICTORY_ABYSSAL_SHARD_CHANCE = 0.15 -- GDD Abschnitt 3: "Bonus-Loot (seltene Eier, Tide Coins)" - Shards als seltener Bonus
RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT = 1

-- // Entführung / Lösegeld (Niederlage) --------------------------------------------
-- Lösegeld-Kosten je Rarity der entführten Kreatur (GDD Abschnitt 3:
-- "Soft-Loss ... gegen Lösegeld/Rettungsmission zurückholbar"). Deckt die
-- volle GDD-Rarity-Skala ab (Abschnitt 3: Common -> Mythic -> Abyssal),
-- auch wenn BreedingConfig aktuell nur bis Legendary würfelt - GachaConfig/
-- künftige Systeme können auch Mythic/Abyssal ins Inventar legen.
local RANSOM_COST_BY_RARITY: { [string]: number } = {
	Common = 150,
	Uncommon = 250,
	Rare = 450,
	Epic = 800,
	Legendary = 1500,
	Mythic = 3000,
	Abyssal = 6000,
}
RaidConfig.RANSOM_COST_BY_RARITY = RANSOM_COST_BY_RARITY
RaidConfig.RANSOM_COST_DEFAULT = 300 -- Fallback für unbekannte/künftige Rarity-Werte

--- Liefert die Lösegeld-Kosten (Tide Coins) für eine gegebene Rarity.
function RaidConfig.GetRansomCost(rarity: string): number
	return RANSOM_COST_BY_RARITY[rarity] or RaidConfig.RANSOM_COST_DEFAULT
end

return RaidConfig
