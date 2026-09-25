--!nocheck
--[[
	Minimal Roblox API shim so the Luau buildscripts in assets/models/** can run
	outside Roblox Studio. Only geometry-relevant behaviour is modelled; everything
	else is stored as plain properties or stubbed.

	CSG approximation:
	  UnionAsync / SubtractAsync / IntersectAsync do not compute meshes. They return
	  a UnionOperation (or IntersectOperation) that remembers its operands (copies of
	  the input parts, in the result's local space). The exporter writes that tree to
	  JSON and the three.js renderer resolves it per pixel (discarding fragments
	  inside cutters / outside intersect operands and drawing cutter walls inside the
	  base). Colour/material set on the result after the operation override the
	  operand colours (UsePartColor-style), which matches what the scripts intend.
]]

local CURRENT_SCRIPT = "?"

local rawtypeof = typeof
local function typeOf(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return rawtypeof(v)
end

-------------------------------------------------------------------------------
-- Vector3
-------------------------------------------------------------------------------
local Vector3 = {}
local V3mt = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3mt)
end
Vector3.new = function(x, y, z) return v3(x, y, z) end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
Vector3.FromNormalId = function() return v3(0, 1, 0) end
local V3methods = {}
function V3methods.Dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function V3methods.Cross(a, b)
	return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
function V3methods.Lerp(a, b, t) return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t) end
function V3methods.Abs(a) return v3(math.abs(a.x), math.abs(a.y), math.abs(a.z)) end
function V3methods.Min(a, b) return v3(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)) end
function V3methods.Max(a, b) return v3(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z)) end
function V3methods.FuzzyEq(a, b, eps) eps = eps or 1e-5; return (a - b).Magnitude <= eps end
function V3methods.Angle(a, b)
	local d = V3methods.Dot(a, b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
function V3methods.Floor(a) return v3(math.floor(a.x), math.floor(a.y), math.floor(a.z)) end
function V3methods.Ceil(a) return v3(math.ceil(a.x), math.ceil(a.y), math.ceil(a.z)) end
V3mt.__index = function(v, k)
	if k == "X" then return v.x elseif k == "Y" then return v.y elseif k == "Z" then return v.z end
	if k == "Magnitude" then return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
	if k == "Unit" then
		local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end
		return v3(v.x / m, v.y / m, v.z / m)
	end
	return V3methods[k]
end
V3mt.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
V3mt.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.x, a * b.y, a * b.z) end
	if type(b) == "number" then return v3(a.x * b, a.y * b, a.z * b) end
	return v3(a.x * b.x, a.y * b.y, a.z * b.z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.x / b, a.y / b, a.z / b) end
	if type(a) == "number" then return v3(a / b.x, a / b.y, a / b.z) end
	return v3(a.x / b.x, a.y / b.y, a.z / b.z)
end
V3mt.__idiv = function(a, b) local r = V3mt.__div(a, b); return v3(math.floor(r.x), math.floor(r.y), math.floor(r.z)) end
V3mt.__unm = function(a) return v3(-a.x, -a.y, -a.z) end
V3mt.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
V3mt.__tostring = function(a) return string.format("%g, %g, %g", a.x, a.y, a.z) end

-- Vector2 (UI only)
local Vector2 = {}
local V2mt = { __type = "Vector2" }
V2mt.__index = function(v, k) if k == "X" then return v.x elseif k == "Y" then return v.y elseif k == "Magnitude" then return math.sqrt(v.x*v.x+v.y*v.y) end end
V2mt.__add = function(a, b) return Vector2.new(a.x + b.x, a.y + b.y) end
V2mt.__sub = function(a, b) return Vector2.new(a.x - b.x, a.y - b.y) end
V2mt.__mul = function(a, b) if type(a) == "number" then return Vector2.new(a*b.x, a*b.y) end if type(b) == "number" then return Vector2.new(a.x*b, a.y*b) end return Vector2.new(a.x*b.x, a.y*b.y) end
Vector2.new = function(x, y) return setmetatable({ x = x or 0, y = y or 0 }, V2mt) end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)

-------------------------------------------------------------------------------
-- CFrame  (p = position, m = 3x3 row-major rotation: m[1..9] = R00 R01 R02 R10 ...)
-------------------------------------------------------------------------------
local CFrame = {}
local CFmt = { __type = "CFrame" }
local function cf(px, py, pz, m)
	return setmetatable({ px = px, py = py, pz = pz, m = m }, CFmt)
end
local IDM = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function matmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotX(a) local c, s = math.cos(a), math.sin(a); return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function rotY(a) local c, s = math.cos(a), math.sin(a); return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rotZ(a) local c, s = math.cos(a), math.sin(a); return { c, -s, 0, s, c, 0, 0, 0, 1 } end
local function fromColumns(pos, r, u, b)
	return cf(pos.x, pos.y, pos.z, { r.x, u.x, b.x, r.y, u.y, b.y, r.z, u.z, b.z })
end
local function lookAt(pos, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - pos)
	if look.Magnitude < 1e-9 then return cf(pos.x, pos.y, pos.z, table.clone(IDM)) end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then right = look:Cross(v3(1, 0, 0)) end
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	return fromColumns(pos, right, up2, -look)
end
function CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then return cf(0, 0, 0, table.clone(IDM)) end
	if n == 1 then return cf(a[1].x, a[1].y, a[1].z, table.clone(IDM)) end
	if n == 2 then return lookAt(a[1], a[2]) end
	if n == 3 then return cf(a[1], a[2], a[3], table.clone(IDM)) end
	if n == 7 then
		-- quaternion x,y,z,qx,qy,qz,qw
		local x, y, z, w = a[4], a[5], a[6], a[7]
		local l = math.sqrt(x * x + y * y + z * z + w * w)
		x, y, z, w = x / l, y / l, z / l, w / l
		return cf(a[1], a[2], a[3], {
			1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
			2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
			2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
		})
	end
	if n == 12 then
		return cf(a[1], a[2], a[3], { a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] })
	end
	error("CFrame.new: unsupported arg count " .. n)
end
function CFrame.Angles(rx, ry, rz)
	return cf(0, 0, 0, matmul(matmul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return cf(0, 0, 0, matmul(matmul(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz) return CFrame.Angles(rx, ry, rz) end
function CFrame.fromAxisAngle(axis, ang)
	local u = axis.Unit
	local c, s, t = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
	local x, y, z = u.x, u.y, u.z
	return cf(0, 0, 0, {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	})
end
function CFrame.lookAt(pos, target, up) return lookAt(pos, target, up) end
function CFrame.lookAlong(pos, dir, up) return lookAt(pos, pos + dir, up) end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return fromColumns(pos, vx, vy, vz)
end
CFrame.identity = cf(0, 0, 0, table.clone(IDM))

local function cfMulV(c, v)
	local m = c.m
	return v3(m[1] * v.x + m[2] * v.y + m[3] * v.z + c.px, m[4] * v.x + m[5] * v.y + m[6] * v.z + c.py, m[7] * v.x + m[8] * v.y + m[9] * v.z + c.pz)
end
local function cfRotV(c, v)
	local m = c.m
	return v3(m[1] * v.x + m[2] * v.y + m[3] * v.z, m[4] * v.x + m[5] * v.y + m[6] * v.z, m[7] * v.x + m[8] * v.y + m[9] * v.z)
end
local function cfInverse(c)
	local m = c.m
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	local p = v3(-c.px, -c.py, -c.pz)
	return cf(t[1] * p.x + t[2] * p.y + t[3] * p.z, t[4] * p.x + t[5] * p.y + t[6] * p.z, t[7] * p.x + t[8] * p.y + t[9] * p.z, t)
end
local function cfMul(a, b)
	local p = cfMulV(a, v3(b.px, b.py, b.pz))
	return cf(p.x, p.y, p.z, matmul(a.m, b.m))
end
local CFmethods = {}
function CFmethods.Inverse(c) return cfInverse(c) end
function CFmethods.ToWorldSpace(c, o) return cfMul(c, o) end
function CFmethods.ToObjectSpace(c, o) return cfMul(cfInverse(c), o) end
function CFmethods.PointToWorldSpace(c, v) return cfMulV(c, v) end
function CFmethods.PointToObjectSpace(c, v) return cfMulV(cfInverse(c), v) end
function CFmethods.VectorToWorldSpace(c, v) return cfRotV(c, v) end
function CFmethods.VectorToObjectSpace(c, v) return cfRotV(cfInverse(c), v) end
function CFmethods.GetComponents(c)
	local m = c.m
	return c.px, c.py, c.pz, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.Lerp(a, b, t)
	-- position lerp + naive matrix lerp re-orthonormalised
	local p = v3(a.px, a.py, a.pz):Lerp(v3(b.px, b.py, b.pz), t)
	local ra, rb = a.m, b.m
	local r = {}
	for i = 1, 9 do r[i] = ra[i] + (rb[i] - ra[i]) * t end
	local right = v3(r[1], r[4], r[7]).Unit
	local up = v3(r[2], r[5], r[8])
	local back = right:Cross(up).Unit
	up = back:Cross(right).Unit
	return fromColumns(p, right, up, back)
end
function CFmethods.ToEulerAnglesXYZ(c)
	local m = c.m
	local ry = math.asin(math.clamp(m[3], -1, 1))
	local rx = math.atan2(-m[6], m[9])
	local rz = math.atan2(-m[2], m[1])
	return rx, ry, rz
end
CFmethods.ToEulerAngles = CFmethods.ToEulerAnglesXYZ
function CFmethods.ToEulerAnglesYXZ(c)
	local m = c.m
	local rx = math.asin(math.clamp(-m[6], -1, 1))
	local ry = math.atan2(m[3], m[9])
	local rz = math.atan2(m[4], m[5])
	return rx, ry, rz
end
CFmethods.ToOrientation = CFmethods.ToEulerAnglesYXZ
function CFmethods.ToAxisAngle(c)
	local m = c.m
	local ang = math.acos(math.clamp((m[1] + m[5] + m[9] - 1) / 2, -1, 1))
	local ax = v3(m[8] - m[6], m[3] - m[7], m[4] - m[2])
	if ax.Magnitude < 1e-9 then return v3(1, 0, 0), 0 end
	return ax.Unit, ang
end
function CFmethods.Orthonormalize(c) return c end
function CFmethods.FuzzyEq(a, b) return (v3(a.px, a.py, a.pz) - v3(b.px, b.py, b.pz)).Magnitude < 1e-5 end
CFmt.__index = function(c, k)
	local m = c.m
	if k == "Position" or k == "p" then return v3(c.px, c.py, c.pz) end
	if k == "X" then return c.px elseif k == "Y" then return c.py elseif k == "Z" then return c.pz end
	if k == "LookVector" or k == "lookVector" then return v3(-m[3], -m[6], -m[9]) end
	if k == "RightVector" or k == "rightVector" then return v3(m[1], m[4], m[7]) end
	if k == "UpVector" or k == "upVector" then return v3(m[2], m[5], m[8]) end
	if k == "XVector" then return v3(m[1], m[4], m[7]) end
	if k == "YVector" then return v3(m[2], m[5], m[8]) end
	if k == "ZVector" then return v3(m[3], m[6], m[9]) end
	if k == "Rotation" then return cf(0, 0, 0, table.clone(m)) end
	return CFmethods[k]
end
CFmt.__mul = function(a, b)
	local tb = typeOf(b)
	if tb == "CFrame" then return cfMul(a, b) end
	if tb == "Vector3" then return cfMulV(a, b) end
	error("CFrame * " .. tb)
end
CFmt.__add = function(a, b) return cf(a.px + b.x, a.py + b.y, a.pz + b.z, table.clone(a.m)) end
CFmt.__sub = function(a, b) return cf(a.px - b.x, a.py - b.y, a.pz - b.z, table.clone(a.m)) end
CFmt.__eq = function(a, b)
	if a.px ~= b.px or a.py ~= b.py or a.pz ~= b.pz then return false end
	for i = 1, 9 do if a.m[i] ~= b.m[i] then return false end end
	return true
end
CFmt.__tostring = function(c) return string.format("%g, %g, %g, ...", c.px, c.py, c.pz) end

-------------------------------------------------------------------------------
-- Color3 / BrickColor
-------------------------------------------------------------------------------
local Color3 = {}
local C3mt = { __type = "Color3" }
local function c3(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end
Color3.new = function(r, g, b) return c3(r, g, b) end
Color3.fromRGB = function(r, g, b) return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
Color3.fromHSV = function(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return c3(v, t, p) elseif i == 1 then return c3(q, v, p) elseif i == 2 then return c3(p, v, t)
	elseif i == 3 then return c3(p, q, v) elseif i == 4 then return c3(t, p, v) else return c3(v, p, q) end
end
Color3.fromHex = function(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
Color3.toHSV = function(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, mx
	local d = mx - mn
	if mx > 0 then s = d / mx end
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
		h = h / 6
	end
	return h, s, v
end
C3mt.__index = function(c, k)
	if k == "r" then return c.R elseif k == "g" then return c.G elseif k == "b" then return c.B end
	if k == "Lerp" then return function(a, b, t) return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
	if k == "ToHSV" then return Color3.toHSV end
	if k == "ToHex" then return function(a) return string.format("%02X%02X%02X", math.floor(a.R * 255 + .5), math.floor(a.G * 255 + .5), math.floor(a.B * 255 + .5)) end end
	return nil
end
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3mt.__tostring = function(c) return string.format("%g, %g, %g", c.R, c.G, c.B) end

local BRICK = {
	["Medium stone grey"] = { 163, 162, 165 }, ["Really black"] = { 17, 17, 17 }, ["Institutional white"] = { 248, 248, 248 },
	["White"] = { 242, 243, 243 }, ["Black"] = { 27, 42, 53 }, ["Bright red"] = { 196, 40, 28 }, ["Bright blue"] = { 13, 105, 172 },
	["Bright yellow"] = { 245, 205, 48 }, ["Bright green"] = { 75, 151, 75 }, ["Cyan"] = { 4, 175, 236 }, ["Toothpaste"] = { 0, 255, 255 },
	["Lime green"] = { 0, 255, 0 }, ["Really red"] = { 255, 0, 0 }, ["Really blue"] = { 0, 0, 255 }, ["Gold"] = { 239, 184, 56 },
	["Dark stone grey"] = { 99, 95, 98 }, ["Sand red"] = { 149, 121, 119 }, ["Pastel blue"] = { 128, 187, 219 },
	["Hot pink"] = { 255, 0, 191 }, ["Magenta"] = { 170, 0, 170 }, ["Deep orange"] = { 255, 176, 0 }, ["Neon orange"] = { 213, 115, 61 },
}
local BrickColor = {}
local BCmt = { __type = "BrickColor" }
BCmt.__tostring = function(b) return b.Name end
local function bc(name, col) return setmetatable({ Name = name, Color = col, r = col.R, g = col.G, b = col.B }, BCmt) end
BrickColor.new = function(a, g, b)
	if type(a) == "string" then
		local t = BRICK[a] or { 163, 162, 165 }
		return bc(a, Color3.fromRGB(t[1], t[2], t[3]))
	elseif typeOf(a) == "Color3" then
		return bc("Custom", a)
	elseif type(a) == "number" and g then
		return bc("Custom", c3(a, g, b))
	end
	return bc("Medium stone grey", Color3.fromRGB(163, 162, 165))
end
BrickColor.palette = function() return BrickColor.new("Medium stone grey") end
BrickColor.random = function() return BrickColor.new("Medium stone grey") end
for name in pairs(BRICK) do
	local key = name:gsub(" (%a)", string.upper):gsub("^%a", string.upper):gsub(" ", "")
	BrickColor[key] = function() return BrickColor.new(name) end
end
BrickColor.Gray = function() return BrickColor.new("Medium stone grey") end
BrickColor.DarkGray = function() return BrickColor.new("Dark stone grey") end

-------------------------------------------------------------------------------
-- Misc datatypes
-------------------------------------------------------------------------------
local function simpleType(tname, ctor)
	local mt = { __type = tname }
	mt.__index = function() return nil end
	return function(...)
		local t = ctor(...)
		return setmetatable(t, mt)
	end, mt
end
local UDim = {}
UDim.new = simpleType("UDim", function(s, o) return { Scale = s or 0, Offset = o or 0 } end)
local UDim2 = {}
UDim2.new = simpleType("UDim2", function(xs, xo, ys, yo)
	if type(xs) == "table" then return { X = xs, Y = xo } end
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end)
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
local NumberRange = { new = simpleType("NumberRange", function(a, b) return { Min = a, Max = b or a } end) }
local NumberSequenceKeypoint = { new = simpleType("NumberSequenceKeypoint", function(t, v, e) return { Time = t, Value = v, Envelope = e or 0 } end) }
local NumberSequence = { new = simpleType("NumberSequence", function(a, b)
	if type(a) == "table" then return { Keypoints = a } end
	return { Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }
end) }
local ColorSequenceKeypoint = { new = simpleType("ColorSequenceKeypoint", function(t, v) return { Time = t, Value = v } end) }
local ColorSequence = { new = simpleType("ColorSequence", function(a, b)
	if typeOf(a) == "Color3" then
		return { Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }
	end
	return { Keypoints = a }
end) }
local TweenInfo = { new = simpleType("TweenInfo", function(t, ...) return { Time = t or 1 } end) }
local PhysicalProperties = { new = simpleType("PhysicalProperties", function(...) return { ... } end) }
local Rect = { new = simpleType("Rect", function(...) return { ... } end) }
local Font = { new = simpleType("Font", function(f) return { Family = f } end), fromEnum = function(e) return e end, fromName = function(n) return n end }
local Ray = { new = simpleType("Ray", function(o, d) return { Origin = o, Direction = d } end) }
local Region3 = { new = simpleType("Region3", function(a, b) return { Min = a, Max = b } end) }
local RaycastParams = { new = simpleType("RaycastParams", function() return {} end) }
local OverlapParams = { new = simpleType("OverlapParams", function() return {} end) }
local DateTime = { now = function() return { UnixTimestamp = 0, UnixTimestampMillis = 0 } end }

-- Random: deterministic xorshift-ish generator (sequence differs from Roblox's PCG)
local Random = {}
local RNGmt = { __type = "Random" }
RNGmt.__index = RNGmt
local function rngStep(self)
	-- 32-bit LCG (Numerical Recipes) using integer-safe double math
	self.s = (self.s * 1664525 + 1013904223) % 4294967296
	return self.s / 4294967296
end
function RNGmt:NextNumber(a, b)
	local r = rngStep(self)
	if a == nil then return r end
	return a + (b - a) * r
end
function RNGmt:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * rngStep(self))
end
function RNGmt:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local t = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(t), r * math.sin(t), z)
end
function RNGmt:Shuffle(t)
	for i = #t, 2, -1 do local j = self:NextInteger(1, i); t[i], t[j] = t[j], t[i] end
end
function RNGmt:Clone() return setmetatable({ s = self.s }, RNGmt) end
Random.new = function(seed)
	seed = math.floor(math.abs(seed or 12345)) % 4294967296
	local r = setmetatable({ s = seed }, RNGmt)
	for _ = 1, 4 do rngStep(r) end
	return r
end
math.randomseed(1)

-------------------------------------------------------------------------------
-- Enum (lenient proxy)
-------------------------------------------------------------------------------
local enumCache = {}
local EImt = { __type = "EnumItem" }
EImt.__tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end
EImt.__index = function(e, k) if k == "Value" then return 0 end return nil end
local ETmt = { __type = "Enum" }
ETmt.__index = function(t, k)
	if k == "GetEnumItems" then return function() return {} end end
	local key = t.__name .. "." .. k
	local item = enumCache[key]
	if not item then
		item = setmetatable({ Name = k, EnumType = t.__name }, EImt)
		enumCache[key] = item
	end
	return item
end
local Enum = setmetatable({}, {
	__index = function(self, k)
		local t = setmetatable({ __name = k }, ETmt)
		rawset(self, k, t)
		return t
	end,
})

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------
local CLASS_PARENTS = {
	Part = "FormFactorPart", FormFactorPart = "BasePart", WedgePart = "FormFactorPart", CornerWedgePart = "BasePart",
	TrussPart = "BasePart", SpawnLocation = "Part", MeshPart = "TriangleMeshPart", TriangleMeshPart = "BasePart",
	UnionOperation = "PartOperation", NegateOperation = "PartOperation", IntersectOperation = "PartOperation",
	PartOperation = "TriangleMeshPart", BasePart = "PVInstance", Model = "PVInstance", PVInstance = "Instance",
	Folder = "Instance", Attachment = "Instance", PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	ParticleEmitter = "Instance", Beam = "Instance", Trail = "Instance", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector",
	ScreenGui = "LayerCollector", LayerCollector = "GuiBase2d", GuiBase2d = "Instance",
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageLabel = "GuiObject", ImageButton = "GuiButton",
	GuiButton = "GuiObject", ScrollingFrame = "GuiObject", GuiObject = "GuiBase2d",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIListLayout = "UIComponent", UIPadding = "UIComponent",
	UIGradient = "UIComponent", UIAspectRatioConstraint = "UIComponent", UIGridLayout = "UIComponent", UIComponent = "Instance",
	Decal = "FaceInstance", Texture = "Decal", FaceInstance = "Instance", SpecialMesh = "FileMesh", FileMesh = "DataModelMesh", DataModelMesh = "Instance",
	BlockMesh = "BevelMesh", CylinderMesh = "BevelMesh", BevelMesh = "DataModelMesh",
	Weld = "JointInstance", WeldConstraint = "Instance", Motor6D = "JointInstance", JointInstance = "Instance",
	Humanoid = "Instance", ProximityPrompt = "Instance", ClickDetector = "Instance", Sound = "Instance", Highlight = "Instance",
	StringValue = "ValueBase", NumberValue = "ValueBase", IntValue = "ValueBase", BoolValue = "ValueBase", ObjectValue = "ValueBase",
	CFrameValue = "ValueBase", Vector3Value = "ValueBase", Color3Value = "ValueBase", ValueBase = "Instance",
	Workspace = "WorldRoot", WorldRoot = "Model",
}
local function isBasePartClass(cls)
	local c = cls
	while c do
		if c == "BasePart" then return true end
		c = CLASS_PARENTS[c]
	end
	return false
end

local Instmt = { __type = "Instance" }
local InstanceMethods = {}
local ALL_INSTANCES = {}

local function defaultProps(cls)
	local p = {}
	if isBasePartClass(cls) then
		p.Size = v3(4, 1, 2)
		if cls == "SpawnLocation" then p.Size = v3(12, 1, 12) end
		p.CFrame = CFrame.new()
		p.Color = Color3.fromRGB(163, 162, 165)
		p.Material = Enum.Material.Plastic
		p.Transparency = 0
		p.Reflectance = 0
		p.Anchored = false
		p.CanCollide = true
		p.CastShadow = true
		if cls == "Part" or cls == "SpawnLocation" then p.Shape = Enum.PartType.Block end
	elseif cls == "Attachment" then
		p.CFrame = CFrame.new()
	elseif cls == "SpecialMesh" or cls == "BlockMesh" or cls == "CylinderMesh" or cls == "FileMesh" then
		if cls == "SpecialMesh" then p.MeshType = Enum.MeshType.Head end -- Roblox default
		p.Scale = v3(1, 1, 1)
		p.Offset = v3(0, 0, 0)
		p.MeshId = ""
		p.TextureId = ""
		p.VertexColor = v3(1, 1, 1)
	elseif cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then
		p.Brightness = 1
		p.Range = 8
		p.Color = Color3.new(1, 1, 1)
		p.Enabled = true
	elseif cls == "ParticleEmitter" then
		p.Enabled = true
		p.Rate = 5
		p.Color = ColorSequence.new(Color3.new(1, 1, 1))
	end
	return p
end

local function newInstance(cls)
	local inst = setmetatable({ _class = cls, _props = defaultProps(cls), _children = {}, _attrs = {}, _parent = nil, _name = cls, _tags = {}, _script = CURRENT_SCRIPT }, Instmt)
	table.insert(ALL_INSTANCES, inst)
	return inst
end

local function removeChild(parent, child)
	local ch = parent._children
	for i = #ch, 1, -1 do
		if ch[i] == child then table.remove(ch, i) end
	end
end
local function setParent(inst, parent)
	if inst._destroyed then error("The Parent property of " .. inst._name .. " is locked") end
	if inst._parent then removeChild(inst._parent, inst) end
	inst._parent = parent
	if parent then table.insert(parent._children, inst) end
end

local function descendants(inst, out)
	out = out or {}
	for _, c in ipairs(inst._children) do
		table.insert(out, c)
		descendants(c, out)
	end
	return out
end

local function isA(inst, cls)
	if cls == "Instance" then return true end
	local c = inst._class
	while c do
		if c == cls then return true end
		c = CLASS_PARENTS[c]
	end
	return false
end

-- rigid transform helpers for Models / PVInstances
local function allParts(inst)
	local out = {}
	if isBasePartClass(inst._class) then table.insert(out, inst) end
	for _, d in ipairs(descendants(inst)) do
		if isBasePartClass(d._class) then table.insert(out, d) end
	end
	return out
end

local function boundingBox(parts, frame)
	frame = frame or CFrame.new()
	local inv = cfInverse(frame)
	local mn, mx
	for _, p in ipairs(parts) do
		local s = p._props.Size * 0.5
		local c = p._props.CFrame
		for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
			local w = cfMulV(inv, cfMulV(c, v3(s.x * sx, s.y * sy, s.z * sz)))
			if not mn then mn, mx = w, w else mn, mx = mn:Min(w), mx:Max(w) end
		end end end
	end
	if not mn then return frame, v3(0, 0, 0) end
	local center = (mn + mx) * 0.5
	return cfMul(frame, CFrame.new(center.x, center.y, center.z)), mx - mn
end

local function getPivot(inst)
	if isBasePartClass(inst._class) then
		return inst._props.CFrame * (inst._props.PivotOffset or CFrame.new())
	end
	local pp = inst._props.PrimaryPart
	if pp and pp._parent then return pp._props.CFrame end
	if inst._props.WorldPivot then return inst._props.WorldPivot end
	local c = boundingBox(allParts(inst))
	return c
end

local function pivotTo(inst, target)
	local current = getPivot(inst)
	local delta = cfMul(target, cfInverse(current))
	for _, p in ipairs(allParts(inst)) do
		p._props.CFrame = cfMul(delta, p._props.CFrame)
	end
	if inst._props.WorldPivot then inst._props.WorldPivot = cfMul(delta, inst._props.WorldPivot) end
end

local SERVICES = {}
local game

Instmt.__index = function(inst, k)
	if type(k) == "string" and string.sub(k, 1, 1) == "_" then return nil end
	local pv = rawget(inst._props, k)
	if type(pv) == "function" then return pv end
	local m = InstanceMethods[k]
	if m then return m end
	if k == "Name" then return inst._name end
	if k == "Parent" then return inst._parent end
	if k == "ClassName" then return inst._class end
	local props = inst._props
	local v = props[k]
	if v ~= nil then return v end
	if k == "Position" then
		if inst._class == "Attachment" then return props.CFrame.Position end
		if props.CFrame then return props.CFrame.Position end
	end
	if k == "Orientation" and props.CFrame then
		local rx, ry, rz = CFmethods.ToEulerAnglesYXZ(props.CFrame)
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	end
	if k == "Rotation" and props.CFrame then
		local rx, ry, rz = CFmethods.ToEulerAnglesXYZ(props.CFrame)
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	end
	if inst._class == "Attachment" then
		local parentCF = (inst._parent and inst._parent._props.CFrame) or CFrame.new()
		if k == "WorldCFrame" then return cfMul(parentCF, props.CFrame) end
		if k == "WorldPosition" then return cfMul(parentCF, props.CFrame).Position end
		if k == "Axis" then return props.CFrame.RightVector end
		if k == "SecondaryAxis" then return props.CFrame.UpVector end
	end
	if k == "BrickColor" and props.Color then return BrickColor.new(props.Color) end
	if k == "AssemblyRootPart" then return inst end
	if k == "Mass" then local s = props.Size or v3(); return s.x * s.y * s.z end
	if k == "WorldPivot" then return getPivot(inst) end
	if k == "PrimaryPart" then return nil end
	-- child lookup
	for _, c in ipairs(inst._children) do
		if c._name == k then return c end
	end
	if inst == game and SERVICES.__getService then
		local ok, svc = pcall(SERVICES.__getService, k)
		if ok and svc then return svc end
	end
	return nil
end

Instmt.__newindex = function(inst, k, v)
	if type(k) == "string" and string.sub(k, 1, 1) == "_" then rawset(inst, k, v); return end
	if k == "Parent" then setParent(inst, v); return end
	if k == "Name" then inst._name = tostring(v); return end
	local props = inst._props
	if k == "Position" and inst._class ~= "Attachment" and props.CFrame and typeOf(v) == "Vector3" then
		local c = props.CFrame
		props.CFrame = cf(v.x, v.y, v.z, table.clone(c.m))
		return
	end
	if k == "Position" and inst._class == "Attachment" then
		local c = props.CFrame
		props.CFrame = cf(v.x, v.y, v.z, table.clone(c.m))
		return
	end
	if k == "Orientation" and props.CFrame then
		local p = props.CFrame.Position
		props.CFrame = CFrame.new(p.x, p.y, p.z) * CFrame.fromEulerAnglesYXZ(math.rad(v.x), math.rad(v.y), math.rad(v.z))
		return
	end
	if k == "Rotation" and props.CFrame and typeOf(v) == "Vector3" then
		local p = props.CFrame.Position
		props.CFrame = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(math.rad(v.x), math.rad(v.y), math.rad(v.z))
		return
	end
	if inst._class == "Attachment" and (k == "WorldCFrame" or k == "WorldPosition") then
		local parentCF = (inst._parent and inst._parent._props.CFrame) or CFrame.new()
		if k == "WorldPosition" then v = cf(v.x, v.y, v.z, table.clone(cfMul(parentCF, props.CFrame).m)) end
		props.CFrame = cfMul(cfInverse(parentCF), v)
		return
	end
	if k == "BrickColor" and typeOf(v) == "BrickColor" then props.Color = v.Color; return end
	if k == "WorldPivot" and inst._class ~= "Model" then return end
	if k == "Color" and inst._csg then inst._colorOverride = true end
	if k == "Material" and inst._csg then inst._materialOverride = true end
	if k == "Transparency" and inst._csg then inst._transparencyOverride = true end
	if k == "Size" and inst._csg and props.Size then
		-- resizing a union scales operands around the union centre
		local old = props.Size
		inst._csgScale = v3(v.x / old.x, v.y / old.y, v.z / old.z)
	end
	props[k] = v
end
Instmt.__tostring = function(inst) return inst._name end

function InstanceMethods.GetChildren(inst) return table.clone(inst._children) end
function InstanceMethods.GetDescendants(inst) return descendants(inst) end
function InstanceMethods.FindFirstChild(inst, name, recursive)
	for _, c in ipairs(inst._children) do
		if c._name == name then return c end
	end
	if recursive then
		for _, d in ipairs(descendants(inst)) do
			if d._name == name then return d end
		end
	end
	return nil
end
function InstanceMethods.WaitForChild(inst, name) return InstanceMethods.FindFirstChild(inst, name) end
function InstanceMethods.FindFirstChildOfClass(inst, cls)
	for _, c in ipairs(inst._children) do if c._class == cls then return c end end
	return nil
end
function InstanceMethods.FindFirstChildWhichIsA(inst, cls, recursive)
	local list = recursive and descendants(inst) or inst._children
	for _, c in ipairs(list) do if isA(c, cls) then return c end end
	return nil
end
function InstanceMethods.FindFirstAncestor(inst, name)
	local p = inst._parent
	while p do if p._name == name then return p end p = p._parent end
	return nil
end
function InstanceMethods.FindFirstAncestorOfClass(inst, cls)
	local p = inst._parent
	while p do if p._class == cls then return p end p = p._parent end
	return nil
end
function InstanceMethods.FindFirstAncestorWhichIsA(inst, cls)
	local p = inst._parent
	while p do if isA(p, cls) then return p end p = p._parent end
	return nil
end
function InstanceMethods.IsA(inst, cls) return isA(inst, cls) end
function InstanceMethods.IsDescendantOf(inst, anc)
	local p = inst._parent
	while p do if p == anc then return true end p = p._parent end
	return false
end
function InstanceMethods.IsAncestorOf(inst, d) return InstanceMethods.IsDescendantOf(d, inst) end
function InstanceMethods.GetFullName(inst)
	local parts = {}
	local p = inst
	while p and p ~= game do table.insert(parts, 1, p._name); p = p._parent end
	return table.concat(parts, ".")
end
function InstanceMethods.Destroy(inst)
	if inst._parent then removeChild(inst._parent, inst) end
	inst._parent = nil
	for _, c in ipairs(table.clone(inst._children)) do InstanceMethods.Destroy(c) end
	inst._destroyed = true
end
function InstanceMethods.ClearAllChildren(inst)
	for _, c in ipairs(table.clone(inst._children)) do InstanceMethods.Destroy(c) end
end
local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local mt = getmetatable(v)
	if mt == Instmt then return v end -- references to instances stay references
	return v -- datatypes are immutable
end
local function cloneInst(inst, map)
	local c = newInstance(inst._class)
	c._name = inst._name
	c._props = {}
	for k, v in pairs(inst._props) do c._props[k] = deepCopy(v) end
	for k, v in pairs(inst._attrs) do c._attrs[k] = v end
	for k, v in pairs(inst._tags) do c._tags[k] = v end
	c._csg = inst._csg
	c._colorOverride = inst._colorOverride
	c._materialOverride = inst._materialOverride
	c._transparencyOverride = inst._transparencyOverride
	c._csgScale = inst._csgScale
	map[inst] = c
	for _, ch in ipairs(inst._children) do
		local cc = cloneInst(ch, map)
		cc._parent = c
		table.insert(c._children, cc)
	end
	return c
end
function InstanceMethods.Clone(inst)
	local map = {}
	local c = cloneInst(inst, map)
	-- remap PrimaryPart references inside the clone
	for old, new in pairs(map) do
		for k, v in pairs(new._props) do
			if type(v) == "table" and getmetatable(v) == Instmt and map[v] then new._props[k] = map[v] end
		end
	end
	return c
end
function InstanceMethods.SetAttribute(inst, k, v) inst._attrs[k] = v end
function InstanceMethods.GetAttribute(inst, k) return inst._attrs[k] end
function InstanceMethods.GetAttributes(inst) return table.clone(inst._attrs) end
function InstanceMethods.AddTag(inst, t) inst._tags[t] = true end
function InstanceMethods.RemoveTag(inst, t) inst._tags[t] = nil end
function InstanceMethods.HasTag(inst, t) return inst._tags[t] == true end
function InstanceMethods.GetTags(inst) local o = {} for k in pairs(inst._tags) do table.insert(o, k) end return o end
local fakeSignal = setmetatable({}, { __index = function() return function() return { Disconnect = function() end } end end })
function InstanceMethods.GetPropertyChangedSignal() return fakeSignal end
function InstanceMethods.GetAttributeChangedSignal() return fakeSignal end
function InstanceMethods.Emit() end
function InstanceMethods.Clear() end
function InstanceMethods.Play() end
function InstanceMethods.Stop() end
function InstanceMethods.GetPivot(inst) return getPivot(inst) end
function InstanceMethods.PivotTo(inst, target)
	if isBasePartClass(inst._class) and #descendants(inst) == 0 then
		inst._props.CFrame = cfMul(target, cfInverse(inst._props.PivotOffset or CFrame.new()))
		return
	end
	pivotTo(inst, target)
end
function InstanceMethods.SetPrimaryPartCFrame(inst, target) pivotTo(inst, target) end
function InstanceMethods.GetPrimaryPartCFrame(inst) return getPivot(inst) end
function InstanceMethods.TranslateBy(inst, d) pivotTo(inst, getPivot(inst) + d) end
function InstanceMethods.MoveTo(inst, pos)
	local p = getPivot(inst)
	pivotTo(inst, cf(pos.x, pos.y, pos.z, table.clone(p.m)))
end
function InstanceMethods.GetBoundingBox(inst)
	local frame = getPivot(inst)
	return boundingBox(allParts(inst), cf(frame.px, frame.py, frame.pz, table.clone(frame.m)))
end
function InstanceMethods.GetExtentsSize(inst)
	local _, s = boundingBox(allParts(inst), getPivot(inst))
	return s
end
function InstanceMethods.GetScale(inst) return inst._scale or 1 end
function InstanceMethods.ScaleTo(inst, s)
	local old = inst._scale or 1
	local f = s / old
	local pivot = getPivot(inst)
	for _, p in ipairs(allParts(inst)) do
		local rel = cfMul(cfInverse(pivot), p._props.CFrame)
		rel = cf(rel.px * f, rel.py * f, rel.pz * f, rel.m)
		p._props.CFrame = cfMul(pivot, rel)
		p._props.Size = p._props.Size * f
	end
	inst._scale = s
end
function InstanceMethods.GetMass(inst) local s = inst._props.Size or v3(); return s.x * s.y * s.z end
function InstanceMethods.GetConnectedParts() return {} end
function InstanceMethods.GetTouchingParts() return {} end
function InstanceMethods.SetNetworkOwner() end
function InstanceMethods.BreakJoints() end
function InstanceMethods.MakeJoints() end
function InstanceMethods.GetService(inst, name) return SERVICES.__getService(name) end
function InstanceMethods.FindService(inst, name) return SERVICES.__getService(name) end
function InstanceMethods.Raycast() return nil end
function InstanceMethods.GetPartBoundsInBox() return {} end
function InstanceMethods.GetPartBoundsInRadius() return {} end
function InstanceMethods.GetPartsInPart() return {} end

-- CSG --------------------------------------------------------------------------
local function snapshotOperand(p, frameInv)
	-- a detached copy of an operand, stored in the result's local space
	local c = InstanceMethods.Clone(p)
	c._localCF = cfMul(frameInv, p._props.CFrame)
	c._parent = nil
	return c
end
local function makeCSG(op, base, others)
	local all = { base }
	for _, o in ipairs(others or {}) do table.insert(all, o) end
	local cls = op == "intersect" and "IntersectOperation" or "UnionOperation"
	local bbCF, bbSize
	if op == "union" then
		bbCF, bbSize = boundingBox(all)
	else
		bbCF, bbSize = boundingBox({ base })
	end
	local frameInv = cfInverse(bbCF)
	local res = newInstance(cls)
	res._name = cls
	for k, v in pairs(base._props) do res._props[k] = v end
	res._props.CFrame = bbCF
	res._props.Size = bbSize
	res._props.UsePartColor = false
	local operands = {}
	for i, p in ipairs(all) do
		local snap = snapshotOperand(p, frameInv)
		snap._role = (op == "subtract" and i > 1) and "cutter" or "solid"
		table.insert(operands, snap)
	end
	res._csg = { op = op, operands = operands, size0 = bbSize }
	return res
end
function InstanceMethods.UnionAsync(inst, others) return makeCSG("union", inst, others) end
function InstanceMethods.SubtractAsync(inst, others) return makeCSG("subtract", inst, others) end
function InstanceMethods.IntersectAsync(inst, others) return makeCSG("intersect", inst, others) end

-------------------------------------------------------------------------------
-- Instance.new / services / globals
-------------------------------------------------------------------------------
local Instance = {}
function Instance.new(cls, parent)
	local inst = newInstance(cls)
	if parent then setParent(inst, parent) end
	return inst
end
Instance.fromExisting = function(i) return InstanceMethods.Clone(i) end

game = newInstance("DataModel")
game._name = "Game"
game._props.PlaceId = 0
game._props.JobId = ""
game._props.CreatorId = 0

local stubServiceMethods = setmetatable({}, {
	__index = function() return function() return nil end end,
})
local function makeService(name)
	local svc = newInstance(name == "Workspace" and "Workspace" or name)
	svc._name = name
	svc._props.CFrame = nil
	setParent(svc, game)
	return svc
end
SERVICES.__getService = function(name)
	if SERVICES[name] then return SERVICES[name] end
	local svc = makeService(name)
	SERVICES[name] = svc
	return svc
end
local KNOWN_SERVICES = { "Workspace", "ReplicatedStorage", "ServerStorage", "ServerScriptService", "Lighting", "StarterGui",
	"StarterPack", "StarterPlayer", "Players", "SoundService", "CollectionService", "TweenService", "RunService", "Debris",
	"HttpService", "PhysicsService", "GeometryService", "InsertService", "TextService", "Teams", "UserInputService", "ContentProvider" }
for _, n in ipairs(KNOWN_SERVICES) do SERVICES.__getService(n) end
local workspace = SERVICES.Workspace
workspace._props.Gravity = 196.2
workspace._props.CurrentCamera = Instance.new("Camera", workspace)

-- service-specific methods (installed as per-instance props so they shadow nothing important)
local function tag(svc, fnName, fn) svc._props[fnName] = fn end
tag(SERVICES.CollectionService, "AddTag", function(_, i, t) i._tags[t] = true end)
tag(SERVICES.CollectionService, "RemoveTag", function(_, i, t) i._tags[t] = nil end)
tag(SERVICES.CollectionService, "HasTag", function(_, i, t) return i._tags[t] == true end)
tag(SERVICES.CollectionService, "GetTagged", function(_, t)
	local o = {}
	for _, i in ipairs(ALL_INSTANCES) do if i._tags[t] and not i._destroyed then table.insert(o, i) end end
	return o
end)
tag(SERVICES.CollectionService, "GetInstanceAddedSignal", function() return fakeSignal end)
tag(SERVICES.CollectionService, "GetInstanceRemovedSignal", function() return fakeSignal end)
tag(SERVICES.TweenService, "Create", function() return { Play = function() end, Cancel = function() end, Pause = function() end, Completed = fakeSignal } end)
tag(SERVICES.TweenService, "GetValue", function(_, a) return a end)
tag(SERVICES.Debris, "AddItem", function() end)
tag(SERVICES.RunService, "IsStudio", function() return true end)
tag(SERVICES.RunService, "IsServer", function() return true end)
tag(SERVICES.RunService, "IsClient", function() return false end)
tag(SERVICES.RunService, "IsRunning", function() return false end)
SERVICES.RunService._props.Heartbeat = fakeSignal
SERVICES.RunService._props.RenderStepped = fakeSignal
SERVICES.RunService._props.Stepped = fakeSignal
tag(SERVICES.HttpService, "GenerateGUID", function() return "00000000-0000-0000-0000-000000000000" end)
tag(SERVICES.HttpService, "JSONEncode", function() return "{}" end)
tag(SERVICES.PhysicsService, "RegisterCollisionGroup", function() end)
tag(SERVICES.PhysicsService, "CollisionGroupSetCollidable", function() end)
tag(SERVICES.Players, "GetPlayers", function() return {} end)
SERVICES.Players._props.PlayerAdded = fakeSignal
tag(SERVICES.GeometryService, "UnionAsync", function(_, parts) local b = parts[1]; local rest = {}; for i = 2, #parts do rest[#rest + 1] = parts[i] end return { makeCSG("union", b, rest) } end)
tag(SERVICES.GeometryService, "SubtractAsync", function(_, b, parts) return { makeCSG("subtract", b, parts) } end)
tag(SERVICES.GeometryService, "IntersectAsync", function(_, b, parts) return { makeCSG("intersect", b, parts) } end)

local task = {
	wait = function(t) return t or 0 end,
	spawn = function(f, ...) if type(f) == "function" then local ok, e = pcall(f, ...) if not ok then print("[shim] task.spawn error: " .. tostring(e)) end end end,
	defer = function(f, ...) if type(f) == "function" then pcall(f, ...) end end,
	delay = function() end,
	cancel = function() end,
	synchronize = function() end,
	desynchronize = function() end,
}

-------------------------------------------------------------------------------
-- JSON export
-------------------------------------------------------------------------------
local function num(x)
	if x ~= x or x == math.huge or x == -math.huge then return "0" end
	local s = string.format("%.5f", x)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then s = "0" end
	return s
end
local function jstr(s)
	s = tostring(s)
	s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', ''):gsub('\t', '\\t')
	return '"' .. s .. '"'
end
local function jcf(c)
	local m = c.m
	return "[" .. table.concat({ num(c.px), num(c.py), num(c.pz), num(m[1]), num(m[2]), num(m[3]), num(m[4]), num(m[5]), num(m[6]), num(m[7]), num(m[8]), num(m[9]) }, ",") .. "]"
end
local function jcol(c) return "[" .. num(c.R) .. "," .. num(c.G) .. "," .. num(c.B) .. "]" end
local function enumName(e)
	if type(e) == "table" and e.Name then return e.Name end
	if e == nil then return "" end
	return tostring(e)
end
local function shapeOf(p)
	local cls = p._class
	if cls == "WedgePart" then return "Wedge" end
	if cls == "CornerWedgePart" then return "CornerWedge" end
	if cls == "Part" or cls == "SpawnLocation" then
		local s = enumName(p._props.Shape)
		if s == "" then s = "Block" end
		return s
	end
	return "Block"
end
local function attrsJson(inst)
	local out = {}
	for k, v in pairs(inst._attrs) do
		local t = typeOf(v)
		local val
		if t == "number" then val = num(v) elseif t == "boolean" then val = tostring(v) else val = jstr(tostring(v)) end
		table.insert(out, jstr(k) .. ":" .. val)
	end
	table.sort(out)
	return "{" .. table.concat(out, ",") .. "}"
end
local function effectsJson(p)
	local fx = {}
	for _, d in ipairs(descendants(p)) do
		if d._class == "PointLight" or d._class == "SpotLight" or d._class == "SurfaceLight" then
			if d._props.Enabled ~= false then
				table.insert(fx, string.format('{"type":"light","color":%s,"range":%s,"brightness":%s}', jcol(d._props.Color), num(d._props.Range or 8), num(d._props.Brightness or 1)))
			end
		elseif d._class == "ParticleEmitter" then
			local col = Color3.new(1, 1, 1)
			local cs = d._props.Color
			if cs and cs.Keypoints and cs.Keypoints[1] then col = cs.Keypoints[1].Value end
			local pos = v3(0, 0, 0)
			if d._parent and d._parent._class == "Attachment" then pos = d._parent._props.CFrame.Position end
			table.insert(fx, string.format('{"type":"particles","name":%s,"color":%s,"enabled":%s,"rate":%s,"offset":[%s,%s,%s]}', jstr(d._name), jcol(col), tostring(d._props.Enabled ~= false), num(d._props.Rate or 0), num(pos.x), num(pos.y), num(pos.z)))
		elseif d._class == "Beam" then
			table.insert(fx, '{"type":"beam"}')
		elseif d._class == "BillboardGui" or d._class == "SurfaceGui" then
			local txt = ""
			for _, g in ipairs(descendants(d)) do if g._props.Text then txt = txt .. g._props.Text .. " " end end
			table.insert(fx, '{"type":"gui","text":' .. jstr(txt) .. '}')
		end
	end
	return "[" .. table.concat(fx, ",") .. "]"
end

local partJson
local function csgJson(p, worldCF)
	local csg = p._csg
	local sc = p._csgScale or v3(1, 1, 1)
	local ops = {}
	for _, o in ipairs(csg.operands) do
		local lc = o._localCF
		lc = cf(lc.px * sc.x, lc.py * sc.y, lc.pz * sc.z, lc.m)
		local w = cfMul(worldCF, lc)
		local override = {
			color = p._colorOverride and p._props.Color or nil,
			material = p._materialOverride and p._props.Material or nil,
			transparency = p._transparencyOverride and p._props.Transparency or nil,
			scale = sc,
		}
		table.insert(ops, partJson(o, w, override, o._role))
	end
	return '"csg":{"op":"' .. csg.op .. '","operands":[' .. table.concat(ops, ",") .. "]}"
end
partJson = function(p, worldCF, override, role)
	worldCF = worldCF or p._props.CFrame
	local size = p._props.Size
	local color = p._props.Color
	local material = enumName(p._props.Material)
	local transparency = p._props.Transparency or 0
	if override then
		if override.color then color = override.color end
		if override.material then material = enumName(override.material) end
		if override.transparency then transparency = math.max(transparency, override.transparency) end
		if override.scale then size = size * override.scale end
	end
	local parts = {
		'"name":' .. jstr(p._name),
		'"class":' .. jstr(p._class),
		'"shape":' .. jstr(shapeOf(p)),
		'"size":[' .. num(size.x) .. "," .. num(size.y) .. "," .. num(size.z) .. "]",
		'"cf":' .. jcf(worldCF),
		'"color":' .. jcol(color),
		'"material":' .. jstr(material),
		'"transparency":' .. num(transparency),
		'"effects":' .. effectsJson(p),
	}
	if role then table.insert(parts, '"role":"' .. role .. '"') end
	-- first DataModelMesh child replaces the part's rendered shape (CSG ignores meshes, so skip operands)
	if not role and not p._csg then
		for _, c in ipairs(p._children) do
			local mt
			if c._class == "SpecialMesh" then
				mt = enumName(c._props.MeshType)
				if mt == "" then mt = "Head" end
			elseif c._class == "FileMesh" then mt = "FileMesh"
			elseif c._class == "BlockMesh" then mt = "Brick"
			elseif c._class == "CylinderMesh" then mt = "CylinderMesh"
			end
			if mt then
				local sc = c._props.Scale or v3(1, 1, 1)
				local of = c._props.Offset or v3(0, 0, 0)
				if typeOf(sc) ~= "Vector3" then sc = v3(1, 1, 1) end
				if typeOf(of) ~= "Vector3" then of = v3(0, 0, 0) end
				table.insert(parts, '"meshType":' .. jstr(mt))
				table.insert(parts, '"meshScale":[' .. num(sc.x) .. "," .. num(sc.y) .. "," .. num(sc.z) .. "]")
				table.insert(parts, '"meshOffset":[' .. num(of.x) .. "," .. num(of.y) .. "," .. num(of.z) .. "]")
				break
			end
		end
	end
	if p._csg then
		-- nested CSG results carry their own override chain
		local ov = override
		local saved = { p._colorOverride, p._props.Color, p._materialOverride, p._props.Material }
		if ov and ov.color and not p._colorOverride then p._colorOverride = true; p._props.Color = ov.color end
		if ov and ov.material and not p._materialOverride then p._materialOverride = true; p._props.Material = ov.material end
		table.insert(parts, csgJson(p, worldCF))
		p._colorOverride, p._props.Color, p._materialOverride, p._props.Material = saved[1], saved[2], saved[3], saved[4]
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function modelJson(model, category)
	local out = {}
	local parts = {}
	for _, d in ipairs(descendants(model)) do
		if isBasePartClass(d._class) then
			table.insert(parts, partJson(d))
		end
	end
	-- sub-model names help debugging
	return "{" .. table.concat({
		'"name":' .. jstr(model._name),
		'"category":' .. jstr(category),
		'"class":' .. jstr(model._class),
		'"script":' .. jstr(model._script),
		'"attributes":' .. attrsJson(model),
		'"primary":' .. ((model._props.PrimaryPart and model._props.PrimaryPart._parent) and jcf(model._props.PrimaryPart._props.CFrame) or "null"),
		'"parts":[' .. table.concat(parts, ",") .. "]",
	}, ",") .. "}"
end

local function exportAll()
	local assets = InstanceMethods.FindFirstChild(workspace, "Assets")
	if not assets then return end
	for _, folder in ipairs(assets._children) do
		for _, model in ipairs(folder._children) do
			print("@@MODEL@@" .. modelJson(model, folder._name))
		end
	end
end

-------------------------------------------------------------------------------
-- runner
-------------------------------------------------------------------------------
local ENV = {
	game = game, workspace = workspace, Workspace = workspace, script = nil,
	Instance = Instance, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, BrickColor = BrickColor,
	UDim = UDim, UDim2 = UDim2, NumberRange = NumberRange, NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint, ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint,
	TweenInfo = TweenInfo, PhysicalProperties = PhysicalProperties, Rect = Rect, Font = Font, Ray = Ray, Region3 = Region3,
	RaycastParams = RaycastParams, OverlapParams = OverlapParams, DateTime = DateTime,
	Random = Random, Enum = Enum, task = task, typeof = typeOf,
	wait = function(t) return t or 0 end, spawn = task.spawn, delay = task.delay, tick = function() return 0 end,
	time = function() return 0 end, elapsedTime = function() return 0 end,
	warn = function(...) local t = { ... } for i = 1, #t do t[i] = tostring(t[i]) end print("@@WARN@@" .. table.concat(t, " ")) end,
	print = function(...) local t = { ... } for i = 1, #t do t[i] = tostring(t[i]) end print("@@PRINT@@" .. table.concat(t, " ")) end,
	require = function() return {} end,
}
setmetatable(ENV, { __index = getfenv(1) })

local function runScript(name, src)
	CURRENT_SCRIPT = name
	local fn, err = loadstring(src, "=" .. name)
	if not fn then
		print("@@ERROR@@" .. name .. "\t" .. tostring(err))
		return
	end
	setfenv(fn, ENV)
	local ok, e = pcall(fn)
	if not ok then
		print("@@ERROR@@" .. name .. "\t" .. tostring(e))
	else
		print("@@OK@@" .. name)
	end
end

return { runScript = runScript, exportAll = exportAll }
