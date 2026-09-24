--[[
	Abyssara – Deep Tide Tycoon
	Asset Type: Hub NPC
	Name: Guide ("Bubbles")
	Description:
		A friendly jellyfish who greets new divers near the spawn area of
		the "Tidal Market" hub and explains the basics. Non-humanoid,
		low-poly, phone-friendly part count (~11 parts).

	STAND ANCHOR LOGIC (read before editing):
		Bubbles isn't tied to a shop-style "Interactable" stand (her
		StandInteractable attribute is just the marker "Spawn") - she floats
		near the hub's spawn cluster instead. This script looks up
		Workspace.Assets.Hub.TidalMarketHub and reads the "HubSpawn1"
		SpawnLocation (see assets/models/hub/TidalMarketHub.lua), then places
		Bubbles a few studs inward from it (toward the landmark) so she
		doesn't sit on top of the spawn pad itself.
		If the hub hasn't been built yet, a documented fixed offset from the
		hub's landmark origin (CFrame.new(-500, 2, -500), see TidalMarketHub.lua
		ORIGIN/PLAZA_TOP_Y) is used instead, roughly matching where HubSpawn1
		ends up once the hub is built (spawn ring radius 34, angle 20°,
		pulled inward toward the landmark).

	NAMING CONVENTION FOR THE ANIMATOR (src/client/NpcAmbientController.client.lua):
		- Model.PrimaryPart = "Body"
		- Attributes: "NpcId", "DisplayName", "StandInteractable", "SpeechHeight"
		- Movable named parts (direct children of the model, siblings of
		  Body): "Head", "ArmL", "ArmR", "Eye1", "Eye2" – the ambient
		  controller captures their rest offset relative to Body once, then
		  animates bob/sway (whole model via Model:PivotTo), head-turn,
		  arm-wave and eye-blink on top of that rest pose. Here ArmL/ArmR are
		  the two primary tentacles used for the welcome-wave gesture.

	RUN:
		Paste into the Roblox Studio Command Bar (or a temporary Script under
		ServerScriptService) and run once. Pure geometry, no gameplay logic.
		Idempotent: an existing "Guide" model is removed before rebuild.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Configuration ---------------------------------------------------------
local NPC_ID = "Guide"
local DISPLAY_NAME = "Bubbles"
local STAND_INTERACTABLE = "Spawn" -- marker only; Bubbles has no shop-style stand, see below
local SPAWN_INWARD_DISTANCE = 8 -- studs, pulled in from HubSpawn1 toward the landmark
local FALLBACK_OFFSET = Vector3.new(22, 0, 8) -- see STAND ANCHOR LOGIC above
local SPEECH_HEIGHT = 4.8
local BODY_HEIGHT = 3.0 -- studs: bell center height above the ground anchor (Bubbles floats)
-- // ------------------------------------------------------------------------

local NEON_CYAN = Color3.fromRGB(0, 245, 255)
local NEON_MAGENTA = Color3.fromRGB(255, 0, 200)
local NEON_VIOLET = Color3.fromRGB(160, 70, 255)
local BELL_COLOR = Color3.fromRGB(150, 230, 255)
local EYE_COLOR = Color3.fromRGB(250, 250, 255)
local EYE_PUPIL_COLOR = Color3.fromRGB(20, 24, 30)

-- // Anchor lookup (spawn-based, not stand-based) -----------------------------
local FALLBACK_LANDMARK_POSITION = Vector3.new(-500, 2, -500)

local function findHubModel(): Instance?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	return hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
end

local function computeGuideAnchorCFrame(): CFrame
	local hub = findHubModel()
	if hub then
		local spawnPart = hub:FindFirstChild("HubSpawn1")
		if spawnPart and spawnPart:IsA("BasePart") then
			local spawnPos = spawnPart.Position
			local landmarkXZ = (hub :: any).PrimaryPart and (hub :: any).PrimaryPart.Position
				or FALLBACK_LANDMARK_POSITION
			local landmarkPos = Vector3.new(landmarkXZ.X, spawnPos.Y, landmarkXZ.Z)
			local inward = landmarkPos - spawnPos
			if inward.Magnitude > 0.01 then
				inward = inward.Unit
			else
				inward = Vector3.new(0, 0, 1)
			end
			local anchorPos = spawnPos + inward * SPAWN_INWARD_DISTANCE
			return CFrame.lookAt(anchorPos, landmarkPos)
		end
	end
	-- Fallback: fixed, documented offset from the hub landmark position.
	local anchorPos = FALLBACK_LANDMARK_POSITION + FALLBACK_OFFSET
	return CFrame.lookAt(anchorPos, FALLBACK_LANDMARK_POSITION)
end

-- // Build helpers ------------------------------------------------------------
local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Folder
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- // Root setup ---------------------------------------------------------------
local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local npcsFolder = getOrCreateFolder(assetsFolder, "Npcs")

local previous = npcsFolder:FindFirstChild(NPC_ID)
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = NPC_ID
model.Parent = npcsFolder

local anchor = computeGuideAnchorCFrame()
local rootCFrame = anchor * CFrame.new(0, BODY_HEIGHT, 0)

-- 1) Body: translucent glowing bell ----------------------------------------
local body = newPart("Body", Vector3.new(3.2, 2.4, 3.2), rootCFrame, BELL_COLOR, Enum.Material.Glass, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 0.2

-- Inner glow core
local glowCore = newPart("GlowCore", Vector3.new(1.3, 1.0, 1.3), rootCFrame, NEON_CYAN, Enum.Material.Neon, model)
glowCore.Shape = Enum.PartType.Ball

-- 2) Head: small friendly "face" bump at the front-bottom of the bell -----
local head = newPart("Head", Vector3.new(1.1, 0.6, 1.1), rootCFrame * CFrame.new(0, -1.15, 0.7), BELL_COLOR, Enum.Material.Glass, model)
head.Shape = Enum.PartType.Ball
head.Transparency = 0.1

-- Big cute eyes (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.4, 0.4, 0.2), rootCFrame * CFrame.new(-0.32, -1.05, 1.2), EYE_COLOR, Enum.Material.Neon, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.4, 0.4, 0.2), rootCFrame * CFrame.new(0.32, -1.05, 1.2), EYE_COLOR, Enum.Material.Neon, model)
eye2.Shape = Enum.PartType.Ball
newPart("Eye1Pupil", Vector3.new(0.16, 0.16, 0.08), rootCFrame * CFrame.new(-0.32, -1.05, 1.28), EYE_PUPIL_COLOR, Enum.Material.SmoothPlastic, model)
newPart("Eye2Pupil", Vector3.new(0.16, 0.16, 0.08), rootCFrame * CFrame.new(0.32, -1.05, 1.28), EYE_PUPIL_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Two primary tentacles (named, movable for the welcome wave) ----------
local armL = newPart("ArmL", Vector3.new(0.5, 3.0, 0.5), rootCFrame * CFrame.new(-1.4, -2.4, 0.2) * CFrame.Angles(math.rad(8), 0, math.rad(10)), NEON_CYAN, Enum.Material.Neon, model)
local armR = newPart("ArmR", Vector3.new(0.5, 3.0, 0.5), rootCFrame * CFrame.new(1.4, -2.4, 0.2) * CFrame.Angles(math.rad(8), 0, math.rad(-10)), NEON_CYAN, Enum.Material.Neon, model)

-- 4) Four more hanging tentacles in a rainbow of neon colors (static) -----
local tentacleColors = { NEON_MAGENTA, NEON_VIOLET, NEON_MAGENTA, NEON_VIOLET }
local tentacleOffsets = { Vector3.new(-0.7, -2.2, -0.8), Vector3.new(0.7, -2.2, -0.8), Vector3.new(-1.0, -2.15, 0.6), Vector3.new(1.0, -2.15, 0.6) }
for index, offset in ipairs(tentacleOffsets) do
	local sign = offset.X < 0 and -1 or 1
	newPart(
		"Tentacle" .. index,
		Vector3.new(0.4, 2.4, 0.4),
		rootCFrame * CFrame.new(offset) * CFrame.Angles(math.rad(6), 0, math.rad(sign * 8)),
		tentacleColors[index],
		Enum.Material.Neon,
		model
	)
end

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Guide (Bubbles) built under Workspace.Assets.Npcs")
