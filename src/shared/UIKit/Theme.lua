--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Theme
	Zuständigkeit:
		Einzige Quelle der Wahrheit für Farben, Schriften und
		Stil-Hilfsfunktionen (Gradient/Stroke) des UIKits. Neon-Palette
		passend zum Biolumineszenz-Thema auf dunklem Tiefsee-Hintergrund.

		Rarity.* MUSS farblich konsistent mit
		src/server/GachaConfig.lua (GachaConfig.DROP_TABLE[*].Color) und
		src/shared/BreedingConfig.lua (BreedingConfig.RARITY_DEFINITIONS)
		bleiben - Werte hier sind 1:1 von dort übernommen. Wird eine dieser
		Konfigurationen künftig geändert, hier nachziehen.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Theme.lua -> ReplicatedStorage.UIKit.Theme
]]

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

local Theme = {}

-- // Tiefsee-Hintergrundtöne ------------------------------------------------
Theme.Background = {
	Deepest = Color3.fromRGB(4, 10, 18),
	Deep = Color3.fromRGB(7, 16, 27),
	Panel = Color3.fromRGB(10, 22, 36),
	PanelLight = Color3.fromRGB(15, 32, 50),
	Divider = Color3.fromRGB(26, 52, 70),
}

-- // Grelle Neon-Palette (Biolumineszenz) -----------------------------------
Theme.Neon = {
	Cyan = Color3.fromRGB(0, 245, 255),
	Magenta = Color3.fromRGB(255, 0, 200),
	ToxicGreen = Color3.fromRGB(130, 255, 60),
	Orange = Color3.fromRGB(255, 130, 0),
	Violet = Color3.fromRGB(160, 70, 255),
	Yellow = Color3.fromRGB(255, 232, 40),
}

-- // Text ---------------------------------------------------------------
Theme.Text = {
	Primary = Color3.fromRGB(235, 250, 255),
	Secondary = Color3.fromRGB(155, 195, 215),
	Muted = Color3.fromRGB(95, 125, 145),
	Stroke = Color3.fromRGB(2, 6, 10), -- Kontrast-Umrandung für Lesbarkeit auf grellen Flächen
	OnNeon = Color3.fromRGB(6, 10, 14), -- dunkler Text auf sehr hellen Neon-Buttons
}

-- // Semantik-Farben (Buttons/Status) ---------------------------------------
Theme.Semantic = {
	Primary = Theme.Neon.Cyan,
	Secondary = Theme.Neon.Violet,
	Success = Theme.Neon.ToxicGreen,
	Danger = Color3.fromRGB(255, 60, 90),
	Warning = Theme.Neon.Orange,
	Info = Theme.Neon.Cyan,
}

-- // Rarity-Farben (MUSS zu GachaConfig.DROP_TABLE / BreedingConfig passen) --
Theme.Rarity = {
	Common = Color3.fromRGB(215, 250, 245),
	Uncommon = Color3.fromRGB(120, 235, 205),
	Rare = Color3.fromRGB(70, 210, 235),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(150, 70, 255),
	Mythic = Color3.fromRGB(135, 60, 255),
} :: { [Rarity]: Color3 }

Theme.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { Rarity }

Theme.RarityLabel = {
	Common = "Common",
	Uncommon = "Uncommon",
	Rare = "Rare",
	Epic = "Epic",
	Legendary = "Legendary",
	Mythic = "Mythic",
} :: { [Rarity]: string }

-- // Schriften -------------------------------------------------------------
Theme.Font = {
	Header = Enum.Font.GothamBlack,
	Body = Enum.Font.GothamMedium,
	BodyBold = Enum.Font.GothamBold,
	Mono = Enum.Font.RobotoMono,
}

Theme.CornerRadius = UDim.new(0, 12)
Theme.StrokeThickness = 2

-- // Stil-Hilfsfunktionen ---------------------------------------------------

-- Fügt einem GuiObject eine lesbare Kontur hinzu (dunkle Umrandung um
-- helle Neon-/Textflächen für Kontrast auf grellem Hintergrund).
function Theme.ApplyStroke(target: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Text.Stroke
	stroke.Thickness = thickness or Theme.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = target
	return stroke
end

-- Fügt eine Diagonal-Gradient über zwei oder mehr Farben hinzu (z. B. für
-- Button-Hintergründe/Panel-Header).
function Theme.ApplyGradient(target: GuiObject, colors: { Color3 }, rotation: number?): UIGradient
	local keypoints = {}
	local count = #colors
	for index, color in colors do
		local time = count == 1 and 0 or (index - 1) / (count - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(time, color))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keypoints)
	gradient.Rotation = rotation or 90
	gradient.Parent = target
	return gradient
end

function Theme.ApplyCorner(target: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius
	corner.Parent = target
	return corner
end

return Theme
