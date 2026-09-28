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

-- Organisches, ovales Teil: Block-Part + SpecialMesh(Sphere), non-uniform
-- Size -> gestrecktes Ellipsoid statt Kiste (rundlicher Kartoon-Clownfisch).
local function newOvalPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
	return part
end

-- Texture-Instanz mit Projekt-Texturschlüssel (siehe assets/textures/README.md).
local function newTexture(key: string, face: Enum.NormalId, part: Instance, opts: { studsU: number?, studsV: number?, color: Color3?, transparency: number? }?): Texture
	local o = opts or {}
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = o.studsU or 3
	tex.StudsPerTileV = o.studsV or 3
	tex.Color3 = o.color or Color3.new(1, 1, 1)
	tex.Transparency = o.transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = part
	return tex
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

-- 1) Body: big, round, chunky cartoon clownfish body -----------------------
local body = newOvalPart("Body", Vector3.new(2.9, 2.3, 3.2), rootCFrame, BODY_ORANGE, Enum.Material.SmoothPlastic, model)

-- Classic white stripes (flattened ellipsoid bands)
newOvalPart("StripeWhite1", Vector3.new(2.75, 0.44, 0.32), rootCFrame * CFrame.new(0, 0, 0.6), STRIPE_WHITE, Enum.Material.SmoothPlastic, model)
newOvalPart("StripeWhite2", Vector3.new(2.6, 0.44, 0.32), rootCFrame * CFrame.new(0, 0.05, -0.4), STRIPE_WHITE, Enum.Material.SmoothPlastic, model)

-- Dorsal fin (static decoration): thin flattened ellipsoid, neon-trimmed
newOvalPart("DorsalFin", Vector3.new(1.0, 0.16, 0.85), rootCFrame * CFrame.new(0, 1.1, -0.3), NEON_GREEN, Enum.Material.Neon, model)

-- Tail stalk bridges the body -> tail fin gap (round ellipsoid connector)
newOvalPart("TailStalk", Vector3.new(0.8, 0.8, 1.05), rootCFrame * CFrame.new(0, 0, -1.2), BODY_ORANGE, Enum.Material.SmoothPlastic, model)
newOvalPart("TailFin", Vector3.new(0.16, 1.15, 0.85), rootCFrame * CFrame.new(0, 0, -1.65), NEON_GREEN, Enum.Material.Neon, model)
newOvalPart("TailFinTip", Vector3.new(0.14, 0.75, 0.58), rootCFrame * CFrame.new(0, 0, -1.8), STRIPE_WHITE, Enum.Material.Neon, model)

-- 2) Head: big round nose bump at the front ------------------------------------
local head = newOvalPart("Head", Vector3.new(1.05, 1.15, 0.8), rootCFrame * CFrame.new(0, 0.05, 1.35), BODY_ORANGE_LIGHT, Enum.Material.SmoothPlastic, model)

-- Big cartoon eyes: white eyeball, big pupil, highlight (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.44, 0.44, 0.3), rootCFrame * CFrame.new(-0.36, 0.22, 1.6), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.44, 0.44, 0.3), rootCFrame * CFrame.new(0.36, 0.22, 1.6), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball
for _, side in ipairs({ -1, 1 }) do
	local pupilCFrame = rootCFrame * CFrame.new(side * 0.37, 0.22, 1.76)
	newPart("EyePupil" .. (side < 0 and "L" or "R"), Vector3.new(0.22, 0.22, 0.14), pupilCFrame, EYE_COLOR, Enum.Material.SmoothPlastic, model).Shape = Enum.PartType.Ball
	newPart("EyeGlint" .. (side < 0 and "L" or "R"), Vector3.new(0.09, 0.09, 0.06), pupilCFrame * CFrame.new(0.08, 0.08, 0.05), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model).Shape = Enum.PartType.Ball
end

-- 3) Pectoral fins (named, movable for waving): thin fanned ellipsoids -----------
local armL = newOvalPart("ArmL", Vector3.new(0.18, 0.65, 0.95), rootCFrame * CFrame.new(-1.35, -0.2, 0.3) * CFrame.Angles(0, 0, math.rad(20)), NEON_GREEN, Enum.Material.Neon, model)
local armR = newOvalPart("ArmR", Vector3.new(0.18, 0.65, 0.95), rootCFrame * CFrame.new(1.35, -0.2, 0.3) * CFrame.Angles(0, 0, math.rad(-20)), NEON_GREEN, Enum.Material.Neon, model)

-- 4) Small trade crate resting against the body (readable "trader" prop) --------
local crate = newPart("TradeCrate", Vector3.new(0.95, 0.9, 0.95), rootCFrame * CFrame.new(0, -0.9, 0.95), Color3.fromRGB(150, 108, 60), Enum.Material.WoodPlanks, model)
local crateBand = newPart("TradeCrateBandX", Vector3.new(1.0, 0.16, 1.0), rootCFrame * CFrame.new(0, -0.9, 0.95), Color3.fromRGB(90, 62, 32), Enum.Material.CorrodedMetal, model)
newPart("TradeCrateGem", Vector3.new(0.34, 0.34, 0.34), rootCFrame * CFrame.new(0, -0.48, 0.95), NEON_GREEN, Enum.Material.Neon, model).Shape = Enum.PartType.Ball
newTexture("WoodPlanks", Enum.NormalId.Front, crate, { studsU = 0.6, studsV = 0.6, color = Color3.fromRGB(100, 70, 38), transparency = 0.4 })
newTexture("MetalPanels", Enum.NormalId.Front, crateBand, { studsU = 0.8, studsV = 0.8, color = Color3.fromRGB(60, 42, 22) })

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Trader (Splash) built under Workspace.Assets.Npcs")
