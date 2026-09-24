--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Öffnungs-VFX-Rig (wiederverwendbares Effekt-Modell)
	Name: GachaEggOpenVFX
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)" -> "Öffnungs-VFX (Schalenriss-Partikel,
	Lichtexplosion, Rarity-farbiger Strahl)".
	Beschreibung:
		Reines Platzhalter-Effekt-Rig: ein unsichtbares Trägermodell mit
		bereits verkabeltem ParticleEmitter-/Beam-/Light-Setup für die
		Ei-Öffnungs-Zeremonie. Enthält KEINE eigene Animation/Abspiel-Logik –
		alle Emitter, der Beam und das Licht sind standardmäßig deaktiviert
		(Enabled = false), damit der Code-Agent sie später sauber gezielt
		an- und wieder ausschalten kann (z. B. Emitter:Emit(n) / Enabled = true
		für X Sekunden).

		Gedachter Einsatz durch den späteren Code-Agenten:
		1) Rig-Klon an die Position/CFrame des sich öffnenden Eis andocken
		   (z. B. WeldConstraint/PivotTo auf Egg-Model.Shell).
		2) "RarityBeam".Color (und ggf. "LightExplosionEmitter".Color /
		   "ShineBurst".Color) passend zur gerollten Rarity setzen.
		3) Emitter kurzzeitig Enabled = true schalten bzw. :Emit() aufrufen,
		   "RarityBeam".Enabled = true für die Dauer des Strahls, danach
		   wieder deaktivieren bzw. Rig aufräumen.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "EffectCore" (unsichtbarer, zentraler Anker-Part)
		  -> Ansatzpunkt zum Andocken/Positionieren des gesamten Rigs.
		- ParticleEmitter "ShellCrackEmitter" (an Attachment "ShellCrackPoint",
		  Kind von EffectCore) -> Platzhalter für Schalenriss-/Splitterpartikel.
		- ParticleEmitter "LightExplosionEmitter" (an Attachment
		  "LightBurstPoint", Kind von EffectCore) -> Platzhalter für die
		  Lichtexplosion beim Schlupf-Moment.
		- PointLight "ShineBurst" (an EffectCore) -> kurzer Licht-Blitz,
		  begleitend zur Lichtexplosion.
		- Beam "RarityBeam" (zwischen Attachments "BeamBase" auf Part
		  "BeamAnchorBottom" und "BeamTop" auf Part "BeamAnchorTop") ->
		  vertikaler, rarity-farbiger Strahl. Farbe ist hier nur ein neutraler
		  Cyan/Violett-Platzhalter-Gradient und wird vom Code-Agenten je
		  gerollter Rarity überschrieben.
		- ALLE Emitter/Beam/Light starten mit Enabled = false. Dieses Skript
		  spielt selbst NICHTS ab und enthält keine Zufalls-/Gacha-Logik.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script
		unter ServerScriptService einfügen und einmal laufen lassen. Reine
		Geometrie-/Effekt-Rig-Erzeugung, keine Gameplay-Logik. Wiederholtes
		Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(76, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local BEAM_HEIGHT = 14 -- Höhe des Strahl-Ankerpunkts über dem Ei
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

local function newAnchorPart(name, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local gachaFolder = getOrCreateFolder(assetsFolder, "Gacha")

local previous = gachaFolder:FindFirstChild("GachaEggOpenVFX")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GachaEggOpenVFX"
model.Parent = gachaFolder

-- Neutrale Platzhalter-Farben (Cyan/Violett-Biolumineszenz-Palette).
-- Der Code-Agent überschreibt diese je nach gerollter Rarity.
local PLACEHOLDER_CYAN = Color3.fromRGB(120, 235, 255)
local PLACEHOLDER_VIOLET = Color3.fromRGB(190, 120, 255)

-- 1) Zentraler, unsichtbarer Anker-Part (PrimaryPart) ------------------------
local effectCore = newAnchorPart("EffectCore", ORIGIN, model)

-- 2) Schalenriss-Partikel-Emitter (Splitter/Funken beim Aufbrechen) ---------
local crackAttachment = Instance.new("Attachment")
crackAttachment.Name = "ShellCrackPoint"
crackAttachment.Parent = effectCore

local shellCrackEmitter = Instance.new("ParticleEmitter")
shellCrackEmitter.Name = "ShellCrackEmitter"
shellCrackEmitter.Color = ColorSequence.new(PLACEHOLDER_CYAN)
shellCrackEmitter.Lifetime = NumberRange.new(0.4, 0.9)
shellCrackEmitter.Speed = NumberRange.new(6, 14)
shellCrackEmitter.SpreadAngle = Vector2.new(180, 180)
shellCrackEmitter.Rate = 0 -- kein Dauer-Rieseln; Code-Agent löst per :Emit(n) aus
shellCrackEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(1, 0),
})
shellCrackEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})
shellCrackEmitter.Enabled = false
shellCrackEmitter.Parent = crackAttachment

-- 3) Lichtexplosions-Partikel-Emitter (großer, kurzer Blitz-Burst) ----------
local burstAttachment = Instance.new("Attachment")
burstAttachment.Name = "LightBurstPoint"
burstAttachment.Parent = effectCore

local lightExplosionEmitter = Instance.new("ParticleEmitter")
lightExplosionEmitter.Name = "LightExplosionEmitter"
lightExplosionEmitter.Color = ColorSequence.new(PLACEHOLDER_VIOLET, PLACEHOLDER_CYAN)
lightExplosionEmitter.Lifetime = NumberRange.new(0.3, 0.6)
lightExplosionEmitter.Speed = NumberRange.new(10, 22)
lightExplosionEmitter.SpreadAngle = Vector2.new(360, 360)
lightExplosionEmitter.Rate = 0 -- Burst statt Dauerpartikel; Code-Agent löst per :Emit(n) aus
lightExplosionEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1.2),
	NumberSequenceKeypoint.new(1, 0),
})
lightExplosionEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 1),
})
lightExplosionEmitter.Enabled = false
lightExplosionEmitter.Parent = burstAttachment

-- 4) Begleitender Licht-Blitz (kurzer PointLight-Flash) ----------------------
local shineBurst = Instance.new("PointLight")
shineBurst.Name = "ShineBurst"
shineBurst.Color = PLACEHOLDER_CYAN
shineBurst.Range = 20
shineBurst.Brightness = 4
shineBurst.Enabled = false
shineBurst.Parent = effectCore

-- 5) Rarity-farbiger vertikaler Strahl (Beam zwischen zwei Anker-Parts) -----
local beamAnchorBottom = newAnchorPart("BeamAnchorBottom", ORIGIN, model)
local beamAnchorTop = newAnchorPart("BeamAnchorTop", ORIGIN * CFrame.new(0, BEAM_HEIGHT, 0), model)

local beamAttachmentBottom = Instance.new("Attachment")
beamAttachmentBottom.Name = "BeamBase"
beamAttachmentBottom.Parent = beamAnchorBottom

local beamAttachmentTop = Instance.new("Attachment")
beamAttachmentTop.Name = "BeamTop"
beamAttachmentTop.Parent = beamAnchorTop

local rarityBeam = Instance.new("Beam")
rarityBeam.Name = "RarityBeam"
rarityBeam.Attachment0 = beamAttachmentBottom
rarityBeam.Attachment1 = beamAttachmentTop
rarityBeam.Color = ColorSequence.new(PLACEHOLDER_CYAN, PLACEHOLDER_VIOLET)
rarityBeam.Width0 = 2.2
rarityBeam.Width1 = 0.4
rarityBeam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
rarityBeam.LightEmission = 1
rarityBeam.FaceCamera = true
rarityBeam.Enabled = false
rarityBeam.Parent = effectCore

model.PrimaryPart = effectCore

print("[Abyssara] GachaEggOpenVFX created under Workspace.Assets.Gacha (all Emitter/Beam/Light: Enabled = false)")
