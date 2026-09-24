--[[
	Abyssara – Deep Tide Tycoon
	Asset Type: Hub NPC
	Name: Quest Giver ("Captain Finn")
	Description:
		A friendly seahorse captain who hands out daily tasks at the Quest
		Board ("QuestBoard", Interactable = "Quests") in the "Tidal Market"
		hub. Non-humanoid, low-poly, phone-friendly part count (~9 parts).

	STAND ANCHOR LOGIC (read before editing):
		This script looks up Workspace.Assets.Hub.TidalMarketHub, finds the
		sub-model whose "Interactable" attribute equals STAND_INTERACTABLE
		below, and reads its "InteractionPoint" Attachment (the spot where a
		player's ProximityPrompt fires, see assets/models/hub/TidalMarketHub.lua
		and README.md "hub" section). Captain Finn is placed to the SIDE of
		that point (a sideways + slightly-inward offset in the attachment's
		own local space, so it stays correct even if the hub's orientation
		ever changes) so he never blocks the prompt or the quest board panel.
		If the hub hasn't been built yet, a documented fixed offset from the
		hub's landmark origin (CFrame.new(-500, 2, -500), see TidalMarketHub.lua
		ORIGIN/PLAZA_TOP_Y) is used instead, roughly where the QuestBoard ends
		up once the hub is built (STAND_RING_RADIUS = 58, QuestBoard offset
		(58*0.2, 58*0.95) plus a few studs of side offset).

	NAMING CONVENTION FOR THE ANIMATOR (src/client/NpcAmbientController.client.lua):
		- Model.PrimaryPart = "Body"
		- Attributes: "NpcId", "DisplayName", "StandInteractable", "SpeechHeight"
		- Movable named parts (direct children of the model, siblings of
		  Body): "Head", "ArmL", "ArmR", "Eye1", "Eye2" – the ambient
		  controller captures their rest offset relative to Body once, then
		  animates bob/sway (whole model via Model:PivotTo), head-turn,
		  arm-wave and eye-blink on top of that rest pose. Here ArmL/ArmR are
		  the small side fins used for the salute/wave gesture.

	RUN:
		Paste into the Roblox Studio Command Bar (or a temporary Script under
		ServerScriptService) and run once. Pure geometry, no gameplay logic.
		Idempotent: an existing "QuestGiver" model is removed before rebuild.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Configuration ---------------------------------------------------------
local NPC_ID = "QuestGiver"
local DISPLAY_NAME = "Captain Finn"
local STAND_INTERACTABLE = "Quests"
local SIDE_OFFSET = 5
local FORWARD_OFFSET = -2
local FALLBACK_OFFSET = Vector3.new(15.6, 0, 55.1) -- see STAND ANCHOR LOGIC above
local SPEECH_HEIGHT = 4.6
local BODY_HEIGHT = 2.1 -- studs: torso center height above the ground anchor
-- // ------------------------------------------------------------------------

local NEON_GREEN = Color3.fromRGB(130, 255, 60)
local BODY_COLOR = Color3.fromRGB(58, 150, 112)
local BODY_COLOR_LIGHT = Color3.fromRGB(82, 182, 138)
local HAT_COLOR = Color3.fromRGB(30, 32, 42)
local EYE_COLOR = Color3.fromRGB(15, 18, 20)

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

local function newWedge(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
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

-- 1) Body: curved seahorse torso ------------------------------------------
local body = newPart("Body", Vector3.new(1.4, 2.6, 1.4), rootCFrame, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Cylinder
body.CFrame = rootCFrame * CFrame.Angles(0, 0, math.rad(90))

-- Curled tail (static decoration)
newWedge("TailCurl", Vector3.new(0.9, 1.0, 0.9), rootCFrame * CFrame.new(0, -1.7, -0.3) * CFrame.Angles(math.rad(-30), 0, 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- Neon dorsal fin along the back
newPart("DorsalFin", Vector3.new(0.15, 1.6, 0.5), rootCFrame * CFrame.new(0, 0.6, -0.75), NEON_GREEN, Enum.Material.Neon, model)

-- 2) Head: seahorse snout pointing forward --------------------------------
local head = newWedge("Head", Vector3.new(0.7, 0.65, 1.5), rootCFrame * CFrame.new(0, 1.55, 0.55) * CFrame.Angles(0, math.rad(180), 0), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- Eyes (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.22, 0.22, 0.22), rootCFrame * CFrame.new(-0.26, 1.72, 0.55), EYE_COLOR, Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.22, 0.22, 0.22), rootCFrame * CFrame.new(0.26, 1.72, 0.55), EYE_COLOR, Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball

-- Captain's hat (static decoration, perched on the head)
newWedge("CaptainHat", Vector3.new(0.9, 0.45, 0.9), rootCFrame * CFrame.new(0, 2.05, 0.4) * CFrame.Angles(0, math.rad(180), 0), HAT_COLOR, Enum.Material.SmoothPlastic, model)
newPart("HatTrim", Vector3.new(0.95, 0.1, 0.95), rootCFrame * CFrame.new(0, 1.85, 0.4), NEON_GREEN, Enum.Material.Neon, model)

-- 3) Side fins (named, movable for the salute/wave gesture) --------------
local armL = newPart("ArmL", Vector3.new(0.15, 0.9, 0.6), rootCFrame * CFrame.new(-0.85, 0.5, 0.1) * CFrame.Angles(0, 0, math.rad(18)), NEON_GREEN, Enum.Material.Neon, model)
local armR = newPart("ArmR", Vector3.new(0.15, 0.9, 0.6), rootCFrame * CFrame.new(0.85, 0.5, 0.1) * CFrame.Angles(0, 0, math.rad(-18)), NEON_GREEN, Enum.Material.Neon, model)

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Quest Giver (Captain Finn) built under Workspace.Assets.Npcs")
