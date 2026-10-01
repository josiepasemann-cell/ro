--[[
	Abyssara - Deep Tide Tycoon
	Asset type: World set dressing
	Name: SunZoneDressing (v3 - decor on top of the sculpted terrain)

	Run AFTER terrain/SunZoneTerrainChunk.lua (it raycasts Workspace.Terrain to stand every prop on the
	real ground). Dresses four deliberate vignettes instead of scattering:
		1. Coral Garden on the raised terrace (north): big, colourful, NON-glowing corals.
		2. Wreck Cove around the pirate ship (east): chest inside the hull, coin piles, barrels, crates,
		   amphorae, anchor, ribs, small corals growing on the hull.
		3. Tide Pool (south-west): turquoise water disc, rim rocks, clams and starfish.
		4. Sun Gate + landing: two lanterns, a signpost, sunbeams.
	Plus seagrass meadows on the LeafyGrass patches and coral clumps hugging the reef wall.

	Glow budget: only the lantern lamps (6) are Neon. Light shafts are 94 percent transparent SmoothPlastic.
	Everything is CanCollide/CanQuery/CanTouch = false. Tagged props animate via WorldAmbience.client.lua.
	Gameplay areas are reserved with blockCircle / blockTrail: landing (r 16), the four trails, the ship.

	Result: Workspace.Assets.World.SunZoneDressing (re-running replaces it).
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(120, 0, 0) -- must match SunZoneTerrainChunk.lua
local HALF = 50
local RANDOM_SEED = 7101
-- // -----------------------------------------------------------------------

-- // BEGIN SHARED GROUND HELPERS (read-only terrain access; identical in every world/*Dressing.lua) ----
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Terrain = Workspace.Terrain
local M = Enum.Material
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local rad, pi, sin, cos, sqrt, abs, max, min = math.rad, math.pi, math.sin, math.cos, math.sqrt, math.abs, math.max, math.min
local C3 = Color3.fromRGB
local function W(x, y, z)
	return ORIGIN:PointToWorldSpace(V3(x, y, z))
end
-- Ground height below local (x, z): raycast against Workspace.Terrain only (run the zone's terrain script first).
-- Falls back to y = 0 when no terrain is hit.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Terrain }
local function groundAt(x, z)
	local origin = W(x, 120, z)
	local hit = Workspace:Raycast(origin, V3(0, -260, 0), rayParams)
	if hit then
		return hit.Position.Y - ORIGIN.Position.Y, hit.Normal
	end
	return 0, V3(0, 1, 0)
end
-- // END SHARED GROUND HELPERS ---------------------------------------------------
-- // BEGIN SHARED PART HELPERS ---------------------------------------------------
-- (Identical in every terrain/*Chunk.lua and world/*.lua. Needs the terrain helper block above:
-- ORIGIN, groundAt, V3/CF/ANG/C3/M/rad/pi.) Glow is opt-in: only glow*/lantern/lamp helpers use Neon.

local rng = Random.new(RANDOM_SEED)
local partCount, neonCount = 0, 0
local SOLID = false -- parts made while true collide (landmarks, stairs); decor never collides

local function rnd(a, b) return rng:NextNumber(a, b) end
local function pick(list) return list[rng:NextInteger(1, #list)] end
local function yaw() return rad(rnd(0, 360)) end
local function setSolid(on) SOLID = on end

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function mk(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = SOLID
	p.CanQuery = SOLID
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	partCount += 1
	if p.Material == M.Neon then neonCount += 1 end
	return p
end
local function box(parent, name, size, cf, color, material) return mk(parent, name, size, cf, color, material) end
local function ball(parent, name, d, cf, color, material) return mk(parent, name, V3(d, d, d), cf, color, material, Enum.PartType.Ball) end
-- Ellipsoid (SpecialMesh Sphere fills the part's Size).
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
local function wedgePart(parent, name, size, cf, color, material)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or M.SmoothPlastic
	w.Anchored = true
	w.CanCollide = SOLID
	w.CanQuery = SOLID
	w.CanTouch = false
	w.CastShadow = false
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	partCount += 1
	return w
end
local function glowBall(parent, name, d, cf, color) return ball(parent, name, d, cf, color, M.Neon) end
local function glowBox(parent, name, size, cf, color) return box(parent, name, size, cf, color, M.Neon) end
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
		for k, v in pairs(attrs) do inst:SetAttribute(k, v) end
	end
end
local function newModel(parent, name, tagName, attrs)
	local m = Instance.new("Model")
	m.Name = name
	pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
	m.Parent = parent
	if tagName then tag(m, tagName, attrs) end
	return m
end

-- // Placement: keep gameplay areas free; stand things on the real terrain ---------
local blockers = {}
local function blockCircle(x, z, r) table.insert(blockers, { x, z, r }) end
local function blockRect(x0, z0, x1, z1) table.insert(blockers, { x0, z0, x1, z1, true }) end
local function isFree(x, z, r)
	for _, b in ipairs(blockers) do
		if b[5] then
			local dx = max(b[1] - x, 0, x - b[3])
			local dz = max(b[2] - z, 0, z - b[4])
			if dx * dx + dz * dz < r * r then return false end
		else
			local dx, dz = x - b[1], z - b[2]
			local rr = b[3] + r
			if dx * dx + dz * dz < rr * rr then return false end
		end
	end
	return true
end
-- World CFrame standing on the terrain at local (x, z), yawed, sunk `sink` studs into the ground.
local function at(x, z, yawRad, sink)
	local g = groundAt(x, z)
	return ORIGIN * CF(x, g - (sink or 0), z) * ANG(0, yawRad or 0, 0)
end
-- Same, but tilted to the ground normal (for rocks / corals on slopes).
local function atSlope(x, z, yawRad, sink)
	local g, n = groundAt(x, z)
	local up = n
	local right = V3(0, 0, 1):Cross(up)
	if right.Magnitude < 1e-3 then right = V3(1, 0, 0) end
	right = right.Unit
	local look = up:Cross(right)
	local localCF = CFrame.fromMatrix(V3(x, g - (sink or 0), z), right, up, look.Unit * -1)
	return ORIGIN * localCF * ANG(0, yawRad or 0, 0)
end
-- Random spot in a rectangle that is free and (optionally) flat enough; reserves it.
local function place(x0, x1, z0, z1, r, maxSlope)
	for _ = 1, 50 do
		local x, z = rnd(x0, x1), rnd(z0, z1)
		if isFree(x, z, r) then
			local ok = true
			if maxSlope then
				local _, n = groundAt(x, z)
				ok = n.Y >= maxSlope
			end
			if ok then
				blockCircle(x, z, r)
				return x, z
			end
		end
	end
	return nil, nil
end

-- // Generic props (all standing on `cf`, +Y up, non-glowing) ------------------------
local function coralTree(parent, cf, h, color, tipColor)
	post(parent, "CoralTrunk", h * 0.17, h * 0.62, cf * CF(0, h * 0.31, 0), color, M.Pebble)
	local n = 3
	local y0 = rnd(0, pi)
	for i = 1, n do
		local bl = h * rnd(0.38, 0.52)
		local base = cf * CF(0, h * rnd(0.42, 0.55), 0) * ANG(0, y0 + i / n * 2 * pi, 0) * ANG(0, 0, -rad(rnd(26, 44)))
		post(parent, "CoralBranch", h * 0.11, bl, base * CF(0, bl / 2, 0), color, M.Pebble)
		ball(parent, "CoralTip", h * 0.17, base * CF(0, bl, 0), tipColor, M.SmoothPlastic)
	end
end
local function tableCoral(parent, cf, r, color, rimColor)
	post(parent, "TableStem", r * 0.32, r * 0.9, cf * CF(0, r * 0.45, 0), color, M.Pebble)
	post(parent, "TablePlate", r * 2, r * 0.22, cf * CF(0, r * 0.95, 0), color, M.Pebble)
	post(parent, "TableRim", r * 2.06, r * 0.08, cf * CF(0, r * 1.06, 0), rimColor, M.SmoothPlastic)
end
local function brainCoral(parent, cf, d, color)
	blob(parent, "BrainDome", V3(d, d * 0.62, d), cf * CF(0, d * 0.2, 0), color, M.Pebble)
	blob(parent, "BrainLobe", V3(d * 0.6, d * 0.4, d * 0.6), cf * CF(d * 0.5, d * 0.1, d * 0.2), color, M.Pebble)
	blob(parent, "BrainLobe", V3(d * 0.5, d * 0.36, d * 0.5), cf * CF(-d * 0.42, d * 0.08, -d * 0.3), color, M.Pebble)
end
local function tubeCoral(parent, cf, color, mouthColor, count)
	for i = 1, count do
		local h = rnd(2.4, 5.2)
		local a = (i / count) * 2 * pi + rnd(-0.4, 0.4)
		local base = cf * CF(cos(a) * 0.9, 0, sin(a) * 0.9) * ANG(rnd(-0.16, 0.16), 0, rnd(-0.16, 0.16))
		post(parent, "Tube", 0.95, h, base * CF(0, h / 2, 0), color, M.Pebble)
		if mouthColor then post(parent, "TubeMouth", 0.7, 0.2, base * CF(0, h + 0.02, 0), mouthColor, M.SmoothPlastic) end
	end
end
local function seaFan(parent, cf, w, color)
	post(parent, "FanStalk", w * 0.09, w * 0.4, cf * CF(0, w * 0.2, 0), color, M.SmoothPlastic)
	blob(parent, "FanBlade", V3(w, w * 0.8, w * 0.1), cf * CF(0, w * 0.8, 0), color, M.SmoothPlastic)
end
local function anemone(parent, cf, d, color, tipColor, tentacles)
	local m = newModel(parent, "Anemone", "WA_Sway", { WA_Amp = 5, WA_Speed = rnd(0.9, 1.4), WA_Phase = rnd(0, 6) })
	blob(m, "AnemoneBase", V3(d * 0.9, d * 0.6, d * 0.9), cf * CF(0, d * 0.18, 0), color, M.SmoothPlastic)
	local n = tentacles or 5
	for i = 1, n do
		local a = i / n * 2 * pi + rnd(-0.2, 0.2)
		local len = d * rnd(0.85, 1.2)
		local base = cf * CF(cos(a) * d * 0.22, d * 0.3, sin(a) * d * 0.22) * ANG(0, -a, 0) * ANG(0, 0, -rad(rnd(18, 34)))
		post(m, "Tentacle", d * 0.2, len, base * CF(0, len / 2, 0), color, M.SmoothPlastic)
		if tipColor then ball(m, "TentacleTip", d * 0.24, base * CF(0, len, 0), tipColor, M.SmoothPlastic) end
	end
	return m
end
-- Kelp tuft: `fronds` chains of leaning blade segments; sways as one unit.
local function kelp(parent, cf, h, color, tipColor, fronds, segs)
	local m = newModel(parent, "Kelp", "WA_Sway", { WA_Amp = rnd(5, 8), WA_Speed = rnd(0.5, 0.9), WA_Phase = rnd(0, 6) })
	fronds = fronds or 3
	segs = segs or 3
	local segH = h / segs
	for f = 1, fronds do
		local a = f / fronds * 2 * pi + rnd(-0.3, 0.3)
		local cur = cf * CF(cos(a) * 0.7, 0, sin(a) * 0.7) * ANG(0, a, 0)
		local w = rnd(0.9, 1.6)
		for s = 1, segs do
			cur = cur * ANG(0, 0, rad(rnd(-9, 9)))
			local taper = 1 - (s - 1) / segs * 0.45
			box(m, "KelpBlade", V3(w * taper, segH * 1.06, 0.32), cur * CF(0, segH / 2, 0), color, M.SmoothPlastic)
			cur = cur * CF(0, segH, 0)
		end
		if tipColor then ball(m, "KelpTip", 0.55, cur, tipColor, M.SmoothPlastic) end
	end
	return m
end
local function seagrass(parent, cf, h, color)
	local m = newModel(parent, "Seagrass", "WA_Sway", { WA_Amp = 9, WA_Speed = rnd(0.8, 1.3), WA_Phase = rnd(0, 6) })
	for i = 1, 2 do
		local bh = h * rnd(0.8, 1.15)
		local base = cf * CF((i - 1.5) * 0.7, 0, 0) * ANG(rnd(-0.2, 0.2), yaw(), rnd(-0.2, 0.2))
		box(m, "Blade", V3(0.9, bh, 0.14), base * CF(0, bh / 2, 0), color, M.SmoothPlastic)
	end
	return m
end
-- Rock with an optional cap colour (moss / snow / ash) and a pebble.
local function capRock(parent, cf, d, rockColor, capColor, rockMaterial)
	blob(parent, "Rock", V3(d, d * rnd(0.6, 0.8), d * rnd(0.85, 1.1)), cf * CF(0, d * 0.25, 0) * ANG(0, yaw(), 0), rockColor, rockMaterial or M.Slate)
	if capColor then blob(parent, "RockCap", V3(d * 0.66, d * 0.26, d * 0.62), cf * CF(d * 0.05, d * 0.55, 0), capColor, M.SmoothPlastic) end
	if d > 3.4 then blob(parent, "Pebble", V3(d * 0.3, d * 0.2, d * 0.3), cf * CF(d * 0.62, d * 0.1, d * 0.2), rockColor, rockMaterial or M.Slate) end
end
-- Lantern post: pole + glowing lamp (flickers). The ONLY always-neon prop; use sparingly.
local function lantern(parent, cf, h, color, withLight)
	post(parent, "LanternPole", 0.5, h, cf * CF(0, h / 2, 0), C3(60, 48, 40), M.Wood)
	box(parent, "LanternCap", V3(1.5, 0.3, 1.5), cf * CF(0, h + 1.35, 0), C3(60, 48, 40), M.Wood)
	local lamp = ball(parent, "LanternLamp", 1.5, cf * CF(0, h + 0.6, 0), color, M.Neon)
	tag(lamp, "WA_Flicker", { WA_Speed = rnd(1.4, 2.4), WA_Phase = rnd(0, 20) })
	if withLight then light(lamp, color, 1.2, 14) end
	return lamp
end
-- Wooden signpost (no neon): board with text on both faces. Board front = -Z of cf.
local function signPost(parent, cf, text, color, h, boardColor)
	h = h or 5.2
	post(parent, "SignPole", 0.55, h, cf * CF(0, h / 2, 0.15), C3(84, 62, 44), M.Wood)
	box(parent, "SignFrame", V3(9.6, 3.6, 0.3), cf * CF(0, h + 1.1, 0.3), C3(110, 80, 52), M.Wood)
	local board = box(parent, "SignBoard", V3(9, 3.1, 0.4), cf * CF(0, h + 1.1, 0), boardColor or C3(40, 58, 78), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.7
		label.Parent = gui
	end
	return board
end
-- Invisible emitter part (tag WA_Bubbles): bubbles / smoke / embers rise from it.
local function emitter(parent, cf, kind)
	local e = mk(parent, "Emitter", V3(1, 1, 1), cf, C3(255, 255, 255), M.SmoothPlastic)
	e.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Bubbles"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rotation = NumberRange.new(0, 360)
	if kind == "smoke" then
		pe.Color = ColorSequence.new(C3(40, 36, 44))
		pe.LightEmission = 0
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(4, 6)
		pe.Speed = NumberRange.new(4, 6)
		pe.Rate = 4
	elseif kind == "ember" then
		pe.Color = ColorSequence.new(C3(255, 150, 70))
		pe.LightEmission = 0.6
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.1) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.3), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(3, 5)
		pe.Speed = NumberRange.new(6, 9)
		pe.Rate = 3
	else
		pe.Color = ColorSequence.new(C3(220, 245, 255))
		pe.LightEmission = 0.3
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.3), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(3, 5)
		pe.Speed = NumberRange.new(5, 8)
		pe.Rate = 5
	end
	pe.Acceleration = V3(0, 1.5, 0)
	pe.SpreadAngle = Vector2.new(9, 9)
	pe.Parent = e
	pe:SetAttribute("BaseRate", pe.Rate)
	tag(e, "WA_Bubbles", {})
	return e
end
-- Soft sun / moon shaft: crossing planes, very transparent and NOT neon (SmoothPlastic), rotates slowly.
local function lightShaft(parent, cf, h, w, color, transp)
	local m = newModel(parent, "LightShaft", "WA_Rotate", { WA_Spin = rnd(1.5, 3) * (rng:NextNumber() < 0.5 and 1 or -1) })
	for i = 0, 1 do
		local p = box(m, "ShaftPlane", V3(w, h, 0.05), cf * CF(0, h / 2, 0) * ANG(0, i * pi / 2 + 0.4, 0), color, M.SmoothPlastic)
		p.Transparency = transp or 0.93
	end
	return m
end
-- Ambient fish/jelly/ray school marker; the client spawns local-only creatures (zero server cost).
local function school(parent, cf, kind, count, size, c1, c2, rx, ry, rz, speed)
	local p = mk(parent, "School_" .. kind, V3(1, 1, 1), cf, c1, M.SmoothPlastic)
	p.Transparency = 1
	tag(p, "WA_School", {
		WA_Kind = kind, WA_Count = count, WA_Size = size, WA_Color = c1, WA_Color2 = c2,
		WA_RadiusX = rx, WA_RadiusY = ry, WA_RadiusZ = rz, WA_Speed = speed, WA_Seed = rng:NextInteger(1, 100000),
	})
	return p
end
local function barrel(parent, cf, s)
	post(parent, "Barrel", 1.6 * s, 2.2 * s, cf * CF(0, 1.1 * s, 0), C3(110, 76, 48), M.Wood)
	post(parent, "BarrelBand", 1.72 * s, 0.22 * s, cf * CF(0, 1.5 * s, 0), C3(60, 60, 68), M.Metal)
end
local function crate(parent, cf, s)
	box(parent, "Crate", V3(2.2 * s, 2 * s, 2.2 * s), cf * CF(0, 1 * s, 0), C3(124, 92, 58), M.WoodPlanks)
	box(parent, "CrateStrap", V3(2.3 * s, 0.3 * s, 2.3 * s), cf * CF(0, 1.4 * s, 0), C3(80, 58, 38), M.Wood)
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
-- Treasure chest with a gold heap (gold = Metal, not neon) and two gems (tiny glow accents allowed).
local function treasureChest(parent, cf, s, gems)
	box(parent, "ChestBase", V3(4.4 * s, 2.2 * s, 2.8 * s), cf * CF(0, 1.1 * s, 0), C3(110, 70, 42), M.WoodPlanks)
	box(parent, "ChestBand", V3(4.6 * s, 0.35 * s, 3 * s), cf * CF(0, 1.9 * s, 0), C3(214, 170, 60), M.Metal)
	box(parent, "ChestLid", V3(4.4 * s, 0.9 * s, 2.8 * s), cf * CF(0, 2.9 * s, -1.2 * s) * ANG(rad(-38), 0, 0), C3(124, 80, 48), M.WoodPlanks)
	blob(parent, "GoldHeap", V3(3.6 * s, 1.2 * s, 2 * s), cf * CF(0, 2.3 * s, 0.1 * s), C3(255, 204, 70), M.Metal)
	if gems then
		glowBall(parent, "Gem", 0.8 * s, cf * CF(1 * s, 3.0 * s, 0.3 * s), C3(255, 110, 200))
	end
end
local function coinPile(parent, cf, s)
	local gold = C3(255, 204, 70)
	blob(parent, "CoinMound", V3(3 * s, 0.9 * s, 3 * s), cf * CF(0, 0.3 * s, 0), gold, M.Metal)
	for i = 1, 3 do
		local a = i / 3 * 2 * pi + rnd(-0.4, 0.4)
		post(parent, "Coin", 0.9 * s, 0.14 * s, cf * CF(cos(a) * 1.5 * s, 0.4 * s, sin(a) * 1.5 * s) * ANG(rnd(-0.6, 0.6), 0, rnd(-0.6, 0.6)), gold, M.Metal)
	end
end
-- Crystal cluster of leaning wedge shards (material decides glow: Glass/Ice = none, Neon = accent).
local function crystalCluster(parent, cf, h, colors, count, material, transparency)
	for i = 1, count do
		local hh = h * rnd(0.45, 1)
		local w = hh * rnd(0.16, 0.24)
		local a = i / count * 2 * pi + rnd(-0.4, 0.4)
		local off = i == 1 and 0 or hh * 0.28
		local p = wedgePart(parent, "Crystal", V3(w, hh, hh * rnd(0.5, 0.75)),
			cf * CF(cos(a) * off, hh * 0.45, sin(a) * off) * ANG(0, rnd(0, 2 * pi), 0) * ANG(rnd(-0.22, 0.22), 0, rnd(-0.22, 0.22)),
			pick(colors), material or M.Glass)
		if transparency then p.Transparency = transparency end
		if p.Material == M.Neon then neonCount += 1 end
	end
end
local function column(parent, cf, h, color, broken)
	box(parent, "ColumnFoot", V3(3.6, 0.9, 3.6), cf * CF(0, 0.45, 0), color, M.Limestone)
	local hh = broken and h * 0.55 or h
	post(parent, "ColumnShaft", 2.2, hh, cf * CF(0, 0.9 + hh / 2, 0), color, M.Limestone)
	if broken then
		post(parent, "ColumnFallen", 2.1, h * 0.4, cf * CF(3.4, 1.05, 1.4) * ANG(0, rad(30), 0) * ANG(0, 0, pi / 2), color, M.Limestone)
	else
		box(parent, "ColumnCap", V3(3.4, 0.8, 3.4), cf * CF(0, 0.9 + h + 0.4, 0), color, M.Limestone)
	end
end
-- Lantern-style hanging jelly / spore bulb: translucent, only the tiny core is neon.
local function glowBulb(parent, cf, d, color, coreColor)
	local m = newModel(parent, "GlowBulb", "WA_Bob", { WA_BobAmp = 0.5, WA_BobSpeed = rnd(0.6, 0.9), WA_Phase = rnd(0, 6), WA_Spin = 0 })
	local shell = blob(m, "BulbShell", V3(d, d * 0.8, d), cf, color, M.SmoothPlastic)
	shell.Transparency = 0.45
	glowBall(m, "BulbCore", d * 0.34, cf, coreColor or color)
	return m
end
local function clam(parent, cf, d, color)
	blob(parent, "ClamBottom", V3(d, d * 0.35, d * 0.8), cf * CF(0, d * 0.16, 0), color, M.SmoothPlastic)
	blob(parent, "ClamLid", V3(d, d * 0.3, d * 0.8), cf * CF(0, d * 0.5, -d * 0.28) * ANG(rad(-48), 0, 0), color, M.SmoothPlastic)
	ball(parent, "Pearl", d * 0.26, cf * CF(0, d * 0.34, 0), C3(255, 244, 250), M.SmoothPlastic)
end
local function starfish(parent, cf, d, color)
	blob(parent, "Starfish", V3(d, 0.35, d), cf * CF(0, 0.1, 0), color, M.Pebble)
	blob(parent, "StarfishArm", V3(d * 0.4, 0.3, d * 1.1), cf * CF(0, 0.12, 0) * ANG(0, rad(60), 0), color, M.Pebble)
end

-- Tall kelp ribbon (3 parts): stem plus two leaf blades; sways as one unit.
local function tallKelp(parent, cf, h, color)
	local m = newModel(parent, "TallKelp", "WA_Sway", { WA_Amp = rnd(4, 7), WA_Speed = rnd(0.4, 0.8), WA_Phase = rnd(0, 6) })
	post(m, "KelpStem", 0.45, h, cf * CF(0, h / 2, 0), color, M.SmoothPlastic)
	for i = 1, 2 do
		local a = i * 2.9 + rnd(0, 1)
		local bl = h * 0.4
		box(m, "KelpLeaf", V3(2.2, bl, 0.18), cf * CF(cos(a) * 0.8, h * (0.3 + 0.26 * i), sin(a) * 0.8) * ANG(0, a, 0) * ANG(0, 0, rad(-16)) * CF(0, bl / 2, 0), color, M.SmoothPlastic)
	end
	return m
end
-- Stone arch in the cf's XY plane facing local Z: two pillars plus a segmented arc. span = inner width.
local function rockArch(parent, cf, span, pillarH, depth, color, material)
	local r = span / 2 + 1.4
	for _, s in ipairs({ -1, 1 }) do
		blob(parent, "ArchPillar", V3(3.8, pillarH * 0.55, depth * 1.1), cf * CF(s * r, pillarH * 0.27, 0), color, material)
		blob(parent, "ArchPillar", V3(3.2, pillarH * 0.6, depth * 0.95), cf * CF(s * r, pillarH * 0.68, 0), color:Lerp(C3(255, 255, 255), 0.08), material)
	end
	local n = 7
	for i = 0, n - 1 do
		local a0 = pi * (i + 0.5) / n
		local c = cf * CF(cos(a0) * r, pillarH * 0.9 + sin(a0) * r * 0.75, 0) * ANG(0, 0, a0)
		box(parent, "ArchStone", V3(3.2, r * 0.62, depth), c, color:Lerp(C3(255, 255, 255), (i % 2) * 0.07), material)
	end
end

-- Cylinder beam between two ZONE-LOCAL points (bones, ribs, pipes, rigging).
local function beam(parent, name, a, b, d, color, material)
	local wa, wb = ORIGIN:PointToWorldSpace(a), ORIGIN:PointToWorldSpace(b)
	local len = (wb - wa).Magnitude
	local cf = CFrame.lookAt((wa + wb) / 2, wb) * ANG(0, pi / 2, 0)
	return mk(parent, name, V3(len + 0.15, d, d), cf, color, material, Enum.PartType.Cylinder)
end
-- // end shared part helpers ----------------------------------------------------

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local worldFolder = getOrCreateFolder(assetsFolder, "World")
local previous = worldFolder:FindFirstChild("SunZoneDressing")
if previous then previous:Destroy() end
local model = Instance.new("Model")
model.Name = "SunZoneDressing"
model.Parent = worldFolder
local function group(name)
	return getOrCreateFolder(model, name)
end

-- // Reserved gameplay areas (must match the trails in SunZoneTerrainChunk.lua) -----------
local function blockTrail(pts, width)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		for k = 0, math.ceil(len / 3) do
			local t = k / math.ceil(len / 3)
			blockCircle(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, width / 2 + 1)
		end
	end
end
blockCircle(0, 0, 16)
blockTrail({ { 0, 0 }, { 8, 6 }, { 14, 10 }, { 18.5, 13.5 } }, 6)
blockTrail({ { 0, 0 }, { 4, -12 }, { 7, -20 } }, 6)
blockTrail({ { 0, 0 }, { -18, -1 }, { -36, 0 } }, 7)
blockTrail({ { 0, 0 }, { -10, 12 }, { -18, 22 } }, 6)
blockCircle(24, 26, 18) -- ship footprint
blockCircle(-24, 24, 11) -- tide pool
blockCircle(-41, 0, 9) -- gate

local CORAL = { C3(255, 110, 150), C3(255, 150, 70), C3(178, 112, 226), C3(250, 206, 70), C3(64, 202, 190), C3(238, 72, 84) }
local function lighter(c, k) return c:Lerp(C3(255, 255, 255), k or 0.35) end
local function coral(parent, kind, x, z, size, ci, yawRad)
	local c = CORAL[ci]
	local cf = at(x, z, yawRad or yaw(), 0.3)
	if kind == "tree" then coralTree(parent, cf, size, c, lighter(c))
	elseif kind == "table" then tableCoral(parent, cf, size * 0.5, c, lighter(c, 0.45))
	elseif kind == "brain" then brainCoral(parent, cf, size, c)
	elseif kind == "tube" then tubeCoral(parent, cf, c, nil, 3)
	elseif kind == "fan" then seaFan(parent, cf, size, c)
	elseif kind == "anemone" then anemone(parent, cf, size, c, nil, 4) end
end

-- // 1) Coral Garden on the terrace (centre 14,-34, top y = 3) ---------------------------
do
	local g = group("CoralGarden")
	local spec = {
		{ "tree", 8, -30, 9, 1 }, { "table", 18, -30, 8, 4 }, { "tree", 24, -34, 8, 5 }, { "brain", 12, -39, 5, 3 },
		{ "tube", 20, -38, 0, 2 }, { "fan", 4, -36, 6, 6 }, { "tree", 14, -26, 6, 2 }, { "anemone", 27, -41, 4, 1 },
		{ "table", 6, -42, 7, 5 }, { "fan", 22, -44, 7, 3 }, { "anemone", 2, -31, 4, 4 },
		{ "tube", 28, -30, 0, 5 }, { "tree", 34, -40, 7, 6 },
	}
	for _, s in ipairs(spec) do coral(g, s[1], s[2], s[3], s[4], s[5]) end
end

-- // 2) Wreck Cove ---------------------------------------------------------------------
local shipFrame = at(24, 26, rad(10), 2.4) * ANG(0, 0, rad(5)) -- same as the ship in the chunk script
local function sw(lx, lz) -- ship-local to zone-local x/z
	local a = rad(10)
	return 24 + lx * cos(a) + lz * sin(a), 26 - lx * sin(a) + lz * cos(a)
end
do
	local g = group("WreckCove")
	treasureChest(g, shipFrame * CF(0, 1.2, 0), 1.0, true) -- inside the hull, visible through the deck gap
	coinPile(g, shipFrame * CF(3.5, 1.2, 1.5), 1)
	local x, z = sw(19, 7); coinPile(g, at(x, z), 1.2)
	x, z = sw(15, 9); treasureChest(g, at(x, z, rad(20), 0.2), 0.9, false)
	for i, s in ipairs({ { 6, 8.5 }, { 8, 9.5 }, { -4, 9 }, { 22, -3 } }) do
		x, z = sw(s[1], s[2]); barrel(g, at(x, z, yaw(), 0.2), 1.0 + (i % 2) * 0.2)
	end
	for _, s in ipairs({ { 0, 9.5 }, { -8, 10 }, { 20, -6 } }) do
		x, z = sw(s[1], s[2]); crate(g, at(x, z, yaw(), 0.1), 1)
	end
	for i, s in ipairs({ { -18, 6 }, { 11, 12 }, { 24, 3 } }) do
		x, z = sw(s[1], s[2]); amphora(g, atSlope(x, z, yaw(), 0.4), 1.1, pick({ C3(196, 120, 80), C3(214, 160, 110), C3(160, 100, 80) }))
	end
	x, z = sw(-20, -3); shipAnchor(g, at(x, z, rad(70), 0.5), 1.4)
	for i = 1, 3 do -- broken ribs of a second, buried hull piece next to the wreck
		x, z = sw(-6 + i * 3.2, 15); local f = at(x, z, rad(10)); box(g, "Rib", V3(0.6, 5 - i * 0.6, 0.6), f * CF(0, 2, 0) * ANG(rad(22), 0, 0), C3(104, 74, 50), M.Wood)
	end
	-- corals growing on the hull, plus sand-coloured barnacle rocks
	for i, s in ipairs({ { -9, 4.6 }, { -1, 4.8 }, { 7, 4.6 }, { 13, 3.2 } }) do
		local c = CORAL[((i * 2) % #CORAL) + 1]
		local cf = shipFrame * CF(s[1], 5.2, s[2]) * ANG(0, yaw(), 0)
		if i % 2 == 0 then brainCoral(g, cf, 2.4, c) else tubeCoral(g, cf, c, nil, 3) end
	end
	-- a few small fish-bone / shell accents, then the gold glint is intentionally NOT glowing
end

-- // 3) Tide pool ----------------------------------------------------------------------
do
	local g = group("TidePool")
	local cx, cz = -24, 24
	local pool = post(g, "PoolWater", 15, 0.15, at(cx, cz, 0, -(-0.9)), C3(70, 214, 222), M.Glass)
	pool.Transparency = 0.45
	for i = 1, 7 do
		local a = i / 7 * 2 * pi + rnd(-0.15, 0.15)
		capRock(g, at(cx + cos(a) * 9.6, cz + sin(a) * 9.6, 0, 0.4), rnd(3, 5), C3(222, 196, 164), nil, M.Limestone)
	end
	clam(g, at(cx + 2, cz - 2, rad(40), -0.9), 2.4, C3(255, 170, 190))
	clam(g, at(cx - 3, cz + 2, rad(-30), -0.9), 2, C3(190, 170, 255))
	starfish(g, at(cx + 1, cz + 3, rad(10), -1.3), 2.2, C3(255, 120, 80))
	starfish(g, at(cx - 2, cz - 3, rad(50), -1.3), 1.8, C3(255, 180, 70))
	seagrass(g, at(cx - 5, cz - 1, 0, -0.6), 3.4, C3(70, 176, 120))
	seagrass(g, at(cx + 5, cz + 1, 0, -0.6), 3.0, C3(96, 196, 128))
	coral(g, "brain", cx + 12, cz - 4, 3.5, 1)
	coral(g, "tree", cx + 11, cz + 6, 5, 4)
	coral(g, "fan", cx - 11, cz + 5, 5, 3)
	coral(g, "tube", cx - 8, cz - 9, 0, 5)
end

-- // 4) Sun Gate, landing and trails --------------------------------------------------------
do
	local g = group("GateAndLanding")
	signPost(g, at(9, -7, rad(-62), 0), "Coral Garden  <  >  Pirate Wreck", C3(255, 224, 150), 5, C3(48, 96, 120))
	signPost(g, at(-12, 5, rad(90), 0), "< Sun Gate", C3(255, 224, 150), 5, C3(48, 96, 120))
	local lamps = {
		{ -41, -10 }, { -41, 10 }, { 6, 8 }, { 16, 18 }, { 2, -9 }, { 8, -18 },
	}
	for i, p in ipairs(lamps) do
		lantern(g, at(p[1], p[2], 0, 0), 4.2, C3(255, 214, 120), i <= 2)
	end
	for _, p in ipairs({ { -8, -3 }, { 9, -2 }, { 3, 9 } }) do
		capRock(g, at(p[1], p[2] + 9, 0, 0.2), rnd(2, 3), C3(236, 214, 176), nil, M.Limestone)
	end
end

-- // 5) Seagrass meadows (the LeafyGrass patches) ------------------------------------------
do
	local g = group("Meadows")
	local green = { C3(70, 176, 120), C3(96, 200, 126), C3(60, 150, 110) }
	local patches = { { -12, -30, 9, 7 }, { -30, -22, 6, 4 }, { 36, -22, 8, 6 }, { -4, 36, 8, 6 }, { 42, 30, 5, 3 } }
	for _, p in ipairs(patches) do
		for i = 1, p[4] do
			local a, d = rnd(0, 2 * pi), rnd(0, p[3] * 0.85)
			seagrass(g, at(p[1] + cos(a) * d, p[2] + sin(a) * d, yaw()), rnd(2.6, 4.6), pick(green))
		end
		if p[3] >= 8 then
			kelp(g, at(p[1] + 2, p[2] - 1, 0), rnd(7, 10), C3(70, 170, 100), nil, 2, 3)
		end
	end
end

-- // 6) Coral clumps hugging the reef wall, rocks at the dune feet ------------------------------
do
	local g = group("ReefClumps")
	local n = 0
	local spots = {
		{ -40, -34 }, { -26, -41 }, { 40, -28 }, { 41, 2 }, { 38, 14 }, { 28, 42 },
		{ -14, 42 }, { -42, -16 }, { -42, 18 }, { 0, -43 },
	}
	for _, s in ipairs(spots) do
		if isFree(s[1], s[2], 3) then
			n += 1
			local ci = (n % #CORAL) + 1
			local kinds = { "tree", "fan", "brain", "tube", "anemone" }
			coral(g, kinds[(n % #kinds) + 1], s[1], s[2], rnd(4, 6), ci)
			if n % 2 == 0 then coral(g, kinds[((n + 2) % #kinds) + 1], s[1] + rnd(-3, 3), s[2] + rnd(-3, 3), rnd(3, 5), ((n + 3) % #CORAL) + 1) end
		end
	end
	for _ = 1, 6 do
		local x, z = place(-44, 44, -44, 44, 3, 0.95)
		if x then capRock(g, atSlope(x, z, yaw(), 0.3), rnd(2.4, 4), C3(222, 196, 162), nil, M.Limestone) end
	end
end

-- // 7) Light, bubbles, life -----------------------------------------------------------------
do
	local g = group("Ambience")
	for _, p in ipairs({ { -14, -8 }, { 12, -14 }, { -20, 30 } }) do
		lightShaft(g, at(p[1], p[2], 0, 0), 62, 12, C3(255, 236, 170), 0.955)
	end
	for _, p in ipairs({ { -30, -14 }, { 44, 18 }, { 12, 40 } }) do
		emitter(g, at(p[1], p[2], 0, -0.6), "bubbles")
	end
	school(g, at(8, -10, 0, -9), "Fish", 6, 2.6, C3(255, 200, 70), C3(255, 120, 60), 16, 4, 16, 0.5)
	school(g, at(24, 26, 0, -16), "Fish", 5, 2.4, C3(70, 200, 230), C3(255, 235, 120), 14, 4, 12, 0.45)
end

print(string.format("[Abyssara] SunZoneDressing v3: %d parts (%d neon, %.1f%%)", partCount, neonCount, neonCount / max(partCount, 1) * 100))
