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

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local AssetTemplateSetup = require(script.Parent:WaitForChild("AssetTemplateSetup"))
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))

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

export type RemoveFailureReason = "DataNotLoaded" | "InvalidPlacement" | "NotFound" | "PersistenceRemoveFailed"

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

local function tagModel(model: Model, placementId: string, buildingId: string, fieldIndex: number)
	model:SetAttribute("PlacementId", placementId)
	model:SetAttribute("BuildingId", buildingId)
	model:SetAttribute("FieldIndex", fieldIndex)
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
	tagModel(model, placement.PlacementId, buildingId, field.Index)
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

	if meta.Model and meta.Model.Parent then
		meta.Model:Destroy()
	end

	userPlacements[placementId] = nil
	local occupied = occupiedFieldByUser[userId]
	if occupied and meta.FieldIndex >= 0 then
		occupied[meta.FieldIndex] = nil
	end

	local definition = BuildingConfig.Get(meta.BuildingId)
	local refund = definition and math.floor(definition.Cost * definition.SellRefundFraction) or 0
	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", refund)

	return {
		Success = true,
		PlacementId = placementId,
		RefundAmount = refund,
		NewBalance = newBalance,
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
		warn(("[PlacementService] Kein Plot für %s - Layout-Wiederherstellung übersprungen."):format(player.Name))
		return
	end

	local fields = PlotRegistry.GetBuildFields(player)
	local primaryCFrame = plot.PrimaryPart.CFrame

	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		local definition = BuildingConfig.Get(placement.BuildingId)
		if not definition then
			warn(
				("[PlacementService] Unbekannte BuildingId '%s' im Layout von %s übersprungen."):format(
					tostring(placement.BuildingId),
					player.Name
				)
			)
			continue
		end

		local template = AssetTemplateSetup.GetBuildingTemplate(definition.TemplateName)
		if not template then
			warn(
				("[PlacementService] Vorlage '%s' fehlt - gespeicherte Platzierung %s von %s übersprungen."):format(
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
		tagModel(model, placement.PlacementId, placement.BuildingId, resolvedFieldIndex)

		if matchedField then
			occupiedFieldByUser[userId][matchedField.Index] = placement.PlacementId
		else
			warn(
				("[PlacementService] Platzierung %s von %s keinem Baufeld zuordenbar (Modell trotzdem sichtbar, Feld bleibt für neue Käufe ggf. fälschlich frei)."):format(
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
