--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: ShopUIController (LocalScript)
	Zuständigkeit:
		Das komplette Shop-Panel – Herzstück/"Highlight" des Spiels laut
		Auftrag: grelle Neon-Produktkarten, FX-Buttons, responsiv auf
		Handy/Tablet/PC/Konsole. Fünf Tabs: "Angebote" (tägliche Rotation +
		Countdown bis Reset), "Gamepasses", "Robux-Pakete" (Entwicklerprodukte
		außer Mystery Egg), "Mystery Egg" (Odds sichtbar VOR dem Kauf,
		Pflicht laut Roblox "Paid Random Items"-Richtlinie) und "Kosmetik"
		(Kauf mit Tide Coins/Abyssal Shards, Ausrüsten, Besitzt-Markierung).

		Datenquelle: ausschließlich ShopRemotes (siehe dortiger Kopfkommentar
		für die vollständige Payload-Doku) + ShopConfig (nur für Anzeige-
		Zwecke, z. B. RequiresTarget-Flag – niemals als Autorität für
		Preis/Besitz, das kommt IMMER live vom Server über GetShopCatalog/
		ShopStateChanged). Jeder Klick ist nur eine Anfrage – der Server
		validiert/berechnet den tatsächlichen Kauf vollständig neu
		(Anti-Exploit-Grundregel, siehe ShopRemotes-Kopfkommentar).

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder klickbare Button entsteht
		ausschließlich über UIKit.Button.new(...) – auch die Produktkarten-
		"Kaufen"-Buttons, Tab-Köpfe (UIKit.Tabs macht das schon selbst),
		Ausrüsten-/Test-Kauf-Buttons.

		Öffnen des Panels (mehrere gleichwertige Wege):
			- MainMenuController-Button "Shop" (Bridge-BindableEvent
			  "OpenShop" unter ReplicatedStorage.AbyssaraUIBridge, siehe
			  MainMenuController.client.lua Kopfkommentar).
			- ProximityPrompt am Hub-Marktstand ("ShopStand"-Untermodell mit
			  Attribut Interactable == "Shop", siehe assets/models/README.md
			  Abschnitt "hub"). Der Server legt dort noch keinen Prompt an,
			  daher wird er hier rein clientseitig an der Interaktionsstelle
			  erzeugt (siehe attachShopPrompt/scanForShopStand unten) – das
			  ist für reine Anzeige-/Interaktions-Hinweise ohne Gameplay-
			  Autorität zulässig.

		Mystery-Egg-Odds werden NICHT hier neu gebaut, sondern über die
		bereits bestehende Bridge "OpenMysteryEgg" im vorhandenen
		GachaOddsUIController.client.lua-Panel angezeigt ("Chancen ansehen"-
		Button im Mystery-Egg-Tab feuert dasselbe Bridge-Event wie der
		Mystery-Egg-Button in der Menüleiste) – keine doppelte Odds-UI.

	Rojo-Einhängepunkt:
		src/client/ShopUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.ShopUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShopRemotes = require(ReplicatedStorage:WaitForChild("ShopRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Panel = UIKit.Panel
local Tabs = UIKit.Tabs
local Button = UIKit.Button
local Toast = UIKit.Toast
local CountUp = UIKit.CountUp
local ScreenFX = UIKit.ScreenFX

local localPlayer = Players.LocalPlayer

-- // Bridge (identisches Muster wie MainMenuController/GachaOddsUIController) --

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

local openShopEvent = getOrCreateBridgeEvent("OpenShop")
local openMysteryEggOddsEvent = getOrCreateBridgeEvent("OpenMysteryEgg")

-- // Anzeige-Metadaten (rein UI, keine Preis-/Besitz-Autorität) -----------------
-- Kein Produkt hier ist "verkaufsstark, aber unfair": Banner sind fest an
-- objektiv nachvollziehbare Werte gebunden (bestes Coins-pro-Robux-
-- Verhältnis, meistgenannter Pass laut GDD-Priorisierung), keine
-- künstliche Verknappung/Dark Patterns.
local BEST_VALUE_KEYS: { [string]: boolean } = { Coins3000 = true }
local POPULAR_KEYS: { [string]: boolean } = { VIPDiver = true, MysteryEgg = true }

local GAMEPASS_GLYPH: { [string]: string } = {
	AutoCollector = "🤖",
	DoubleCoins = "💰",
	ExtraPlot = "🏝️",
	VIPDiver = "👑",
	TrenchRunner = "🏃",
}

local DEV_PRODUCT_GLYPH: { [string]: string } = {
	Coins500 = "🪙",
	Coins3000 = "🪙",
	RescueToken = "🆘",
	MysteryEgg = "🥚",
	RaidSkip = "⏭️",
	InstantBreeding = "⚡",
}

local COSMETIC_GLYPH: { [string]: string } = {
	DiverSuitColor = "🤿",
	CreatureGlowColor = "✨",
	Decoration = "🪸",
}

local CURRENCY_GLYPH: { [string]: string } = {
	TideCoins = "🪙",
	AbyssalShards = "💎",
}

local REASON_MESSAGES: { [string]: string } = {
	InvalidKey = "Ungültiges Produkt. Bitte Shop neu laden.",
	UnknownGamepass = "Dieser Gamepass ist unbekannt.",
	UnknownProduct = "Dieses Produkt ist unbekannt.",
	NotConfigured = "Noch nicht verfügbar – bald freigeschaltet!",
	AlreadyOwned = "Du besitzt das bereits.",
	PaidRandomItemsRestricted = "Der Robux-Kauf von Zufalls-Items ist in deiner Region eingeschränkt (Roblox-Richtlinie). Du kannst Mystery Eggs weiterhin gratis über das Spiel erhalten.",
	AlreadyUsedToday = "Heute schon benutzt – morgen wieder verfügbar.",
	MissingTarget = "Kein passendes Ziel gefunden (z. B. keine entführte Kreatur/kein laufendes Brutbecken).",
	InvalidTarget = "Dieses Ziel gehört dir nicht oder existiert nicht mehr.",
	StudioOnly = "Nur in Roblox Studio verfügbar.",
	InvalidArguments = "Ungültige Anfrage.",
	UnknownKind = "Unbekannter Kauftyp.",
	DataNotLoaded = "Deine Spieldaten laden noch – bitte kurz warten.",
	InvalidItem = "Ungültiger Artikel.",
	UnknownItem = "Unbekannter Artikel.",
	InsufficientFunds = "Nicht genug Guthaben.",
	ChargeFailed = "Bezahlung fehlgeschlagen. Bitte erneut versuchen.",
	PersistenceFailed = "Speichern fehlgeschlagen. Bitte erneut versuchen.",
	NotOwned = "Du besitzt diesen Artikel noch nicht.",
}

local function friendlyReason(reason: string?): string
	if not reason then
		return "Aktion fehlgeschlagen. Bitte erneut versuchen."
	end
	return REASON_MESSAGES[reason] or ("Aktion fehlgeschlagen (" .. reason .. ").")
end

-- // Formatierung ---------------------------------------------------------------

local function formatRobux(amount: number): string
	return "R$ " .. string.format("%d", amount)
end

local function formatCoins(amount: number): string
	return string.format("%d", math.floor(amount + 0.5))
end

local function secondsUntilNextUtcMidnight(): number
	local now = os.time()
	local utcNow = os.date("!*t", now)
	local nowClock = utcNow.hour * 3600 + utcNow.min * 60 + utcNow.sec
	local remaining = (24 * 3600) - nowClock
	if remaining <= 0 then
		remaining = 24 * 3600
	end
	return remaining
end

local function formatCountdown(totalSeconds: number): string
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- // Grundgerüst: eine Zeile Text mit UITextSizeConstraint (kein nackter Button,
-- reine Labels sind erlaubt) -----------------------------------------------------

local function makeLabel(props: {
	Parent: Instance,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	Font: Enum.Font?,
	Color: Color3?,
	MinSize: number?,
	MaxSize: number?,
	XAlign: Enum.TextXAlignment?,
	Wrapped: boolean?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromOffset(0, 0)
	label.Font = props.Font or Theme.Font.Body
	label.TextColor3 = props.Color or Theme.Text.Primary
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextScaled = true
	label.TextWrapped = props.Wrapped or false
	label.Text = props.Text
	label.Parent = props.Parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinSize or 12
	constraint.MaxTextSize = props.MaxSize or 20
	constraint.Parent = label
	return label
end

local function makeNeonIcon(parent: Instance, glyph: string, colorA: Color3, colorB: Color3): Frame
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundColor3 = colorA
	icon.Size = UDim2.fromOffset(56, 56)
	icon.Position = UDim2.fromOffset(12, 12)
	Theme.ApplyCorner(icon, UDim.new(0, 14))
	Theme.ApplyGradient(icon, { colorA, colorB }, 120)
	local stroke = Theme.ApplyStroke(icon, colorA, 2)
	stroke.Transparency = 0.15
	icon.Parent = parent

	local glyphLabel = Instance.new("TextLabel")
	glyphLabel.BackgroundTransparency = 1
	glyphLabel.Size = UDim2.fromScale(1, 1)
	glyphLabel.Font = Theme.Font.Header
	glyphLabel.Text = glyph
	glyphLabel.TextScaled = true
	glyphLabel.TextColor3 = Theme.Text.OnNeon
	glyphLabel.Parent = icon
	local glyphConstraint = Instance.new("UITextSizeConstraint")
	glyphConstraint.MinTextSize = 18
	glyphConstraint.MaxTextSize = 30
	glyphConstraint.Parent = glyphLabel

	return icon
end

local function makeBanner(parent: Instance, text: string, color: Color3)
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(1, 0)
	banner.Position = UDim2.new(1, -8, 0, 8)
	banner.Size = UDim2.fromOffset(math.clamp(#text * 8 + 20, 60, 160), 22)
	banner.BackgroundColor3 = color
	banner.ZIndex = 4
	Theme.ApplyCorner(banner, UDim.new(0, 8))
	banner.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font.BodyBold
	label.TextColor3 = Theme.Text.OnNeon
	label.TextScaled = true
	label.Text = text
	label.ZIndex = 4
	label.Parent = banner
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 10
	constraint.MaxTextSize = 14
	constraint.Parent = label
end

-- // Grid-Wrapper: responsive Spaltenanzahl je Gerät -----------------------------

type CardHandle = { Destroy: (self: CardHandle) -> () }

type GridWrapper = {
	Frame: Frame,
	Grid: UIGridLayout,
	Cards: { CardHandle },
	AddCard: (self: GridWrapper, cardHandle: CardHandle) -> (),
	ClearCards: (self: GridWrapper) -> (),
	Destroy: (self: GridWrapper) -> (),
}

local CARD_HEIGHT = 258

local function computeColumnCount(deviceClass: string, width: number): number
	if deviceClass == "Phone" then
		return width > 480 and 2 or 1
	elseif deviceClass == "Tablet" then
		return width > 760 and 3 or 2
	else
		-- PC und Konsole
		return width > 980 and 4 or 3
	end
end

local function createGridWrapper(parent: Instance, layoutOrder: number): GridWrapper
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Grid"
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.LayoutOrder = layoutOrder
	wrapper.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(14, 14)
	grid.CellSize = UDim2.fromOffset(260, CARD_HEIGHT)
	grid.Parent = wrapper

	local function applyColumns()
		local state = Device.GetState()
		local width = wrapper.AbsoluteSize.X
		if width <= 0 then
			width = state.ViewportSize.X - 80
		end
		local columns = computeColumnCount(state.Class, width)
		local padding = 14
		local cellWidth = math.floor((width - padding * (columns - 1)) / math.max(columns, 1))
		cellWidth = math.max(cellWidth, 200)
		grid.CellSize = UDim2.fromOffset(cellWidth, CARD_HEIGHT)
		grid.CellPadding = UDim2.fromOffset(padding, padding)
	end

	applyColumns()
	local deviceConnection = Device.Changed:Connect(applyColumns)
	local sizeConnection = wrapper:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyColumns)

	local handle = {} :: GridWrapper
	handle.Frame = wrapper
	handle.Grid = grid
	handle.Cards = {}

	handle.AddCard = function(self, cardHandle: CardHandle)
		table.insert(self.Cards, cardHandle)
	end

	handle.ClearCards = function(self)
		for _, card in self.Cards do
			card:Destroy()
		end
		table.clear(self.Cards)
	end

	handle.Destroy = function(self)
		self:ClearCards()
		deviceConnection:Disconnect()
		sizeConnection:Disconnect()
		wrapper:Destroy()
	end

	return handle
end

-- // Basis-Kartenrahmen -----------------------------------------------------------

local function createCardFrame(parent: Instance, layoutOrder: number): Frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.fromScale(1, 1)
	card.LayoutOrder = layoutOrder
	card.ClipsDescendants = false
	Theme.ApplyCorner(card, UDim.new(0, 16))
	local stroke = Theme.ApplyStroke(card, Theme.Neon.Violet, 2)
	stroke.Transparency = 0.35
	Theme.ApplyGradient(card, { Theme.Background.PanelLight, Theme.Background.Panel }, 100)
	card.Parent = parent
	return card
end

-- // State ------------------------------------------------------------------------

type ShopCatalog = { [string]: any }

local currentCatalog: ShopCatalog? = nil
local panelHandle: any = nil
local tabsHandle: any = nil
local tideCoinsLabel: TextLabel? = nil
local abyssalShardsLabel: TextLabel? = nil
local lastTideCoins = 0
local lastAbyssalShards = 0

local offerGrid: GridWrapper? = nil
local offerCountdownLabel: TextLabel? = nil
local gamepassGrid: GridWrapper? = nil
local devProductGrid: GridWrapper? = nil
local mysteryEggGrid: GridWrapper? = nil
local cosmeticGrid: GridWrapper? = nil

local countdownThread: thread? = nil
local isFetchingCatalog = false

-- Vorwärtsdeklaration: requestCatalog() (unten) ruft dies nach jedem Laden
-- auf, die eigentliche Definition folgt weiter unten (nach den Karten-
-- Baufunktionen, die sie referenziert) - als lokale Variable statt Luau-
-- Warnung/`--!strict`-Fehler durch einen impliziten globalen Namen.
local refreshAllTabsFromCatalog: () -> ()

-- // Käufe --------------------------------------------------------------------

local function requestCatalog()
	if isFetchingCatalog then
		return
	end
	isFetchingCatalog = true
	task.spawn(function()
		local ok, result = pcall(function()
			return ShopRemotes.GetShopCatalog:InvokeServer()
		end)
		isFetchingCatalog = false
		if ok and type(result) == "table" then
			currentCatalog = result :: ShopCatalog
			refreshAllTabsFromCatalog()
		else
			warn("[ShopUIController] Konnte Shop-Katalog nicht laden:", result)
		end
	end)
end

local function requestGamepassPurchase(key: string)
	ShopRemotes.RequestPromptGamepassPurchase:FireServer(key)
end

local function requestDevProductPurchase(key: string, targetId: string?)
	ShopRemotes.RequestPromptDevProductPurchase:FireServer(key, targetId)
end

local function requestStudioPurchase(kind: string, key: string)
	if not RunService:IsStudio() then
		return
	end
	ShopRemotes.RequestSimulateStudioPurchase:FireServer(kind, key)
end

local function celebratePurchase(message: string, color: Color3)
	Toast.Show({ Text = message, Type = "Success", Duration = 3.5 })
	ScreenFX.BigMoment(color)
end

local function requestCosmeticPurchase(itemId: string, itemName: string)
	task.spawn(function()
		local ok, result = pcall(function()
			return ShopRemotes.RequestPurchaseCosmetic:InvokeServer(itemId)
		end)
		if not ok or type(result) ~= "table" then
			Toast.Show({ Text = "Kauf fehlgeschlagen. Bitte erneut versuchen.", Type = "Error", Duration = 3 })
			return
		end
		if result.Success then
			celebratePurchase(itemName .. " gekauft!", Theme.Neon.ToxicGreen)
			requestCatalog()
		else
			Toast.Show({ Text = friendlyReason(result.Reason), Type = "Warning", Duration = 3.5 })
		end
	end)
end

local function requestCosmeticEquip(itemId: string, itemName: string)
	task.spawn(function()
		local ok, result = pcall(function()
			return ShopRemotes.RequestEquipCosmetic:InvokeServer(itemId)
		end)
		if not ok or type(result) ~= "table" then
			Toast.Show({ Text = "Ausrüsten fehlgeschlagen. Bitte erneut versuchen.", Type = "Error", Duration = 3 })
			return
		end
		if result.Success then
			Toast.Show({ Text = itemName .. " ausgerüstet!", Type = "Success", Duration = 2.5 })
			requestCatalog()
		else
			Toast.Show({ Text = friendlyReason(result.Reason), Type = "Warning", Duration = 3.5 })
		end
	end)
end

-- // Kartenaufbau: Gamepass -------------------------------------------------------

local function buildGamepassCard(parent: Instance, layoutOrder: number, row: { [string]: any }): CardHandle
	local card = createCardFrame(parent, layoutOrder)
	local glyph = GAMEPASS_GLYPH[row.Key] or "⭐"
	makeNeonIcon(card, glyph, Theme.Neon.Cyan, Theme.Neon.Violet)

	if row.Owned then
		makeBanner(card, "Besitzt", Theme.Neon.ToxicGreen)
	elseif POPULAR_KEYS[row.Key] then
		makeBanner(card, "Beliebt", Theme.Neon.Orange)
	end

	makeLabel({
		Parent = card,
		Text = row.Name,
		Size = UDim2.new(1, -80, 0, 22),
		Position = UDim2.fromOffset(78, 12),
		Font = Theme.Font.BodyBold,
		MinSize = 13,
		MaxSize = 18,
	})

	makeLabel({
		Parent = card,
		Text = row.Description,
		Size = UDim2.new(1, -16, 0, 56),
		Position = UDim2.fromOffset(8, 78),
		Color = Theme.Text.Secondary,
		MinSize = 10,
		MaxSize = 14,
		Wrapped = true,
	})

	makeLabel({
		Parent = card,
		Text = formatRobux(row.PriceRobuxDisplay),
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 138),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Yellow,
		MinSize = 14,
		MaxSize = 20,
	})

	local buyLabel = if row.Owned then "Besitzt" elseif not row.Purchasable then "Bald verfügbar" else "Kaufen"
	local buyButton = Button.new({
		Parent = card,
		Text = buyLabel,
		Variant = if row.Owned then "Ghost" else "Primary",
		Important = row.Purchasable and not row.Owned,
		Disabled = row.Owned or not row.Purchasable,
		Size = UDim2.new(1, -16, 0, 40),
		LayoutOrder = 1,
	})
	buyButton.Instance.Position = UDim2.fromOffset(8, 168)
	buyButton.Clicked:Connect(function()
		requestGamepassPurchase(row.Key)
	end)

	local studioButton: any = nil
	if RunService:IsStudio() then
		studioButton = Button.new({
			Parent = card,
			Text = "Studio: Testkauf",
			Variant = "Ghost",
			Disabled = row.Owned,
			Size = UDim2.new(1, -16, 0, 30),
			LayoutOrder = 2,
		})
		studioButton.Instance.Position = UDim2.fromOffset(8, 212)
		studioButton.Clicked:Connect(function()
			requestStudioPurchase("Gamepass", row.Key)
		end)
	end

	local handle = {} :: CardHandle
	handle.Destroy = function(_self)
		buyButton:Destroy()
		if studioButton then
			studioButton:Destroy()
		end
		card:Destroy()
	end
	return handle
end

-- // Kartenaufbau: Entwicklerprodukt (Robux-Pakete + Mystery Egg) ----------------

local function buildDevProductCard(parent: Instance, layoutOrder: number, row: { [string]: any }, showOddsButton: boolean): CardHandle
	local card = createCardFrame(parent, layoutOrder)
	local glyph = DEV_PRODUCT_GLYPH[row.Key] or "🛍️"
	makeNeonIcon(card, glyph, Theme.Neon.Magenta, Theme.Neon.Violet)

	if BEST_VALUE_KEYS[row.Key] then
		makeBanner(card, "Bester Wert", Theme.Neon.ToxicGreen)
	elseif POPULAR_KEYS[row.Key] then
		makeBanner(card, "Beliebt", Theme.Neon.Orange)
	end

	makeLabel({
		Parent = card,
		Text = row.Name,
		Size = UDim2.new(1, -80, 0, 22),
		Position = UDim2.fromOffset(78, 12),
		Font = Theme.Font.BodyBold,
		MinSize = 13,
		MaxSize = 18,
	})

	makeLabel({
		Parent = card,
		Text = row.Description,
		Size = UDim2.new(1, -16, 0, 48),
		Position = UDim2.fromOffset(8, 78),
		Color = Theme.Text.Secondary,
		MinSize = 10,
		MaxSize = 14,
		Wrapped = true,
	})

	makeLabel({
		Parent = card,
		Text = formatRobux(row.PriceRobuxDisplay),
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 128),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Yellow,
		MinSize = 14,
		MaxSize = 20,
	})

	-- Pflichtangabe (Roblox "Paid Random Items"-Richtlinie): Sperr-/
	-- Ablehnungsgrund klar UND freundlich anzeigen statt das Produkt einfach
	-- zu verstecken. Bei zielgebundenen Produkten (Rettungs-Token/Zucht
	-- sofort abschließen) zusätzlich ein Hinweis, dass der Server das
	-- zuletzt markierte Ziel serverseitig prüft (kein UI-Zielwähler hier -
	-- das ist Aufgabe des jeweiligen Fachscreens (RaidUIController/
	-- BreedingUIController); ein Kauf ohne gültiges Ziel wird freundlich
	-- über PurchasePromptRejected abgelehnt, siehe REASON_MESSAGES).
	local noteText: string? = nil
	if row.DisabledReason and row.DisabledReason ~= "" then
		noteText = friendlyReason(row.DisabledReason)
	elseif row.RequiresTarget then
		noteText = "Wirkt auf dein zuletzt ausgewähltes Ziel (z. B. entführte Kreatur/Brutbecken)."
	end
	local disabledNoteHeight = 0
	if noteText then
		makeLabel({
			Parent = card,
			Text = noteText,
			Size = UDim2.new(1, -16, 0, 34),
			Position = UDim2.fromOffset(8, 152),
			Color = if row.DisabledReason then Theme.Semantic.Warning else Theme.Text.Muted,
			MinSize = 9,
			MaxSize = 12,
			Wrapped = true,
		})
		disabledNoteHeight = 36
	end

	local buttonY = 168 + disabledNoteHeight - 20
	if disabledNoteHeight == 0 then
		buttonY = 168
	end

	local buyLabel = if not row.Purchasable then "Bald verfügbar" else "Kaufen"
	local buyButton = Button.new({
		Parent = card,
		Text = buyLabel,
		Variant = "Primary",
		Important = row.Purchasable,
		Disabled = not row.Purchasable,
		Size = UDim2.new(1, -16, 0, 40),
		LayoutOrder = 1,
	})
	buyButton.Instance.Position = UDim2.fromOffset(8, buttonY)
	buyButton.Clicked:Connect(function()
		requestDevProductPurchase(row.Key, nil)
	end)

	local extraButtons: { any } = {}
	local nextOrder = 2
	local nextY = buttonY + 44

	if showOddsButton then
		local oddsButton = Button.new({
			Parent = card,
			Text = "Chancen ansehen",
			Variant = "Secondary",
			Size = UDim2.new(1, -16, 0, 30),
			LayoutOrder = nextOrder,
		})
		oddsButton.Instance.Position = UDim2.fromOffset(8, nextY)
		oddsButton.Clicked:Connect(function()
			openMysteryEggOddsEvent:Fire()
		end)
		table.insert(extraButtons, oddsButton)
		nextOrder += 1
		nextY += 34
	end

	if RunService:IsStudio() then
		local studioButton = Button.new({
			Parent = card,
			Text = "Studio: Testkauf",
			Variant = "Ghost",
			Size = UDim2.new(1, -16, 0, 28),
			LayoutOrder = nextOrder,
		})
		studioButton.Instance.Position = UDim2.fromOffset(8, nextY)
		studioButton.Clicked:Connect(function()
			requestStudioPurchase("DevProduct", row.Key)
		end)
		table.insert(extraButtons, studioButton)
		nextY += 32
	end

	local handle = {} :: CardHandle
	handle.Destroy = function(_self)
		buyButton:Destroy()
		for _, button in extraButtons do
			button:Destroy()
		end
		card:Destroy()
	end
	return handle
end

-- // Kartenaufbau: Kosmetik -------------------------------------------------------

local function buildCosmeticCard(parent: Instance, layoutOrder: number, row: { [string]: any }): CardHandle
	local card = createCardFrame(parent, layoutOrder)
	local glyph = COSMETIC_GLYPH[row.Slot] or "🎨"
	local swatchColor = row.SwatchColor or Theme.Neon.Cyan
	makeNeonIcon(card, glyph, swatchColor, Theme.Neon.Violet)

	if row.Equipped then
		makeBanner(card, "Ausgerüstet", Theme.Neon.Cyan)
	elseif row.Owned then
		makeBanner(card, "Besitzt", Theme.Neon.ToxicGreen)
	end

	makeLabel({
		Parent = card,
		Text = row.Name,
		Size = UDim2.new(1, -80, 0, 22),
		Position = UDim2.fromOffset(78, 12),
		Font = Theme.Font.BodyBold,
		MinSize = 12,
		MaxSize = 17,
	})

	makeLabel({
		Parent = card,
		Text = row.Description,
		Size = UDim2.new(1, -16, 0, 48),
		Position = UDim2.fromOffset(8, 78),
		Color = Theme.Text.Secondary,
		MinSize = 10,
		MaxSize = 14,
		Wrapped = true,
	})

	local currencyGlyph = CURRENCY_GLYPH[row.Currency] or ""
	makeLabel({
		Parent = card,
		Text = currencyGlyph .. " " .. formatCoins(row.Price),
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 128),
		Font = Theme.Font.BodyBold,
		Color = if row.Currency == "AbyssalShards" then Theme.Neon.Violet else Theme.Neon.Cyan,
		MinSize = 14,
		MaxSize = 20,
	})

	local primaryButton: any
	if row.Equipped then
		primaryButton = Button.new({
			Parent = card,
			Text = "Ausgerüstet",
			Variant = "Ghost",
			Disabled = true,
			Size = UDim2.new(1, -16, 0, 40),
			LayoutOrder = 1,
		})
	elseif row.Owned then
		primaryButton = Button.new({
			Parent = card,
			Text = "Ausrüsten",
			Variant = "Success",
			Important = true,
			Size = UDim2.new(1, -16, 0, 40),
			LayoutOrder = 1,
		})
		primaryButton.Clicked:Connect(function()
			requestCosmeticEquip(row.Id, row.Name)
		end)
	else
		primaryButton = Button.new({
			Parent = card,
			Text = "Kaufen",
			Variant = "Primary",
			Important = true,
			Size = UDim2.new(1, -16, 0, 40),
			LayoutOrder = 1,
		})
		primaryButton.Clicked:Connect(function()
			requestCosmeticPurchase(row.Id, row.Name)
		end)
	end
	primaryButton.Instance.Position = UDim2.fromOffset(8, 168)

	local handle = {} :: CardHandle
	handle.Destroy = function(_self)
		primaryButton:Destroy()
		card:Destroy()
	end
	return handle
end

-- // Tab-Inhalte befüllen ---------------------------------------------------------

local function ensureGrids()
	if not tabsHandle then
		return
	end
	if not offerGrid then
		local offersContent = tabsHandle:GetContentFrame("Offers")
		offerCountdownLabel = makeLabel({
			Parent = offersContent,
			Text = "Nächste Rotation in --:--:--",
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.Font.BodyBold,
			Color = Theme.Neon.Cyan,
			MinSize = 12,
			MaxSize = 18,
		})
		offerCountdownLabel.LayoutOrder = 0
		offerGrid = createGridWrapper(offersContent, 1)
	end
	if not gamepassGrid then
		gamepassGrid = createGridWrapper(tabsHandle:GetContentFrame("Gamepasses"), 0)
	end
	if not devProductGrid then
		devProductGrid = createGridWrapper(tabsHandle:GetContentFrame("DevProducts"), 0)
	end
	if not mysteryEggGrid then
		mysteryEggGrid = createGridWrapper(tabsHandle:GetContentFrame("MysteryEgg"), 0)
	end
	if not cosmeticGrid then
		cosmeticGrid = createGridWrapper(tabsHandle:GetContentFrame("Cosmetics"), 0)
	end
end

local function rebuildOffersTab(catalog: ShopCatalog)
	if not offerGrid then
		return
	end
	offerGrid:ClearCards()
	local cosmeticsById: { [string]: { [string]: any } } = {}
	for _, row in catalog.Cosmetics do
		cosmeticsById[row.Id] = row
	end
	local order = 1
	for _, itemId in catalog.DailyOfferItemIds do
		local row = cosmeticsById[itemId]
		if row then
			local card = buildCosmeticCard(offerGrid.Frame, order, row)
			offerGrid:AddCard(card)
			order += 1
		end
	end
	if order == 1 then
		local emptyLabel = makeLabel({
			Parent = offerGrid.Frame,
			Text = "Heute keine Angebote – schau morgen wieder vorbei!",
			Size = UDim2.new(1, 0, 0, 30),
			Color = Theme.Text.Muted,
			MinSize = 12,
			MaxSize = 16,
		})
		offerGrid:AddCard({
			Destroy = function(_self)
				emptyLabel:Destroy()
			end,
		})
	end
end

local function rebuildGamepassesTab(catalog: ShopCatalog)
	if not gamepassGrid then
		return
	end
	gamepassGrid:ClearCards()
	for order, row in ipairs(catalog.Gamepasses) do
		local card = buildGamepassCard(gamepassGrid.Frame, order, row)
		gamepassGrid:AddCard(card)
	end
end

local function rebuildDevProductsTab(catalog: ShopCatalog)
	if not devProductGrid then
		return
	end
	devProductGrid:ClearCards()
	local order = 1
	for _, row in ipairs(catalog.DevProducts) do
		if row.Key ~= "MysteryEgg" then
			local card = buildDevProductCard(devProductGrid.Frame, order, row, false)
			devProductGrid:AddCard(card)
			order += 1
		end
	end
end

local function rebuildMysteryEggTab(catalog: ShopCatalog)
	if not mysteryEggGrid then
		return
	end
	mysteryEggGrid:ClearCards()
	for order, row in ipairs(catalog.DevProducts) do
		if row.Key == "MysteryEgg" then
			local card = buildDevProductCard(mysteryEggGrid.Frame, order, row, true)
			mysteryEggGrid:AddCard(card)
		end
	end
end

local function rebuildCosmeticsTab(catalog: ShopCatalog)
	if not cosmeticGrid then
		return
	end
	cosmeticGrid:ClearCards()
	for order, row in ipairs(catalog.Cosmetics) do
		local card = buildCosmeticCard(cosmeticGrid.Frame, order, row)
		cosmeticGrid:AddCard(card)
	end
end

local function refreshCurrencyHeader(catalog: ShopCatalog)
	local currencies = catalog.Currencies or {}
	local newTideCoins = (currencies.TideCoins :: number?) or 0
	local newAbyssalShards = (currencies.AbyssalShards :: number?) or 0

	if tideCoinsLabel then
		CountUp.Animate(tideCoinsLabel, lastTideCoins, newTideCoins, 0.6, function(value: number)
			return CURRENCY_GLYPH.TideCoins .. " " .. CountUp.DefaultFormat(value)
		end)
	end
	if abyssalShardsLabel then
		CountUp.Animate(abyssalShardsLabel, lastAbyssalShards, newAbyssalShards, 0.6, function(value: number)
			return CURRENCY_GLYPH.AbyssalShards .. " " .. CountUp.DefaultFormat(value)
		end)
	end
	lastTideCoins = newTideCoins
	lastAbyssalShards = newAbyssalShards
end

refreshAllTabsFromCatalog = function()
	local catalog = currentCatalog
	if not catalog or not tabsHandle then
		return
	end
	ensureGrids()
	rebuildOffersTab(catalog)
	rebuildGamepassesTab(catalog)
	rebuildDevProductsTab(catalog)
	rebuildMysteryEggTab(catalog)
	rebuildCosmeticsTab(catalog)
	refreshCurrencyHeader(catalog)
end

-- // Countdown-Loop (nur während Panel offen) ------------------------------------

local function stopCountdownLoop()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
end

local function startCountdownLoop()
	stopCountdownLoop()
	countdownThread = task.spawn(function()
		while true do
			if offerCountdownLabel then
				offerCountdownLabel.Text = "Nächste Rotation in " .. formatCountdown(secondsUntilNextUtcMidnight())
			end
			task.wait(1)
		end
	end)
end

-- // Panel-Aufbau -----------------------------------------------------------------

local function buildPanel()
	if panelHandle then
		return
	end

	panelHandle = Panel.new({
		Title = "Abyssara Shop",
		Closable = true,
		CenteredSize = UDim2.fromOffset(1040, 700),
		OnClose = function()
			stopCountdownLoop()
		end,
	})

	local content = panelHandle.Content

	local currencyBar = Instance.new("Frame")
	currencyBar.Name = "CurrencyBar"
	currencyBar.BackgroundTransparency = 1
	currencyBar.Size = UDim2.new(1, 0, 0, 28)
	currencyBar.Parent = content

	local currencyList = Instance.new("UIListLayout")
	currencyList.FillDirection = Enum.FillDirection.Horizontal
	currencyList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	currencyList.VerticalAlignment = Enum.VerticalAlignment.Center
	currencyList.Padding = UDim.new(0, 18)
	currencyList.Parent = currencyBar

	tideCoinsLabel = makeLabel({
		Parent = currencyBar,
		Text = CURRENCY_GLYPH.TideCoins .. " 0",
		Size = UDim2.fromOffset(140, 26),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Cyan,
		XAlign = Enum.TextXAlignment.Right,
		MinSize = 14,
		MaxSize = 20,
	})
	tideCoinsLabel.LayoutOrder = 1

	abyssalShardsLabel = makeLabel({
		Parent = currencyBar,
		Text = CURRENCY_GLYPH.AbyssalShards .. " 0",
		Size = UDim2.fromOffset(140, 26),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Violet,
		XAlign = Enum.TextXAlignment.Right,
		MinSize = 14,
		MaxSize = 20,
	})
	abyssalShardsLabel.LayoutOrder = 2

	local tabsHost = Instance.new("Frame")
	tabsHost.Name = "TabsHost"
	tabsHost.BackgroundTransparency = 1
	tabsHost.Size = UDim2.new(1, 0, 1, -34)
	tabsHost.Position = UDim2.fromOffset(0, 34)
	tabsHost.Parent = content

	tabsHandle = Tabs.new({
		Parent = tabsHost,
		Tabs = {
			{ Id = "Offers", Label = "Angebote" },
			{ Id = "Gamepasses", Label = "Gamepasses" },
			{ Id = "DevProducts", Label = "Robux-Pakete" },
			{ Id = "MysteryEgg", Label = "Mystery Egg" },
			{ Id = "Cosmetics", Label = "Kosmetik" },
		},
		DefaultTabId = "Offers",
	})

	ensureGrids()
end

-- // Öffnen/Schließen ---------------------------------------------------------

local function openShop()
	buildPanel()
	panelHandle:Open()
	startCountdownLoop()
	requestCatalog()
end

-- // Remote-Verdrahtung --------------------------------------------------------

ShopRemotes.ShopStateChanged.OnClientEvent:Connect(function(catalog: ShopCatalog)
	currentCatalog = catalog
	if panelHandle and panelHandle.ScreenGui.Enabled then
		refreshAllTabsFromCatalog()
	end
end)

ShopRemotes.PurchasePromptRejected.OnClientEvent:Connect(function(payload: { Reason: string?, ProductKey: string? })
	Toast.Show({
		Text = friendlyReason(payload and payload.Reason),
		Type = "Warning",
		Duration = 4,
	})
end)

local bridgeConnection = openShopEvent.Event:Connect(openShop)

-- // Hub-ProximityPrompt (ShopStand, Interactable == "Shop") ---------------------
-- Server legt hier noch keinen Prompt an (siehe assets/models/README.md
-- Abschnitt "hub") - rein clientseitige Interaktionshilfe ohne Gameplay-
-- Autorität ist zulässig, der eigentliche Kauf läuft immer über die
-- serverseitig validierten ShopRemotes-Kanäle oben.
local SHOP_PROMPT_NAME = "AbyssaraShopPrompt"
local attachedShopStands: { [Instance]: ProximityPrompt } = {}

local function attachShopPrompt(model: Instance)
	if attachedShopStands[model] then
		return
	end
	local anchor: BasePart? = nil
	local interactionPoint = model:FindFirstChild("InteractionPoint", true)
	if interactionPoint and interactionPoint:IsA("Attachment") then
		anchor = interactionPoint.Parent :: BasePart?
	end
	if not anchor then
		if model:IsA("BasePart") then
			anchor = model
		elseif model:IsA("Model") then
			anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	if not anchor then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = SHOP_PROMPT_NAME
	prompt.ActionText = "Shop öffnen"
	prompt.ObjectText = "Abyssara Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	attachedShopStands[model] = prompt

	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == localPlayer then
			openShop()
		end
	end)
end

local function scanForShopStand(root: Instance)
	if root:GetAttribute("Interactable") == "Shop" then
		attachShopPrompt(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:GetAttribute("Interactable") == "Shop" then
			attachShopPrompt(descendant)
		end
	end
end

scanForShopStand(Workspace)
local descendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant: Instance)
	if descendant:GetAttribute("Interactable") == "Shop" then
		attachShopPrompt(descendant)
	end
end)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	stopCountdownLoop()
	bridgeConnection:Disconnect()
	descendantAddedConnection:Disconnect()
	if offerGrid then
		offerGrid:Destroy()
	end
	if gamepassGrid then
		gamepassGrid:Destroy()
	end
	if devProductGrid then
		devProductGrid:Destroy()
	end
	if mysteryEggGrid then
		mysteryEggGrid:Destroy()
	end
	if cosmeticGrid then
		cosmeticGrid:Destroy()
	end
	if tabsHandle then
		tabsHandle:Destroy()
	end
	if panelHandle then
		panelHandle:Destroy()
	end
end)
