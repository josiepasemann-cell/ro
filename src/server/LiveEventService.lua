--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: LiveEventService
	Zuständigkeit:
		Kernlogik des rotierenden Live-Event-Systems (docs/content-update-1.md,
		Abschnitt 1 + 7b): erkennt den aktuell laut LiveEventConfig aktiven
		12h-UTC-Slot, tweent Lighting/Fog + eine passende Partikel-Stimmung
		beim Wechsel, verwaltet je Spieler die Event-Währungsbilanz (mit dem
		Fairness-Reset aus Abschnitt 1.2 bei jedem Slot-Wechsel), den
		3-Schritte-Quest-Linien-Fortschritt, den Event-Shop-Kauf (inkl.
		eigenem, kleinem gewichteten Ei-Roll) sowie die Gameplay-Modifikatoren,
		die andere Systeme (IdleIncomeService/BreedingService/RaidService/
		PickupSpawner) an ihrer jeweiligen Berechnungsstelle über
		GetModifier/GetBuildingIncomeMultiplier abfragen.

		Verdienst-Einhängepunkte laufen AUSSCHLIESSLICH über den bestehenden
		GameEvents-Hub (SporeDelivered/RaidWon/BreedingCompleted) - EIN
		zentraler Satz Abonnements hier statt gestreuter Aufrufe in jedem
		einzelnen Gameplay-Service (siehe GameEvents-Kopfkommentar).
		Zusätzliche, im GDD ausdrücklich event-eigene Verdienstquellen ohne
		bestehenden GameEvents-Hook (Sunken Chest/Frozen-Spore-Auftauen)
		ruft PickupSpawner (eigenes Modul desselben Agenten) direkt über
		LiveEventService.AwardEventCurrency/AdvanceEventQuest auf - Ghost
		Ship (Spooky Tide) und Vent-Puls (Volcanic Vent) sind reine
		Server-Zeit-Ereignisse ohne Spieler-Trigger und laufen komplett
		intern in diesem Modul (siehe runSpecialEventLoop).

	VEREINFACHUNG "Ghost Ship" (Abschnitt 1.3, Spooky Tide):
		Das GDD beschreibt ein Landmark-Modell, das "einmal pro Slot" in der
		Nähe des Sun-Zone-Shipwreck-Landmarks erscheint. Kein Ghost-Ship-3D-
		Modell ist Teil der 3D-Asset-Bauliste (Abschnitt 7a) - es existiert
		daher (noch) keine interaktive Welt-Instanz dafür. Diese Version
		implementiert den spielerischen KERN (einmal pro Slot, zu einem
		zufälligen Zeitpunkt, Bonus-Währung + Quest-Fortschritt für alle
		online Spieler) als serverseitig getakteten Broadcast statt eines
		Welt-Objekts - ein künftiges Landmark-Modell kann denselben
		`triggerGhostShip`-Effekt einfach an ein ProximityPrompt hängen,
		ohne dieses Modul zu ändern.

	VEREINFACHUNG Event-Eier (Abschnitt 1.2/1.3):
		Jedes Event-Ei im Shop ist im Design-Dokument 1:1 einer bestimmten
		Kreatur zugeordnet (z. B. "ToxinPuffer Egg" -> garantiert
		ToxinPuffer). Der Kauf löst trotzdem einen (aktuell einelementigen)
		gewichteten Roll aus (siehe rollEventEgg) statt eine Kreatur fest zu
		verdrahten - identisches Muster zu GachaService/BreedingService,
		zukunftssicher für ein eventuelles "Mystery"-Event-Ei mit mehreren
		möglichen Ergebnissen, ohne die Aufruf-Stelle ändern zu müssen. Das
		Ei "schlüpft" sofort beim Kauf (keine separate Inkubationszeit wie
		beim BroodPool) - im Design-Dokument ist für Event-Eier keine
		Zucht-Wartezeit vorgesehen, siehe Quest-Schritt-Wortlaut "Schlüpfe
		ein X Egg", der bereits unmittelbar nach Kauf erfüllt wird.

	Studio-Testschalter (Abschnitt 6 im Auftrag, siehe docs/live-events.md):
		NUR wenn `RunService:IsStudio()` true ist, überschreibt das Server-
		Attribut `workspace:GetAttribute("ForceEvent")` (einer der 6
		EventId-Strings) den deterministisch berechneten Slot. In einem
		veröffentlichten Live-Spiel ist `IsStudio()` immer false - das
		Attribut wird dort vollständig ignoriert, unabhängig davon, ob es
		versehentlich gesetzt wurde.

	Rojo-Einhängepunkt:
		src/server/LiveEventService.lua -> ServerScriptService.LiveEventService
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local LiveEventConfig = require(ReplicatedStorage:WaitForChild("LiveEventConfig"))
local LiveEventRemotes = require(ReplicatedStorage:WaitForChild("LiveEventRemotes"))

type EventDefinition = LiveEventConfig.EventDefinition
type LiveEventState = PlayerDataService.LiveEventState

local LiveEventService = {}

local rng = Random.new()

-- // Konfiguration ------------------------------------------------------------

local EVENT_CHECK_INTERVAL_SECONDS = 5 -- grob genug für Performance, fein genug gegen "verpasste" Slot-Wechsel
local LIGHTING_TRANSITION_SECONDS = 4
local DECORATION_REFRESH_INTERVAL_SECONDS = 15

-- // Laufzeit-Zustand (NICHT persistent - siehe PlayerDataService.LiveEventState
-- für den persistierten Teil je Spieler) ---------------------------------------

local currentEventId: string? = nil
local currentEventDef: EventDefinition? = nil
local specialLoopThread: thread? = nil

-- // Studio-Testschalter --------------------------------------------------------

local function getForcedEventId(): string?
	if not RunService:IsStudio() then
		return nil
	end
	local forced = Workspace:GetAttribute("ForceEvent")
	if type(forced) == "string" and LiveEventConfig.GetEvent(forced) then
		return forced
	end
	return nil
end

local function resolveCurrentEventId(): string
	return getForcedEventId() or LiveEventConfig.GetActiveEventId(os.time())
end

-- // Lighting-/Partikel-Stimmung -----------------------------------------------

local function applyLighting(profile: LiveEventConfig.LightingProfile, instant: boolean)
	if instant then
		Lighting.Ambient = profile.Ambient
		Lighting.OutdoorAmbient = profile.OutdoorAmbient
		Lighting.FogColor = profile.FogColor
		Lighting.FogEnd = profile.FogEnd
		return
	end

	local tween = TweenService:Create(
		Lighting,
		TweenInfo.new(LIGHTING_TRANSITION_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			Ambient = profile.Ambient,
			OutdoorAmbient = profile.OutdoorAmbient,
			FogColor = profile.FogColor,
			FogEnd = profile.FogEnd,
		}
	)
	tween:Play()
end

--- Liest die von WorldSetup.server.lua hinterlegten Baseline-Attribute
--- (siehe dortiger Kommentar) - defensiver Fallback auf die dort aktuell
--- hartcodierten Werte, falls WorldSetup (noch) nicht gelaufen ist (z. B.
--- Modul-Lade-Reihenfolge in einem zukünftigen Refactor).
local function getBaselineLightingProfile(): LiveEventConfig.LightingProfile
	local ambient = Lighting:GetAttribute("BaselineAmbient")
	local outdoorAmbient = Lighting:GetAttribute("BaselineOutdoorAmbient")
	local fogColor = Lighting:GetAttribute("BaselineFogColor")
	local fogEnd = Lighting:GetAttribute("BaselineFogEnd")
	return {
		Ambient = if typeof(ambient) == "Color3" then ambient else Color3.fromRGB(18, 28, 36),
		OutdoorAmbient = if typeof(outdoorAmbient) == "Color3" then outdoorAmbient else Color3.fromRGB(14, 22, 30),
		FogColor = if typeof(fogColor) == "Color3" then fogColor else Color3.fromRGB(5, 12, 18),
		FogEnd = if typeof(fogEnd) == "number" then fogEnd else 150,
	}
end

local function getHubAnchorPosition(): Vector3
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	local hubModel = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	if hubModel and hubModel:IsA("Model") and hubModel.PrimaryPart then
		return hubModel.PrimaryPart.Position + Vector3.new(0, 18, 0)
	end
	return Vector3.new(0, 20, 0)
end

local moodEmitter: ParticleEmitter? = nil

local function ensureMoodEmitter(): ParticleEmitter?
	if moodEmitter and moodEmitter.Parent then
		return moodEmitter
	end

	local folder = Workspace:FindFirstChild("LiveEventFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LiveEventFX"
		folder.Parent = Workspace
	end

	local anchor = Instance.new("Part")
	anchor.Name = "MoodAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(getHubAnchorPosition())
	anchor.Parent = folder

	local attachment = Instance.new("Attachment")
	attachment.Name = "MoodPoint"
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EventMood"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment

	moodEmitter = emitter
	return moodEmitter
end

local function updateParticleMood(profile: LiveEventConfig.ParticleProfile)
	local emitter = ensureMoodEmitter()
	if not emitter then
		return
	end

	emitter.Color = ColorSequence.new(profile.Color1, profile.Color2)
	emitter.Rate = profile.Rate

	if profile.Direction == "Up" then
		emitter.Acceleration = Vector3.new(0, 3, 0)
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.Speed = NumberRange.new(1, 2)
	elseif profile.Direction == "Down" then
		emitter.Acceleration = Vector3.new(0, -3, 0)
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.Speed = NumberRange.new(1, 2)
	else -- "Horizontal"
		emitter.Acceleration = Vector3.new(2, 0.2, 0)
		emitter.SpreadAngle = Vector2.new(180, 20)
		emitter.Speed = NumberRange.new(0.5, 1.5)
	end
end

-- // Event-Deko-Anzeige (Cosmetic-Slot "Decoration", siehe ShopConfig.CosmeticSlot) --
-- Bewusst schlank: keine eigene Platzier-/Bewege-UI, nur "besitzt + ausgerüstet
-- -> steht sichtbar am Plot" - identisches Prinzip zu PickupSpawners eigener,
-- in sich geschlossener Asset-Vorlagen-Beschaffung (AssetTemplateSetup wird
-- laut Auftrag NICHT für Decorations erweitert).

local DECORATION_MODEL_NAMES: { [string]: boolean } = {}
for _, event in pairs(LiveEventConfig.EVENTS) do
	for _, item in ipairs(event.ShopItems) do
		if item.Type == "Cosmetic" and item.CosmeticSlot == "Decoration" then
			DECORATION_MODEL_NAMES[item.Id] = true
		end
	end
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Folder
end

local decorationTemplatesFolder = getOrCreateFolder(getOrCreateFolder(ReplicatedStorage, "AssetTemplates"), "Decorations")
local warnedMissingDecoration: { [string]: boolean } = {}

local function getDecorationTemplate(name: string): Model?
	local existing = decorationTemplatesFolder:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing
	end

	local assetsFolder = Workspace:FindFirstChild("Assets")
	local decorFolder = assetsFolder and assetsFolder:FindFirstChild("Decorations")
	local source = decorFolder and decorFolder:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		if not warnedMissingDecoration[name] then
			warnedMissingDecoration[name] = true
			warn(
				("[LiveEventService] Decoration model '%s' is missing under Workspace.Assets.Decorations - please run assets/models/decorations/%s.lua once in Studio (see assets/models/README.md)."):format(
					name,
					name
				)
			)
		end
		return nil
	end

	local clone = source:Clone()
	clone.Name = name
	clone.Parent = decorationTemplatesFolder
	source:Destroy()
	return clone
end

local playerDecorationDisplays: { [number]: Model } = {}

local function refreshDecorationDisplay(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local equippedId = PlayerDataService.GetEquippedCosmetics(player)["Decoration"]
	local existing = playerDecorationDisplays[player.UserId]

	if type(equippedId) ~= "string" or not DECORATION_MODEL_NAMES[equippedId] then
		if existing then
			existing:Destroy()
			playerDecorationDisplays[player.UserId] = nil
		end
		return
	end

	if existing and existing.Parent and existing.Name == equippedId then
		return -- bereits korrekt angezeigt
	end
	if existing then
		existing:Destroy()
		playerDecorationDisplays[player.UserId] = nil
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		return
	end

	local template = getDecorationTemplate(equippedId)
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Name = equippedId
	clone.Parent = plot

	local ok = pcall(function()
		clone:PivotTo(plot.PrimaryPart.CFrame * CFrame.new(-22, plot.PrimaryPart.Size.Y / 2 + 1, -22))
	end)
	if not ok then
		clone:Destroy()
		return
	end

	playerDecorationDisplays[player.UserId] = clone
end

-- // Slot-/Fairness-Zustand je Spieler (Abschnitt 1.2) -------------------------

--- Stellt sicher, dass der persistierte LiveEventState von `player` zum
--- AKTUELLEN Slot gehört - setzt Bilanz/Quest-Fortschritt zurück, sobald
--- entweder die Event-Id ODER der Slot-Start-Zeitstempel vom gespeicherten
--- Stand abweicht (deckt sowohl einen normalen Event-Wechsel als auch die
--- Wiederkehr DESSELBEN Events 3 Tage später ab - siehe Fairness-Regel
--- Abschnitt 1.2). Gibt den (ggf. frisch zurückgesetzten) State zurück.
local function ensureCurrentSlotState(player: Player): LiveEventState
	local slotStart = LiveEventConfig.GetSlotStart(os.time())
	local state = PlayerDataService.GetLiveEventState(player)

	if state.Currency.EventId ~= currentEventId or state.Currency.SlotStart ~= slotStart then
		local freshState: LiveEventState = {
			Currency = { EventId = currentEventId, SlotStart = slotStart, Balance = 0 },
			Quest = { EventId = currentEventId, SlotStart = slotStart, StepProgress = {}, Claimed = false },
			OwnedEventItems = state.OwnedEventItems, -- rein informativ, überlebt Resets bewusst (siehe Typ-Kommentar)
		}
		PlayerDataService.SetLiveEventState(player, freshState)
		return freshState
	end

	return state
end

-- // Event-Währung + Quest-Fortschritt (öffentlich, siehe PickupSpawner) -------

--- Schreibt `amount` (muss positiv sein) der aktuellen Event-Währung gut,
--- setzt bei Bedarf zuerst den Slot-Zustand zurück (Fairness-Regel) und
--- zählt automatisch auf den "CollectCurrency"-Quest-Schritt an (falls die
--- aktive Quest-Linie einen solchen Schritt hat). `reason` ist rein
--- informativ (Client-Toast/-FX-Auswahl, siehe EventUIController).
function LiveEventService.AwardEventCurrency(player: Player, amount: number, reason: string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end

	local state = ensureCurrentSlotState(player)
	state.Currency.Balance += amount
	PlayerDataService.SetLiveEventState(player, state)

	LiveEventRemotes.EventCurrencyChanged:FireClient(player, { Balance = state.Currency.Balance, Reason = reason })

	LiveEventService.AdvanceEventQuest(player, "CollectCurrency", amount)
end

--- Erhöht ALLE Quest-Schritte der aktiven Event-Quest-Linie, deren `Key`
--- `key` entspricht und noch nicht ihr Ziel erreicht haben, um `amount`
--- (auf das jeweilige Target geklemmt - kein Overflow). Pusht
--- EventQuestProgressUpdated je tatsächlich veränderter Schritt.
function LiveEventService.AdvanceEventQuest(player: Player, key: string, amount: number)
	if not PlayerDataService.IsDataLoaded(player) or not currentEventDef then
		return
	end
	if type(amount) ~= "number" or amount <= 0 then
		return
	end

	local state = ensureCurrentSlotState(player)
	if state.Quest.Claimed then
		return
	end

	local changed = false
	for index, step in ipairs(currentEventDef.QuestLine.Steps) do
		if step.Key == key then
			local progress = state.Quest.StepProgress[index] or 0
			if progress < step.Target then
				progress = math.min(step.Target, progress + amount)
				state.Quest.StepProgress[index] = progress
				changed = true

				LiveEventRemotes.EventQuestProgressUpdated:FireClient(player, {
					StepIndex = index,
					Progress = progress,
					Target = step.Target,
				})
			end
		end
	end

	if changed then
		PlayerDataService.SetLiveEventState(player, state)
	end
end

-- // GameEvents-Einhängepunkte (EIN zentraler Satz Abonnements, siehe Kopfkommentar) --

GameEvents.Connect(GameEvents.Events.SporeDelivered, function(player: Player, payload: { [string]: any })
	if not currentEventDef then
		return
	end
	local rawAmount = payload.Amount
	local sporeCount = if type(rawAmount) == "number" then rawAmount else 1
	local amount = sporeCount * currentEventDef.EarnPerGlowSpore
	if amount > 0 then
		LiveEventService.AwardEventCurrency(player, amount, "GlowSpore")
	end
end)

GameEvents.Connect(GameEvents.Events.RaidWon, function(player: Player, payload: { [string]: any })
	if not currentEventDef then
		return
	end
	local wavesCleared = payload.WavesCleared
	if type(wavesCleared) == "number" and wavesCleared > 0 and currentEventDef.EarnPerRaidWave > 0 then
		LiveEventService.AwardEventCurrency(player, wavesCleared * currentEventDef.EarnPerRaidWave, "RaidWave")
	end
	LiveEventService.AdvanceEventQuest(player, "SurviveRaid", 1)
end)

GameEvents.Connect(GameEvents.Events.BreedingCompleted, function(player: Player, _payload: { [string]: any })
	if not currentEventDef then
		return
	end
	local bonus = currentEventDef.EarnSpecial.BreedingCycle
	if type(bonus) == "number" and bonus > 0 then
		LiveEventService.AwardEventCurrency(player, bonus, "BreedingCycle")
		LiveEventService.AdvanceEventQuest(player, "BreedingCycle", 1)
	end
end)

-- // Server-getaktete Spezial-Ereignisse (Ghost Ship / Vent-Puls) -------------

local function forEachLoadedPlayer(fn: (Player) -> ())
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataService.IsDataLoaded(player) then
			task.spawn(fn, player)
		end
	end
end

local function triggerVentPulse()
	if not currentEventDef then
		return
	end
	local bonus = currentEventDef.EarnSpecial.VentPulse
	forEachLoadedPlayer(function(player: Player)
		if type(bonus) == "number" and bonus > 0 then
			LiveEventService.AwardEventCurrency(player, bonus, "VentPulse")
		end
		LiveEventService.AdvanceEventQuest(player, "VentPulse", 1)
	end)
end

local function triggerGhostShip()
	if not currentEventDef then
		return
	end
	local bonus = currentEventDef.EarnSpecial.GhostShipFound
	forEachLoadedPlayer(function(player: Player)
		if type(bonus) == "number" and bonus > 0 then
			LiveEventService.AwardEventCurrency(player, bonus, "GhostShipFound")
		end
		LiveEventService.AdvanceEventQuest(player, "GhostShipFound", 1)
	end)
end

local function stopSpecialLoop()
	if specialLoopThread then
		task.cancel(specialLoopThread)
		specialLoopThread = nil
	end
end

local function startSpecialLoop(eventDef: EventDefinition)
	stopSpecialLoop()

	if eventDef.Id == "VolcanicVent" then
		local interval = eventDef.Modifiers.VentPulseIntervalSeconds
		if type(interval) ~= "number" or interval <= 0 then
			interval = 480
		end
		specialLoopThread = task.spawn(function()
			while true do
				task.wait(interval)
				triggerVentPulse()
			end
		end)
	elseif eventDef.Id == "SpookyTide" then
		specialLoopThread = task.spawn(function()
			-- Einmal irgendwann innerhalb der ersten 10 Minuten des Slots -
			-- bewusst früh genug, dass auch kurze Spielsitzungen eine
			-- realistische Chance haben, es mitzuerleben.
			task.wait(rng:NextInteger(90, 600))
			triggerGhostShip()
		end)
	end
end

-- // Slot-Wechsel-Ablauf --------------------------------------------------------

local function buildStateForPlayer(player: Player): { [string]: any }?
	if not currentEventDef then
		return nil
	end

	local slotStart = LiveEventConfig.GetSlotStart(os.time())
	local slotEnd = LiveEventConfig.GetSlotEnd(os.time())
	local state = ensureCurrentSlotState(player)

	local shopItems = {}
	for _, item in ipairs(currentEventDef.ShopItems) do
		table.insert(shopItems, {
			Id = item.Id,
			DisplayName = item.DisplayName,
			Cost = item.Cost,
			Type = item.Type,
			Owned = state.OwnedEventItems[item.Id] == true,
		})
	end

	local steps = {}
	for index, step in ipairs(currentEventDef.QuestLine.Steps) do
		table.insert(steps, {
			Id = step.Id,
			Description = step.Description,
			Target = step.Target,
			Progress = state.Quest.StepProgress[index] or 0,
		})
	end

	return {
		EventId = currentEventDef.Id,
		DisplayName = currentEventDef.DisplayName,
		ColorPrimary = currentEventDef.ColorPrimary,
		ColorSecondary = currentEventDef.ColorSecondary,
		SlotStart = slotStart,
		SlotEnd = slotEnd,
		Now = os.time(),
		CurrencyId = currentEventDef.CurrencyId,
		CurrencyDisplayName = currentEventDef.CurrencyDisplayName,
		CurrencyGlyph = currentEventDef.CurrencyGlyph,
		CurrencyBalance = state.Currency.Balance,
		ShopItems = shopItems,
		QuestLine = {
			Title = currentEventDef.QuestLine.Title,
			Steps = steps,
			Claimed = state.Quest.Claimed,
			RewardTideCoins = currentEventDef.QuestLine.RewardTideCoins,
			RewardTitle = currentEventDef.QuestLine.RewardTitle,
		},
	}
end

local function broadcastEventChanged()
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataService.IsDataLoaded(player) then
			local ok, payload = pcall(buildStateForPlayer, player)
			if ok and payload then
				LiveEventRemotes.EventChanged:FireClient(player, payload)
			end
		end
	end
end

local function switchToEvent(newEventId: string, instant: boolean, broadcast: boolean)
	currentEventId = newEventId
	currentEventDef = LiveEventConfig.GetEvent(newEventId)

	if not currentEventDef then
		-- Sollte nie eintreten (nur validierte Ids erreichen diese
		-- Funktion), aber defensiv: auf Baseline zurückfallen statt mit
		-- nil-Referenzen weiterzurechnen.
		applyLighting(getBaselineLightingProfile(), instant)
		warn(("[LiveEventService] Unknown event id '%s' - falling back to baseline lighting."):format(newEventId))
		return
	end

	applyLighting(currentEventDef.Lighting, instant)
	updateParticleMood(currentEventDef.Particle)
	startSpecialLoop(currentEventDef)

	print(("[LiveEventService] Aktives Event: %s (Slot bis %s UTC)."):format(
		currentEventDef.DisplayName,
		os.date("!%Y-%m-%d %H:%M", LiveEventConfig.GetSlotEnd(os.time()))
	))

	if broadcast then
		broadcastEventChanged()
	end
end

local function runEventSchedulerLoop()
	while true do
		task.wait(EVENT_CHECK_INTERVAL_SECONDS)
		local desired = resolveCurrentEventId()
		if desired ~= currentEventId then
			switchToEvent(desired, false, true)
		end
	end
end

-- Initiale, sofortige (ungetweente) Anwendung beim Server-Start - kein
-- Broadcast nötig (beim allerersten require() sind praktisch nie schon
-- Spieler mit geladenen Daten verbunden).
switchToEvent(resolveCurrentEventId(), true, false)
task.spawn(runEventSchedulerLoop)

task.spawn(function()
	while true do
		task.wait(DECORATION_REFRESH_INTERVAL_SECONDS)
		forEachLoadedPlayer(refreshDecorationDisplay)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local display = playerDecorationDisplays[player.UserId]
	if display then
		display:Destroy()
	end
	playerDecorationDisplays[player.UserId] = nil
end)

-- // Öffentliche Getter (für IdleIncomeService/BreedingService/RaidService/
-- PickupSpawner/EventUIController - siehe jeweilige Kopfkommentare) -----------

--- Liefert die vollständige Definition des aktuell aktiven Events, oder nil
--- in dem extrem kurzen Fenster vor der allerersten Slot-Auflösung
--- (praktisch nie beobachtbar, siehe switchToEvent-Aufruf oben).
function LiveEventService.GetActiveEvent(): EventDefinition?
	return currentEventDef
end

function LiveEventService.GetActiveEventId(): string?
	return currentEventId
end

--- true, wenn `eventId` GENAU das aktuell aktive Event ist.
function LiveEventService.IsEventActive(eventId: string): boolean
	return currentEventId == eventId
end

--- Liefert `Modifiers[key]` des aktiven Events, oder `default`, falls das
--- aktive Event diesen Modifikator nicht definiert (z. B. weil er nur für
--- EIN bestimmtes Event gilt) - der zentrale Einhängepunkt für alle
--- anderen Services (Abschnitt 7b), damit RaidConfig/BuildingConfig/
--- BreedingConfig selbst NIE mutiert werden müssen.
function LiveEventService.GetModifier(key: string, default: any): any
	if not currentEventDef then
		return default
	end
	local value = currentEventDef.Modifiers[key]
	if value == nil then
		return default
	end
	return value
end

--- Kombinierter Einkommens-Multiplikator für EIN Gebäude (siehe
--- IdleIncomeService.computeIncomePerMinute) - berücksichtigt sowohl
--- globale Gebäude-Multiplikatoren (Frozen Current -10%, Treasure Tide
--- +25% Tide-Coin-Einkommen) als auch gebäudespezifische (Toxic Tide
--- FilterPlant ×1.5, Bloom GlowBuoyStation ×1.4).
function LiveEventService.GetBuildingIncomeMultiplier(buildingId: string): number
	if not currentEventDef then
		return 1
	end

	local modifiers = currentEventDef.Modifiers
	local multiplier = 1

	if type(modifiers.BuildingIncomeMultiplier) == "number" then
		multiplier *= modifiers.BuildingIncomeMultiplier
	end
	if type(modifiers.TideCoinIncomeMultiplier) == "number" then
		multiplier *= modifiers.TideCoinIncomeMultiplier
	end
	if buildingId == "FilterPlant" and type(modifiers.FilterPlantIncomeMultiplier) == "number" then
		multiplier *= modifiers.FilterPlantIncomeMultiplier
	end
	if buildingId == "GlowBuoyStation" and type(modifiers.GlowBuoyStationIncomeMultiplier) == "number" then
		multiplier *= modifiers.GlowBuoyStationIncomeMultiplier
	end

	return multiplier
end

-- // Client-Sync (LiveEventRemotes.GetEventState) ------------------------------

function LiveEventService.GetState(player: Player): { [string]: any }
	return buildStateForPlayer(player) or {}
end

-- // Event-Ei-Roll (klein, gewichtet - siehe VEREINFACHUNG im Kopfkommentar) ---

local function rollEventEgg(item: LiveEventConfig.ShopItem): (string?, string?)
	local creatureId = item.CreatureId
	if not creatureId or not currentEventDef then
		return nil, nil
	end

	-- Gewichtete Roll-Infrastruktur (aktuell immer genau 1 Eintrag mit
	-- Gewicht 100, siehe Kopfkommentar) - identisches Muster zu
	-- BreedingService.rollWeightedRarity, nur mit einem Kreaturen-Pool
	-- statt eines Rarity-Pools.
	local weights: { [string]: number } = { [creatureId] = 100 }
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight += weight
	end
	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	local resultId = creatureId
	for id, weight in pairs(weights) do
		cumulative += weight
		if roll <= cumulative then
			resultId = id
			break
		end
	end

	local creatureDef = LiveEventConfig.GetEventCreature(currentEventDef.Id, resultId)
	local rarity = creatureDef and creatureDef.Rarity or "Rare"
	return resultId, rarity
end

-- // Event-Shop-Kauf ------------------------------------------------------------

export type ShopPurchaseResult = {
	Success: boolean,
	Reason: string?,
	ItemId: string?,
	NewBalance: number?,
	CreatureId: string?,
	Rarity: string?,
	NewTideCoinBalance: number?,
}

--- Validiert und schließt einen Event-Shop-Kauf vollständig serverseitig ab.
--- `itemId` ist ein unvertrauter, angeblicher Client-Wert - wird komplett
--- neu gegen den Shop-Katalog des AKTUELL aktiven Events geprüft (ein
--- Artikel eines bereits beendeten Events ist NICHT mehr kaufbar, selbst
--- wenn der Client noch ein altes Panel offen hat).
function LiveEventService.RequestPurchaseShopItem(player: Player, itemId: any): ShopPurchaseResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if not currentEventDef then
		return { Success = false, Reason = "NoActiveEvent" }
	end
	if type(itemId) ~= "string" then
		return { Success = false, Reason = "UnknownItem" }
	end

	local item: LiveEventConfig.ShopItem? = nil
	for _, candidate in ipairs(currentEventDef.ShopItems) do
		if candidate.Id == itemId then
			item = candidate
			break
		end
	end
	if not item then
		return { Success = false, Reason = "UnknownItem" }
	end

	local state = ensureCurrentSlotState(player)
	if state.Currency.Balance < item.Cost then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	state.Currency.Balance -= item.Cost
	PlayerDataService.SetLiveEventState(player, state)
	LiveEventRemotes.EventCurrencyChanged:FireClient(player, { Balance = state.Currency.Balance, Reason = "Purchase" })

	local result: ShopPurchaseResult = { Success = true, ItemId = item.Id, NewBalance = state.Currency.Balance }

	if item.Type == "CreatureEgg" then
		local creatureId, rarity = rollEventEgg(item)
		if not creatureId or not rarity then
			-- Sollte laut Konfiguration nicht passieren - Kauf rückgängig
			-- machen statt eine Kreatur ohne Rarity ins Inventar zu buchen.
			state.Currency.Balance += item.Cost
			PlayerDataService.SetLiveEventState(player, state)
			return { Success = false, Reason = "EggRollFailed" }
		end

		local instance = PlayerDataService.AddCreatureToInventory(player, { CreatureId = creatureId, Rarity = rarity })
		if not instance then
			state.Currency.Balance += item.Cost
			PlayerDataService.SetLiveEventState(player, state)
			return { Success = false, Reason = "PersistenceFailed" }
		end

		result.CreatureId = creatureId
		result.Rarity = rarity
		LiveEventService.AdvanceEventQuest(player, "HatchEgg", 1)
	elseif item.Type == "Cosmetic" then
		PlayerDataService.AddOwnedCosmetic(player, item.Id)
		-- Sofort ausrüsten (kinderfreundliche Direkt-Belohnung, siehe
		-- Kopfkommentar "Event-Deko-Anzeige") - ein separates Ausrüsten-UI
		-- ist nicht Teil dieses Systems.
		PlayerDataService.SetEquippedCosmetic(player, item.CosmeticSlot or "Decoration", item.Id)
	elseif item.Type == "Currency" then
		local _, newTideBalance = PlayerDataService.AddCurrency(player, "TideCoins", item.ConvertsToTideCoins or 0)
		result.NewTideCoinBalance = newTideBalance
	end

	PlayerDataService.AddOwnedEventItem(player, item.Id)
	return result
end

-- // Event-Quest-Linie: Belohnung abholen ---------------------------------------

export type ClaimEventQuestResult = {
	Success: boolean,
	Reason: string?,
	RewardTideCoins: number?,
	RewardTitle: string?,
	NewTideCoinBalance: number?,
}

function LiveEventService.RequestClaimEventQuest(player: Player): ClaimEventQuestResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if not currentEventDef then
		return { Success = false, Reason = "NoActiveEvent" }
	end

	local state = ensureCurrentSlotState(player)
	if state.Quest.Claimed then
		return { Success = false, Reason = "AlreadyClaimed" }
	end

	for index, step in ipairs(currentEventDef.QuestLine.Steps) do
		local progress = state.Quest.StepProgress[index] or 0
		if progress < step.Target then
			return { Success = false, Reason = "NotCompleted" }
		end
	end

	state.Quest.Claimed = true
	PlayerDataService.SetLiveEventState(player, state)

	local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", currentEventDef.QuestLine.RewardTideCoins)
	PlayerDataService.AddUnlockedTitle(player, currentEventDef.QuestLine.RewardTitle)

	return {
		Success = true,
		RewardTideCoins = currentEventDef.QuestLine.RewardTideCoins,
		RewardTitle = currentEventDef.QuestLine.RewardTitle,
		NewTideCoinBalance = newBalance,
	}
end

return LiveEventService
