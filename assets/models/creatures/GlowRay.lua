--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowRay ("Leuchtrochen") - freie 6. Kreatur des MVP-Sets
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Flacher, rautenförmiger Rochenkörper (per CSG-Union aus zwei
		Keil-Parts "verschmolzen") mit heller Rückenzeichnung, dunklerer
		Unterseite, spitzen Flossenzacken, kleinen Kiemenschlitzen, einem
		dünnen Peitschenschwanz mit Giftstachel und leuchtendem Kantenrand.
		Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (der Rautenkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- Teile "SideFin1"/"SideFin2" werden von IdleSway automatisch geschwenkt.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(12, 5, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Uncommon"
local ZONE = "SunZone"
-- // ----------------------------------------------------------------------

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function newPart(name, size, cframe, color, material, parent)
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GlowRay")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowRay"
model.Parent = creaturesFolder

local RAY_COLOR = Color3.fromRGB(120, 150, 255)
local BELLY_COLOR = Color3.fromRGB(70, 90, 170)
local GLOW_COLOR = Color3.fromRGB(140, 220, 255)

-- 1) Rautenkörper per CSG-Union aus zwei Wedge-Parts -------------------------
local wedgeFrontCFrame = ORIGIN * CFrame.new(0, 0, 1.4)
local wedgeFront = Instance.new("WedgePart")
wedgeFront.Name = "WedgeFront"
wedgeFront.Size = Vector3.new(3.2, 0.6, 2.8)
wedgeFront.CFrame = wedgeFrontCFrame * CFrame.Angles(0, math.rad(180), 0)
wedgeFront.Color = RAY_COLOR
wedgeFront.Material = Enum.Material.SmoothPlastic
wedgeFront.Anchored = true
wedgeFront.Parent = Workspace

local wedgeBackCFrame = ORIGIN * CFrame.new(0, 0, -1.4)
local wedgeBack = Instance.new("WedgePart")
wedgeBack.Name = "WedgeBack"
wedgeBack.Size = Vector3.new(3.2, 0.6, 2.8)
wedgeBack.CFrame = wedgeBackCFrame
wedgeBack.Color = RAY_COLOR
wedgeBack.Material = Enum.Material.SmoothPlastic
wedgeBack.Anchored = true
wedgeBack.Parent = Workspace

local body = wedgeFront:UnionAsync({ wedgeBack })
body.Name = "Body"
body.Color = RAY_COLOR
body.Material = Enum.Material.SmoothPlastic
body.Anchored = true
body.CanCollide = false
body.Parent = model

-- 2) Dunklere Unterseiten-Platte (klar von oben abgesetzt) --------------------
local belly = newPart("Belly", Vector3.new(2.6, 0.18, 2.2), ORIGIN * CFrame.new(0, -0.24, 0), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Leuchtender Kantenrand (dünner Ring unter dem Körper) -------------------
local rim = newPart("GlowRim", Vector3.new(3.4, 0.12, 3.0), ORIGIN * CFrame.new(0, -0.3, 0), GLOW_COLOR, Enum.Material.Neon, model)
rim.Transparency = 0.1

-- 4) Spitze Flossenzacken an den 4 Rauten-Ecken --------------------------------
local tipOffsets = {
	{ 1.55, 0 },
	{ -1.55, 0 },
	{ 0, 2.55 },
	{ 0, -2.35 },
}
for i, off in ipairs(tipOffsets) do
	local tip = Instance.new("WedgePart")
	tip.Name = "FinTip" .. i
	tip.Size = Vector3.new(0.5, 0.22, 0.7)
	local dir = Vector3.new(off[1], 0, off[2])
	local ang = math.atan2(off[1], off[2])
	tip.CFrame = ORIGIN * CFrame.new(off[1] * 0.85, -0.02, off[2] * 0.85) * CFrame.Angles(0, ang, 0)
	tip.Color = RAY_COLOR
	tip.Material = Enum.Material.SmoothPlastic
	tip.Anchored = true
	tip.CanCollide = false
	tip.Parent = model
end

-- 5) Zwei "flatternde" Seitenflossenkanten (dünne Glow-Streifen, animierbar) --
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"SideFin" .. i,
		Vector3.new(1.3, 0.1, 0.9),
		ORIGIN * CFrame.new(side * 1.35, 0.05, 0.4) * CFrame.Angles(0, 0, math.rad(side * 8)),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
	fin.Transparency = 0.35
end

-- 6) Rückenzeichnung: helle Neon-Sprenkel ---------------------------------------
local spotOffsets = { { 0.6, 0.6 }, { -0.6, 0.6 }, { 0.5, -0.4 }, { -0.5, -0.4 }, { 0, 1.2 } }
for i, off in ipairs(spotOffsets) do
	newBall("Spot" .. i, Vector3.new(0.22, 0.1, 0.22), ORIGIN * CFrame.new(off[1], 0.3, off[2]), GLOW_COLOR, Enum.Material.Neon, model)
end

-- 7) Kleine Kiemenschlitze auf der Unterseite -----------------------------------
for i = 1, 5 do
	local x = -0.8 + (i - 1) * 0.4
	newPart("GillSlit" .. i, Vector3.new(0.08, 0.05, 0.35), ORIGIN * CFrame.new(x, -0.32, 0.9), Color3.fromRGB(40, 45, 70), Enum.Material.SmoothPlastic, model)
end

-- 8) Peitschenschwanz (3 sich verjüngende, überlappende Segmente) --------------
local currentCFrame = ORIGIN * CFrame.new(0, 0, -2.5)
local prevHalfZ = 0.3
for i = 1, 3 do
	local segLength = 1.3 - i * 0.12
	local width = 0.32 - i * 0.06
	local halfZ = segLength / 2
	local overlap = 0.16
	currentCFrame = currentCFrame * CFrame.new(0, 0, -(prevHalfZ + halfZ - overlap))
	newPart("TailSegment" .. i, Vector3.new(width, width, segLength), currentCFrame, RAY_COLOR, Enum.Material.SmoothPlastic, model)
	prevHalfZ = halfZ
end

-- Giftstachel an der Schwanzspitze
local barbCFrame = currentCFrame * CFrame.new(0, 0, -(prevHalfZ + 0.15 - 0.12))
local barb = Instance.new("WedgePart")
barb.Name = "TailTip"
barb.Size = Vector3.new(0.18, 0.18, 0.5)
barb.CFrame = barbCFrame
barb.Color = Color3.fromRGB(230, 230, 235)
barb.Material = Enum.Material.SmoothPlastic
barb.Anchored = true
barb.CanCollide = false
barb.Parent = model

-- 9) Zwei kleine Augen (Glow) --------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.5, 0.16, 1.3)
	newBall("Eye" .. i, Vector3.new(0.26, 0.24, 0.26), eyeCFrame, Color3.fromRGB(20, 20, 25), Enum.Material.Neon, model)
end

-- 10) Idle-Puls-Attachment -----------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Ray")

print("[Abyssara] GlowRay created under Workspace.Assets.Creatures")
