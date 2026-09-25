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

	BEWEGUNGS-ARCHITEKTUR (GEÄNDERT - Seamless-Animation-System, siehe
	docs/animation-system.md):
		Server bleibt AUTORITATIV für die Wander-LOGIK (welches Ziel eine
		Kreatur ansteuert, wann sie "ankommt" und ein neues Ziel bekommt) -
		EIN gemeinsamer, gedrosselter Loop (WANDER_TICK_SECONDS) prüft dafür
		ALLE angezeigten Kreaturen aller Plots, kein Loop pro Kreatur/Plot.

		NEU: der Server bewegt das Model dabei NICHT MEHR direkt per
		`Model:PivotTo()` (das ließ anchored Parts auf Clients bei 5 Hz
		sichtbar ruckeln - Roblox interpoliert CFrame-Änderungen anchored
		Teile NICHT). Stattdessen publiziert der Server nur noch die
		Ziel-Weltposition als `ModelAnimationTags.ATTR_TARGET_POSITION`-
		Attribut (CollectionService-Tag `ModelAnimationTags.DISPLAY_CREATURE`,
		siehe ModelAnimationTags-Kopfkommentar) - der Client
		(`src/client/ModelAnimator.client.lua`) interpoliert selbst jeden
		Frame flüssig dorthin (Chase/Lerp-Pattern, identisch zu
		`BuddyClient.client.lua`s bereits bewährtem Follow-Ansatz) UND legt
		die Idle-Bob-/Flossen-Sway-Animation (`IdleSway`-Modul) client-seitig
		on top. Das ist bewusst KEIN Bruch des "kein Client-Trust"-Prinzips:
		diese Kreaturen haben keinerlei Gameplay-Gewicht (keine Kollision,
		keine Treffer-/Prompt-Logik hängt an ihrer exakten Position) - nur
		die vom Server gewählten WERTE (welche Kreatur, welches ungefähre
		Wander-Ziel) sind relevant, nicht die exakte Bild-für-Bild-Position.
		Andere Spieler, die dasselbe fremde Plot sehen, sehen dieselbe
		Server-Zielposition und interpolieren mit demselben Chase-Verfahren
		dorthin - keine divergierenden Positionen.

	PULSE-/BOB-ANIMATION (GEÄNDERT):
		Läuft jetzt komplett client-seitig über `IdleSway`
		(`src/shared/ModelAnimation/IdleSway.lua`) - dieselbe Idle-Logik wie
		bei Buddys (`BuddyClient.client.lua`) und Raid-Gegnern
		(`RaidService.lua` + `ModelAnimator.client.lua`), für optische
		Konsistenz. Das Attachment "PulseAttachment" am PrimaryPart "Body"
		(Buildscript-Konvention, siehe assets/models/README.md) bleibt als
		dokumentierter Marker bestehen, wird von `IdleSway` aber nicht mehr
		zwingend vorausgesetzt (jedes Modell mit PrimaryPart bobbt).

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
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GachaConfig = require(script.Parent:WaitForChild("GachaConfig"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local ModelAnimationTags = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("ModelAnimationTags"))

type CreatureInstance = PlayerDataService.CreatureInstance

-- // Konfiguration -------------------------------------------------------------

local MAX_DISPLAYED_CREATURES = 6
local WANDER_RADIUS_STUDS = 20 -- skaliert mit dem ~60-Stud-Hex-Plot, siehe Abschnitt 5.1
local SWIM_HEIGHT_MIN = 5
local SWIM_HEIGHT_MAX = 13
local SPEED_STUDS_PER_SECOND_MIN = 2.5
local SPEED_STUDS_PER_SECOND_MAX = 5.5
local ARRIVE_DISTANCE_STUDS = 1.5
-- Bob-/Puls-Idle-Animation läuft seit dem Seamless-Animation-System
-- komplett client-seitig (IdleSway-Modul) - hier kein Bob-Tuning mehr nötig.

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
	}

	clone:PivotTo(CFrame.new(baseX, swimHeight, baseZ))

	-- Seamless-Animation-System (docs/animation-system.md): Tag + initiales
	-- Ziel-Attribut für den Client-Renderer (ModelAnimator.client.lua). Der
	-- Server ruft `PivotTo` ab hier NIE WIEDER auf dieses Model auf (siehe
	-- tickSlot) - nur noch ATTR_TARGET_POSITION-Updates.
	CollectionService:AddTag(clone, ModelAnimationTags.DISPLAY_CREATURE)
	clone:SetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION, Vector3.new(baseX, swimHeight, baseZ))

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
	end

	-- Seamless-Animation-System: NUR die logische Zielposition publizieren
	-- (ohne Bob - der Client legt Bob/Idle-Sway selbst on top, siehe
	-- IdleSway-Modul) - kein PivotTo mehr auf dem Server, siehe
	-- Kopfkommentar "Bewegungs-Architektur".
	if slot.Model.Parent then
		slot.Model:SetAttribute(
			ModelAnimationTags.ATTR_TARGET_POSITION,
			Vector3.new(slot.BaseX, slot.SwimHeight, slot.BaseZ)
		)
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

print("[Abyssara] CreatureDisplayService ready (plot creature display active).")

return CreatureDisplayService
