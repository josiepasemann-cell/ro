--[[
	Abyssara - Deep Tide Tycoon
	Asset type: Hub terrain (Workspace.Terrain sculpt)
	Name: HubTerrain (v1 - new)

	IDENTITY: the cozy sandy harbour around the Tidal Market plaza. Warm sand seabed under and around
	the round plaza (TidalMarketHub.HubBase, r 110, top y = 2), a stepped beach ring, sandstone and
	limestone dunes as a backdrop wall (gap along the plot road), and a sand causeway for the plot road
	that runs diagonally (+X +Z) out to the PlotGate.

	TERRAIN SAFETY: nothing here covers a named hub part. Under the plaza the terrain stops at y = 0
	(the plaza slab occupies y -2 .. 2), the beach ring tops out at y = 2 (flush with the plaza top) only
	OUTSIDE r 110, and the plot-road causeway has its top at y = 2 like the road dashes.
	Idempotent: the whole hub region (ORIGIN +- 174) is wiped with an Air FillBlock first.

	RUN: Studio Command Bar, edit mode. Order: this script, hub/TidalMarketHub.lua, world/HubDressing.lua.
]]

-- // Configuration ---------------------------------------------------------
local ORIGIN = CFrame.new(-500, 0, -500) -- must match TidalMarketHub.lua
local HALF = 170
local RANDOM_SEED = 9101
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

clearRegion(HALF, HALF)

-- strata: limestone seabed with a sand skin, wider than the plaza
fillCyl(0, -20, 0, 36, 158, M.Limestone) -- y -38 .. -2
fillCyl(0, -2, 0, 4, 158, M.Sand) -- y -4 .. 0 (the plaza slab sits on top of this)
-- beach ring around the plaza: flush with the plaza top (y = 2) at r 110..122, then one step lower
fillCyl(0, 0, 0, 4, 130, M.Sand) -- top y = 2
fillCyl(0, -1, 0, 2, 142, M.Sand) -- top y = 0 (a 2 stud step down, walkable)
fillCyl(0, 4, 0, 8, 109.5, M.Air) -- under the plaza slab (r 110) the terrain stays at y = 0, no coplanar surfaces
for i = 0, 35 do -- Limestone rim stones between plaza and beach
	local a = i / 36 * 2 * pi
	if not (abs(((a - pi / 4 + pi) % (2 * pi)) - pi) < 0.2) then -- leave the plot road open
		hill(cos(a) * 124, sin(a) * 124, 5, 3.2, M.Limestone)
	end
end

-- dune wall / reef backdrop (r 138 .. 160), lower on the Sun/Twilight/Midnight/Hadal axes so the portals stay readable
for i = 0, 29 do
	local a = i / 30 * 2 * pi
	local roadGap = abs(((a - pi / 4 + pi) % (2 * pi)) - pi) < 0.22
	if not roadGap then
		local h = 8 + 5 * sin(a * 5) + 3 * sin(a * 11 + 1)
		local r = 11 + abs(sin(a * 7)) * 3
		local R = 146
		hill(cos(a) * R, sin(a) * R, r, h, M.Sandstone)
		if h > 12 then hill(cos(a) * (R - 3), sin(a) * (R - 3), 6, h + 4, M.Limestone) end
	end
end
-- far sandstone cliffs behind the dunes
for i = 0, 17 do
	local a = i / 18 * 2 * pi + 0.1
	local roadGap = abs(((a - pi / 4 + pi) % (2 * pi)) - pi) < 0.3
	if not roadGap then
		hill(cos(a) * 158, sin(a) * 158, 9, 18 + 6 * sin(a * 3), M.Sandstone)
	end
end

-- seagrass beds on the beach (LeafyGrass patches)
for _, p in ipairs({ { -118, 40 }, { 40, -118 }, { -60, 108 }, { 108, -70 }, { 90, 100 }, { -110, -60 } }) do
	patch(p[1], p[2], 8, M.LeafyGrass, 2)
end
-- sand patches and shallow dunes outside the plaza
hill(-130, -20, 7, 3, M.Sand)
hill(30, 128, 7, 3, M.Sand)
hill(120, 30, 7, 3, M.Sand)

-- plot road causeway: diagonal sand strip, top y = 2 (matches the visual road dashes in TidalMarketHub)
fillBlock(120, -2, 120, 130, 8, 16, M.Sand, -45)
fillCyl(162, -2, 162, 8, 10, M.Sand) -- landing pad around the PlotGate

print(string.format("[Abyssara] HubTerrain v1: %d terrain fills", fillCount))
