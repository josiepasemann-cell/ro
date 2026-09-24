--[[
	Abyssara – Deep Tide Tycoon
	Modul: BuildingConfig
	Zuständigkeit:
		Statische Datentabelle der 4 MVP-Gebäude (GDD Abschnitt 8/9):
		BroodPool_Basic, GlowBuoyStation, FilterPlant, AnglerfishTower.
		Einzige Quelle der Wahrheit für Baukosten, Verkaufs-Rückerstattung,
		Freischalt-Level und Baufeld-Bedarf pro Gebäude - PlacementService
		(Server) UND die Client-Vorschau lesen ausschließlich aus diesem
		Modul, damit Zahlen nie an zwei Stellen auseinanderlaufen.

	Rojo-Einhängepunkt:
		src/shared/BuildingConfig.lua -> ReplicatedStorage.BuildingConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der
		Client liest dies NUR für Anzeige/Vorschau-Zwecke; die alleinige
		Autorität über Käufe/Platzierung bleibt PlacementService auf dem
		Server, siehe dort.)

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
		aber einen spürbaren Teil der Investition zurück.

	Produktionsraten (IncomeRate, ergänzt für das Idle-Einkommen-/
	Produktionssystem, GDD Abschnitt 3 "Minute-zu-Minute" + Abschnitt 9
	Punkt 3):
		Nur Gebäude, deren Rolle laut GDD Abschnitt 8 tatsächlich
		"Ressourcen-Produktionsgebäude" ist, produzieren passiv Tide
		Coins - GlowBuoyStation ("Sammelt passiv Glow Spores für
		Tide-Coin-Einkommen") und FilterPlant ("Ressourcen-
		Produktionsgebäude, veredelt Rohertrag"). BroodPool (Zucht-
		Timer-Gebäude, eigenes künftiges System, GDD Abschnitt 9 Punkt 4)
		und AnglerfishTower (reiner Verteidigungsturm für Trench Raids,
		GDD Abschnitt 9 Punkt 5) haben bewusst IncomeRate = 0 - sie
		gehören zu anderen Systemen statt zum Idle-Einkommen.

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
		tatsächlich in Tide-Coin-Gutschriften umsetzt.
]]

export type BuildingId = "BroodPool" | "GlowBuoyStation" | "FilterPlant" | "AnglerfishTower"

export type BuildingDefinition = {
	Id: BuildingId,
	DisplayName: string,
	Description: string,
	Cost: number, -- Tide Coins
	SellRefundFraction: number, -- 0..1, Anteil von Cost bei Verkauf/Entfernen
	GridFieldCount: number, -- benötigte Baufelder auf der Habitat-Plot-Basis (MVP: immer 1)
	UnlockLevel: number,
	TemplateName: string, -- Name unter ReplicatedStorage.AssetTemplates.Buildings (siehe AssetTemplateSetup)
	IncomeRate: number, -- Tide Coins / Minute passives Idle-Einkommen; 0 = kein Produktionsgebäude
}

local BuildingConfig = {}

local DEFINITIONS: { [string]: BuildingDefinition } = {
	GlowBuoyStation = {
		Id = "GlowBuoyStation",
		DisplayName = "Lichtboje",
		Description = "Sammelt passiv Glow Spores für Tide-Coin-Einkommen.",
		Cost = 150,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 1,
		TemplateName = "GlowBuoyStation",
		IncomeRate = 15,
	},
	BroodPool = {
		Id = "BroodPool",
		DisplayName = "Brutbecken",
		Description = "Inkubiert Kreaturen-Eier (Basisstufe 1/3).",
		Cost = 250,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 1,
		TemplateName = "BroodPool_Basic",
		IncomeRate = 0, -- kein Idle-Einkommen, siehe künftiges Zucht-/Ei-System (GDD Abschnitt 9 Punkt 4)
	},
	FilterPlant = {
		Id = "FilterPlant",
		DisplayName = "Filteranlage",
		Description = "Ressourcen-Produktionsgebäude, veredelt Rohertrag.",
		Cost = 450,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 3,
		TemplateName = "FilterPlant",
		IncomeRate = 30,
	},
	AnglerfishTower = {
		Id = "AnglerfishTower",
		DisplayName = "Anglerfisch-Turm",
		Description = "Verteidigungsturm gegen Trench-Raid-Wellen.",
		Cost = 700,
		SellRefundFraction = 0.5,
		GridFieldCount = 1,
		UnlockLevel = 8,
		TemplateName = "AnglerfishTower",
		IncomeRate = 0, -- kein Idle-Einkommen, reiner Verteidigungsturm (GDD Abschnitt 9 Punkt 5)
	},
}

--- Feste Anzeige-/Hotkey-Reihenfolge (1-4), da `pairs()` über DEFINITIONS
--- keine stabile Reihenfolge garantiert.
BuildingConfig.ORDER = { "GlowBuoyStation", "BroodPool", "FilterPlant", "AnglerfishTower" } :: { BuildingId }

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

return BuildingConfig
