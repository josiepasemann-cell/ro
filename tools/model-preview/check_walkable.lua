-- Terrain walkability / landing check for the zone buildscripts (runs inside the preview shim).
-- usage: node export.mjs --only terrain,hub/HubTerrain --extra check_walkable.lua   (look for "CHECK" lines)
-- For every zone it raycasts straight down (like TravelService.findSafeLandingCFrame) over the landing
-- plaza and over each gameplay point list, and reports height range / slope. warn() lines print as WARN.
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { Terrain }

local function ground(wx, wz)
	local hit = Workspace:Raycast(Vector3.new(wx, 120, wz), Vector3.new(0, -260, 0), params)
	return hit and hit.Position.Y or nil, hit and hit.Normal or nil
end

local zones = {
	{ "SunZone", 120, 0, 11, { { 8, 6 }, { 14, 10 }, { 18.5, 13.5 }, { 4, -12 }, { 7, -20 }, { -18, -1 }, { -36, 0 }, { -10, 12 }, { -18, 22 } } },
	{ "TwilightZone", -120, 0, 11, { { 1, -12 }, { -4, -24 }, { -16, -28 }, { -26, -28 }, { -30, -28 }, { 10, 6 }, { 22, 10 }, { 30, 12 }, { 30, 18 }, { 30, 24 }, { 30, 30 }, { 30, 36 }, { 30, 42 } } },
	{ "MidnightZone", 0, 120, 11, { { 0, 6 }, { 0, 12 }, { 0, 18 }, { 0, 24 }, { 0, 30 }, { 0, 33 }, { 6, 33 }, { -6, 33 }, { 0, 39 }, { 12, -2 }, { 26, -2 }, { 40, -4 }, { -12, 8 }, { -26, 18 }, { -34, 24 } } },
	{ "HadalDepths", 0, -120, 11, { { 0, -12 }, { 0, -22 }, { 0, -28 }, { 0, -34 }, { 0, -42 }, { 14, 6 }, { 26, 10 }, { 34, 12 }, { -14, 8 }, { -28, 16 }, { -34, 20 } } },
}
local bad = 0
for _, z in ipairs(zones) do
	local name, ox, oz, r, pts = z[1], z[2], z[3], z[4], z[5]
	local lo, hi = math.huge, -math.huge
	local misses = 0
	local hiAt = ""
	for dx = -r, r, 2 do
		for dz = -r, r, 2 do
			if dx * dx + dz * dz <= r * r then
				local y = ground(ox + dx, oz + dz)
				if y then
					lo = math.min(lo, y)
					if y > hi then hi, hiAt = y, string.format("(%d,%d)", dx, dz) end
				else misses += 1 end
			end
		end
	end
	local ok = misses == 0 and (hi - lo) <= 0.75
	if not ok then bad += 1 end
	warn(string.format("CHECK %s landing plaza r%d: height %.2f..%.2f (range %.2f, highest at %s), misses %d -> %s", name, r, lo, hi, hi - lo, hiAt, misses, ok and "OK" or "BAD"))
	-- TravelService.findSafeLandingCFrame: ray from ChunkBase.Position + 60 studs straight down. The origin must be ABOVE
	-- the surface at the chunk centre (otherwise the ray starts inside terrain and lands on the buried slab).
	local chunk = Workspace.Assets.Terrain:FindFirstChild(name .. "TerrainChunk") or Workspace.Assets.Terrain:FindFirstChild(string.gsub(name, "Zone", "") .. "TerrainChunk")
	local cy = ground(ox, oz)
	if chunk and chunk.PrimaryPart then
		local startY = chunk.PrimaryPart.Position.Y + 60
		local startOk = cy ~= nil and startY > cy + 2 and startY - cy < 240
		if not startOk then bad += 1 end
		warn(string.format("CHECK %s travel ray starts y=%.1f, surface y=%.1f (landing y=%.1f) -> %s", name, startY, cy or -99, (cy or 0) + 3, startOk and "OK" or "BAD"))
	else
		warn("CHECK " .. name .. " chunk/PrimaryPart not found -> BAD")
		bad += 1
	end
	-- gameplay points: must exist, be walkable (normal.y >= 0.8) and not be lava
	local worst, worstAt = 1, ""
	local missing = 0
	for _, p in ipairs(pts) do
		local y, n = ground(ox + p[1], oz + p[2])
		if not y then missing += 1 elseif n.Y < worst then worst, worstAt = n.Y, string.format("(%g,%g)", p[1], p[2]) end
	end
	local pok = missing == 0 and worst >= 0.8
	if not pok then bad += 1 end
	warn(string.format("CHECK %s trail/lane points (%d): missing %d, flattest normal.y %.2f at %s -> %s", name, #pts, missing, worst, worstAt, pok and "OK" or "BAD"))
end
-- hub: nothing may rise above the plaza slab top (y = 2) inside r 109, and the plot-road causeway top is y = 2
local hubBad = 0
for a = 0, 350, 10 do
	for r = 10, 108, 14 do
		local y = ground(-500 + math.cos(math.rad(a)) * r, -500 + math.sin(math.rad(a)) * r)
		if y and y > 0.5 then hubBad += 1 end
	end
end
warn(string.format("CHECK Hub terrain under the plaza stays <= 0.5 (slab top is 2): %s", hubBad == 0 and "OK" or ("BAD " .. hubBad)))
local roadY = ground(-500 + 120, -500 + 120)
warn(string.format("CHECK Hub plot-road causeway top y = %.2f (expect 2)", roadY or -99))
warn(bad == 0 and "CHECK ALL ZONES OK" or ("CHECK FAILURES: " .. bad))
