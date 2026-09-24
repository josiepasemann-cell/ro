--[[
	Abyssara – Deep Tide Tycoon
	Asset Type: Hub NPC
	Name: Egg Keeper ("Inky the Egg Keeper")
	Description:
		A wise old glowing octopus who watches over the Mystery Egg station
		("GachaStation", Interactable = "Gacha") in the "Tidal Market" hub.
		Non-humanoid, low-poly, phone-friendly part count (~11 parts).

	STAND ANCHOR LOGIC (read before editing):
		This script looks up Workspace.Assets.Hub.TidalMarketHub, finds the
		sub-model whose "Interactable" attribute equals STAND_INTERACTABLE
		below, and reads its "InteractionPoint" Attachment (the spot where a
		player's ProximityPrompt fires, see assets/models/hub/TidalMarketHub.lua
		and README.md "hub" section). Inky is placed to the SIDE of that
		point (a sideways + slightly-inward offset in the attachment's own
		local space, so it stays correct even if the hub's orientation ever
		changes) so she never blocks the prompt or the egg display pedestal.
		If the hub hasn't been built yet, a documented fixed offset from the
		hub's landmark origin (CFrame.new(-500, 2, -500), see TidalMarketHub.lua
		ORIGIN/PLAZA_TOP_Y) is used instead, roughly where the GachaStation
		ends up once the hub is built (STAND_RING_RADIUS = 58, GachaStation
		offset (58*0.75, -58*0.4) plus a few studs of side offset).

	NAMING CONVENTION FOR THE ANIMATOR (src/client/NpcAmbientController.client.lua):
		- Model.PrimaryPart = "Body"
		- Attributes: "NpcId", "DisplayName", "StandInteractable", "SpeechHeight"
		- Movable named parts (direct children of the model, siblings of
		  Body): "Head", "ArmL", "ArmR", "Eye1", "Eye2" – the ambient
		  controller captures their rest offset relative to Body once, then
		  animates bob/sway (whole model via Model:PivotTo), head-turn,
		  arm-wave and eye-blink on top of that rest pose. Here ArmL/ArmR are
		  the two primary tentacles used for the wave gesture.

	RUN:
		Paste into the Roblox Studio Command Bar (or a temporary Script under
		ServerScriptService) and run once. Pure geometry, no gameplay logic.
		Idempotent: an existing "EggKeeper" model is removed before rebuild.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Configuration ---------------------------------------------------------
local NPC_ID = "EggKeeper"
local DISPLAY_NAME = "Inky"
local STAND_INTERACTABLE = "Gacha"
local SIDE_OFFSET = 5
local FORWARD_OFFSET = -2
local FALLBACK_OFFSET = Vector3.new(39.5, 0, -23.2) -- see STAND ANCHOR LOGIC above
local SPEECH_HEIGHT = 5.0
local BODY_HEIGHT = 2.0 -- studs: mantle center height above the ground anchor
-- // ------------------------------------------------------------------------

local NEON_VIOLET = Color3.fromRGB(160, 70, 255)
local MANTLE_COLOR = Color3.fromRGB(96, 62, 132)
local MANTLE_COLOR_LIGHT = Color3.fromRGB(128, 88, 170)
local TENTACLE_COLOR = Color3.fromRGB(120, 78, 168)
local EYE_COLOR = Color3.fromRGB(232, 232, 250)

-- // Stand anchor lookup -----------------------------------------------------
local function findHubModel(): Instance?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	return hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
end

local function findStandByInteractable(interactableValue: string): Instance?
	local hub = findHubModel()
	if not hub then
		return nil
	end
	if hub:GetAttribute("Interactable") == interactableValue then
		return hub
	end
	for _, descendant in hub:GetDescendants() do
		if descendant:GetAttribute("Interactable") == interactableValue then
			return descendant
		end
	end
	return nil
end

local FALLBACK_LANDMARK_POSITION = Vector3.new(-500, 2, -500)

local function computeStandAnchorCFrame(interactableValue: string, sideOffset: number, forwardOffset: number, fallbackOffset: Vector3): CFrame
	local stand = findStandByInteractable(interactableValue)
	if stand and stand:IsA("Model") and stand.PrimaryPart then
		local interactionPoint = stand:FindFirstChild("InteractionPoint", true)
		if interactionPoint and interactionPoint:IsA("Attachment") then
			local pointCFrame = interactionPoint.WorldCFrame
			local sideDir = pointCFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
			local forwardDir = pointCFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))
			local groundY = stand.PrimaryPart.Position.Y
			local anchorXZ = pointCFrame.Position + sideDir * sideOffset + forwardDir * forwardOffset
			local anchorPos = Vector3.new(anchorXZ.X, groundY, anchorXZ.Z)
			local lookTarget = Vector3.new(stand.PrimaryPart.Position.X, groundY, stand.PrimaryPart.Position.Z)
			if (anchorPos - lookTarget).Magnitude > 0.01 then
				return CFrame.lookAt(anchorPos, lookTarget)
			end
		end
	end
	-- Fallback: fixed, documented offset from the hub landmark position.
	local anchorPos = FALLBACK_LANDMARK_POSITION + fallbackOffset
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

local anchor = computeStandAnchorCFrame(STAND_INTERACTABLE, SIDE_OFFSET, FORWARD_OFFSET, FALLBACK_OFFSET)
local rootCFrame = anchor * CFrame.new(0, BODY_HEIGHT, 0)

-- 1) Body: rounded mantle -------------------------------------------------
local body = newPart("Body", Vector3.new(3.0, 3.4, 3.0), rootCFrame, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- Glowing "age ring" wrinkles on the mantle
newPart("MantleGlowRing", Vector3.new(3.05, 0.18, 3.05), rootCFrame * CFrame.new(0, 0.3, 0), NEON_VIOLET, Enum.Material.Neon, model)
newPart("MantleGlowRing2", Vector3.new(2.7, 0.14, 2.7), rootCFrame * CFrame.new(0, -0.5, 0), NEON_VIOLET, Enum.Material.Neon, model)

-- 2) Head: smaller bump perched at the front-top of the mantle ----------
local head = newPart("Head", Vector3.new(1.5, 1.1, 1.3), rootCFrame * CFrame.new(0, 1.35, 0.9), MANTLE_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)
head.Shape = Enum.PartType.Ball

-- Big kind eyes (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.55, 0.55, 0.3), rootCFrame * CFrame.new(-0.4, 1.4, 1.55), EYE_COLOR, Enum.Material.Neon, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.55, 0.55, 0.3), rootCFrame * CFrame.new(0.4, 1.4, 1.55), EYE_COLOR, Enum.Material.Neon, model)
eye2.Shape = Enum.PartType.Ball

-- 3) Two primary tentacles (named, movable for waving) -------------------
local armL = newPart("ArmL", Vector3.new(0.55, 2.6, 0.55), rootCFrame * CFrame.new(-1.6, -2.0, 0.4) * CFrame.Angles(math.rad(10), 0, math.rad(14)), TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)
local armR = newPart("ArmR", Vector3.new(0.55, 2.6, 0.55), rootCFrame * CFrame.new(1.6, -2.0, 0.4) * CFrame.Angles(math.rad(10), 0, math.rad(-14)), TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)

-- 4) Four more hanging tentacles (static decoration) ----------------------
local tentacleOffsets = { Vector3.new(-0.8, -2.2, -1.0), Vector3.new(0.8, -2.2, -1.0), Vector3.new(-1.3, -2.1, -0.3), Vector3.new(1.3, -2.1, -0.3) }
for index, offset in ipairs(tentacleOffsets) do
	local sign = offset.X < 0 and -1 or 1
	newPart(
		"Tentacle" .. index,
		Vector3.new(0.45, 2.2, 0.45),
		rootCFrame * CFrame.new(offset) * CFrame.Angles(math.rad(6), 0, math.rad(sign * 8)),
		TENTACLE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Egg Keeper (Inky) built under Workspace.Assets.Npcs")
