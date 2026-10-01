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

	MEHRERE PLOTS (Extra Habitat Plot gamepass, ShopConfig key "ExtraPlot"):
		Jeder Spieler belegt EIN Slot-PAAR im Raster: Spalte 2k = Plot 1,
		Spalte 2k+1 = Plot 2 direkt daneben (gleiche Reihe). Plot 2 wird nur
		auf Anfrage erzeugt (AssignPlot(player, 2), aufgerufen von
		PlacementServer fuer Gamepass-Besitzer) - PlotRegistry selbst prueft
		KEINEN Gamepass-Besitz. Alle Getter nehmen ein optionales
		`plotIndex` (nil = 1), dadurch laufen alle bestehenden Aufrufer
		unveraendert auf Plot 1. Plot 1 heisst weiterhin "<UserId>" (der
		Client sucht ihn so), Plot 2 heisst "<UserId>_2". Das Player-Attribut
		"PlotCount" (1 oder 2) spiegelt die aktuell zugewiesenen Plots fuer
		die Client-UI.

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
local MAX_PLOTS_PER_PLAYER = 2 -- Plot 1 + Extra Habitat Plot
local COLUMNS_PER_ROW = 10 -- Raster-Spalten; jeder Spieler belegt MAX_PLOTS_PER_PLAYER nebeneinanderliegende Spalten
local SLOTS_PER_ROW = COLUMNS_PER_ROW // MAX_PLOTS_PER_PLAYER
local PLOT_Y = 0
-- Plot-Raster bewusst weit weg vom Zonen-Chunk-Cluster (Radius ~170 um 0,0,0)
-- und vom Hub (-500,0,-500): sonst wuerde Plot #1 mitten in den vier Zonen
-- stehen (Terrain-Ueberlappung, Spieler koennten fremde Plots/Zonen sehen).
local GRID_ORIGIN_X = 1000
local GRID_ORIGIN_Z = 1000
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
local plotsByUserId: { [number]: { [number]: Model } } = {} -- [userId][plotIndex]

PlotRegistry.MAX_PLOTS = MAX_PLOTS_PER_PLAYER

--- Plot-Ursprung: Spieler-Slot -> Spaltenpaar, plotIndex 2 liegt direkt
--- rechts (+X) neben Plot 1.
local function slotOrigin(slotIndex: number, plotIndex: number): CFrame
	local col = ((slotIndex - 1) % SLOTS_PER_ROW) * MAX_PLOTS_PER_PLAYER + (plotIndex - 1)
	local row = math.floor((slotIndex - 1) / SLOTS_PER_ROW)
	return CFrame.new(GRID_ORIGIN_X + col * SLOT_SPACING, PLOT_Y, GRID_ORIGIN_Z + row * SLOT_SPACING)
end

--- Normalisiert einen (ggf. unvertrauten) Plot-Index: nil -> 1, nur ganze
--- Zahlen 1..MAX_PLOTS gueltig, sonst nil.
function PlotRegistry.NormalizePlotIndex(plotIndex: any): number?
	if plotIndex == nil then
		return 1
	end
	if type(plotIndex) ~= "number" or plotIndex ~= math.floor(plotIndex) then
		return nil
	end
	if plotIndex < 1 or plotIndex > MAX_PLOTS_PER_PLAYER then
		return nil
	end
	return plotIndex
end

local function refreshPlotCountAttribute(player: Player)
	local count = 0
	local plots = plotsByUserId[player.UserId]
	if plots then
		for _, plot in pairs(plots) do
			if plot.Parent then
				count += 1
			end
		end
	end
	player:SetAttribute("PlotCount", count)
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

--- Weist `player` die Plot-Kopie `plotIndex` (nil = 1, max. 2) zu
--- (idempotent - ein bereits aktiver Plot wird zurückgegeben statt eines
--- zweiten). Plot 2 liegt neben Plot 1; existiert Plot 1 noch nicht, wird er
--- vorher mit angelegt. Gibt nil zurück, falls die Plot-Vorlage fehlt
--- (Buildscript nie in Studio ausgeführt, siehe AssetTemplateSetup-Warnung)
--- oder `plotIndex` ungültig ist. Prüft KEINEN Gamepass-Besitz (Aufrufer).
function PlotRegistry.AssignPlot(player: Player, plotIndexArg: number?): Model?
	local plotIndex = PlotRegistry.NormalizePlotIndex(plotIndexArg)
	if not plotIndex then
		return nil
	end
	local userId = player.UserId

	local plots = plotsByUserId[userId]
	local existing = plots and plots[plotIndex]
	if existing and existing.Parent then
		return existing
	end

	if plotIndex > 1 then
		-- Plot 2 haengt am Slot von Plot 1.
		local first = PlotRegistry.AssignPlot(player, 1)
		if not first then
			return nil
		end
	end

	local template = AssetTemplateSetup.GetPlotTemplate()
	if not template then
		warn(("[PlotRegistry] Cannot assign a plot to %s - HabitatPlotBase template is missing."):format(player.Name))
		return nil
	end

	local slot = slotByUserId[userId]
	if not slot then
		slot = claimSlot()
		slotByUserId[userId] = slot
	end

	local plot = template:Clone()
	plot.Name = if plotIndex == 1 then tostring(userId) else ("%d_%d"):format(userId, plotIndex)
	plot:SetAttribute("OwnerUserId", userId)
	plot:SetAttribute("OwnerName", player.Name)
	plot:SetAttribute("PlotIndex", plotIndex)

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = plot

	-- Der eigene Plot liegt weit weg vom Hub (Spawn). Mit StreamingEnabled
	-- (siehe Release-Checkliste) wuerde er sonst nie zum Besitzer replizieren,
	-- solange dieser im Hub steht - Bau-/Zucht-UI fanden dann "keinen Plot".
	-- PersistentPerPlayer: nur der Besitzer bekommt den Plot dauerhaft (samt
	-- allen spaeter darunter erzeugten Gebaeuden/Sporen/Kreaturen).
	pcall(function()
		(plot :: any).ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)

	plot.Parent = plotsFolder
	plot:PivotTo(slotOrigin(slot, plotIndex))
	pcall(function()
		(plot :: any):AddPersistentPlayer(player)
	end)

	plotsByUserId[userId] = plotsByUserId[userId] or {}
	plotsByUserId[userId][plotIndex] = plot
	refreshPlotCountAttribute(player)
	return plot
end

--- Entfernt ALLE Plot-Instanzen eines Spielers wieder aus dem Workspace
--- (inkl. aller darauf platzierten Gebäude-Modelle) und gibt den Welt-Slot
--- (beide Spalten) für den nächsten Spieler frei. Die Persistenz der
--- Platzierungen selbst läuft unabhängig davon bereits über
--- PlayerDataService/HabitatLayout - hier wird nur die Laufzeit-
--- Repräsentation im Workspace aufgeräumt.
function PlotRegistry.ReleasePlot(player: Player)
	local userId = player.UserId

	local plots = plotsByUserId[userId]
	if plots then
		for _, plot in pairs(plots) do
			plot:Destroy()
		end
	end
	plotsByUserId[userId] = nil

	local slot = slotByUserId[userId]
	if slot then
		table.insert(freeSlots, slot)
	end
	slotByUserId[userId] = nil

	if player.Parent then
		player:SetAttribute("PlotCount", 0)
	end
end

--- Liefert die aktive Plot-Instanz `plotIndex` (nil = 1) eines Spielers,
--- oder nil.
function PlotRegistry.GetPlot(player: Player, plotIndexArg: number?): Model?
	local plotIndex = PlotRegistry.NormalizePlotIndex(plotIndexArg)
	if not plotIndex then
		return nil
	end
	local plots = plotsByUserId[player.UserId]
	local plot = plots and plots[plotIndex]
	if plot and plot.Parent then
		return plot
	end
	return nil
end

--- Liefert alle aktiven Plots eines Spielers (Index-Reihenfolge).
function PlotRegistry.GetPlots(player: Player): { Model }
	local result: { Model } = {}
	for index = 1, MAX_PLOTS_PER_PLAYER do
		local plot = PlotRegistry.GetPlot(player, index)
		if plot then
			table.insert(result, plot)
		end
	end
	return result
end

--- Liefert alle Baufelder eines Spieler-Plots (Index 1..GridFieldCount)
--- mitsamt ihrem Attachment (für lokale/Welt-CFrame-Berechnung).
function PlotRegistry.GetBuildFields(player: Player, plotIndex: number?): { BuildField }
	local plot = PlotRegistry.GetPlot(player, plotIndex)
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
function PlotRegistry.GetBuildField(player: Player, fieldIndex: number, plotIndex: number?): BuildField?
	for _, field in ipairs(PlotRegistry.GetBuildFields(player, plotIndex)) do
		if field.Index == fieldIndex then
			return field
		end
	end
	return nil
end

--- Liefert den "Buildings"-Unterordner eines Spieler-Plots, in dem
--- PlacementService platzierte Gebäude-Instanzen ablegt (oder nil, falls
--- kein Plot zugewiesen ist).
function PlotRegistry.GetBuildingsFolder(player: Player, plotIndex: number?): Folder?
	local plot = PlotRegistry.GetPlot(player, plotIndex)
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
