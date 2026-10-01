--!nonstrict
--[[
	Abyssara - Deep Tide Tycoon
	Script: WorldAmbience (LocalScript)
	Responsibility:
		Makes the static set dressing from assets/models/world/ feel alive:
		kelp / anemones / seagrass / hanging vines sway with the current,
		neon glows and mushrooms pulse, lanterns flicker, light shafts turn,
		wisps and islets bob, bubble vents and ember vents emit particles,
		fish schools / jellyfish / rays roam on smooth paths, and now and
		then a bigger creature swims past. A camera-attached plankton emitter
		adds drifting motes everywhere.

		Everything is discovered through CollectionService tags (see
		WorldAmbienceConfig.Tags and docs/world-ambience.md) - independent of
		folder layout, build order and StreamingEnabled.

	Performance design (mobile first):
		* ONE RunService.PreRender connection drives everything (like
		  ModelAnimator: no per-object connections; only one added/removed
		  signal pair per tag).
		* Distance LOD against the camera: Near = every frame, Mid / Far =
		  throttled, beyond Far = frozen. Distances are recomputed every
		  ~0.35 s, not every frame.
		* Anchored parts are moved with ONE Workspace:BulkMoveTo call per
		  frame, capped by a per-frame part budget (MaxPartMovesPerFrame).
		* Creatures (fish, jellies, rays) are created locally only while the
		  camera is near their school marker (nothing replicates), capped by
		  MaxCreatures.
		* Quality tiers High / Medium / Low / Off (WorldAmbienceConfig.Quality).
		  UIKit.Settings "Reduced Effects" forces Low (read only; this script
		  never changes the setting). Touch-only devices default to Medium.
		  Override: attribute WorldAmbienceQuality on the LocalPlayer or on
		  Workspace.

	Never touched: anything under a model tagged by ModelAnimator
	(ModelAnimationTags.*) or inside a "Buildings" folder - those are
	gameplay models and belong to ModelAnimator.

	Rojo mount: src/client/WorldAmbience.client.lua ->
		StarterPlayer.StarterPlayerScripts.WorldAmbience
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("WorldAmbienceConfig"))
local Tags = Config.Tags
local localPlayer = Players.LocalPlayer

-- // Optional hooks (fail soft) ------------------------------------------------------
local Settings = nil
do
	local ok, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("UIKit", 10))
	end)
	if ok and result and result.Settings then
		Settings = result.Settings
	end
end

-- Tags used by ModelAnimator: never animate anything under them.
local protectedTags = {}
do
	local ok, tagsModule = pcall(function()
		local folder = ReplicatedStorage:WaitForChild("ModelAnimation", 10)
		return require(folder:WaitForChild("ModelAnimationTags", 10))
	end)
	if ok and tagsModule then
		for key, value in pairs(tagsModule) do
			if type(value) == "string" and not string.find(key, "^ATTR_") then
				table.insert(protectedTags, value)
			end
		end
	end
end
local protectedNames = {}
for _, name in ipairs(Config.ProtectedAncestorNames) do
	protectedNames[name] = true
end

local function isProtected(inst)
	local node = inst
	while node and node ~= Workspace do
		if protectedNames[node.Name] then
			return true
		end
		for _, tagName in ipairs(protectedTags) do
			if CollectionService:HasTag(node, tagName) then
				return true
			end
		end
		node = node.Parent
	end
	return false
end

-- // State -------------------------------------------------------------------------------
local tierName = "High"
local tier = Config.Quality.High
local camPos = Vector3.zero
local frameCounter = 0
local lastLod = -1
local lastQualityCheck = -1

local localFolder = Workspace:FindFirstChild("WorldAmbienceLocal")
if not localFolder then
	localFolder = Instance.new("Folder")
	localFolder.Name = "WorldAmbienceLocal"
	localFolder.Parent = Workspace
end

local bulkParts = {}
local bulkCFs = {}
local bulkCount = 0
local function pushMove(part, cf)
	bulkCount += 1
	bulkParts[bulkCount] = part
	bulkCFs[bulkCount] = cf
end

-- entries per system
local swayList, pulseList, flickerList, rigidList, bubbleList, schoolList = {}, {}, {}, {}, {}, {}
local swayMap, pulseMap, flickerMap, rigidMap, bubbleMap, schoolMap = {}, {}, {}, {}, {}, {}

local creatureCount = 0

local function attrNumber(inst, name, default)
	local v = inst:GetAttribute(name)
	if type(v) == "number" then
		return v
	end
	return default
end

local function collectParts(inst)
	local parts = {}
	if inst:IsA("BasePart") then
		parts[1] = inst
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				parts[#parts + 1] = d
			end
		end
	end
	return parts
end

local function pivotInfo(inst)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf, size
	end
	return inst.CFrame, inst.Size
end

local function worldPos(inst)
	if inst:IsA("Model") then
		return (inst:GetBoundingBox()).Position
	end
	return inst.Position
end

-- // Builders ------------------------------------------------------------------------------
local function buildSway(inst)
	local parts = collectParts(inst)
	if #parts == 0 then
		return nil
	end
	local cf, size = pivotInfo(inst)
	local hang = inst:GetAttribute("WA_Hang") == true
	local height = math.max(size.Y, 0.5)
	local pivot = cf.Position + Vector3.new(0, hang and size.Y / 2 or -size.Y / 2, 0)
	local movers, locals, ks = {}, {}, {}
	for _, part in ipairs(parts) do
		local base = part.CFrame
		local rel = base.Position.Y - pivot.Y
		local k = math.clamp((hang and -rel or rel) / height, 0, 1)
		if k > 0.04 then
			movers[#movers + 1] = part
			locals[#locals + 1] = CFrame.new(-pivot) * base
			ks[#ks + 1] = k ^ 1.25
		end
	end
	if #movers == 0 then
		return nil
	end
	return {
		Inst = inst,
		Pos = cf.Position,
		Parts = movers,
		Locals = locals,
		Ks = ks,
		Pivot = pivot,
		Amp = math.rad(attrNumber(inst, "WA_Amp", Config.SwayDefaultAmpDeg)),
		Speed = attrNumber(inst, "WA_Speed", Config.SwayDefaultSpeed),
		Phase = attrNumber(inst, "WA_Phase", 0),
		Next = 0,
		Dist = 1e9,
		Tier = 3,
	}
end

local function buildGlowSet(inst)
	local neon, neonBase, lights, lightBase = {}, {}, {}, {}
	local function consider(d)
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			neon[#neon + 1] = d
			neonBase[#neonBase + 1] = d.Transparency
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			lights[#lights + 1] = d
			lightBase[#lightBase + 1] = d.Brightness
		end
	end
	consider(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		consider(d)
	end
	return neon, neonBase, lights, lightBase
end

local function buildPulse(inst, flicker)
	local neon, neonBase, lights, lightBase = buildGlowSet(inst)
	if #neon == 0 and #lights == 0 then
		return nil
	end
	return {
		Inst = inst,
		Pos = worldPos(inst),
		Neon = neon,
		NeonBase = neonBase,
		Lights = lights,
		LightBase = lightBase,
		Speed = attrNumber(inst, "WA_Speed", flicker and 1.8 or 0.8),
		Depth = attrNumber(inst, "WA_Depth", 0.35),
		Phase = attrNumber(inst, "WA_Phase", 0),
		Next = 0,
		Dist = 1e9,
		Tier = 3,
	}
end

local function buildRigid(inst)
	local parts = collectParts(inst)
	if #parts == 0 then
		return nil
	end
	local cf = pivotInfo(inst)
	local locals = {}
	for i, part in ipairs(parts) do
		locals[i] = cf:ToObjectSpace(part.CFrame)
	end
	local spin = inst:GetAttribute("WA_Spin")
	local bobAmp = inst:GetAttribute("WA_BobAmp")
	if type(spin) ~= "number" then
		spin = CollectionService:HasTag(inst, Tags.Rotate) and 6 or 0
	end
	if type(bobAmp) ~= "number" then
		bobAmp = CollectionService:HasTag(inst, Tags.Bob) and 0.8 or 0
	end
	return {
		Inst = inst,
		Pos = cf.Position,
		Parts = parts,
		Locals = locals,
		Origin = cf.Position,
		Rot = cf.Rotation,
		Spin = math.rad(spin),
		BobAmp = bobAmp,
		BobSpeed = attrNumber(inst, "WA_BobSpeed", 0.7),
		Phase = attrNumber(inst, "WA_Phase", 0),
		Next = 0,
		Dist = 1e9,
		Tier = 3,
	}
end

local function buildBubbles(inst)
	local emitters, baseRates = {}, {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			emitters[#emitters + 1] = d
			baseRates[#baseRates + 1] = d:GetAttribute("BaseRate") or d.Rate
			d.Enabled = false
		end
	end
	if #emitters == 0 then
		return nil
	end
	return { Inst = inst, Pos = worldPos(inst), Emitters = emitters, BaseRates = baseRates, On = false, Dist = 1e9 }
end

local function buildSchool(inst)
	if not inst:IsA("BasePart") then
		return nil
	end
	local seed = attrNumber(inst, "WA_Seed", 1)
	local r = Random.new(seed)
	return {
		Inst = inst,
		Pos = inst.Position,
		Kind = inst:GetAttribute("WA_Kind") or "Fish",
		Count = attrNumber(inst, "WA_Count", 8),
		Size = attrNumber(inst, "WA_Size", 1.5),
		Color = inst:GetAttribute("WA_Color") or Color3.fromRGB(255, 190, 60),
		Color2 = inst:GetAttribute("WA_Color2") or Color3.fromRGB(255, 120, 60),
		RX = attrNumber(inst, "WA_RadiusX", 24),
		RY = attrNumber(inst, "WA_RadiusY", 4),
		RZ = attrNumber(inst, "WA_RadiusZ", 24),
		Speed = attrNumber(inst, "WA_Speed", 2),
		A = { r:NextNumber(0, 6.28), r:NextNumber(0, 6.28), r:NextNumber(0, 6.28), r:NextNumber(0, 6.28), r:NextNumber(0, 6.28), r:NextNumber(0, 6.28) },
		Members = nil,
		Dist = 1e9,
	}
end

-- // Registration (one added/removed signal pair per tag) ---------------------------------
local function register(map, list, inst, builder, flag)
	if map[inst] or not inst:IsDescendantOf(Workspace) or isProtected(inst) then
		return
	end
	local entry = builder(inst, flag)
	if entry then
		map[inst] = entry
		list[#list + 1] = entry
	end
end

local function despawnSchool(entry)
	if entry.Members then
		for _, m in ipairs(entry.Members) do
			for _, p in ipairs(m.Creature.Parts) do
				p:Destroy()
			end
			creatureCount -= 1
		end
		entry.Members = nil
	end
end

local function unregister(map, inst)
	local entry = map[inst]
	if entry then
		entry.Dead = true
		map[inst] = nil
		if entry.Members then
			despawnSchool(entry)
		end
	end
end

local function connectTag(tagName, handler, onRemoved)
	for _, inst in ipairs(CollectionService:GetTagged(tagName)) do
		handler(inst)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(handler)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(onRemoved)
end

-- // Creature builders (client-local, 3-5 parts each) -------------------------------------------
local function newCreaturePart(parent, size, cf, color, material, sphere)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if sphere then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

local CREATURE_BUILD = {}

function CREATURE_BUILD.Fish(L, c1, c2, parent)
	local cf = CFrame.new(0, -500, 0)
	return {
		Kind = "Fish",
		Size = L,
		Parts = {
			newCreaturePart(parent, Vector3.new(0.34 * L, 0.44 * L, L), cf, c1, Enum.Material.SmoothPlastic, true),
			newCreaturePart(parent, Vector3.new(0.06 * L, 0.5 * L, 0.34 * L), cf, c2, Enum.Material.Neon, true),
			newCreaturePart(parent, Vector3.new(0.05 * L, 0.28 * L, 0.4 * L), cf, c2, Enum.Material.Neon, true),
		},
	}
end

function CREATURE_BUILD.Jelly(D, c1, c2, parent)
	local cf = CFrame.new(0, -500, 0)
	local bell = newCreaturePart(parent, Vector3.new(D, 0.7 * D, D), cf, c1, Enum.Material.Neon, true)
	bell.Transparency = 0.35
	local parts = { bell }
	for i = 1, 3 do
		parts[#parts + 1] = newCreaturePart(parent, Vector3.new(0.08 * D, D, 0.08 * D), cf, c2, Enum.Material.Neon, false)
	end
	return { Kind = "Jelly", Size = D, Parts = parts }
end

function CREATURE_BUILD.Ray(L, c1, c2, parent)
	local cf = CFrame.new(0, -500, 0)
	return {
		Kind = "Ray",
		Size = L,
		Parts = {
			newCreaturePart(parent, Vector3.new(0.55 * L, 0.16 * L, 0.85 * L), cf, c1, Enum.Material.SmoothPlastic, true),
			newCreaturePart(parent, Vector3.new(0.6 * L, 0.05 * L, 0.55 * L), cf, c1, Enum.Material.SmoothPlastic, true),
			newCreaturePart(parent, Vector3.new(0.6 * L, 0.05 * L, 0.55 * L), cf, c1, Enum.Material.SmoothPlastic, true),
			newCreaturePart(parent, Vector3.new(0.04 * L, 0.04 * L, 0.8 * L), cf, c2, Enum.Material.Neon, false),
		},
	}
end

local function buildCreature(kind, size, c1, c2)
	local builder = CREATURE_BUILD[kind] or CREATURE_BUILD.Fish
	local c = builder(size, c1, c2, localFolder)
	creatureCount += 1
	return c
end

local function destroyCreature(c)
	for _, p in ipairs(c.Parts) do
		p:Destroy()
	end
	creatureCount -= 1
end

-- Queue the pose of a creature at `cf` (front = -Z) into the bulk move arrays.
local function poseCreature(c, cf, t, phase)
	local parts = c.Parts
	local L = c.Size
	if c.Kind == "Fish" then
		local wag = math.sin(t * 9 + phase) * 0.45
		pushMove(parts[1], cf)
		pushMove(parts[2], cf * CFrame.new(0, 0, L * 0.52) * CFrame.Angles(0, wag, 0) * CFrame.new(0, 0, L * 0.12))
		pushMove(parts[3], cf * CFrame.new(0, L * 0.24, L * 0.04))
	elseif c.Kind == "Jelly" then
		pushMove(parts[1], cf)
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			local sx = math.sin(t * 1.3 + phase + i) * 0.18
			local sz = math.cos(t * 1.1 + phase + i * 2) * 0.18
			pushMove(
				parts[i + 1],
				cf * CFrame.new(math.cos(a) * L * 0.26, -L * 0.32, math.sin(a) * L * 0.26) * CFrame.Angles(sx, 0, sz) * CFrame.new(0, -L * 0.5, 0)
			)
		end
	else -- Ray
		local flap = math.sin(t * 2.2 + phase) * 0.4
		pushMove(parts[1], cf)
		pushMove(parts[2], cf * CFrame.new(-L * 0.3, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(-L * 0.28, 0, 0))
		pushMove(parts[3], cf * CFrame.new(L * 0.3, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(L * 0.28, 0, 0))
		pushMove(parts[4], cf * CFrame.new(0, 0, L * 0.82) * CFrame.Angles(math.sin(t * 1.5 + phase) * 0.08, 0, 0))
	end
end

-- // School paths ---------------------------------------------------------------------------------
local function pathPoint(s, t)
	local k = s.Speed
	local a = s.A
	local x = math.sin(t * 0.13 * k + a[1]) + 0.35 * math.sin(t * 0.31 * k + a[2])
	local y = 0.6 * math.sin(t * 0.17 * k + a[3]) + 0.25 * math.sin(t * 0.41 * k + a[4])
	local z = math.cos(t * 0.11 * k + a[5]) + 0.35 * math.sin(t * 0.29 * k + a[6])
	return s.Pos + Vector3.new(x * s.RX / 1.35, y * s.RY / 0.85, z * s.RZ / 1.35)
end

local function spawnSchool(s)
	local scale = tier.SchoolCountScale
	local want = math.max(s.Kind == "Fish" and 3 or 1, math.floor(s.Count * scale + 0.5))
	want = math.min(want, tier.MaxCreatures - creatureCount)
	if want <= 0 then
		return
	end
	local r = Random.new(math.floor(s.A[1] * 1000))
	s.Members = {}
	for i = 1, want do
		local c = buildCreature(s.Kind, s.Size * r:NextNumber(0.85, 1.2), s.Color, s.Color2)
		local spread = s.Size * (s.Kind == "Fish" and 2.4 or 3.2)
		s.Members[i] = {
			Creature = c,
			Lag = r:NextNumber(0, 1.8) + (i - 1) * 0.12,
			Offset = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-0.6, 0.6), r:NextNumber(-1, 1)) * spread,
			Phase = r:NextNumber(0, 6.28),
		}
	end
end

local function updateSchool(s, t)
	local members = s.Members
	if not members then
		return
	end
	for _, m in ipairs(members) do
		local tt = t - m.Lag
		local p = pathPoint(s, tt)
		local ahead = pathPoint(s, tt + 0.25)
		local pos = p + m.Offset * (1 + 0.15 * math.sin(t * 0.9 + m.Phase))
		local cf
		if s.Kind == "Jelly" then
			pos += Vector3.new(0, math.sin(t * 1.7 + m.Phase) * 0.5, 0)
			cf = CFrame.new(pos)
				* CFrame.Angles(0, t * 0.15 + m.Phase, 0)
				* CFrame.Angles(math.sin(t * 0.5 + m.Phase) * 0.1, 0, math.cos(t * 0.45 + m.Phase) * 0.1)
		else
			local fwd = ahead - p
			if fwd.Magnitude < 1e-3 then
				fwd = Vector3.zAxis
			end
			cf = CFrame.lookAt(pos, pos + fwd)
			if s.Kind == "Ray" then
				cf = cf * CFrame.Angles(0, 0, math.sin(t * 0.5 + m.Phase) * 0.18)
			end
		end
		poseCreature(m.Creature, cf, t, m.Phase)
	end
end

-- // Ambient pass-by creatures -----------------------------------------------------------------------
local passBys = {}
local nextPassBy = 0
local rng = Random.new()

local function currentZone()
	local best, bestScore = nil, 1e9
	for _, zone in ipairs(Config.Zones) do
		local d = (Vector3.new(camPos.X, 0, camPos.Z) - Vector3.new(zone.Center.X, 0, zone.Center.Z)).Magnitude
		local score = d / zone.Radius
		if score < 1 and score < bestScore then
			best, bestScore = zone, score
		end
	end
	return best
end

local function spawnPassBy(now)
	local zone = currentZone()
	if not zone or #zone.PassBy == 0 then
		return
	end
	local def = zone.PassBy[rng:NextInteger(1, #zone.PassBy)]
	local count = math.min(def.Group, tier.MaxCreatures - creatureCount)
	if count <= 0 then
		return
	end
	local R = Config.PassByRingRadius
	local theta = rng:NextNumber(0, math.pi * 2)
	local height = rng:NextNumber(Config.PassByHeight[1], Config.PassByHeight[2])
	local start = camPos + Vector3.new(math.cos(theta) * R, height, math.sin(theta) * R)
	local aim = camPos + Vector3.new(rng:NextNumber(-45, 45), height * 0.5, rng:NextNumber(-45, 45))
	local dir = (aim - start) * Vector3.new(1, 0.25, 1)
	dir = dir.Unit
	local speed = rng:NextNumber(Config.PassBySpeed[1], Config.PassBySpeed[2])
	local members = {}
	for i = 1, count do
		local size = def.Size * rng:NextNumber(0.85, 1.15)
		members[i] = {
			Creature = buildCreature(def.Kind, size, def.Color, def.Color2),
			Offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * def.Size * (count > 1 and 2.2 or 0),
			Phase = rng:NextNumber(0, 6.28),
		}
	end
	table.insert(passBys, {
		Start = start,
		Dir = dir,
		Perp = Vector3.new(-dir.Z, 0, dir.X),
		Speed = speed,
		Born = now,
		Life = 2 * R / speed + 4,
		Kind = def.Kind,
		Members = members,
		Wave = rng:NextNumber(3, 8),
	})
end

local function updatePassBys(now, t)
	for i = #passBys, 1, -1 do
		local pb = passBys[i]
		local age = now - pb.Born
		if age > pb.Life or not tier.PassBy then
			for _, m in ipairs(pb.Members) do
				destroyCreature(m.Creature)
			end
			table.remove(passBys, i)
		else
			local base = pb.Start + pb.Dir * (pb.Speed * age) + pb.Perp * (math.sin(age * 0.35) * pb.Wave)
			local ahead = pb.Start + pb.Dir * (pb.Speed * (age + 0.3)) + pb.Perp * (math.sin((age + 0.3) * 0.35) * pb.Wave)
			for _, m in ipairs(pb.Members) do
				local pos = base + m.Offset
				local cf
				if pb.Kind == "Jelly" then
					cf = CFrame.new(pos + Vector3.new(0, math.sin(t * 1.5 + m.Phase) * 0.8, 0)) * CFrame.Angles(math.sin(t * 0.4) * 0.1, t * 0.1, 0)
				else
					cf = CFrame.lookAt(pos, pos + (ahead - base))
				end
				poseCreature(m.Creature, cf, t, m.Phase)
			end
		end
	end
end

-- // Plankton (camera-attached) ---------------------------------------------------------------------
local planktonPart = Instance.new("Part")
planktonPart.Name = "Plankton"
planktonPart.Size = Config.PlanktonBox
planktonPart.Transparency = 1
planktonPart.Anchored = true
planktonPart.CanCollide = false
planktonPart.CanQuery = false
planktonPart.CanTouch = false
planktonPart.CastShadow = false
planktonPart.Parent = localFolder

local plankton = Instance.new("ParticleEmitter")
plankton.Texture = "rbxasset://textures/particles/sparkles_main.dds"
plankton.Shape = Enum.ParticleEmitterShape.Box
plankton.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
plankton.Lifetime = NumberRange.new(8, 12)
plankton.Speed = NumberRange.new(0.2, 0.8)
plankton.SpreadAngle = Vector2.new(180, 180)
plankton.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
plankton.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1) })
plankton.LightEmission = 0.6
plankton.Rate = 0
plankton.Enabled = false
plankton.Color = ColorSequence.new(Config.DefaultPlankton)
plankton.Parent = planktonPart

-- // Quality ------------------------------------------------------------------------------------------
local function resolveTier()
	local override = localPlayer:GetAttribute(Config.QualityAttribute)
	if type(override) ~= "string" then
		override = Workspace:GetAttribute(Config.QualityAttribute)
	end
	if type(override) == "string" and Config.Quality[override] then
		return override
	end
	if Settings and Settings.GetReducedEffects and Settings.GetReducedEffects() then
		return Config.ReducedEffectsTier
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return Config.DefaultTouch
	end
	return Config.DefaultDesktop
end

local function applyTier(newName)
	if newName == tierName and tier then
		return
	end
	tierName = newName
	tier = Config.Quality[newName]
	-- drop all local creatures; schools respawn with the new counts
	for _, s in ipairs(schoolList) do
		despawnSchool(s)
	end
	for _, pb in ipairs(passBys) do
		for _, m in ipairs(pb.Members) do
			destroyCreature(m.Creature)
		end
	end
	table.clear(passBys)
	for _, b in ipairs(bubbleList) do
		b.On = false
		for _, e in ipairs(b.Emitters) do
			e.Enabled = false
		end
	end
	lastLod = -1
end

-- // LOD classification (every ~0.35 s) -----------------------------------------------------------
local function compact(list, map)
	local n = 0
	for i = 1, #list do
		local e = list[i]
		if not e.Dead and e.Inst.Parent ~= nil and e.Inst:IsDescendantOf(Workspace) then
			n += 1
			list[n] = e
		else
			if e.Inst then
				map[e.Inst] = nil
			end
			if e.Members then
				despawnSchool(e)
			end
		end
	end
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
end

local function classify(list)
	local near, mid, far = tier.NearDistance, tier.MidDistance, tier.FarDistance
	for i = 1, #list do
		local e = list[i]
		local d = (e.Pos - camPos).Magnitude
		e.Dist = d
		e.Tier = d < near and 0 or (d < mid and 1 or (d < far and 2 or 3))
	end
end

local function recomputeLod(now)
	compact(swayList, swayMap)
	compact(pulseList, pulseMap)
	compact(flickerList, flickerMap)
	compact(rigidList, rigidMap)
	compact(bubbleList, bubbleMap)
	compact(schoolList, schoolMap)
	classify(swayList)
	classify(pulseList)
	classify(flickerList)
	classify(rigidList)

	-- bubbles: enable emitters near the camera only
	for _, b in ipairs(bubbleList) do
		local d = (b.Pos - camPos).Magnitude
		b.Dist = d
		local want = tier.BubbleDistance > 0 and d < tier.BubbleDistance
		if want ~= b.On then
			b.On = want
			for i, e in ipairs(b.Emitters) do
				e.Rate = b.BaseRates[i] * tier.BubbleRateScale
				e.Enabled = want
			end
		end
	end

	-- schools: spawn near / despawn far (hysteresis)
	local spawnD = tier.SchoolSpawnDistance
	for _, s in ipairs(schoolList) do
		local d = (s.Pos - camPos).Magnitude
		s.Dist = d
		if tier.Enabled and spawnD > 0 then
			if not s.Members and d < spawnD then
				spawnSchool(s)
			elseif s.Members and d > spawnD + Config.SchoolDespawnExtra then
				despawnSchool(s)
			end
		elseif s.Members then
			despawnSchool(s)
		end
	end

	-- plankton tint follows the zone
	local zone = currentZone()
	plankton.Color = ColorSequence.new(zone and zone.Plankton or Config.DefaultPlankton)
	local rate = tier.PlanktonRate
	if rate > 0 then
		plankton.Rate = rate
		plankton.Enabled = true
	else
		plankton.Enabled = false
	end
	lastLod = now
end

-- // Per-system updates ---------------------------------------------------------------------------------
local function dueAt(e, now)
	if e.Tier == 0 then
		return true
	end
	if e.Tier == 3 then
		return false
	end
	if now >= e.Next then
		e.Next = now + (e.Tier == 1 and tier.MidInterval or tier.FarInterval)
		return true
	end
	return false
end

local function updateSway(now, t, budget)
	local n = #swayList
	if n == 0 or not tier.Sway then
		return budget
	end
	local start = frameCounter % n
	for step = 0, n - 1 do
		if budget <= 0 then
			break
		end
		local e = swayList[(start + step) % n + 1]
		if dueAt(e, now) then
			local s, ph, amp = e.Speed, e.Phase, e.Amp
			local gust = 0.85 + 0.15 * math.sin(t * 0.17 + ph)
			local ax = amp * gust * (0.7 * math.sin(t * s + ph) + 0.3 * math.sin(t * s * 0.37 + ph * 2.1))
			local az = amp * gust * (0.7 * math.sin(t * s * 0.83 + ph * 1.3 + 1.7) + 0.3 * math.sin(t * s * 0.29 + ph))
			local pivotCF = CFrame.new(e.Pivot)
			local parts, locals, ks = e.Parts, e.Locals, e.Ks
			for i = 1, #parts do
				local k = ks[i]
				pushMove(parts[i], pivotCF * CFrame.Angles(ax * k, 0, az * k) * locals[i])
			end
			budget -= #parts
		end
	end
	return budget
end

local function updateRigid(now, t, budget)
	local n = #rigidList
	if n == 0 or not tier.Motion then
		return budget
	end
	local start = frameCounter % n
	for step = 0, n - 1 do
		if budget <= 0 then
			break
		end
		local e = rigidList[(start + step) % n + 1]
		if dueAt(e, now) then
			local dy = e.BobAmp * math.sin(t * e.BobSpeed * 2 + e.Phase)
			local o = e.Origin
			local frame = CFrame.new(o.X, o.Y + dy, o.Z) * e.Rot * CFrame.Angles(0, e.Spin * t + e.Phase, 0)
			local parts, locals = e.Parts, e.Locals
			for i = 1, #parts do
				pushMove(parts[i], frame * locals[i])
			end
			budget -= #parts
		end
	end
	return budget
end

local function updatePulse(now, t)
	if not tier.Pulse then
		return
	end
	for i = 1, #pulseList do
		local e = pulseList[i]
		if dueAt(e, now) then
			local p = 0.5 + 0.5 * math.sin(t * e.Speed * 2 + e.Phase)
			local dim = e.Depth * Config.PulseDepthScale * (1 - p)
			local neon, neonBase = e.Neon, e.NeonBase
			for j = 1, #neon do
				local b = neonBase[j]
				neon[j].Transparency = b + (1 - b) * dim
			end
			local lights, lightBase = e.Lights, e.LightBase
			for j = 1, #lights do
				lights[j].Brightness = lightBase[j] * (1 - 0.7 * dim)
			end
		end
	end
end

local function updateFlicker(now, t)
	if not tier.Flicker then
		return
	end
	for i = 1, #flickerList do
		local e = flickerList[i]
		if dueAt(e, now) then
			local n = math.noise(t * e.Speed, e.Phase, 0)
			local v = math.clamp(0.9 + n * 0.5, Config.FlickerMin, 1.05)
			if math.noise(t * e.Speed * 0.4, e.Phase, 7) < -0.38 then
				v *= Config.FlickerDipFactor -- occasional (small) dip
			end
			local neon, neonBase = e.Neon, e.NeonBase
			for j = 1, #neon do
				neon[j].Transparency = neonBase[j] + (1 - neonBase[j]) * math.clamp(1 - v, 0, 0.6) * 0.5
			end
			local lights, lightBase = e.Lights, e.LightBase
			for j = 1, #lights do
				lights[j].Brightness = lightBase[j] * v
			end
		end
	end
end

local function updateSchools(now, t)
	for i = 1, #schoolList do
		local s = schoolList[i]
		if s.Members then
			if s.Dist < tier.MidDistance or frameCounter % 2 == 0 then
				updateSchool(s, t)
			end
		end
	end
end

-- // Main loop ---------------------------------------------------------------------------------------------
local function onFrame(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	frameCounter += 1
	local now = os.clock()
	camPos = camera.CFrame.Position

	if now - lastQualityCheck > 1 then
		lastQualityCheck = now
		applyTier(resolveTier())
	end
	if not tier.Enabled then
		plankton.Enabled = false
		return
	end
	if now - lastLod > Config.LodRecomputeInterval then
		recomputeLod(now)
	end

	local t = Workspace:GetServerTimeNow()
	bulkCount = 0
	table.clear(bulkParts)
	table.clear(bulkCFs)

	-- plankton box follows the camera
	pushMove(planktonPart, CFrame.new(camPos))

	local budget = tier.MaxPartMovesPerFrame
	budget = updateSway(now, t, budget)
	budget = updateRigid(now, t, budget)
	updatePulse(now, t)
	updateFlicker(now, t)
	updateSchools(now, t)

	if tier.PassBy and now >= nextPassBy then
		local interval = tier.PassByInterval
		nextPassBy = now + rng:NextNumber(interval[1], interval[2])
		if #passBys < 2 then
			spawnPassBy(now)
		end
	end
	updatePassBys(now, t)

	if bulkCount > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- // Wire up ---------------------------------------------------------------------------------------------------
applyTier(resolveTier())
nextPassBy = os.clock() + 8

connectTag(Tags.Sway, function(inst)
	register(swayMap, swayList, inst, buildSway)
end, function(inst)
	unregister(swayMap, inst)
end)
connectTag(Tags.Pulse, function(inst)
	register(pulseMap, pulseList, inst, buildPulse, false)
end, function(inst)
	unregister(pulseMap, inst)
end)
connectTag(Tags.Flicker, function(inst)
	register(flickerMap, flickerList, inst, buildPulse, true)
end, function(inst)
	unregister(flickerMap, inst)
end)
local function registerRigid(inst)
	register(rigidMap, rigidList, inst, buildRigid)
end
local function unregisterRigid(inst)
	if not CollectionService:HasTag(inst, Tags.Rotate) and not CollectionService:HasTag(inst, Tags.Bob) then
		unregister(rigidMap, inst)
	end
end
connectTag(Tags.Rotate, registerRigid, unregisterRigid)
connectTag(Tags.Bob, registerRigid, unregisterRigid)
connectTag(Tags.Bubbles, function(inst)
	register(bubbleMap, bubbleList, inst, buildBubbles)
end, function(inst)
	unregister(bubbleMap, inst)
end)
connectTag(Tags.School, function(inst)
	register(schoolMap, schoolList, inst, buildSchool)
end, function(inst)
	unregister(schoolMap, inst)
end)

RunService.PreRender:Connect(onFrame)
