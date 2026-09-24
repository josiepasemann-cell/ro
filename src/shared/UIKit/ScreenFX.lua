--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.ScreenFX
	Zuständigkeit:
		Bildschirmweite FX-Helfer für große Momente (Level-Up, Mythic-
		Gacha-Drop): Flash (Vollbild-Farbblitz, ausblendend) und Shake
		(kurzes Kamera-Wackeln).

		BEWUSSTE DESIGN-ENTSCHEIDUNG zu Shake: Es wird NICHT versucht,
		workspace.CurrentCamera.CFrame direkt zu setzen/zu "besitzen" (das
		würde mit anderen, hier nicht besessenen Kamera-Skripten
		konkurrieren, z. B. PlacementPreviewController.client.lua).
		Stattdessen wird RunService:BindToRenderStep(...) mit einer
		Priorität von Enum.RenderPriority.Camera.Value + 1 genutzt - das
		garantiert, dass unser additiver Mini-Offset JEDEN Frame NACH dem
		regulären Kamera-Update angewendet wird (rein additiv relativ zur
		jeweils aktuellen CFrame, kein gespeicherter Zustand über Frames
		hinweg außer dem Zufalls-Offset selbst) und beim Zeitablauf sauber
		mit UnbindFromRenderStep wieder entfernt wird. Das ist die in der
		Roblox-Community etablierte, konfliktfreie Methode für Screen-Shake
		ohne Kamera-Ownership zu übernehmen.

	Rojo-Einhängepunkt:
		src/shared/UIKit/ScreenFX.lua -> ReplicatedStorage.UIKit.ScreenFX
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Settings = require(script.Parent:WaitForChild("Settings"))

local SHAKE_BINDING_NAME = "UIKitScreenShake"

export type FlashProps = {
	Color: Color3?,
	Duration: number?,
	MaxTransparency: number?,
}

local ScreenFX = {}

local overlayGui: ScreenGui? = nil
local flashFrame: Frame? = nil

local function getPlayerGui(): PlayerGui
	local player = Players.LocalPlayer
	assert(player, "UIKit.ScreenFX kann nur clientseitig verwendet werden")
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function ensureInit()
	if overlayGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UIKitScreenFX"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.Parent = getPlayerGui()

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 200
	flash.Parent = gui

	overlayGui = gui
	flashFrame = flash
end

-- Vollbild-Farbblitz, der schnell ausblendet (z. B. Mythic-Drop, Level-Up).
function ScreenFX.Flash(props: FlashProps?)
	if Settings.ShouldSkipFX() then
		return
	end
	ensureInit()
	local flash = flashFrame :: Frame
	local color = (props and props.Color) or Color3.fromRGB(255, 255, 255)
	local duration = (props and props.Duration) or 0.5
	local maxTransparency = (props and props.MaxTransparency) or 0.25

	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = maxTransparency
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
end

local shakeToken = 0

-- Kurzer, additiver Kamera-Shake (siehe Design-Entscheidung im Kopf-
-- kommentar). `magnitudeStuds` ist die maximale Auslenkung in Studs
-- (klein halten, 0.1-0.3 wirkt bereits deutlich), `duration` in Sekunden.
function ScreenFX.Shake(magnitudeStuds: number?, duration: number?)
	if Settings.ShouldSkipFX() then
		return
	end

	local strength = magnitudeStuds or 0.22
	local totalDuration = duration or 0.35

	shakeToken += 1
	local myToken = shakeToken

	local startTime = os.clock()
	pcall(function()
		RunService:UnbindFromRenderStep(SHAKE_BINDING_NAME)
	end)
	RunService:BindToRenderStep(SHAKE_BINDING_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if myToken ~= shakeToken then
			return
		end
		local elapsed = os.clock() - startTime
		if elapsed >= totalDuration then
			RunService:UnbindFromRenderStep(SHAKE_BINDING_NAME)
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local falloff = 1 - (elapsed / totalDuration)
		local offset = Vector3.new(
			(math.random() * 2 - 1) * strength * falloff,
			(math.random() * 2 - 1) * strength * falloff,
			0
		)
		camera.CFrame *= CFrame.new(offset)
	end)
end

-- Kombi-Helfer für die ganz großen Momente (z. B. Mythic-Gacha-Drop):
-- Flash + Shake gleichzeitig.
function ScreenFX.BigMoment(color: Color3?)
	ScreenFX.Flash({ Color = color, Duration = 0.6, MaxTransparency = 0.15 })
	ScreenFX.Shake(0.3, 0.45)
end

return ScreenFX
