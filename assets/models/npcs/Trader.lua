--[[
	Abyssara – Deep Tide Tycoon
	Asset Type: Hub NPC
	Name: Trader ("Splash the Trader")
	Description:
		A cheerful clownfish who greets players at the Trade Dock
		("TradeDock", Interactable = "Trade") in the "Tidal Market" hub.
		Non-humanoid, low-poly, phone-friendly part count (~10 parts).

	STAND ANCHOR LOGIC (read before editing):
		This script looks up Workspace.Assets.Hub.TidalMarketHub, finds the
		sub-model whose "Interactable" attribute equals STAND_INTERACTABLE
		below, and reads its "InteractionPoint" Attachment (the spot where a
		player's ProximityPrompt fires, see assets/models/hub/TidalMarketHub.lua
		and README.md "hub" section). Splash is placed to the SIDE of that
		point (a sideways + slightly-inward offset in the attachment's own
		local space, so it stays correct even if the hub's orientation ever
		changes) so he never blocks the prompt or the two trade podiums.
		If the hub hasn't been built yet, a documented fixed offset from the
		hub's landmark origin (CFrame.new(-500, 2, -500), see TidalMarketHub.lua
		ORIGIN/PLAZA_TOP_Y) is used instead, roughly where the TradeDock ends
		up once the hub is built (STAND_RING_RADIUS = 58, TradeDock offset
		(-58*0.15, 58*1.05) plus a few studs toward the dock entrance).

	NAMING CONVENTION FOR THE ANIMATOR (src/client/NpcAmbientController.client.lua):
		- Model.PrimaryPart = "Body"
		- Attributes: "NpcId", "DisplayName", "StandInteractable", "SpeechHeight"
		- Movable named parts (direct children of the model, siblings of
		  Body): "Head", "ArmL", "ArmR", "Eye1", "Eye2" – the ambient
		  controller captures their rest offset relative to Body once, then
		  animates bob/sway (whole model via Model:PivotTo), head-turn,
		  arm-wave and eye-blink on top of that rest pose. Here ArmL/ArmR are
		  the pectoral fins used for the wave gesture.

	RUN:
		Paste into the Roblox Studio Command Bar (or a temporary Script under
		ServerScriptService) and run once. Pure geometry, no gameplay logic.
		Idempotent: an existing "Trader" model is removed before rebuild.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Configuration ---------------------------------------------------------
local NPC_ID = "Trader"
local DISPLAY_NAME = "Splash"
local STAND_INTERACTABLE = "Trade"
local SIDE_OFFSET = -5
local FORWARD_OFFSET = -2
local FALLBACK_OFFSET = Vector3.new(-14.7, 0, 63.9) -- see STAND ANCHOR LOGIC above
local SPEECH_HEIGHT = 4.2
local BODY_HEIGHT = 1.4 -- studs: body center height above the ground anchor
-- // ------------------------------------------------------------------------

local NEON_GREEN = Color3.fromRGB(130, 255, 60)
local BODY_ORANGE = Color3.fromRGB(255, 140, 50)
local BODY_ORANGE_LIGHT = Color3.fromRGB(255, 170, 100)
local STRIPE_WHITE = Color3.fromRGB(245, 248, 250)
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

-- 1) Body: round clownfish body -------------------------------------------
local body = newPart("Body", Vector3.new(2.6, 2.0, 3.0), rootCFrame, BODY_ORANGE, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- Classic white stripes
newPart("StripeWhite1", Vector3.new(2.65, 0.4, 0.3), rootCFrame * CFrame.new(0, 0, 0.6), STRIPE_WHITE, Enum.Material.SmoothPlastic, model)
newPart("StripeWhite2", Vector3.new(2.5, 0.4, 0.3), rootCFrame * CFrame.new(0, 0.05, -0.4), STRIPE_WHITE, Enum.Material.SmoothPlastic, model)

-- Dorsal + tail fins (static decoration), neon-trimmed to match the dock
newWedge("DorsalFin", Vector3.new(0.9, 0.14, 0.8), rootCFrame * CFrame.new(0, 1.05, -0.3) * CFrame.Angles(0, math.rad(90), 0), NEON_GREEN, Enum.Material.Neon, model)
newWedge("TailFin", Vector3.new(0.8, 1.1, 0.14), rootCFrame * CFrame.new(0, 0, -1.55) * CFrame.Angles(0, 0, math.rad(90)), NEON_GREEN, Enum.Material.Neon, model)

-- 2) Head: small nose bump at the front ------------------------------------
local head = newPart("Head", Vector3.new(0.9, 1.0, 0.7), rootCFrame * CFrame.new(0, 0.05, 1.3), BODY_ORANGE_LIGHT, Enum.Material.SmoothPlastic, model)
head.Shape = Enum.PartType.Ball

-- Eyes (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.3, 0.3, 0.3), rootCFrame * CFrame.new(-0.32, 0.2, 1.55), EYE_COLOR, Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.3, 0.3, 0.3), rootCFrame * CFrame.new(0.32, 0.2, 1.55), EYE_COLOR, Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball

-- 3) Pectoral fins (named, movable for waving) -----------------------------
local armL = newPart("ArmL", Vector3.new(0.14, 0.6, 0.9), rootCFrame * CFrame.new(-1.3, -0.2, 0.3) * CFrame.Angles(0, 0, math.rad(20)), NEON_GREEN, Enum.Material.Neon, model)
local armR = newPart("ArmR", Vector3.new(0.14, 0.6, 0.9), rootCFrame * CFrame.new(1.3, -0.2, 0.3) * CFrame.Angles(0, 0, math.rad(-20)), NEON_GREEN, Enum.Material.Neon, model)

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Trader (Splash) built under Workspace.Assets.Npcs")
