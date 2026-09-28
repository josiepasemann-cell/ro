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

-- Organisches, ovales Teil: Block-Part + SpecialMesh(Sphere), non-uniform
-- Size -> gestrecktes Ellipsoid statt Kiste (weicher, kartoonig runder Oktopus).
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

-- 1) Body: big, soft, bulbous mantle (chunky cartoon ellipsoid) ------------
local body = newOvalPart("Body", Vector3.new(3.4, 3.7, 3.2), rootCFrame, MANTLE_COLOR, Enum.Material.Marble, model)

-- Glowing "age ring" wrinkles on the mantle
newOvalPart("MantleGlowRing", Vector3.new(3.15, 0.2, 3.15), rootCFrame * CFrame.new(0, 0.3, 0), NEON_VIOLET, Enum.Material.Neon, model)
newOvalPart("MantleGlowRing2", Vector3.new(2.8, 0.16, 2.8), rootCFrame * CFrame.new(0, -0.5, 0), NEON_VIOLET, Enum.Material.Neon, model)

-- 2) Head: oversized round bump perched at the front-top of the mantle ----------
local head = newOvalPart("Head", Vector3.new(1.8, 1.3, 1.5), rootCFrame * CFrame.new(0, 1.4, 0.95), MANTLE_COLOR_LIGHT, Enum.Material.Marble, model)

-- Big, kind, wide cartoon eyes with pupils + highlights (named, movable for blink)
local eye1 = newPart("Eye1", Vector3.new(0.7, 0.7, 0.34), rootCFrame * CFrame.new(-0.42, 1.42, 1.62), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye1.Shape = Enum.PartType.Ball
local eye2 = newPart("Eye2", Vector3.new(0.7, 0.7, 0.34), rootCFrame * CFrame.new(0.42, 1.42, 1.62), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic, model)
eye2.Shape = Enum.PartType.Ball
for _, side in ipairs({ -1, 1 }) do
	local pupilCFrame = rootCFrame * CFrame.new(side * 0.42, 1.42, 1.78)
	local pupil = newPart("EyePupil" .. (side < 0 and "L" or "R"), Vector3.new(0.3, 0.3, 0.18), pupilCFrame, Color3.fromRGB(60, 40, 90), Enum.Material.SmoothPlastic, model)
	pupil.Shape = Enum.PartType.Ball
	local glint = newPart("EyeGlint" .. (side < 0 and "L" or "R"), Vector3.new(0.1, 0.1, 0.06), pupilCFrame * CFrame.new(0.09, 0.09, 0.06), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	glint.Shape = Enum.PartType.Ball
end

-- Wise old spectacles (readable "elder" prop): two thin round lens rims + a bridge
newPart("SpecsLensL", Vector3.new(0.62, 0.62, 0.06), rootCFrame * CFrame.new(-0.42, 1.42, 1.7), Color3.fromRGB(230, 225, 210), Enum.Material.Glass, model).Shape = Enum.PartType.Ball
newPart("SpecsLensR", Vector3.new(0.62, 0.62, 0.06), rootCFrame * CFrame.new(0.42, 1.42, 1.7), Color3.fromRGB(230, 225, 210), Enum.Material.Glass, model).Shape = Enum.PartType.Ball
newPart("SpecsBridge", Vector3.new(0.4, 0.08, 0.08), rootCFrame * CFrame.new(0, 1.42, 1.71), Color3.fromRGB(210, 200, 180), Enum.Material.Foil, model)

-- 3) Two primary tentacles: tapering chains of overlapping ellipsoids (movable) --
for _, spec in ipairs({ { name = "ArmL", side = -1 }, { name = "ArmR", side = 1 } }) do
	local baseCFrame = rootCFrame * CFrame.new(spec.side * 1.6, -1.0, 0.4) * CFrame.Angles(math.rad(10), 0, math.rad(spec.side * 14))
	local arm = newOvalPart(spec.name, Vector3.new(0.6, 1.3, 0.6), baseCFrame, TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)
	newOvalPart(spec.name .. "Tip", Vector3.new(0.42, 1.2, 0.42), baseCFrame * CFrame.new(0, -1.15, 0) * CFrame.Angles(math.rad(spec.side * 6), 0, 0), TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 4) Four more hanging tentacles: tapering two-segment ellipsoid chains ---------
local tentacleOffsets = { Vector3.new(-0.8, -2.2, -1.0), Vector3.new(0.8, -2.2, -1.0), Vector3.new(-1.3, -2.1, -0.3), Vector3.new(1.3, -2.1, -0.3) }
for index, offset in ipairs(tentacleOffsets) do
	local sign = offset.X < 0 and -1 or 1
	local segCFrame = rootCFrame * CFrame.new(offset) * CFrame.Angles(math.rad(6), 0, math.rad(sign * 8))
	newOvalPart("Tentacle" .. index, Vector3.new(0.5, 1.1, 0.5), segCFrame, TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)
	newOvalPart("Tentacle" .. index .. "Tip", Vector3.new(0.34, 1.1, 0.34), segCFrame * CFrame.new(0, -1.0, 0), TENTACLE_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 5) A guarded mystery egg (big, round) cradled between the front tentacles -----
local egg = newPart("GuardedEgg", Vector3.new(0.9, 1.1, 0.9), rootCFrame * CFrame.new(0, -1.5, 1.0), Color3.fromRGB(220, 200, 255), Enum.Material.SmoothPlastic, model)
egg.Shape = Enum.PartType.Ball
newOvalPart("GuardedEggBand", Vector3.new(0.94, 0.18, 0.94), rootCFrame * CFrame.new(0, -1.35, 1.0), NEON_VIOLET, Enum.Material.Neon, model)

model.PrimaryPart = body
model:SetAttribute("NpcId", NPC_ID)
model:SetAttribute("DisplayName", DISPLAY_NAME)
model:SetAttribute("StandInteractable", STAND_INTERACTABLE)
model:SetAttribute("SpeechHeight", SPEECH_HEIGHT)
CollectionService:AddTag(model, "NpcAmbient")

print("[Abyssara] Egg Keeper (Inky) built under Workspace.Assets.Npcs")
