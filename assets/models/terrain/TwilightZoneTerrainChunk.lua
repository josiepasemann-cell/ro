--[[
	Abyssara - Deep Tide Tycoon
	Asset type: Zone terrain (Workspace.Terrain sculpt + landmark parts)
	Name: TwilightZoneTerrainChunk (v3 - smooth Terrain)

	IDENTITY: blue-violet dusk. Violet slate ground, indigo cliff walls, a winding kelp-forest canyon
	with a stone gate, a field of rock spires with a natural arch, and a sheer chasm whose far side
	drops into darkness (crossed by a stone bridge). Only a few bioluminescent accents (see the
	dressing). Lighting/fog/colour grading: src/client/ZoneAtmosphere.client.lua (TwilightZone).

	WHAT THIS SCRIPT WRITES
		- Workspace.Terrain inside the zone region (ORIGIN +- (HALF + 4)); wiped first -> idempotent.
		- Workspace.Assets.Terrain.TwilightZoneTerrainChunk: hidden safety floor `ChunkBase`
		  (PrimaryPart, attribute Zone = "TwilightZone"), the canyon gate and the spire arch.

	LAYOUT (local studs, x east / z south): landing plaza at 0,0; trail NW into the canyon corridor
	(walls z -14 / -40) towards the gate at x -30; trail E to the chasm bridge (chasm x 14..46,
	z 14..34, floor -20, a 32 degree ramp along its north side walks back out); spire field NE.

	GAMEPLAY AREAS (flat, empty): landing (r 12 + margin), all trails, the bridge, the ramp.
	RUN: Studio Command Bar, edit mode; then world/TwilightZoneDressing.lua.
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(-120, 0, 0)
local HALF = 50
local RANDOM_SEED = 3202
-- // -----------------------------------------------------------------------

-- // BEGIN SHARED TERRAIN HELPERS ------------------------------------------------
-- (Identical in every terrain/*.lua and hub/HubTerrain.lua on purpose: buildscripts are pasted one at a
-- time into the Studio Command Bar, so they cannot require each other. Edit one copy, re-copy to the rest.)
-- All coordinates passed to these helpers are LOCAL to ORIGIN (x/z = studs from the zone centre, y = 0 is
-- the flat walking surface). Terrain is only ever written inside this zone's region (see clearRegion).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Terrain = Workspace.Terrain
local M = Enum.Material
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local rad, pi, sin, cos, sqrt, abs, max, min = math.rad, math.pi, math.sin, math.cos, math.sqrt, math.abs, math.max, math.min
local C3 = Color3.fromRGB

-- Terrain material colours are global per place (Terrain:SetMaterialColor), so every zone owns its own
-- materials: Sun = Sand/Limestone/Salt/Sandstone/LeafyGrass/Ground, Twilight = Slate/Rock/Mud/Grass,
-- Midnight = Basalt/Asphalt/CrackedLava, Hadal = Glacier/Ice/Snow, Hub = Sand/Cobblestone/Pavement.
local PALETTE = {
	[M.Sand] = C3(236, 196, 120), [M.Limestone] = C3(232, 204, 172), [M.Salt] = C3(250, 242, 222),
	[M.Sandstone] = C3(236, 150, 112), [M.LeafyGrass] = C3(84, 168, 120), [M.Ground] = C3(206, 172, 120),
	[M.Slate] = C3(108, 94, 170), [M.Rock] = C3(100, 128, 190), [M.Mud] = C3(48, 40, 90), [M.Grass] = C3(36, 108, 116),
	[M.Basalt] = C3(36, 32, 40), [M.Asphalt] = C3(62, 52, 58), [M.CrackedLava] = C3(255, 120, 40),
	[M.Glacier] = C3(104, 168, 224), [M.Ice] = C3(166, 216, 244), [M.Snow] = C3(222, 238, 252),
	[M.Cobblestone] = C3(176, 150, 112), [M.Pavement] = C3(196, 176, 140),
}
for material, color in pairs(PALETTE) do
	Terrain:SetMaterialColor(material, color)
end

local fillCount = 0
local REGION = HALF + 4 -- this zone's terrain region is ORIGIN +- REGION; fills must never leave it
local function inside(what, x, z, rx, rz)
	if abs(x) + rx > REGION + 0.01 or abs(z) + rz > REGION + 0.01 then
		warn(string.format("[terrain] %s at (%.0f, %.0f) leaves the zone region (+-%d)", what, x, z, REGION))
	end
end
local function W(x, y, z)
	return ORIGIN:PointToWorldSpace(V3(x, y, z))
end
local function fillBall(x, y, z, r, mat)
	inside("FillBall", x, z, r, r)
	Terrain:FillBall(W(x, y, z), r, mat)
	fillCount += 1
end
local function fillBlock(x, y, z, sx, sy, sz, mat, yawDeg)
	local c, s = abs(cos(rad(yawDeg or 0))), abs(sin(rad(yawDeg or 0)))
	inside("FillBlock", x, z, c * sx / 2 + s * sz / 2, s * sx / 2 + c * sz / 2)
	Terrain:FillBlock(ORIGIN * CF(x, y, z) * ANG(0, rad(yawDeg or 0), 0), V3(sx, sy, sz), mat)
	fillCount += 1
end
local function fillCyl(x, y, z, h, r, mat)
	inside("FillCylinder", x, z, r, r)
	Terrain:FillCylinder(ORIGIN * CF(x, y, z), h, r, mat)
	fillCount += 1
end
-- Wedge: tall side at local +Z, slope falls towards -Z (same as a WedgePart). yawDeg turns it.
local function fillWedge(x, y, z, sx, sy, sz, mat, yawDeg)
	local c, s = abs(cos(rad(yawDeg or 0))), abs(sin(rad(yawDeg or 0)))
	inside("FillWedge", x, z, c * sx / 2 + s * sz / 2, s * sx / 2 + c * sz / 2)
	Terrain:FillWedge(ORIGIN * CF(x, y, z) * ANG(0, rad(yawDeg or 0), 0), V3(sx, sy, sz), mat)
	fillCount += 1
end
-- Rounded mound whose top reaches height h above the surface (y = 0).
local function hill(x, z, r, h, mat)
	fillBall(x, h - r, z, r, mat)
end
-- Ridge / dune line: a chain of mounds from (x1,z1) to (x2,z2); radius and height are interpolated.
local function ridge(x1, z1, x2, z2, r1, h1, r2, h2, mat)
	local len = sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local n = max(1, math.ceil(len / (min(r1, r2) * 0.7)))
	for i = 0, n do
		local t = i / n
		hill(x1 + (x2 - x1) * t, z1 + (z2 - z1) * t, r1 + (r2 - r1) * t, h1 + (h2 - h1) * t, mat)
	end
end
-- Flat disc that only repaints the top 4 studs (paths, plazas, algae beds).
local function patch(x, z, r, mat, topY)
	fillCyl(x, (topY or 0) - 2, z, 4, r, mat)
end
-- Polyline path of overlapping patches (pts = { {x,z}, ... }).
local function trail(pts, width, mat, topY)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = max(1, math.ceil(len / (width * 0.45)))
		for k = 0, n do
			local t = k / n
			patch(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, width / 2, mat, topY)
		end
	end
end
-- Carve helpers (Air). Depth is measured downwards from y = 0.
local function carveBall(x, z, r, depth)
	fillBall(x, r - depth, z, r, M.Air)
end
local function segYaw(x1, z1, x2, z2)
	return math.deg(math.atan2(-(z2 - z1), x2 - x1))
end
-- Straight canyon / trench / river bed between two points, width w, floor at -depth.
local function carveTrench(x1, z1, x2, z2, w, depth, overhead)
	local len = sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local top = overhead or 40
	fillBlock((x1 + x2) / 2, (top - depth) / 2, (z1 + z2) / 2, len, depth + top, w, M.Air, segYaw(x1, z1, x2, z2))
end
-- Vertical rock wall (cliff / canyon wall) between two points, thickness w, height h.
local function cliffWall(x1, z1, x2, z2, w, h, mat)
	local len = sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	fillBlock((x1 + x2) / 2, h / 2 - 2, (z1 + z2) / 2, len, h + 4, w, mat, segYaw(x1, z1, x2, z2))
end

-- Lava river: a channel carved 3 studs below the surface and filled with CrackedLava (the only glowing ground).
local function river(pts, w, depth)
	depth = depth or 3
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local ext = w * 0.5
		local dx, dz = (b[1] - a[1]) / len, (b[2] - a[2]) / len
		local x1, z1, x2, z2 = a[1] - dx * ext * (i > 1 and 1 or 0), a[2] - dz * ext * (i > 1 and 1 or 0), b[1] + dx * ext, b[2] + dz * ext
		carveTrench(x1, z1, x2, z2, w, depth)
		fillBlock((x1 + x2) / 2, -depth - 2, (z1 + z2) / 2, sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2), 4, w, M.CrackedLava, segYaw(x1, z1, x2, z2))
	end
end
-- Flat-topped bridge slab across a channel (top at y = 0).
local function bridge(x, z, len, w, yawDeg, mat)
	fillBlock(x, -2, z, len, 4, w, mat, yawDeg)
end
-- Volcanic cone: smooth dome with a lava-filled crater.
local function volcano(x, z, R, h, craterR, mat)
	hill(x, z, R, h, mat)
	fillBall(x, h + craterR * 0.35, z, craterR, M.Air)
	fillBall(x, h - craterR * 0.55, z, craterR * 0.75, M.CrackedLava)
end
local function clearRegion(halfX, halfZ)
	-- idempotent re-runs: wipe this zone's terrain (and only this zone's) before sculpting again
	Terrain:FillBlock(ORIGIN * CF(0, 0, 0), V3(halfX * 2 + 8, 200, halfZ * 2 + 8), M.Air)
end

-- Ground height below local (x, z): raycast against Workspace.Terrain only. Falls back to 0.
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
-- // END SHARED TERRAIN HELPERS --------------------------------------------------
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

-- // 1) Wipe + strata: deep indigo mud, violet slate surface -----------------------------
clearRegion(HALF, HALF)
fillBlock(0, -36, 0, HALF * 2, 56, HALF * 2, M.Mud) -- y -64 .. -8
fillBlock(0, -4, 0, HALF * 2, 8, HALF * 2, M.Slate) -- y -8 .. 0 walking surface

-- // 2) Perimeter: tall indigo wall with cap rocks and spires ------------------------------
local function rimHeight(x, z)
	return 9 + 3 * sin(x * 0.17) + 3 * sin(z * 0.23 + 1) + (z < -30 and 4 or 0)
end
for i = -5, 5 do
	local t = i * 9
	local r = min(7 + abs(sin(t * 1.3)) * 2.5, REGION - abs(t) - 0.1)
	local inset = HALF - r * 0.8
	for _, p in ipairs({ { t, -inset }, { t, inset }, { -inset, t }, { inset, t } }) do
		local h = rimHeight(p[1], p[2])
		hill(p[1], p[2], r, h, M.Mud)
		hill(p[1] * 0.95, p[2] * 0.95, r * 0.55, h + 3, M.Slate)
	end
end
-- spires: vertical pillars with rounded tops (silhouette)
local function spire(x, z, r, h, mat)
	fillCyl(x, (h - 6) / 2, z, h + 6, r, mat)
	fillBall(x, h - r * 0.3, z, r, mat)
end
for _, s in ipairs({ { -44, 40, 4, 26 }, { 44, -42, 4, 28 }, { 40, 44, 5, 24 }, { -46, -46, 5, 30 }, { 0, -46, 4, 26 }, { 0, 46, 4, 22 } }) do
	spire(s[1], s[2], s[3], s[4], M.Mud)
end

-- // 3) Kelp canyon: two long walls with a corridor between them ----------------------------
cliffWall(-46, -14, -8, -13, 6, 19, M.Mud)
cliffWall(-46, -40, 0, -42, 6, 24, M.Mud)
for _, x in ipairs({ -40, -28, -18 }) do -- cap rocks on the south wall, ledges on the north wall
	hill(x, -13.5, 5, 22, M.Slate)
end
for _, x in ipairs({ -42, -30, -18, -6 }) do
	hill(x, -41, 5.5, 28, M.Slate)
end
hill(-16, -15, 6, 13, M.Mud) -- soft end of the south wall (clear of the landing and the trail)
hill(2, -40, 7, 17, M.Mud)

-- // 4) Spire field + natural arch (north-east) ------------------------------------------------
spire(20, -30, 3.2, 22, M.Mud)
spire(34, -30, 3.2, 20, M.Mud)
spire(14, -42, 3, 16, M.Mud)
spire(40, -18, 3, 17, M.Mud)
spire(27, -14, 2.4, 11, M.Mud)
hill(26, -40, 9, 7, M.Slate)

-- // 5) Chasm with a switchback ramp and a stone bridge --------------------------------------------
carveTrench(14, 24, 46, 24, 20, 20) -- x 14..46, z 14..34, floor at y = -20
fillWedge(30, -10, 18, 8, 20, 32, M.Rock, -90) -- 32 degree ramp along the north side, high end at x = 14
fillBlock(30, -2, 24, 8, 4, 26, M.Slate) -- bridge, top at y = 0
patch(28, 28, 5, M.Grass, -20) -- floor patches
patch(40, 26, 4, M.Grass, -20)
hill(34, 27, 3, 2, M.Rock) -- rocks on the chasm floor
hill(20, 30, 3.5, 3, M.Rock)

-- // 6) Ground patches: kelp beds (Grass) and path stone (Rock) ---------------------------------------
patch(-24, 8, 10, M.Grass)
patch(-12, 28, 9, M.Grass)
patch(-36, 26, 8, M.Grass)
patch(10, -26, 7, M.Grass)
patch(-30, -28, 6, M.Grass) -- inside the canyon
patch(40, 40, 7, M.Grass)
hill(-30, 6, 6, 4, M.Slate)
hill(-38, 20, 8, 5, M.Slate)
hill(-18, 38, 8, 4, M.Slate)
hill(20, -4, 5, 3, M.Slate)
hill(14, 40, 6, 3.5, M.Slate)

patch(0, 0, 12, M.Rock) -- landing plaza
patch(0, 0, 5, M.Slate)
trail({ { 0, 0 }, { 1, -12 }, { -4, -24 }, { -16, -28 }, { -26, -28 }, { -30, -28 } }, 7, M.Rock) -- into the canyon, to the gate
trail({ { 0, 0 }, { 10, 6 }, { 22, 10 }, { 30, 12 } }, 7, M.Rock) -- to the chasm bridge
trail({ { 30, 36 }, { 30, 42 }, { 38, 42 } }, 7, M.Rock) -- far side: lookout
patch(38, 42, 8, M.Rock)

-- // 7) Parts: safety floor, canyon gate, spire arch ------------------------------------------------------
local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")
local previous = terrainFolder:FindFirstChild("TwilightZoneTerrainChunk")
if previous then previous:Destroy() end
local model = Instance.new("Model")
model.Name = "TwilightZoneTerrainChunk"
model.Parent = terrainFolder

-- ChunkBase is TravelService's PrimaryPart: it casts from ChunkBase.Position + 60 studs straight down, so the
-- slab must sit between 58 studs below and 0 studs above the walking surface (y = -44 keeps the ray start 16 studs
-- above the flat landing plaza and the slab itself buried / below it).
setSolid(true)
local base = box(model, "ChunkBase", V3(HALF * 2, 2, HALF * 2), ORIGIN * CF(0, -44, 0), C3(48, 40, 90), M.Slate)
base.Transparency = 1
base.CanQuery = true

local stone = C3(84, 88, 150)
-- Twilight Gate: stone arch across the canyon corridor (faces along local X)
rockArch(model, at(-30, -27, pi / 2, 0.5), 15, 14, 5, stone, M.Slate)
-- Spire arch: rock bridge between two spires (spires at 20,-30 / 34,-30, height 22 / 20)
do
	local cf = ORIGIN * CF(27, 17, -30) * ANG(0, pi / 2 * 0, 0) -- spans along X
	rockArch(model, cf, 5, 4, 4.6, stone, M.Slate)
end
setSolid(false)

model.PrimaryPart = base
model:SetAttribute("Zone", "TwilightZone")
model:SetAttribute("Identity", "VioletKelpCanyon")
print(string.format("[Abyssara] TwilightZoneTerrainChunk v3: %d terrain fills, %d parts (%d neon)", fillCount, partCount, neonCount))
