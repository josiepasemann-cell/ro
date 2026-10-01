--!strict
--[[
	Abyssara - Deep Tide Tycoon
	Module: WorldAmbienceConfig
	Responsibility:
		All tuning knobs of src/client/WorldAmbience.client.lua in one place:
		CollectionService tag names, quality tiers (distance LOD, update
		rates, frame budgets, creature counts), zone palettes and the
		"occasional ambient creature swims past" settings.
		See docs/world-ambience.md for how the tags are used by the
		buildscripts in assets/models/world/.

	Rojo mount: src/shared/WorldAmbienceConfig.lua -> ReplicatedStorage.WorldAmbienceConfig
]]

export type QualityTier = {
	Enabled: boolean,
	-- Distance LOD (studs from the camera). Near: animated every frame.
	-- Mid: animated at MidInterval. Far: animated at FarInterval. Beyond: frozen.
	NearDistance: number,
	MidDistance: number,
	FarDistance: number,
	MidInterval: number,
	FarInterval: number,
	MaxPartMovesPerFrame: number, -- hard cap of BulkMoveTo entries per frame
	Sway: boolean,
	Pulse: boolean,
	Flicker: boolean,
	Motion: boolean, -- WA_Rotate / WA_Bob
	BubbleDistance: number, -- 0 = bubble emitters off
	BubbleRateScale: number,
	SchoolSpawnDistance: number, -- schools exist only while the camera is this close
	SchoolCountScale: number,
	MaxCreatures: number, -- total ambient creatures alive at once (schools + pass-bys)
	PassBy: boolean,
	PassByInterval: { number }, -- {min, max} seconds between pass-bys
	PlanktonRate: number, -- 0 = camera-attached plankton off
}

export type ZoneInfo = {
	Name: string,
	Center: Vector3,
	Radius: number,
	Plankton: Color3,
	PassBy: { { Kind: string, Size: number, Color: Color3, Color2: Color3, Group: number } },
}

local WorldAmbienceConfig = {}

-- // Tags (set by the buildscripts in assets/models/world/) ----------------------
WorldAmbienceConfig.Tags = {
	Sway = "WA_Sway", -- Model or Part: bends with the current (kelp, anemones, seagrass, vines)
	Pulse = "WA_Pulse", -- Model or Part: neon transparency + light brightness breathe
	Flicker = "WA_Flicker", -- Part or Model: lantern flicker
	Rotate = "WA_Rotate", -- Model or Part: slow spin around the vertical axis (light shafts)
	Bob = "WA_Bob", -- Model or Part: gentle float up/down (+ optional spin)
	Bubbles = "WA_Bubbles", -- Part holding ParticleEmitter(s): distance/quality gated
	School = "WA_School", -- invisible marker Part: the client spawns local fish/jelly/rays
}

-- Tags of the gameplay animator (ModelAnimator). Instances under these are never touched.
WorldAmbienceConfig.ProtectedAncestorNames = { "Buildings" }

-- // Quality ----------------------------------------------------------------------
-- Override at runtime with the attribute `WorldAmbienceQuality` ("High" | "Medium" |
-- "Low" | "Off") on the LocalPlayer or on Workspace. UIKit.Settings "Reduced
-- Effects" forces "Low". Touch-only devices default to "Medium".
WorldAmbienceConfig.QualityAttribute = "WorldAmbienceQuality"
WorldAmbienceConfig.DefaultDesktop = "High"
WorldAmbienceConfig.DefaultTouch = "Medium"
WorldAmbienceConfig.ReducedEffectsTier = "Low"

WorldAmbienceConfig.Quality = {
	High = {
		Enabled = true,
		NearDistance = 80,
		MidDistance = 150,
		FarDistance = 230,
		MidInterval = 1 / 24,
		FarInterval = 1 / 8,
		MaxPartMovesPerFrame = 500,
		Sway = true,
		Pulse = true,
		Flicker = true,
		Motion = true,
		BubbleDistance = 130,
		BubbleRateScale = 1,
		SchoolSpawnDistance = 150,
		SchoolCountScale = 1,
		MaxCreatures = 40,
		PassBy = true,
		PassByInterval = { 45, 100 },
		PlanktonRate = 6,
	},
	Medium = {
		Enabled = true,
		NearDistance = 55,
		MidDistance = 110,
		FarDistance = 160,
		MidInterval = 1 / 15,
		FarInterval = 1 / 5,
		MaxPartMovesPerFrame = 260,
		Sway = true,
		Pulse = true,
		Flicker = true,
		Motion = true,
		BubbleDistance = 90,
		BubbleRateScale = 0.6,
		SchoolSpawnDistance = 110,
		SchoolCountScale = 0.6,
		MaxCreatures = 22,
		PassBy = true,
		PassByInterval = { 70, 140 },
		PlanktonRate = 3,
	},
	Low = {
		Enabled = true,
		NearDistance = 35,
		MidDistance = 60,
		FarDistance = 90,
		MidInterval = 1 / 8,
		FarInterval = 1 / 3,
		MaxPartMovesPerFrame = 100,
		Sway = true,
		Pulse = false,
		Flicker = false,
		Motion = false,
		BubbleDistance = 45,
		BubbleRateScale = 0.35,
		SchoolSpawnDistance = 70,
		SchoolCountScale = 0.35,
		MaxCreatures = 8,
		PassBy = false,
		PassByInterval = { 90, 180 },
		PlanktonRate = 0,
	},
	Off = {
		Enabled = false,
		NearDistance = 0,
		MidDistance = 0,
		FarDistance = 0,
		MidInterval = 1,
		FarInterval = 1,
		MaxPartMovesPerFrame = 0,
		Sway = false,
		Pulse = false,
		Flicker = false,
		Motion = false,
		BubbleDistance = 0,
		BubbleRateScale = 0,
		SchoolSpawnDistance = 0,
		SchoolCountScale = 0,
		MaxCreatures = 0,
		PassBy = false,
		PassByInterval = { 999, 999 },
		PlanktonRate = 0,
	},
} :: { [string]: QualityTier }

-- // Glow animation strength (less eye strain) -----------------------------------------------------
-- Only a handful of props are Neon now (lanterns, crystals, portals), so the remaining pulse / flicker is
-- deliberately gentle: pulse depth is scaled down and lantern flicker only dips a little.
WorldAmbienceConfig.PulseDepthScale = 0.55 -- multiplies every WA_Depth (1 = old strength)
WorldAmbienceConfig.FlickerMin = 0.72 -- lowest brightness factor of a flickering lantern (was 0.3)
WorldAmbienceConfig.FlickerDipFactor = 0.85 -- the occasional dip multiplies by this (was 0.55)

-- // Timing / motion ---------------------------------------------------------------
WorldAmbienceConfig.LodRecomputeInterval = 0.35 -- seconds between distance classifications
WorldAmbienceConfig.SchoolDespawnExtra = 40 -- hysteresis: despawn this far beyond the spawn distance
WorldAmbienceConfig.SwayDefaultAmpDeg = 6
WorldAmbienceConfig.SwayDefaultSpeed = 0.8
WorldAmbienceConfig.PlanktonBox = Vector3.new(90, 40, 90)

-- Passing creatures: spawn on a ring around the camera and cross it.
WorldAmbienceConfig.PassByRingRadius = 140
WorldAmbienceConfig.PassBySpeed = { 9, 15 } -- studs/second
WorldAmbienceConfig.PassByHeight = { -6, 26 } -- relative to the camera

-- // Zones (world positions of hub and zone chunks; keep in sync with the buildscripts) --
local function pass(kind: string, size: number, c1: Color3, c2: Color3, group: number)
	return { Kind = kind, Size = size, Color = c1, Color2 = c2, Group = group }
end

WorldAmbienceConfig.Zones = {
	{
		Name = "Hub",
		Center = Vector3.new(-500, 0, -500),
		Radius = 200,
		Plankton = Color3.fromRGB(150, 230, 255),
		PassBy = {
			pass("Ray", 16, Color3.fromRGB(70, 190, 230), Color3.fromRGB(255, 240, 200), 1),
			pass("Fish", 5, Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 110, 60), 5),
			pass("Jelly", 9, Color3.fromRGB(255, 100, 230), Color3.fromRGB(255, 230, 250), 1),
		},
	},
	{
		Name = "SunZone",
		Center = Vector3.new(120, 0, 0),
		Radius = 90,
		Plankton = Color3.fromRGB(255, 240, 190),
		PassBy = {
			pass("Ray", 16, Color3.fromRGB(80, 210, 235), Color3.fromRGB(255, 240, 200), 1),
			pass("Fish", 5, Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 120, 60), 6),
		},
	},
	{
		Name = "TwilightZone",
		Center = Vector3.new(-120, 0, 0),
		Radius = 90,
		Plankton = Color3.fromRGB(150, 235, 255),
		PassBy = {
			pass("Jelly", 12, Color3.fromRGB(90, 230, 255), Color3.fromRGB(200, 255, 255), 1),
			pass("Ray", 18, Color3.fromRGB(150, 110, 235), Color3.fromRGB(120, 250, 240), 1),
		},
	},
	{
		Name = "MidnightZone",
		Center = Vector3.new(0, 0, 120),
		Radius = 95,
		Plankton = Color3.fromRGB(255, 170, 110),
		PassBy = {
			pass("Fish", 6, Color3.fromRGB(110, 40, 90), Color3.fromRGB(255, 120, 60), 4),
			pass("Jelly", 10, Color3.fromRGB(255, 90, 220), Color3.fromRGB(255, 200, 120), 1),
		},
	},
	{
		Name = "HadalDepths",
		Center = Vector3.new(0, 0, -120),
		Radius = 100,
		Plankton = Color3.fromRGB(190, 150, 255),
		PassBy = {
			pass("Ray", 24, Color3.fromRGB(50, 40, 110), Color3.fromRGB(110, 240, 255), 1),
			pass("Fish", 9, Color3.fromRGB(60, 50, 140), Color3.fromRGB(100, 240, 255), 3),
		},
	},
	{
		-- player plots (grid starts at 1000, 1000, see PlotRegistry); big radius
		-- because the grid is 10 x N slots 200 studs apart.
		Name = "Plots",
		Center = Vector3.new(1900, 0, 1000),
		Radius = 1100,
		Plankton = Color3.fromRGB(170, 235, 255),
		PassBy = {
			pass("Ray", 14, Color3.fromRGB(80, 200, 235), Color3.fromRGB(255, 240, 200), 1),
			pass("Fish", 4, Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 110, 60), 5),
		},
	},
} :: { ZoneInfo }

-- // Zone atmosphere (read by src/client/ZoneAtmosphere.client.lua) ----------------------------------
-- One lighting / fog / grading profile per zone name in `Zones` above ("Plots" falls back to "Hub").
-- Glow is kept readable but never blown out: Bloom.Threshold is high, so only intentional Neon (lanterns,
-- crystals, portals) and CrackedLava bleed; ordinary lit surfaces do not. Brightness/Contrast are not
-- touched on ColorCorrection.Brightness (WorldSetup flickers that one on the server).
export type AtmosphereProfile = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	Density: number,
	Offset: number,
	Haze: number,
	Glare: number,
	Tint: Color3,
	Saturation: number,
	Contrast: number,
	BloomIntensity: number,
	BloomSize: number,
	BloomThreshold: number,
}
local function prof(p: AtmosphereProfile): AtmosphereProfile
	return p
end
WorldAmbienceConfig.AtmosphereBlendSeconds = 2.5
WorldAmbienceConfig.AtmosphereCheckInterval = 0.5
WorldAmbienceConfig.Atmosphere = {
	Hub = prof({
		ClockTime = 12.5, Brightness = 2.2,
		Ambient = Color3.fromRGB(120, 150, 150), OutdoorAmbient = Color3.fromRGB(150, 172, 160),
		FogColor = Color3.fromRGB(60, 150, 170), FogStart = 60, FogEnd = 420,
		AtmosphereColor = Color3.fromRGB(110, 200, 215), AtmosphereDecay = Color3.fromRGB(60, 130, 150),
		Density = 0.3, Offset = 0.15, Haze = 1.6, Glare = 0,
		Tint = Color3.fromRGB(255, 248, 235), Saturation = 0.12, Contrast = 0.08,
		BloomIntensity = 0.25, BloomSize = 18, BloomThreshold = 1.1,
	}),
	SunZone = prof({
		ClockTime = 13, Brightness = 3,
		Ambient = Color3.fromRGB(150, 190, 175), OutdoorAmbient = Color3.fromRGB(190, 215, 190),
		FogColor = Color3.fromRGB(70, 185, 200), FogStart = 80, FogEnd = 520,
		AtmosphereColor = Color3.fromRGB(120, 215, 225), AtmosphereDecay = Color3.fromRGB(80, 170, 180),
		Density = 0.22, Offset = 0.1, Haze = 1, Glare = 0,
		Tint = Color3.fromRGB(255, 246, 226), Saturation = 0.2, Contrast = 0.05,
		BloomIntensity = 0.2, BloomSize = 16, BloomThreshold = 1.15,
	}),
	TwilightZone = prof({
		ClockTime = 18.7, Brightness = 1.6,
		Ambient = Color3.fromRGB(70, 64, 130), OutdoorAmbient = Color3.fromRGB(90, 84, 160),
		FogColor = Color3.fromRGB(38, 34, 96), FogStart = 30, FogEnd = 260,
		AtmosphereColor = Color3.fromRGB(90, 80, 170), AtmosphereDecay = Color3.fromRGB(30, 20, 80),
		Density = 0.4, Offset = 0.2, Haze = 2.2, Glare = 0,
		Tint = Color3.fromRGB(228, 226, 255), Saturation = 0.1, Contrast = 0.12,
		BloomIntensity = 0.35, BloomSize = 20, BloomThreshold = 1,
	}),
	MidnightZone = prof({
		ClockTime = 0, Brightness = 1,
		Ambient = Color3.fromRGB(56, 34, 38), OutdoorAmbient = Color3.fromRGB(70, 40, 40),
		FogColor = Color3.fromRGB(22, 8, 10), FogStart = 20, FogEnd = 210,
		AtmosphereColor = Color3.fromRGB(80, 30, 30), AtmosphereDecay = Color3.fromRGB(30, 6, 6),
		Density = 0.45, Offset = 0.25, Haze = 2.6, Glare = 0,
		Tint = Color3.fromRGB(255, 232, 220), Saturation = 0.05, Contrast = 0.22,
		BloomIntensity = 0.5, BloomSize = 22, BloomThreshold = 0.9,
	}),
	HadalDepths = prof({
		ClockTime = 0, Brightness = 1.8,
		Ambient = Color3.fromRGB(120, 160, 200), OutdoorAmbient = Color3.fromRGB(140, 180, 220),
		FogColor = Color3.fromRGB(110, 150, 190), FogStart = 10, FogEnd = 160,
		AtmosphereColor = Color3.fromRGB(150, 190, 225), AtmosphereDecay = Color3.fromRGB(60, 100, 150),
		Density = 0.55, Offset = 0.3, Haze = 3.4, Glare = 0,
		Tint = Color3.fromRGB(225, 240, 255), Saturation = -0.05, Contrast = 0.05,
		BloomIntensity = 0.3, BloomSize = 20, BloomThreshold = 1,
	}),
} :: { [string]: AtmosphereProfile }

WorldAmbienceConfig.DefaultPlankton = Color3.fromRGB(170, 235, 255)

return WorldAmbienceConfig
