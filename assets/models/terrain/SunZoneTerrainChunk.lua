--[[
	Abyssara - Deep Tide Tycoon
	Asset type: Zone terrain (Workspace.Terrain sculpt + landmark parts)
	Name: SunZoneTerrainChunk (v3 - smooth Terrain)

	IDENTITY: bright, sandy reef shallows. Warm sand and pale limestone ground, coral-pink sandstone
	reef walls, rolling dunes, seagrass meadows, a turquoise tide pool and one big landmark: a sunken
	pirate ship (tilted, boardable by a gangway) that every path leads to. Mood: sunny, safe, colourful.
	Lighting/fog/colour grading come from src/client/ZoneAtmosphere.client.lua (SunZone profile).

	WHAT THIS SCRIPT WRITES
		- Workspace.Terrain inside the zone region (x/z = ORIGIN +- (HALF + 4)): strata (limestone under
		  sand), a closed reef-wall bowl, dunes, a coral terrace, tide pool, seagrass beds and paths.
		  Re-running first wipes that region with an Air FillBlock, so it is idempotent.
		- Workspace.Assets.Terrain.SunZoneTerrainChunk (Model): hidden safety floor `ChunkBase`
		  (PrimaryPart, attribute Zone = "SunZone"), the pirate ship and the Sun Gate rock arch.
		- Everything else (corals, treasure, lanterns, light shafts ...) is SunZoneDressing.lua.

	GAMEPLAY AREAS (kept flat and empty): the landing spot at the chunk centre (r 13, TravelService
	raycasts straight down at ChunkBase.Position.X/Z), the three trails from it, the gangway foot.

	RUN: Studio Command Bar in edit mode. Order: this script, then world/SunZoneDressing.lua.
	Terrain colours are global per place; every terrain script sets the same palette block.
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(120, 0, 0) -- zone centre (matches WorldAmbienceConfig / ZoneAtmosphere)
local HALF = 50 -- half of the 100 x 100 chunk
local RANDOM_SEED = 3101
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

-- // 1) Region wipe + strata ---------------------------------------------------
clearRegion(HALF, HALF)
fillBlock(0, -20, 0, HALF * 2, 24, HALF * 2, M.Limestone) -- y -32 .. -8, shows as pale cliff layers
fillBlock(0, -4, 0, HALF * 2, 8, HALF * 2, M.Sand) -- y -8 .. 0, the walking surface

-- // 2) Reef-wall bowl (closed ring, taller at the back/east = background layer) ---
local function rimHeight(x, z)
	local base = 8 + 3 * sin(x * 0.19 + z * 0.13) + 2 * sin(z * 0.31)
	if x > 28 then base += (x - 28) * 0.5 end -- east cliff towers over the ship
	if x < -34 and abs(z) < 12 then base = 3 end -- low sill in front of the Sun Gate
	return base
end
for i = -5, 5 do
	local t = i * 9
	local r = 7 + abs(sin(t)) * 2
	local inset = HALF - r * 0.8 -- keep every fill inside the zone region
	for _, p in ipairs({ { t, -inset }, { t, inset }, { -inset, t }, { inset, t } }) do
		local h = rimHeight(p[1], p[2])
		hill(p[1], p[2], r, h, M.Sandstone)
		if h > 12 then hill(p[1] * 0.94, p[2] * 0.94, 5, h + 3, M.Limestone) end -- pale cap rocks
	end
end
for _, c in ipairs({ { -44, -44 }, { 44, -44 }, { -44, 44 } }) do
	hill(c[1] * 0.97, c[2] * 0.97, 8, 13, M.Sandstone)
end

-- // 3) Dunes (rolling midground) -----------------------------------------------
ridge(-36, -30, -20, -42, 10, 5, 11, 8, M.Sand)
ridge(-40, 12, -36, 38, 10, 7, 10, 5, M.Sand)
ridge(-6, 44, 12, 46, 7, 4, 7, 5, M.Sand)
ridge(36, -16, 43, 4, 9, 6, 9, 9, M.Sand)
hill(-22, -16, 9, 4, M.Sand) -- soft bump next to the Gate trail
hill(18, 2, 7, 3, M.Sand)
hill(-8, 22, 7, 3.5, M.Sand)

-- // 4) Coral terrace (raised plateau with a ramp, north) -------------------------
fillCyl(14, 1, -34, 4, 14, M.Limestone) -- top at y = 3
fillCyl(27, 1, -37, 4, 10, M.Limestone)
fillCyl(5, 1, -38, 4, 8, M.Limestone)
fillWedge(7, 1.5, -22, 6, 3, 8, M.Limestone, 180) -- ramp up to the terrace (tall edge to the north)
patch(14, -34, 11, M.Salt, 3)

-- // 5) Tide pool (carved basin with a pale salt rim, south-west) --------------------
patch(-24, 24, 11, M.Salt)
carveBall(-24, 24, 8, 2.4)

-- // 6) Seagrass meadows (LeafyGrass patches) ---------------------------------------
patch(-12, -30, 9, M.LeafyGrass)
patch(-30, -22, 6, M.LeafyGrass)
patch(36, -22, 8, M.LeafyGrass)
patch(-4, 36, 8, M.LeafyGrass)
patch(42, 30, 5, M.LeafyGrass)

-- // 7) Landing plaza + stone trails (kept flat, nothing is built on them) -----------
patch(0, 0, 12, M.Limestone)
patch(0, 0, 6, M.Salt)
trail({ { 0, 0 }, { 8, 6 }, { 14, 10 }, { 18.5, 13.5 } }, 6, M.Limestone) -- to the ship gangway
trail({ { 0, 0 }, { 4, -12 }, { 7, -20 } }, 6, M.Limestone) -- to the coral terrace ramp
trail({ { 0, 0 }, { -18, -1 }, { -36, 0 } }, 7, M.Limestone) -- to the Sun Gate
trail({ { 0, 0 }, { -10, 12 }, { -18, 22 } }, 6, M.Limestone) -- to the tide pool

-- // 8) Parts: safety floor, Sun Gate, pirate ship -------------------------------------
local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")
local previous = terrainFolder:FindFirstChild("SunZoneTerrainChunk")
if previous then previous:Destroy() end
local model = Instance.new("Model")
model.Name = "SunZoneTerrainChunk"
model.Parent = terrainFolder

-- Hidden floor far below the sand: nobody can fall out of the world, TravelService still has a part to read.
-- ChunkBase is TravelService's PrimaryPart: it casts from ChunkBase.Position + 60 studs straight down, so the
-- slab must sit between 58 studs below and 0 studs above the walking surface (y = -44 keeps the ray start 16 studs
-- above the flat landing plaza and the slab itself buried / below it).
setSolid(true)
local base = box(model, "ChunkBase", V3(HALF * 2, 2, HALF * 2), ORIGIN * CF(0, -44, 0), C3(226, 200, 176), M.Limestone)
base.Transparency = 1
base.CanQuery = true

local sandstone = C3(236, 168, 128)
-- Sun Gate: rock arch at the hub-facing (west) edge, frames the way back
do
	local gx = -41
	local cf = at(gx, 0, 0, 0.5)
	box(model, "GatePillarL", V3(3.6, 12, 4), cf * CF(0, 6, -6.5), sandstone, M.Sandstone)
	box(model, "GatePillarR", V3(3.6, 12, 4), cf * CF(0, 6, 6.5), sandstone, M.Sandstone)
	box(model, "GateLintel", V3(4.2, 3, 18), cf * CF(0, 13, 0), sandstone, M.Sandstone)
	blob(model, "GateFootL", V3(6, 3.5, 7), cf * CF(0, 1, -6.5), C3(226, 196, 160), M.Sandstone)
	blob(model, "GateFootR", V3(6, 3.5, 7), cf * CF(0, 1, 6.5), C3(226, 196, 160), M.Sandstone)
	blob(model, "GateKeystone", V3(4.6, 3.4, 5), cf * CF(0, 14.4, 0), C3(250, 226, 190), M.Limestone)
end

-- Pirate ship wreck (bow = +X in ship space). Sunk 2.4 studs, bow up, yawed towards the landing spot.
local S = at(24, 26, rad(10), 2.4) * ANG(0, 0, rad(5))
local function sp(x, y, z) return S * CF(x, y, z) end
local WOOD = C3(112, 78, 52)
local DARK = C3(78, 54, 38)
local PLANK = C3(168, 128, 88)
box(model, "ShipKeel", V3(30, 1.2, 6.5), sp(0, 0.6, 0), DARK, M.WoodPlanks)
for _, side in ipairs({ -1, 1 }) do
	box(model, "ShipSide", V3(26, 5.2, 0.9), sp(-2, 3.4, side * 4), WOOD, M.WoodPlanks)
	box(model, "ShipBow", V3(6.8, 5.2, 0.9), sp(14.75, 3.4, side * 2) * ANG(0, side * rad(36), 0), WOOD, M.WoodPlanks)
	for _, x in ipairs({ -6, 2, 9 }) do -- cannons poking out of the hull
		post(model, "Cannon", 1.1, 3.4, sp(x, 3.9, side * 4.3) * ANG(side * pi / 2, 0, 0), C3(44, 44, 54), M.Metal)
	end
end
box(model, "ShipStern", V3(0.9, 5.2, 8.2), sp(-14.5, 3.4, 0), WOOD, M.WoodPlanks)
box(model, "DeckFront", V3(11, 0.6, 8), sp(8.5, 5.8, 0), PLANK, M.WoodPlanks)
box(model, "DeckBack", V3(9, 0.6, 8), sp(-8, 5.8, 0), PLANK, M.WoodPlanks)
box(model, "CastleBlock", V3(7, 3.6, 8.6), sp(-11, 8, 0), WOOD, M.WoodPlanks)
box(model, "CastleRoof", V3(7.6, 0.5, 9.2), sp(-11, 10.1, 0), DARK, M.WoodPlanks)
for _, z in ipairs({ -2.6, 0, 2.6 }) do
	box(model, "CastleWindow", V3(0.3, 1.3, 1.6), sp(-14.6, 8.2, z), C3(34, 40, 50), M.Glass)
end
wedgePart(model, "Gangway", V3(4, 6, 9), sp(-3, 3, -8.5), C3(150, 112, 76), M.WoodPlanks) -- walk up to the deck
-- masts (leaning, snapped), yards and tattered sails
local function mast(x, len, lean)
	local cf = sp(x, 6, 0) * ANG(0, 0, rad(lean))
	post(model, "Mast", 0.9, len, cf * CF(0, len / 2, 0), C3(96, 68, 46), M.Wood)
	box(model, "MastSplinter", V3(0.7, 1.6, 0.5), cf * CF(0.1, len + 0.6, 0) * ANG(0, 0, rad(20)), C3(150, 110, 76), M.Wood)
	return cf
end
local main = mast(3, 25, -5)
post(model, "MainYard", 0.45, 13, main * CF(0, 18, 0) * ANG(pi / 2, 0, 0), C3(96, 68, 46), M.Wood)
box(model, "MainSail", V3(0.15, 8, 11.5), main * CF(0.2, 13.6, 0) * ANG(rad(6), 0, 0), C3(236, 226, 200), M.Fabric)
box(model, "SailRip", V3(0.16, 2.2, 3), main * CF(0.25, 11, 3.2), C3(60, 80, 96), M.Fabric)
local fore = mast(11, 17, 4)
post(model, "ForeYard", 0.4, 9, fore * CF(0, 12, 0) * ANG(pi / 2, 0, 0), C3(96, 68, 46), M.Wood)
box(model, "ForeSail", V3(0.15, 5.4, 7.4), fore * CF(0.2, 9, 0), C3(228, 214, 186), M.Fabric)
post(model, "Rigging", 0.22, 22, sp(7, 17, 0) * ANG(0, 0, rad(-66)), C3(70, 56, 44), M.Fabric) -- main mast to bow
post(model, "Bowsprit", 0.7, 9, sp(18.5, 7.3, 0) * ANG(0, 0, -(pi / 2 - rad(18))), C3(96, 68, 46), M.Wood)
-- wheel and the (non-glowing) skull flag
mk(model, "ShipWheel", V3(0.35, 3.2, 3.2), sp(-7.4, 7.9, 0), C3(120, 82, 54), M.Wood, Enum.PartType.Cylinder)
mk(model, "WheelHub", V3(0.5, 0.9, 0.9), sp(-7.4, 7.9, 0), C3(40, 40, 48), M.Metal, Enum.PartType.Cylinder)
local flag = fore * CF(0.3, 16, 1.9)
box(model, "SkullFlag", V3(0.15, 2.6, 3.8), flag, C3(30, 30, 36), M.Fabric)
ball(model, "SkullHead", 1.2, flag * CF(-0.15, 0.3, 0), C3(244, 240, 228), M.SmoothPlastic)
for _, z in ipairs({ -0.28, 0.28 }) do
	ball(model, "SkullEye", 0.3, flag * CF(-0.62, 0.45, z), C3(24, 24, 30), M.SmoothPlastic)
end
setSolid(false)

model.PrimaryPart = base
model:SetAttribute("Zone", "SunZone")
model:SetAttribute("Identity", "SunnyReefShallows")
print(string.format("[Abyssara] SunZoneTerrainChunk v3: %d terrain fills, %d parts (%d neon)", fillCount, partCount, neonCount))
