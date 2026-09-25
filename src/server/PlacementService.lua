--[[
	Abyssara – Deep Tide Tycoon
	Modul: PlacementService
	Zuständigkeit:
		Kernlogik des Bauplatzierungs-Systems (GDD Abschnitt 9, Punkt 2):
		serverseitige Validierung jeder Platzierungs-/Entfernungsanfrage
		(Kollisionsprüfung, Kaufkosten-Prüfung/-Abzug, 90°-Snap-Rotation,
		Level-Freischaltung), Instanziierung/Entfernung der Gebäude-Modelle
		im Workspace, sowie Wiederherstellung des gespeicherten Habitat-
		Layouts beim Join. Nutzt für JEDE Persistenz-Operation ausschließlich
		die bestehende PlayerDataService-API (GetHabitatLayout,
		AddHabitatPlacement, RemoveHabitatPlacement, GetCurrency,
		AddCurrency) - erfindet keine eigene Persistenz.

		Reine Logik, keine Remote-Verdrahtung - die übernimmt
		PlacementServer.server.lua (analog zu GachaService/GachaServer.
		server.lua), damit dieses Modul unabhängig von RemoteEvents testbar
		bleibt.

	Sicherheitsprinzip (kein Client-Trust):
		Jede öffentliche Funktion hier nimmt zwar rohe, vom Client
		behauptete Werte entgegen (buildingId, fieldIndex, rotationY,
		placementId), validiert/normalisiert aber JEDEN davon komplett neu,
		bevor irgendetwas verändert wird: unbekannte BuildingId, ungültiger
		Feld-Index, bereits belegtes Feld, zu niedriges Spieler-Level, zu
		wenig Tide Coins und beliebige Rotation-Werte führen alle zu einer
		sauberen Ablehnung statt zu einem inkonsistenten Zustand. Der
		Rückgabewert jeder Funktion ist die einzige Quelle der Wahrheit, die
		PlacementServer.server.lua an den anfragenden Client zurücksendet.

	WICHTIGER DESIGN-PUNKT (siehe auch PlotRegistry.lua):
		HabitatPlacement.Position (bestehendes PlayerDataService-Schema)
		wird hier NICHT als absolute Weltposition gespeichert, sondern als
		LOKALER Offset relativ zum PrimaryPart des Plots (identisch zu
		Attachment.Position der jeweiligen BuildField-Attachment). Das ist
		nötig, weil PlotRegistry Spielern je nach freiem Welt-Slot bei
		jedem Join einen anderen Welt-Platz zuweisen kann - der lokale
		Offset bleibt dagegen für einen gegebenen Baufeld-Index über jeden
		Plot-Klon hinweg konstant. Keine Erweiterung von PlayerDataService
		nötig, da {X, Y, Z} bereits exakt dafür passt.

	Rojo-Einhängepunkt:
		src/server/PlacementService.lua -> ServerScriptService.PlacementService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local AssetTemplateSetup = require(script.Parent:WaitForChild("AssetTemplateSetup"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local ModelAnimationTags = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("ModelAnimationTags"))

type BuildField = PlotRegistry.BuildField

export type PlaceFailureReason =
	"DataNotLoaded"
	| "UnknownBuilding"
	| "InvalidField"
	| "NoPlot"
	| "LevelTooLow"
	| "FieldOccupied"
	| "TemplateMissing"
	| "InsufficientFunds"
	| "ChargeFailed"
	| "PersistenceFailed"
	| "BroodPoolLimitReached"

export type RemoveFailureReason = "DataNotLoaded" | "InvalidPlacement" | "NotFound" | "PersistenceRemoveFailed"

-- // Gebäude-Upgrade-System (Stufen 1->2->3, siehe docs/building-upgrades.md) --
export type UpgradeFailureReason =
	"DataNotLoaded"
	| "InvalidPlacement"
	| "NotFound"
	| "UnknownBuilding"
	| "MaxStageReached"
	| "LevelTooLow"
	| "IncubationActive"
	| "InsufficientFunds"
	| "ChargeFailed"
	| "PersistenceFailed"

export type PlaceResult = {
	Success: boolean,
	Reason: PlaceFailureReason?,
	Placement: PlayerDataService.HabitatPlacement?,
	FieldIndex: number?,
	NewBalance: number?,
}

export type RemoveResult = {
	Success: boolean,
	Reason: RemoveFailureReason?,
	PlacementId: string?,
	RefundAmount: number?,
	NewBalance: number?,
}

export type UpgradeResult = {
	Success: boolean,
	Reason: UpgradeFailureReason?,
	PlacementId: string?,
	NewStage: number?,
	NewBalance: number?, -- Tide Coins
	NewAbyssalShardBalance: number?, -- nur gesetzt, falls die Stufe Abyssal Shards gekostet hat (siehe BuildingConfig.BuildingUpgradeCost)
}

local PlacementService = {}

-- // Pro-Spieler-Laufzeitzustand (NICHT persistent - Spiegel des bereits
-- persistenten HabitatLayouts, nur für schnelle Belegungs-/Modell-Lookups) --

type PlacementMeta = {
	BuildingId: string,
	FieldIndex: number, -- -1, falls beim Restore keinem Feld zugeordnet werden konnte (siehe findNearestField)
	Model: Model,
}

local placementsByUser: { [number]: { [string]: PlacementMeta } } = {}
local occupiedFieldByUser: { [number]: { [number]: string } } = {}

-- // Hilfsfunktionen ------------------------------------------------------

--- Normalisiert einen beliebigen (unvertrauten) Rotation-Wert auf die
--- nächste 90°-Stufe, geklemmt auf [0, 360). Der Server bestimmt die
--- tatsächlich verwendete Rotation IMMER selbst - der Client-Wert ist nur
--- ein grober Vorschlag.
local function normalizeRotation(rotationY: any): number
	local raw = tonumber(rotationY) or 0
	local snapped = math.floor((raw / 90) + 0.5) * 90
	snapped = snapped % 360
	return snapped
end

local FIELD_MATCH_TOLERANCE = 2 -- Studs, toleriert Fließkomma-/DataStore-JSON-Rundungsfehler

--- Sucht unter `fields` das Baufeld, dessen lokale Attachment-Position am
--- nächsten an `localPosition` liegt (innerhalb FIELD_MATCH_TOLERANCE).
--- Wird nur beim Join-Restore gebraucht, da HabitatPlacement selbst keinen
--- Feld-Index speichert (siehe Design-Punkt oben) - der lokale Offset
--- allein reicht aber, um ihn zuverlässig zurückzugewinnen.
local function findNearestField(fields: { BuildField }, localPosition: Vector3): BuildField?
	local best: BuildField? = nil
	local bestDist = math.huge
	for _, field in ipairs(fields) do
		local dist = (field.Attachment.Position - localPosition).Magnitude
		if dist < bestDist then
			best = field
			bestDist = dist
		end
	end
	if best and bestDist <= FIELD_MATCH_TOLERANCE then
		return best
	end
	return nil
end

local function tagModel(model: Model, placementId: string, buildingId: string, fieldIndex: number, level: number?)
	model:SetAttribute("PlacementId", placementId)
	model:SetAttribute("BuildingId", buildingId)
	model:SetAttribute("FieldIndex", fieldIndex)
	-- "Level" ergänzt für das Zucht-/Ei-System (BreedingUIController liest
	-- dies, um clientseitig ohne Extra-Roundtrip die richtige
	-- BreedingConfig-Stufe anzuzeigen, z. B. Fütterungskosten VOR dem
	-- Start) UND für das Gebäude-Upgrade-System (siehe
	-- docs/building-upgrades.md) - applyStageToModel aktualisiert diesen
	-- Wert bei jedem erfolgreichen Upgrade mit. Default 1, siehe
	-- PlayerDataService.AddHabitatPlacement.
	model:SetAttribute("Level", level or 1)
end

--- Seamless-Animation-System (docs/animation-system.md): idempotentes Tag +
--- Zeitstempel für den Client-Renderer (ModelAnimator.client.lua) - bewusst
--- NICHT Teil von `tagModel` selbst, da `tagModel` auch beim reinen
--- Layout-Restore beim Join läuft (RestorePlayerLayout), wo KEINE Pop-in-/
--- Flash-Animation gewünscht ist (die Gebäude sollen beim Join einfach
--- "schon da" sein, nicht jedes Mal neu einpoppen). Nur an den drei
--- tatsächlichen Ereignissen aufgerufen: frische Platzierung (RequestPlace),
--- Modell-Tausch beim Upgrade UND Fail-Soft-Akzent-Update beim Upgrade
--- (beide in applyStageToModel) - der Client unterscheidet "brandneue
--- Modell-Instanz" (Pop-in) von "bereits bekannte Instanz, Attribut ändert
--- sich erneut" (kurzer Flash) selbst.
local function markPlacementFx(model: Model)
	CollectionService:AddTag(model, ModelAnimationTags.BUILDING_PLACED)
	model:SetAttribute(ModelAnimationTags.ATTR_PLACED_AT, Workspace:GetServerTimeNow())
end

-- // Gebäude-Upgrade-System: Modell-Wechsel bzw. Fail-Soft-Akzent -----------
-- (siehe docs/building-upgrades.md + AssetTemplateSetup.GetBuildingStageTemplate-
-- Kopfkommentar zur Fail-Soft-Design-Entscheidung).

local STAGE_ACCENT_COLOR: { [number]: Color3 } = {
	-- Farben identisch zu UIKit.Theme.Neon.Cyan/Violet (siehe docs/ui-kit.md) -
	-- bewusst als eigene Color3-Konstanten geführt statt UIKit.Theme zu
	-- requiren, damit dieses rein serverseitige Modul unabhängig vom
	-- (eigentlich client-orientierten) UIKit-Paket bleibt.
	[2] = Color3.fromRGB(0, 245, 255),
	[3] = Color3.fromRGB(160, 70, 255),
}
local STAGE_ACCENT_THICKNESS: { [number]: number } = {
	[2] = 0.35,
	[3] = 0.55,
}
local STAGE_ACCENT_NAME = "StageAccentRing"

--- Fail-Soft-Ersatz für ein (noch) fehlendes Stufe-2/3-Modell: ein
--- schwebender Neon-Ring + Punktlicht um den aktuellen Modell-Pivot, Farbe/
--- Helligkeit je Stufe gestaffelt (Stufe 3 auffälliger als Stufe 2). Rein
--- kosmetisch, KEIN Gameplay-Effekt. Ersetzt einen bereits vorhandenen Ring
--- (erneutes Upgrade Stufe 2 -> 3 am selben, weiterhin fehlenden Modell).
local function applyStageAccent(model: Model, stage: number)
	local color = STAGE_ACCENT_COLOR[stage]
	if not color then
		return
	end

	local existing = model:FindFirstChild(STAGE_ACCENT_NAME)
	if existing then
		existing:Destroy()
	end

	local pivot = model:GetPivot()
	local ring = Instance.new("Part")
	ring.Name = STAGE_ACCENT_NAME
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.new(STAGE_ACCENT_THICKNESS[stage] or 0.35, 6, 6)
	ring.CFrame = pivot * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = stage >= 3 and 3.5 or 2.2
	light.Parent = ring
end

--- Entfernt einen ggf. vorhandenen Fail-Soft-Akzent (z. B. weil ein
--- inzwischen doch vorhandenes echtes Stufe-Modell verwendet wird - dessen
--- eigener Look soll nicht zusätzlich vom Platzhalter-Ring überlagert
--- werden).
local function clearStageAccent(model: Model)
	local existing = model:FindFirstChild(STAGE_ACCENT_NAME)
	if existing then
		existing:Destroy()
	end
end

--- Wendet eine Ausbaustufe auf ein BEREITS im Workspace stehendes
--- Platzierungs-Modell an: tauscht das Modell gegen die passende Stufe-2/3-
--- Vorlage (falls vorhanden, siehe AssetTemplateSetup.GetBuildingStageTemplate),
--- oder ergänzt andernfalls nur den Fail-Soft-Akzent auf dem UNVERÄNDERTEN
--- Stufe-1-Modell. Position/Rotation/PlacementId/FieldIndex bleiben in
--- jedem Fall erhalten (Pivot des alten Modells wird 1:1 auf das neue
--- übertragen). Mutiert `meta.Model` bei einem tatsächlichen Modell-Wechsel.
local function applyStageToModel(
	placementId: string,
	meta: PlacementMeta,
	definition: BuildingConfig.BuildingDefinition,
	targetStage: number
)
	local oldModel = meta.Model
	if not oldModel or not oldModel.Parent then
		return
	end

	local stageTemplate = AssetTemplateSetup.GetBuildingStageTemplate(meta.BuildingId, targetStage)
	if stageTemplate then
		local pivot = oldModel:GetPivot()
		local parent = oldModel.Parent
		local modelName = oldModel.Name
		oldModel:Destroy()

		local newModel = stageTemplate:Clone()
		newModel.Name = modelName
		newModel.Parent = parent
		newModel:PivotTo(pivot)
		tagModel(newModel, placementId, meta.BuildingId, meta.FieldIndex, targetStage)
		markPlacementFx(newModel)

		meta.Model = newModel
		return
	end

	-- Kein echtes Stufe-Modell (noch) vorhanden - Stufe-1-Modell behalten,
	-- nur Attribute + Fail-Soft-Akzent aktualisieren (siehe Kopfkommentar).
	tagModel(oldModel, placementId, meta.BuildingId, meta.FieldIndex, targetStage)
	applyStageAccent(oldModel, targetStage)
	markPlacementFx(oldModel)
end

-- // Öffentliche API ------------------------------------------------------

--- Validiert und führt eine Platzierungsanfrage vollständig serverseitig
--- aus. `buildingId`, `fieldIndex`, `rotationY` sind unvertraute,
--- angebliche Client-Werte - keiner davon wird ungeprüft übernommen.
function PlacementService.RequestPlace(player: Player, buildingId: any, fieldIndex: any, rotationY: any): PlaceResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if type(buildingId) ~= "string" then
		return { Success = false, Reason = "UnknownBuilding" }
	end
	local definition = BuildingConfig.Get(buildingId)
	if not definition then
		return { Success = false, Reason = "UnknownBuilding" }
	end

	if type(fieldIndex) ~= "number" or fieldIndex ~= math.floor(fieldIndex) then
		return { Success = false, Reason = "InvalidField" }
	end

	local playerLevel = PlayerDataService.GetLevel(player)
	if playerLevel < definition.UnlockLevel then
		return { Success = false, Reason = "LevelTooLow" }
	end

	-- Zweiter Brutbecken-Slot ab Level 6 (GDD Abschnitt 6): BuildingConfig
	-- kennt nur EIN generelles UnlockLevel pro Gebäudetyp (hier: Level 1 für
	-- BroodPool, siehe BuildingConfig-Kopfkommentar), keine "Slot-Anzahl pro
	-- Level"-Regel. Diese zusätzliche Zählung ist daher die einzige
	-- Durchsetzungsstelle für die Slot-Grenze (siehe ProgressionConfig.
	-- GetMaxBroodPools) - erfordert keine Änderung an BuildingConfig selbst,
	-- da alle anderen MVP-Gebäudetypen unlimitiert bleiben.
	if buildingId == "BroodPool" then
		local existingBroodPools = 0
		for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
			if placement.BuildingId == "BroodPool" then
				existingBroodPools += 1
			end
		end
		if existingBroodPools >= ProgressionConfig.GetMaxBroodPools(playerLevel) then
			return { Success = false, Reason = "BroodPoolLimitReached" }
		end
	end

	local field = PlotRegistry.GetBuildField(player, fieldIndex)
	if not field then
		return { Success = false, Reason = "InvalidField" }
	end

	local buildingsFolder = PlotRegistry.GetBuildingsFolder(player)
	if not buildingsFolder then
		return { Success = false, Reason = "NoPlot" }
	end

	local userId = player.UserId
	local occupied = occupiedFieldByUser[userId]
	if occupied and occupied[fieldIndex] then
		return { Success = false, Reason = "FieldOccupied" }
	end

	-- Vorlage-Existenz VOR dem Kassieren prüfen, damit im Fehlerfall kein
	-- Rollback des Kontostands nötig ist.
	local template = AssetTemplateSetup.GetBuildingTemplate(definition.TemplateName)
	if not template then
		return { Success = false, Reason = "TemplateMissing" }
	end

	local balance = PlayerDataService.GetCurrency(player, "TideCoins")
	if balance < definition.Cost then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	local snappedRotation = normalizeRotation(rotationY)

	-- Guard gegen negativen Kontostand: AddCurrency klemmt intern zwar auf
	-- minimal 0, lehnt eine zu große Abbuchung aber NICHT selbst ab -
	-- deshalb der explizite balance >= Cost-Check oben, BEVOR wir abziehen.
	local chargeOk, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", -definition.Cost)
	if not chargeOk then
		return { Success = false, Reason = "ChargeFailed" }
	end

	local localPosition = field.Attachment.Position
	local placement = PlayerDataService.AddHabitatPlacement(player, {
		BuildingId = buildingId,
		Position = { X = localPosition.X, Y = localPosition.Y, Z = localPosition.Z },
		RotationY = snappedRotation,
	})

	if not placement then
		-- Persistenz fehlgeschlagen (z. B. Daten zwischen Prüfung und
		-- Schreiben entladen) - bereits abgezogene Kosten zurückerstatten.
		PlayerDataService.AddCurrency(player, "TideCoins", definition.Cost)
		return { Success = false, Reason = "PersistenceFailed" }
	end

	local model = template:Clone()
	model.Name = "Building_" .. placement.PlacementId
	tagModel(model, placement.PlacementId, buildingId, field.Index, placement.Level)
	markPlacementFx(model)
	model.Parent = buildingsFolder
	model:PivotTo(field.Attachment.WorldCFrame * CFrame.Angles(0, math.rad(snappedRotation), 0))

	occupiedFieldByUser[userId] = occupiedFieldByUser[userId] or {}
	occupiedFieldByUser[userId][fieldIndex] = placement.PlacementId

	placementsByUser[userId] = placementsByUser[userId] or {}
	placementsByUser[userId][placement.PlacementId] = {
		BuildingId = buildingId,
		FieldIndex = fieldIndex,
		Model = model,
	}

	-- Progression-Einhängepunkt: NACH erfolgreichem Abschluss (nicht beim
	-- Request), siehe ProgressionService-Kopfkommentar.
	ProgressionService.AwardXP(player, "BuildingPlaced")

	-- GameEvents-Einhängepunkt (Auftrag Punkt 1): QuestService/
	-- LeaderboardService hören hierauf, kennen PlacementService selbst
	-- NICHT - siehe GameEvents-Kopfkommentar.
	GameEvents.Fire(GameEvents.Events.BuildingPlaced, player, {
		BuildingId = buildingId,
		PlacementId = placement.PlacementId,
	})

	return {
		Success = true,
		Placement = placement,
		FieldIndex = fieldIndex,
		NewBalance = newBalance,
	}
end

--- Validiert und führt eine Entfernungs-/Verkaufsanfrage vollständig
--- serverseitig aus. Gibt einen Teil-Refund (BuildingConfig.
--- SellRefundFraction) auf die Tide Coins gut. `placementId` wird
--- ausschließlich gegen den EIGENEN Pro-Spieler-Zustand des anfragenden
--- Spielers geprüft - fremde PlacementIds können hier grundsätzlich nichts
--- entfernen.
function PlacementService.RequestRemove(player: Player, placementId: any): RemoveResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if type(placementId) ~= "string" then
		return { Success = false, Reason = "InvalidPlacement" }
	end

	local userId = player.UserId
	local userPlacements = placementsByUser[userId]
	local meta = userPlacements and userPlacements[placementId]
	if not meta then
		return { Success = false, Reason = "NotFound" }
	end

	local removed = PlayerDataService.RemoveHabitatPlacement(player, placementId)
	if not removed then
		return { Success = false, Reason = "PersistenceRemoveFailed" }
	end

	-- Ein verkauftes BroodPool kann eine laufende/fertige Zucht-Inkubation
	-- (Zucht-/Ei-System, GDD Abschnitt 9 Punkt 4) hinterlassen haben - ohne
	-- Aufräumen bliebe der Datensatz verwaist (referenziert eine nicht mehr
	-- existierende PlacementId) liegen. Kein zusätzlicher Refund der
	-- Fütterungskosten hier, analog dazu, dass ein Verkauf generell nur den
	-- SellRefundFraction-Anteil der Baukosten erstattet.
	PlayerDataService.RemoveIncubation(player, placementId)

	-- Seamless-Animation-System (docs/animation-system.md): Refund wird
	-- unten wie gewohnt sofort berechnet/gutgeschrieben - nur das
	-- tatsächliche `:Destroy()` verzögert sich, damit der Client
	-- (ModelAnimator.client.lua) das Gebäude sichtbar schrumpfen lassen kann
	-- statt es instant verschwinden zu lassen (identisches Karenzzeit-
	-- Prinzip wie RaidService.scheduleDeathDestroy).
	if meta.Model and meta.Model.Parent then
		local soldModel = meta.Model
		CollectionService:AddTag(soldModel, ModelAnimationTags.BUILDING_PLACED)
		soldModel:SetAttribute(ModelAnimationTags.ATTR_SOLD_AT, Workspace:GetServerTimeNow())
		task.delay(BuildingConfig.SELL_FX_SECONDS, function()
			if soldModel.Parent then
				soldModel:Destroy()
			end
		end)
	end

	userPlacements[placementId] = nil
	local occupied = occupiedFieldByUser[userId]
	if occupied and meta.FieldIndex >= 0 then
		occupied[meta.FieldIndex] = nil
	end

	local definition = BuildingConfig.Get(meta.BuildingId)

	-- Rückerstattung berücksichtigt bereits investierte Upgrade-Kosten
	-- (Auftrag Gebäude-Upgrade-System, siehe docs/building-upgrades.md) -
	-- NICHT nur den ursprünglichen Bau-Cost. `stage` wird vom bereits vor
	-- der Entfernung ausgelesenen Modell-Attribut übernommen (siehe
	-- tagModel/applyStageToModel - "Level" ist dort IMMER synchron zur
	-- persistenten HabitatPlacement.Level), ein zusätzlicher
	-- GetHabitatLayout-Scan ist dafür nicht nötig.
	local stage = (meta.Model and meta.Model:GetAttribute("Level")) or 1
	if type(stage) ~= "number" then
		stage = 1
	end

	local investedTideCoins = 0
	local investedAbyssalShards = 0
	if definition then
		investedTideCoins = definition.Cost
		for targetStage = 2, math.min(stage, definition.MaxStage) do
			local upgradeCost = definition.UpgradeCosts[targetStage]
			if upgradeCost then
				investedTideCoins += upgradeCost.TideCoins
				investedAbyssalShards += upgradeCost.AbyssalShards or 0
			end
		end
	end

	local sellFraction = definition and definition.SellRefundFraction or 0
	local refund = math.floor(investedTideCoins * sellFraction)
	local shardRefund = math.floor(investedAbyssalShards * sellFraction)

	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", refund)
	if shardRefund > 0 then
		PlayerDataService.AddCurrency(player, "AbyssalShards", shardRefund)
	end

	return {
		Success = true,
		PlacementId = placementId,
		RefundAmount = refund,
		NewBalance = newBalance,
	}
end

--- Validiert und führt eine Ausbaustufen-Anfrage (Stufe -> Stufe+1, max.
--- BuildingConfig.BuildingDefinition.MaxStage) vollständig serverseitig aus.
--- `placementId` ist ein unvertrauter, angeblicher Client-Wert - wird
--- ausschließlich gegen den eigenen Pro-Spieler-Laufzeitzustand (Beweis für
--- Eigentümerschaft, identisches Prinzip zu RequestRemove) UND das eigene,
--- bereits persistente HabitatLayout (autoritative aktuelle Stufe) geprüft,
--- bevor irgendetwas verändert wird.
---
--- DESIGN-ENTSCHEIDUNG "kein Upgrade während laufender Inkubation" (Auftrag
--- Punkt 2 - explizit zu entscheiden/dokumentieren, siehe auch
--- docs/building-upgrades.md): Ein BroodPool mit aktiver Inkubation
--- (PlayerDataService.GetIncubationForPlacement) kann NICHT hochgestuft
--- werden. Grund: Das Zucht-ERGEBNIS wurde beim Start bereits mit der
--- ALTEN Stufe gewürfelt (siehe BreedingService.RequestStartBreeding
--- Kopfkommentar "Roll beim Start statt beim Abholen") und liegt bereits
--- fest in PlayerDataService.BreedingIncubation - ein Upgrade MITTEN in der
--- Inkubation würde dem Spieler keinerlei rückwirkenden Vorteil für die
--- bereits laufende Zucht bringen, könnte aber den Eindruck erwecken
--- ("ich habe gerade auf Meisterstufe hochgestuft, wieso ist mein Ergebnis
--- nicht besser?"). Ein simples, klares "erst abholen, dann upgraden"
--- vermeidet dieses Missverständnis vollständig, ohne die Inkubation selbst
--- anzufassen (kein Datenverlust, keine Sonderfall-Rechnung nötig).
function PlacementService.RequestUpgrade(player: Player, placementId: any): UpgradeResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if type(placementId) ~= "string" then
		return { Success = false, Reason = "InvalidPlacement" }
	end

	local userId = player.UserId
	local userPlacements = placementsByUser[userId]
	local meta = userPlacements and userPlacements[placementId]
	if not meta then
		return { Success = false, Reason = "NotFound" }
	end

	local definition = BuildingConfig.Get(meta.BuildingId)
	if not definition then
		return { Success = false, Reason = "UnknownBuilding" }
	end

	-- Aktuelle Stufe AUTORITATIV aus dem persistenten HabitatLayout lesen
	-- (nicht aus dem Modell-Attribut, das nur ein Spiegel davon ist) - der
	-- Lookup bestätigt zugleich, dass `placementId` wirklich (noch) im
	-- eigenen Layout existiert.
	local currentStage: number? = nil
	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		if placement.PlacementId == placementId then
			currentStage = placement.Level
			break
		end
	end
	if not currentStage then
		return { Success = false, Reason = "NotFound" }
	end

	if currentStage >= definition.MaxStage then
		return { Success = false, Reason = "MaxStageReached" }
	end

	local targetStage = currentStage + 1
	local upgradeCost = definition.UpgradeCosts[targetStage]
	if not upgradeCost then
		return { Success = false, Reason = "MaxStageReached" }
	end

	local playerLevel = PlayerDataService.GetLevel(player)
	if playerLevel < upgradeCost.LevelRequirement then
		return { Success = false, Reason = "LevelTooLow" }
	end

	if meta.BuildingId == "BroodPool" and PlayerDataService.GetIncubationForPlacement(player, placementId) then
		return { Success = false, Reason = "IncubationActive" }
	end

	local balance = PlayerDataService.GetCurrency(player, "TideCoins")
	if balance < upgradeCost.TideCoins then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	local shardCost = upgradeCost.AbyssalShards or 0
	if shardCost > 0 then
		local shardBalance = PlayerDataService.GetCurrency(player, "AbyssalShards")
		if shardBalance < shardCost then
			return { Success = false, Reason = "InsufficientFunds" }
		end
	end

	local chargeOk, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", -upgradeCost.TideCoins)
	if not chargeOk then
		return { Success = false, Reason = "ChargeFailed" }
	end

	local newShardBalance: number? = nil
	if shardCost > 0 then
		local shardOk, shardBalanceAfter = PlayerDataService.AddCurrency(player, "AbyssalShards", -shardCost)
		if not shardOk then
			-- Rollback der bereits abgezogenen Tide Coins, siehe identisches
			-- Muster in RequestPlace/BreedingService.RequestStartBreeding.
			PlayerDataService.AddCurrency(player, "TideCoins", upgradeCost.TideCoins)
			return { Success = false, Reason = "ChargeFailed" }
		end
		newShardBalance = shardBalanceAfter
	end

	local persisted = PlayerDataService.SetHabitatPlacementLevel(player, placementId, targetStage)
	if not persisted then
		-- Persistenz fehlgeschlagen (z. B. Daten zwischen Prüfung und
		-- Schreiben entladen) - bereits abgezogene Kosten zurückerstatten.
		PlayerDataService.AddCurrency(player, "TideCoins", upgradeCost.TideCoins)
		if shardCost > 0 then
			PlayerDataService.AddCurrency(player, "AbyssalShards", shardCost)
		end
		return { Success = false, Reason = "PersistenceFailed" }
	end

	applyStageToModel(placementId, meta, definition, targetStage)

	-- GameEvents-Einhängepunkt (Auftrag Punkt 5): Achievements/Quests hören
	-- hierüber, kennen PlacementService selbst NICHT - siehe
	-- GameEvents-Kopfkommentar.
	GameEvents.Fire(GameEvents.Events.BuildingUpgraded, player, {
		BuildingId = meta.BuildingId,
		PlacementId = placementId,
		NewStage = targetStage,
	})

	return {
		Success = true,
		PlacementId = placementId,
		NewStage = targetStage,
		NewBalance = newBalance,
		NewAbyssalShardBalance = newShardBalance,
	}
end

--- Rekonstruiert das gespeicherte Habitat-Layout eines Spielers im
--- Workspace. Wird von PlacementServer.server.lua NACH erfolgreichem
--- PlotRegistry.AssignPlot UND PlayerDataService.WaitForData aufgerufen
--- (siehe dort) - setzt also voraus, dass beides bereits vorliegt.
function PlacementService.RestorePlayerLayout(player: Player)
	local userId = player.UserId
	placementsByUser[userId] = {}
	occupiedFieldByUser[userId] = {}

	local buildingsFolder = PlotRegistry.GetBuildingsFolder(player)
	local plot = PlotRegistry.GetPlot(player)
	if not buildingsFolder or not plot or not plot.PrimaryPart then
		warn(("[PlacementService] No plot for %s - layout restoration skipped."):format(player.Name))
		return
	end

	local fields = PlotRegistry.GetBuildFields(player)
	local primaryCFrame = plot.PrimaryPart.CFrame

	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		local definition = BuildingConfig.Get(placement.BuildingId)
		if not definition then
			warn(
				("[PlacementService] Unknown BuildingId '%s' in the layout of %s skipped."):format(
					tostring(placement.BuildingId),
					player.Name
				)
			)
			continue
		end

		-- Gebäude-Upgrade-System (siehe docs/building-upgrades.md): bei
		-- Stufe > 1 zuerst die echte Stufe-Vorlage versuchen, sonst auf das
		-- Stufe-1-Modell zurückfallen + Fail-Soft-Akzent ergänzen (siehe
		-- applyStageAccent) - identisches Verhalten wie beim Upgrade selbst
		-- (applyStageToModel), nur hier "von Grund auf" statt als Wechsel.
		local stage = placement.Level or 1
		local template: Model? = nil
		local usedStageTemplate = false
		if stage > 1 then
			template = AssetTemplateSetup.GetBuildingStageTemplate(placement.BuildingId, stage)
			usedStageTemplate = template ~= nil
		end
		if not template then
			template = AssetTemplateSetup.GetBuildingTemplate(definition.TemplateName)
		end
		if not template then
			warn(
				("[PlacementService] Template '%s' is missing - saved placement %s by %s skipped."):format(
					definition.TemplateName,
					placement.PlacementId,
					player.Name
				)
			)
			continue
		end

		local storedPos = Vector3.new(placement.Position.X, placement.Position.Y, placement.Position.Z)
		local matchedField = findNearestField(fields, storedPos)

		local model = template:Clone()
		model.Name = "Building_" .. placement.PlacementId
		model.Parent = buildingsFolder
		model:PivotTo(primaryCFrame * CFrame.new(storedPos) * CFrame.Angles(0, math.rad(placement.RotationY), 0))

		local resolvedFieldIndex = matchedField and matchedField.Index or -1
		tagModel(model, placement.PlacementId, placement.BuildingId, resolvedFieldIndex, placement.Level)

		if stage > 1 and not usedStageTemplate then
			applyStageAccent(model, stage)
		elseif stage <= 1 then
			-- Defensiv: ein evtl. übrig gebliebener Akzent-Rest aus einem
			-- geklonten Stufe-1-Template (sollte nie vorkommen, da Vorlagen
			-- selbst nie einen StageAccentRing enthalten) wird hier trotzdem
			-- konsequent entfernt.
			clearStageAccent(model)
		end

		if matchedField then
			occupiedFieldByUser[userId][matchedField.Index] = placement.PlacementId
		else
			warn(
				("[PlacementService] Placement %s by %s could not be matched to a build field (model still visible, field may incorrectly stay free for new purchases)."):format(
					placement.PlacementId,
					player.Name
				)
			)
		end

		placementsByUser[userId][placement.PlacementId] = {
			BuildingId = placement.BuildingId,
			FieldIndex = resolvedFieldIndex,
			Model = model,
		}
	end
end

--- Räumt den rein transienten Laufzeit-Zustand eines Spielers auf
--- (PlayerRemoving). Die Modell-Instanzen selbst werden von
--- PlotRegistry.ReleasePlot entfernt (zusammen mit dem gesamten Plot) -
--- hier geht es nur darum, keine toten Referenzen im Speicher zu behalten.
function PlacementService.CleanupPlayer(player: Player)
	local userId = player.UserId
	placementsByUser[userId] = nil
	occupiedFieldByUser[userId] = nil
end

return PlacementService
