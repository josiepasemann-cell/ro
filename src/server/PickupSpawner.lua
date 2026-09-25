--[[
	Abyssara – Deep Tide Tycoon
	Modul: PickupSpawner
	Zuständigkeit:
		Lässt auf jedem Spieler-Plot periodisch begrenzt viele, leuchtende
		"Glow Spore"-Pickups spawnen (GDD Abschnitt 3: "Sammelt 'Glow Spores'
		/ Bioluminiszenz-Ressourcen ..."), macht sie über ein
		`ProximityPrompt` aufhebbar (funktioniert plattformübergreifend ohne
		Zusatzcode: PC-Taste, automatischer Touch-Button auf Mobile,
		Gamepad-Button - siehe Roblox-Engine-Verhalten von ProximityPrompt)
		und bringt aufgehobene Sporen über HeldItemService.HoldItem sichtbar
		in die Hand des Spielers.

		Bringt außerdem ein Abgabe-`ProximityPrompt` an jeder platzierten
		GlowBuoyStation eines Spielers an (siehe PlacementService/
		BuildingConfig - NICHT von diesem Modul selbst platziert, nur
		beobachtet): Abgeben einer gehaltenen Glow Spore dort gewährt einen
		Bonus über PlayerDataService.AddCurrency("TideCoins", ...).

		Validiert serverseitig sowohl die Distanz (Prompt-Reichweite PLUS
		erneuter Server-Check) als auch das Eigentum (nur die eigenen Sporen
		des jeweiligen Plot-Eigentümers lassen sich aufheben) - siehe
		Sicherheitsprinzip unten.

		Wird eine gehaltene Glow Spore fallen gelassen (HeldItemService.
		DropHeld, z. B. über die "G"-Taste im Client), abonniert dieses
		Modul `HeldItemService.ItemDropped` und registriert sie automatisch
		wieder als aufhebbares Welt-Pickup auf dem Plot des Spielers.

	Sicherheitsprinzip (kein Client-Trust):
		ProximityPrompt.Triggered liefert als ersten Parameter den
		auslösenden `Player` direkt von der Roblox-Engine (nicht vom Client
		fälschbar). Trotzdem wird JEDE Aktion hier zusätzlich serverseitig
		geprüft: Eigentümer-Attribut (`OwnerUserId`) gegen `player.UserId`,
		erneute Distanzmessung server-seitig (HumanoidRootPart <-> Pickup/
		Station), und beim Aufheben ein sofortiges `prompt.Enabled = false`
		gegen doppeltes Auslösen während des Übergangs.

	Eigene, in sich geschlossene Asset-Vorlagen-Beschaffung:
		Analog zu AssetTemplateSetup.lua (das dieses Modul bewusst NICHT
		anfasst/erweitert, siehe Dateibesitz-Vorgabe), promotet dieses Modul
		selbst das einmalig in Studio ausgeführte Buildscript-Ergebnis
		`Workspace.Assets.Pickups.GlowSporePickup` (siehe
		assets/models/pickups/GlowSporePickup.lua) zu einer wiederverwendbaren
		Vorlage unter `ReplicatedStorage.AssetTemplates.Pickups`.

	Rojo-Einhängepunkt:
		src/server/PickupSpawner.lua -> ServerScriptService.PickupSpawner
		(reines Logik-Modul, analog zum PlacementService/PlacementServer-
		Muster - die Remote-/Join-/Leave-Verdrahtung übernimmt
		HeldItemServer.server.lua über PickupSpawner.OnPlayerAdded/
		OnPlayerRemoving.)
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local HeldItemService = require(script.Parent:WaitForChild("HeldItemService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))
local HeldItemConfig = require(ReplicatedStorage:WaitForChild("HeldItemConfig"))

local PickupSpawner = {}

local GLOW_SPORE_KIND = "GlowSpore"
local PLOT_WAIT_TIMEOUT_SECONDS = 15

local rng = Random.new()

-- // Eigene Asset-Vorlagen-Beschaffung (Pickups) ------------------------------

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

local pickupTemplatesFolder = getOrCreateFolder(getOrCreateFolder(ReplicatedStorage, "AssetTemplates"), "Pickups")

local function promotePickupTemplate(name: string)
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local pickupsSource = assetsFolder and assetsFolder:FindFirstChild("Pickups")
	local source = pickupsSource and pickupsSource:FindFirstChild(name)

	if not source or not source:IsA("Model") then
		if not pickupTemplatesFolder:FindFirstChild(name) then
			warn(
				("[PickupSpawner] '%s' is missing under Workspace.Assets.Pickups - please run assets/models/pickups/%s.lua once in Studio (see assets/models/README.md)."):format(
					name,
					name
				)
			)
		end
		return
	end

	local clone = source:Clone()
	clone.Name = name

	local existingTemplate = pickupTemplatesFolder:FindFirstChild(name)
	if existingTemplate then
		existingTemplate:Destroy()
	end
	clone.Parent = pickupTemplatesFolder

	source:Destroy()
	print(("[PickupSpawner] Template '%s' ready under %s."):format(name, pickupTemplatesFolder:GetFullName()))
end

promotePickupTemplate("GlowSporePickup")
-- Live-Event-Pickups (docs/content-update-1.md Abschnitt 1.3 + 7a): gleiches
-- "einmal in Studio bauen, hier promoten"-Prinzip wie GlowSporePickup oben.
-- Beide sind laut assets/models/README.md optional/event-exklusiv - fehlen
-- sie (3D-Agent noch nicht fertig), warnt promotePickupTemplate bereits
-- defensiv und die jeweilige Variante fällt unten auf die normale Glow
-- Spore zurück, statt den Server abstürzen zu lassen.
promotePickupTemplate("SunkenChest")
promotePickupTemplate("FrozenSpore")

local function getGlowSporeTemplate(): Model?
	local model = pickupTemplatesFolder:FindFirstChild("GlowSporePickup")
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function getSunkenChestTemplate(): Model?
	local model = pickupTemplatesFolder:FindFirstChild("SunkenChest")
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function getFrozenSporeTemplate(): Model?
	local model = pickupTemplatesFolder:FindFirstChild("FrozenSpore")
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- // Pro-Spieler-Laufzeitzustand ----------------------------------------------

local activeUsers: { [number]: boolean } = {}
local livePickupsByUser: { [number]: { Model } } = {}

local function countLivePickups(userId: number): number
	local list = livePickupsByUser[userId]
	if not list then
		return 0
	end
	for index = #list, 1, -1 do
		local model = list[index]
		if not model or not model.Parent then
			table.remove(list, index)
		end
	end
	return #list
end

-- // Glow-Spore-Pickups: Aufheben --------------------------------------------

--- `itemKind` ist standardmäßig `GLOW_SPORE_KIND` (normale/Toxic-Tide-
--- Spore-Variante - beide teilen sich denselben HeldItemService-ItemKind,
--- da die Toxic-Variante nur ein zusätzliches `TideCoinValueMultiplier`-
--- Attribut trägt, siehe spawnGlowSporeForPlayer). `onThawedFrozenSpore`
--- wird nach erfolgreichem Aufheben aufgerufen, WENN `itemKind ==
--- "FrozenSpore"` - siehe attachFrozenSporePrompt (Live-Event-Einhängepunkt,
--- docs/content-update-1.md Abschnitt 1.3 "Thaw Watch"-Quest).
local function onPickupTriggered(player: Player, pickup: Model, prompt: ProximityPrompt, itemKind: string?)
	local resolvedKind = itemKind or GLOW_SPORE_KIND

	if not pickup.Parent or not prompt.Enabled then
		return
	end

	local ownerUserId = pickup:GetAttribute("OwnerUserId")
	if ownerUserId ~= player.UserId then
		-- Besitz-Validierung: nur die eigenen Sporen des Plot-Eigentümers
		-- lassen sich aufheben (siehe Auftrag).
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local anchorPart = pickup.PrimaryPart or pickup:FindFirstChildWhichIsA("BasePart")
	if not rootPart or not anchorPart then
		return
	end

	-- Zusätzliche Server-Distanzprüfung (Verteidigung in der Tiefe on top
	-- von ProximityPrompt.MaxActivationDistance selbst, siehe Auftrag).
	local distance = (rootPart.Position - anchorPart.Position).Magnitude
	if distance > HeldItemConfig.Pickup.PromptMaxActivationDistance + 3 then
		return
	end

	prompt.Enabled = false -- verhindert doppeltes Auslösen während des Übergangs

	local success = HeldItemService.HoldItem(player, resolvedKind, pickup, {
		Reparent = true,
	})

	if not success then
		prompt.Enabled = true
		return
	end

	-- Das Modell wandert per Reparent direkt in die Hand des Spielers - der
	-- Prompt selbst (bislang Kind desselben Parts) wird nicht mehr gebraucht
	-- und würde sonst sichtbar am gehaltenen Item mitreisen.
	task.defer(function()
		if prompt then
			prompt:Destroy()
		end
	end)

	if resolvedKind == "FrozenSpore" then
		-- "Auftauen" = erfolgreiches Aufheben nach voller Halte-Dauer (siehe
		-- attachFrozenSporePrompt) - Event-Währung/Quest-Fortschritt laufen
		-- hier, NICHT erst bei der GlowBuoyStation-Abgabe (Frost Shards fürs
		-- reine Sammeln kommen trotzdem noch zusätzlich über SporeDelivered
		-- bei der Abgabe, siehe onDepositTriggered).
		local eventDef = LiveEventService.GetActiveEvent()
		local bonus = eventDef and eventDef.EarnSpecial.FrozenSporeThawed
		if type(bonus) == "number" and bonus > 0 then
			LiveEventService.AwardEventCurrency(player, bonus, "FrozenSporeThawed")
		end
		LiveEventService.AdvanceEventQuest(player, "FrozenSporeThawed", 1)
	end
end

local function attachPickupPrompt(pickup: Model)
	local part = pickup.PrimaryPart or pickup:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	if part:FindFirstChild("PickupPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Glow Spore"
	prompt.HoldDuration = HeldItemConfig.Pickup.PromptHoldDurationSeconds
	prompt.MaxActivationDistance = HeldItemConfig.Pickup.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		onPickupTriggered(player, pickup, prompt)
	end)
end

-- // Frozen-Spore-Auftauen (Frozen Current, docs/content-update-1.md
-- Abschnitt 1.3) ---------------------------------------------------------------
-- Modell-Vertrag (assets/models/README.md, Pickups-Abschnitt): 3 Kind-Models
-- `IcyShellState`/`CrackedState`/`OpenState`, Reihenfolge in Attribut
-- `ThawStates`, per Transparency togglebar (nie zerstören). `Body`
-- (PrimaryPart) selbst startet bei Transparency 1, bis `OpenState` erreicht
-- ist. Das "Auftauen" wird elegant durch ProximityPrompt.HoldDuration
-- realisiert (3s Halten = Auftauen, Roblox feuert `Triggered` erst NACH der
-- vollen Haltezeit) - kein eigener Timer-Code nötig.

local function applyThawState(pickup: Model, targetStateName: string)
	local statesAttribute = pickup:GetAttribute("ThawStates")
	local order: { string } = {}
	if type(statesAttribute) == "string" then
		for name in statesAttribute:gmatch("[^,]+") do
			table.insert(order, name)
		end
	end
	if #order == 0 then
		order = { "IcyShellState", "CrackedState", "OpenState" }
	end

	for _, stateName in ipairs(order) do
		local stateModel = pickup:FindFirstChild(stateName)
		if stateModel then
			local targetTransparency = if stateName == targetStateName then 0 else 1
			for _, descendant in ipairs(stateModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Transparency = targetTransparency
				end
			end
		end
	end

	local body = pickup.PrimaryPart
	if body and body:IsA("BasePart") then
		body.Transparency = if targetStateName == "OpenState" then 0 else 1
	end
end

local function attachFrozenSporePrompt(pickup: Model)
	local part = pickup.PrimaryPart or pickup:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	if part:FindFirstChild("ThawPrompt") then
		return
	end

	applyThawState(pickup, "IcyShellState")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ThawPrompt"
	prompt.ActionText = "Thaw"
	prompt.ObjectText = "Frozen Spore"
	prompt.HoldDuration = LiveEventService.GetModifier("FrozenSporeThawSeconds", 3)
	prompt.MaxActivationDistance = HeldItemConfig.Pickup.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.PromptButtonHoldBegan:Connect(function(_player: Player)
		if pickup.Parent and prompt.Enabled then
			applyThawState(pickup, "CrackedState")
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(_player: Player)
		-- Losgelassen, BEVOR die volle Haltezeit erreicht war (sonst wäre
		-- bereits `Triggered` gefeuert und `prompt.Enabled` false) - zurück
		-- auf den ungetauten Ausgangszustand.
		if pickup.Parent and prompt.Enabled then
			applyThawState(pickup, "IcyShellState")
		end
	end)
	prompt.Triggered:Connect(function(player: Player)
		applyThawState(pickup, "OpenState")
		onPickupTriggered(player, pickup, prompt, "FrozenSpore")
	end)
end

-- // Glow-Spore-Pickups: Spawnen ----------------------------------------------

local function getOrCreatePickupsFolder(plot: Model): Folder
	return getOrCreateFolder(plot, "Pickups")
end

--- Entscheidet, ob DIESER Spawn statt einer normalen Glow Spore eine
--- Event-Varianten-Spore wird (docs/content-update-1.md Abschnitt 1.3:
--- Toxic Tide "Toxic Spore" ×3 Wert, Frozen Current "Frozen Spore" ×4 Wert
--- + Auftau-Rätsel). Fällt defensiv auf "Normal" zurück, wenn das jeweilige
--- Event-Modell (noch) fehlt.
local function pickSporeVariant(): ("Normal" | "Toxic" | "Frozen")
	if LiveEventService.IsEventActive("ToxicTide") then
		local chance = LiveEventService.GetModifier("ToxicSporeChance", 0)
		if type(chance) == "number" and rng:NextNumber() < chance then
			return "Toxic"
		end
	elseif LiveEventService.IsEventActive("FrozenCurrent") then
		local chance = LiveEventService.GetModifier("FrozenSporeChance", 0)
		if type(chance) == "number" and rng:NextNumber() < chance and getFrozenSporeTemplate() then
			return "Frozen"
		end
	end
	return "Normal"
end

local function spawnGlowSporeForPlayer(player: Player, plot: Model)
	local userId = player.UserId
	local list = livePickupsByUser[userId]
	if not list then
		list = {}
		livePickupsByUser[userId] = list
	end

	if countLivePickups(userId) >= HeldItemConfig.Pickup.MaxPerPlot then
		return
	end

	local variant = pickSporeVariant()
	local template = if variant == "Frozen" then getFrozenSporeTemplate() else getGlowSporeTemplate()
	if not template then
		return
	end

	local platform = plot.PrimaryPart
	if not platform then
		return
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)

	local angle = rng:NextNumber() * math.pi * 2
	local radius = rng:NextNumber(HeldItemConfig.Pickup.MinSpawnRadiusStuds, HeldItemConfig.Pickup.SpawnRadiusStuds)
	local localOffset = Vector3.new(math.cos(angle) * radius, platform.Size.Y / 2 + 1.5, math.sin(angle) * radius)

	local spore = template:Clone()
	spore.Name = if variant == "Frozen" then "FrozenSporePickup" else "GlowSporePickup"
	spore:SetAttribute("OwnerUserId", userId)

	if variant == "Toxic" then
		spore:SetAttribute("TideCoinValueMultiplier", LiveEventService.GetModifier("ToxicSporeValueMultiplier", 3))
		local body = spore.PrimaryPart
		if body and body:IsA("BasePart") then
			-- Rein visuelle Unterscheidung ("größere" Toxic Spore laut
			-- Design-Dokument) - reuses das normale GlowSporePickup-Modell,
			-- kein eigenes 3D-Asset in der Bauliste (Abschnitt 7a).
			body.Size *= 1.3
		end
	elseif variant == "Frozen" then
		spore:SetAttribute("TideCoinValueMultiplier", LiveEventService.GetModifier("FrozenSporeValueMultiplier", 4))
	end

	spore.Parent = pickupsFolder
	spore:PivotTo(platform.CFrame * CFrame.new(localOffset))

	if variant == "Frozen" then
		attachFrozenSporePrompt(spore)
	else
		attachPickupPrompt(spore)
	end

	table.insert(list, spore)
end

-- // Spore Shower (purchasable ability, see AbilityService.GrantSporeShower) ---
-- Spawns `count` NORMAL Glow Spores scattered on `player`'s own plot,
-- reusing the exact same reachable, "not inside buildings" scatter geometry
-- as spawnGlowSporeForPlayer above (same radius range around the plot's
-- platform center) - but BYPASSES HeldItemConfig.Pickup.MaxPerPlot on
-- purpose (Auftrag: "even above the normal per-plot spore cap, then the cap
-- applies again as they get collected" - the cap is only enforced going
-- FORWARD by spawnGlowSporeForPlayer's own countLivePickups check, it never
-- retroactively removes already-spawned spores). Always the plain "Normal"
-- variant (no event-variant roll) - a paid convenience shouldn't depend on
-- live-event RNG. Returns the number actually spawned (0 if the plot/
-- template isn't ready, e.g. the buildscript was never run in Studio).
function PickupSpawner.SpawnBonusSpores(player: Player, count: number): number
	local plot = PlotRegistry.GetPlot(player)
	if not plot then
		return 0
	end

	local platform = plot.PrimaryPart
	local template = getGlowSporeTemplate()
	if not platform or not template then
		return 0
	end

	local userId = player.UserId
	local list = livePickupsByUser[userId]
	if not list then
		list = {}
		livePickupsByUser[userId] = list
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)
	local spawnedCount = 0

	for _ = 1, count do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(HeldItemConfig.Pickup.MinSpawnRadiusStuds, HeldItemConfig.Pickup.SpawnRadiusStuds)
		local localOffset = Vector3.new(math.cos(angle) * radius, platform.Size.Y / 2 + 1.5, math.sin(angle) * radius)

		local spore = template:Clone()
		spore.Name = "GlowSporePickup"
		spore:SetAttribute("OwnerUserId", userId)
		spore.Parent = pickupsFolder
		spore:PivotTo(platform.CFrame * CFrame.new(localOffset))

		attachPickupPrompt(spore)
		table.insert(list, spore)
		spawnedCount += 1
	end

	return spawnedCount
end

-- // GlowBuoyStation: Abgabe --------------------------------------------------

-- Sowohl die normale/Toxic-Tide-Spore (ItemKind GLOW_SPORE_KIND, siehe
-- Kopfkommentar von onPickupTriggered) als auch eine bereits aufgetaute
-- Frozen Spore (ItemKind "FrozenSpore") sind an der GlowBuoyStation
-- abgebbar - beide tragen optional ein `TideCoinValueMultiplier`-Attribut
-- (siehe spawnGlowSporeForPlayer), das hier den Basislohn skaliert.
local DEPOSITABLE_ITEM_KINDS: { [string]: boolean } = { [GLOW_SPORE_KIND] = true, FrozenSpore = true }

local function onDepositTriggered(player: Player, station: Model)
	local held = HeldItemService.GetHeld(player)
	if not held or not DEPOSITABLE_ITEM_KINDS[held.ItemKind] then
		-- Nichts (Passendes) zum Abgeben - keine Aktion, kein Fehlerzustand.
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local stationPart = station.PrimaryPart
	if not rootPart or not stationPart then
		return
	end

	local distance = (rootPart.Position - stationPart.Position).Magnitude
	if distance > HeldItemConfig.Deposit.PromptMaxActivationDistance + 3 then
		return
	end

	-- Live-Event-Wert-Multiplikator (Toxic Spore ×3 / Frozen Spore ×4, siehe
	-- Kopfkommentar oben) VOR dem Zerstören des Modells auslesen.
	local valueMultiplier = held.Model:GetAttribute("TideCoinValueMultiplier")
	if type(valueMultiplier) ~= "number" or valueMultiplier <= 0 then
		valueMultiplier = 1
	end

	local consumedKind, consumedModel = HeldItemService.ConsumeHeld(player)
	if not consumedKind then
		return
	end
	if consumedModel then
		consumedModel:Destroy()
	end

	local reward = math.floor(HeldItemConfig.Deposit.TideCoinsReward * valueMultiplier + 0.5)
	local ok = PlayerDataService.AddCurrency(player, "TideCoins", reward)
	if not ok then
		warn(("[PickupSpawner] AddCurrency for %s (spore deposit) failed."):format(player.Name))
		return
	end

	-- GameEvents-Einhängepunkt (Auftrag Punkt 1): QuestService UND
	-- LiveEventService (1 Event-Währung/Glow Spore, siehe dortiger
	-- Kopfkommentar) zählen hierüber die "Liefere N Glow Spores ab"-
	-- Tagesquest bzw. die Event-Währungsbilanz - siehe GameEvents-
	-- Kopfkommentar. NUR bei tatsächlich erfolgreicher Gutschrift gefeuert.
	GameEvents.Fire(GameEvents.Events.SporeDelivered, player, { Amount = 1 })
end

local function attachDepositPrompt(station: Model)
	local part = station.PrimaryPart or station:FindFirstChild("MainOrb") or station:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	if part:FindFirstChild("DepositPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ActionText = "Deposit"
	prompt.ObjectText = "Glow Buoy Station"
	prompt.HoldDuration = HeldItemConfig.Deposit.PromptHoldDurationSeconds
	prompt.MaxActivationDistance = HeldItemConfig.Deposit.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		onDepositTriggered(player, station)
	end)
end

--- Durchsucht die platzierten Gebäude von `player` (PlotRegistry/
--- PlacementService - hier NICHT selbst platziert, nur beobachtet) nach
--- GlowBuoyStation-Instanzen und bringt dort - idempotent - ein
--- Abgabe-Prompt an. Wird pro Spawn-Tick erneut aufgerufen statt nur einmal
--- per ChildAdded, um jede mögliche Reihenfolge-Race zwischen diesem Modul
--- und PlacementServer.server.lua beim Join sicher abzudecken.
local function ensureDepositPrompts(player: Player)
	local buildingsFolder = PlotRegistry.GetBuildingsFolder(player)
	if not buildingsFolder then
		return
	end
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("BuildingId") == "GlowBuoyStation" then
			attachDepositPrompt(child)
		end
	end
end

-- // Fallenlassen: gedropptes Item wird wieder zum Pickup ---------------------

HeldItemService.ItemDropped:Connect(function(player: Player, model: Model, itemKind: string, _dropCFrame: CFrame)
	if not DEPOSITABLE_ITEM_KINDS[itemKind] then
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot then
		-- Kein Plot (mehr) vorhanden (z. B. Spieler verlässt gerade) - das
		-- Item wurde von HeldItemService bereits sichtbar in die Welt
		-- gelegt, ohne Plot-Zuordnung aber nicht sinnvoll nachverfolgbar.
		model:Destroy()
		return
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)
	-- Eine fallengelassene Frozen Spore war beim Aufheben bereits vollständig
	-- aufgetaut (siehe attachFrozenSporePrompt) - verhält sich ab hier wie
	-- eine normale Spore (inkl. GLOW_SPORE_KIND beim nächsten Aufheben, das
	-- bereits gesetzte TideCoinValueMultiplier-Attribut bleibt erhalten).
	model.Name = "GlowSporePickup"
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = pickupsFolder

	attachPickupPrompt(model)

	local list = livePickupsByUser[player.UserId]
	if not list then
		list = {}
		livePickupsByUser[player.UserId] = list
	end
	table.insert(list, model)
end)

-- // Sunken Chest (Treasure Tide, docs/content-update-1.md Abschnitt 1.3) -----
-- Eigener, einfacherer Ablauf als Glow Spore: kein Halten/Abgeben über
-- HeldItemService - ein einzelnes "Öffnen"-ProximityPrompt gewährt die
-- Belohnung sofort und zerstört die Truhe. Höchstens EINE lebende Truhe pro
-- Spieler gleichzeitig, neu bestückt frühestens
-- `SunkenChestSpawnIntervalSeconds` (Standard 1h) nach der letzten - siehe
-- maybeSpawnSunkenChest.

local liveSunkenChestByUser: { [number]: Model } = {}
local lastSunkenChestSpawnAt: { [number]: number } = {}

local function onSunkenChestTriggered(player: Player, chest: Model, prompt: ProximityPrompt)
	if not chest.Parent or not prompt.Enabled then
		return
	end

	local ownerUserId = chest:GetAttribute("OwnerUserId")
	if ownerUserId ~= player.UserId then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local anchorPart = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
	if not rootPart or not anchorPart then
		return
	end

	local distance = (rootPart.Position - anchorPart.Position).Magnitude
	if distance > HeldItemConfig.Pickup.PromptMaxActivationDistance + 3 then
		return
	end

	if not LiveEventService.IsEventActive("TreasureTide") then
		-- Event ist zwischen Anzeige und Klick zu Ende gegangen (12h-Slot-
		-- Wechsel) - Truhe kommentarlos abräumen statt noch zu belohnen,
		-- konsistent mit der Fairness-Regel (Abschnitt 1.2: keine
		-- Event-Belohnungen außerhalb des zugehörigen Slots).
		chest:Destroy()
		liveSunkenChestByUser[player.UserId] = nil
		return
	end

	prompt.Enabled = false

	local eventDef = LiveEventService.GetActiveEvent()
	local tideCoinsReward = (eventDef and eventDef.Modifiers.SunkenChestValueTideCoins) or 150
	local ok = PlayerDataService.AddCurrency(player, "TideCoins", tideCoinsReward)
	if ok then
		local bonus = eventDef and eventDef.EarnSpecial.SunkenChestOpened
		if type(bonus) == "number" and bonus > 0 then
			LiveEventService.AwardEventCurrency(player, bonus, "SunkenChestOpened")
		end
		LiveEventService.AdvanceEventQuest(player, "SunkenChestOpened", 1)
	end

	chest:Destroy()
	liveSunkenChestByUser[player.UserId] = nil
end

local function attachSunkenChestPrompt(chest: Model)
	local part = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Sunken Chest"
	prompt.HoldDuration = HeldItemConfig.Pickup.PromptHoldDurationSeconds
	prompt.MaxActivationDistance = HeldItemConfig.Pickup.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		onSunkenChestTriggered(player, chest, prompt)
	end)
end

--- Spawnt (höchstens 1x/Stunde je Spieler, siehe Kopfkommentar) eine Sunken
--- Chest auf dem Plot, WENN Treasure Tide aktiv ist. Räumt eine bereits
--- vorhandene, noch nicht geöffnete Truhe ab, sobald das Event endet (siehe
--- Fairness-Regel Abschnitt 1.2).
local function maybeSpawnSunkenChest(player: Player, plot: Model)
	local userId = player.UserId
	local existing = liveSunkenChestByUser[userId]
	if existing and not existing.Parent then
		existing = nil
		liveSunkenChestByUser[userId] = nil
	end

	if not LiveEventService.IsEventActive("TreasureTide") then
		if existing then
			existing:Destroy()
			liveSunkenChestByUser[userId] = nil
		end
		return
	end

	if existing then
		return
	end

	local interval = LiveEventService.GetModifier("SunkenChestSpawnIntervalSeconds", 3600)
	if os.time() - (lastSunkenChestSpawnAt[userId] or 0) < interval then
		return
	end

	local template = getSunkenChestTemplate()
	local platform = plot.PrimaryPart
	if not template or not platform then
		return
	end

	local pickupsFolder = getOrCreatePickupsFolder(plot)
	local angle = rng:NextNumber() * math.pi * 2
	local radius = rng:NextNumber(HeldItemConfig.Pickup.MinSpawnRadiusStuds, HeldItemConfig.Pickup.SpawnRadiusStuds)
	local localOffset = Vector3.new(math.cos(angle) * radius, platform.Size.Y / 2 + 1.5, math.sin(angle) * radius)

	local chest = template:Clone()
	chest.Name = "SunkenChestPickup"
	chest:SetAttribute("OwnerUserId", userId)
	chest.Parent = pickupsFolder
	chest:PivotTo(platform.CFrame * CFrame.new(localOffset))

	attachSunkenChestPrompt(chest)

	liveSunkenChestByUser[userId] = chest
	lastSunkenChestSpawnAt[userId] = os.time()
end

-- // Pro-Spieler-Spawn-Loop ----------------------------------------------------

local function waitForPlot(player: Player): Model?
	local waited = 0
	while activeUsers[player.UserId] do
		local plot = PlotRegistry.GetPlot(player)
		if plot then
			return plot
		end
		if waited >= PLOT_WAIT_TIMEOUT_SECONDS then
			return nil
		end
		task.wait(1)
		waited += 1
	end
	return nil
end

local function plotSpawnLoop(player: Player)
	local plot = waitForPlot(player)
	if not plot then
		return
	end

	while activeUsers[player.UserId] and plot.Parent do
		ensureDepositPrompts(player)
		spawnGlowSporeForPlayer(player, plot)
		maybeSpawnSunkenChest(player, plot)
		task.wait(HeldItemConfig.Pickup.SpawnCheckIntervalSeconds)
	end
end

-- // Öffentliche API (Join-/Leave-Verdrahtung durch HeldItemServer.server.lua) -

function PickupSpawner.OnPlayerAdded(player: Player)
	activeUsers[player.UserId] = true
	livePickupsByUser[player.UserId] = {}
	task.spawn(plotSpawnLoop, player)
end

function PickupSpawner.OnPlayerRemoving(player: Player)
	activeUsers[player.UserId] = nil
	-- Die Pickup-Instanzen selbst liegen unter `plot.Pickups` und werden
	-- automatisch mit dem gesamten Plot zerstört, sobald PlotRegistry.
	-- ReleasePlot(player) läuft (siehe PlacementServer.server.lua) - hier
	-- nur die reine Laufzeit-Buchführung aufräumen.
	livePickupsByUser[player.UserId] = nil
	liveSunkenChestByUser[player.UserId] = nil
	lastSunkenChestSpawnAt[player.UserId] = nil
end

-- Kein eigenständiges PlayerAdded/PlayerRemoving-Binding hier (anders als
-- z. B. PlayerDataService) - die Join-/Leave-Verdrahtung inkl. bereits
-- verbundener Spieler übernimmt bewusst zentral HeldItemServer.server.lua
-- (gleiches Aufteilungsmuster wie PlacementService/PlacementServer.server.lua).

return PickupSpawner
