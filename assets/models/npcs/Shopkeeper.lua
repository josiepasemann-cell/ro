--[[
	Abyssara – Deep Tide Tycoon
	Asset Type: Hub NPC
	Name: Shopkeeper ("Shelly the Shopkeeper")
	Description:
		Cheerful hermit crab merchant who stands beside the Shop stand
		("ShopStand", Interactable = "Shop") in the "Tidal Market" hub.
		Non-humanoid, low-poly, phone-friendly part count (~11 parts).

	STAND ANCHOR LOGIC (read before editing):
		This script looks up Workspace.Assets.Hub.TidalMarketHub, finds the
		sub-model whose "Interactable" attribute equals STAND_INTERACTABLE
		below, and reads its "InteractionPoint" Attachment (the spot where a
		player's ProximityPrompt fires, see assets/models/hub/TidalMarketHub.lua
		and README.md "hub" section). Shelly is placed to the SIDE of that
		point (a sideways + slightly-inward offset in the attachment's own
		local space, so it stays correct even if the hub's orientation ever
		changes) so she never blocks the prompt.
		If the hub hasn't been built yet, a documented fixed offset from the
		hub's landmark origin (CFrame.new(-500, 2, -500), see TidalMarketHub.lua
		ORIGIN/PLAZA_TOP_Y) is used instead, roughly where the ShopStand ends
		up once the hub is built (STAND_RING_RADIUS = 58, ShopStand offset
		(-58*0.7, -58*0.55) plus a few studs of side offset).

	NAMING CONVENTION FOR THE ANIMATOR (src/client/NpcAmbientController.client.lua):
		- Model.PrimaryPart = "Body"
		- Attributes: "NpcId", "DisplayName", "StandInteractable", "SpeechHeight"
		- Movable named parts (direct children of the model, siblings of
		  Body): "Head", "ArmL", "ArmR", "Eye1", "Eye2" – the ambient
		  controller captures their rest offset relative to Body once, then
		  animates bob/sway (whole model via Model:PivotTo), head-turn,
		  arm-wave and eye-blink on top of that rest pose.

	RUN:
		Paste into the Roblox Studio Command Bar (or a temporary Script under
		ServerScriptService) and run once. Pure geometry, no gameplay logic.
		Idempotent: an existing "Shopkeeper" model is removed before rebuild.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Configuration ---------------------------------------------------------
local NPC_ID = "Shopkeeper"
local DISPLAY_NAME = "Shelly"
local STAND_INTERACTABLE = "Shop"
local SIDE_OFFSET = 5 -- studs, sideways from the stand's InteractionPoint
local FORWARD_OFFSET = -2 -- studs, back toward the stand (stays off the prompt line)
local FALLBACK_OFFSET = Vector3.new(-36.6, 0, -31.9) -- see STAND ANCHOR LOGIC above
local SPEECH_HEIGHT = 4.4 -- studs above ground for the speech bubble
local BODY_HEIGHT = 1.5 -- studs: shell center height above the ground anchor
-- // ------------------------------------------------------------------------

local NEON_ORANGE = Color3.fromRGB(255, 130, 0)
local NEON_CYAN = Color3.fromRGB(0, 245, 255)
local SHELL_COLOR = Color3.fromRGB(150, 92, 46)
local SHELL_COLOR_LIGHT = Color3.fromRGB(198, 138, 82)
local CLAW_COLOR = Color3.fromRGB(255, 150, 70)
local LEG_COLOR = Color3.fromRGB(168, 108, 58)

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

-- 1) Body: domed shell ---------------------------------------------------
local body = newPart("Body", Vector3.new(3.2, 2.2, 3.0), rootCFrame, SHELL_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- Glowing spiral marking on the shell
newPart("ShellMark", Vector3.new(0.2, 1.6, 0.9), rootCFrame * CFrame.new(0.6, 0.5, 1.0) * CFrame.Angles(0, math.rad(35), math.rad(20)), NEON_ORANGE, Enum.Material.Neon, model)

-- 2) Head: small crab face poking out front-bottom of the shell ---------
local head = newPart("Head", Vector3.new(1.1, 0.9, 0.9), rootCFrame * CFrame.new(0, -0.7, 1.6), SHELL_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- Eye stalks (static decoration) + eyes (named, movable for blink)
for _, side in ipairs({ -1, 1 }) do
	newPart(
		"EyeStalk" .. (side < 0 and "L" or "R"),
		Vector3.new(0.12, 0.55, 0.12),
		rootCFrame * CFrame.new(side * 0.3, -0.05, 1.9),
		SHELL_COLOR_LIGHT,
		Enum.Material.SmoothPlastic,
		model
	)
end

local eye1 = newPart("Eye1", Vector3.new(0.32, 0.32, 0.32), rootCFrame * CFrame.new(-0.3, 0.2, 2.05), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.32, 0.32, 0.32), rootCFrame * CFrame.new(0.3, 0.2, 2.05), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball

-- 3) Claws (named, movable for waving) -----------------------------------
local armL = newPart("ArmL", Vector3.new(1.0, 0.7, 1.4), rootCFrame * CFrame.new(-1.9, 0.1, 0.4) * CFrame.Angles(0, math.rad(24), 0), CLAW_COLOR, Enum.Material.Neon, model)
armL.Shape = Enum.PartType.Ball
local armR = newPart("ArmR", Vector3.new(1.0, 0.7, 1.4), rootCFrame * CFrame.new(1.9, 0.1, 0.4) * CFrame.Angles(0, math.rad(-24), 0), CLAW_COLOR, Enum.Material.Neon, model)
armR.Shape = Enum.PartType.Ball

-- 4) Little legs peeking from under the shell (static decoration) -------
local legOffsets = { Vector3.new(-1.1, -1.0, -0.8), Vector3.new(-1.3, -1.0, 0.3), Vector3.new(1.1, -1.0, -0.8), Vector3.new(1.3, -1.0, 0.3) }
for index, offset in ipairs(legOffsets) do
	local sign = offset.X < 0 and -1 or 1
	newPart(
		"Leg" .. index,
		Vector3.new(0.22, 0.85, 0.22),
		rootCFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(sign * 28)),
		LEG_COLOR,
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

print("[Abyssara] Shopkeeper (Shelly) built under Workspace.Assets.Npcs")
