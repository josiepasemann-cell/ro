--[[
	Abyssara - Deep Tide Tycoon
	Asset type: World set dressing
	Name: MidnightZoneDressing

	Fills the Midnight Zone chunk (MidnightZoneTerrainChunk, 110x110) with a
	bioluminescent lava cave: glowing mushroom clusters, pulsing spore pods,
	tube worms, magenta/orange anemones, glowing corals, lava rocks with
	ember cores, ember vents, small crystals, a wrecked hull and treasure
	nook on the flanks, lanterns along the entrance passage, signposts, glow
	patches on the floor, floating wisps, boulders around the chunk edge and
	a hanging rock mass underneath.

	GAMEPLAY AREAS STAY FREE: the narrow entrance passage and hub lane
	(|x| < 12 for the whole length), the whole arena area (|x| < 42, z > 12)
	with the Tiefenfuerst gate and its spires, and the landing spot. Only the
	cave flanks and the far corners are dressed. Everything is CanCollide =
	false / CanQuery = false / CastShadow = false. Animation happens
	client-side (src/client/WorldAmbience.client.lua, docs/world-ambience.md).

	PART BUDGET (this script only): target ~400 parts.

	Run: Studio Command Bar, edit mode, AFTER MidnightZoneTerrainChunk.lua.
	Result: Workspace.Assets.World.MidnightZoneDressing. Re-running replaces it.
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(0, 0, 120) -- must match MidnightZoneTerrainChunk.lua
local HALF = 55 -- chunk size 110
local TOP = 1.5
local RANDOM_SEED = 7303
-- // -----------------------------------------------------------------------

-- // Shared helper block --------------------------------------------------
-- (Identical in every assets/models/world/*.lua on purpose: buildscripts are
-- pasted one at a time into the Studio Command Bar, so they cannot require
-- each other. Edit one copy, then re-copy it to the others.)

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local rng = Random.new(RANDOM_SEED)
local rad, pi = math.rad, math.pi
local V3, CF = Vector3.new, CFrame.new
local ANG = CFrame.Angles
local C3 = Color3.fromRGB
local M = Enum.Material

local partCount = 0

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function rnd(a, b)
	return rng:NextNumber(a, b)
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function yaw()
	return rad(rnd(0, 360))
end

-- Small decor part: anchored, no collision / query / touch / shadow.
local function mk(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	partCount += 1
	return p
end

local function ball(parent, name, d, cf, color, material)
	return mk(parent, name, V3(d, d, d), cf, color, material, Enum.PartType.Ball)
end

-- Ellipsoid (SpecialMesh Sphere fills the part's Size, so squashed domes work).
local function blob(parent, name, size, cf, color, material)
	local p = mk(parent, name, size, cf, color, material)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Upright cylinder: `len` along the cf's Y axis, centred on cf.
local function post(parent, name, d, len, cf, color, material)
	return mk(parent, name, V3(len, d, d), cf * ANG(0, 0, pi / 2), color, material, Enum.PartType.Cylinder)
end

local function box(parent, name, size, cf, color, material)
	return mk(parent, name, size, cf, color, material)
end

local function wedge(parent, name, size, cf, color, material)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or M.SmoothPlastic
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	partCount += 1
	return w
end

local function neonBall(parent, name, d, cf, color)
	return ball(parent, name, d, cf, color, M.Neon)
end

local function neonBox(parent, name, size, cf, color)
	return box(parent, name, size, cf, color, M.Neon)
end

local function light(part, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = part
	return l
end

-- WorldAmbience.client.lua looks these tags/attributes up (docs/world-ambience.md)
local function tag(inst, tagName, attrs)
	CollectionService:AddTag(inst, tagName)
	if attrs then
		for k, v in pairs(attrs) do
			inst:SetAttribute(k, v)
		end
	end
end

local function newModel(parent, name, tagName, attrs)
	local m = Instance.new("Model")
	m.Name = name
	-- atomic streaming: the animation script sees every part at once
	pcall(function()
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m.Parent = parent
	if tagName then
		tag(m, tagName, attrs)
	end
	return m
end

local function addKeyedTexture(parent, key, face, studsU, studsV, color, transparency)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = studsU
	tex.StudsPerTileV = studsV
	tex.Color3 = color
	tex.Transparency = transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = parent
	return tex
end

-- // Placement helper: keep gameplay areas free -------------------------------
local blockers = {}

local function blockCircle(x, z, r)
	table.insert(blockers, { x, z, r })
end

local function blockRect(x0, z0, x1, z1)
	table.insert(blockers, { x0, z0, x1, z1, true })
end

local function isFree(x, z, r)
	for _, b in ipairs(blockers) do
		if b[5] then
			local dx = math.max(b[1] - x, 0, x - b[3])
			local dz = math.max(b[2] - z, 0, z - b[4])
			if dx * dx + dz * dz < r * r then
				return false
			end
		else
			local dx, dz = x - b[1], z - b[2]
			local rr = b[3] + r
			if dx * dx + dz * dz < rr * rr then
				return false
			end
		end
	end
	return true
end

-- Random free spot inside a rectangle; reserves it so later props keep away.
local function place(x0, x1, z0, z1, r)
	for _ = 1, 40 do
		local x, z = rnd(x0, x1), rnd(z0, z1)
		if isFree(x, z, r) then
			blockCircle(x, z, r)
			return x, z
		end
	end
	return nil, nil
end

-- // Props ---------------------------------------------------------------------
-- All prop functions take the ground CFrame (`cf`, origin on the ground,
-- +Y up) and build upwards.

-- Branching coral: trunk, 3-4 angled branches with (optionally glowing) tips.
local function coralTree(parent, cf, h, color, tipColor, glowTips)
	post(parent, "CoralTrunk", h * 0.17, h * 0.62, cf * CF(0, h * 0.31, 0), color, M.Pebble)
	local n = rng:NextInteger(3, 4)
	local y0 = rnd(0, pi)
	for i = 1, n do
		local bl = h * rnd(0.38, 0.52)
		local base = cf * CF(0, h * rnd(0.42, 0.55), 0) * ANG(0, y0 + i / n * 2 * pi, 0) * ANG(0, 0, -rad(rnd(26, 44)))
		post(parent, "CoralBranch", h * 0.11, bl, base * CF(0, bl / 2, 0), color, M.Pebble)
		ball(parent, "CoralTip", h * 0.16, base * CF(0, bl, 0), tipColor, glowTips and M.Neon or M.SmoothPlastic)
	end
end

-- Table coral: stem plus a wide flat plate with a neon rim.
local function tableCoral(parent, cf, r, color, rimColor)
	post(parent, "TableStem", r * 0.32, r * 0.9, cf * CF(0, r * 0.45, 0), color, M.Pebble)
	post(parent, "TablePlate", r * 2, r * 0.22, cf * CF(0, r * 0.95, 0), color, M.Pebble)
	post(parent, "TableRim", r * 2.06, r * 0.07, cf * CF(0, r * 1.06, 0), rimColor, M.Neon)
end

-- Brain coral: bulbous dome with two smaller lobes.
local function brainCoral(parent, cf, d, color)
	blob(parent, "BrainDome", V3(d, d * 0.62, d), cf * CF(0, d * 0.2, 0), color, M.Pebble)
	blob(parent, "BrainLobe", V3(d * 0.6, d * 0.4, d * 0.6), cf * CF(d * 0.5, d * 0.1, d * 0.2), color, M.Pebble)
	blob(parent, "BrainLobe", V3(d * 0.5, d * 0.36, d * 0.5), cf * CF(-d * 0.42, d * 0.08, -d * 0.3), color, M.Pebble)
end

-- Tube coral: cluster of leaning tubes with glowing mouths.
local function tubeCoral(parent, cf, color, glowColor, count)
	for i = 1, count do
		local h = rnd(2.4, 5.2)
		local a = (i / count) * 2 * pi + rnd(-0.4, 0.4)
		local base = cf * CF(math.cos(a) * 0.9, 0, math.sin(a) * 0.9) * ANG(rnd(-0.16, 0.16), 0, rnd(-0.16, 0.16))
		post(parent, "Tube", 0.95, h, base * CF(0, h / 2, 0), color, M.Pebble)
		post(parent, "TubeMouth", 1.05, 0.25, base * CF(0, h, 0), glowColor, M.Neon)
	end
end

-- Sea fan: flat wide ellipsoid on a short stalk.
local function seaFan(parent, cf, w, color)
	post(parent, "FanStalk", w * 0.09, w * 0.4, cf * CF(0, w * 0.2, 0), color, M.SmoothPlastic)
	blob(parent, "FanBlade", V3(w, w * 0.8, w * 0.1), cf * CF(0, w * 0.8, 0), color, M.SmoothPlastic)
end

-- Anemone: fat base, ring of leaning tentacles with glowing tips (sways + pulses).
local function anemone(parent, cf, d, color, tipColor, tentacles)
	local m = newModel(parent, "Anemone", "WA_Sway", { WA_Amp = 5, WA_Speed = rnd(0.9, 1.4), WA_Phase = rnd(0, 6) })
	tag(m, "WA_Pulse", { WA_Speed = rnd(0.7, 1.1), WA_Depth = 0.45, WA_Phase = rnd(0, 6) })
	blob(m, "AnemoneBase", V3(d * 0.9, d * 0.6, d * 0.9), cf * CF(0, d * 0.18, 0), color, M.SmoothPlastic)
	local n = tentacles or 5
	for i = 1, n do
		local a = i / n * 2 * pi + rnd(-0.2, 0.2)
		local len = d * rnd(0.85, 1.2)
		local base = cf * CF(math.cos(a) * d * 0.22, d * 0.3, math.sin(a) * d * 0.22) * ANG(0, -a, 0) * ANG(0, 0, -rad(rnd(18, 34)))
		post(m, "Tentacle", d * 0.16, len, base * CF(0, len / 2, 0), color, M.SmoothPlastic)
		neonBall(m, "TentacleTip", d * 0.24, base * CF(0, len, 0), tipColor)
	end
	return m
end

-- Kelp tuft: `fronds` chains of leaning segments; sways as one unit.
local function kelp(parent, cf, h, color, tipColor, fronds, segs)
	local m = newModel(parent, "Kelp", "WA_Sway", { WA_Amp = rnd(5, 8), WA_Speed = rnd(0.5, 0.9), WA_Phase = rnd(0, 6) })
	fronds = fronds or 3
	segs = segs or 3
	local segH = h / segs
	for f = 1, fronds do
		local a = f / fronds * 2 * pi + rnd(-0.3, 0.3)
		local cur = cf * CF(math.cos(a) * 0.7, 0, math.sin(a) * 0.7) * ANG(0, a, 0)
		local w = rnd(0.9, 1.5)
		for s = 1, segs do
			cur = cur * ANG(0, 0, rad(rnd(-9, 9)))
			local taper = 1 - (s - 1) / segs * 0.45
			box(m, "KelpBlade", V3(w * taper, segH * 1.06, 0.32), cur * CF(0, segH / 2, 0), color, M.SmoothPlastic)
			cur = cur * CF(0, segH, 0)
		end
		neonBall(m, "KelpTip", 0.55, cur, tipColor)
	end
	return m
end

-- Seagrass: a few thin blades (sways).
local function seagrass(parent, cf, h, color)
	local m = newModel(parent, "Seagrass", "WA_Sway", { WA_Amp = 9, WA_Speed = rnd(0.8, 1.3), WA_Phase = rnd(0, 6) })
	for i = 1, 3 do
		local bh = h * rnd(0.7, 1.15)
		local a = i / 3 * 2 * pi
		local base = cf * CF(math.cos(a) * 0.5, 0, math.sin(a) * 0.5) * ANG(rnd(-0.22, 0.22), 0, rnd(-0.22, 0.22))
		box(m, "Blade", V3(0.5, bh, 0.14), base * CF(0, bh / 2, 0), color, M.SmoothPlastic)
	end
	return m
end

-- Glowing mushrooms: 2-3 stems with domed caps (pulse).
local function mushrooms(parent, cf, h, capColor, stemColor, count)
	local m = newModel(parent, "Mushrooms", "WA_Pulse", { WA_Speed = rnd(0.5, 0.9), WA_Depth = 0.4, WA_Phase = rnd(0, 6) })
	for i = 1, count or 3 do
		local hh = h * rnd(0.6, 1.15)
		local a = i / (count or 3) * 2 * pi + rnd(-0.3, 0.3)
		local off = i == 1 and 0 or hh * 0.45
		local base = cf * CF(math.cos(a) * off, 0, math.sin(a) * off)
		post(m, "Stem", hh * 0.16, hh, base * CF(0, hh / 2, 0), stemColor, M.SmoothPlastic)
		blob(m, "Cap", V3(hh * 0.85, hh * 0.42, hh * 0.85), base * CF(0, hh, 0), capColor, M.Neon)
	end
	return m
end

-- Rock with a moss cap and a pebble.
local function mossRock(parent, cf, d, rockColor, mossColor)
	blob(parent, "Rock", V3(d, d * rnd(0.6, 0.8), d * rnd(0.85, 1.1)), cf * CF(0, d * 0.25, 0) * ANG(0, yaw(), 0), rockColor, M.Slate)
	blob(parent, "Moss", V3(d * 0.66, d * 0.26, d * 0.62), cf * CF(d * 0.05, d * 0.55, 0), mossColor, M.Grass)
	blob(parent, "Pebble", V3(d * 0.3, d * 0.2, d * 0.3), cf * CF(d * 0.62, d * 0.1, d * 0.2), rockColor, M.Slate)
end

-- Lantern post: pole + glowing lamp (flickers; optional real PointLight).
local function lantern(parent, cf, h, color, withLight)
	post(parent, "LanternPole", 0.5, h, cf * CF(0, h / 2, 0), C3(40, 46, 60), M.Metal)
	local lamp = ball(parent, "LanternLamp", 1.7, cf * CF(0, h + 0.6, 0), color, M.Neon)
	tag(lamp, "WA_Flicker", { WA_Speed = rnd(1.4, 2.4), WA_Phase = rnd(0, 20) })
	if withLight then
		light(lamp, color, 1.4, 16)
	end
	return lamp
end

-- Signpost: pole, neon frame and a board with text on both faces.
-- The board's front (-Z of cf) faces the reader.
local function signPost(parent, cf, text, color, h)
	h = h or 5.2
	post(parent, "SignPole", 0.55, h, cf * CF(0, h / 2, 0.15), C3(60, 48, 40), M.Wood)
	neonBox(parent, "SignFrame", V3(9.6, 3.6, 0.3), cf * CF(0, h + 1.1, 0.32), color)
	local board = box(parent, "SignBoard", V3(9, 3.1, 0.4), cf * CF(0, h + 1.1, 0), C3(14, 24, 40), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.6
		label.Parent = gui
	end
	return board
end

-- Invisible emitter part (tag WA_Bubbles): bubbles (or embers) rise from it.
local function bubbleEmitter(parent, cf, color, ember)
	local e = mk(parent, "VentEmitter", V3(1, 1, 1), cf, color, M.SmoothPlastic)
	e.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Bubbles"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(ember and color or C3(200, 245, 255))
	pe.LightEmission = ember and 1 or 0.5
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, ember and 0.5 or 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(3, 5)
	pe.Speed = NumberRange.new(ember and 6 or 5, ember and 9 or 8)
	pe.Acceleration = V3(0, 1.5, 0)
	pe.SpreadAngle = Vector2.new(9, 9)
	pe.Rate = ember and 5 or 7
	pe.Rotation = NumberRange.new(0, 360)
	pe.Parent = e
	pe:SetAttribute("BaseRate", pe.Rate)
	tag(e, "WA_Bubbles", {})
	return e
end

-- Bubble/ember vent: rock rim, glowing throat and an emitter.
local function vent(parent, cf, r, rockColor, glowColor, ember)
	for i = 1, 3 do
		local a = i / 3 * 2 * pi + rnd(-0.3, 0.3)
		blob(parent, "VentRock", V3(r * 0.9, r * 0.6, r * 0.9), cf * CF(math.cos(a) * r * 0.6, r * 0.2, math.sin(a) * r * 0.6), rockColor, M.Slate)
	end
	post(parent, "VentGlow", r * 0.8, 0.3, cf * CF(0, r * 0.28, 0), glowColor, M.Neon)
	return bubbleEmitter(parent, cf * CF(0, r * 0.5, 0), glowColor, ember)
end

-- Light shaft: three crossing translucent neon planes; rotates + shimmers.
local function lightShaft(parent, cf, h, w, color, transp)
	local m = newModel(parent, "LightShaft", "WA_Rotate", { WA_Spin = rnd(2.5, 5) * (rng:NextNumber() < 0.5 and 1 or -1) })
	tag(m, "WA_Pulse", { WA_Speed = rnd(0.25, 0.45), WA_Depth = 0.6, WA_Phase = rnd(0, 6) })
	for i = 0, 2 do
		local p = neonBox(m, "ShaftPlane", V3(w, h, 0.05), cf * CF(0, h / 2, 0) * ANG(0, i * pi / 3, 0), color)
		p.Transparency = transp or 0.9
	end
	return m
end

-- Barrel, crate, amphora, anchor: small wreck/treasure bits.
local function barrel(parent, cf, s)
	local c = C3(96, 66, 42)
	post(parent, "Barrel", 1.6 * s, 2.2 * s, cf * CF(0, 1.1 * s, 0), c, M.Wood)
	post(parent, "BarrelBand", 1.72 * s, 0.22 * s, cf * CF(0, 1.5 * s, 0), C3(60, 60, 68), M.Metal)
end

local function crate(parent, cf, s)
	local b = box(parent, "Crate", V3(2.2 * s, 2 * s, 2.2 * s), cf * CF(0, 1 * s, 0), C3(112, 84, 54), M.WoodPlanks)
	addKeyedTexture(b, "WoodPlanks", Enum.NormalId.Top, 4, 4, C3(200, 170, 130), 0.1)
	box(parent, "CrateStrap", V3(2.3 * s, 0.3 * s, 2.3 * s), cf * CF(0, 1.4 * s, 0), C3(70, 52, 34), M.Wood)
end

local function amphora(parent, cf, s, color)
	blob(parent, "AmphoraBody", V3(1.6 * s, 2.2 * s, 1.6 * s), cf * CF(0, 1.1 * s, 0), color, M.Slate)
	post(parent, "AmphoraNeck", 0.6 * s, 1 * s, cf * CF(0, 2.5 * s, 0), color, M.Slate)
end

local function shipAnchor(parent, cf, s)
	local c = C3(58, 62, 74)
	post(parent, "AnchorShank", 0.55 * s, 5 * s, cf * CF(0, 2.5 * s, 0), c, M.Metal)
	post(parent, "AnchorCross", 0.5 * s, 3 * s, cf * CF(0, 4.3 * s, 0) * ANG(0, 0, pi / 2), c, M.Metal)
	post(parent, "AnchorArm", 0.5 * s, 3.4 * s, cf * CF(-1.2 * s, 0.6 * s, 0) * ANG(0, 0, -rad(50)), c, M.Metal)
	post(parent, "AnchorArm", 0.5 * s, 3.4 * s, cf * CF(1.2 * s, 0.6 * s, 0) * ANG(0, 0, rad(50)), c, M.Metal)
end

-- Ship ribs: keel + N V-shaped rib pairs (half-buried hull skeleton).
local function shipRibs(parent, cf, length, color)
	box(parent, "Keel", V3(length, 0.8, 1), cf * CF(0, 0.4, 0), color, M.Wood)
	local n = math.floor(length / 3)
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * (length / n)
		local hh = 5.5 - math.abs(x) / length * 3.5
		for _, side in ipairs({ 1, -1 }) do
			local base = cf * CF(x, -0.1, side * 0.6) * ANG(side * rad(24), 0, 0)
			box(parent, "Rib", V3(0.55, hh, 0.55), base * CF(0, hh / 2, 0), color, M.Wood)
		end
	end
end

local function brokenMast(parent, cf, h, color, sailColor)
	local tilt = cf * ANG(0, 0, rad(rnd(-14, 14)))
	post(parent, "Mast", 0.7, h, tilt * CF(0, h / 2, 0), color, M.Wood)
	post(parent, "Yard", 0.4, h * 0.6, tilt * CF(0, h * 0.75, 0) * ANG(0, 0, pi / 2), color, M.Wood)
	box(parent, "TornSail", V3(h * 0.5, h * 0.32, 0.1), tilt * CF(0, h * 0.55, 0.15), sailColor, M.Fabric)
end

-- Treasure chest with glowing gold (pulses).
local function treasureChest(parent, cf, s)
	local m = newModel(parent, "TreasureChest", "WA_Pulse", { WA_Speed = 0.9, WA_Depth = 0.5, WA_Phase = rnd(0, 6) })
	box(m, "ChestBase", V3(4.4 * s, 2.2 * s, 2.8 * s), cf * CF(0, 1.1 * s, 0), C3(96, 62, 38), M.WoodPlanks)
	box(m, "ChestBand", V3(4.6 * s, 0.35 * s, 3 * s), cf * CF(0, 1.9 * s, 0), C3(210, 170, 60), M.Metal)
	box(m, "ChestLid", V3(4.4 * s, 0.9 * s, 2.8 * s), cf * CF(0, 2.9 * s, -1.2 * s) * ANG(rad(-38), 0, 0), C3(110, 72, 44), M.WoodPlanks)
	blob(m, "GoldHeap", V3(3.6 * s, 1.2 * s, 2 * s), cf * CF(0, 2.3 * s, 0.1 * s), C3(255, 210, 70), M.Neon)
	neonBall(m, "Gem", 0.9 * s, cf * CF(1 * s, 3.1 * s, 0.3 * s), C3(255, 80, 200))
	neonBall(m, "Gem", 0.7 * s, cf * CF(-1.1 * s, 3 * s, 0.5 * s), C3(80, 240, 255))
	return m
end

local function coinPile(parent, cf, s)
	local gold = C3(255, 205, 60)
	blob(parent, "CoinMound", V3(3 * s, 0.9 * s, 3 * s), cf * CF(0, 0.3 * s, 0), gold, M.Metal)
	for i = 1, 3 do
		local a = i / 3 * 2 * pi + rnd(-0.4, 0.4)
		post(parent, "Coin", 0.9 * s, 0.14 * s, cf * CF(math.cos(a) * 1.5 * s, 0.6 * s, math.sin(a) * 1.5 * s) * ANG(rnd(-0.6, 0.6), 0, rnd(-0.6, 0.6)), gold, M.Neon)
	end
end

-- Crystal cluster of leaning wedge shards.
local function crystalCluster(parent, cf, h, colors, count, material)
	for i = 1, count do
		local hh = h * rnd(0.45, 1)
		local w = hh * rnd(0.16, 0.24)
		local a = i / count * 2 * pi + rnd(-0.4, 0.4)
		local off = i == 1 and 0 or hh * 0.28
		wedge(
			parent,
			"Crystal",
			V3(w, hh, hh * rnd(0.5, 0.75)),
			cf * CF(math.cos(a) * off, hh * 0.45, math.sin(a) * off) * ANG(0, rnd(0, 2 * pi), 0) * ANG(rnd(-0.22, 0.22), 0, rnd(-0.22, 0.22)),
			pick(colors),
			material or M.Neon
		)
	end
end

-- Ruined column (optionally broken, with a fallen top piece and glowing band).
local function column(parent, cf, h, color, glowColor, broken)
	box(parent, "ColumnFoot", V3(3.6, 0.9, 3.6), cf * CF(0, 0.45, 0), color, M.Slate)
	post(parent, "ColumnShaft", 2.2, h, cf * CF(0, 0.9 + h / 2, 0), color, M.Slate)
	post(parent, "ColumnGlow", 2.4, 0.35, cf * CF(0, 0.9 + h * 0.6, 0), glowColor, M.Neon)
	if broken then
		post(parent, "ColumnFallen", 2.1, h * 0.5, cf * CF(3.6, 1.05, 1.2) * ANG(0, rad(30), 0) * ANG(0, 0, pi / 2), color, M.Slate)
	else
		box(parent, "ColumnCap", V3(3.4, 0.8, 3.4), cf * CF(0, 0.9 + h + 0.4, 0), color, M.Slate)
	end
end

local function runeSlab(parent, cf, h, color, glowColor)
	box(parent, "Slab", V3(4.4, h, 0.9), cf * CF(0, h / 2, 0), color, M.Slate)
	for i = 1, 3 do
		neonBox(parent, "Rune", V3(rnd(1.4, 2.6), 0.28, 0.12), cf * CF(rnd(-0.6, 0.6), h * (0.3 + i * 0.18), -0.5), glowColor)
	end
end

-- Lava/ember rock: dark blob with a glowing core peeking out.
local function lavaRock(parent, cf, d, rockColor, glowColor)
	blob(parent, "LavaRock", V3(d, d * 0.7, d * 0.9), cf * CF(0, d * 0.3, 0) * ANG(0, yaw(), 0), rockColor, M.Basalt)
	blob(parent, "LavaCore", V3(d * 0.5, d * 0.22, d * 0.5), cf * CF(d * 0.18, d * 0.62, 0), glowColor, M.Neon)
end

-- Tube worms / spore stalks: thin stalks with glowing bulbs (sway).
local function tubeWorms(parent, cf, color, tipColor, count)
	local m = newModel(parent, "TubeWorms", "WA_Sway", { WA_Amp = 7, WA_Speed = rnd(0.7, 1.1), WA_Phase = rnd(0, 6) })
	for i = 1, count do
		local h = rnd(3, 6.5)
		local a = i / count * 2 * pi
		local base = cf * CF(math.cos(a) * 0.8, 0, math.sin(a) * 0.8) * ANG(rnd(-0.2, 0.2), 0, rnd(-0.2, 0.2))
		post(m, "Worm", 0.42, h, base * CF(0, h / 2, 0), color, M.SmoothPlastic)
		neonBall(m, "WormTip", 0.95, base * CF(0, h, 0), tipColor)
	end
	return m
end

-- Glowing spore pod on a stalk (pulses).
local function sporePod(parent, cf, h, color)
	local m = newModel(parent, "SporePod", "WA_Pulse", { WA_Speed = rnd(0.6, 1.2), WA_Depth = 0.5, WA_Phase = rnd(0, 6) })
	post(m, "PodStalk", 0.3, h, cf * CF(0, h / 2, 0), C3(40, 50, 60), M.SmoothPlastic)
	neonBall(m, "PodBulb", h * 0.42, cf * CF(0, h, 0), color)
	return m
end

-- Floating wisp / crystal (bobs and spins slowly).
local function wisp(parent, cf, d, color)
	local m = newModel(parent, "Wisp", "WA_Bob", { WA_BobAmp = rnd(0.6, 1.4), WA_BobSpeed = rnd(0.5, 0.9), WA_Phase = rnd(0, 6), WA_Spin = rnd(10, 25) })
	tag(m, "WA_Pulse", { WA_Speed = rnd(0.8, 1.4), WA_Depth = 0.3, WA_Phase = rnd(0, 6) })
	neonBall(m, "WispCore", d, cf, color)
	local halo = ball(m, "WispHalo", d * 1.9, cf, color, M.Neon)
	halo.Transparency = 0.82
	return m
end

-- Jelly lamp plant (static stalk + translucent bell that bobs).
local function jellyLamp(parent, cf, d, color)
	post(parent, "LampStalk", d * 0.14, d * 1.6, cf * CF(0, d * 0.8, 0), C3(40, 90, 90), M.SmoothPlastic)
	local m = newModel(parent, "JellyLamp", "WA_Bob", { WA_BobAmp = 0.35, WA_BobSpeed = 0.8, WA_Phase = rnd(0, 6), WA_Spin = 0 })
	tag(m, "WA_Pulse", { WA_Speed = 0.7, WA_Depth = 0.35, WA_Phase = rnd(0, 6) })
	local bell = blob(m, "LampBell", V3(d, d * 0.7, d), cf * CF(0, d * 1.75, 0), color, M.Neon)
	bell.Transparency = 0.2
	return m
end


-- Flat colour patch on the ground (algae mat, pebble field, glow moss).
local function groundPatch(parent, cf, d, color, material)
	return blob(parent, "GroundPatch", V3(d, 0.35, d * rnd(0.6, 0.9)), cf * CF(0, 0.05, 0), color, material or M.Grass)
end

-- Clam: two shell halves (one open) with a glowing pearl.
local function clam(parent, cf, d, color)
	blob(parent, "ClamBottom", V3(d, d * 0.35, d * 0.8), cf * CF(0, d * 0.16, 0), color, M.SmoothPlastic)
	blob(parent, "ClamLid", V3(d, d * 0.3, d * 0.8), cf * CF(0, d * 0.5, -d * 0.28) * ANG(rad(-48), 0, 0), color, M.SmoothPlastic)
	neonBall(parent, "Pearl", d * 0.28, cf * CF(0, d * 0.34, 0), C3(255, 240, 250))
end

local function starfish(parent, cf, d, color)
	blob(parent, "Starfish", V3(d, 0.35, d), cf * CF(0, 0.1, 0), color, M.Pebble)
	blob(parent, "StarfishArm", V3(d * 0.4, 0.3, d * 1.1), cf * CF(0, 0.12, 0) * ANG(0, rad(60), 0), color, M.Pebble)
end

-- Hanging vine (cliff lip / cave ceiling): chain of segments swinging from the top.
local function hangingVine(parent, topCF, len, color, tipColor, segs)
	local m = newModel(parent, "HangingVine", "WA_Sway", { WA_Amp = rnd(5, 8), WA_Speed = rnd(0.5, 0.9), WA_Phase = rnd(0, 6), WA_Hang = true })
	segs = segs or 4
	local segLen = len / segs
	local cur = topCF
	for i = 1, segs do
		cur = cur * ANG(0, 0, rad(rnd(-7, 7)))
		post(m, "VineSeg", 0.5 * (1 - (i - 1) / segs * 0.4), segLen * 1.05, cur * CF(0, -segLen / 2, 0), color, M.SmoothPlastic)
		cur = cur * CF(0, -segLen, 0)
	end
	neonBall(m, "VineTip", 0.9, cur, tipColor)
	return m
end

-- Emitter only: bubbles rise a long way (abyss updraft).
local function updraft(parent, cf, color, rate)
	local e = bubbleEmitter(parent, cf, color, false)
	local pe = e.Bubbles
	pe.Lifetime = NumberRange.new(9, 12)
	pe.Rate = rate or 3
	pe:SetAttribute("BaseRate", pe.Rate)
	pe.LightEmission = 0.8
	pe.Color = ColorSequence.new(color)
	return e
end

-- Ambient fish/jelly/ray school marker; the client spawns local-only creatures
-- while the camera is near (nothing replicates, zero server cost).
local function school(parent, cf, kind, count, size, c1, c2, rx, ry, rz, speed)
	local p = mk(parent, "School_" .. kind, V3(1, 1, 1), cf, c1, M.SmoothPlastic)
	p.Transparency = 1
	tag(p, "WA_School", {
		WA_Kind = kind,
		WA_Count = count,
		WA_Size = size,
		WA_Color = c1,
		WA_Color2 = c2,
		WA_RadiusX = rx,
		WA_RadiusY = ry,
		WA_RadiusZ = rz,
		WA_Speed = speed,
		WA_Seed = rng:NextInteger(1, 100000),
	})
	return p
end

-- Ragged boulders wrapped around a rectangular chunk edge (soften the slab
-- silhouette). `skip(x, z)` -> true leaves a gap (lanes, cliffs).
local function rimBoulders(parent, ORIGIN, halfX, halfZ, topY, count, colors, mossColor, skip)
	local perim = 4 * (halfX + halfZ)
	for i = 1, count do
		local s = (i - 0.5) / count * perim + rnd(-2, 2)
		local x, z, ox, oz
		if s < 2 * halfX then
			x, z, ox, oz = -halfX + s, -halfZ, 0, -1
		elseif s < 2 * halfX + 2 * halfZ then
			x, z, ox, oz = halfX, -halfZ + (s - 2 * halfX), 1, 0
		elseif s < 4 * halfX + 2 * halfZ then
			x, z, ox, oz = halfX - (s - 2 * halfX - 2 * halfZ), halfZ, 0, 1
		else
			x, z, ox, oz = -halfX, halfZ - (s - 4 * halfX - 2 * halfZ), -1, 0
		end
		if not (skip and skip(x, z)) then
			local d = rnd(5, 10)
			local cf = ORIGIN * CF(x + ox * d * 0.22, topY - d * 0.12, z + oz * d * 0.22) * ANG(0, yaw(), 0)
			blob(parent, "RimBoulder", V3(d, d * rnd(0.6, 0.8), d * rnd(0.9, 1.2)), cf, pick(colors), M.Slate)
			if mossColor and rng:NextNumber() < 0.6 then
				blob(parent, "RimMoss", V3(d * 0.6, d * 0.22, d * 0.55), cf * CF(0, d * 0.3, 0), mossColor, M.Grass)
			end
		end
	end
end

-- Hanging rock mass under a floating slab (so it reads as an island).
local function underside(parent, ORIGIN, x, z, w, d, topY, colors)
	local tiers = {
		{ 0.92, 0.9, 7, -2.5 },
		{ 0.68, 0.66, 9, -8.5 },
		{ 0.42, 0.4, 10, -15 },
		{ 0.2, 0.2, 9, -22 },
	}
	for _, t in ipairs(tiers) do
		blob(parent, "UnderRock", V3(w * t[1], t[3], d * t[2]), ORIGIN * CF(x + rnd(-2, 2), topY + t[4], z + rnd(-2, 2)) * ANG(0, yaw(), 0), pick(colors), M.Slate)
	end
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local worldFolder = getOrCreateFolder(assetsFolder, "World")
-- // end shared helper block -----------------------------------------------

local previous = worldFolder:FindFirstChild("MidnightZoneDressing")
if previous then
	previous:Destroy()
end
local model = Instance.new("Model")
model.Name = "MidnightZoneDressing"
model.Parent = worldFolder

local function fold(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = model
	return f
end
local glow, lava, rocks, wreck, signs, lamps, fx, edge =
	fold("GlowCave"), fold("LavaRocks"), fold("Rocks"), fold("Wreck"), fold("Signs"), fold("Lanterns"), fold("Effects"), fold("Edge")

local function at(x, z, y, deg)
	return ORIGIN * CF(x, TOP + (y or 0), z) * ANG(0, deg and rad(deg) or yaw(), 0)
end

-- // Palette ---------------------------------------------------------------
local CAPS = { C3(60, 210, 255), C3(240, 80, 220), C3(150, 255, 110), C3(255, 140, 60) }
local STEM = C3(50, 44, 60)
local CORAL = { C3(220, 70, 200), C3(150, 90, 255), C3(255, 120, 70) }
local TIP = { C3(255, 130, 240), C3(120, 230, 255), C3(255, 190, 90) }
local ROCK = { C3(44, 40, 50), C3(36, 34, 44), C3(52, 46, 54) }
local LAVA = C3(255, 100, 30)
local EMBER = C3(255, 160, 70)
local PATCH = { C3(200, 60, 190), C3(40, 170, 210), C3(255, 110, 40), C3(100, 220, 120) }
local CRYSTAL = { C3(80, 230, 255), C3(240, 80, 230), C3(255, 150, 70) }

-- // Reserved areas ----------------------------------------------------------
blockRect(-12, -HALF, 12, 14) -- entrance passage + hub lane + landing
blockRect(-44, 8, 44, HALF) -- arena, gate and spires
blockRect(-16, -48, 16, -30) -- passage walls and overhang
blockCircle(-34, -14, 9) -- wreck (placed below)
blockCircle(36, -12, 8) -- treasure nook (placed below)

-- Random free spot on either cave flank (|x| 13..51).
local function spot(r)
	for _ = 1, 40 do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local x = side * rnd(13, 51)
		local z = rnd(-50, 52)
		if isFree(x, z, r) then
			blockCircle(x, z, r)
			return x, z
		end
	end
	return nil, nil
end

-- // Ground glow patches --------------------------------------------------
for _ = 1, 14 do
	local x, z = spot(3)
	if x then
		groundPatch(rocks, at(x, z), rnd(4, 8), pick(PATCH), M.Pebble)
	end
end

-- // Bioluminescent garden -----------------------------------------------
for _ = 1, 9 do
	local x, z = spot(3)
	if x then
		mushrooms(glow, at(x, z), rnd(2.6, 4.6), pick(CAPS), STEM, 3)
	end
end
for _ = 1, 5 do
	local x, z = spot(2.6)
	if x then
		tubeWorms(glow, at(x, z), C3(70, 40, 80), pick(TIP), 3)
	end
end
for _ = 1, 8 do
	local x, z = spot(1.6)
	if x then
		sporePod(glow, at(x, z), rnd(2.5, 5), pick(CAPS))
	end
end
for _ = 1, 4 do
	local x, z = spot(3)
	if x then
		anemone(glow, at(x, z), rnd(2.6, 3.6), pick(CORAL), pick(TIP), 5)
	end
end
for _ = 1, 5 do
	local x, z = spot(3)
	if x then
		coralTree(glow, at(x, z), rnd(5, 8), pick(CORAL), pick(TIP), true)
	end
end
for _ = 1, 4 do
	local x, z = spot(2.5)
	if x then
		crystalCluster(glow, at(x, z), rnd(3, 5), CRYSTAL, 4, M.Neon)
	end
end
for _ = 1, 8 do
	local x, z = spot(2.6)
	if x then
		lavaRock(lava, at(x, z), rnd(2.6, 4.6), pick(ROCK), EMBER)
	end
end
for _ = 1, 3 do
	local x, z = spot(3)
	if x then
		brainCoral(glow, at(x, z), rnd(2.5, 3.6), pick(CORAL))
	end
end
for _ = 1, 6 do
	local x, z = spot(1.5)
	if x then
		wisp(fx, ORIGIN * CF(x, TOP + rnd(4, 10), z), rnd(0.7, 1.1), pick(CAPS))
	end
end

-- // Wreck + treasure -----------------------------------------------------
do
	local wood = C3(64, 52, 52)
	shipRibs(wreck, at(-34, -14, 0, 80), 16, wood)
	brokenMast(wreck, at(-30, -19, 0, 10), 8, C3(52, 44, 44), C3(120, 80, 110))
	barrel(wreck, at(-27, -8), 1)
	crate(wreck, at(-41, -20), 1)
	treasureChest(wreck, at(36, -12, 0, 200), 1)
	coinPile(wreck, at(32, -9), 1)
	crystalCluster(wreck, at(41, -16), 3, CRYSTAL, 3, M.Neon)
end

-- // Vents (embers), signs, lanterns --------------------------------------
vent(fx, at(-20, 4), 2, ROCK[1], EMBER, true)
vent(fx, at(24, -26), 2, ROCK[2], EMBER, true)
vent(fx, at(-46, 30), 2, ROCK[3], LAVA, true)

signPost(signs, at(-18, -26, 0, 180), "MIDNIGHT ZONE", C3(255, 120, 230))
signPost(signs, at(18, -4, 0, 180), "Glow Cave  >>", C3(120, 235, 255))
signPost(signs, at(-18, 6, 0, 0), "Lava Ahead - Stay Cool!", C3(255, 150, 70))
signPost(signs, at(47, 6, 0, 270), "Deep Lord Arena  >>", C3(255, 90, 90))

local LAMP = { C3(255, 140, 60), C3(255, 100, 220), C3(100, 220, 255) }
local li = 0
for _, z in ipairs({ -52, -24, -10, 0, 8 }) do
	for _, side in ipairs({ 1, -1 }) do
		li += 1
		lantern(lamps, ORIGIN * CF(side * 10, TOP, z), 3.2, LAMP[li % 3 + 1], li % 4 == 0)
	end
end

for _, s in ipairs({ { -32, -30 }, { 32, 6 } }) do
	lightShaft(fx, at(s[1], s[2], 0, 0), 50, rnd(6, 8), C3(255, 130, 70), 0.95)
end
school(fx, ORIGIN * CF(-30, TOP + 10, -4), "Fish", 8, 1.5, C3(120, 40, 80), C3(255, 120, 60), 16, 4, 28, 2.2)
school(fx, ORIGIN * CF(30, TOP + 12, -20), "Jelly", 2, 4.5, C3(255, 90, 220), C3(255, 200, 120), 14, 6, 18, 0.55)
school(fx, ORIGIN * CF(0, TOP + 14, 20), "Ray", 1, 8, C3(70, 40, 90), C3(255, 130, 70), 30, 4, 22, 1.1)

-- // Edge ----------------------------------------------------------------------
rimBoulders(edge, ORIGIN, HALF, HALF, TOP, 18, ROCK, nil, function(x, z)
	return math.abs(x) < 14 and (z < -HALF + 1 or z > HALF - 1)
end)
underside(edge, ORIGIN, 0, 0, 110, 110, TOP - 1.5, { C3(34, 30, 42), C3(44, 38, 50) })

print(("[Abyssara] MidnightZoneDressing created under Workspace.Assets.World (%d parts)"):format(partCount))
