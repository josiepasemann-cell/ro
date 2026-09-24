--[[
	Abyssara – Deep Tide Tycoon
	Skript: WorldSetup (Server-Startskript)
	Zuständigkeit:
		Richtet beim Serverstart die globale Unterwasser-Weltatmosphäre ein
		(Lighting/Atmosphere/ColorCorrection/Bloom/Fog) und sorgt für
		ambiente Lebendigkeit am Spawn-Ort (aufsteigende Luftblasen,
		schwebendes Plankton, sanftes Licht-Flackern), damit Spieler beim
		Joinen an einem stimmungsvollen, glaubwürdig "unter Wasser"
		wirkenden Ort landen (siehe GDD Abschnitt 4, Hub-Welt "Tidal
		Market").

	WIE DER HUB INS LIVE-SPIEL KOMMT (pragmatische, dokumentierte Entscheidung,
	analog zum bestehenden Muster in AssetTemplateSetup.lua – nur gelesen,
	nicht verändert):
		Die Hub-Geometrie selbst (assets/models/hub/TidalMarketHub.lua) ist
		bewusst ein EINMALIGES Studio-Buildscript, kein Laufzeit-Skript:
		CSG-Operationen (UnionAsync) sind teuer und sollen nicht bei jedem
		Serverstart erneut laufen, und das Skript soll wie alle anderen
		Buildscripts in assets/models/ ausschließlich reine Geometrie
		erzeugen (siehe assets/models/README.md).
		Workflow:
			1) Ein Entwickler führt TidalMarketHub.lua einmalig in der
			   Studio-Command-Bar aus (siehe Kopfkommentar dort). Das Modell
			   entsteht unter Workspace.Assets.Hub.TidalMarketHub.
			2) Der Entwickler speichert das Place (File -> Save / Publish).
			   Ab diesem Zeitpunkt ist der Hub fester Bestandteil des
			   veröffentlichten Places, genau wie bei den Terrain-Chunks und
			   der HabitatPlotBase-Vorlage.
			3) Dieses Skript (WorldSetup) läuft bei JEDEM Serverstart (auch
			   live) und PRÜFT NUR, ob Workspace.Assets.Hub.TidalMarketHub
			   existiert. Es baut den Hub NICHT nach - das würde erneute,
			   unnötig teure CSG-Berechnungen bei jedem Serverstart bedeuten
			   und würde dem dokumentierten "einmalig in Studio"-Workflow
			   widersprechen (siehe identische Design-Entscheidung im
			   Kopfkommentar von AssetTemplateSetup.lua, Abschnitt
			   "ALTERNATIVE, die bewusst NICHT gewählt wurde").
			4) Fehlt der Hub (Buildscript nie ausgeführt/gespeichert), wird
			   klar per warn() gemeldet UND ein minimaler Fallback-Spawn
			   erzeugt (siehe ensureFallbackSpawn unten), damit Spieler
			   trotzdem sicher joinen können statt ins Leere zu fallen.

		Dieses Skript selbst erzeugt NUR laufzeit-generierte, günstige
		Instanzen (Lighting-Einstellungen, ParticleEmitter, PointLights) -
		keine CSG-Geometrie, keine Parts mit hoher Bauzeit. Es ist idempotent
		(räumt vorher erzeugte AmbientFX-Instanzen auf, bevor es neue baut),
		daher unproblematisch bei Server-Neustarts oder Studio-Re-Runs.

	Rojo-Einhängepunkt:
		src/server/WorldSetup.server.lua -> ServerScriptService.WorldSetup
		(Script, kein ModuleScript - läuft automatisch beim Serverstart.)
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- // Konfiguration ---------------------------------------------------------
local AMBIENT_FX_TAG = "AmbientFX" -- CollectionService-Tag, siehe Client-Hook-Vorschlag unten
local FLICKER_AMPLITUDE = 0.06 -- sehr sanft, keine Ablenkung/Epilepsie-Risiko
local FLICKER_SPEED = 0.35
-- // ------------------------------------------------------------------------

-- // 1) Lighting-Grundstimmung: dunkle Tiefsee, aber lesbar --------------
Lighting.ClockTime = 0 -- Mitternacht: kein störendes Sonnenlicht/SunRays-Bedarf
Lighting.GeographicLatitude = 0
Lighting.Brightness = 1.4
Lighting.Ambient = Color3.fromRGB(18, 28, 36)
Lighting.OutdoorAmbient = Color3.fromRGB(14, 22, 30)
Lighting.ColorShift_Top = Color3.fromRGB(10, 20, 30)
Lighting.ColorShift_Bottom = Color3.fromRGB(5, 10, 16)
Lighting.EnvironmentDiffuseScale = 0.4
Lighting.EnvironmentSpecularScale = 0.3
Lighting.GlobalShadows = true -- weiche Gesamtschatten; einzelne PointLights laufen mit Shadows=false (Performance, siehe Hub-/Terrain-Buildscripts)
Lighting.ShadowSoftness = 0.4

-- Tiefsee-Nebel: verkürzt Sichtweite plausibel UND spart Rendering-Kosten
-- (entfernte Geometrie wird ohnehin verdeckt) - Werte moderat für Handy-FPS.
Lighting.FogColor = Color3.fromRGB(5, 12, 18)
Lighting.FogStart = 15
Lighting.FogEnd = 150

-- Baseline-Snapshot für das Live-Event-System (LiveEventService,
-- docs/content-update-1.md Abschnitt 1.3): Attribute statt eines zweiten
-- hartcodierten Zahlensatzes in einem anderen Modul, damit die "Normal-
-- Stimmung", zu der zwischen/ohne Events zurückgetweent wird, IMMER exakt
-- den obigen Werten entspricht, selbst wenn sie hier künftig geändert
-- werden. LiveEventService liest diese Attribute defensiv mit Fallback.
Lighting:SetAttribute("BaselineAmbient", Lighting.Ambient)
Lighting:SetAttribute("BaselineOutdoorAmbient", Lighting.OutdoorAmbient)
Lighting:SetAttribute("BaselineFogColor", Lighting.FogColor)
Lighting:SetAttribute("BaselineFogEnd", Lighting.FogEnd)

-- // 2) Post-Processing: Neon-Biolumineszenz zum Leuchten bringen --------
local function getOrCreate(className, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local atmosphere = getOrCreate("Atmosphere", "DeepTideAtmosphere", Lighting)
atmosphere.Density = 0.45
atmosphere.Offset = 0.25
atmosphere.Color = Color3.fromRGB(20, 60, 75)
atmosphere.Decay = Color3.fromRGB(5, 15, 25)
atmosphere.Glare = 0.15
atmosphere.Haze = 3.2

local colorCorrection = getOrCreate("ColorCorrectionEffect", "DeepTideColorCorrection", Lighting)
colorCorrection.Enabled = true
colorCorrection.Brightness = 0
colorCorrection.Contrast = 0.15
colorCorrection.Saturation = 0.4 -- kräftigere Neon-Farben (Wunsch: grelle Biolumineszenz)
colorCorrection.TintColor = Color3.fromRGB(225, 240, 255) -- leichter Blaustich

local bloom = getOrCreate("BloomEffect", "DeepTideBloom", Lighting)
bloom.Enabled = true
bloom.Intensity = 0.85
bloom.Size = 24
bloom.Threshold = 0.9 -- greift primär auf Neon-Material (hohe Helligkeit)

-- Sonnenstrahlen explizit aus (Unterwasser-Setting, laut Auftrag "SunRays aus")
local sunRays = getOrCreate("SunRaysEffect", "DeepTideSunRays", Lighting)
sunRays.Enabled = false

-- DepthOfField bewusst NICHT gesetzt: zusätzliche GPU-Kosten auf Mobile ohne
-- klaren Stimmungsgewinn gegenüber Fog+Atmosphere - siehe README "hub"-
-- Abschnitt, Performance-Hinweise.

print("[Abyssara] WorldSetup: Lighting/Atmosphere/ColorCorrection/Bloom für Tiefsee-Stimmung gesetzt.")

-- // 3) Hub-Vorhandensein prüfen (analog AssetTemplateSetup-Muster) ------
local function findHubModel(): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	local hubModel = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	if hubModel and hubModel:IsA("Model") then
		return hubModel
	end
	return nil
end

local function ensureFallbackSpawn()
	local fallbackFolder = Workspace:FindFirstChild("WorldSetupFallback")
	if fallbackFolder then
		fallbackFolder:Destroy()
	end
	fallbackFolder = Instance.new("Folder")
	fallbackFolder.Name = "WorldSetupFallback"
	fallbackFolder.Parent = Workspace

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "FallbackSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 5, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Material = Enum.Material.Basalt
	spawn.Color = Color3.fromRGB(24, 26, 34)
	spawn.Parent = fallbackFolder

	warn(
		"[WorldSetup] Workspace.Assets.Hub.TidalMarketHub fehlt - bitte "
			.. "assets/models/hub/TidalMarketHub.lua einmal in Studio ausführen "
			.. "und das Place speichern (siehe Kopfkommentar dort). Ein "
			.. "minimaler Notfall-Spawn wurde erzeugt, damit Spieler trotzdem "
			.. "sicher joinen können."
	)
end

local hubModel = findHubModel()
local hubCenter = hubModel and hubModel.PrimaryPart and hubModel.PrimaryPart.Position or nil

if not hubModel then
	ensureFallbackSpawn()
else
	print("[Abyssara] WorldSetup: TidalMarketHub gefunden bei " .. tostring(hubCenter) .. ".")
end

-- // 4) Ambiente Lebendigkeit: Blasen, Plankton, sanftes Flackern --------
-- Nur am Hub verankert (das ist der garantierte Join-Ort aller Spieler,
-- siehe Auftrag "Spieler landen beim Joinen an einem lebendigen Ort").
-- Zonen-Terrain-Chunks und Spieler-Plots liegen außerhalb des Verantwor-
-- tungsbereichs dieses Skripts (siehe Dateibesitz) und können bei Bedarf
-- dasselbe Muster (AMBIENT_FX_TAG-Emitter an Attachments) übernehmen.
local function clearPreviousAmbientFx()
	local previous = Workspace:FindFirstChild("AmbientFX")
	if previous then
		previous:Destroy()
	end
end

local function newAmbientAnchor(name: string, position: Vector3, parent: Instance): Attachment
	local anchor = Instance.new("Part")
	anchor.Name = name .. "Anchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = parent

	local attachment = Instance.new("Attachment")
	attachment.Name = "EmitPoint"
	attachment.Parent = anchor
	return attachment
end

local function addBubbleEmitter(attachment: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RisingBubbles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- Platzhalter-Textur (Standard-Roblox-Asset)
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Acceleration = Vector3.new(0, 6, 0) -- steigt auf
	emitter.Rate = 5 -- moderat, siehe Handy-Performance-Hinweis in README
	emitter.LightEmission = 0.6
	emitter.Parent = attachment
	CollectionService:AddTag(emitter, AMBIENT_FX_TAG)
	return emitter
end

local function addPlanktonEmitter(attachment: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DriftingPlankton"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 255, 210)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 140, 255)),
	})
	emitter.Size = NumberSequence.new(0.08)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(6, 10)
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.SpreadAngle = Vector2.new(180, 180) -- diffuse Drift in alle Richtungen
	emitter.Acceleration = Vector3.new(0, 0.2, 0)
	emitter.Rate = 8
	emitter.LightEmission = 0.4
	emitter.Parent = attachment
	CollectionService:AddTag(emitter, AMBIENT_FX_TAG)
	return emitter
end

clearPreviousAmbientFx()

local ambientFolder = Instance.new("Folder")
ambientFolder.Name = "AmbientFX"
ambientFolder.Parent = Workspace

if hubCenter then
	-- 4 Blasen-Quellen locker um die Landmark verteilt (dichte Wirkung ohne
	-- Emitter-Übermaß - siehe Deko-Dichte-Rhythmus-Prinzip aus den
	-- Terrain-Design-Notizen, hier auf Partikel übertragen).
	local bubbleOffsets = {
		Vector3.new(8, 2, 8),
		Vector3.new(-8, 2, 8),
		Vector3.new(8, 2, -8),
		Vector3.new(-8, 2, -8),
	}
	for i, offset in ipairs(bubbleOffsets) do
		local attachment = newAmbientAnchor("Bubbles" .. i, hubCenter + offset, ambientFolder)
		addBubbleEmitter(attachment)
	end

	-- 2 großflächige Plankton-Drift-Quellen (hoch über dem Platz, damit die
	-- Partikel über die gesamte Marktfläche hinweg sichtbar treiben).
	local planktonOffsets = { Vector3.new(0, 22, 0), Vector3.new(30, 16, -20) }
	for i, offset in ipairs(planktonOffsets) do
		local attachment = newAmbientAnchor("Plankton" .. i, hubCenter + offset, ambientFolder)
		addPlanktonEmitter(attachment)
	end

	-- Sanftes Licht-Flackern: leichtes Sinus-Rauschen auf ColorCorrection.
	-- Bewusst global statt pro Licht (billiger, wirkt trotzdem "lebendig",
	-- ohne Dutzende Lights einzeln ansteuern zu müssen).
	local flickerConnection
	local elapsed = 0
	flickerConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local noise = math.noise(elapsed * FLICKER_SPEED, 0, 0) * FLICKER_AMPLITUDE
		colorCorrection.Brightness = noise * 0.5
	end)
	CollectionService:AddTag(ambientFolder, AMBIENT_FX_TAG)
end

print("[Abyssara] WorldSetup: Ambient-FX (Blasen/Plankton/Flackern) am Hub aktiv.")

--[[
	CLIENT-HOOK-VORSCHLAG (nicht implementiert, siehe Auftrag - Grafik-
	qualität/Spieleranzahl kann der Server nicht zuverlässig einschätzen):

	Alle hier erzeugten Ambient-FX-Instanzen (ParticleEmitter UND der
	Attachment-Folder "AmbientFX" selbst) sind bereits mit dem
	CollectionService-Tag "AmbientFX" versehen. Ein künftiges
	LocalScript (z. B. unter StarterPlayerScripts, vom UI-/Client-Agenten
	zu bauen) könnte darauf so aufsetzen, OHNE dieses Server-Skript
	anzufassen:

		local CollectionService = game:GetService("CollectionService")
		local UserGameSettings = UserSettings():GetService("UserGameSettings")

		local function applyQuality()
			local quality = UserGameSettings.SavedQualityLevel.Value -- 0-10, 0 = Automatisch
			local playerCount = #game.Players:GetPlayers()
			local scale = 1
			if quality > 0 and quality <= 3 or playerCount > 20 then
				scale = 0.3 -- niedrige Grafikqualität ODER viele Spieler -> Partikel drosseln
			elseif quality > 0 and quality <= 6 or playerCount > 10 then
				scale = 0.6
			end
			for _, instance in CollectionService:GetTagged("AmbientFX") do
				if instance:IsA("ParticleEmitter") then
					instance.Rate = instance:GetAttribute("BaseRate") or instance.Rate
					instance.Rate *= scale
				end
			end
		end

	Empfehlung: `BaseRate` als Attribut auf jedem Emitter spiegeln (bereits
	vorbereitbar durch `emitter:SetAttribute("BaseRate", emitter.Rate)` in
	diesem Skript, siehe unten), damit der Client verlustfrei herunter-
	und wieder hochskalieren kann, statt kumulativ zu multiplizieren.
]]
for _, emitter in ipairs(ambientFolder:GetDescendants()) do
	if emitter:IsA("ParticleEmitter") then
		emitter:SetAttribute("BaseRate", emitter.Rate)
	end
end
