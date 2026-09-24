--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: UI – Odds-Display-Panel (reines Layout-Grundgerüst)
	Name: GachaOddsPanel
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)" -> "Odds-Display-UI-Panel (Drop-Tabelle-Anzeige
	vor Kauf)". Roblox verlangt bei virtuellen Zufallsgütern offengelegte
	Wahrscheinlichkeiten – dieses Panel ist die reine Layout-Hülle dafür.

	Beschreibung:
		ScreenGui mit einem zentrierten, abgerundeten Panel: Titel-Zeile,
		Liste mit einer Zeile pro Rarity-Stufe (Farb-Swatch + Name +
		Platzhalter-Prozentwert) und einem Schließen-Button unten.

	WICHTIG: Dies ist AUSSCHLIESSLICH ein visuelles UI-Grundgerüst.
		- Es lädt/berechnet KEINE echten Drop-Wahrscheinlichkeiten. Die
		  angezeigten Prozentwerte sind reine Platzhalter-Texte (Summe = 100,
		  rein zur Layout-Kontrolle), NICHT synchron zu einer echten
		  Drop-Tabelle.
		- Es enthält KEIN LocalScript/Script mit Funktions-Logik. Der
		  Schließen-Button hat keinerlei Click-Verbindung – das kommt bewusst
		  erst später durch den Code-Agenten.
		- Keine Gacha-/Zufalls-/Kauf-/Persistenz-Logik.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- ScreenGui "GachaOddsUI" -> Wurzel-Container, DisplayOrder/Enabled
		  vom Code-Agenten später nach Bedarf gesteuert (hier: Enabled = false
		  als Startzustand, da rein durch UI-Aktion einzublenden).
		- Frame "OddsPanel" -> Hauptpanel (PrimaryPart-Äquivalent für UI: das
		  Objekt, dessen Visible der Code-Agent umschaltet, um das Panel
		  ein-/auszublenden).
		- TextLabel "TitleLabel" -> Panel-Titel.
		- Frame "RarityList" (mit UIListLayout) -> Container für die
		  Rarity-Zeilen. Enthält 6 Zeilen, benannt "RarityRow_<Tier>"
		  (Tier = Common/Uncommon/Rare/Epic/Legendary/Mythic, konsistent zur
		  EggTier-Konvention der MysteryEgg_*-Modelle).
		- Jede Zeile enthält: Frame "ColorSwatch" (Rarity-Akzentfarbe),
		  TextLabel "NameLabel" und TextLabel "PercentLabel"
		  (`PercentLabel.Text` ist der auszutauschende Platzhalter-Wert –
		  Attribut `PercentLabel:SetAttribute("PlaceholderOnly", true)`
		  markiert das explizit für den Code-Agenten).
		- TextButton "CloseButton" -> rein visueller Button ohne
		  MouseButton1Click-Verbindung.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script
		unter ServerScriptService einfügen und einmal laufen lassen (baut unter
		game.StarterGui, damit es neuen Spielern automatisch zur Verfügung
		steht; ProcessReceipt/Anzeigelogik kommt später). Wiederholtes
		Ausführen ist sicher (idempotent).
]]

local StarterGui = game:GetService("StarterGui")

-- // Konfiguration -------------------------------------------------------
-- Platzhalter-Prozentwerte (Layout-Test, Summe = 100 %). KEINE echte
-- Drop-Tabelle – wird vom Code-Agenten später an GachaService gebunden.
local RARITY_ROWS = {
	{ tier = "Common", label = "Gewöhnlich", percent = "45.0%", color = Color3.fromRGB(215, 250, 245) },
	{ tier = "Uncommon", label = "Ungewöhnlich", percent = "27.0%", color = Color3.fromRGB(120, 235, 205) },
	{ tier = "Rare", label = "Selten", percent = "16.0%", color = Color3.fromRGB(70, 210, 235) },
	{ tier = "Epic", label = "Episch", percent = "8.0%", color = Color3.fromRGB(170, 90, 255) },
	{ tier = "Legendary", label = "Legendär", percent = "3.5%", color = Color3.fromRGB(150, 70, 255) },
	{ tier = "Mythic", label = "Mythisch", percent = "0.5%", color = Color3.fromRGB(135, 60, 255) },
}
-- // ----------------------------------------------------------------------

local function newInstance(className, properties, parent)
	local inst = Instance.new(className)
	for property, value in pairs(properties) do
		inst[property] = value
	end
	inst.Parent = parent
	return inst
end

-- Idempotenz: vorheriges Panel entfernen -------------------------------------
local previous = StarterGui:FindFirstChild("GachaOddsUI")
if previous then
	previous:Destroy()
end

-- 1) ScreenGui-Wurzel ----------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GachaOddsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false -- Start ausgeblendet; Einblenden ist spätere UI-Logik
screenGui.Parent = StarterGui

-- 2) Halbtransparenter Hintergrund-Dimmer (rein optisch, kein Click-Fang-Skript) --
local dimmer = newInstance("Frame", {
	Name = "Dimmer",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	ZIndex = 1,
}, screenGui)

-- 3) Hauptpanel ------------------------------------------------------------------
local panel = newInstance("Frame", {
	Name = "OddsPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 430),
	BackgroundColor3 = Color3.fromRGB(18, 28, 38),
	BorderSizePixel = 0,
	ZIndex = 2,
}, dimmer)

newInstance("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
newInstance("UIStroke", {
	Color = Color3.fromRGB(90, 220, 255),
	Thickness = 2,
	Transparency = 0.3,
}, panel)
newInstance("UIPadding", {
	PaddingTop = UDim.new(0, 18),
	PaddingBottom = UDim.new(0, 16),
	PaddingLeft = UDim.new(0, 20),
	PaddingRight = UDim.new(0, 20),
}, panel)

-- 4) Titel -------------------------------------------------------------------------
local titleLabel = newInstance("TextLabel", {
	Name = "TitleLabel",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Text = "Mystery Egg – Drop-Chancen",
	TextColor3 = Color3.fromRGB(200, 245, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
}, panel)

local subtitleLabel = newInstance("TextLabel", {
	Name = "SubtitleLabel",
	Position = UDim2.new(0, 0, 0, 40),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Text = "Offengelegte Wahrscheinlichkeiten pro Öffnung (Platzhalter)",
	TextColor3 = Color3.fromRGB(140, 190, 205),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
}, panel)

-- 5) Rarity-Zeilen-Liste -------------------------------------------------------------
local rarityList = newInstance("Frame", {
	Name = "RarityList",
	Position = UDim2.new(0, 0, 0, 72),
	Size = UDim2.new(1, 0, 1, -72 - 56),
	BackgroundTransparency = 1,
	ZIndex = 2,
}, panel)

newInstance("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, rarityList)

for i, row in ipairs(RARITY_ROWS) do
	local rowFrame = newInstance("Frame", {
		Name = "RarityRow_" .. row.tier,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(26, 38, 50),
		BorderSizePixel = 0,
		LayoutOrder = i,
		ZIndex = 2,
	}, rarityList)
	newInstance("UICorner", { CornerRadius = UDim.new(0, 8) }, rowFrame)
	newInstance("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, rowFrame)

	local swatch = newInstance("Frame", {
		Name = "ColorSwatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = row.color,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, rowFrame)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, swatch)

	local nameLabel = newInstance("TextLabel", {
		Name = "NameLabel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 34, 0.5, 0),
		Size = UDim2.new(0.6, -34, 0.8, 0),
		BackgroundTransparency = 1,
		Text = row.label,
		TextColor3 = Color3.fromRGB(225, 240, 245),
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, rowFrame)
	nameLabel:SetAttribute("EggTier", row.tier)

	local percentLabel = newInstance("TextLabel", {
		Name = "PercentLabel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.3, 0, 0.8, 0),
		BackgroundTransparency = 1,
		Text = row.percent,
		TextColor3 = row.color,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	}, rowFrame)
	-- Markiert für den Code-Agenten: dieser Wert ist NUR ein Layout-Platzhalter
	-- und muss durch die echte, serverseitig synchrone Drop-Tabelle ersetzt werden.
	percentLabel:SetAttribute("PlaceholderOnly", true)
end

-- 6) Fußzeile mit Compliance-Hinweistext (Platzhalter) -------------------------------
local footerLabel = newInstance("TextLabel", {
	Name = "FooterNote",
	Position = UDim2.new(0, 0, 1, -56),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Text = "Chancen gelten pro einzelner Ei-Öffnung. Kein Kauf-Zwang.",
	TextColor3 = Color3.fromRGB(120, 150, 165),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
}, panel)

-- 7) Schließen-Button (rein visuell, keine Click-Verbindung) -------------------------
local closeButton = newInstance("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = Color3.fromRGB(90, 220, 255),
	BorderSizePixel = 0,
	Text = "Schließen",
	TextColor3 = Color3.fromRGB(10, 20, 28),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	AutoButtonColor = true,
	ZIndex = 3,
}, panel)
newInstance("UICorner", { CornerRadius = UDim.new(0, 10) }, closeButton)

print("[Abyssara] GachaOddsPanel erzeugt unter game.StarterGui.GachaOddsUI (rein visuelles Layout, ohne Funktions-Logik)")
