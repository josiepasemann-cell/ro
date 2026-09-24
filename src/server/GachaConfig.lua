--[[
	Abyssara – Deep Tide Tycoon
	Modul: GachaConfig
	Zuständigkeit:
		Einzige, klar editierbare Quelle der Wahrheit für die Mystery-Egg-
		Drop-Tabelle, die Kreaturen-Pools je Rarity, den Pity-Mechanismus und
		die Duplikat-Ausgleichswerte. Enthält bewusst KEINE Zufalls-/Roll-
		Logik selbst (die lebt in GachaService) – nur Daten + kleine, reine
		Hilfsfunktionen darauf.

	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".

	Rojo-Einhängepunkt:
		src/server/  ->  ServerScriptService
		(bewusst NICHT unter ReplicatedStorage/src/shared! Die Drop-Tabelle
		darf laut Roblox-Compliance zwar vor Kauf offengelegt werden, aber
		nur über den serverseitig kontrollierten Weg – siehe
		GachaService.GetOddsTable() und den RemoteFunction-Kanal
		"GetGachaOdds" in GachaRemotes.lua. Läge dieses Modul in
		ReplicatedStorage, könnte der Client es direkt requiren und die
		Werte hart auf Client-Seite duplizieren/cachen, was bei einer
		späteren Balancing-Änderung zu Inkonsistenzen zwischen Anzeige und
		tatsächlichem Roll führen könnte. Weil ServerScriptService dem
		Client grundsätzlich nicht zugänglich ist, ist der "nur über den
		Server lesen"-Grundsatz hier technisch erzwungen statt nur
		Konvention.)

	Namenskonsistenz zu den bestehenden 3D-/UI-Assets:
		- Rarity-Strings ("Common".."Mythic") entsprechen exakt dem
		  `EggTier`-Attribut der MysteryEgg_*-Modelle (assets/models/gacha/)
		  und den `RarityRow_<Tier>`-Namen in GachaOddsPanel.lua.
		- CREATURE_POOL referenziert die Model-Namen unter
		  assets/models/creatures/ (== Model.Name dort), deren `Rarity`-
		  Attribut mit dem jeweiligen Schlüssel hier übereinstimmt.
]]

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityDefinition = {
	Weight: number, -- Gewicht für den gewichteten Zufalls-Roll (hier == Prozentwert, da Summe = 100)
	DisplayLabel: string, -- deutscher Anzeigename für die Odds-UI
	Color: Color3, -- muss exakt zu GachaOddsPanel.lua's ColorSwatch-Farbe je Zeile passen
}

local GachaConfig = {}

-- // Rarity-Reihenfolge (Common = schwächste, Mythic = stärkste Stufe) -------
-- Deckt bewusst nur die Teilmenge ab, für die aktuell Mystery-Egg-Modelle
-- existieren (assets/models/gacha/). Die volle GDD-Skala geht bis "Abyssal"
-- (siehe docs/game-design-doc.md, Abschnitt 3) - das ist Endgame-Content
-- außerhalb des Gacha-Scopes von Erweiterungskonzept 1.7 und wird hier
-- bewusst nicht mitgeführt.
GachaConfig.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { Rarity }

-- // Drop-Tabelle --------------------------------------------------------
-- Gewichte entsprechen 1:1 den Platzhalter-Prozentwerten, die bereits als
-- Layout-Platzhalter in assets/models/ui/GachaOddsPanel.lua stehen (Summe
-- = 100.0), damit die zuvor rein visuelle Odds-UI ab jetzt exakt das
-- anzeigt, was auch tatsächlich gerollt wird. Werte hier sind die einzige
-- Stelle, die für Balancing-Änderungen angepasst werden muss.
GachaConfig.DROP_TABLE = {
	Common = { Weight = 45.0, DisplayLabel = "Gewöhnlich", Color = Color3.fromRGB(215, 250, 245) },
	Uncommon = { Weight = 27.0, DisplayLabel = "Ungewöhnlich", Color = Color3.fromRGB(120, 235, 205) },
	Rare = { Weight = 16.0, DisplayLabel = "Selten", Color = Color3.fromRGB(70, 210, 235) },
	Epic = { Weight = 8.0, DisplayLabel = "Episch", Color = Color3.fromRGB(170, 90, 255) },
	Legendary = { Weight = 3.5, DisplayLabel = "Legendär", Color = Color3.fromRGB(150, 70, 255) },
	Mythic = { Weight = 0.5, DisplayLabel = "Mythisch", Color = Color3.fromRGB(135, 60, 255) },
} :: { [Rarity]: RarityDefinition }

-- // Kreaturen-Pool je Rarity ---------------------------------------------
-- Model-Namen exakt wie unter assets/models/creatures/*.lua vergeben.
-- HINWEIS: Für "Mythic" existiert im aktuellen Kreaturen-Set (siehe
-- assets/models/README.md, Tabelle "creatures/") noch KEIN dediziertes
-- Modell (das MVP-Set deckt nur Common..Legendary ab). GachaService fällt
-- in diesem Fall bewusst auf den nächstniedrigeren, nicht-leeren Pool
-- zurück (siehe GachaService._pickCreatureForRarity) und loggt das als
-- Warnung. Sobald ein echtes Mythic-Kreaturen-Asset existiert, hier
-- einfach den entsprechenden Model-Namen eintragen.
GachaConfig.CREATURE_POOL = {
	Common = { "GlowJelly", "GlowShrimp" },
	Uncommon = { "GlowRay" },
	Rare = { "Anglerfish" },
	Epic = { "BioluminescentEel" },
	Legendary = { "CrystalKraken" },
	Mythic = {}, -- bewusst leer, siehe Hinweis oben
} :: { [Rarity]: { string } }

-- // Anzeigenamen-Fallback je Kreatur --------------------------------------
-- GachaService versucht zuerst, den Anzeigenamen LIVE vom bereits in
-- Workspace.Assets.Creatures platzierten Modell zu lesen
-- (model:GetAttribute("CreatureName"), von den Buildscripts gesetzt).
-- Diese Tabelle ist nur der Fallback, falls das Modell (noch) nicht in
-- der Welt existiert (z. B. auf einem Test-/Server-Start ohne vorher
-- ausgeführte Buildscripts).
GachaConfig.CREATURE_DISPLAY_NAME_FALLBACK = {
	GlowJelly = "Glühqualle",
	GlowShrimp = "Leuchtgarnele",
	GlowRay = "Leuchtrochen",
	Anglerfish = "Anglerfisch",
	BioluminescentEel = "Biolumineszenz-Aal",
	CrystalKraken = "Kristallkrake",
} :: { [string]: string }

-- // Pity-Mechanik ---------------------------------------------------------
-- Garantierter Epic-oder-besser-Drop nach PITY_THRESHOLD in Folge
-- erfolglosen (< Epic) Ei-Öffnungen. Zähler wird pro Spieler serverseitig
-- geführt (siehe GachaService, PLATZHALTER-Hinweis zur späteren
-- DataStore-Persistenz) und bei jedem Epic-oder-besser-Ergebnis
-- zurückgesetzt (egal ob natürlich oder durch Pity erzwungen).
GachaConfig.PITY_THRESHOLD = 50
GachaConfig.PITY_MIN_RARITY = "Epic" :: Rarity

-- // Duplikatsschutz: Ausgleichs-Menge in Tide Coins je Rarity ------------
-- Vgl. expansion-concepts.md 1.7: "doppelte Kreaturen werden automatisch
-- in Tide Coins/Fusions-Katalysatoren (vgl. 3.14) konvertiert". Diese
-- Erweiterung implementiert vorerst nur den Tide-Coins-Pfad (Fusions-
-- Katalysatoren gehören zu Konzept 3.14 und sind hier bewusst out of
-- scope). Werte sind Balancing-Platzhalter, hier zentral änderbar.
GachaConfig.DUPLICATE_COMPENSATION_TIDE_COINS = {
	Common = 25,
	Uncommon = 60,
	Rare = 150,
	Epic = 400,
	Legendary = 1200,
	Mythic = 4000,
} :: { [Rarity]: number }

-- // Preis für ein Ei an der Station (Tide Coins) --------------------------
-- Muss deutlich über dem erwarteten Duplikat-Ausgleich liegen (~145 Coins pro
-- Roll, wenn nur noch Duplikate kommen), sonst wird das Ei zur Münzmaschine.
-- Der Robux-Kauf (OpenPurchasedEgg) ist davon unberührt.
GachaConfig.EGG_COST_TIDE_COINS = 350

-- // Anti-Spam: Mindestabstand zwischen zwei Öffnungs-Anfragen (Sekunden) --
GachaConfig.MIN_SECONDS_BETWEEN_ROLLS = 1.0

-- // Hilfsfunktionen --------------------------------------------------------

--- Liefert den 1-basierten Index einer Rarity in RARITY_ORDER (Common = 1,
--- Mythic = 6). Wird für Pity-/Duplikat-Vergleiche ("mindestens Epic?")
--- verwendet.
function GachaConfig.GetRarityIndex(rarity: Rarity): number
	local order = GachaConfig.RARITY_ORDER
	for index = 1, #order do
		if order[index] == rarity then
			return index
		end
	end
	error(("[GachaConfig] Unbekannte Rarity: %s"):format(tostring(rarity)))
end

--- true, wenn `rarity` mindestens so hochwertig ist wie `minRarity`.
function GachaConfig.IsRarityAtLeast(rarity: Rarity, minRarity: Rarity): boolean
	return GachaConfig.GetRarityIndex(rarity) >= GachaConfig.GetRarityIndex(minRarity)
end

--- Summe aller Gewichte in der Drop-Tabelle (praktisch immer 100, aber
--- bewusst nicht hart einprogrammiert, falls die Tabelle später verändert
--- wird und nicht mehr exakt auf 100 summiert).
function GachaConfig.GetTotalWeight(): number
	local total = 0
	for _, definition in pairs(GachaConfig.DROP_TABLE) do
		total += definition.Weight
	end
	return total
end

return GachaConfig
