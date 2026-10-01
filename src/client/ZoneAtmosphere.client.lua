--!strict
--[[
	Abyssara - Deep Tide Tycoon
	Script: ZoneAtmosphere (client)
	Responsibility:
		Gives every zone its own lighting / fog / colour-grading mood (sunny turquoise reef, violet dusk,
		red-black volcanic night, pale deep-ice fog, cozy teal harbour) by blending Lighting, the
		DeepTideAtmosphere, DeepTideColorCorrection and DeepTideBloom objects that WorldSetup.server.lua
		creates. Profiles live in WorldAmbienceConfig.Atmosphere (keyed by zone name); the zone is derived
		from the character position (camera as fallback) with WorldAmbienceConfig.Zones, so it follows
		teleports from TravelService without any extra remote.

	Notes
		- Local only. Nothing replicates; the server keeps its deep-sea defaults as the fallback mood.
		- ColorCorrection.Brightness is NOT touched (WorldSetup flickers it on the server).
		- Live events (LiveEventService tweens Ambient/Fog on the server): while an event runs, the server
		  values win. When the server values return to the Baseline* attributes this script re-applies the
		  current zone profile.
		- Sets LocalPlayer attribute "CurrentZone" (Hub, SunZone, TwilightZone, MidnightZone, HadalDepths,
		  Plots) for other client scripts.

	Rojo mount: src/client/ZoneAtmosphere.client.lua -> StarterPlayerScripts.ZoneAtmosphere
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("WorldAmbienceConfig"))
local player = Players.LocalPlayer

local atmosphere = Lighting:WaitForChild("DeepTideAtmosphere", 20) :: Atmosphere?
local colorCorrection = Lighting:WaitForChild("DeepTideColorCorrection", 20) :: ColorCorrectionEffect?
local bloom = Lighting:WaitForChild("DeepTideBloom", 20) :: BloomEffect?

local currentZone: string? = nil
local activeTweens: { Tween } = {}

local function profileFor(zoneName: string)
	return Config.Atmosphere[zoneName] or Config.Atmosphere.Hub
end

local function tween(instance: Instance, props: { [string]: any }, seconds: number)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
	table.insert(activeTweens, t)
	t:Play()
end

local function applyProfile(zoneName: string, instant: boolean)
	local p = profileFor(zoneName)
	local seconds = if instant then 0.01 else Config.AtmosphereBlendSeconds
	for _, t in ipairs(activeTweens) do
		t:Cancel()
	end
	table.clear(activeTweens)

	tween(Lighting, {
		ClockTime = p.ClockTime,
		Brightness = p.Brightness,
		Ambient = p.Ambient,
		OutdoorAmbient = p.OutdoorAmbient,
		FogColor = p.FogColor,
		FogStart = p.FogStart,
		FogEnd = p.FogEnd,
	}, seconds)
	if atmosphere then
		tween(atmosphere, {
			Color = p.AtmosphereColor,
			Decay = p.AtmosphereDecay,
			Density = p.Density,
			Offset = p.Offset,
			Haze = p.Haze,
			Glare = p.Glare,
		}, seconds)
	end
	if colorCorrection then
		tween(colorCorrection, { TintColor = p.Tint, Saturation = p.Saturation, Contrast = p.Contrast }, seconds)
	end
	if bloom then
		-- touch devices: smaller bloom radius (cheaper)
		local size = if (game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").KeyboardEnabled)
			then math.floor(p.BloomSize * 0.6)
			else p.BloomSize
		tween(bloom, { Intensity = p.BloomIntensity, Size = size, Threshold = p.BloomThreshold }, seconds)
	end
end

local function zoneAt(position: Vector3): string
	local best, bestScore = "Hub", math.huge
	for _, zone in ipairs(Config.Zones) do
		local d = (Vector3.new(position.X, 0, position.Z) - Vector3.new(zone.Center.X, 0, zone.Center.Z)).Magnitude
		local score = d / zone.Radius
		if score < 1 and score < bestScore then
			best, bestScore = zone.Name, score
		end
	end
	if best == "Plots" then
		return "Hub"
	end
	return best
end

local function currentPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function refresh(forceInstant: boolean)
	local pos = currentPosition()
	if not pos then
		return
	end
	local zone = zoneAt(pos)
	if zone ~= currentZone then
		local first = currentZone == nil
		currentZone = zone
		player:SetAttribute("CurrentZone", zone)
		applyProfile(zone, first or forceInstant)
	end
end

-- Live events: when the server values come back to the baseline, restore the zone mood.
local function serverBackToBaseline()
	local ambient = Lighting:GetAttribute("BaselineAmbient")
	local fogEnd = Lighting:GetAttribute("BaselineFogEnd")
	if typeof(ambient) == "Color3" and type(fogEnd) == "number" then
		return Lighting.FogEnd == fogEnd and Lighting.Ambient == ambient
	end
	return false
end
Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
	if currentZone and serverBackToBaseline() then
		applyProfile(currentZone, false)
	end
end)

refresh(true)
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed >= Config.AtmosphereCheckInterval then
		elapsed = 0
		refresh(false)
	end
end)
