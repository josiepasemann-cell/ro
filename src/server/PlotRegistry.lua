--[[
	Abyssara – Deep Tide Tycoon
	Modul: PlotRegistry
	Zuständigkeit:
		Weist jedem verbundenen Spieler eine eigene, im Workspace platzierte
		Kopie der Habitat-Plot-Basis zu (Vorlage bereitgestellt durch
		AssetTemplateSetup, siehe dort) und verwaltet deren Lebenszyklus
		(Zuweisung bei Join, Freigabe bei Verlassen/Disconnect).

		Liest ausschließlich das in HabitatPlotBase.lua bereits angelegte
		Baufelder-Raster aus (6 Attachments "BuildField1".."BuildField6" am
		PrimaryPart "PlatformBase", Attribut "GridFieldCount") - erfindet
		KEIN eigenes, paralleles Grid-System.

	WICHTIGER DESIGN-PUNKT (lokale statt absolute Positionen):
		Jeder Spieler kann je nach freiem Welt-Slot bei JEDEM Join an einer
		anderen Weltposition landen (siehe `slotOrigin` unten - Slots
		werden bei Disconnect freigegeben und beim nächsten Join evtl.
		anders vergeben). Ein in HabitatLayout gespeicherter absoluter
		Welt-Punkt wäre daher nach einem Server-Neustart/Rejoin oft falsch.

		Deshalb liefert dieses Modul für Baufelder bewusst
		`Attachment.Position` (in Roblox bereits relativ zum Parent, hier
		also relativ zum PrimaryPart "PlatformBase" des jeweiligen Plots)
		statt einer Welt-CFrame. PlacementService speichert bei
		HabitatPlacement.Position genau diesen LOKALEN Offset - der ist für
		einen gegebenen Baufeld-Index über alle Plot-Klone hinweg IMMER
		identisch, unabhängig vom aktuell zugewiesenen Welt-Slot. Siehe
		PlacementService.lua für die Rekonstruktion beim Join.

	Rojo-Einhängepunkt:
		src/server/PlotRegistry.lua -> ServerScriptService.PlotRegistry
]]

local Workspace = game:GetService("Workspace")

local AssetTemplateSetup = require(script.Parent:WaitForChild("AssetTemplateSetup"))

export type BuildField = {
	Index: number,
	Attachment: Attachment,
}

local PlotRegistry = {}

-- // Konfiguration -------------------------------------------------------
local SLOT_SPACING = 200 -- Studs zwischen Plot-Ursprüngen (Plot ~60 Studs flat-to-flat + Gebäude-Überstand + Sicherheitsabstand)
local SLOTS_PER_ROW = 10
local PLOT_Y = 0
-- // ----------------------------------------------------------------------

local plotsFolder: Folder = (function()
	local folder = Workspace:FindFirstChild("PlayerPlots")
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = "PlayerPlots"
		folder.Parent = Workspace
	end
	return folder :: Folder
end)()

local nextFreeSlot = 1
local freeSlots: { number } = {} -- wiederverwendete, freigegebene Slot-Indizes (LIFO)

local slotByUserId: { [number]: number } = {}
local plotByUserId: { [number]: Model } = {}

local function slotOrigin(slotIndex: number): CFrame
	local col = (slotIndex - 1) % SLOTS_PER_ROW
	local row = math.floor((slotIndex - 1) / SLOTS_PER_ROW)
	return CFrame.new(col * SLOT_SPACING, PLOT_Y, row * SLOT_SPACING)
end

local function claimSlot(): number
	local slot = table.remove(freeSlots)
	if slot then
		return slot
	end
	slot = nextFreeSlot
	nextFreeSlot += 1
	return slot
end

--- Weist `player` eine eigene Plot-Kopie zu (idempotent - ein Spieler, der
--- bereits einen aktiven Plot hat, bekommt denselben zurück statt eines
--- zweiten). Gibt nil zurück, falls die Plot-Vorlage fehlt (Buildscript nie
--- in Studio ausgeführt, siehe AssetTemplateSetup-Warnung).
function PlotRegistry.AssignPlot(player: Player): Model?
	local userId = player.UserId

	local existing = plotByUserId[userId]
	if existing and existing.Parent then
		return existing
	end

	local template = AssetTemplateSetup.GetPlotTemplate()
	if not template then
		warn(("[PlotRegistry] Kann %s keinen Plot zuweisen - HabitatPlotBase-Vorlage fehlt."):format(player.Name))
		return nil
	end

	local slot = claimSlot()
	slotByUserId[userId] = slot

	local plot = template:Clone()
	plot.Name = tostring(userId)
	plot:SetAttribute("OwnerUserId", userId)
	plot:SetAttribute("OwnerName", player.Name)

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = plot

	plot.Parent = plotsFolder
	plot:PivotTo(slotOrigin(slot))

	plotByUserId[userId] = plot
	return plot
end

--- Entfernt die Plot-Instanz eines Spielers wieder aus dem Workspace
--- (inkl. aller darauf platzierten Gebäude-Modelle) und gibt den Welt-Slot
--- für den nächsten Spieler frei. Die Persistenz der Platzierungen selbst
--- läuft unabhängig davon bereits über PlayerDataService/HabitatLayout -
--- hier wird nur die Laufzeit-Repräsentation im Workspace aufgeräumt.
function PlotRegistry.ReleasePlot(player: Player)
	local userId = player.UserId

	local plot = plotByUserId[userId]
	if plot then
		plot:Destroy()
	end
	plotByUserId[userId] = nil

	local slot = slotByUserId[userId]
	if slot then
		table.insert(freeSlots, slot)
	end
	slotByUserId[userId] = nil
end

--- Liefert die aktive Plot-Instanz eines Spielers, oder nil.
function PlotRegistry.GetPlot(player: Player): Model?
	local plot = plotByUserId[player.UserId]
	if plot and plot.Parent then
		return plot
	end
	return nil
end

--- Liefert alle Baufelder eines Spieler-Plots (Index 1..GridFieldCount)
--- mitsamt ihrem Attachment (für lokale/Welt-CFrame-Berechnung).
function PlotRegistry.GetBuildFields(player: Player): { BuildField }
	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		return {}
	end

	local fieldCount = plot:GetAttribute("GridFieldCount")
	if type(fieldCount) ~= "number" then
		fieldCount = 6 -- Fallback, falls Attribut fehlt (siehe HabitatPlotBase.lua)
	end

	local fields: { BuildField } = {}
	for i = 1, fieldCount do
		local attachment = plot.PrimaryPart:FindFirstChild("BuildField" .. i)
		if attachment and attachment:IsA("Attachment") then
			table.insert(fields, { Index = i, Attachment = attachment })
		end
	end
	return fields
end

--- Liefert das Baufeld mit gegebenem Index für den Plot von `player`, oder
--- nil, falls kein Plot zugewiesen ist oder der Index ungültig ist.
function PlotRegistry.GetBuildField(player: Player, fieldIndex: number): BuildField?
	for _, field in ipairs(PlotRegistry.GetBuildFields(player)) do
		if field.Index == fieldIndex then
			return field
		end
	end
	return nil
end

--- Liefert den "Buildings"-Unterordner eines Spieler-Plots, in dem
--- PlacementService platzierte Gebäude-Instanzen ablegt (oder nil, falls
--- kein Plot zugewiesen ist).
function PlotRegistry.GetBuildingsFolder(player: Player): Folder?
	local plot = PlotRegistry.GetPlot(player)
	if not plot then
		return nil
	end
	local folder = plot:FindFirstChild("Buildings")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

return PlotRegistry
