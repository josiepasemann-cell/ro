--[[
	Abyssara - Deep Tide Tycoon
	Asset type: World set dressing
	Name: HubDressing (v3 - cozy market plaza)

	Dresses the Tidal Market hub (TidalMarketHub, plaza radius 110, top y = 2 at -500, 0, -500) as a
	readable, cozy harbour market instead of a light show:
		- 8 market stalls with striped Fabric awnings, counters and wares in a ring (r about 78),
		- 8 wooden piers pointing outwards over the beach ring with mooring posts, 3 rowboats, lanterns,
		- lane lanterns (warm, 12), zone signposts at the four lane starts and at the plot road,
		- benches, planters (coral / seagrass in wood boxes), colourful banner poles,
		- beach dressing outside the plaza: tall kelp, coral clumps, boulders (placed on HubTerrain.lua),
		- 3 faint light shafts (not neon), bubble vents and two fish/jelly school markers.

	GAMEPLAY AREAS STAY FREE (blockCircle / blockRect): centre landmark (r 18), the four 20-stud lanes to the
	portals, the plot road (diagonal +X +Z), six spawns, the four interactable stands (shop, gacha,
	leaderboard, quest board), the trade dock and the NPCs around them. Piers sit between the lanes.
	Only the pier decks are collidable; everything else is CanCollide/CanQuery/CanTouch = false.
	Glow budget: about 5 percent Neon (lantern lamps only). Animation: src/client/WorldAmbience.client.lua.

	Run: Studio Command Bar, edit mode, AFTER hub/HubTerrain.lua and hub/TidalMarketHub.lua.
	Result: Workspace.Assets.World.HubDressing. Re-running replaces it.
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(-500, 0, -500) -- must match TidalMarketHub.lua / HubTerrain.lua
local PLAZA_RADIUS = 110
local TOP = 2 -- plaza top (PLAZA_THICKNESS / 2)
local RANDOM_SEED = 7505
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

-- On the plaza the walking surface is the HubBase slab (y = 2); outside r 110 it is the HubTerrain beach.
local function topAt(x, z)
	if x * x + z * z <= (PLAZA_RADIUS - 1) ^ 2 then return TOP end
	local g = groundAt(x, z)
	return g
end
local function at(x, z, yawRad, sink)
	return ORIGIN * CF(x, topAt(x, z) - (sink or 0), z) * ANG(0, yawRad or 0, 0)
end
local function polar(r, deg) return cos(rad(deg)) * r, sin(rad(deg)) * r end
-- cframe at (x, z) whose -Z looks at the plaza centre (stalls, signs, benches face the middle)
local function facingCentre(x, z, sink)
	local p = ORIGIN:PointToWorldSpace(V3(x, topAt(x, z) - (sink or 0), z))
	local c = ORIGIN:PointToWorldSpace(V3(0, topAt(x, z) - (sink or 0), 0))
	return CFrame.lookAt(p, c)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local worldFolder = getOrCreateFolder(assetsFolder, "World")
local previous = worldFolder:FindFirstChild("HubDressing")
if previous then previous:Destroy() end
local model = Instance.new("Model")
model.Name = "HubDressing"
model.Parent = worldFolder
local function group(name) return getOrCreateFolder(model, name) end

-- // Reserved gameplay areas (hub-local coordinates, centre = 0,0) -------------------------
blockCircle(0, 0, 18) -- centre landmark
blockRect(-112, -11, 112, 11) -- lanes to the Sun (+X) and Midnight (-X) portals
blockRect(-11, -112, 11, 112) -- lanes to the Twilight (+Z) and Hadal (-Z) portals
for _, a in ipairs({ 20, 70, 130, 200, 250, 310 }) do
	local x, z = polar(34, a)
	blockCircle(x, z, 8) -- spawns
end
local STANDS = { { -40.6, -31.9 }, { 43.5, -23.2 }, { -49.3, 20.3 }, { 11.6, 55.1 } }
for _, s in ipairs(STANDS) do blockCircle(s[1], s[2], 15) end -- stands + their NPCs
blockRect(-17, 53, 0, 90) -- trade dock
for r = 90, 250, 10 do blockCircle(r * 0.7071, r * 0.7071, 13) end -- plot road (diagonal)
for _, p in ipairs({ { 92, 0 }, { 0, 92 }, { -92, 0 }, { 0, -92 } }) do blockCircle(p[1], p[2], 14) end -- portals

local WOOD = C3(150, 108, 74)
local WOOD_DARK = C3(104, 74, 52)
local AWNING = {
	{ C3(236, 90, 84), C3(250, 240, 224) }, { C3(46, 150, 176), C3(250, 240, 224) },
	{ C3(240, 176, 60), C3(250, 240, 224) }, { C3(110, 170, 100), C3(250, 240, 224) },
}
local WARES = { C3(255, 150, 70), C3(240, 90, 110), C3(120, 200, 130), C3(250, 214, 90), C3(150, 120, 220) }

-- // 1) Market stalls --------------------------------------------------------------------------
local function stall(parent, cf, colors, lampOn)
	box(parent, "StallCounter", V3(5.6, 2.4, 2.2), cf * CF(0, 1.2, 0), WOOD, M.WoodPlanks)
	box(parent, "StallTop", V3(5.9, 0.3, 2.5), cf * CF(0, 2.5, 0), WOOD_DARK, M.Wood)
	for _, sx in ipairs({ -2.7, 2.7 }) do
		post(parent, "StallPostBack", 0.35, 6.6, cf * CF(sx, 3.3, 1.7), WOOD_DARK, M.Wood)
		post(parent, "StallPostFront", 0.35, 5, cf * CF(sx, 2.5, -1.9), WOOD_DARK, M.Wood)
	end
	for i = 1, 6 do -- striped awning, slopes down to the front
		box(parent, "AwningStripe", V3(0.98, 0.14, 4.9), cf * CF(-2.45 + (i - 0.5) * 0.98, 5.6, -0.1) * ANG(rad(-13), 0, 0), colors[(i % 2) + 1], M.Fabric)
	end
	for i = 1, 3 do -- wares on the counter
		local c = pick(WARES)
		if i == 1 then post(parent, "WareBarrel", 1.0, 0.9, cf * CF(-1.6, 3.1, 0), WOOD_DARK, M.Wood)
		else box(parent, "WareCrate", V3(0.9, 0.7, 0.9), cf * CF((i - 2) * 1.5, 3, 0.1), c, M.SmoothPlastic) end
	end
	box(parent, "StallBoard", V3(3.6, 0.9, 0.2), cf * CF(0, 4.3, -2.05), C3(250, 240, 224), M.SmoothPlastic)
	if lampOn then
		local l = ball(parent, "StallLamp", 0.9, cf * CF(2.1, 4.6, -2.2), C3(255, 210, 130), M.Neon)
		neonCount += 1
		tag(l, "WA_Flicker", { WA_Speed = rnd(1.4, 2.2), WA_Phase = rnd(0, 20) })
	end
end
do
	local g = group("Stalls")
	local placed = 0
	for i, a in ipairs({ 22, 58, 100, 128, 150, 178, 235, 280, 305, 340, 200, 118 }) do
		local x, z = polar(78, a)
		if placed < 8 and isFree(x, z, 8) then
			blockCircle(x, z, 8)
			placed += 1
			local cf = facingCentre(x, z, 0)
			stall(g, cf, AWNING[(placed % #AWNING) + 1], placed % 3 == 0)
			-- crates and barrels beside the stall
			box(g, "SideCrate", V3(2, 1.8, 2), cf * CF(4.6, 0.9, 0.6) * ANG(0, rad(rnd(-20, 20)), 0), WOOD, M.WoodPlanks)
			barrel(g, cf * CF(-4.6, 0, 0.8), 1)
		end
	end
end

-- // 2) Wooden piers over the beach ring ------------------------------------------------------------
do
	local g = group("Piers")
	local boats = { [1] = true, [4] = true, [6] = true }
	for i, a in ipairs({ 20, 70, 110, 160, 200, 250, 290, 340 }) do
		local x, z = polar(118, a)
		local cf = ORIGIN * CF(x, TOP + 0.5, z) * ANG(0, -rad(a) + pi / 2, 0) -- local -Z points to the plaza, +Z outwards
		setSolid(true)
		box(g, "PierDeck", V3(6.4, 0.5, 22), cf, WOOD, M.WoodPlanks)
		setSolid(false)
		for _, side in ipairs({ -1, 1 }) do
			for _, zz in ipairs({ -8, 0, 8 }) do
				post(g, "PierPost", 0.7, 3.4, cf * CF(side * 3.3, -0.8, zz), WOOD_DARK, M.Wood)
			end
			box(g, "PierRail", V3(0.25, 0.25, 22), cf * CF(side * 3.3, 1.8, 0), WOOD_DARK, M.Wood)
		end
		for _, side in ipairs({ -1, 1 }) do post(g, "Bollard", 0.7, 1.2, cf * CF(side * 3, 1.1, 10.4), C3(60, 50, 44), M.Metal) end
		if i % 2 == 0 then
			post(g, "PierLampPole", 0.35, 3.4, cf * CF(3.3, 2.2, 10), WOOD_DARK, M.Wood)
			local l = ball(g, "PierLamp", 1.1, cf * CF(3.3, 4.3, 10), C3(255, 210, 130), M.Neon)
			neonCount += 1
			tag(l, "WA_Flicker", { WA_Speed = rnd(1.4, 2.2), WA_Phase = rnd(0, 20) })
		end
		if boats[i] then -- little rowboat resting on the sand next to the pier
			local b = cf * CF(7.2, 0.1, 6) * ANG(0, rad(8), 0)
			blob(g, "BoatHull", V3(2.6, 1.3, 6.6), b * CF(0, 0.4, 0), C3(196, 90, 70), M.WoodPlanks)
			box(g, "BoatSeat", V3(2.2, 0.2, 0.7), b * CF(0, 0.95, 0.4), WOOD, M.Wood)
			post(g, "BoatOar", 0.2, 3, b * CF(1.5, 1.2, -0.4) * ANG(0, 0, rad(70)), WOOD_DARK, M.Wood)
		end
	end
end

-- // 3) Lane lanterns, signposts ---------------------------------------------------------------------
do
	local g = group("LanesAndSigns")
	local names = { { 0, "Sun Zone  Lv 1" }, { 90, "Twilight Zone  Lv 10" }, { 180, "Midnight Zone  Lv 25" }, { 270, "Hadal Depths  Lv 45" } }
	for li, n in ipairs(names) do
		for k, r in ipairs({ 32, 56, 80 }) do -- warm lanterns on alternating sides of each lane
			local side = (k % 2 == 0) and 13 or -13
			local lx, lz = polar(r, n[1])
			local px, pz = polar(side, n[1] + 90)
			if isFree(lx + px, lz + pz, 2) then lantern(g, at(lx + px, lz + pz, 0, 0), 4.2, C3(255, 206, 128), li == 1 and k == 1) end
		end
		local sx, sz = polar(24, n[1])
		local ox, oz = polar(14.5, n[1] + 90)
		local p = ORIGIN:PointToWorldSpace(V3(sx + ox, TOP, sz + oz))
		signPost(g, CFrame.lookAt(p, ORIGIN:PointToWorldSpace(V3(0, TOP, 0))), n[2], C3(255, 240, 210), 4.4, C3(54, 94, 120))
	end
	local rx, rz = polar(118, 45)
	local p = ORIGIN:PointToWorldSpace(V3(rx - 7, TOP, rz + 7))
	signPost(g, CFrame.lookAt(p, ORIGIN:PointToWorldSpace(V3(0, TOP, 0))), "My Plot  >>", C3(255, 240, 210), 4.4, C3(54, 120, 90))
end

-- // 4) Benches and planters -------------------------------------------------------------------------
do
	local g = group("Furniture")
	local benches = 0
	for _ = 1, 30 do
		if benches >= 6 then break end
		local r, a = rnd(44, 66), rnd(0, 360)
		local x, z = polar(r, a)
		if isFree(x, z, 4) then
			blockCircle(x, z, 4)
			benches += 1
			local cf = facingCentre(x, z, 0)
			box(g, "BenchSeat", V3(4.4, 0.35, 1.3), cf * CF(0, 1.5, 0), WOOD, M.WoodPlanks)
			box(g, "BenchBack", V3(4.4, 1.1, 0.25), cf * CF(0, 2.3, 0.6) * ANG(rad(-8), 0, 0), WOOD, M.WoodPlanks)
			for _, sx in ipairs({ -1.8, 1.8 }) do box(g, "BenchLeg", V3(0.35, 1.5, 1.1), cf * CF(sx, 0.75, 0), WOOD_DARK, M.Wood) end
		end
	end
	local pots = 0
	for _ = 1, 50 do
		if pots >= 8 then break end
		local r, a = rnd(46, 104), rnd(0, 360)
		local x, z = polar(r, a)
		if isFree(x, z, 4) then
			blockCircle(x, z, 4)
			pots += 1
			local cf = at(x, z, yaw(), 0)
			box(g, "PlanterBox", V3(3.4, 1.4, 3.4), cf * CF(0, 0.7, 0), WOOD, M.WoodPlanks)
			box(g, "PlanterSoil", V3(3, 0.3, 3), cf * CF(0, 1.45, 0), C3(88, 66, 48), M.Ground)
			if pots % 2 == 0 then coralTree(g, cf * CF(0, 1.5, 0), 4.2, pick(WARES), pick(WARES)) else seagrass(g, cf * CF(0, 1.5, 0), 3.2, C3(80, 170, 120)) end
		end
	end
	-- banner poles: bright Fabric flags along the plaza rim
	for i = 1, 14 do
		local a = i / 14 * 360 + 7
		local x, z = polar(105, a)
		if isFree(x, z, 2) then
			local cf = at(x, z, rad(-a + 90), 0)
			post(g, "BannerPole", 0.3, 6.4, cf * CF(0, 3.2, 0), WOOD_DARK, M.Wood)
			box(g, "BannerFlag", V3(0.12, 2.6, 1.7), cf * CF(0, 5.2, 1), AWNING[(i % #AWNING) + 1][1], M.Fabric)
		end
	end
end

-- // 5) Beach and seabed outside the plaza (placed on HubTerrain) --------------------------------------
do
	local g = group("Beach")
	local KELP = { C3(52, 150, 120), C3(70, 170, 110), C3(40, 130, 130) }
	for _ = 1, 14 do
		local r, a = rnd(124, 140), rnd(0, 360)
		local x, z = polar(r, a)
		if isFree(x, z, 2) and abs(((a - 45 + 180) % 360) - 180) > 12 then tallKelp(g, at(x, z, yaw(), 0.2), rnd(10, 18), pick(KELP)) end
	end
	local CORALS = { C3(255, 110, 150), C3(255, 150, 70), C3(178, 112, 226), C3(250, 206, 70), C3(64, 202, 190) }
	for i = 1, 8 do
		local a = i / 8 * 360 + 12
		local x, z = polar(rnd(118, 128), a)
		if isFree(x, z, 3) and abs(((a - 45 + 180) % 360) - 180) > 12 then
			local c = pick(CORALS)
			local cf = at(x, z, yaw(), 0.2)
			if i % 3 == 0 then tableCoral(g, cf, 3, c, c:Lerp(C3(255, 255, 255), 0.4))
			elseif i % 3 == 1 then brainCoral(g, cf, 4.4, c)
			else coralTree(g, cf, 6, c, c:Lerp(C3(255, 255, 255), 0.35)) end
		end
	end
	for _ = 1, 8 do
		local r, a = rnd(114, 134), rnd(0, 360)
		local x, z = polar(r, a)
		if isFree(x, z, 3) and abs(((a - 45 + 180) % 360) - 180) > 12 then capRock(g, atSlope(x, z, yaw(), 0.4), rnd(3, 6), C3(214, 192, 158), nil, M.Limestone) end
	end
end

-- // 6) Light and life --------------------------------------------------------------------------------------
do
	local g = group("Ambience")
	for _, p in ipairs({ { 30, 40 }, { -40, -60 }, { 70, -30 } }) do
		lightShaft(g, at(p[1], p[2], 0, 0), 70, 14, C3(255, 238, 190), 0.96)
	end
	for _, p in ipairs({ { 10, 10 }, { -10, -9 }, { 126, -40 }, { -126, 40 } }) do
		emitter(g, at(p[1], p[2], 0, 0.4), "bubbles")
	end
	school(g, ORIGIN * CF(0, 22, 0), "Fish", 6, 3, C3(255, 200, 70), C3(255, 120, 60), 40, 6, 40, 0.45)
	school(g, ORIGIN * CF(-60, 18, 40), "Jelly", 3, 5, C3(150, 220, 240), C3(255, 255, 255), 24, 5, 24, 0.3)
end

print(string.format("[Abyssara] HubDressing v3: %d parts (%d neon, %.1f%%)", partCount, neonCount, neonCount / max(partCount, 1) * 100))
