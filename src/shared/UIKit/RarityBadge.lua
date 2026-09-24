--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.RarityBadge
	Zuständigkeit:
		Kleines Abzeichen zur Anzeige einer Kreaturen-/Item-Rarity, farblich
		konsistent mit UIKit.Theme.Rarity (== GachaConfig.DROP_TABLE /
		BreedingConfig.RARITY_DEFINITIONS). Für Common..Mythic geeignet
		(Zucht-Ergebnisse nutzen nur Common..Legendary, Gacha zusätzlich
		Mythic - dieses Widget deckt beide Quellen ab).

	Rojo-Einhängepunkt:
		src/shared/UIKit/RarityBadge.lua -> ReplicatedStorage.UIKit.RarityBadge
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

export type RarityBadgeProps = {
	Parent: Instance,
	Rarity: Theme.Rarity,
	Size: UDim2?,
	Position: UDim2?,
}

export type RarityBadgeHandle = {
	Instance: Frame,
	SetRarity: (self: RarityBadgeHandle, rarity: Theme.Rarity) -> (),
	Destroy: (self: RarityBadgeHandle) -> (),
}

local RarityBadge = {}

function RarityBadge.new(props: RarityBadgeProps): RarityBadgeHandle
	local frame = Instance.new("Frame")
	frame.Name = "RarityBadge"
	frame.BackgroundColor3 = Theme.Background.Deepest
	frame.Size = props.Size or UDim2.fromOffset(96, 26)
	if props.Position then
		frame.Position = props.Position
	end
	frame.Parent = props.Parent
	Theme.ApplyCorner(frame, UDim.new(1, 0))
	local stroke = Theme.ApplyStroke(frame, Theme.Rarity[props.Rarity], 2)
	local gradient = Theme.ApplyGradient(frame, { Theme.Rarity[props.Rarity], Theme.Background.Deepest }, 0)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.85),
	})

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -8, 1, 0)
	label.Position = UDim2.fromOffset(4, 0)
	label.Font = Theme.Font.BodyBold
	label.TextColor3 = Theme.Rarity[props.Rarity]
	label.Text = Theme.RarityLabel[props.Rarity]
	label.TextScaled = true
	label.Parent = frame
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 11
	constraint.MaxTextSize = 16
	constraint.Parent = label
	Theme.ApplyStroke(label, Theme.Text.Stroke, 1)

	local handle = {} :: RarityBadgeHandle
	handle.Instance = frame

	handle.SetRarity = function(_self, rarity: Theme.Rarity)
		stroke.Color = Theme.Rarity[rarity]
		gradient.Color = ColorSequence.new(Theme.Rarity[rarity], Theme.Background.Deepest)
		label.TextColor3 = Theme.Rarity[rarity]
		label.Text = Theme.RarityLabel[rarity]
	end

	handle.Destroy = function(_self)
		frame:Destroy()
	end

	return handle
end

return RarityBadge
