--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: CodexUIController (LocalScript)
	Zuständigkeit:
		Client-UI für das Kreaturen-Kodex-System (docs/content-update-1.md,
		Abschnitt 5.2): responsives Karten-Raster aller aktuell existierenden
		Kreaturen, gruppiert in Tabs je Zone + einem eigenen "Events"-Tab,
		mit Silhouette-Darstellung für nicht besessene Kreaturen,
		Rarity-Abzeichen, Vollständigkeits-Leiste je Zone, Belohnungs-
		Abholung und einem Favoriten-Stern (steuert die Plot-Anzeige aus
		CreatureDisplayService live).

		WICHTIG: Dies ist AUSSCHLIESSLICH Anzeige/Komfort. Katalog-Aufbau,
		Besitz-/Vollständigkeits-Auswertung, Favoriten-Validierung und
		Belohnungs-Vergabe laufen vollständig serverseitig in CodexService -
		dieses Skript zeigt nur, was der Server über CodexRemotes meldet,
		und schickt bei Favoriten-/Belohnungs-Aktionen lediglich eine
		Absichtserklärung, die der Server komplett neu validiert.

		BEWUSSTE VEREINFACHUNG "Neu laden statt Live-Abo" (Auftrag: "where
		ambiguous, choose the simpler option and note it"): Katalog + Status
		werden bei JEDEM Öffnen des Panels frisch per RemoteFunction
		abgefragt (GetCodexCatalog/GetCodexState) statt über eine dauerhafte
		Push-Verbindung aktuell gehalten zu werden. Ein Spieler, der z. B.
		während offenem Kodex-Panel ein Mystery Egg öffnet, sieht die neue
		Kreatur erst beim nächsten Öffnen/nach einer Aktion (Favorit
		setzen/Belohnung abholen lösen ohnehin einen Rebuild aus) - für ein
		Panel, das typischerweise kurz geöffnet und wieder geschlossen wird,
		ist das ein akzeptabler Trade-off gegen die Komplexität eines
		weiteren Push-Kanals (identisches Prinzip wie RaidUIController's
		"Entführte Kreaturen"-Panel, das nur beim Öffnen neu aufgebaut wird).

		BEWUSSTE VEREINFACHUNG "Karten statt ViewportFrame-Vorschau" (Auftrag
		Punkt 3, "otherwise a styled card with rarity color"): Kreaturen-
		Vorschauen sind rarity-farbige Karten mit Namen/Icon-Glyphe statt
		echter 3D-ViewportFrame-Live-Vorschauen. Grund: bis zu ~30+
		gleichzeitig sichtbare Grid-Karten würden bei ViewportFrames
		entweder viele echte WorldModel/Camera-Instanzen (teuer, exakt die
		Art Handy-Unfreundlichkeit, die Abschnitt 5.1 vermeiden will) oder
		ein aufwendiges Cell-Recycling-System brauchen, für das es noch
		keine garantiert kamerafreundliche, konsistente Vorschau-Pose je
		Kreaturen-Modell gibt. Eine echte Bild-/Icon-Pipeline
		(assets/models/ui/, siehe assets/models/README.md) ist ohnehin
		Aufgabe des 3D-/UI-Asset-Agenten, nicht dieses Systems - sobald
		Icon-Asset-IDs existieren, genügt es, `buildCreatureGlyph()` unten
		durch ein `ImageLabel` mit echter Icon-Asset-Id zu ersetzen.

		Öffnen des Panels:
			- MainMenuController-Button "Kodex" (Bridge-BindableEvent
			  "OpenCodex", siehe MainMenuController.client.lua Kopfkommentar).

	Rojo-Einhängepunkt:
		src/client/CodexUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.CodexUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodexRemotes = require(ReplicatedStorage:WaitForChild("CodexRemotes"))
local BuddyRemotes = require(ReplicatedStorage:WaitForChild("BuddyRemotes"))
-- Extra Buddy Slot Gamepass (Auftrag "purchasable abilities/boosts"): only
-- used here to know whether the SECOND "Set Buddy 2" button should even be
-- offered - AbilityService.GetStatus is the single source of truth for
-- gamepass ownership, no second, redundant ownership lookup added here.
local AbilityRemotes = require(ReplicatedStorage:WaitForChild("AbilityRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Tabs = UIKit.Tabs
local RarityBadge = UIKit.RarityBadge
local ProgressBar = UIKit.ProgressBar
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX
local Device = UIKit.Device

local player = Players.LocalPlayer

-- // Bridge (siehe MainMenuController.client.lua Kopfkommentar) ----------------
local function getOrCreateBridgeEvent(eventName: string): BindableEvent
	local bridge = ReplicatedStorage:FindFirstChild("AbyssaraUIBridge")
	if not bridge then
		bridge = Instance.new("Folder")
		bridge.Name = "AbyssaraUIBridge"
		bridge.Parent = ReplicatedStorage
	end
	local event = bridge:FindFirstChild(eventName)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = eventName
		event.Parent = bridge
	end
	return event :: BindableEvent
end

local openCodexEvent = getOrCreateBridgeEvent("OpenCodex")

-- // Kleine Formatierungs-Helfer ------------------------------------------------

--- "HadalDepths" -> "Hadal Depths", "SunZone" -> "Sun Zone" - trennt
--- CamelCase-Ids in lesbare Labels, OHNE eine feste Zonen-Namensliste zu
--- pflegen (bleibt automatisch korrekt für künftige Zonen/Ids).
local function humanizeId(id: string): string
	local spaced = id:gsub("(%l)(%u)", "%1 %2")
	return spaced
end

local function safeRarityKey(rarity: any): string?
	if typeof(rarity) == "string" and table.find(Theme.RarityOrder, rarity) then
		return rarity
	end
	return nil
end

local function rarityColorFor(rarity: any): Color3
	local key = safeRarityKey(rarity)
	if key then
		return (Theme.Rarity :: any)[key]
	end
	return Theme.Text.Secondary
end

-- // Remote-Aufrufe (synchron, siehe Kopfkommentar "Neu laden statt Live-Abo") --

type CatalogEntry = {
	CreatureId: string,
	DisplayName: string,
	Rarity: string,
	Zone: string,
	Event: string?,
}

type Catalog = {
	ZoneOrder: { string },
	Entries: { CatalogEntry },
}

type ZoneCompletion = {
	Owned: number,
	Total: number,
	Percent: number,
	RewardClaimed: boolean,
	RewardClaimable: boolean,
}

type CodexState = {
	OwnedCreatureIds: { [string]: boolean },
	Favorites: { string },
	ClaimedZoneRewards: { [string]: boolean },
	ZoneCompletion: { [string]: ZoneCompletion },
	IncomeBonusPercent: number,
}

local function fetchCatalog(): Catalog?
	local ok, result = pcall(function()
		return CodexRemotes.GetCodexCatalog:InvokeServer()
	end)
	if ok then
		return result :: Catalog
	end
	warn("[CodexUIController] GetCodexCatalog failed: " .. tostring(result))
	return nil
end

local function fetchState(): CodexState?
	local ok, result = pcall(function()
		return CodexRemotes.GetCodexState:InvokeServer()
	end)
	if ok then
		return result :: CodexState
	end
	warn("[CodexUIController] GetCodexState failed: " .. tostring(result))
	return nil
end

--- Buddy-Auswahl des anfragenden Spielers (docs/buddy.md) - eigener
--- Remote-Kanal (BuddyRemotes), NICHT Teil von CodexState, da das Buddy-
--- System bewusst unabhängig von CodexService ist (siehe
--- BuddyService-Kopfkommentar "Bewusst entkoppelt").
local function fetchBuddyCreatureId(): string?
	local ok, result = pcall(function()
		return BuddyRemotes.GetBuddyState:InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		return result.CreatureId
	end
	if not ok then
		warn("[CodexUIController] GetBuddyState failed: " .. tostring(result))
	end
	return nil
end

--- Second buddy slot's current creature (or nil) - see fetchBuddyCreatureId.
local function fetchBuddyCreatureId2(): string?
	local ok, result = pcall(function()
		return BuddyRemotes.GetBuddyState:InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		return result.CreatureId2
	end
	return nil
end

--- Whether the local player owns the "Extra Buddy Slot" gamepass - gates
--- whether the "Set Buddy 2" button appears on owned cards at all.
local function fetchHasExtraBuddySlot(): boolean
	local ok, result = pcall(function()
		return AbilityRemotes.GetAbilityStatus:InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		return result.HasExtraBuddySlot == true
	end
	return false
end

-- // Panel-Grundgerüst (einmalig gebaut) ----------------------------------------

local panel = Panel.new({
	Title = "Creature Codex",
	Closable = true,
	CenteredSize = UDim2.fromOffset(780, 580),
})

local EVENTS_TAB_ID = "Events"

local currentTabsHandle: any = nil
local currentFavorites: { string } = {}
local pendingFavoriteRequest = false
local currentBuddyCreatureId: string? = nil
local pendingBuddyRequest = false
local currentBuddyCreatureId2: string? = nil
local pendingBuddyRequest2 = false
local currentHasExtraBuddySlot = false

local function destroyCurrentTabs()
	if currentTabsHandle then
		currentTabsHandle:Destroy()
		currentTabsHandle = nil
	end
end

--- Baut eine einzelne Kreaturen-Karte. `owned` steuert Silhouette- vs.
--- echte Darstellung; `onFavoriteToggle`/`onBuddyToggle` sind nil für
--- nicht besessene Karten (Favoriten/Buddy sind nur für besessene
--- Kreaturen möglich, siehe docs/buddy.md).
local function buildCard(
	parent: Instance,
	entry: CatalogEntry,
	owned: boolean,
	isFavorite: boolean,
	isBuddy: boolean,
	layoutOrder: number,
	onFavoriteToggle: (() -> ())?,
	onBuddyToggle: (() -> ())?,
	isBuddy2: boolean?,
	onBuddyToggle2: (() -> ())?
)
	local card = Instance.new("Frame")
	card.Name = entry.CreatureId
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.LayoutOrder = layoutOrder
	card.Parent = parent
	Theme.ApplyCorner(card, UDim.new(0, 10))
	local strokeColor = owned and rarityColorFor(entry.Rarity) or Theme.Background.Deepest
	local stroke = Theme.ApplyStroke(card, strokeColor, 2)
	stroke.Transparency = owned and 0.1 or 0.5

	-- // Icon-/Glyphe-Fläche (siehe Kopfkommentar "Karten statt ViewportFrame") --
	local iconArea = Instance.new("Frame")
	iconArea.Name = "IconArea"
	iconArea.BackgroundColor3 = owned and rarityColorFor(entry.Rarity) or Color3.fromRGB(25, 25, 30)
	iconArea.BackgroundTransparency = owned and 0.72 or 0
	iconArea.Size = UDim2.new(1, -12, 0, 78)
	iconArea.Position = UDim2.fromOffset(6, 6)
	iconArea.Parent = card
	Theme.ApplyCorner(iconArea, UDim.new(0, 8))

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = Theme.Font.Header
	glyph.TextColor3 = owned and rarityColorFor(entry.Rarity) or Color3.fromRGB(60, 60, 68)
	glyph.TextScaled = true
	glyph.Text = owned and "🐚" or "???"
	glyph.Parent = iconArea

	if owned and onFavoriteToggle then
		local favoriteButton = Button.new({
			Parent = iconArea,
			Text = isFavorite and "★" or "☆",
			Variant = isFavorite and "Success" or "Ghost",
			Size = UDim2.fromOffset(30, 30),
		})
		favoriteButton.Instance.AnchorPoint = Vector2.new(1, 0)
		favoriteButton.Instance.Position = UDim2.new(1, -4, 0, 4)
		favoriteButton.Clicked:Connect(onFavoriteToggle)
	end

	-- // Buddy-Auswahl (docs/buddy.md) - "Set Buddy"-Button spiegelbildlich
	-- zum Favoriten-Stern oben, damit KEIN bestehendes Karten-Layout
	-- umgebaut werden muss. Player-visible text is English (see task
	-- requirement) even though the rest of this panel is still German.
	if owned and onBuddyToggle then
		local buddyButton = Button.new({
			Parent = iconArea,
			Text = isBuddy and "✓ Buddy" or "Set Buddy",
			Variant = isBuddy and "Success" or "Ghost",
			Size = UDim2.fromOffset(isBuddy and 64 or 70, 26),
		})
		buddyButton.Instance.AnchorPoint = Vector2.new(0, 0)
		buddyButton.Instance.Position = UDim2.new(0, 4, 0, 4)
		buddyButton.Clicked:Connect(onBuddyToggle)
	end

	-- Second buddy slot (Extra Buddy Slot gamepass, 149 Robux) - identical
	-- placement idea as "Set Buddy" above, stacked directly below it so no
	-- existing card layout needs to change. Only ever passed when the local
	-- player actually owns the gamepass (see rebuildPanel).
	if owned and onBuddyToggle2 then
		local buddyButton2 = Button.new({
			Parent = iconArea,
			Text = isBuddy2 and "✓ Buddy 2" or "Set Buddy 2",
			Variant = isBuddy2 and "Success" or "Ghost",
			Size = UDim2.fromOffset(isBuddy2 and 72 or 78, 26),
		})
		buddyButton2.Instance.AnchorPoint = Vector2.new(0, 0)
		buddyButton2.Instance.Position = UDim2.new(0, 4, 0, 34)
		buddyButton2.Clicked:Connect(onBuddyToggle2)
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -12, 0, 20)
	nameLabel.Position = UDim2.fromOffset(6, 88)
	nameLabel.Font = Theme.Font.BodyBold
	nameLabel.TextColor3 = owned and Theme.Text.Primary or Theme.Text.Muted
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = owned and entry.DisplayName or "???"
	nameLabel.Parent = card
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MinTextSize = 10
	nameConstraint.MaxTextSize = 16
	nameConstraint.Parent = nameLabel

	local badgeRarity = safeRarityKey(entry.Rarity)
	if badgeRarity then
		RarityBadge.new({
			Parent = card,
			Rarity = badgeRarity :: any,
			Size = UDim2.fromOffset(84, 20),
			Position = UDim2.fromOffset(6, 112),
		})
	end

	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Size = UDim2.new(1, -12, 0, 16)
	subLabel.Position = UDim2.fromOffset(6, 136)
	subLabel.Font = Theme.Font.Body
	subLabel.TextColor3 = Theme.Text.Muted
	subLabel.TextScaled = true
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = entry.Event and ("Event: " .. humanizeId(entry.Event)) or humanizeId(entry.Zone)
	subLabel.Parent = card
	local subConstraint = Instance.new("UITextSizeConstraint")
	subConstraint.MinTextSize = 8
	subConstraint.MaxTextSize = 12
	subConstraint.Parent = subLabel

	return card
end

local function buildGridContainer(parent: Instance, layoutOrder: number): Frame
	local container = Instance.new("Frame")
	container.Name = "Grid"
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.LayoutOrder = layoutOrder
	container.Parent = parent

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(150, 158)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = container

	return container
end

local requestFavoritesUpdate: (({ string }) -> ())? = nil
local requestBuddyUpdate: ((string?) -> ())? = nil
local requestBuddyUpdate2: ((string?) -> ())? = nil

--- Baut den kompletten Panel-Inhalt (Tabs + Karten) frisch auf. Wird beim
--- Öffnen sowie nach jeder erfolgreichen Favoriten-/Belohnungs-/Buddy-
--- Aktion aufgerufen (siehe Kopfkommentar "Neu laden statt Live-Abo").
local function rebuildPanel(preferredTabId: string?)
	local catalog = fetchCatalog()
	local state = fetchState()
	if not catalog or not state then
		Toast.Show({ Text = "Codex could not be loaded.", Type = "Error" })
		return
	end

	currentFavorites = state.Favorites
	currentBuddyCreatureId = fetchBuddyCreatureId()
	currentBuddyCreatureId2 = fetchBuddyCreatureId2()
	currentHasExtraBuddySlot = fetchHasExtraBuddySlot()

	destroyCurrentTabs()

	local tabDefs: { { Id: string, Label: string } } = {}
	for _, zoneId in ipairs(catalog.ZoneOrder) do
		table.insert(tabDefs, { Id = zoneId, Label = humanizeId(zoneId) })
	end
	table.insert(tabDefs, { Id = EVENTS_TAB_ID, Label = "Events" })

	local entriesByZone: { [string]: { CatalogEntry } } = {}
	local eventEntries: { CatalogEntry } = {}
	for _, entry in ipairs(catalog.Entries) do
		if entry.Event then
			table.insert(eventEntries, entry)
		else
			local list = entriesByZone[entry.Zone]
			if not list then
				list = {}
				entriesByZone[entry.Zone] = list
			end
			table.insert(list, entry)
		end
	end

	local defaultTabId = preferredTabId
	local isKnownTab = defaultTabId ~= nil
		and (defaultTabId == EVENTS_TAB_ID or table.find(catalog.ZoneOrder, defaultTabId) ~= nil)
	if not isKnownTab then
		defaultTabId = tabDefs[1] and tabDefs[1].Id or EVENTS_TAB_ID
	end

	local tabsHandle = Tabs.new({
		Parent = panel.Content,
		Tabs = tabDefs,
		DefaultTabId = defaultTabId,
	})
	currentTabsHandle = tabsHandle

	local function onFavoriteToggleFactory(creatureId: string): () -> ()
		return function()
			if pendingFavoriteRequest then
				return
			end
			local newFavorites: { string } = {}
			local isCurrentlyFavorite = table.find(currentFavorites, creatureId) ~= nil
			if isCurrentlyFavorite then
				for _, id in ipairs(currentFavorites) do
					if id ~= creatureId then
						table.insert(newFavorites, id)
					end
				end
			else
				if #currentFavorites >= 6 then
					Toast.Show({ Text = "Maximum of 6 favorites - remove one first.", Type = "Warning" })
					return
				end
				for _, id in ipairs(currentFavorites) do
					table.insert(newFavorites, id)
				end
				table.insert(newFavorites, creatureId)
			end
			if requestFavoritesUpdate then
				requestFavoritesUpdate(newFavorites)
			end
		end
	end

	--- Buddy-Auswahl (docs/buddy.md): Klick auf eine bereits als Buddy
	--- gewählte Karte entfernt den Buddy (nil), sonst wird diese Kreatur
	--- zum neuen Buddy (ersetzt eine evtl. vorherige Wahl - es gibt immer
	--- höchstens EINEN Buddy, anders als bis zu 6 Favoriten).
	local function onBuddyToggleFactory(creatureId: string): () -> ()
		return function()
			if pendingBuddyRequest then
				return
			end
			local newBuddyCreatureId: string? = if currentBuddyCreatureId == creatureId then nil else creatureId
			if requestBuddyUpdate then
				requestBuddyUpdate(newBuddyCreatureId)
			end
		end
	end

	--- Second buddy slot (Extra Buddy Slot gamepass) - identical toggle
	--- principle as onBuddyToggleFactory above, its own independent slot.
	local function onBuddyToggleFactory2(creatureId: string): () -> ()
		return function()
			if pendingBuddyRequest2 then
				return
			end
			local newBuddyCreatureId2: string? = if currentBuddyCreatureId2 == creatureId then nil else creatureId
			if requestBuddyUpdate2 then
				requestBuddyUpdate2(newBuddyCreatureId2)
			end
		end
	end

	for _, zoneId in ipairs(catalog.ZoneOrder) do
		local contentFrame = tabsHandle:GetContentFrame(zoneId)
		local completion = state.ZoneCompletion[zoneId]

		if completion then
			local header = Instance.new("Frame")
			header.Name = "CompletionHeader"
			header.BackgroundTransparency = 1
			header.Size = UDim2.new(1, 0, 0, 64)
			header.LayoutOrder = 0
			header.Parent = contentFrame

			local titleLabel = Instance.new("TextLabel")
			titleLabel.BackgroundTransparency = 1
			titleLabel.Size = UDim2.new(1, -150, 0, 22)
			titleLabel.Font = Theme.Font.BodyBold
			titleLabel.TextColor3 = Theme.Text.Primary
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.TextScaled = true
			titleLabel.Text = ("%s: %d/%d — %d%%"):format(
				humanizeId(zoneId),
				completion.Owned,
				completion.Total,
				completion.Percent
			)
			titleLabel.Parent = header
			local titleConstraint = Instance.new("UITextSizeConstraint")
			titleConstraint.MinTextSize = 12
			titleConstraint.MaxTextSize = 18
			titleConstraint.Parent = titleLabel

			local barHost = Instance.new("Frame")
			barHost.BackgroundTransparency = 1
			barHost.Position = UDim2.fromOffset(0, 28)
			barHost.Size = UDim2.new(1, -150, 0, 14)
			barHost.Parent = header
			ProgressBar.new({
				Parent = barHost,
				Size = UDim2.fromScale(1, 1),
				Value = completion.Total > 0 and (completion.Owned / completion.Total) or 0,
				Colors = { Theme.Neon.Cyan, Theme.Neon.ToxicGreen },
			})

			local claimButton = Button.new({
				Parent = header,
				Text = if completion.RewardClaimed
					then "✓ Claimed"
					elseif completion.RewardClaimable then "Claim Reward"
					else "Incomplete",
				Variant = if completion.RewardClaimed then "Ghost" elseif completion.RewardClaimable then "Success" else "Ghost",
				Size = UDim2.fromOffset(140, 44),
				Disabled = not completion.RewardClaimable,
			})
			claimButton.Instance.AnchorPoint = Vector2.new(1, 0)
			claimButton.Instance.Position = UDim2.new(1, 0, 0, 10)
			if completion.RewardClaimable then
				claimButton.Clicked:Connect(function()
					claimButton:SetDisabled(true)
					claimButton:SetText("Claiming ...")
					CodexRemotes.RequestClaimZoneReward:FireServer(zoneId)
				end)
			end
		end

		local grid = buildGridContainer(contentFrame, 1)
		local zoneEntries = entriesByZone[zoneId] or {}
		table.sort(zoneEntries, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		for index, entry in ipairs(zoneEntries) do
			local owned = state.OwnedCreatureIds[entry.CreatureId] == true
			local isFavorite = table.find(currentFavorites, entry.CreatureId) ~= nil
			local isBuddy = currentBuddyCreatureId == entry.CreatureId
			local isBuddy2 = currentBuddyCreatureId2 == entry.CreatureId
			buildCard(
				grid,
				entry,
				owned,
				isFavorite,
				isBuddy,
				index,
				owned and onFavoriteToggleFactory(entry.CreatureId) or nil,
				owned and onBuddyToggleFactory(entry.CreatureId) or nil,
				isBuddy2,
				(owned and currentHasExtraBuddySlot) and onBuddyToggleFactory2(entry.CreatureId) or nil
			)
		end
	end

	do
		local contentFrame = tabsHandle:GetContentFrame(EVENTS_TAB_ID)
		local grid = buildGridContainer(contentFrame, 0)
		table.sort(eventEntries, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		for index, entry in ipairs(eventEntries) do
			local owned = state.OwnedCreatureIds[entry.CreatureId] == true
			local isFavorite = table.find(currentFavorites, entry.CreatureId) ~= nil
			local isBuddy = currentBuddyCreatureId == entry.CreatureId
			local isBuddy2 = currentBuddyCreatureId2 == entry.CreatureId
			buildCard(
				grid,
				entry,
				owned,
				isFavorite,
				isBuddy,
				index,
				owned and onFavoriteToggleFactory(entry.CreatureId) or nil,
				owned and onBuddyToggleFactory(entry.CreatureId) or nil,
				isBuddy2,
				(owned and currentHasExtraBuddySlot) and onBuddyToggleFactory2(entry.CreatureId) or nil
			)
		end
	end
end

requestFavoritesUpdate = function(newFavorites: { string })
	pendingFavoriteRequest = true
	CodexRemotes.RequestSetFavorites:FireServer(newFavorites)
end

requestBuddyUpdate = function(newBuddyCreatureId: string?)
	pendingBuddyRequest = true
	BuddyRemotes.RequestSetBuddy:FireServer(newBuddyCreatureId)
end

requestBuddyUpdate2 = function(newBuddyCreatureId2: string?)
	pendingBuddyRequest2 = true
	BuddyRemotes.RequestSetBuddy2:FireServer(newBuddyCreatureId2)
end

-- // Server-Antworten -----------------------------------------------------------

local setFavoritesConnection = CodexRemotes.SetFavoritesResult.OnClientEvent:Connect(function(payload: { [string]: any })
	pendingFavoriteRequest = false
	if payload.Success then
		Toast.Show({ Text = "Favorites updated - plot display coming soon.", Type = "Success", Duration = 2.5 })
	else
		Toast.Show({ Text = "Could not set favorites (" .. tostring(payload.Reason) .. ").", Type = "Error" })
	end
	if panel.ScreenGui.Enabled then
		-- Panel noch offen: Karten-Sternzustände synchron halten.
		rebuildPanel(nil)
	end
end)

-- Buddy-Ergebnis-Texte sind bewusst ENGLISCH (Auftrag: alle neuen
-- spielerseitig sichtbaren Strings in Englisch, unabhängig davon, dass
-- der Rest dieses Panels noch Deutsch ist - siehe Kopfkommentar der
-- betroffenen Buttons oben).
local setBuddyConnection = BuddyRemotes.SetBuddyResult.OnClientEvent:Connect(function(payload: { [string]: any })
	pendingBuddyRequest = false
	if payload.Success then
		if payload.CreatureId then
			Toast.Show({ Text = "Buddy set! It will follow you through the world.", Type = "Success", Duration = 2.5 })
		else
			Toast.Show({ Text = "Buddy removed.", Type = "Info", Duration = 2 })
		end
	else
		Toast.Show({ Text = "Could not set buddy (" .. tostring(payload.Reason) .. ").", Type = "Error" })
	end
	if panel.ScreenGui.Enabled then
		-- Panel noch offen: Karten-Buddy-Zustände synchron halten.
		rebuildPanel(nil)
	end
end)

--- Second buddy slot result - same wording/behavior as setBuddyConnection
--- above, plus the gamepass-specific "NoExtraSlot" rejection reason.
local setBuddy2Connection = BuddyRemotes.SetBuddy2Result.OnClientEvent:Connect(function(payload: { [string]: any })
	pendingBuddyRequest2 = false
	if payload.Success then
		if payload.CreatureId then
			Toast.Show({ Text = "Second buddy set! It will follow you on your other side.", Type = "Success", Duration = 2.5 })
		else
			Toast.Show({ Text = "Second buddy removed.", Type = "Info", Duration = 2 })
		end
	elseif payload.Reason == "NoExtraSlot" then
		Toast.Show({ Text = "You need the Extra Buddy Slot gamepass for a second buddy.", Type = "Warning", Duration = 3.5 })
	else
		Toast.Show({ Text = "Could not set second buddy (" .. tostring(payload.Reason) .. ").", Type = "Error" })
	end
	if panel.ScreenGui.Enabled then
		rebuildPanel(nil)
	end
end)

local claimResultConnection = CodexRemotes.ClaimZoneRewardResult.OnClientEvent:Connect(function(payload: { [string]: any })
	if payload.Success then
		Toast.Show({
			Text = ("%s claimed: +%d Tide Coins, title \"%s\"!"):format(
				humanizeId(tostring(payload.Zone)),
				payload.RewardTideCoins or 0,
				tostring(payload.RewardTitle)
			),
			Type = "Success",
			Duration = 4,
		})
		ScreenFX.BigMoment(Theme.Neon.ToxicGreen)
	else
		Toast.Show({ Text = "Reward could not be claimed (" .. tostring(payload.Reason) .. ").", Type = "Error" })
	end
	if panel.ScreenGui.Enabled then
		rebuildPanel(payload.Zone)
	end
end)

-- // Öffnen -----------------------------------------------------------------------

local openConnection = openCodexEvent.Event:Connect(function()
	rebuildPanel(nil)
	panel:Open()
end)

-- // Aufräumen --------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	openConnection:Disconnect()
	setFavoritesConnection:Disconnect()
	setBuddyConnection:Disconnect()
	setBuddy2Connection:Disconnect()
	claimResultConnection:Disconnect()
	destroyCurrentTabs()
	panel:Destroy()
end)
