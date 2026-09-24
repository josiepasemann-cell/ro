--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.ProgressBar
	Zuständigkeit:
		Fortschrittsbalken mit Neon-Gradient-Füllung und weicher Tween-
		Animation zwischen Werten (z. B. Inkubationsfortschritt Brutbecken,
		Idle-Einkommen-Kapazität, XP-Balken).

	Rojo-Einhängepunkt:
		src/shared/UIKit/ProgressBar.lua -> ReplicatedStorage.UIKit.ProgressBar
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

export type ProgressBarProps = {
	Parent: Instance,
	Size: UDim2?,
	Value: number?, -- 0..1
	Colors: { Color3 }?,
}

export type ProgressBarHandle = {
	Track: Frame,
	Fill: Frame,
	SetProgress: (self: ProgressBarHandle, value: number, animated: boolean?) -> (),
	Destroy: (self: ProgressBarHandle) -> (),
}

local ProgressBar = {}

function ProgressBar.new(props: ProgressBarProps): ProgressBarHandle
	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Theme.Background.Deepest
	track.Size = props.Size or UDim2.new(1, 0, 0, 18)
	track.ClipsDescendants = true
	track.Parent = props.Parent
	Theme.ApplyCorner(track, UDim.new(1, 0))
	Theme.ApplyStroke(track, Theme.Background.Divider, 1.5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(math.clamp(props.Value or 0, 0, 1), 0, 1, 0)
	fill.Parent = track
	Theme.ApplyCorner(fill, UDim.new(1, 0))
	Theme.ApplyGradient(fill, props.Colors or { Theme.Neon.Cyan, Theme.Neon.Violet }, 0)

	local handle = {} :: ProgressBarHandle
	handle.Track = track
	handle.Fill = fill

	handle.SetProgress = function(_self, value: number, animated: boolean?)
		local clamped = math.clamp(value, 0, 1)
		if animated == false then
			fill.Size = UDim2.new(clamped, 0, 1, 0)
		else
			TweenService:Create(
				fill,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(clamped, 0, 1, 0) }
			):Play()
		end
	end

	handle.Destroy = function(_self)
		track:Destroy()
	end

	return handle
end

return ProgressBar
