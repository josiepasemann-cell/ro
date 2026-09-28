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

-- Organisches, ovales Teil: Block-Part + SpecialMesh(Sphere), non-uniform
-- Size -> gestrecktes Ellipsoid statt Kiste (rundlicher Kartoon-Seepferdchen-Look).
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

-- 1) Body: upright seahorse torso, built from overlapping round ellipsoid
--    segments (belly, chest, upper chest) - chunky, tapering silhouette -------
-- NOTE: -Z is the model's front (LookVector side, faces the hub stand/camera,
-- see computeStandAnchorCFrame's CFrame.lookAt above) - snout/face/hat sit on
-- -Z, the curled tail + dorsal fin sit on +Z (behind), giving a readable
-- upright seahorse silhouette from the front.
local body = newOvalPart("Body", Vector3.new(1.55, 1.9, 1.5), rootCFrame * CFrame.new(0, -0.5, 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)
newOvalPart("UpperChest", Vector3.new(1.2, 1.25, 1.15), rootCFrame * CFrame.new(0, 0.55, 0.05), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- Ridged belly plates (small overlapping flattened ellipsoids down the front)
for i = 1, 4 do
	local y = -1.1 + (i - 1) * 0.45
	newOvalPart(
		"BellyPlate" .. i,
		Vector3.new(1.0, 0.36, 0.4),
		rootCFrame * CFrame.new(0, y, -0.62),
		BODY_COLOR_LIGHT,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- Curled tail (three tapering, overlapping ellipsoid segments coiling behind the body)
local tailSegments = {
	{ pos = Vector3.new(0, -1.55, 0.35), size = Vector3.new(0.9, 0.9, 0.95) },
	{ pos = Vector3.new(0, -2.15, 0.95), size = Vector3.new(0.65, 0.8, 0.75) },
	{ pos = Vector3.new(0.05, -2.35, 1.55), size = Vector3.new(0.45, 0.6, 0.55) },
}
for i, spec in ipairs(tailSegments) do
	newOvalPart(
		"TailCurl" .. i,
		spec.size,
		rootCFrame * CFrame.new(spec.pos),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- Neon dorsal fin along the back: thin, flattened, fanned ellipsoids --------------
newOvalPart("DorsalFin", Vector3.new(0.18, 1.5, 0.6), rootCFrame * CFrame.new(0, 0.2, 0.55), NEON_GREEN, Enum.Material.SmoothPlastic, model)
newOvalPart("DorsalFinTip", Vector3.new(0.15, 0.8, 0.42), rootCFrame * CFrame.new(0, 1.1, 0.65), NEON_GREEN, Enum.Material.SmoothPlastic, model)

-- 2) Head: big, round cartoon seahorse snout, overlapping the upper chest --------
local head = newOvalPart("Head", Vector3.new(1.0, 0.9, 1.6), rootCFrame * CFrame.new(0, 1.3, -0.55), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- Snout crest ridge (small thin fin running along the snout)
newOvalPart("SnoutCrest", Vector3.new(0.16, 0.24, 1.1), rootCFrame * CFrame.new(0, 1.62, -0.65), NEON_GREEN, Enum.Material.SmoothPlastic, model)

-- Big cartoon eyes: white eyeball, big pupil, highlight (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.42, 0.42, 0.24), rootCFrame * CFrame.new(-0.28, 1.46, -0.65), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.42, 0.42, 0.24), rootCFrame * CFrame.new(0.28, 1.46, -0.65), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball
for _, side in ipairs({ -1, 1 }) do
	local pupilCFrame = rootCFrame * CFrame.new(side * 0.29, 1.46, -0.78)
	newPart("EyePupil" .. (side < 0 and "L" or "R"), Vector3.new(0.2, 0.2, 0.12), pupilCFrame, EYE_COLOR, Enum.Material.SmoothPlastic, model).Shape = Enum.PartType.Ball
	newPart("EyeHighlight" .. (side < 0 and "1" or "2"), Vector3.new(0.09, 0.09, 0.08), pupilCFrame * CFrame.new(0.08, 0.08, -0.05), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model).Shape = Enum.PartType.Ball
end

-- Friendly captain's smile (small dark ellipsoid arc under the snout tip)
newOvalPart("Mouth", Vector3.new(0.34, 0.1, 0.12), rootCFrame * CFrame.new(0, 1.1, -1.12), Color3.fromRGB(50, 35, 32), Enum.Material.SmoothPlastic, model)

-- Rosy cheek blush (friendly cartoon captain)
for _, side in ipairs({ -1, 1 }) do
	local blush = newPart("Blush" .. (side < 0 and "L" or "R"), Vector3.new(0.28, 0.18, 0.06), rootCFrame * CFrame.new(side * 0.42, 1.24, -0.85), Color3.fromRGB(255, 150, 150), Enum.Material.SmoothPlastic, model)
	blush.Shape = Enum.PartType.Ball
	blush.Transparency = 0.35
end

-- Rounded captain's hat (dome crown + brim ellipsoids, not a boxy wedge) --------
local hatCrown = newOvalPart("CaptainHat", Vector3.new(1.15, 0.85, 1.1), rootCFrame * CFrame.new(0, 1.95, -0.35) * CFrame.Angles(0, math.rad(180), 0), HAT_COLOR, Enum.Material.Fabric, model)
newOvalPart("HatBrim", Vector3.new(1.35, 0.24, 1.35), rootCFrame * CFrame.new(0, 1.55, -0.4), HAT_COLOR, Enum.Material.Fabric, model)
newOvalPart("HatTrim", Vector3.new(1.2, 0.1, 1.2), rootCFrame * CFrame.new(0, 1.66, -0.4), NEON_GREEN, Enum.Material.SmoothPlastic, model)
local hatBadge = newPart("HatBadge", Vector3.new(0.36, 0.36, 0.12), rootCFrame * CFrame.new(0, 1.95, -0.82), Color3.fromRGB(255, 210, 60), Enum.Material.Neon, model)
hatBadge.Shape = Enum.PartType.Ball
newTexture("GoldFoil", Enum.NormalId.Front, hatCrown, { studsU = 1, studsV = 1, color = Color3.fromRGB(230, 200, 120), transparency = 0.55 })

-- 3) Side fins (named, movable for the salute/wave gesture): thin fanned ellipsoids
local armL = newOvalPart("ArmL", Vector3.new(0.2, 0.95, 0.65), rootCFrame * CFrame.new(-0.85, 0.4, 0.05) * CFrame.Angles(0, 0, math.rad(18)), NEON_GREEN, Enum.Material.SmoothPlastic, model)
local armR = newOvalPart("ArmR", Vector3.new(0.2, 0.95, 0.65), rootCFrame * CFrame.new(0.85, 0.4, 0.05) * CFrame.Angles(0, 0, math.rad(-18)), NEON_GREEN, Enum.Material.SmoothPlastic, model)

-- Oversized satchel of scrolls slung on the hip (readable "quest giver" prop)
local satchel = newPart("Satchel", Vector3.new(0.7, 0.75, 0.5), rootCFrame * CFrame.new(0.6, -0.78, 0.15) * CFrame.Angles(0, 0, math.rad(-10)), Color3.fromRGB(120, 90, 55), Enum.Material.Fabric, model)
newOvalPart("SatchelStrap", Vector3.new(0.16, 1.35, 0.18), rootCFrame * CFrame.new(0.25, -0.05, 0.1) * CFrame.Angles(0, 0, math.rad(28)), Color3.fromRGB(90, 65, 38), Enum.Material.Fabric, model)
newPart("ScrollTip", Vector3.new(0.18, 0.4, 0.18), rootCFrame * CFrame.new(0.6, -0.45, 0.15), Color3.fromRGB(235, 220, 175), Enum.Material.SmoothPlastic, model).Shape = Enum.PartType.Cylinder
newTexture("WoodPlanks", Enum.NormalId.Front, satchel, { studsU = 1, studsV = 1, color = Color3.fromRGB(95, 68, 38), transparency = 0.4 })

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Quest Giver (Captain Finn) built under Workspace.Assets.Npcs")
