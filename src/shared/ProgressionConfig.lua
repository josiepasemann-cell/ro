--[[
	Abyssara – Deep Tide Tycoon
	Modul: ProgressionConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für das Spieler-Level-/
		XP-System (GDD Abschnitt 6 "Fortschrittssystem" + Abschnitt 9,
		Punkt 7 "Progression-/Level-System"): die XP-Kurve bis Level 25 (MVP-
		Scope laut Abschnitt 10), die XP-Belohnung je Ereignis-Typ, sowie die
		Level-Unlock-Tabelle. Enthält bewusst KEINE Zufalls-/Persistenz-Logik
		selbst (die lebt in ProgressionService) – nur Daten + kleine, reine
		Hilfsfunktionen darauf, analog zu GachaConfig/BuildingConfig.

	Rojo-Einhängepunkt:
		src/shared/ProgressionConfig.lua -> ReplicatedStorage.ProgressionConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - der Client
		liest dies NUR für Anzeige-Zwecke, z. B. um die XP-Leiste zu
		beschriften; die alleinige Autorität über tatsächliche XP-Vergabe und
		Level-Ups bleibt ProgressionService auf dem Server, siehe dort. Anders
		als GachaConfig gibt es hier keinen Compliance-Grund, das Modul vor
		dem Client zu verstecken - die XP-Kurve ist kein Geheimnis.)

	XP-KURVE - HERLEITUNG (GDD Abschnitt 6, "Progression Curve"):
		Das GDD nennt keine exakten XP-Zahlen, nur ein Tempo-Bild:
			"Level 1–10: schnelle Freischaltungen (alle 5–10 Min.),
			 Tutorial-Belohnungen hoch."
			"Level 10–25: Kosten x1,15 pro Stufe, Einkommen x1,12 – leichtes
			 Gap, durch Gamepasses/Season Pass abfederbar."
		Daraus pragmatisch abgeleitet (identisches Vorgehen wie
		BuildingConfig's Preisgestaltungs-Kommentar für die dort ebenfalls
		nicht exakt vorgegebenen Baukosten):
			- BASE_XP_STEP (120 XP für Level 1->2) so gewählt, dass ein aktiver
			  Spieler (Gebäude bauen ~15 XP, Zucht abschließen ~40 XP, Raid-
			  Sieg ~60 XP) einen frühen Level-Up realistisch in 5-10 Minuten
			  erreicht (Tutorial-Loop laut GDD Abschnitt 3).
			- EARLY_GROWTH = 1.08 für die Stufen 1->2 .. 9->10: bewusst flacher
			  als die spätere Kosten-Kurve, damit sich "schnelle
			  Freischaltungen" auch nach mehreren Level-Ups noch schnell
			  anfühlen (deckt sich mit BuildingConfig.UnlockLevel=3 für die
			  FilterPlant, die so realistisch früh erreichbar bleibt).
			- LATE_GROWTH = 1.15 für die Stufen 10->11 .. 24->25: übernimmt
			  direkt den im GDD explizit genannten Kosten-Faktor "x1,15 pro
			  Stufe" ab Level 10 - das "leichte Gap" wird dadurch spürbar,
			  ohne unspielbar zu werden (Level 25 bleibt im MVP-Zeitrahmen
			  erreichbar, siehe Abschnitt 10: "Level-/XP-System bis Level 25").
			- MAX_LEVEL = 25, exakt der MVP-Scope aus Abschnitt 10. Level 25+
			  (GDD Abschnitt 6, Phase 2/3: "Level 25–45", Prestige) ist bewusst
			  NICHT Teil dieser Tabelle - ProgressionService deckelt XP-
			  Gutschriften oberhalb Level 25 (siehe dort), ein künftiges
			  Prestige-/Ascend-System (GDD Abschnitt 9, Punkt 8) kann diese
			  Tabelle später einfach erweitern, ohne bestehende Werte zu
			  verändern.

	Rundungs-Hinweis:
		Alle XP-Werte werden auf ganze Zahlen gerundet (math.floor(x + 0.5)),
		da PlayerDataService.XP eine reine Zahl ohne Nachkommastellen-Semantik
		ist (siehe dortiger Kommentar "Speichert nur die Rohwerte").
]]

export type ProgressionEventSource = "BuildingPlaced" | "BreedingCompleted" | "RaidWon" | "MysteryEggOpened"

export type UnlockEntry = {
	Level: number,
	Id: string,
	Label: string, -- deutscher Anzeigename fürs Level-Up-Banner
	Type: "Building" | "BroodPoolSlot" | "Tower" | "ZonePortal",
	Implemented: boolean, -- false = nur als Ankündigung im Banner, System existiert noch nicht (siehe ZonePortal-Eintrag)
}

local ProgressionConfig = {}

-- // Grundwerte der XP-Kurve (siehe Herleitung im Kopfkommentar) -------------

ProgressionConfig.MAX_LEVEL = 25

local BASE_XP_STEP = 120 -- XP-Bedarf für Level 1 -> 2
local EARLY_GROWTH = 1.08 -- Level 1-9 (GDD: "schnelle Freischaltungen alle 5-10 Min.")
local LATE_GROWTH = 1.15 -- Level 10-24 (GDD: "Kosten x1,15 pro Stufe" ab Level 10)
local EARLY_LATE_BOUNDARY_LEVEL = 10 -- ab hier gilt LATE_GROWTH (GDD-Grenze "Level 1-10" vs. "Level 10-25")

-- // XP-Belohnungen je Ereignis-Typ (GDD Abschnitt 6: "XP aus Quests, Raid-
-- Siegen, Zuchterfolgen" + Abschnitt 9 Punkt 7). Das Tages-Quest-System
-- selbst ist NICHT Teil dieses Auftrags (GDD Abschnitt 9, Punkt 11, eigenes
-- künftiges System) - "Gebäude platziert" und "Mystery Egg geöffnet" decken
-- stattdessen die beiden bereits existierenden, sofort verfügbaren
-- MVP-Ereignisquellen ab, die im Kern-Loop (GDD Abschnitt 3) regelmäßig
-- auftreten. Werte sind bewusst gestaffelt nach Aufwand/Seltenheit des
-- jeweiligen Ereignisses (Bauen ist häufig & günstig -> wenig XP, ein
-- Raid-Sieg ist seltener & riskanter -> viel XP).
ProgressionConfig.XP_REWARDS = {
	BuildingPlaced = 15,
	BreedingCompleted = 40,
	RaidWon = 60,
	MysteryEggOpened = 25,
} :: { [ProgressionEventSource]: number }

-- // Level-Unlock-Tabelle (GDD Abschnitt 6: "Unlocks pro Level") -------------
-- WICHTIG: FilterPlant (Level 3) und AnglerfishTower (Level 8) sind bereits
-- über BuildingConfig.UnlockLevel vollständig durchgesetzt (PlacementService
-- prüft das dort, siehe PlacementService.RequestPlace) - diese Einträge hier
-- dienen NUR der Anzeige im Level-Up-Banner, sind KEINE zweite
-- Durchsetzungsstelle (keine doppelte Prüfung, keine Divergenzgefahr).
-- "Zweiter Brutbeckenslot" (Level 6) wird hier ZUSÄTZLICH aktiv durchgesetzt
-- (siehe GetMaxBroodPools unten + PlacementService), weil es bislang keine
-- eigene Konfigurationsstelle dafür gab. "Zonenportal Dämmerzone" (Level 10)
-- ist bewusst NUR ein Anzeige-Eintrag (Implemented = false) - das
-- Zonen-/Teleport-System selbst existiert im MVP noch nicht (GDD Abschnitt
-- 10 MVP-Scope nennt zwar "2 Zonen: Sonnenzone, Dämmerzone", aber kein
-- Teleport-/Zonenwechsel-System als eigenen Auftrag; ein künftiges Zonen-
-- System kann diesen Eintrag auf Implemented = true umstellen, sobald es
-- existiert).
ProgressionConfig.UNLOCKS = {
	{
		Level = 3,
		Id = "FilterPlant",
		Label = "Neues Baumodul: Filteranlage",
		Type = "Building",
		Implemented = true,
	},
	{
		Level = 6,
		Id = "BroodPoolSecondSlot",
		Label = "Zweiter Brutbecken-Slot",
		Type = "BroodPoolSlot",
		Implemented = true,
	},
	{
		Level = 8,
		Id = "AnglerfishTower",
		Label = "Erster Verteidigungsturm: Anglerfisch-Turm",
		Type = "Tower",
		Implemented = true,
	},
	{
		Level = 10,
		Id = "ZonePortal_Daemmerzone",
		Label = "Zonenportal: Dämmerzone (folgt)",
		Type = "ZonePortal",
		Implemented = false, -- PLATZHALTER: Zonen-/Teleport-System existiert noch nicht, siehe Kommentar oben.
	},
} :: { UnlockEntry }

-- // XP-Kurve: einmalig beim Modul-Load vorberechnete Tabellen ---------------
-- STEP_XP[level] = XP-Bedarf, um von `level` auf `level + 1` zu kommen
-- (nil für level >= MAX_LEVEL, da es dort keine weitere Stufe gibt).
-- TOTAL_XP_FOR_LEVEL[level] = kumulative All-Time-XP, die exakt für das
-- Erreichen von `level` (ausgehend von Level 1, 0 XP) nötig ist.
local STEP_XP: { [number]: number } = {}
local TOTAL_XP_FOR_LEVEL: { [number]: number } = { [1] = 0 }

do
	local xp = BASE_XP_STEP
	local cumulative = 0
	for level = 1, ProgressionConfig.MAX_LEVEL - 1 do
		local stepXp = math.floor(xp + 0.5)
		STEP_XP[level] = stepXp
		cumulative += stepXp
		TOTAL_XP_FOR_LEVEL[level + 1] = cumulative

		local growth = if level < EARLY_LATE_BOUNDARY_LEVEL then EARLY_GROWTH else LATE_GROWTH
		xp *= growth
	end
end

-- // Öffentliche API ----------------------------------------------------------

--- XP-Bedarf, um von `level` auf `level + 1` zu kommen. Gibt nil zurück,
--- falls `level` bereits MAX_LEVEL erreicht/überschritten hat (keine weitere
--- Stufe in der MVP-Kurve, siehe Kopfkommentar).
function ProgressionConfig.GetXPToNextLevel(level: number): number?
	return STEP_XP[level]
end

--- Kumulative All-Time-XP, die exakt für das Erreichen von `level` nötig
--- ist (Level 1 = 0 XP). Für level > MAX_LEVEL wird der MAX_LEVEL-Wert
--- zurückgegeben (keine Extrapolation über die MVP-Kurve hinaus).
function ProgressionConfig.GetTotalXPForLevel(level: number): number
	local clamped = math.clamp(math.floor(level), 1, ProgressionConfig.MAX_LEVEL)
	return TOTAL_XP_FOR_LEVEL[clamped] or 0
end

--- Leitet aus einer kumulativen All-Time-XP-Summe (PlayerDataService.XP) das
--- höchste Level ab, dessen XP-Schwelle bereits erreicht ist - geklemmt auf
--- MAX_LEVEL (zusätzliche XP über die MAX_LEVEL-Schwelle hinaus wird
--- weiterhin gespeichert, siehe PlayerDataService.AddXP, erzeugt im MVP aber
--- keine weiteren Level-Ups; Basis für ein künftiges Prestige-System).
function ProgressionConfig.GetLevelForTotalXP(totalXP: number): number
	local level = 1
	while level < ProgressionConfig.MAX_LEVEL and totalXP >= (TOTAL_XP_FOR_LEVEL[level + 1] or math.huge) do
		level += 1
	end
	return level
end

--- Liefert (xpIntoCurrentLevel, xpNeededForCurrentLevel) für die HUD-XP-
--- Leiste: wie viel XP der Spieler INNERHALB des aktuellen Levels bereits
--- hat, und wie viel für den nächsten Level-Up insgesamt nötig ist. Bei
--- bereits erreichtem MAX_LEVEL wird (0, 0) zurückgegeben (Client zeigt in
--- diesem Fall sinnvollerweise eine volle/deaktivierte Leiste statt einer
--- Division durch 0).
function ProgressionConfig.GetProgressWithinLevel(totalXP: number, level: number): (number, number)
	if level >= ProgressionConfig.MAX_LEVEL then
		return 0, 0
	end
	local floorXp = TOTAL_XP_FOR_LEVEL[level] or 0
	local stepXp = STEP_XP[level] or 0
	return math.max(0, totalXP - floorXp), stepXp
end

--- Maximale Anzahl gleichzeitig platzierbarer BroodPool-Gebäude für ein
--- gegebenes Spieler-Level (GDD Abschnitt 6: "zweiter Brutbeckenslot Level
--- 6"). PlacementService setzt dies aktiv durch (siehe dort) - einzige
--- Durchsetzungsstelle für diese Regel.
function ProgressionConfig.GetMaxBroodPools(level: number): number
	if level >= 6 then
		return 2
	end
	return 1
end

return ProgressionConfig
