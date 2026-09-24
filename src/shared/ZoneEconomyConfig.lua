--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: ZoneEconomyConfig
	Zuständigkeit:
		Content Update 1, Abschnitt 6 ("Zonen-spezifischer Sporen-Bonus") +
		Abschnitt 3.1 ("Zonen-Skalierung"): einzige Datentabelle dafür, was
		"die Zone eines Spielers" für Wirtschafts-/Raid-Zwecke bedeutet, und
		wie stark tiefere Zonen Einkommen/Sporen-Wert gegenüber SunZone/
		TwilightZone bonieren. Reine Daten + eine winzige, reine
		Lookup-Hilfsfunktion - keine Logik, identisches Muster zu RaidConfig/
		BuildingConfig/BreedingConfig.

	DESIGN-ENTSCHEIDUNG (siehe Auftrag - "the player's zone" ist absichtlich
	nicht eindeutig im Content-Update-Dokument definiert, da jeder Spieler
	nur EIN Plot besitzt und Zonen laut TravelService reine Reiseziele sind,
	kein dauerhafter Aufenthaltsort):

		"Die Zone eines Spielers" = die TIEFSTE Zone, die sein aktuelles
		Level bereits freischaltet (GetZoneForLevel unten), NICHT seine
		zuletzt betretene/physische Position. Begründung:

		1. Einfach + deterministisch + rein serverseitig: eine reine
		   Funktion von PlayerDataService.GetLevel(player) - kein neuer
		   persistenter Zustand nötig (kein "LastZone"-Feld in
		   PlayerDataService, keine Client-Positions-Meldung, kein
		   Server-Trust-Problem).
		2. Passt zum bestehenden Raid-/Idle-Modell: Raids finden IMMER auf
		   dem EIGENEN Plot statt (siehe RaidService.startRaid -
		   CenterPosition = plot.PrimaryPart.Position), niemals in einer
		   der 4 begehbaren Zonen-Terrain-Chunks. Ebenso spawnen Glow-Spore-
		   Pickups laut PickupSpawner ausschließlich auf dem eigenen Plot,
		   nicht in den Zonen-Chunks. Eine "während man physisch in
		   MidnightZone steht"-Regel hätte deshalb ohnehin nie einen
		   spielbaren Effekt - sie wörtlich umzusetzen würde PickupSpawner/
		   RaidService zwingen, die Live-Charakterposition zu tracken, für
		   ein Feature, das in der Praxis nie greifen würde.
		3. Fühlt sich für Spieler trotzdem stimmig an: "tiefer vorgedrungen"
		   (höheres Level, höhere Zonen-Portale freigeschaltet) ist
		   spielerisch dieselbe Fortschritts-Erzählung wie "tiefer
		   unterwegs" - passt zum GDD-Leitmotiv "Zonen-Tiefe = Fortschritt".
		4. Konsistent zwischen Raid-Skalierung UND Sporen-/Einkommens-Bonus:
		   beide lesen exakt denselben GetZoneForLevel-Wert, es gibt also
		   nie einen Widerspruch ("harte Raids, aber SunZone-Einkommen"
		   oder umgekehrt).

		ZONE_UNLOCK_LEVEL unten ist eine bewusst EIGENSTÄNDIGE, statische
		Kopie von TravelService.ZONE_REQUIRED_LEVEL_FALLBACK (1/10/25/45):
		TravelService ist ein serverseitiges Modul (ServerScriptService) und
		erlaubt zur Laufzeit eine Portal-Attribut-Override (siehe dortiges
		attachZonePortalPrompts) - dieses Modul hier lebt aber bewusst unter
		ReplicatedStorage (Server UND Client lesen es, siehe RaidConfig-
		Konvention) und darf daher kein serverseitiges Modul requiren. Die
		Portal-Attribute in TidalMarketHub.lua sind laut assets/models/
		README.md ohnehin statisch auf exakt diese 4 Werte gesetzt - die
		Override-Möglichkeit in TravelService ist nur eine defensive
		Absicherung, kein tatsächlich variierender Wert. Sollte sich das
		einmal ändern, ist dies der einzige Ort, der synchron gehalten
		werden müsste (siehe docs/zones-and-raids.md für den vollständigen
		Entscheid).

	Rojo-Einhängepunkt:
		src/shared/ZoneEconomyConfig.lua -> ReplicatedStorage.ZoneEconomyConfig
]]

export type ZoneId = "SunZone" | "TwilightZone" | "MidnightZone" | "HadalDepths"

local ZoneEconomyConfig = {}

--- Feste Tiefen-Reihenfolge (flachste -> tiefste Zone).
ZoneEconomyConfig.ZONE_ORDER = { "SunZone", "TwilightZone", "MidnightZone", "HadalDepths" } :: { ZoneId }

-- Statische Kopie von TravelService.ZONE_REQUIRED_LEVEL_FALLBACK (siehe
-- Kopfkommentar, warum keine direkte Abhängigkeit).
local ZONE_UNLOCK_LEVEL: { [ZoneId]: number } = {
	SunZone = 1,
	TwilightZone = 10,
	MidnightZone = 25,
	HadalDepths = 45,
}
ZoneEconomyConfig.ZONE_UNLOCK_LEVEL = ZONE_UNLOCK_LEVEL

-- Content Update 1, Abschnitt 6: "Glow Spores collected while standing in
-- MidnightZone have a flat +20% Tide Coin value" / HadalDepths +35%. Wird
-- hier als allgemeiner Zonen-Einkommens-Multiplikator geführt (siehe
-- IdleIncomeService-Integration: die einzige tatsächlich wiederkehrende
-- Tide-Coin-Quelle im MVP ist das Gebäude-Idle-Einkommen, da Glow-Spore-
-- Abgabe an GlowBuoyStation letztlich ebenfalls über dasselbe
-- IncomeRate-Modell/denselben "eine Zone pro Spieler"-Wert läuft - siehe
-- Kopfkommentar-Punkt 2 oben).
local SPORE_VALUE_MULTIPLIER: { [ZoneId]: number } = {
	SunZone = 1.0,
	TwilightZone = 1.0,
	MidnightZone = 1.2,
	HadalDepths = 1.35,
}
ZoneEconomyConfig.SPORE_VALUE_MULTIPLIER = SPORE_VALUE_MULTIPLIER

--- Liefert die "Zone des Spielers" für `level` (siehe Design-Entscheidung
--- oben) - die tiefste Zone, deren ZONE_UNLOCK_LEVEL bereits erreicht ist.
--- Fällt für Level < 1 (sollte nie vorkommen) auf SunZone zurück.
function ZoneEconomyConfig.GetZoneForLevel(level: number?): ZoneId
	local numericLevel = tonumber(level) or 1
	local deepest: ZoneId = "SunZone"
	for _, zoneId in ipairs(ZoneEconomyConfig.ZONE_ORDER) do
		if numericLevel >= (ZONE_UNLOCK_LEVEL[zoneId] or math.huge) then
			deepest = zoneId
		end
	end
	return deepest
end

--- Liefert den Tide-Coin-/Einkommens-Multiplikator für `zoneId`. Unbekannte/
--- zukünftige Zonen-Ids fallen defensiv auf 1.0 (neutral) zurück statt einen
--- Fehler zu werfen.
function ZoneEconomyConfig.GetIncomeMultiplier(zoneId: string?): number
	if type(zoneId) ~= "string" then
		return 1.0
	end
	return SPORE_VALUE_MULTIPLIER[zoneId :: ZoneId] or 1.0
end

return ZoneEconomyConfig
