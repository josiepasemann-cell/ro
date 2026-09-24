--[[
	Abyssara – Deep Tide Tycoon
	Modul: CreatureDisplayService
	Zuständigkeit:
		Macht besessene Kreaturen tatsächlich SICHTBAR auf dem eigenen Plot
		(docs/content-update-1.md, Abschnitt 5.1) - bisher waren sie reine
		Inventar-Zeilen. Wählt je Spieler bis zu 6 anzuzeigende Kreaturen
		(standardmäßig die 6 seltensten, Favoriten-Override über den Kodex,
		siehe CodexService), spawnt/despawnt ihre Modelle auf dem Plot und
		lässt sie servergesteuert in einem Radius um den Plot-Mittelpunkt
		wandern/schweben.

	AUSWAHL-REGEL (Abschnitt 5.1):
		- Kein Favoriten-Eintrag gesetzt: automatisch die 6 seltensten
		  besessenen Kreaturen-INSTANZEN (Gleichstand -> zuletzt erhalten
		  zuerst), siehe selectDisplayInstances().
		- Favoriten gesetzt (CodexService.SetFavorites, max. 6 CreatureIds):
		  ERSETZT die Auto-Auswahl komplett (kein Auffüllen mit Rarest-
		  Kreaturen) - je Favoriten-Art wird die zuletzt erhaltene besessene
		  Instanz dieser Art angezeigt. Bewusste Vereinfachung: Favoriten
		  sind Kreaturen-ARTEN (CreatureId), keine einzelnen InstanceIds -
		  siehe PlayerDataService.CodexState-Kopfkommentar für die
		  Begründung.

	BEWEGUNGS-PERFORMANCE (Abschnitt 5.1, "Handy-Performance"):
		EIN gemeinsamer, gedrosselter Loop (WANDER_TICK_SECONDS, identisches
		Muster zu RaidService.runRaidTickLoop/RaidConfig.RAID_TICK_SECONDS)
		bewegt ALLE angezeigten Kreaturen aller Plots - kein Loop pro
		Kreatur/Plot. Modelle sind vollständig `Anchored` (siehe Kreaturen-
		Buildscripts, assets/models/creatures/*.lua) und werden rein per
		`Model:PivotTo()` bewegt - keine Physik/Kollision.

		ENTSCHEIDUNG "Server- statt Client-getriebene Bewegung" (Auftrag:
		"consider driving motion on clients instead if cheaper, document
		the choice"): bewusst SERVERSEITIG gehalten, nicht client-getrieben.
		Begründung: (1) Server bleibt bei JEDER Positionsangabe alleinige
		Autorität (Projekt-Grundsatz "kein Client-Trust" - eine client-
		seitige Wander-Simulation würde entweder pro Client eigene,
		divergierende Positionen zeigen (andere Spieler sehen fremde Plots
		leicht unterschiedlich) oder exakt denselben RNG-Seed/Zeitbasis
		client-seitig nachbilden müssen, was fragiler ist als eine einzige
		Server-Quelle. (2) Der Teil-/Update-Budget ist ohnehin klein (<=6
		Kreaturen a 2-15 Parts je sichtbarem Plot, `WANDER_TICK_SECONDS` =
		5 Hz statt RaidConfig's 10 Hz) - die zusätzliche CPU-Last ist
		trigonometrisch trivial, die Netzwerk-Replikation (CFrame-Deltas,
		nur für tatsächlich gestreamte/nahe Plots dank
		`Workspace.StreamingEnabled`) ist kleiner als die für Gebäude-
		Platzierung bereits bestehende Replikationslast. Ein Umstieg auf
		client-seitige Interpolation wäre nur bei deutlich höherer
		Kreaturenzahl/-frequenz gerechtfertigt.

	PULSE-/BOB-ANIMATION:
		Jede Kreatur besitzt bereits ein Attachment "PulseAttachment" am
		PrimaryPart "Body" (Buildscript-Konvention, siehe
		assets/models/README.md) als vorgesehenen Ansatzpunkt für die
		Idle-Puls-/Schwebe-Animation. Da dieses System die gesamte Modell-
		Pivot (inkl. `Body`, also inkl. `PulseAttachment`) jeden Tick per
		`PivotTo` neu setzt, "bobt" das Attachment automatisch mit - kein
		zusätzlicher, zweiter Animationskanal nötig.

	Rojo-Einhängepunkt:
		src/server/CreatureDisplayService.lua ->
		ServerScriptService.CreatureDisplayService
		(reines Server-Modul; verdrahtet Players.PlayerAdded/PlayerRemoving
		+ GameEvents-Abonnements selbst beim ersten require(), identisches
		Muster zu GachaService/PlayerDataService - kein separates Bootstrap-
		Script nötig.)

	BEWUSST ENTKOPPELT von CodexService:
		Dieses Modul braucht keinen vollen Kreaturen-Katalog (Zone/Event-
		Gruppierung) - nur PlayerDataService.CreatureInventory (enthält
		bereits Rarity/AcquiredAt je Instanz) + GachaConfig.RARITY_ORDER für
		die Rarest-Sortierung. Es requiret CodexService NICHT (vermeidet
		unnötige Kopplung); CodexService feuert stattdessen das
		GameEvents-Signal "CodexFavoritesChanged", auf das hier reagiert
		wird - reine Einbahnstraßen-Kommunikation, kein Require-Zyklus.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GachaConfig = require(script.Parent:WaitForChild("GachaConfig"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))

type CreatureInstance = PlayerDataService.CreatureInstance

-- // Konfiguration -------------------------------------------------------------

local MAX_DISPLAYED_CREATURES = 6
local WANDER_RADIUS_STUDS = 20 -- skaliert mit dem ~60-Stud-Hex-Plot, siehe Abschnitt 5.1
local SWIM_HEIGHT_MIN = 5
local SWIM_HEIGHT_MAX = 13
local SPEED_STUDS_PER_SECOND_MIN = 2.5
local SPEED_STUDS_PER_SECOND_MAX = 5.5
local ARRIVE_DISTANCE_STUDS = 1.5
local BOB_AMPLITUDE_STUDS = 0.6
local BOB_SPEED_MIN = 0.6
local BOB_SPEED_MAX = 1.3

-- Gedrosselter gemeinsamer Tick (siehe Kopfkommentar) - bewusst langsamer
-- als RaidConfig.RAID_TICK_SECONDS (0.1s/10 Hz), da reine Ambiente-
-- Bewegung keine Kampf-Präzision braucht.
local WANDER_TICK_SECONDS = 0.2

-- Sicherheitsnetz-Resync (fängt Inventar-Änderungen ab, die aus welchem
-- Grund auch immer kein GameEvents-Signal feuern, z. B. künftige
-- Admin-/Debug-Befehle) - rebuildDisplay() selbst ist ein günstiger Diff,
-- kein teurer Full-Respawn, siehe dort.
local SAFETY_RESYNC_INTERVAL_SECONDS = 20

local JOIN_DATA_TIMEOUT_SECONDS = 15

local rng = Random.new()

-- // Laufzeit-Zustand -----------------------------------------------------------

type DisplaySlot = {
	Model: Model,
	InstanceId: string,
	CreatureId: string,
	BaseX: number,
	BaseZ: number,
	SwimHeight: number,
	TargetX: number,
	TargetZ: number,
	Speed: number,
	BobPhase: number,
	BobSpeed: number,
	LastYaw: number,
}

type PlotDisplay = {
	Player: Player,
	Plot: Model,
	Folder: Folder,
	CenterX: number,
	CenterZ: number,
	BaseY: number,
	Slots: { DisplaySlot },
}

local displaysByUserId: { [number]: PlotDisplay } = {}
local warnedMissingTemplate: { [string]: boolean } = {}

local CreatureDisplayService = {}

-- // Hilfsfunktionen --------------------------------------------------------

local function safeRarityIndex(rarity: string): number
	local index = table.find(GachaConfig.RARITY_ORDER, rarity)
	return index or 0
end

--- Wählt bis zu MAX_DISPLAYED_CREATURES Kreaturen-Instanzen für die Plot-
--- Anzeige (siehe Kopfkommentar "Auswahl-Regel").
local function selectDisplayInstances(player: Player): { CreatureInstance }
	local inventory = PlayerDataService.GetCreatureInventory(player)
	local favorites = PlayerDataService.GetCodexFavorites(player)

	if #favorites > 0 then
		local chosen: { CreatureInstance } = {}
		for _, creatureId in ipairs(favorites) do
			if #chosen >= MAX_DISPLAYED_CREATURES then
				break
			end
			local best: CreatureInstance? = nil
			for _, instance in ipairs(inventory) do
				if instance.CreatureId == creatureId and (not best or instance.AcquiredAt > (best :: CreatureInstance).AcquiredAt) then
					best = instance
				end
			end
			if best then
				table.insert(chosen, best :: CreatureInstance)
			end
		end
		return chosen
	end

	local sorted: { CreatureInstance } = {}
	for _, instance in ipairs(inventory) do
		table.insert(sorted, instance)
	end
	table.sort(sorted, function(a, b)
		local ra, rb = safeRarityIndex(a.Rarity), safeRarityIndex(b.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.AcquiredAt > b.AcquiredAt
	end)

	local result: { CreatureInstance } = {}
	for i = 1, math.min(MAX_DISPLAYED_CREATURES, #sorted) do
		table.insert(result, sorted[i])
	end
	return result
end

local function getOrCreateCreaturesFolder(plot: Model): Folder
	local existing = plot:FindFirstChild("Creatures")
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Creatures"
	folder.Parent = plot
	return folder
end

local function findCreatureTemplate(creatureId: string): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local creaturesFolder = assetsFolder and assetsFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	return nil
end

local function randomPointInRadius(centerX: number, centerZ: number): (number, number)
	local angle = rng:NextNumber() * math.pi * 2
	local distance = rng:NextNumber() * WANDER_RADIUS_STUDS
	return centerX + math.cos(angle) * distance, centerZ + math.sin(angle) * distance
end

--- Phone-Performance-Härtung (Abschnitt 5.1): PointLights an angezeigten
--- Kreaturen werfen keine Schatten (identische Regel wie hub-/terrain-weit,
--- siehe assets/models/README.md "Handy-Performance"). Aktuelle Kreaturen-
--- Buildscripts setzen noch keine PointLights, dieser Schritt ist reine
--- Zukunftssicherung für künftige Modelle.
local function hardenLightsForPhone(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
			descendant.Shadows = false
		end
	end
end

local function despawnSlot(slot: DisplaySlot)
	slot.Model:Destroy()
end

local function spawnSlot(display: PlotDisplay, instance: CreatureInstance): DisplaySlot?
	local template = findCreatureTemplate(instance.CreatureId)
	if not template then
		if not warnedMissingTemplate[instance.CreatureId] then
			warnedMissingTemplate[instance.CreatureId] = true
			warn(
				("[CreatureDisplayService] No Workspace.Assets.Creatures model for '%s' - plot display skipped until the buildscript has been run in Studio."):format(
					instance.CreatureId
				)
			)
		end
		return nil
	end

	local clone = template:Clone()
	clone.Name = instance.InstanceId
	hardenLightsForPhone(clone)
	clone.Parent = display.Folder

	local baseX, baseZ = randomPointInRadius(display.CenterX, display.CenterZ)
	local targetX, targetZ = randomPointInRadius(display.CenterX, display.CenterZ)
	local swimHeight = display.BaseY + rng:NextNumber(SWIM_HEIGHT_MIN, SWIM_HEIGHT_MAX)

	local slot: DisplaySlot = {
		Model = clone,
		InstanceId = instance.InstanceId,
		CreatureId = instance.CreatureId,
		BaseX = baseX,
		BaseZ = baseZ,
		SwimHeight = swimHeight,
		TargetX = targetX,
		TargetZ = targetZ,
		Speed = rng:NextNumber(SPEED_STUDS_PER_SECOND_MIN, SPEED_STUDS_PER_SECOND_MAX),
		BobPhase = rng:NextNumber() * math.pi * 2,
		BobSpeed = rng:NextNumber(BOB_SPEED_MIN, BOB_SPEED_MAX),
		LastYaw = rng:NextNumber() * math.pi * 2,
	}

	clone:PivotTo(CFrame.new(baseX, swimHeight, baseZ))

	return slot
end

--- Baut die Anzeige für `player` neu auf - günstiger DIFF gegen den
--- aktuellen Zustand (nur tatsächlich geänderte Slots werden despawnt/neu
--- gespawnt, unveränderte Instanzen behalten ihre Position/Wander-Phase).
function CreatureDisplayService.RefreshForPlayer(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		return
	end

	local display = displaysByUserId[player.UserId]
	if not display or display.Plot ~= plot then
		if display then
			for _, slot in ipairs(display.Slots) do
				despawnSlot(slot)
			end
		end
		local center = plot.PrimaryPart.Position
		display = {
			Player = player,
			Plot = plot,
			Folder = getOrCreateCreaturesFolder(plot),
			CenterX = center.X,
			CenterZ = center.Z,
			BaseY = center.Y,
			Slots = {},
		}
		displaysByUserId[player.UserId] = display
	end

	local desired = selectDisplayInstances(player)
	local desiredByInstanceId: { [string]: boolean } = {}
	for _, instance in ipairs(desired) do
		desiredByInstanceId[instance.InstanceId] = true
	end

	-- Nicht mehr gewünschte Slots entfernen.
	local keptSlots: { DisplaySlot } = {}
	for _, slot in ipairs(display.Slots) do
		if desiredByInstanceId[slot.InstanceId] then
			table.insert(keptSlots, slot)
		else
			despawnSlot(slot)
		end
	end
	display.Slots = keptSlots

	local existingInstanceIds: { [string]: boolean } = {}
	for _, slot in ipairs(display.Slots) do
		existingInstanceIds[slot.InstanceId] = true
	end

	-- Neue Slots für frisch hinzugekommene Instanzen spawnen.
	for _, instance in ipairs(desired) do
		if not existingInstanceIds[instance.InstanceId] then
			local slot = spawnSlot(display, instance)
			if slot then
				table.insert(display.Slots, slot)
			end
		end
	end
end

--- Entfernt alle angezeigten Kreaturen von `player` und den Laufzeit-
--- Zustand dazu (PlayerRemoving/Plot-Freigabe).
function CreatureDisplayService.CleanupPlayer(player: Player)
	local display = displaysByUserId[player.UserId]
	if not display then
		return
	end
	for _, slot in ipairs(display.Slots) do
		despawnSlot(slot)
	end
	displaysByUserId[player.UserId] = nil
end

-- // Gemeinsamer, gedrosselter Wander-/Bob-Loop (siehe Kopfkommentar) ----------

local function tickSlot(slot: DisplaySlot, display: PlotDisplay, dt: number, now: number)
	local dx = slot.TargetX - slot.BaseX
	local dz = slot.TargetZ - slot.BaseZ
	local distance = math.sqrt(dx * dx + dz * dz)

	if distance <= ARRIVE_DISTANCE_STUDS then
		-- Ziel erreicht: neues zufälliges Ziel innerhalb des Wander-Radius
		-- um den Plot-Mittelpunkt wählen.
		slot.TargetX, slot.TargetZ = randomPointInRadius(display.CenterX, display.CenterZ)
	else
		local step = math.min(slot.Speed * dt, distance)
		local nx, nz = dx / distance, dz / distance
		slot.BaseX += nx * step
		slot.BaseZ += nz * step
		slot.LastYaw = math.atan2(nx, nz)
	end

	local bobY = math.sin(now * slot.BobSpeed + slot.BobPhase) * BOB_AMPLITUDE_STUDS
	local position = Vector3.new(slot.BaseX, slot.SwimHeight + bobY, slot.BaseZ)
	local cframe = CFrame.new(position) * CFrame.Angles(0, slot.LastYaw, 0)

	if slot.Model.Parent then
		slot.Model:PivotTo(cframe)
	end
end

local function runWanderLoop()
	while true do
		task.wait(WANDER_TICK_SECONDS)
		local now = os.clock()
		for _, display in pairs(displaysByUserId) do
			if display.Plot.Parent then
				for _, slot in ipairs(display.Slots) do
					tickSlot(slot, display, WANDER_TICK_SECONDS, now)
				end
			end
		end
	end
end

local function runSafetyResyncLoop()
	while true do
		task.wait(SAFETY_RESYNC_INTERVAL_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			if PlayerDataService.IsDataLoaded(player) then
				task.spawn(CreatureDisplayService.RefreshForPlayer, player)
			end
		end
	end
end

-- // Join/Leave-Verdrahtung -----------------------------------------------------

local function onPlayerAdded(player: Player)
	PlotRegistry.AssignPlot(player) -- idempotent, siehe PlotRegistry-Kopfkommentar

	local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
	if not data then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end

	CreatureDisplayService.RefreshForPlayer(player)
end

local function onPlayerRemoving(player: Player)
	CreatureDisplayService.CleanupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

-- // GameEvents-Reaktion (Inventar-/Favoriten-Änderungen) ----------------------

local function onInventoryRelevantEvent(player: Player, _payload: { [string]: any })
	task.defer(CreatureDisplayService.RefreshForPlayer, player)
end

GameEvents.Connect(GameEvents.Events.EggOpened, onInventoryRelevantEvent)
GameEvents.Connect(GameEvents.Events.BreedingCompleted, onInventoryRelevantEvent)
GameEvents.Connect(GameEvents.Events.RaidLost, onInventoryRelevantEvent) -- Entführung kann eine angezeigte Kreatur entfernen
GameEvents.Connect("CodexFavoritesChanged", onInventoryRelevantEvent)

task.spawn(runWanderLoop)
task.spawn(runSafetyResyncLoop)

print("[Abyssara] CreatureDisplayService bereit (Plot-Kreaturenanzeige aktiv).")

return CreatureDisplayService
